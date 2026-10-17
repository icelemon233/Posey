import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/core/storage/storage_transaction.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:uuid/uuid.dart';
import 'package:posey/core/media/image_format.dart';

class PoseRepository {
  PoseRepository(
    this.storage, {
    Future<String> Function()? loadCatalog,
    PhotoLibrary? photos,
  }) : _loadCatalog =
           loadCatalog ??
           (() => rootBundle.loadString('assets/data/poses.json')),
       photos = photos ?? DevicePhotoLibrary();
  final PhotoLibrary photos;
  final PoseyStorage storage;
  final Future<String> Function() _loadCatalog;

  Future<List<PoseTemplate>> loadTemplates() async {
    final raw = jsonDecode(await _loadCatalog());
    if (raw is! List) throw const FormatException('姿势库格式无效');
    final templates = raw
        .map((value) => PoseTemplate.fromJson(objectOf(value)))
        .toList();
    if (templates.map((pose) => pose.id).toSet().length != templates.length) {
      throw const FormatException('姿势库包含重复标识');
    }
    return templates;
  }

  Future<Set<String>> loadFavorites() async {
    final raw = jsonDecode(await storage.read('favorites') ?? '[]');
    if (raw is! List) throw const FormatException('收藏记录格式无效');
    return stringsOf(raw).toSet();
  }

  Future<void> saveFavorites(Set<String> ids) =>
      storage.write('favorites', jsonEncode(ids.toList()));

  Future<List<PoseTemplate>> loadCustom() async {
    final raw = jsonDecode(await storage.read('custom-poses-v1') ?? '[]');
    if (raw is! List) throw const FormatException('自有参考记录格式无效');
    final poses = raw
        .map((value) => PoseTemplate.fromJson(objectOf(value)))
        .toList();
    if (poses.any((pose) => !pose.isUserReference) ||
        poses.map((pose) => pose.id).toSet().length != poses.length) {
      throw const FormatException('自有参考编号无效');
    }
    return poses;
  }

  Future<Map<String, int>> loadRecents() async {
    final raw = jsonDecode(await storage.read('recent-poses-v1') ?? '{}');
    if (raw is! Map ||
        raw.entries.any(
          (entry) => entry.key is! String || entry.value is! num,
        )) {
      throw const FormatException('最近使用记录格式无效');
    }
    return raw.map(
      (key, value) => MapEntry(key as String, (value as num).toInt()),
    );
  }

  Future<void> saveRecents(Map<String, int> values) =>
      storage.write('recent-poses-v1', jsonEncode(values));
  Future<void> saveCustom(List<PoseTemplate> poses, {Set<String>? favorites}) =>
      writeStorageBatch(storage, {
        'custom-poses-v1': jsonEncode(poses.map((pose) => pose.raw).toList()),
        if (favorites != null) 'favorites': jsonEncode(favorites.toList()),
      });
  Future<PoseTemplate> createCustom(
    String path,
    String title,
    String category,
    String gender,
  ) async {
    final id = 'user-${const Uuid().v4()}';
    final bytes = await photos.readPhoto(path);
    final file = await storage.saveBytes('$id.${imageExtension(bytes)}', bytes);
    return PoseTemplate.fromJson({
      'id': id,
      'title': title.trim(),
      'illustration': file,
      'category': category,
      'gender': gender,
      'userReference': true,
      'source': {'usageStatus': 'user-imported', 'label': '自有参考'},
      'steps': ['对照参考调整身体和手脚位置。'],
      'tags': [],
      'scenes': [],
      'props': [],
    });
  }

  Future<void> resetRecord(String key) async {
    if (!['favorites', 'custom-poses-v1', 'recent-poses-v1'].contains(key)) {
      throw ArgumentError('Unknown record');
    }
    final original = await storage.read(key);
    if (original != null) {
      await storage.write('$key-recovery-${const Uuid().v4()}', original);
    }
    await storage.write(key, key == 'recent-poses-v1' ? '{}' : '[]');
  }
}
