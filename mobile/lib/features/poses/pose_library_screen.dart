import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/core/ui/reference_image.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/poses/pose_library_view_model.dart';

const poseCategories = {
  'all': '全部',
  'standing': '站姿',
  'half': '半身',
  'seated': '坐姿',
  'crouching': '蹲跪',
};

class PoseLibraryScreen extends StatefulWidget {
  const PoseLibraryScreen({
    super.key,
    required this.viewModel,
    required this.favoritesOnly,
    required this.onOpenPose,
    this.onAddReference,
  });
  final PoseLibraryViewModel viewModel;
  final bool favoritesOnly;
  final ValueChanged<PoseTemplate> onOpenPose;
  final VoidCallback? onAddReference;
  @override
  State<PoseLibraryScreen> createState() => _PoseLibraryScreenState();
}

class _PoseLibraryScreenState extends State<PoseLibraryScreen> {
  late final query = TextEditingController(
    text: widget.viewModel.filters(favoritesOnly: widget.favoritesOnly).query,
  );
  @override
  void didUpdateWidget(covariant PoseLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favoritesOnly != widget.favoritesOnly) {
      query.text = widget.viewModel
          .filters(favoritesOnly: widget.favoritesOnly)
          .query;
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void clear() {
    query.clear();
    widget.viewModel.resetFilters(favoritesOnly: widget.favoritesOnly);
  }

  Future<void> resetRecord(String key) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('重置无法读取的记录？'),
        scrollable: true,
        content: const Text('先在本机保留原始记录的恢复副本，再重建这项记录。其他资料会保留。'),
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
    if (agreed == true && mounted) {
      await runUiAction(context, () => widget.viewModel.resetRecord(key));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      final model = widget.viewModel,
          f = model.filters(favoritesOnly: widget.favoritesOnly);
      final filtered = model.filtered(favoritesOnly: widget.favoritesOnly);
      return CustomScrollView(
        key: PageStorageKey('pose-library-${widget.favoritesOnly}'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final error in model.loadErrors.entries)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(error.value),
                            Wrap(
                              spacing: 12,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      runUiAction(context, model.load),
                                  child: const Text('重新加载'),
                                ),
                                TextButton(
                                  onPressed: () => resetRecord(error.key),
                                  child: const Text('备份并重置'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextField(
                    key: const Key('pose-search'),
                    controller: query,
                    decoration: InputDecoration(
                      hintText: '搜索姿势、场景或道具',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                query.clear();
                                model.setQuery(
                                  '',
                                  favoritesOnly: widget.favoritesOnly,
                                );
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                    onChanged: (value) => model.setQuery(
                      value,
                      favoritesOnly: widget.favoritesOnly,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('全部')),
                      ButtonSegment(value: 'female', label: Text('女生')),
                      ButtonSegment(value: 'male', label: Text('男生')),
                    ],
                    selected: {f.gender},
                    onSelectionChanged: (values) => model.setGender(
                      values.first,
                      favoritesOnly: widget.favoritesOnly,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in poseCategories.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(entry.value),
                              selected: f.category == entry.key,
                              onSelected: (_) => model.setCategory(
                                entry.key,
                                favoritesOnly: widget.favoritesOnly,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: f.scene,
                          key: ValueKey(
                            'scene-${widget.favoritesOnly}-${f.scene}',
                          ),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '场景',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('全部场景'),
                            ),
                            for (final scene in model.scenes)
                              DropdownMenuItem(
                                value: scene,
                                child: Text(scene),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              model.setScene(
                                value,
                                favoritesOnly: widget.favoritesOnly,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: f.sort,
                          key: ValueKey(
                            'sort-${widget.favoritesOnly}-${f.sort}',
                          ),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '排序',
                            isDense: true,
                          ),
                          items: [
                            for (final entry in {
                              'catalog': '默认',
                              'recent': '最近使用',
                              'saved': '收藏优先',
                              'name': '名称',
                            }.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              model.setSort(
                                value,
                                favoritesOnly: widget.favoritesOnly,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${filtered.length} 个姿势',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (f.active)
                        TextButton(onPressed: clear, child: const Text('清除筛选')),
                      if (widget.onAddReference != null)
                        TextButton.icon(
                          onPressed: widget.onAddReference,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('导入参考'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.favoritesOnly && model.favorites.isEmpty
                            ? '还没有收藏，点心形图标添加。'
                            : '还没有匹配的姿势。',
                        textAlign: TextAlign.center,
                      ),
                      if (f.active)
                        TextButton(onPressed: clear, child: const Text('清除筛选')),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .68,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final pose = filtered[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => widget.onOpenPose(pose),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: Color(pose.accent)
                                      .withValues(alpha: .16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: ReferenceImage(pose.illustration),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    key: Key('favorite-${pose.id}'),
                                    tooltip: '收藏${pose.title}',
                                    onPressed: () => runUiAction(
                                      context,
                                      () => model.toggleFavorite(pose.id),
                                    ),
                                    icon: Icon(
                                      model.favorites.contains(pose.id)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                ),
                                if (pose.isUserReference)
                                  const Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: Chip(label: Text('自有参考')),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pose.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pose.subtitle.isEmpty
                                      ? pose.scenes.join(' · ')
                                      : pose.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
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
