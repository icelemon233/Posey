import 'dart:io';

import 'package:flutter/services.dart';
import 'package:posey/core/json.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';

class NativeBackgroundAi {
  const NativeBackgroundAi({
    this.channel = const MethodChannel('com.posey.camera/background-ai'),
  });
  final MethodChannel channel;
  bool get supported => Platform.isIOS;
  Future<String> start(PreparedAiRequest request) async {
    final response = objectOf(
      await channel.invokeMethod('start', request.nativePayload()),
    );
    final id = response['jobId'];
    if (id is! String || id.isEmpty) throw const FormatException('后台任务未返回有效标识');
    return id;
  }

  Future<List<Json>> jobs({List<String> knownResults = const []}) async {
    final response = objectOf(
      await channel.invokeMethod('getJobs', {'knownResults': knownResults}),
    );
    final records = response['jobs'];
    if (records is! List) throw const FormatException('后台任务响应格式无效');
    return records.map((value) {
      final record = objectOf(value);
      if (record['id'] is! String ||
          (record['id'] as String).isEmpty ||
          record['state'] is! String) {
        throw const FormatException('后台任务记录不完整');
      }
      return record;
    }).toList();
  }

  Future<void> cancel(String id) =>
      channel.invokeMethod('cancel', {'jobId': id});
  Future<void> clear(String id) => channel.invokeMethod('clear', {'jobId': id});
}
