import 'package:flutter/foundation.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_job_repository.dart';

class AiJobsViewModel extends ChangeNotifier {
  AiJobsViewModel(
    this.repository,
    this.photos, {
    required this.configuration,
    required this.preferences,
    required this.targetFor,
  }) {
    repository.addListener(_changed);
  }
  final AiJobRepository repository;
  final PhotoLibrary photos;
  final AiConfiguration Function() configuration;
  final AiPreferences Function() preferences;
  final PoseTemplate? Function(AiJob) targetFor;
  final _saving = <String>{};
  bool _disposed = false;
  List<AiJob> get jobs => repository.jobs;
  int get activeJobs => repository.activeJobs;
  bool get backgroundSupported => repository.backgroundSupported;
  String? get syncError => repository.syncError;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> enqueue(
    PoseTemplate target,
    Uint8List image, {
    required bool consent,
  }) => repository.enqueue(
    target,
    image,
    consent: consent,
    configuration: configuration(),
    preferences: preferences(),
  );

  Future<void> submitPhoto(
    PoseTemplate target,
    String path, {
    required bool consent,
  }) async {
    if (!consent) throw StateError('请先确认将这张照片和姿势参考发送给 AI 服务');
    final config = configuration(), options = preferences();
    config.validate();
    final image = await photos.readPhoto(path);
    if (_disposed) return;
    await repository.enqueue(
      target,
      image,
      consent: true,
      configuration: config,
      preferences: options,
    );
  }

  Future<void> retry(AiJob job) async {
    if (job.active) return;
    final target = targetFor(job);
    if (target == null) throw StateError('这个参考姿势已不可用，请重新选择。');
    await submitPhoto(target, job.sourcePath, consent: true);
  }

  Future<void> cancel(String id) => repository.cancel(id);
  Future<void> clear(String id) => repository.clear(id);
  Future<void> syncNative() => repository.syncNative();
  Future<bool> saveResult(AiJob job) async {
    if (job.resultPath == null || !_saving.add(job.id)) return false;
    _changed();
    try {
      await photos.saveToGallery(job.resultPath!);
      return true;
    } finally {
      _saving.remove(job.id);
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    repository.removeListener(_changed);
    super.dispose();
  }
}
