import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/poses/pose_library_view_model.dart';

const poseCategories = {
  'all': '全部',
  'standing': '站姿',
  'half': '半身',
  'seated': '坐姿',
  'crouching': '蹲跪',
};

class PoseLibraryScreen extends StatelessWidget {
  const PoseLibraryScreen({
    super.key,
    required this.viewModel,
    required this.favoritesOnly,
    required this.onOpenPose,
  });
  final PoseLibraryViewModel viewModel;
  final bool favoritesOnly;
  final ValueChanged<PoseTemplate> onOpenPose;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final filtered = viewModel.filtered(favoritesOnly: favoritesOnly);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!favoritesOnly) ...[
                    Text(
                      '自然一点，就很好看。',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text('选一个喜欢的姿势，让每一次拍照都有灵感。'),
                    const SizedBox(height: 20),
                  ],
                  TextFormField(
                    initialValue: viewModel.query,
                    key: const Key('pose-search'),
                    decoration: const InputDecoration(
                      hintText: '搜索站姿、旅行、手部…',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: viewModel.setQuery,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('全部')),
                      ButtonSegment(value: 'female', label: Text('女生')),
                      ButtonSegment(value: 'male', label: Text('男生')),
                    ],
                    selected: {viewModel.gender},
                    onSelectionChanged: (values) =>
                        viewModel.setGender(values.first),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: poseCategories.entries
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(entry.value),
                                selected: viewModel.category == entry.key,
                                onSelected: (_) =>
                                    viewModel.setCategory(entry.key),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${filtered.length} 个姿势',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('还没有匹配的姿势。')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) => SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.crossAxisExtent > 650 ? 3 : 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: .67,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final pose = filtered[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onOpenPose(pose),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: Color(pose.accent)
                                        .withValues(alpha: .2),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Image.asset(
                                        pose.illustration,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: IconButton(
                                      key: Key('favorite-${pose.id}'),
                                      tooltip: '收藏${pose.title}',
                                      onPressed: () => runUiAction(
                                        context,
                                        () => viewModel.toggleFavorite(pose.id),
                                      ),
                                      icon: Icon(
                                        viewModel.favorites.contains(pose.id)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
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
                                    pose.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
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
            ),
        ],
      );
    },
  );
}
