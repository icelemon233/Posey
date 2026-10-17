import 'package:flutter/material.dart';
import 'package:posey/core/ui/posey_theme.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/settings/settings_view_model.dart';
import 'package:posey/features/settings/ai_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.viewModel});
  final SettingsViewModel viewModel;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('让 Posey 更像你', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('AI Pose 设置'),
            subtitle: Text(
              viewModel.configuration.normalizedKey.isEmpty
                  ? '连接你的火山方舟账户'
                  : '已保存设备密钥',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AiSettingsScreen(viewModel: viewModel),
              ),
            ),
          ),
        ),
        Card(
          child: SwitchListTile(
            title: const Text('随心拍只从收藏中选'),
            subtitle: const Text('仍遵循当前的性别与姿势筛选'),
            value: viewModel.shuffleFavorites,
            onChanged: (value) => runUiAction(
              context,
              () => viewModel.setShuffleFavorites(value),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('首页主题', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: homeThemes.containsKey(viewModel.theme)
              ? viewModel.theme
              : 'sunny-cream',
          onChanged: (value) {
            if (value != null) {
              runUiAction(context, () => viewModel.setTheme(value));
            }
          },
          child: Column(
            children: homeThemes.entries
                .map(
                  (entry) => Card(
                    child: RadioListTile<String>(
                      title: Text(entry.value.$1),
                      secondary: CircleAvatar(
                        backgroundColor: entry.value.$2,
                        radius: 12,
                      ),
                      value: entry.key,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
        const Text('关于 Posey', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('50 个原创姿势参考。使用相机叠加参考图，或用 AI Pose 调整已有照片。参考图不会出现在你拍摄的成片里。'),
        const SizedBox(height: 16),
        const Text('照片与隐私', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          '拍摄、收藏和参考图在本机处理。只有你确认 AI 生成后，选中的照片才会发送到配置的服务。API Key 保存在此设备的系统安全存储中。'
          '移除任务只清理应用中的副本，已保存到系统相册的照片由你管理。',
        ),
        const SizedBox(height: 20),
        const Text('Posey · Flutter 0.2.1', textAlign: TextAlign.center),
      ],
    ),
  );
}
