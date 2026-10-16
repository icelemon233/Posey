import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PoseyStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<String?> readApiKey();
  Future<void> writeApiKey(String value);
  Future<String> saveBytes(String fileName, Uint8List bytes);
  Future<void> deleteOwnedFile(String path);
}

class DevicePoseyStorage implements PoseyStorage {
  DevicePoseyStorage(
    this.preferences,
    this.directory, {
    FlutterSecureStorage? secure,
  }) : secure = secure ?? const FlutterSecureStorage();
  final SharedPreferences preferences;
  final Directory directory;
  final FlutterSecureStorage secure;
  static Future<DevicePoseyStorage> open() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/posey');
    await directory.create(recursive: true);
    return DevicePoseyStorage(await SharedPreferences.getInstance(), directory);
  }

  @override
  Future<String?> read(String key) async =>
      preferences.getString('posey.flutter.$key');
  @override
  Future<void> write(String key, String value) async {
    try {
      if (await preferences.setString('posey.flutter.$key', value)) return;
    } catch (_) {
      // The plugin can report failure through either its result or an exception.
    }
    try {
      await preferences.reload();
    } catch (_) {
      // Keep the failure visible even when the persisted cache cannot be reread.
    }
    throw StateError('设备资料未能保存，请重试。');
  }

  @override
  Future<String?> readApiKey() => secure.read(key: 'posey.ark-api-key');
  @override
  Future<void> writeApiKey(String value) async {
    if (value.isEmpty) {
      await secure.delete(key: 'posey.ark-api-key');
    } else {
      await secure.write(key: 'posey.ark-api-key', value: value);
    }
  }

  @override
  Future<String> saveBytes(String fileName, Uint8List bytes) async {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$').hasMatch(fileName)) {
      throw const FormatException('图片文件名无效');
    }
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> deleteOwnedFile(String path) async {
    final file = File(path);
    if (file.absolute.uri.normalizePath().resolve('.') !=
        directory.absolute.uri.normalizePath().resolve('./')) {
      return;
    }
    if (await file.exists()) await file.delete();
  }
}
