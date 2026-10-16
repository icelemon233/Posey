import 'dart:convert';

import 'package:posey/core/json.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';

class SavedSettings {
  const SavedSettings({
    this.theme = 'sunny-cream',
    this.shuffleFavorites = false,
    this.configuration = const AiConfiguration(),
    this.preferences = const AiPreferences(),
  });
  final String theme;
  final bool shuffleFavorites;
  final AiConfiguration configuration;
  final AiPreferences preferences;
}

class SettingsRepository {
  const SettingsRepository(this.storage);
  final PoseyStorage storage;

  Future<SavedSettings> load() async {
    final values = await Future.wait<String?>([
      storage.read('theme'),
      storage.read('shuffle-favorites'),
      storage.read('ai-config'),
      storage.read('ai-preferences'),
      storage.readApiKey(),
    ]);
    final metadata = objectOf(jsonDecode(values[2] ?? '{}'));
    return SavedSettings(
      theme: values[0] ?? 'sunny-cream',
      shuffleFavorites: values[1] == 'true',
      configuration: AiConfiguration(
        key: values[4] ?? '',
        endpoint:
            metadata['endpoint'] as String? ?? const AiConfiguration().endpoint,
        model: metadata['model'] as String? ?? const AiConfiguration().model,
      ),
      preferences: AiPreferences.fromJson(
        objectOf(jsonDecode(values[3] ?? '{}')),
      ),
    );
  }

  Future<void> saveTheme(String value) => storage.write('theme', value);
  Future<void> saveShuffle(bool value) =>
      storage.write('shuffle-favorites', '$value');

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
      // Preferences and secure storage do not share a transaction. Restore both
      // before reporting failure so a new endpoint cannot inherit an old key.
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
}
