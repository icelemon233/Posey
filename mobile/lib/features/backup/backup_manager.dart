import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:posey/core/media/device_platform.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/backup/backup_archive.dart';

class BackupManager extends ChangeNotifier {
  BackupManager({
    required this.storage,
    required this.platform,
    required this.snapshot,
    required this.assets,
    required this.apply,
    required this.canImport,
    required this.statistics,
    required this.cleanup,
  });
  final PoseyStorage storage;
  final DevicePlatform platform;
  final Future<BackupSnapshot> Function(int? workLimit) snapshot;
  final Set<String> Function() assets;
  final Future<Set<String>> Function(DecodedBackup, bool restoreInterface)
  apply;
  final bool Function() canImport;
  final Future<Map<String, int>> Function() statistics;
  final Future<int> Function() cleanup;
  bool busy = false, _disposed = false;
  String? message;
  DecodedBackup? candidate;
  String? _input;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    if (busy) throw StateError('请等待当前备份操作完成');
    busy = true;
    message = null;
    _notify();
    try {
      return await action();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> export({int? workLimit}) => _run(() async {
    final data = await snapshot(workLimit);
    final path = await storage.saveBytes(
      'backup-export-${const Uuid().v4()}.zip',
      Uint8List(0),
    );
    try {
      final files = await storage.mediaFiles();
      final encoding = prepareBackup(
        data,
        path,
        files.map((file) => file.path).toSet(),
      );
      await compute(encodeBackup, encoding);
      final result = await platform.exportFile(
        'Posey-backup-${DateTime.now().toIso8601String().substring(0, 10)}.zip',
        path,
      );
      message = result ? '备份已导出' : '已取消导出';
      return result;
    } finally {
      await storage.deleteOwnedFile(path);
    }
  });
  Future<DecodedBackup?> prepareImport() => _run(() async {
    if (!canImport()) throw StateError('任务仍在生成或同步，请完成后再导入备份。');
    await cancelImport();
    final path = await platform.importFile();
    if (path == null) return null;
    _input = path;
    final marker = await storage.saveBytes(
      'backup-import-marker-${const Uuid().v4()}.tmp',
      Uint8List(0),
    );
    final directory = File(marker).parent.path;
    await storage.deleteOwnedFile(marker);
    try {
      candidate = await compute(
        decodeBackup,
        BackupDecoding(path, directory, const Uuid().v4(), assets()),
      );
      return candidate;
    } on FormatException catch (error) {
      await cancelImport();
      throw FormatException(error.message);
    } catch (_) {
      await cancelImport();
      throw const FormatException('备份读取或校验失败，未开始导入。');
    }
  });
  Future<void> applyImport({required bool restoreInterface}) => _run(() async {
    final data = candidate;
    if (data == null) throw StateError('请先选择备份文件');
    if (!canImport()) throw StateError('任务仍在生成或同步，请完成后再导入备份。');
    final used = await apply(data, restoreInterface);
    for (final path in data.files.values) {
      if (!used.contains(path)) await storage.deleteOwnedFile(path);
    }
    candidate = null;
    await _deleteInput();
    message = '备份已合并，已有编号保留当前内容。';
  });
  Future<void> _deleteInput() async {
    final path = _input;
    _input = null;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> cancelImport() async {
    final data = candidate;
    candidate = null;
    if (data != null && await storage.read('pending-transaction-v1') == null) {
      for (final path in data.files.values) {
        await storage.deleteOwnedFile(path);
      }
    }
    await _deleteInput();
  }

  Future<int> clearTemporary() => _run(() async {
    if (candidate != null) throw StateError('请先导入或取消已选择的备份。');
    final bytes = await cleanup();
    message = '已清理 ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB 临时文件';
    return bytes;
  });
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
