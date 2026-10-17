import 'dart:io';

import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/works/photo_work.dart';
import 'package:posey/features/works/works_repository.dart';

class WorksScreen extends StatefulWidget {
  const WorksScreen({
    super.key,
    required this.repository,
    required this.onOpen,
    required this.onShare,
  });
  final WorksRepository repository;
  final ValueChanged<PhotoWork> onOpen;
  final Future<void> Function(List<String>) onShare;
  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends State<WorksScreen> {
  final selected = <String>{};
  WorkKind? filter;
  bool busy = false;
  Future<void> action(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await runUiAction(context, operation);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('删除 ${selected.length} 个作品？'),
        content: const Text('已保存到系统相册的照片会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (agreed == true) {
      await action(() async {
        await widget.repository.delete({...selected});
        selected.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final works = widget.repository.works
          .where((work) => filter == null || work.kind == filter)
          .toList();
      selected.removeWhere((id) => widget.repository.find(id) == null);
      return Column(
        children: [
          if (widget.repository.loadError != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(widget.repository.loadError!),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => action(widget.repository.load),
                        child: const Text('重新加载'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final agreed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialog) => AlertDialog(
                                    title: const Text('重置作品列表？'),
                                    content: const Text(
                                      '先保留本机恢复副本，再重建列表。系统相册不会受影响。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialog, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dialog, true),
                                        child: const Text('备份并重置'),
                                      ),
                                    ],
                                  ),
                                );
                                if (agreed == true) {
                                  await action(
                                    widget.repository.resetUnreadableHistory,
                                  );
                                }
                              },
                        child: const Text('备份并重置'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final entry in <WorkKind?, String>{
                  null: '全部',
                  WorkKind.photo: '照片',
                  WorkKind.edit: '编辑',
                  WorkKind.ai: 'AI 成片',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: filter == entry.key,
                      onSelected: (_) => setState(() => filter = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            for (final id in {...selected}) {
                              await widget.repository.saveToGallery(id);
                            }
                          }),
                    child: const Text('保存到相册'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(
                            () => widget.onShare(
                              selected
                                  .map((id) => widget.repository.find(id)!.path)
                                  .toList(),
                            ),
                          ),
                    child: const Text('分享'),
                  ),
                  TextButton(
                    onPressed: busy ? null : remove,
                    child: const Text('删除'),
                  ),
                  TextButton(
                    onPressed: () => setState(selected.clear),
                    child: const Text('取消选择'),
                  ),
                ],
              ),
            ),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: works.isEmpty
                ? const Center(
                    child: Text(
                      '还没有作品。拍摄或导入照片后会保存在这里。',
                      textAlign: TextAlign.center,
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: works.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          childAspectRatio: .72,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemBuilder: (context, index) {
                      final work = works[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onLongPress: () =>
                              setState(() => selected.add(work.id)),
                          onTap: () {
                            if (selected.isEmpty) {
                              widget.onOpen(work);
                            } else {
                              setState(() {
                                if (!selected.add(work.id)) {
                                  selected.remove(work.id);
                                }
                              });
                            }
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(work.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Center(child: Text('照片无法读取')),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: ColoredBox(
                                  color: Colors.black54,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      work.pose.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (selected.contains(work.id))
                                const Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                  ),
                                ),
                              if (work.savedToGallery)
                                const Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Icon(
                                    Icons.download_done,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}
