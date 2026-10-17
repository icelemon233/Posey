import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:posey/core/media/photo_library.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/core/storage/storage_transaction.dart';
import 'package:posey/core/media/device_platform.dart';
import 'package:posey/features/ai_pose/ai_job_repository.dart';
import 'package:posey/features/ai_pose/ai_jobs_view_model.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';
import 'package:posey/features/ai_pose/native_background_ai.dart';
import 'package:posey/features/poses/pose_library_view_model.dart';
import 'package:posey/features/poses/pose_repository.dart';
import 'package:posey/features/settings/settings_repository.dart';
import 'package:posey/features/settings/settings_view_model.dart';
import 'package:posey/features/works/works_repository.dart';
import 'package:posey/features/works/photo_work.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/app/import_recovery.dart';
import 'package:posey/app/data_management.dart';
import 'package:posey/features/backup/backup_manager.dart';

enum AppLoadState { loading, ready, failed }

class PoseyDependencies extends ChangeNotifier {
  PoseyDependencies({
    required this.storage,
    required this.aiService,
    PhotoLibrary? photos,
    NativeBackgroundAi native = const NativeBackgroundAi(),
    DevicePlatform? platform,
  }) : photos = photos ?? DevicePhotoLibrary(),
       platform = platform ?? DevicePlatform(),
       library = PoseLibraryViewModel(PoseRepository(storage, photos: photos)),
       settings = SettingsViewModel(SettingsRepository(storage)) {
    works = WorksRepository(
      storage,
      this.photos,
      cleanup: (paths) =>
          cleanRemovedMedia(storage, library, works, jobs, paths),
    );
    importRecovery = ImportRecovery(storage, this.photos);
    _jobsRepository = AiJobRepository(
      storage,
      aiService,
      native: native,
      preserveResult: _preserveResult,
    );
    jobs = AiJobsViewModel(
      _jobsRepository,
      this.photos,
      configuration: () => settings.configuration,
      preferences: () => settings.preferences,
      targetFor: (job) => job.targetSnapshot != null
          ? PoseTemplate.fromJson(job.targetSnapshot!)
          : library.find(job.targetId, title: job.targetTitle),
      beforeSubmit: () async {
        if (this.platform.supported) await this.platform.requestNotifications();
      },
    );
    backup = createBackupManager(
      storage: storage,
      platform: this.platform,
      library: library,
      settings: settings,
      works: works,
      jobs: jobs,
      reload: () =>
          Future.wait([library.load(), settings.load(), works.load()]),
      fatal: (message) {
        _state = AppLoadState.failed;
        error = message;
        _notify();
      },
    );
  }
  final PhotoLibrary photos;
  final PoseyStorage storage;
  final AiPoseService aiService;
  final DevicePlatform platform;
  late final WorksRepository works;
  late final ImportRecovery importRecovery;
  late final BackupManager backup;
  String? importError;
  final PoseLibraryViewModel library;
  final SettingsViewModel settings;
  late final AiJobRepository _jobsRepository;
  late final AiJobsViewModel jobs;
  AppLoadState _state = AppLoadState.loading;
  AppLoadState get state => _state;
  String? error;
  Future<void>? _initialization;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() =>
      _initialization ??= _load().whenComplete(() => _initialization = null);
  Future<void> _load() async {
    if (_disposed) return;
    _state = AppLoadState.loading;
    error = null;
    _notify();
    try {
      await recoverStorageTransaction(storage);
      await Future.wait([
        library.load(),
        _loadSettings(),
        _loadWorks(),
        _loadJobs(),
      ]);
      for (final job in jobs.jobs.where(
        (job) =>
            job.state == AiJobState.completed && job.archivedWorkId == null,
      )) {
        try {
          await jobs.archiveResult(job.id);
        } catch (_) {
          /* The task exposes retrying retention. */
        }
      }
      await retryImportRecovery();
      if (!_disposed) _state = AppLoadState.ready;
    } catch (failure) {
      if (!_disposed) {
        _state = AppLoadState.failed;
        error = '加载失败，可以重试：$failure';
      }
    }
    _notify();
  }

  Future<void> _loadJobs() async {
    try {
      await _jobsRepository.load();
    } catch (_) {
      // AI history has its own recovery UI; offline photography stays available.
    }
  }

  Future<void> _loadWorks() async {
    try {
      await works.load();
    } catch (_) {
      /* The works page owns record recovery. */
    }
  }

  Future<void> _loadSettings() async {
    try {
      await settings.load();
    } catch (_) {
      /* Photography does not depend on AI settings. */
    }
  }

  Future<void> retryImportRecovery() async {
    try {
      final pending = await importRecovery.recover();
      if (pending != null) {
        await works.retain(pending.path!, pending.pose, importId: pending.id);
        await importRecovery.complete(pending.id);
      }
      importError = null;
    } catch (_) {
      importError = '上次选择的照片尚未恢复，请在设置中重试恢复。';
    }
    _notify();
  }

  Future<String> _preserveResult(AiJob job) async {
    await works.ensureLoaded();
    final pose = job.targetSnapshot != null
        ? PoseTemplate.fromJson(job.targetSnapshot!)
        : library.find(job.targetId, title: job.targetTitle) ??
              PoseTemplate.fromJson({
                'id': job.targetId.isEmpty ? 'legacy-${job.id}' : job.targetId,
                'title': job.targetTitle,
                'illustration': '',
                'unavailable': true,
              });
    final source = works.find(job.sourceWorkId ?? '');
    final work = await works.retain(
      job.resultPath!,
      pose,
      kind: WorkKind.ai,
      sourceWorkId: source?.id,
      originalPath:
          source?.original ?? (job.sourcePath.isEmpty ? null : job.sourcePath),
      aiJobId: job.id,
    );
    return work.id;
  }

  Future<AiConnectionCheck> checkAiConnection(
    AiConfiguration configuration,
  ) async {
    final service = aiService;
    if (service is! AiConnectionTester) throw StateError('当前服务未提供连接检查');
    return (service as AiConnectionTester).checkConnection(configuration);
  }

  void cancelAiConnectionCheck() {
    final service = aiService;
    if (service is AiConnectionTester) {
      (service as AiConnectionTester).cancelConnectionCheck();
    }
  }

  Future<Map<String, dynamic>>? _deviceInfo;
  Future<Map<String, dynamic>> deviceInfo() => _deviceInfo ??= platform
      .appInfo()
      .catchError((Object _) => <String, dynamic>{'error': '版本信息暂时不可用'});

  @override
  void dispose() {
    _disposed = true;
    jobs.dispose();
    _jobsRepository.dispose();
    library.dispose();
    settings.dispose();
    works.dispose();
    backup.dispose();
    unawaited(platform.dispose());
    super.dispose();
  }
}
