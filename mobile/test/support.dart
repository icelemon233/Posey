import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';

class TestStorage implements PoseyStorage {
  TestStorage(this.directory);
  final Directory directory;
  final data = <String, String>{};
  String? key;
  final deleted = <String>[];
  @override
  Future<String?> read(String name) async => data[name];
  @override
  Future<void> write(String name, String value) async {
    data[name] = value;
  }

  @override
  Future<String?> readApiKey() async => key;
  @override
  Future<void> writeApiKey(String value) async {
    key = value;
  }

  @override
  Future<String> saveBytes(String name, Uint8List bytes) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<void> deleteOwnedFile(String path) async {
    deleted.add(path);
    if (path.isNotEmpty && await File(path).exists()) await File(path).delete();
  }
}

class DelayedService implements AiPoseService {
  Completer<void>? prepareGate;
  int prepares = 0;
  final pending = <String, Completer<Uint8List>>{};
  final requests = <String, PreparedAiRequest>{};
  final cancelled = <String>[];
  @override
  Future<PreparedAiRequest> prepare(
    AiConfiguration config,
    AiPreferences preferences,
    PoseTemplate target,
    Uint8List source,
  ) async {
    prepares++;
    await prepareGate?.future;
    return PreparedAiRequest(config, {
      'prompt': buildPosePrompt(target.title, preferences),
      'image': ['source', 'guide'],
    }, target.title);
  }

  @override
  Future<Uint8List> generate(String id, PreparedAiRequest request) {
    requests[id] = request;
    return (pending[id] = Completer<Uint8List>()).future;
  }

  @override
  void cancel(String id) {
    cancelled.add(id);
  }
}
