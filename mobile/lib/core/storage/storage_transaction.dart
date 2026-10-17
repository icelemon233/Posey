import 'dart:convert';

import 'package:posey/core/storage/posey_storage.dart';

const _journalKey = 'pending-transaction-v1';
final _transactions = Expando<Future<void>>();
Future<void> recoverStorageTransaction(PoseyStorage storage) async {
  final raw = await storage.read(_journalKey);
  if (raw == null) return;
  final json = jsonDecode(raw);
  if (json is! Map || json['version'] != 1 || json['before'] is! Map) {
    throw const FormatException('资料恢复记录无法读取，请保留应用资料后重试。');
  }
  for (final entry in (json['before'] as Map).entries) {
    if (entry.key is! String ||
        entry.key == _journalKey ||
        (entry.value != null && entry.value is! String)) {
      throw const FormatException('资料恢复记录格式无效');
    }
  }
  for (final entry in (json['before'] as Map).entries) {
    if (entry.value == null) {
      await storage.remove(entry.key);
    } else {
      await storage.write(entry.key, entry.value);
    }
  }
  await storage.remove(_journalKey);
}

// Callers serialize operations on these keys. The journal survives process death.
Future<void> writeStorageBatch(
  PoseyStorage storage,
  Map<String, String> values,
) async {
  final operation = (_transactions[storage] ?? Future<void>.value())
      .catchError((Object _) {})
      .then((_) => _writeStorageBatch(storage, values));
  _transactions[storage] = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  return operation;
}

Future<void> _writeStorageBatch(
  PoseyStorage storage,
  Map<String, String> values,
) async {
  if (values.containsKey(_journalKey)) {
    throw ArgumentError('Reserved storage key');
  }
  await recoverStorageTransaction(storage);
  final before = <String, String?>{};
  for (final key in values.keys) {
    before[key] = await storage.read(key);
  }
  await storage.write(
    _journalKey,
    jsonEncode({'version': 1, 'before': before}),
  );
  try {
    for (final entry in values.entries) {
      await storage.write(entry.key, entry.value);
    }
    await storage.remove(_journalKey);
  } catch (_) {
    await recoverStorageTransaction(storage);
    rethrow;
  }
}
