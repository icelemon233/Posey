import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/settings/settings_view_model.dart';

class SettingsRecovery extends StatefulWidget {
  const SettingsRecovery({super.key, required this.model});
  final SettingsViewModel model;
  @override
  State<SettingsRecovery> createState() => _SettingsRecoveryState();
}

class _SettingsRecoveryState extends State<SettingsRecovery> {
  bool busy = false;
  Future<void> run(Future<void> Function() command) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await runUiAction(context, command);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reset() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('重置设置？'),
        scrollable: true,
        content: const Text('原始设置会先保留本机恢复副本。AI 密钥会移除，需要重新填写；照片、参考和收藏会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('备份并重置'),
          ),
        ],
      ),
    );
    if (agreed == true && mounted) await run(widget.model.resetUnreadable);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => widget.model.loadError == null
        ? const SizedBox.shrink()
        : Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.model.loadError!),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => run(widget.model.load),
                        child: const Text('重新加载设置'),
                      ),
                      TextButton(
                        onPressed: busy ? null : reset,
                        child: const Text('备份并重置'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
  );
}
