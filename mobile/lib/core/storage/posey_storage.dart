import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class StoredMediaFile {
  const StoredMediaFile(this.path, this.bytes);
  final String path;
  final int bytes;
}

abstract interface class PoseyStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> recordKeys();
  Future<String?> readApiKey();
  Future<void> writeApiKey(String value);
  Future<String?> readSecret(String name);
  Future<void> writeSecret(String name,String? value);
  Future<String> saveBytes(String fileName, Uint8List bytes);
  Future<void> deleteOwnedFile(String path);
  Future<Uint8List> readOwnedFile(String path);
  Future<List<StoredMediaFile>> mediaFiles();
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
  Future<Set<String>> recordKeys() async => preferences
      .getKeys()
      .where((key) => key.startsWith('posey.flutter.'))
      .map((key) => key.substring('posey.flutter.'.length))
      .toSet();
  @override
  Future<void> remove(String key) async {
    try{if(await preferences.remove('posey.flutter.$key'))return;}catch(_){/* Reload the persisted cache below. */}
    try{await preferences.reload();}catch(_){/* Keep the failure visible. */}
    throw StateError('设备资料未能移除，请重试。');
  }

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
  Future<String?> readSecret(String name)=>secure.read(key:'posey.secret.$name');
  @override
  Future<void> writeSecret(String name,String? value) async {
    if(!RegExp(r'^[a-zA-Z0-9_.-]{1,120}$').hasMatch(name))throw const FormatException('私密记录编号无效');
    if(value==null){await secure.delete(key:'posey.secret.$name');}else{await secure.write(key:'posey.secret.$name',value:value);}
  }
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
    final temporary = File('${file.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      return file.path;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  bool _owns(String path) =>
      File(path).absolute.uri.normalizePath().resolve('.') ==
      directory.absolute.uri.normalizePath().resolve('./');

  @override
  Future<Uint8List> readOwnedFile(String path) {
    if (!_owns(path)) throw const FormatException('文件不属于本应用');
    return File(path).readAsBytes();
  }

  @override
  Future<List<StoredMediaFile>> mediaFiles() async {
    final result = <StoredMediaFile>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && !entity.path.endsWith('.tmp')) {
        result.add(StoredMediaFile(entity.path, await entity.length()));
      }
    }
    return result;
  }

  @override
  Future<void> deleteOwnedFile(String path) async {
    final file = File(path);
    if (!_owns(path)) return;
    if (await file.exists()) await file.delete();
  }
}
