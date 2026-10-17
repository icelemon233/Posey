import 'package:flutter/foundation.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_job_repository.dart';
import 'package:posey/core/json.dart';

class AiJobsViewModel extends ChangeNotifier {
  AiJobsViewModel(
    this.repository,
    this.photos, {
    required this.configuration,
    required this.preferences,
    required this.targetFor,
    this.beforeSubmit,
  }) {
    repository.addListener(_changed);
  }
  final AiJobRepository repository;
  final PhotoLibrary photos;
  final AiConfiguration Function() configuration;
  final AiPreferences Function() preferences;
  final PoseTemplate? Function(AiJob) targetFor;
  final Future<void> Function()? beforeSubmit;
  AiRequestOptions currentOptions() =>
      AiRequestOptions(configuration(), preferences());
  AiRequestOptions retryOptions(AiJob job, {bool original = true}) {
    final current = currentOptions(), metadata = job.requestMetadata;
    if (!original ||
        metadata == null ||
        metadata['endpoint'] != current.configuration.baseUri.toString()) {
      return current;
    }
    return AiRequestOptions(
      AiConfiguration(
        key: current.configuration.key,
        endpoint: metadata['endpoint'] as String,
        model: metadata['model'] as String? ?? current.configuration.model,
      ),
      AiPreferences.fromJson(objectOf(metadata['preferences'])),
      frozenPrompt: metadata['prompt'] as String?,
    );
  }

  final _saving = <String>{};
  final _retrying = <String>{};
  bool _disposed = false;
  bool _recovering = false;
  bool get recovering => _recovering;
  List<AiJob> get jobs => repository.jobs;
  int get activeJobs => repository.activeJobs;
  bool get backgroundSupported => repository.backgroundSupported;
  bool get hasPendingIO => repository.hasPendingIO;
  bool isRetryingResult(String id) => repository.isRetryingResult(id);
  Future<void> retryResult(String id) => repository.retryResult(id);
  Future<void> repairNativeHistory() => repository.repairNativeHistory();
  String? get syncError => repository.syncError;
  String? get loadError => repository.loadError;
  String? get persistenceError => repository.persistenceError;
  bool isRetrying(String id) =>
      _retrying.contains(id) || repository.isRetrying(id);
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
    String? retryOf,
    String? sourceWorkId,
    AiRequestOptions? options,
  }) async {
    if (!consent) throw StateError('请先确认将这张照片和姿势参考发送给 AI 服务');
    final snapshot = options ?? currentOptions();
    final config = snapshot.configuration, choices = snapshot.preferences;
    config.validate();
    if (repository.loadError != null) throw StateError('请先恢复 AI 任务记录');
    await beforeSubmit?.call();
    final image = await photos.readPhoto(path);
    if (_disposed) return;
    await repository.enqueue(
      target,
      image,
      consent: true,
      configuration: config,
      preferences: choices,
      retryOf: retryOf,
      sourceWorkId: sourceWorkId,
      frozenPrompt: snapshot.frozenPrompt,
    );
  }

  Future<void> retry(
    AiJob job, {
    required bool consent,
    AiRequestOptions? options,
  }) async {
    if (!consent) throw StateError('请先确认本次生成的数据发送与费用');
    if (_disposed || job.active || isRetrying(job.id)) return;
    _retrying.add(job.id);
    _changed();
    try {
      final target = targetFor(job);
      if (target == null) throw StateError('这个参考姿势已不可用，请重新选择。');
      await submitPhoto(
        target,
        job.sourcePath,
        consent: true,
        retryOf: job.id,
        sourceWorkId: job.sourceWorkId,
        options: options ?? retryOptions(job),
      );
    } finally {
      _retrying.remove(job.id);
      _changed();
    }
  }

  Future<void> _recover(Future<void> Function() action) async {
    if (_disposed || _recovering) return;
    _recovering = true;
    _changed();
    try {
      await action();
    } finally {
      _recovering = false;
      _changed();
    }
  }

  Future<void> reload() => _recover(repository.load);
  Future<void> resetUnreadableHistory() =>
      _recover(repository.resetUnreadableHistory);
  Future<void> retryPersistence() => repository.retryPersistence();
  Future<void> archiveResult(String id) => repository.archiveResult(id);
  Future<void> clearFinished({bool includeCompleted = false}) =>
      repository.clearFinished(includeCompleted: includeCompleted);

  Future<void> cancel(String id) => repository.cancel(id);
  Future<void> clear(String id) => repository.clear(id);
  Future<void> syncNative() => repository.refreshNative();
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
