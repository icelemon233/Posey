import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services.dart';

class PoseyController extends ChangeNotifier {
  PoseyController(
    this.storage,
    this.service, {
    this.native = const NativeBackgroundAi(),
  });
  final PoseyStorage storage;
  final AiPoseService service;
  final NativeBackgroundAi native;
  List<PoseTemplate> templates = [];
  Set<String> favorites = {};
  List<AiJob> jobs = [];
  AiConfiguration configuration = const AiConfiguration();
  AiPreferences preferences = const AiPreferences();
  bool loading = true;
  String? error;
  String theme = 'sunny-cream';
  bool shuffleFavorites = false;
  bool _disposed = false, _running = false, _nativeSyncing = false;
  Timer? _poll;
  int _enqueuing = 0;
  final _prepared = <String, PreparedAiRequest>{};
  Future<void> _persistTail = Future.value();
  int get activeJobs => jobs.where((job) => job.active).length + _enqueuing;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final raw = jsonDecode(
        await rootBundle.loadString('assets/data/poses.json'),
      ) as List;
      templates = raw
          .map((value) => PoseTemplate.fromJson(objectOf(value)))
          .toList();
      favorites = stringsOf(jsonDecode(await storage.read('favorites') ?? '[]'))
          .toSet();
      theme = await storage.read('theme') ?? 'sunny-cream';
      shuffleFavorites = await storage.read('shuffle-favorites') == 'true';
      preferences = AiPreferences.fromJson(
        objectOf(jsonDecode(await storage.read('ai-preferences') ?? '{}')),
      );
      final metadata = objectOf(
        jsonDecode(await storage.read('ai-config') ?? '{}'),
      );
      configuration = AiConfiguration(
        key: await storage.readApiKey() ?? '',
        endpoint:
            metadata['endpoint'] as String? ??
            'https://ark.cn-beijing.volces.com/api/v3',
        model: metadata['model'] as String? ?? 'doubao-seedream-5-0-pro-260628',
      );
      jobs = (jsonDecode(await storage.read('jobs') ?? '[]') as List)
          .map((value) => AiJob.fromJson(objectOf(value)))
          .toList();
      if (native.supported) {
        await syncNative();
        _poll = Timer.periodic(
          const Duration(seconds: 3),
          (_) => unawaited(syncNative()),
        );
      } else {
        for (final job in jobs) {
          if (job.active) {
            job.state = AiJobState.failed;
            job.message = '上次任务被中断，确认后可以重试。';
          }
        }
      }
      await _persistJobs();
    } catch (failure) {
      error = '加载失败，可以重试：${failure.toString()}';
    }
    loading = false;
    _notify();
  }

  Future<void> toggleFavorite(String id) async {
    if (favorites.contains(id)) {
      favorites.remove(id);
    } else {
      favorites.add(id);
    }
    _notify();
    await storage.write('favorites', jsonEncode(favorites.toList()));
  }

  Future<void> setTheme(String value) async {
    theme = value;
    _notify();
    await storage.write('theme', value);
  }

  Future<void> setShuffleFavorites(bool value) async {
    shuffleFavorites = value;
    _notify();
    await storage.write('shuffle-favorites', '$value');
  }

  Future<void> saveConfiguration(
    AiConfiguration value,
    AiPreferences next,
  ) async {
    if (value.key.trim().isNotEmpty) value.validate();
    await storage.writeApiKey(value.normalizedKey);
    await storage.write('ai-config', jsonEncode(value.metadata()));
    await storage.write('ai-preferences', jsonEncode(next.toJson()));
    configuration = value;
    preferences = next;
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> enqueue(
    PoseTemplate target,
    Uint8List image, {
    required bool consent,
  }) async {
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
      source = await storage.saveBytes(
        '${const Uuid().v4()}-source.jpg',
        image,
      );
      if (native.supported) {
        final id = await native.start(prepared);
        jobs.insert(
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
        await syncNative();
      } else {
        final id = const Uuid().v4();
        _prepared[id] = prepared;
        jobs.insert(
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
      if (source != null && !jobs.any((job) => job.sourcePath == source)) {
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
        final pending = jobs
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
          if (job.state == AiJobState.cancelled) continue;
          final bytes = await service.generate(job.id, prepared);
          if (job.state == AiJobState.cancelled) continue;
          final path = await storage.saveBytes('${job.id}-result.jpg', bytes);
          if (job.state == AiJobState.cancelled || !jobs.contains(job)) {
            await storage.deleteOwnedFile(path);
            continue;
          }
          job.resultPath = path;
          job.completedAt = DateTime.now().millisecondsSinceEpoch;
          job.state = AiJobState.completed;
        } catch (failure) {
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
        final retained = retainRecentJobs(jobs);
        for (final job in jobs.where((job) => !retained.contains(job))) {
          await storage.deleteOwnedFile(job.sourcePath);
          if (job.resultPath != null) {
            await storage.deleteOwnedFile(job.resultPath!);
          }
        }
        jobs = retained;
        await storage.write('jobs', encodeJobs(jobs));
      });

  Future<void> cancel(String id) async {
    final matches = jobs.where((job) => job.id == id);
    if (matches.isEmpty) return;
    matches.first.state = AiJobState.cancelled;
    _prepared.remove(id);
    service.cancel(id);
    if (native.supported) await native.cancel(id);
    await _persistJobs();
    _notify();
  }

  Future<void> clear(String id) async {
    final matches = jobs.where((job) => job.id == id).toList();
    if (matches.isEmpty) return;
    final job = matches.first;
    if (job.active) await cancel(id);
    if (native.supported) await native.clear(id);
    jobs.removeWhere((item) => item.id == id);
    await storage.deleteOwnedFile(job.sourcePath);
    if (job.resultPath != null) await storage.deleteOwnedFile(job.resultPath!);
    await _persistJobs();
    _notify();
  }

  Future<void> retry(AiJob job) async {
    if (job.active) return;
    final target = templates.firstWhere((target) => target.id == job.targetId);
    await enqueue(
      target,
      await File(job.sourcePath).readAsBytes(),
      consent: true,
    );
  }

  Future<void> syncNative() async {
    if (!native.supported || _nativeSyncing || _disposed) return;
    _nativeSyncing = true;
    try {
      for (final record in await native.jobs(
        knownResults: jobs
            .where((job) => job.resultPath != null)
            .map((job) => job.id)
            .toList(),
      )) {
        final id = record['id'] as String;
        final matching = jobs.where((job) => job.id == id).toList();
        AiJob job;
        if (matching.isNotEmpty) {
          job = matching.first;
        } else {
          final title = record['targetTitle'] as String? ?? '目标姿势';
          final targets = templates.where((target) => target.title == title);
          job = AiJob(
            id: id,
            targetId: targets.isEmpty ? '' : targets.first.id,
            targetTitle: title,
            sourcePath: '',
            createdAt: integerOf(record['createdAt']),
          );
          jobs.add(job);
        }
        if (job.state == AiJobState.cancelled) continue;
        job.state = AiJobState.values.firstWhere(
          (state) => state.name == record['state'],
          orElse: () => AiJobState.failed,
        );
        job.message = record['message'] as String?;
        job.completedAt = record['completedAt'] is num
            ? integerOf(record['completedAt'])
            : null;
        if (job.state == AiJobState.completed &&
            job.resultPath == null &&
            record['image'] is String) {
          final data = (record['image'] as String).split(',').last;
          job.resultPath = await storage.saveBytes(
            '$id-result.jpg',
            base64Decode(data),
          );
        }
      }
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _persistJobs();
      _notify();
    } catch (_) {
      /* A task can continue in iOS URLSession while the Flutter view is inactive. */
    } finally {
      _nativeSyncing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    if (!native.supported) {
      for (final job in jobs.where((job) => job.active)) {
        service.cancel(job.id);
      }
    }
    super.dispose();
  }
}
