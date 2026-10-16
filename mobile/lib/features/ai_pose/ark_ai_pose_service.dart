import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:posey/core/json.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';

Uint8List resizeForAi(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法读取这张图片');
  final oriented = image.bakeOrientation(decoded);
  final largest = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final resized = largest > 2048
      ? image.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 2048 : null,
          height: oriented.height > oriented.width ? 2048 : null,
        )
      : oriented;
  return Uint8List.fromList(image.encodeJpg(resized, quality: 90));
}

class PreparedAiRequest {
  const PreparedAiRequest(this.configuration, this.body, this.title);
  final AiConfiguration configuration;
  final Json body;
  final String title;
  Json nativePayload() => {
    'apiKey': configuration.normalizedKey,
    'endpoint': configuration.uri.toString(),
    'model': configuration.model,
    'sourceImage': (body['image'] as List)[0],
    'guideImage': (body['image'] as List)[1],
    'prompt': body['prompt'],
    'targetTitle': title,
  };
}

abstract interface class AiPoseService {
  Future<PreparedAiRequest> prepare(
    AiConfiguration configuration,
    AiPreferences preferences,
    PoseTemplate target,
    Uint8List source,
  );
  Future<Uint8List> generate(String jobId, PreparedAiRequest request);
  void cancel(String jobId);
}

class ArkAiPoseService implements AiPoseService {
  ArkAiPoseService({
    http.Client Function()? clientFactory,
    Future<ByteData> Function(String)? assetLoader,
  }) : clientFactory = clientFactory ?? http.Client.new,
       assetLoader = assetLoader ?? rootBundle.load;
  final http.Client Function() clientFactory;
  final Future<ByteData> Function(String) assetLoader;
  final _clients = <String, http.Client>{};
  @override
  Future<PreparedAiRequest> prepare(
    AiConfiguration configuration,
    AiPreferences preferences,
    PoseTemplate target,
    Uint8List source,
  ) async {
    configuration.validate();
    final guide = await assetLoader(target.illustration);
    final sourceBytes = await compute(resizeForAi, source),
        guideBytes = await compute(
          resizeForAi,
          guide.buffer.asUint8List(guide.offsetInBytes, guide.lengthInBytes),
        );
    return PreparedAiRequest(configuration, {
      'model': configuration.model,
      'prompt': buildPosePrompt(target.title, preferences),
      'image': [
        'data:image/jpeg;base64,${base64Encode(sourceBytes)}',
        'data:image/jpeg;base64,${base64Encode(guideBytes)}',
      ],
      'size': '2K',
      'output_format': 'jpeg',
      'response_format': 'b64_json',
      'watermark': false,
    }, target.title);
  }

  @override
  Future<Uint8List> generate(String jobId, PreparedAiRequest request) async {
    final client = clientFactory();
    _clients[jobId] = client;
    try {
      final response = await client
          .post(
            request.configuration.uri,
            headers: {
              'Authorization': 'Bearer ${request.configuration.normalizedKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(request.body),
          )
          .timeout(const Duration(minutes: 5));
      Json payload = {};
      try {
        payload = objectOf(jsonDecode(utf8.decode(response.bodyBytes)));
      } catch (_) {
        /* A generic error follows for non-JSON responses. */
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = '${objectOf(payload['error'])['code'] ?? ''}';
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw StateError('AI 服务鉴权失败，请检查 API Key 和模型权限');
        }
        if (response.statusCode == 429) throw StateError('AI Pose 现在有点忙，请稍后再试');
        if (RegExp(
          'sensitive|moderation',
          caseSensitive: false,
        ).hasMatch(code)) {
          throw StateError('当前画面无法生成，请换一个画面再试');
        }
        throw StateError('AI Pose 暂时生成失败，请稍后重试');
      }
      final data = payload['data'];
      if (data is! List || data.isEmpty) throw StateError('AI 没有返回可用图片');
      final item = objectOf(data.first);
      Uint8List result;
      if (item['b64_json'] is String) {
        result = base64Decode(item['b64_json'] as String);
      } else if (item['url'] is String) {
        final uri = Uri.parse(item['url'] as String);
        if (uri.scheme != 'https') throw StateError('AI 返回的图片地址不安全');
        final imageResponse = await client
            .get(uri)
            .timeout(const Duration(seconds: 45));
        if (imageResponse.statusCode != 200) throw StateError('AI 返回图片读取失败');
        result = imageResponse.bodyBytes;
      } else {
        throw StateError('AI 没有返回可用图片');
      }
      if (image.decodeImage(result) == null) throw StateError('AI 返回的图片格式无效');
      return result;
    } finally {
      _clients.remove(jobId);
      client.close();
    }
  }

  @override
  void cancel(String jobId) {
    _clients.remove(jobId)?.close();
  }
}
