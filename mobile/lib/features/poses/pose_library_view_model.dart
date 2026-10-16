import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:posey/features/poses/pose_repository.dart';
import 'package:posey/features/poses/pose_template.dart';

class PoseLibraryViewModel extends ChangeNotifier {
  PoseLibraryViewModel(this.repository, {Random? random})
    : _random = random ?? Random();
  final PoseRepository repository;
  final Random _random;
  List<PoseTemplate> _templates = [];
  Set<String> _favorites = {};
  String _query = '', _gender = 'all', _category = 'all';
  bool _disposed = false;
  Future<void> _writes = Future.value();

  List<PoseTemplate> get templates => List.unmodifiable(_templates);
  Set<String> get favorites => Set.unmodifiable(_favorites);
  String get query => _query;
  String get gender => _gender;
  String get category => _category;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final results = await Future.wait<Object>([
      repository.loadTemplates(),
      repository.loadFavorites(),
    ]);
    if (_disposed) return;
    _templates = results[0] as List<PoseTemplate>;
    _favorites = results[1] as Set<String>;
    _notify();
  }

  List<PoseTemplate> filtered({bool favoritesOnly = false}) => _templates
      .where(
        (pose) =>
            pose.matches(_query, _gender, _category) &&
            (!favoritesOnly || _favorites.contains(pose.id)),
      )
      .toList();

  PoseTemplate? find(String id, {String? title}) {
    final byId = _templates.where((pose) => pose.id == id);
    if (byId.isNotEmpty) return byId.first;
    if (id.isEmpty && title != null) {
      final byTitle = _templates.where((pose) => pose.title == title);
      if (byTitle.isNotEmpty) return byTitle.first;
    }
    return null;
  }

  PoseTemplate? randomPose({
    bool favoritesOnly = false,
    bool onlySaved = false,
  }) {
    final choices = filtered(favoritesOnly: favoritesOnly || onlySaved);
    return choices.isEmpty ? null : choices[_random.nextInt(choices.length)];
  }

  void setQuery(String value) {
    _query = value;
    _notify();
  }

  void setGender(String value) {
    _gender = value;
    _notify();
  }

  void setCategory(String value) {
    _category = value;
    _notify();
  }

  Future<void> toggleFavorite(String id) =>
      _writes = _writes.catchError((Object _) {}).then((_) async {
        if (_disposed) return;
        final next = {..._favorites};
        if (!next.add(id)) next.remove(id);
        await repository.saveFavorites(next);
        if (_disposed) return;
        _favorites = next;
        _notify();
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
