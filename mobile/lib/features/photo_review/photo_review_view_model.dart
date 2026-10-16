import 'package:flutter/foundation.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/features/poses/pose_template.dart';

enum PhotoReviewPhase { idle, saving, submitting }

class PhotoReviewViewModel extends ChangeNotifier {
  PhotoReviewViewModel({
    required this.photos,
    required this.target,
    required this.path,
    required this.hasConfiguration,
    required this.serviceHost,
    required this.submit,
    this.generated = false,
  });
  final PhotoLibrary photos;
  final PoseTemplate target;
  final String path;
  final bool generated;
  final bool Function() hasConfiguration;
  final String Function() serviceHost;
  final Future<void> Function({required bool consent}) submit;
  PhotoReviewPhase _phase = PhotoReviewPhase.idle;
  bool _saved = false, _disposed = false;
  bool get busy => _phase != PhotoReviewPhase.idle;
  bool get saved => _saved;
  PhotoReviewPhase get phase => _phase;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> save() async {
    if (busy || _disposed) return false;
    _phase = PhotoReviewPhase.saving;
    _notify();
    try {
      await photos.saveToGallery(path);
      _saved = true;
      return true;
    } finally {
      _phase = PhotoReviewPhase.idle;
      _notify();
    }
  }

  Future<bool> generate({required bool consent}) async {
    if (!consent) throw StateError('请先确认将这张照片和姿势参考发送给 AI 服务');
    if (busy || _disposed || generated) return false;
    _phase = PhotoReviewPhase.submitting;
    _notify();
    try {
      await submit(consent: true);
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
