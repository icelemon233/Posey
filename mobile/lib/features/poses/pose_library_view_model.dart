import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:posey/features/poses/pose_repository.dart';
import 'package:posey/features/poses/pose_template.dart';

class PoseFilters {
  String query = '',
      gender = 'all',
      category = 'all',
      scene = 'all',
      sort = 'catalog';
  bool get active =>
      query.isNotEmpty ||
      gender != 'all' ||
      category != 'all' ||
      scene != 'all' ||
      sort != 'catalog';
  void reset() {
    query = '';
    gender = 'all';
    category = 'all';
    scene = 'all';
    sort = 'catalog';
  }
}

class PoseLibraryViewModel extends ChangeNotifier {
  PoseLibraryViewModel(this.repository, {Random? random})
    : _random = random ?? Random();
  final PoseRepository repository;
  final Random _random;
  List<PoseTemplate> _builtIn = [], _custom = [];
  Set<String> _favorites = {};
  Map<String, int> _recents = {};
  final _mainFilters = PoseFilters(), _favoriteFilters = PoseFilters();
  final Map<String, String> loadErrors = {};
  bool _disposed = false;
  Future<void> _writes = Future.value();
  Future<void>? _loading;
  Future<void> settle() => _writes.catchError((Object _) {});
  List<PoseTemplate> get templates =>
      List.unmodifiable([..._builtIn, ..._custom]);
  List<PoseTemplate> get custom => List.unmodifiable(_custom);
  Set<String> get favorites => Set.unmodifiable(_favorites);
  Map<String, int> get recents => Map.unmodifiable(_recents);
  String get query => _mainFilters.query;
  String get gender => _mainFilters.gender;
  String get category => _mainFilters.category;
  List<String> get scenes =>
      templates.expand((pose) => pose.scenes).toSet().toList()..sort();
  PoseFilters filters({bool favoritesOnly = false}) =>
      favoritesOnly ? _favoriteFilters : _mainFilters;
  void _notify() {
    for (final filter in [_mainFilters, _favoriteFilters]) {
      if (filter.scene != 'all' && !scenes.contains(filter.scene)) {
        filter.scene = 'all';
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  Future<void> _load() async {
    await settle();
    final catalog = await repository.loadTemplates();
    if (_disposed) return;
    _builtIn = catalog;
    await Future.wait([
      _loadPart('favorites', () async {
        _favorites = await repository.loadFavorites();
      }),
      _loadPart('custom-poses-v1', () async {
        _custom = await repository.loadCustom();
      }),
      _loadPart('recent-poses-v1', () async {
        _recents = await repository.loadRecents();
      }),
    ]);
    _notify();
  }

  Future<void> _loadPart(String key, Future<void> Function() action) async {
    try {
      await action();
      loadErrors.remove(key);
    } catch (_) {
      loadErrors[key] = switch (key) {
        'favorites' => '收藏记录无法读取',
        'custom-poses-v1' => '自有参考无法读取',
        _ => '最近使用记录无法读取',
      };
    }
  }

  List<PoseTemplate> filtered({bool favoritesOnly = false}) {
    final f = filters(favoritesOnly: favoritesOnly);
    final result = templates
        .where(
          (pose) =>
              pose.matches(f.query, f.gender, f.category) &&
              (f.scene == 'all' || pose.scenes.contains(f.scene)) &&
              (!favoritesOnly || _favorites.contains(pose.id)),
        )
        .toList();
    if (f.sort == 'recent') {
      result.sort(
        (a, b) => (_recents[b.id] ?? 0).compareTo(_recents[a.id] ?? 0),
      );
    }
    if (f.sort == 'name') result.sort((a, b) => a.title.compareTo(b.title));
    if (f.sort == 'saved') {
      result.sort(
        (a, b) => (_favorites.contains(b.id) ? 1 : 0).compareTo(
          _favorites.contains(a.id) ? 1 : 0,
        ),
      );
    }
    return result;
  }

  PoseTemplate? find(String id, {String? title}) => templates
      .where((pose) => pose.id == id || id.isEmpty && pose.title == title)
      .firstOrNull;
  PoseTemplate? randomPose({
    bool favoritesOnly = false,
    bool onlySaved = false,
  }) {
    final choices = filtered(favoritesOnly: favoritesOnly)
        .where((pose) => !onlySaved || _favorites.contains(pose.id))
        .toList();
    return choices.isEmpty ? null : choices[_random.nextInt(choices.length)];
  }

  void setQuery(String value, {bool favoritesOnly = false}) {
    filters(favoritesOnly: favoritesOnly).query = value;
    _notify();
  }

  void setGender(String value, {bool favoritesOnly = false}) {
    filters(favoritesOnly: favoritesOnly).gender = value;
    _notify();
  }

  void setCategory(String value, {bool favoritesOnly = false}) {
    filters(favoritesOnly: favoritesOnly).category = value;
    _notify();
  }

  void setScene(String value, {bool favoritesOnly = false}) {
    filters(favoritesOnly: favoritesOnly).scene = value;
    _notify();
  }

  void setSort(String value, {bool favoritesOnly = false}) {
    filters(favoritesOnly: favoritesOnly).sort = value;
    _notify();
  }

  void resetFilters({bool favoritesOnly = false}) {
    filters(favoritesOnly: favoritesOnly).reset();
    _notify();
  }

  Future<void> _serialize(Future<void> Function() action) =>
      _writes = _writes.catchError((Object _) {}).then((_) async {
        await _loading;
        if (!_disposed) {
          await action();
          _notify();
        }
      });
  Future<void> toggleFavorite(String id) => _serialize(() async {
    if (loadErrors.containsKey('favorites')) throw StateError('请先恢复收藏记录');
    final next = {..._favorites};
    if (!next.add(id)) next.remove(id);
    await repository.saveFavorites(next);
    _favorites = next;
  });
  Future<void> markUsed(String id) => _serialize(() async {
    if (loadErrors.containsKey('recent-poses-v1')) return;
    final next = {..._recents, id: DateTime.now().millisecondsSinceEpoch};
    final entries = next.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final retained = Map.fromEntries(entries.take(100));
    await repository.saveRecents(retained);
    _recents = retained;
  });
  Future<void> addReference(
    String path,
    String title,
    String category,
    String gender,
  ) => _serialize(() async {
    if (loadErrors.containsKey('custom-poses-v1')) throw StateError('请先恢复自有参考');
    if (_custom.length >= 500) throw StateError('最多保存 500 个自有参考，请先备份或整理。');
    if (title.trim().isEmpty || title.trim().length > 80) {
      throw const FormatException('请输入 1 到 80 个字的参考名称');
    }
    final pose = await repository.createCustom(path, title, category, gender);
    try {
      final next = [..._custom, pose];
      await repository.saveCustom(next);
      _custom = next;
    } catch (_) {
      await repository.storage.deleteOwnedFile(pose.illustration);
      rethrow;
    }
  });
  Future<void> renameReference(
    PoseTemplate pose,
    String title, {
    String? category,
    String? gender,
  }) => _serialize(() async {
    if (loadErrors.containsKey('custom-poses-v1')) {
      throw StateError('请先恢复自有参考');
    }
    if (!pose.isUserReference ||
        title.trim().isEmpty ||
        title.trim().length > 80) {
      throw const FormatException('参考名称无效');
    }
    final next = _custom
        .map(
          (item) => item.id == pose.id
              ? PoseTemplate.fromJson({
                  ...item.raw,
                  'title': title.trim(),
                  'category': ?category,
                  'gender': ?gender,
                })
              : item,
        )
        .toList();
    await repository.saveCustom(next);
    _custom = next;
  });
  Future<void> deleteReference(PoseTemplate pose) => _serialize(() async {
    if (!pose.isUserReference) throw StateError('内置参考不能删除');
    if (loadErrors.isNotEmpty) throw StateError('请先恢复无法读取的记录');
    final next = _custom.where((item) => item.id != pose.id).toList(),
        saved = {..._favorites}..remove(pose.id);
    await repository.saveCustom(next, favorites: saved);
    _custom = next;
    _favorites = saved;
  });
  Future<void> resetRecord(String key) async {
    if (!loadErrors.containsKey(key)) return;
    await _serialize(() => repository.resetRecord(key));
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
