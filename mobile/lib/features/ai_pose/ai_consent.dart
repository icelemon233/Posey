import 'package:flutter/material.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';

Future<bool> confirmAiGeneration(
  BuildContext context, {
  required AiRequestOptions options,
  required String poseTitle,
  bool retry = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(retry ? '再次生成？' : '使用 AI 生成？'),
        scrollable: true,
        content: Text(
          '所选照片和“$poseTitle”参考会发送到 ${options.configuration.uri.host}。\n'
          '模型：${options.configuration.model}\n\n'
          '本次生成可能产生服务费用。面部、表情和背景的保留取决于模型结果，请生成后与原图对比。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('同意并生成'),
          ),
        ],
      ),
    ) ??
    false;
