import 'dart:async';

import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/backup/backup_manager.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.manager});
  final BackupManager manager;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  int range = -1;
  late Future<Map<String, int>> stats = widget.manager.statistics();
  @override
  void dispose() {
    if (!widget.manager.busy) unawaited(widget.manager.cancelImport());
    super.dispose();
  }

  Future<void> beginImport() async {
    await runUiAction(context, () async {
      final candidate = await widget.manager.prepareImport();
      if (candidate == null || !mounted) return;
      var restore = false;
      final agreed = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('合并备份？'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(candidate.manifest['works'] as List).length} 个作品、${(candidate.manifest['poses'] as List).length} 个自有参考。\n相同编号会保留当前内容，不移除现有作品。',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('同时恢复界面与相机设置'),
                  value: restore,
                  onChanged: (value) =>
                      setDialogState(() => restore = value ?? false),
                ),
                const Text('AI 配置与密钥不会改变。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('合并导入'),
              ),
            ],
          ),
        ),
      );
      if (agreed == true) {
        await widget.manager.applyImport(restoreInterface: restore);
        if (mounted) setState(() => stats = widget.manager.statistics());
      } else {
        await widget.manager.cancelImport();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.manager,
    builder: (context, _) => PopScope(
      canPop: !widget.manager.busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('备份与存储')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.manager.busy) const LinearProgressIndicator(),
            FutureBuilder<Map<String, int>>(
              future: stats,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null)
                  return Text(snapshot.hasError ? '存储统计暂时无法读取' : '正在统计存储…');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '应用内照片 ${(data['bytes']! / (1024 * 1024)).toStringAsFixed(1)} MB',
                  ),
                  subtitle: Text(
                    '${data['works']} 个作品 · ${data['references']} 个自有参考 · ${data['recovery']} 份恢复副本',
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: range,
              decoration: const InputDecoration(labelText: '备份作品范围'),
              items: const [
                DropdownMenuItem(value: -1, child: Text('全部作品')),
                DropdownMenuItem(value: 100, child: Text('最近 100 个')),
                DropdownMenuItem(value: 20, child: Text('最近 20 个')),
                DropdownMenuItem(value: 0, child: Text('不包含作品照片')),
              ],
              onChanged: widget.manager.busy
                  ? null
                  : (value) => setState(() => range = value ?? -1),
            ),
            const SizedBox(height: 12),
            const Text(
              '备份包含界面与相机设置、收藏、自有参考，以及选定范围的作品和原图。AI 配置与密钥不会导出。单份备份最多 1 GB。',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.manager.busy
                  ? null
                  : () => runUiAction(
                      context,
                      () => widget.manager.export(
                        workLimit: range < 0 ? null : range,
                      ),
                    ),
              icon: const Icon(Icons.upload_file),
              label: const Text('导出备份'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.manager.busy ? null : beginImport,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('导入并合并备份'),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: widget.manager.busy
                  ? null
                  : () => runUiAction(context, () async {
                      await widget.manager.clearTemporary();
                      if (mounted)
                        setState(() => stats = widget.manager.statistics());
                    }),
              child: const Text('清理分享与导出临时文件'),
            ),
            if (widget.manager.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(widget.manager.message!),
              ),
          ],
        ),
      ),
    ),
  );
}
