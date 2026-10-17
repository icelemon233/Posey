import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/core/storage/storage_transaction.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/camera/camera_preferences.dart';

class SavedSettings {
  const SavedSettings({
    this.theme = 'sunny-cream',
    this.themeMode = 'system',
    this.shuffleFavorites = false,
    this.onboardingSeen = false,
    this.configuration = const AiConfiguration(),
    this.preferences = const AiPreferences(),
    this.camera = const CameraPreferences(),
  });
  final String theme, themeMode;
  final bool shuffleFavorites, onboardingSeen;
  final AiConfiguration configuration;
  final AiPreferences preferences;
  final CameraPreferences camera;
  SavedSettings copyWith({
    String? theme,
    String? themeMode,
    bool? shuffleFavorites,
    bool? onboardingSeen,
    AiConfiguration? configuration,
    AiPreferences? preferences,
    CameraPreferences? camera,
  }) => SavedSettings(
    theme: theme ?? this.theme,
    themeMode: themeMode ?? this.themeMode,
    shuffleFavorites: shuffleFavorites ?? this.shuffleFavorites,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    configuration: configuration ?? this.configuration,
    preferences: preferences ?? this.preferences,
    camera: camera ?? this.camera,
  );
}

const settingsKeys = [
  'theme',
  'theme-mode',
  'shuffle-favorites',
  'onboarding-seen',
  'ai-config',
  'ai-preferences',
  'camera-preferences-v1',
];

class SettingsRepository {
  const SettingsRepository(this.storage);
  final PoseyStorage storage;
  Future<SavedSettings> load() async {
    final values = await Future.wait<String?>([
      for (final key in settingsKeys) storage.read(key),
      storage.readApiKey(),
    ]);
    Json object(String? raw) {
      final parsed = jsonDecode(raw ?? '{}');
      if (parsed is! Map) throw const FormatException('设置记录格式无效');
      return objectOf(parsed);
    }

    final metadata = object(values[4]),
        prefs = object(values[5]),
        camera = object(values[6]);
    final mode = values[1] ?? 'system';
    if (!['system', 'light', 'dark'].contains(mode))
      throw const FormatException('主题模式无效');
    return SavedSettings(
      theme: values[0] ?? 'sunny-cream',
      themeMode: mode,
      shuffleFavorites: values[2] == 'true',
      onboardingSeen: values[3] == 'true',
      configuration: AiConfiguration(
        key: values[7] ?? '',
        endpoint:
            metadata['endpoint'] as String? ?? const AiConfiguration().endpoint,
        model: metadata['model'] as String? ?? const AiConfiguration().model,
      ),
      preferences: AiPreferences.fromJson(prefs),
      camera: CameraPreferences.fromJson(camera),
    );
  }

  Future<void> saveTheme(String value) => storage.write('theme', value);
  Future<void> saveThemeMode(String value) {
    if (!['system', 'light', 'dark'].contains(value))
      throw const FormatException('主题模式无效');
    return storage.write('theme-mode', value);
  }

  Future<void> saveShuffle(bool value) =>
      storage.write('shuffle-favorites', '$value');
  Future<void> saveOnboarding() => storage.write('onboarding-seen', 'true');
  Future<void> saveCamera(CameraPreferences value) =>
      storage.write('camera-preferences-v1', jsonEncode(value.toJson()));
  Future<void> saveAi(
    AiConfiguration configuration,
    AiPreferences preferences,
  ) async {
    if (configuration.normalizedKey.isNotEmpty) configuration.validate();
    final previous = await Future.wait<String?>([
      storage.readApiKey(),
      storage.read('ai-config'),
      storage.read('ai-preferences'),
    ]);
    try {
      await storage.writeApiKey(configuration.normalizedKey);
      await storage.write('ai-config', jsonEncode(configuration.metadata()));
      await storage.write('ai-preferences', jsonEncode(preferences.toJson()));
    } catch (_) {
      try {
        await storage.writeApiKey(previous[0] ?? '');
        await storage.write('ai-config', previous[1] ?? '{}');
        await storage.write('ai-preferences', previous[2] ?? '{}');
      } catch (_) {
        throw StateError('设置保存失败，请重新打开设置并核对服务地址和密钥。');
      }
      rethrow;
    }
  }

  Future<void> resetUnreadable() async {
    final original = <String, String?>{};
    for (final key in settingsKeys) {
      original[key] = await storage.read(key);
    }
    await storage.write(
      'settings-recovery-${const Uuid().v4()}',
      jsonEncode(original),
    );
    // A reset never pairs an old credential with a reset service endpoint.
    await storage.writeApiKey('');
    await writeStorageBatch(storage, {
      'theme': 'sunny-cream',
      'theme-mode': 'system',
      'shuffle-favorites': 'false',
      'onboarding-seen': 'false',
      'ai-config': jsonEncode(const AiConfiguration().metadata()),
      'ai-preferences': jsonEncode(const AiPreferences().toJson()),
      'camera-preferences-v1': '{}',
    });
  }
}
