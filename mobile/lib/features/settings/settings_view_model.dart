import 'package:flutter/foundation.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/settings/settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this.repository);
  final SettingsRepository repository;
  SavedSettings _settings = const SavedSettings();
  Future<void> _writes = Future.value();
  bool _disposed = false;
  String get theme => _settings.theme;
  bool get shuffleFavorites => _settings.shuffleFavorites;
  AiConfiguration get configuration => _settings.configuration;
  AiPreferences get preferences => _settings.preferences;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final next = await repository.load();
    if (_disposed) return;
    _settings = next;
    _notify();
  }

  Future<void> _serialize(Future<void> Function() action) =>
      _writes = _writes.catchError((Object _) {}).then((_) async {
        if (!_disposed) await action();
      });

  Future<void> setTheme(String value) => _serialize(() async {
    await repository.saveTheme(value);
    _settings = SavedSettings(
      theme: value,
      shuffleFavorites: shuffleFavorites,
      configuration: configuration,
      preferences: preferences,
    );
    _notify();
  });

  Future<void> setShuffleFavorites(bool value) => _serialize(() async {
    await repository.saveShuffle(value);
    _settings = SavedSettings(
      theme: theme,
      shuffleFavorites: value,
      configuration: configuration,
      preferences: preferences,
    );
    _notify();
  });

  Future<void> saveConfiguration(AiConfiguration value, AiPreferences next) =>
      _serialize(() async {
        await repository.saveAi(value, next);
        _settings = SavedSettings(
          theme: theme,
          shuffleFavorites: shuffleFavorites,
          configuration: value,
          preferences: next,
        );
        _notify();
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
