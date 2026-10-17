import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:posey/core/json.dart';

class DevicePlatform {
  DevicePlatform({
    this.channel = const MethodChannel('com.posey.camera/platform'),
  }) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openJob' && call.arguments is String) {
        _openedJobs.add(call.arguments as String);
      }
    });
  }
  final MethodChannel channel;
  bool get supported => Platform.isAndroid || Platform.isIOS;
  final _openedJobs = StreamController<String>.broadcast();
  Stream<String> get openedJobs => _openedJobs.stream;
  Future<void> openSettings() => channel.invokeMethod('openSettings');
  Future<bool> requestNotifications({bool force = false}) async =>
      await channel.invokeMethod<bool>('requestNotifications', {
        'force': force,
      }) ??
      false;
  Future<void> shareFiles(List<String> paths) =>
      channel.invokeMethod('shareFiles', {'paths': paths});
  Future<bool> exportFile(String name, String path) async =>
      await channel.invokeMethod<bool>('exportFile', {
        'name': name,
        'path': path,
      }) ??
      false;
  Future<String?> importFile() => channel.invokeMethod<String>('importFile');
  Future<Json> appInfo() async =>
      objectOf(await channel.invokeMethod('appInfo'));
  Future<int> clearTemporaryFiles() async =>
      await channel.invokeMethod<int>('clearTemporaryFiles') ?? 0;
  Future<Json> storageUsage() async =>
      objectOf(await channel.invokeMethod('storageUsage'));
  Future<String?> pendingJob() => channel.invokeMethod<String>('pendingJob');
  Future<void> dispose() async {
    channel.setMethodCallHandler(null);
    await _openedJobs.close();
  }
}
