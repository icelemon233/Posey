import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/core/media/image_format.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/core/storage/stored_media_paths.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/works/photo_work.dart';

class WorksRepository extends ChangeNotifier {
  WorksRepository(this.storage, this.photos, {this.cleanup});
  final Future<void> Function(Set<String>)? cleanup;
  final PoseyStorage storage;
  final PhotoLibrary photos;
  List<PhotoWork> _works = [];
  List<PhotoWork> get works => List.unmodifiable(_works);
  String? loadError;
  bool _loaded = false, _disposed = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  int _pendingWrites = 0;
  bool get hasPendingWrites => _pendingWrites > 0;
  Future<void> settle() => _writes;
  final _galleryBusy = <String>{};
  final _galleryWritten = <String>{};
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  PhotoWork? find(String id) =>
      _works.where((work) => work.id == id).firstOrNull;
  Future<void> ensureLoaded() => _loaded ? Future.value() : load();
  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  Future<void> _load() async {
    try {
      final raw = jsonDecode(await storage.read('works-v1') ?? '[]');
      if (raw is! List) throw const FormatException('作品记录格式无效');
      final paths = StoredMediaPaths(await storage.mediaFiles());
      final next = raw
          .map((value) => PhotoWork.fromJson(paths.work(objectOf(value))))
          .toList();
      if (next.map((work) => work.id).toSet().length != next.length) {
        throw const FormatException('作品编号重复');
      }
      if (_disposed) return;
      _works = next..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loaded = true;
      loadError = null;
    } catch (_) {
      _loaded = false;
      loadError = '作品记录无法读取。请重试，或备份后重置作品列表。';
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    _pendingWrites++;
    final operation = _writes
        .catchError((Object _) {})
        .then((_) async {
          if (_disposed) throw StateError('作品页面已关闭');
          await ensureLoaded();
          if (loadError != null) throw StateError(loadError!);
          return action();
        })
        .whenComplete(() => _pendingWrites--);
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _commit(List<PhotoWork> next) async {
    await storage.write(
      'works-v1',
      jsonEncode(next.map((work) => work.toJson()).toList()),
    );
    _works = next;
    _notify();
  }

  Future<PhotoWork> retain(
    String path,
    PoseTemplate pose, {
    WorkKind kind = WorkKind.photo,
    String? sourceWorkId,
    String? originalPath,
    String? aiJobId,
    String? importId,
  }) => _serialize(() async {
    if (importId != null) {
      final existing = _works
          .where((work) => work.importId == importId)
          .firstOrNull;
      if (existing != null) return existing;
    }
    if (aiJobId != null) {
      final existing = _works
          .where((work) => work.aiJobId == aiJobId)
          .firstOrNull;
      if (existing != null) return existing;
    }
    final bytes = await photos.readPhoto(path);
    final id = const Uuid().v4();
    final stored = await storage.saveBytes(
      'work-$id.${imageExtension(bytes)}',
      bytes,
    );
    String? storedOriginal;
    try {
      final original = originalPath ?? find(sourceWorkId ?? '')?.original;
      if (original != null && original != path) {
        if (_works.any(
          (work) => work.path == original || work.originalPath == original,
        )) {
          storedOriginal = original;
        } else {
          final originalBytes = await photos.readPhoto(original);
          storedOriginal = await storage.saveBytes(
            'work-$id-original.${imageExtension(originalBytes)}',
            originalBytes,
          );
        }
      }
      final work = PhotoWork(
        id: id,
        path: stored,
        pose: pose,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        kind: kind,
        sourceWorkId: sourceWorkId,
        originalPath: storedOriginal,
        aiJobId: aiJobId,
        importId: importId,
      );
      await _commit([work, ..._works]);
      return work;
    } catch (_) {
      await storage.deleteOwnedFile(stored);
      if (storedOriginal != null &&
          !_works.any(
            (work) =>
                work.original == storedOriginal || work.path == storedOriginal,
          )) {
        await storage.deleteOwnedFile(storedOriginal);
      }
      rethrow;
    }
  });
  Future<bool> saveToGallery(String id) async {
    if (!_galleryBusy.add(id)) return false;
    try {
      final work = find(id);
      if (work == null) throw StateError('作品已移除');
      if (work.savedToGallery) return false;
      if (!_galleryWritten.contains(id)) {
        await photos.saveToGallery(work.path);
        _galleryWritten.add(id);
      }
      try {
        await _serialize(
          () => _commit(
            _works
                .map(
                  (item) => item.id == id
                      ? item.copyWith(savedToGallery: true)
                      : item,
                )
                .toList(),
          ),
        );
      } catch (_) {
        throw StateError('照片已保存到相册，但作品标记未能保存。可以重试保存标记。');
      }
      return true;
    } finally {
      _galleryBusy.remove(id);
      _notify();
    }
  }

  Set<String> get referencedPaths => {
    for (final work in _works) ...[work.path, work.original],
    for (final work in _works)
      if (work.pose.isUserReference) work.pose.illustration,
  };
  Future<PhotoWork> retainBytes(
    Uint8List bytes,
    PoseTemplate pose, {
    String? sourceWorkId,
    String? originalPath,
  }) async {
    final temporary = await storage.saveBytes(
      'edit-staging-${const Uuid().v4()}.jpg',
      bytes,
    );
    try {
      return await retain(
        temporary,
        pose,
        kind: WorkKind.edit,
        sourceWorkId: sourceWorkId,
        originalPath: originalPath,
      );
    } finally {
      await storage.deleteOwnedFile(temporary);
    }
  }

  Future<void> delete(Set<String> ids) => _serialize(() async {
    final removed = _works.where((work) => ids.contains(work.id)).toList();
    await _commit(_works.where((work) => !ids.contains(work.id)).toList());
    final retained = referencedPaths;
    if (cleanup != null) {
      await cleanup!({
        for (final work in removed) ...[
          work.path,
          work.original,
          if (work.pose.isUserReference) work.pose.illustration,
        ],
      });
      return;
    }
    for (final path in {
      for (final work in removed) ...[work.path, work.original],
    }) {
      if (!retained.contains(path)) await storage.deleteOwnedFile(path);
    }
  });
  Future<void> resetUnreadableHistory() async {
    if (loadError == null) return;
    final original = await storage.read('works-v1');
    if (original != null) {
      await storage.write('works-recovery-${const Uuid().v4()}', original);
    }
    await storage.write('works-v1', '[]');
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
