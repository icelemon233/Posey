import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/core/storage/stored_media_paths.dart';
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
    this.preserveResult,
  });
  final PoseyStorage storage;
  final AiPoseService service;
  final NativeBackgroundAi native;
  final Future<String> Function(AiJob)? preserveResult;
  final _archiving = <String>{};
  List<AiJob> _jobs = [];
  List<AiJob> get jobs =>
      List.unmodifiable(_jobs.map((job) => AiJob.fromJson(job.toJson())));
  String? syncError;
  String? loadError, persistenceError;
  bool _disposed = false, _running = false, _nativeSyncing = false;
  Timer? _poll;
  int _enqueuing = 0;
  int _nativeRevision = 0;
  final _prepared = <String, PreparedAiRequest>{};
  final _retryReservations = <String>{};
  final _startingNative = <String>{};
  final _resultBytes = <String, Uint8List>{};
  final _resultUrls = <String, Uri>{};
  final _retryingResults = <String>{};
  final _savingResults = <String, Future<bool>>{};
  Future<void>? _nativeSyncFuture;
  Future<void> _persistTail = Future.value();
  int get activeJobs => _jobs.where((job) => job.active).length + _enqueuing;
  bool get backgroundSupported => native.supported;
  bool get hasPendingIO =>
      _running ||
      _nativeSyncing ||
      _enqueuing > 0 ||
      _archiving.isNotEmpty ||
      _retryingResults.isNotEmpty ||
      _savingResults.isNotEmpty;
  bool isRetryingResult(String id) =>
      _retryingResults.contains(id) || _savingResults.containsKey(id);
  bool isRetrying(String id) =>
      _retryReservations.contains(id) ||
      _jobs.any((job) => job.retryOf == id && job.active);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _nativeRevision++;
    _poll?.cancel();
    _poll = null;
    try {
      final raw = jsonDecode(await storage.read('jobs') ?? '[]');
      if (raw is! List) throw const FormatException('AI 任务记录格式无效');
      final paths = StoredMediaPaths(await storage.mediaFiles());
      final restored = raw
          .map((value) => AiJob.fromJson(paths.job(objectOf(value))))
          .toList();
      if (restored.map((job) => job.id).toSet().length != restored.length) {
        throw const FormatException('AI 任务记录包含重复编号');
      }
      if (_disposed) return;
      _jobs = restored;
      final files = {
        for (final file in await storage.mediaFiles())
          file.path.replaceAll('\\', '/').split('/').last: file.path,
      };
      for (final job in _jobs) {
        final result = files['${job.id}-result.jpg'];
        if (result != null &&
            (job.active || job.state == AiJobState.awaitingResult)) {
          job.resultPath = result;
          job.state = AiJobState.completed;
          job.pendingResult = null;
          job.completedAt ??= DateTime.now().millisecondsSinceEpoch;
        }
        if (!native.supported && job.state == AiJobState.awaitingResult) {
          final raw = await storage.readSecret('result-url-${job.id}');
          if (job.pendingResult == PendingAiResult.download && raw != null) {
            _resultUrls[job.id] = Uri.parse(raw);
          } else if (!_resultBytes.containsKey(job.id)) {
            job.state = AiJobState.failed;
            job.pendingResult = null;
            job.message = '上次成片未能保存。服务可能已处理，请先查看服务记录，再决定是否重新生成。';
          }
        }
      }
      if (native.supported) {
        await refreshNative();
      } else {
        for (final job in _jobs.where((job) => job.active)) {
          job.state = AiJobState.failed;
          job.message = '上次任务被中断，确认后可以重试。';
        }
      }
      for (final job in _jobs.where(
        (job) => job.state == AiJobState.completed,
      )) {
        await _archiveResult(job);
      }
      await _persistJobs();
      loadError = null;
      if (native.supported && !_disposed) {
        _poll = Timer.periodic(
          const Duration(seconds: 3),
          (_) => unawaited(syncNative()),
        );
      }
    } catch (_) {
      loadError = 'AI 任务记录暂时无法读取。可以重新加载，或备份后重置任务记录。';
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> resetUnreadableHistory() async {
    if (loadError == null) return;
    final original = await storage.read('jobs');
    if (original != null) {
      await storage.write('jobs-recovery-${const Uuid().v4()}', original);
    }
    await storage.write('jobs', '[]');
    await load();
  }

  Future<void> retryPersistence() async {
    try {
      await _persistJobs();
    } finally {
      _notify();
    }
  }

  Future<void> enqueue(
    PoseTemplate target,
    Uint8List image, {
    required bool consent,
    required AiConfiguration configuration,
    required AiPreferences preferences,
    String? retryOf,
    String? sourceWorkId,
    String? frozenPrompt,
  }) async {
    if (_disposed) throw StateError('任务列表已关闭');
    if (loadError != null) throw StateError('请先在 AI Pose 页面恢复任务记录，再开始生成。');
    if (!consent) throw StateError('请先确认将这张照片和姿势参考发送给 AI 服务');
    configuration.validate();
    if (_jobs.any(
      (job) =>
          job.archiveError != null || job.state == AiJobState.awaitingResult,
    )) {
      throw StateError('请先在任务页将未留存的成片保存到作品，再开始新的生成。');
    }
    if (activeJobs >= maxActiveJobs) {
      throw StateError('最多同时保留 3 个进行中的任务，请等待或取消一个任务');
    }
    if (retryOf != null && isRetrying(retryOf)) return;
    if (retryOf != null) _retryReservations.add(retryOf);
    _enqueuing++;
    _notify();
    bool reserved = true;
    String? source;
    String? startingNativeId;
    try {
      // Freeze model, credentials and preferences before this job enters the queue.
      var prepared = await service.prepare(
        configuration,
        preferences,
        target,
        image,
      );
      if (frozenPrompt != null) {
        prepared = PreparedAiRequest(prepared.configuration, {
          ...prepared.body,
          'prompt': frozenPrompt,
        }, prepared.title);
      }
      if (_disposed) throw StateError('任务列表已关闭');
      source = await storage.saveBytes(
        '${const Uuid().v4()}-source.jpg',
        image,
      );
      if (_disposed) throw StateError('任务列表已关闭');
      final id = const Uuid().v4();
      final job = AiJob(
        id: id,
        targetId: target.id,
        targetTitle: target.title,
        sourcePath: source,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        retryOf: retryOf,
        sourceWorkId: sourceWorkId,
        targetSnapshot: target.raw,
        requestMetadata: {
          ...AiRequestOptions(configuration, preferences).metadata(),
          'prompt': prepared.body['prompt'],
        },
      );
      if (native.supported) {
        startingNativeId = id;
        _startingNative.add(id);
        _nativeRevision++;
      }
      // A rejected local commit must never leave runnable or native work behind.
      await _persistJobs(adding: job);
      _enqueuing--;
      reserved = false;
      if (_disposed ||
          job.state == AiJobState.cancelled ||
          !_jobs.contains(job)) {
        job.state = AiJobState.cancelled;
        await _tryPersistJobs();
        throw StateError(_disposed ? '任务列表已关闭' : '任务已取消');
      }
      if (native.supported) {
        try {
          final accepted = await native.start(
            prepared.withRecoveryMetadata(job.toJson()),
            jobId: id,
          );
          if (accepted != id) throw const FormatException('后台任务编号不一致');
          _nativeRevision++;
        } catch (failure) {
          job.state = AiJobState.failed;
          job.message = _message(failure);
          await _tryPersistJobs();
          rethrow;
        }
        if (!_nativeSyncing) await syncNative();
      } else {
        _prepared[id] = prepared;
        unawaited(_process());
      }
    } catch (_) {
      if (source != null && !_jobs.any((job) => job.sourcePath == source)) {
        await storage.deleteOwnedFile(source);
      }
      rethrow;
    } finally {
      if (reserved) _enqueuing--;
      if (retryOf != null) _retryReservations.remove(retryOf);
      if (startingNativeId != null) _startingNative.remove(startingNativeId);
      _notify();
    }
    _notify();
  }

  Future<void> _process() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (!_disposed) {
        if (_jobs.any((job) => job.state == AiJobState.awaitingResult)) break;
        final pending = _jobs
            .where(
              (job) =>
                  job.state == AiJobState.queued &&
                  _prepared.containsKey(job.id),
            )
            .toList();
        if (pending.isEmpty) break;
        final job = pending.last;
        try {
          job.state = AiJobState.generating;
          await _persistJobs();
          _notify();
          final prepared = _prepared.remove(job.id);
          if (prepared == null) throw StateError('任务已中断，请确认后重试');
          if (_disposed || job.state == AiJobState.cancelled) continue;
          final bytes = await service.generate(job.id, prepared);
          if (_disposed || job.state == AiJobState.cancelled) continue;
          await _acceptResult(job, bytes);
        } catch (failure) {
          _prepared.remove(job.id);
          if (_disposed) continue;
          if (failure is AiDownloadException &&
              job.state != AiJobState.cancelled) {
            _resultUrls[job.id] = failure.uri;
            job.state = AiJobState.awaitingResult;
            job.pendingResult = PendingAiResult.download;
            job.message = '成片已生成，下载中断。重试下载不会再次生成。';
            try {
              await storage.writeSecret(
                'result-url-${job.id}',
                failure.uri.toString(),
              );
            } catch (_) {
              job.message = '成片地址未能安全保存，请先重试下载；关闭应用后可能无法恢复。';
            }
          } else if (job.state != AiJobState.cancelled) {
            job.state = AiJobState.failed;
            job.message = _message(failure);
          }
        }
        await _tryPersistJobs();
        _notify();
      }
    } finally {
      _running = false;
    }
  }

  String _message(Object failure) => failure.toString().replaceFirst(
    RegExp(r'^(Bad state: |FormatException: )'),
    '',
  );

  Future<bool> _acceptResult(AiJob job, Uint8List bytes) {
    _resultBytes[job.id] = bytes;
    return _savingResults.putIfAbsent(
      job.id,
      () => _writeResult(job).whenComplete(() {
        _savingResults.remove(job.id);
      }),
    );
  }

  Future<bool> _writeResult(AiJob job) async {
    try {
      final path = await storage.saveBytes(
        '${job.id}-result.jpg',
        _resultBytes[job.id]!,
      );
      if (_disposed ||
          job.state == AiJobState.cancelled ||
          !_jobs.contains(job)) {
        await storage.deleteOwnedFile(path);
        _resultBytes.remove(job.id);
        return false;
      }
      job.resultPath = path;
      job.completedAt ??= DateTime.now().millisecondsSinceEpoch;
      job.state = AiJobState.completed;
      job.pendingResult = null;
      job.message = null;
      _resultBytes.remove(job.id);
      _resultUrls.remove(job.id);
      try {
        await storage.writeSecret('result-url-${job.id}', null);
      } catch (_) {
        /* The credential remains encrypted and can be cleaned later. */
      }
      await _archiveResult(job);
      return true;
    } catch (_) {
      if (job.resultPath != null) return true;
      if (!_disposed &&
          job.state != AiJobState.cancelled &&
          _jobs.contains(job)) {
        job.state = AiJobState.awaitingResult;
        job.pendingResult = PendingAiResult.save;
        job.message = '成片已生成，但图片未能写入。请释放存储空间后重试保存，无需再次生成。';
      }
      return false;
    }
  }

  Future<void> retryResult(String id) async {
    final job = _jobs.where((job) => job.id == id).firstOrNull;
    if (job == null ||
        job.state != AiJobState.awaitingResult ||
        !_retryingResults.add(id)) {
      return;
    }
    _notify();
    try {
      Uint8List? bytes = _resultBytes[id];
      if (bytes == null && native.supported) {
        await native.retryResult(id);
        bytes = await native.image(id);
        if (bytes == null) {
          await refreshNative();
          return;
        }
      }
      if (bytes == null && job.pendingResult == PendingAiResult.download) {
        final downloader = service, uri = _resultUrls[id];
        if (downloader is! AiResultDownloader || uri == null) {
          throw StateError('成片地址无法恢复，请先查看服务记录。');
        }
        bytes = await (downloader as AiResultDownloader).downloadResult(
          id,
          uri,
        );
      }
      if (bytes == null) throw StateError('尚未取得成片，请重试同步后台结果。');
      if (!await _acceptResult(job, bytes)) {
        throw StateError(job.message ?? '图片未能保存');
      }
      await _tryPersistJobs();
      unawaited(_process());
    } finally {
      _retryingResults.remove(id);
      _notify();
    }
  }

  Future<void> _archiveResult(AiJob job) async {
    if (preserveResult == null ||
        job.resultPath == null ||
        job.archivedWorkId != null ||
        !_archiving.add(job.id)) {
      return;
    }
    try {
      job.archivedWorkId = await preserveResult!(AiJob.fromJson(job.toJson()));
      job.archiveError = null;
    } catch (_) {
      job.archiveError = '成片已生成，但未能保存到作品。请重试留存，或先保存到系统相册。';
    } finally {
      _archiving.remove(job.id);
    }
  }

  Future<void> archiveResult(String id) async {
    final job = _jobs.where((job) => job.id == id).firstOrNull;
    if (job == null || job.state != AiJobState.completed) return;
    await _archiveResult(job);
    await _tryPersistJobs();
    _notify();
    if (job.archiveError != null) throw StateError(job.archiveError!);
  }

  Future<void> clearFinished({bool includeCompleted = false}) async {
    final ids = jobs
        .where(
          (job) =>
              !job.active &&
              job.state != AiJobState.awaitingResult &&
              (job.state != AiJobState.completed ||
                  preserveResult == null ||
                  job.archivedWorkId != null) &&
              (includeCompleted || job.state != AiJobState.completed),
        )
        .map((job) => job.id)
        .toList();
    for (final id in ids) {
      await clear(id);
    }
  }

  Future<void> _tryPersistJobs() async {
    try {
      await _persistJobs();
    } catch (_) {
      // Keep the result or terminal failure visible; saving again never resubmits AI.
    }
  }

  Future<void> _persistJobs({AiJob? adding}) =>
      _persistTail = _persistTail.catchError((Object _) {}).then((_) async {
        final candidates = [?adding, ..._jobs];
        final retained = retainRecentJobs(candidates);
        final removed = candidates
            .where((job) => !retained.contains(job))
            .toList();
        try {
          await storage.write('jobs', encodeJobs(retained));
        } catch (_) {
          persistenceError = '任务记录未能保存。请重试保存，避免关闭应用后丢失本次记录。';
          rethrow;
        }
        if (adding != null) _jobs.insert(0, adding);
        _jobs.removeWhere(removed.contains);
        persistenceError = null;
        for (final job in removed) {
          try {
            await storage.deleteOwnedFile(job.sourcePath);
            if (job.resultPath != null) {
              await storage.deleteOwnedFile(job.resultPath!);
            }
          } catch (_) {
            // A cleanup failure must not turn an already committed submission into an error.
          }
        }
      });

  Future<void> cancel(String id) async {
    final matches = _jobs.where((job) => job.id == id);
    if (matches.isEmpty) return;
    _nativeRevision++;
    final job = matches.first, previous = matches.first.state;
    job.state = AiJobState.cancelled;
    if (native.supported) {
      try {
        await native.cancel(id);
      } catch (_) {
        job.state = previous;
        _nativeRevision++;
        _notify();
        rethrow;
      }
    }
    _prepared.remove(id);
    service.cancel(id);
    try {
      await _persistJobs();
    } finally {
      _notify();
    }
  }

  Future<void> clear(String id) async {
    final matches = _jobs.where((job) => job.id == id).toList();
    if (matches.isEmpty) return;
    _nativeRevision++;
    final job = matches.first;
    if (job.active) await cancel(id);
    if (native.supported) await native.clear(id);
    final index = _jobs.indexOf(job);
    _jobs.removeWhere((item) => item.id == id);
    try {
      await _persistJobs();
    } catch (_) {
      _jobs.insert(index.clamp(0, _jobs.length), job);
      _notify();
      rethrow;
    }
    _resultBytes.remove(id);
    _resultUrls.remove(id);
    try {
      await storage.deleteOwnedFile(job.sourcePath);
      if (job.resultPath != null) {
        await storage.deleteOwnedFile(job.resultPath!);
      }
      await storage.writeSecret('result-url-$id', null);
    } catch (_) {
      syncError = '任务已移除，部分临时文件未能清理。可以在备份与存储中重试清理。';
    }
    if (!native.supported) unawaited(_process());
    _notify();
  }

  Future<void> syncNative() => _nativeSyncFuture ??= _syncNative().whenComplete(
    () => _nativeSyncFuture = null,
  );
  Future<void> refreshNative() async {
    final pending = _nativeSyncFuture;
    if (pending != null) await pending;
    await syncNative();
  }

  Future<void> repairNativeHistory() async {
    await native.repairHistory();
    await refreshNative();
  }

  Future<void> _syncNative() async {
    if (!native.supported || _disposed) return;
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
          final metadata = objectOf(record['metadata']);
          final title = record['targetTitle'] as String? ?? '目标姿势';
          job = AiJob(
            id: id,
            targetId: metadata['targetId'] as String? ?? '',
            targetTitle: title,
            sourcePath: '',
            createdAt: integerOf(record['createdAt']),
            targetSnapshot: metadata['targetSnapshot'] is Map
                ? objectOf(metadata['targetSnapshot'])
                : null,
            requestMetadata: metadata['requestMetadata'] is Map
                ? objectOf(metadata['requestMetadata'])
                : null,
            sourceWorkId: metadata['sourceWorkId'] as String?,
            retryOf: metadata['retryOf'] as String?,
          );
          _jobs.add(job);
        }
        if (_disposed || job.state == AiJobState.cancelled) continue;
        if (job.sourcePath.isEmpty && record['sourceAvailable'] == true) {
          final source = await native.image(id, source: true);
          if (source != null) {
            final path = await storage.saveBytes(
              '$id-source-restored.jpg',
              source,
            );
            if (_disposed ||
                revision != _nativeRevision ||
                !_jobs.contains(job)) {
              await storage.deleteOwnedFile(path);
              return;
            }
            job.sourcePath = path;
          }
        }
        final nextState = AiJobState.values.firstWhere(
          (state) => state.name == record['state'],
          orElse: () => AiJobState.failed,
        );
        final message = record['message'] as String?;
        final completedAt = record['completedAt'] is num
            ? integerOf(record['completedAt'])
            : null;
        var resultPath = job.resultPath;
        if ((nextState == AiJobState.completed ||
                nextState == AiJobState.awaitingResult) &&
            resultPath == null &&
            (record['image'] is String || record['imageAvailable'] == true)) {
          final bytes = record['image'] is String
              ? base64Decode((record['image'] as String).split(',').last)
              : await native.image(id);
          if (bytes == null) throw const FormatException('后台结果图片无法读取');
          if (!await _acceptResult(job, bytes)) continue;
          resultPath = job.resultPath;
          if (_disposed ||
              revision != _nativeRevision ||
              !_jobs.contains(job)) {
            if (resultPath != null) await storage.deleteOwnedFile(resultPath);
            return;
          }
        }
        if (nextState == AiJobState.completed && resultPath == null) {
          throw const FormatException('后台任务未返回可用图片');
        }
        job.state = resultPath != null && nextState != AiJobState.cancelled
            ? AiJobState.completed
            : nextState;
        job.pendingResult = job.state == AiJobState.awaitingResult
            ? PendingAiResult.values
                  .where((value) => value.name == record['pendingResult'])
                  .firstOrNull
            : null;
        job.message = job.state == AiJobState.completed ? null : message;
        job.completedAt = completedAt ?? job.completedAt;
        job.resultPath = resultPath;
        if (job.state == AiJobState.completed) await _archiveResult(job);
      }
      if (_disposed || revision != _nativeRevision) return;
      final nativeIds = records.map((record) => record['id']).toSet();
      for (final job in _jobs.where(
        (job) =>
            job.active &&
            !nativeIds.contains(job.id) &&
            !_startingNative.contains(job.id),
      )) {
        job.state = AiJobState.failed;
        job.message = '上次任务未能继续，确认后可以重试。';
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
