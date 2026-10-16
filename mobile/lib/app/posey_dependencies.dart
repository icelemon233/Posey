import 'package:flutter/foundation.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/ai_pose/ai_job_repository.dart';
import 'package:posey/features/ai_pose/ai_jobs_view_model.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';
import 'package:posey/features/ai_pose/native_background_ai.dart';
import 'package:posey/features/poses/pose_library_view_model.dart';
import 'package:posey/features/poses/pose_repository.dart';
import 'package:posey/features/settings/settings_repository.dart';
import 'package:posey/features/settings/settings_view_model.dart';

enum AppLoadState { loading, ready, failed }

class PoseyDependencies extends ChangeNotifier {
  PoseyDependencies({
    required PoseyStorage storage,
    required AiPoseService aiService,
    PhotoLibrary? photos,
    NativeBackgroundAi native = const NativeBackgroundAi(),
  }) : photos = photos ?? DevicePhotoLibrary(),
       library = PoseLibraryViewModel(PoseRepository(storage)),
       settings = SettingsViewModel(SettingsRepository(storage)),
       _jobsRepository = AiJobRepository(storage, aiService, native: native) {
    jobs = AiJobsViewModel(
      _jobsRepository,
      this.photos,
      configuration: () => settings.configuration,
      preferences: () => settings.preferences,
      targetFor: (job) => library.find(job.targetId, title: job.targetTitle),
    );
  }
  final PhotoLibrary photos;
  final PoseLibraryViewModel library;
  final SettingsViewModel settings;
  final AiJobRepository _jobsRepository;
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
      await Future.wait([
        library.load(),
        settings.load(),
        _jobsRepository.load(),
      ]);
      if (!_disposed) _state = AppLoadState.ready;
    } catch (failure) {
      if (!_disposed) {
        _state = AppLoadState.failed;
        error = '加载失败，可以重试：$failure';
      }
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    jobs.dispose();
    _jobsRepository.dispose();
    library.dispose();
    settings.dispose();
    super.dispose();
  }
}
