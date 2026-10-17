import 'package:flutter/material.dart';
import 'package:posey/core/ui/reference_image.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/poses/pose_library_screen.dart';

Future<PoseTemplate?> pickPose(
  BuildContext context,
  List<PoseTemplate> poses,
) => showModalBottomSheet<PoseTemplate>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      FractionallySizedBox(heightFactor: .88, child: PosePicker(poses: poses)),
);

class PosePicker extends StatefulWidget {
  const PosePicker({super.key, required this.poses});
  final List<PoseTemplate> poses;
  @override
  State<PosePicker> createState() => _PosePickerState();
}

class _PosePickerState extends State<PosePicker> {
  String query = '', category = 'all';
  @override
  Widget build(BuildContext context) {
    final poses = widget.poses
        .where((pose) => pose.matches(query, 'all', category))
        .toList();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: '搜索参考',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final entry in poseCategories.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: category == entry.key,
                      onSelected: (_) => setState(() => category = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: poses.isEmpty
                ? const Center(child: Text('没有匹配的参考'))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: poses.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: .65,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemBuilder: (context, index) {
                      final pose = poses[index];
                      return InkWell(
                        onTap: () => Navigator.pop(context, pose),
                        child: Column(
                          children: [
                            Expanded(child: ReferenceImage(pose.illustration)),
                            Text(
                              pose.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ReferenceForm extends StatefulWidget {
  const ReferenceForm({super.key, this.initial});
  final PoseTemplate? initial;
  @override
  State<ReferenceForm> createState() => _ReferenceFormState();
}

class _ReferenceFormState extends State<ReferenceForm> {
  late final title = TextEditingController(text: widget.initial?.title ?? '');
  String category = 'standing', gender = 'all';
  String? error;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '添加自有参考' : '修改参考名称'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: title,
          maxLength: 80,
          autofocus: true,
          decoration: InputDecoration(labelText: '参考名称', errorText: error),
        ),
        if (widget.initial == null) ...[
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: '姿势分类'),
            items: [
              for (final entry in poseCategories.entries.where(
                (entry) => entry.key != 'all',
              ))
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => category = value ?? category,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: gender,
            decoration: const InputDecoration(labelText: '适用筛选'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('不限')),
              DropdownMenuItem(value: 'female', child: Text('女生')),
              DropdownMenuItem(value: 'male', child: Text('男生')),
            ],
            onChanged: (value) => gender = value ?? gender,
          ),
          const SizedBox(height: 12),
          const Text('请使用你有权保存和处理的参考图片。'),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (title.text.trim().isEmpty) {
            setState(() => error = '请输入参考名称');
            return;
          }
          Navigator.pop(context, (
            title: title.text.trim(),
            category: category,
            gender: gender,
          ));
        },
        child: const Text('保存'),
      ),
    ],
  );
}
