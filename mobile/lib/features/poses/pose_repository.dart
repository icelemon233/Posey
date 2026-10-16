import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/poses/pose_template.dart';

class PoseRepository {
  PoseRepository(this.storage, {Future<String> Function()? loadCatalog})
    : _loadCatalog =
          loadCatalog ??
          (() => rootBundle.loadString('assets/data/poses.json'));
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
}
