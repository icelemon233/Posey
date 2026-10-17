import 'package:flutter/foundation.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/works/photo_work.dart';

enum PhotoReviewPhase { idle, saving, submitting }

class PhotoGenerationRequest {
  const PhotoGenerationRequest({required this.path,required this.target,required this.options,this.workId});
  final String path;
  final PoseTemplate target;
  final AiRequestOptions options;
  final String? workId;
}

class PhotoReviewViewModel extends ChangeNotifier {
  PhotoReviewViewModel({
    required this.photos,
    required this._target,
    required this._path,
    required this.hasConfiguration,
    required this.serviceHost,
    required this.submit,
    this._generated = false,
    this.originalPath,
    this.workId,
    this.retainAction,
    this.saveAction,
    this.savedState,
    this.requestOptions,
    this.submitWithOptions,
    this.submitRequest,
  });
  final PhotoLibrary photos;
  PoseTemplate _target;
  String _path;
  bool _generated;
  PoseTemplate get target => _target;
  String get path => _path;
  bool get generated => _generated;
  String? originalPath, workId;
  bool get retained => workId != null;
  final Future<PhotoWork> Function()? retainAction;
  final Future<void> Function()? saveAction;
  final bool Function()? savedState;
  final AiRequestOptions Function()? requestOptions;
  final Future<void> Function(AiRequestOptions, {required bool consent})?
  submitWithOptions;
  final Future<void> Function(PhotoGenerationRequest,{required bool consent})? submitRequest;
  PhotoGenerationRequest? createRequest() {
    final options=requestOptions?.call();if(options==null)return null;
    return PhotoGenerationRequest(path:generated?originalPath??path:path,target:target.withMirror(target.mirrored),options:options,workId:workId);
  }
  final bool Function() hasConfiguration;
  final String Function() serviceHost;
  final Future<void> Function({required bool consent}) submit;
  PhotoReviewPhase _phase = PhotoReviewPhase.idle;
  bool _saved = false, _disposed = false;
  bool get busy => _phase != PhotoReviewPhase.idle;
  bool get saved => _saved || (savedState?.call() ?? false);
  PhotoReviewPhase get phase => _phase;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> save() async {
    if (busy || _disposed || saved) return false;
    _phase = PhotoReviewPhase.saving;
    _notify();
    try {
      if (saveAction != null) {
        await saveAction!();
      } else {
        await photos.saveToGallery(path);
      }
      _saved = true;
      return true;
    } finally {
      _phase = PhotoReviewPhase.idle;
      _notify();
    }
  }

  Future<bool> generate({
    required bool consent,
    AiRequestOptions? options,
    PhotoGenerationRequest? request,
  }) async {
    if (!consent) throw StateError('请先确认将这张照片和姿势参考发送给 AI 服务');
    if (busy || _disposed) return false;
    if (!(request?.target??target).available) throw StateError('请先选择一个姿势参考');
    if (request==null && !retained && retainAction != null) {
      await retain();
      if (_disposed || !retained) return false;
    }
    _phase = PhotoReviewPhase.submitting;
    _notify();
    try {
      if(submitRequest!=null&&request!=null){await submitRequest!(request,consent:true);}
      else if (submitWithOptions != null && options != null) {
        await submitWithOptions!(options, consent: true);
      } else {
        await submit(consent: true);
      }
      return !_disposed;
    } finally {
      _phase = PhotoReviewPhase.idle;
      _notify();
    }
  }

  void selectTarget(PoseTemplate pose) {
    if (!busy && !_disposed) {
      _target = pose;
      _notify();
    }
  }

  void replacePhoto(PhotoWork work) {
    if (_disposed) return;
    workId = work.id;
    _path = work.path;
    originalPath = work.original;
    _target = work.pose;
    _generated = work.kind == WorkKind.ai;
    _saved = false;
    _notify();
  }

  Future<bool> retain() async {
    if (retained || retainAction == null || busy || _disposed) return false;
    _phase = PhotoReviewPhase.saving;
    _notify();
    try {
      final work = await retainAction!();
      if (!_disposed) replacePhoto(work);
      return !_disposed;
    } finally {
      _phase = PhotoReviewPhase.idle;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
