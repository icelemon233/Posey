import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/settings/settings_view_model.dart';

class OnboardingCard extends StatelessWidget {
  const OnboardingCard({super.key, required this.model});
  final SettingsViewModel model;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => model.onboardingSeen
        ? const SizedBox.shrink()
        : Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: ExpansionTile(
              title: const Text('使用说明'),
              leading: const Icon(Icons.info_outline),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                const Text(
                  '选择参考后拍照，或导入已有照片。作品会留存在本机，可以编辑、对比、分享并保存到系统相册。AI 生成为可选功能，需配置自己的服务。',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        runUiAction(context, model.completeOnboarding),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
  );
}
