import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/poses/pose_template.dart';

class PendingPhotoImport {
  const PendingPhotoImport(this.id, this.pose, this.path);
  final String id;
  final PoseTemplate pose;
  final String? path;
  Json toJson() => {'id': id, 'pose': pose.raw, 'path': path};
}

class ImportRecovery {
  ImportRecovery(this.storage, this.photos);
  final PoseyStorage storage;
  final PhotoLibrary photos;
  String? _recoveredPath;
  Future<PendingPhotoImport?> pending() async {
    final raw = await storage.read('pending-import-v1');
    if (raw == null) return null;
    final json = objectOf(jsonDecode(raw));
    if (json['id'] is! String ||
        json['pose'] is! Map ||
        (json['path'] != null && json['path'] is! String)) {
      throw const FormatException('照片恢复记录无效');
    }
    return PendingPhotoImport(
      json['id'],
      PoseTemplate.fromJson(objectOf(json['pose'])),
      json['path'] as String?,
    );
  }

  Future<String> stage(PoseTemplate pose) async {
    final id = const Uuid().v4();
    await storage.write(
      'pending-import-v1',
      jsonEncode(PendingPhotoImport(id, pose, null).toJson()),
    );
    return id;
  }

  Future<void> selected(String id, String path) async {
    final record = await pending();
    if (record?.id != id) throw StateError('照片选择已被其他操作替换，请重试。');
    await storage.write(
      'pending-import-v1',
      jsonEncode(PendingPhotoImport(id, record!.pose, path).toJson()),
    );
  }

  Future<void> complete(String id) async {
    if ((await pending())?.id == id) {
      await storage.remove('pending-import-v1');
      _recoveredPath = null;
    }
  }

  Future<PendingPhotoImport?> recover() async {
    var record = await pending();
    final provider = photos;
    final lost =
        _recoveredPath ??
        (provider is RecoverablePhotoLibrary
            ? await (provider as RecoverablePhotoLibrary).recoverLostPhoto()
            : null);
    _recoveredPath = lost;
    if (record == null && lost != null) {
      final id = await stage(
        PoseTemplate.fromJson({
          'id': 'unselected-reference',
          'title': '未选择参考',
          'illustration': '',
          'unavailable': true,
        }),
      );
      await selected(id, lost);
      record = await pending();
    }
    if (record == null) return null;
    if (record.path == null && lost != null) {
      await selected(record.id, lost);
      record = await pending();
    }
    if (record?.path == null) {
      await complete(record!.id);
      return null;
    }
    return record;
  }
}
