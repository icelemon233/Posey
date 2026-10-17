import 'package:flutter/foundation.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/features/photo_review/photo_edit.dart';

class PhotoEditorViewModel extends ChangeNotifier {
  PhotoEditorViewModel({
    required this.path,
    required this.photos,
    required this.onSave,
  });
  final String path;
  final PhotoLibrary photos;
  final Future<void> Function(Uint8List) onSave;
  Uint8List? _original, preview;
  PhotoEdit edit = const PhotoEdit();
  String? error;
  bool rendering = false, saving = false, _disposed = false;
  int _revision = 0;
  Future<void>? _loading, _rendering;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  Future<void> _load() async {
    try {
      final bytes = await photos.readPhoto(path);
      if (_disposed) return;
      _original = bytes;
      await render(edit);
    } catch (_) {
      error = '照片无法读取，请重新选择照片。';
      _notify();
    }
  }

  Future<void> render(PhotoEdit next) {
    if (_disposed || _original == null || saving) return Future.value();
    edit = next;
    _revision++;
    rendering = true;
    error = null;
    _notify();
    return _rendering ??= _render().whenComplete(() => _rendering = null);
  }

  Future<void> _render() async {
    while (!_disposed) {
      final revision = _revision, draft = edit;
      try {
        final bytes = await compute(editPhoto, (
          bytes: _original!,
          edit: draft,
          preview: true,
        ));
        if (_disposed) return;
        if (revision == _revision) preview = bytes;
      } catch (_) {
        if (revision == _revision) error = '照片无法编辑，请改用 JPEG、PNG 或 WebP 图片。';
      }
      if (revision == _revision) break;
    }
    rendering = false;
    _notify();
  }

  Future<bool> save() async {
    if (_disposed || _original == null || saving || rendering) return false;
    saving = true;
    _notify();
    try {
      final bytes = await compute(editPhoto, (
        bytes: _original!,
        edit: edit,
        preview: false,
      ));
      if (_disposed) return false;
      await onSave(bytes);
      return true;
    } finally {
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
