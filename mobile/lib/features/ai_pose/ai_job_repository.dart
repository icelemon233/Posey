import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';
import 'package:posey/features/ai_pose/native_background_ai.dart';

class AiJobRepository extends ChangeNotifier {
  AiJobRepository(
    this.storage,
    this.service, {
    this.native = const NativeBackgroundAi(),
  });
  final PoseyStorage storage;
  final AiPoseService service;
  final NativeBackgroundAi native;
  List<AiJob> _jobs = [];
  List<AiJob> get jobs =>
      List.unmodifiable(_jobs.map((job) => AiJob.fromJson(job.toJson())));
  String? syncError;
  bool _disposed = false, _running = false, _nativeSyncing = false;
  Timer? _poll;
  int _enqueuing = 0;
  int _nativeRevision = 0;
  final _prepared = <String, PreparedAiRequest>{};
  Future<void> _persistTail = Future.value();
  int get activeJobs => _jobs.where((job) => job.active).length + _enqueuing;
  bool get backgroundSupported => native.supported;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final raw = jsonDecode(await storage.read('jobs') ?? '[]');
    if (raw is! List) throw const FormatException('AI 任务记录格式无效');
    _jobs = raw.map((value) => AiJob.fromJson(objectOf(value))).toList();
    if (_disposed) return;
    _poll?.cancel();
    if (native.supported) {
      await syncNative();
      if (!_disposed) {
        _poll = Timer.periodic(
          const Duration(seconds: 3),
          (_) => unawaited(syncNative()),
        );
      }
    } else {
      for (final job in _jobs.where((job) => job.active)) {
        job.state = AiJobState.failed;
        job.message = '上次任务被中断，确认后可以重试。';
      }
    }
    await _persistJobs();
    _notify();
  }

  Future<void> enqueue(
    PoseTemplate target,
    Uint8List image, {
    required bool consent,
    required AiConfiguration configuration,
    required AiPreferences preferences,
  }) async {
    if (_disposed) throw StateError('任务列表已关闭');
    if (!consent) throw StateError('请先确认将这张照片和姿势参考发送给 AI 服务');
    configuration.validate();
    if (activeJobs >= maxActiveJobs) {
      throw StateError('最多同时保留 3 个进行中的任务，请等待或取消一个任务');
    }
    _enqueuing++;
    _notify();
    bool reserved = true;
    String? source;
    try {
      // Freeze model, credentials and preferences before this job enters the queue.
      final prepared = await service.prepare(
        configuration,
        preferences,
        target,
        image,
      );
      if (_disposed) throw StateError('任务列表已关闭');
      source = await storage.saveBytes(
        '${const Uuid().v4()}-source.jpg',
        image,
      );
      if (_disposed) throw StateError('任务列表已关闭');
      if (native.supported) {
        final id = await native.start(prepared);
        final index = _jobs.indexWhere((job) => job.id == id);
        final synced = index < 0 ? null : _jobs[index];
        final job = AiJob(
          id: id,
          targetId: target.id,
          targetTitle: target.title,
          sourcePath: source,
          createdAt: synced?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
          state: synced?.state ?? AiJobState.queued,
          resultPath: synced?.resultPath,
          completedAt: synced?.completedAt,
          message: synced?.message,
        );
        if (index < 0) {
          _jobs.insert(0, job);
        } else {
          _jobs[index] = job;
        }
        _enqueuing--;
        reserved = false;
        await _persistJobs();
        await syncNative();
      } else {
        final id = const Uuid().v4();
        _prepared[id] = prepared;
        _jobs.insert(
          0,
          AiJob(
            id: id,
            targetId: target.id,
            targetTitle: target.title,
            sourcePath: source,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        _enqueuing--;
        reserved = false;
        await _persistJobs();
        unawaited(_process());
      }
    } catch (_) {
      if (source != null && !_jobs.any((job) => job.sourcePath == source)) {
        await storage.deleteOwnedFile(source);
      }
      rethrow;
    } finally {
      if (reserved) _enqueuing--;
      _notify();
    }
    _notify();
  }

  Future<void> _process() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (!_disposed) {
        final pending = _jobs
            .where((job) => job.state == AiJobState.queued)
            .toList();
        if (pending.isEmpty) break;
        final job = pending.last;
        job.state = AiJobState.generating;
        await _persistJobs();
        _notify();
        try {
          final prepared = _prepared.remove(job.id);
          if (prepared == null) throw StateError('任务已中断，请确认后重试');
          if (_disposed || job.state == AiJobState.cancelled) continue;
          final bytes = await service.generate(job.id, prepared);
          if (_disposed || job.state == AiJobState.cancelled) continue;
          final path = await storage.saveBytes('${job.id}-result.jpg', bytes);
          if (_disposed ||
              job.state == AiJobState.cancelled ||
              !_jobs.contains(job)) {
            await storage.deleteOwnedFile(path);
            continue;
          }
          job.resultPath = path;
          job.completedAt = DateTime.now().millisecondsSinceEpoch;
          job.state = AiJobState.completed;
        } catch (failure) {
          if (_disposed) continue;
          if (job.state != AiJobState.cancelled) {
            job.state = AiJobState.failed;
            job.message = failure.toString().replaceFirst(
              RegExp(r'^(Bad state: |FormatException: )'),
              '',
            );
          }
        }
        await _persistJobs();
        _notify();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _persistJobs() =>
      _persistTail = _persistTail.catchError((Object _) {}).then((_) async {
        final retained = retainRecentJobs(_jobs);
        for (final job in _jobs.where((job) => !retained.contains(job))) {
          await storage.deleteOwnedFile(job.sourcePath);
          if (job.resultPath != null) {
            await storage.deleteOwnedFile(job.resultPath!);
          }
        }
        _jobs = retained;
        await storage.write('jobs', encodeJobs(_jobs));
      });

  Future<void> cancel(String id) async {
    final matches = _jobs.where((job) => job.id == id);
    if (matches.isEmpty) return;
    _nativeRevision++;
    matches.first.state = AiJobState.cancelled;
    _prepared.remove(id);
    service.cancel(id);
    if (native.supported) await native.cancel(id);
    await _persistJobs();
    _notify();
  }

  Future<void> clear(String id) async {
    final matches = _jobs.where((job) => job.id == id).toList();
    if (matches.isEmpty) return;
    _nativeRevision++;
    final job = matches.first;
    if (job.active) await cancel(id);
    if (native.supported) await native.clear(id);
    _jobs.removeWhere((item) => item.id == id);
    await storage.deleteOwnedFile(job.sourcePath);
    if (job.resultPath != null) await storage.deleteOwnedFile(job.resultPath!);
    await _persistJobs();
    _notify();
  }

  Future<void> syncNative() async {
    if (!native.supported || _nativeSyncing || _disposed) return;
    _nativeSyncing = true;
    try {
      final revision = _nativeRevision;
      final records = await native.jobs(
        knownResults: _jobs
            .where((job) => job.resultPath != null)
            .map((job) => job.id)
            .toList(),
      );
      if (_disposed || revision != _nativeRevision) return;
      for (final record in records) {
        final id = record['id'] as String;
        final matching = _jobs.where((job) => job.id == id).toList();
        AiJob job;
        if (matching.isNotEmpty) {
          job = matching.first;
        } else {
          final title = record['targetTitle'] as String? ?? '目标姿势';
          job = AiJob(
            id: id,
            targetId: '',
            targetTitle: title,
            sourcePath: '',
            createdAt: integerOf(record['createdAt']),
          );
          _jobs.add(job);
        }
        if (_disposed || job.state == AiJobState.cancelled) continue;
        final nextState = AiJobState.values.firstWhere(
          (state) => state.name == record['state'],
          orElse: () => AiJobState.failed,
        );
        final message = record['message'] as String?;
        final completedAt = record['completedAt'] is num
            ? integerOf(record['completedAt'])
            : null;
        var resultPath = job.resultPath;
        if (nextState == AiJobState.completed &&
            resultPath == null &&
            record['image'] is String) {
          final data = (record['image'] as String).split(',').last;
          resultPath = await storage.saveBytes(
            '$id-result.jpg',
            base64Decode(data),
          );
          if (_disposed ||
              revision != _nativeRevision ||
              !_jobs.contains(job)) {
            await storage.deleteOwnedFile(resultPath);
            return;
          }
        }
        if (nextState == AiJobState.completed && resultPath == null) {
          throw const FormatException('后台任务未返回可用图片');
        }
        job.state = nextState;
        job.message = message;
        job.completedAt = completedAt;
        job.resultPath = resultPath;
      }
      _jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _persistJobs();
      syncError = null;
      _notify();
    } catch (_) {
      syncError = '后台任务暂时无法同步，可以稍后重试。';
      _notify();
    } finally {
      _nativeSyncing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    if (!native.supported) {
      for (final job in _jobs.where((job) => job.active)) {
        service.cancel(job.id);
      }
    }
    super.dispose();
  }
}
