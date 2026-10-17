import 'package:flutter/material.dart';
import 'package:posey/core/ui/posey_theme.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/settings/settings_view_model.dart';
import 'package:posey/features/settings/settings_recovery.dart';
import 'package:posey/features/settings/ai_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.viewModel,
    this.onConfigureAi,
    this.onBackup,
    this.onOpenSettings,
    this.onNotifications,
    this.onRecoverImport,
    this.importError,
    this.deviceInfo,
    this.onClearTasks,
  });
  final SettingsViewModel viewModel;
  final Future<void> Function()? onConfigureAi,
      onBackup,
      onOpenSettings,
      onNotifications,
      onRecoverImport,
      onClearTasks;
  final String? importError;
  final Future<Map<String, dynamic>>? deviceInfo;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SettingsRecovery(model: viewModel),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('AI 设置'),
          subtitle: Text(
            viewModel.configuration.normalizedKey.isEmpty ? '未配置服务' : '已保存设备密钥',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              onConfigureAi?.call() ??
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AiSettingsScreen(viewModel: viewModel),
                ),
              ),
        ),
        if (onBackup != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份与存储'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onBackup,
          ),
        if (onOpenSettings != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_applications_outlined),
            title: const Text('系统权限'),
            subtitle: const Text('相机、相册与通知'),
            onTap: () => runUiAction(context, onOpenSettings!),
          ),
        if (onNotifications != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('允许任务通知'),
            onTap: () => runUiAction(context, onNotifications!),
          ),
        if (importError != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(importError!),
            trailing: TextButton(
              onPressed: onRecoverImport,
              child: const Text('重试恢复'),
            ),
          ),
        if (onClearTasks != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清理任务副本'),
            subtitle: const Text('作品与系统相册保留'),
            onTap: onClearTasks,
          ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('随机参考只从收藏中选'),
          subtitle: const Text('遵循当前筛选'),
          value: viewModel.shuffleFavorites,
          onChanged: viewModel.loadError != null
              ? null
              : (value) => runUiAction(
                  context,
                  () => viewModel.setShuffleFavorites(value),
                ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(viewModel.themeMode),
          initialValue: viewModel.themeMode,
          decoration: const InputDecoration(labelText: '外观'),
          items: const [
            DropdownMenuItem(value: 'system', child: Text('跟随系统')),
            DropdownMenuItem(value: 'light', child: Text('浅色')),
            DropdownMenuItem(value: 'dark', child: Text('深色')),
          ],
          onChanged: viewModel.loadError != null
              ? null
              : (value) {
                  if (value != null) {
                    runUiAction(context, () => viewModel.setThemeMode(value));
                  }
                },
        ),
        const SizedBox(height: 16),
        Text('配色', style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: homeThemes.containsKey(viewModel.theme)
              ? viewModel.theme
              : 'sunny-cream',
          onChanged: (value) {
            if (value != null && viewModel.loadError == null) {
              runUiAction(context, () => viewModel.setTheme(value));
            }
          },
          child: Column(
            children: [
              for (final entry in homeThemes.entries)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value.$1),
                  secondary: CircleAvatar(
                    radius: 10,
                    backgroundColor: entry.value.$2,
                  ),
                  value: entry.key,
                ),
            ],
          ),
        ),
        const Divider(),
        Text('照片与隐私', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('拍摄和导入的照片会留存在本机作品中，卸载应用会移除这些资料。需要长期保留的照片请保存到系统相册或导出备份。'),
        const SizedBox(height: 8),
        const Text('只有确认 AI 生成后，所选照片和参考才会发送到配置的服务。密钥使用系统安全存储；备份不包含 AI 配置与密钥。'),
        const SizedBox(height: 20),
        if (deviceInfo != null)
          FutureBuilder<Map<String, dynamic>>(
            future: deviceInfo,
            builder: (context, snapshot) {
              final info = snapshot.data;
              return Text(
                info?['version'] is String
                    ? 'Posey ${info!['version']} (${info['build']})'
                    : 'Posey',
                textAlign: TextAlign.center,
              );
            },
          )
        else
          const Text('Posey', textAlign: TextAlign.center),
      ],
    ),
  );
}
