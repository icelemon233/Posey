import 'package:flutter/foundation.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/camera/camera_preferences.dart';
import 'package:posey/features/settings/settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this.repository);
  final SettingsRepository repository;
  SavedSettings _settings = const SavedSettings();
  Future<void> _writes = Future.value();
  Future<void> settle() => _writes.catchError((Object _) {});
  bool _disposed = false;
  String? loadError;
  String get theme => _settings.theme;
  String get themeMode => _settings.themeMode;
  bool get shuffleFavorites => _settings.shuffleFavorites;
  bool get onboardingSeen => _settings.onboardingSeen;
  CameraPreferences get camera => _settings.camera;
  AiConfiguration get configuration => _settings.configuration;
  AiPreferences get preferences => _settings.preferences;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      final next = await repository.load();
      if (_disposed) return;
      _settings = next;
      loadError = null;
    } catch (_) {
      loadError = '设置无法读取。请重试，或备份后重置设置。';
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> _serialize(Future<void> Function() action) =>
      _writes = _writes.catchError((Object _) {}).then((_) async {
        if (_disposed) return;
        if (loadError != null) throw StateError('请先恢复设置记录');
        await action();
        _notify();
      });
  Future<void> setTheme(String value) => _serialize(() async {
    await repository.saveTheme(value);
    _settings = _settings.copyWith(theme: value);
  });
  Future<void> setThemeMode(String value) => _serialize(() async {
    await repository.saveThemeMode(value);
    _settings = _settings.copyWith(themeMode: value);
  });
  Future<void> setShuffleFavorites(bool value) => _serialize(() async {
    await repository.saveShuffle(value);
    _settings = _settings.copyWith(shuffleFavorites: value);
  });
  Future<void> completeOnboarding() => _serialize(() async {
    await repository.saveOnboarding();
    _settings = _settings.copyWith(onboardingSeen: true);
  });
  Future<void> setCameraPreferences(CameraPreferences value) =>
      _serialize(() async {
        await repository.saveCamera(value);
        _settings = _settings.copyWith(camera: value);
      });
  Future<void> saveConfiguration(AiConfiguration value, AiPreferences next) =>
      _serialize(() async {
        await repository.saveAi(value, next);
        _settings = _settings.copyWith(configuration: value, preferences: next);
      });
  Future<void> resetUnreadable() async {
    if (loadError == null) return;
    await repository.resetUnreadable();
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
