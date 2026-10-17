import 'package:flutter/material.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/core/ui/reference_image.dart';

class PoseDetailsSheet extends StatelessWidget {
  const PoseDetailsSheet({
    super.key,
    required this.pose,
    required this.onCamera,
    required this.onImport,
    this.onRename,
    this.onDelete,
  });
  final PoseTemplate pose;
  final VoidCallback onCamera, onImport;
  final VoidCallback? onRename, onDelete;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReferenceImage(
              pose.illustration,
              height: 260,
              mirrored: pose.mirrored,
            ),
            Text(pose.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(pose.subtitle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final value in [...pose.scenes, ...pose.props])
                  Chip(label: Text(value)),
              ],
            ),
            const SizedBox(height: 12),
            for (final entry in pose.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${entry.$1 + 1}. ${entry.$2}'),
                ),
              ),
            const SizedBox(height: 8),
            if (pose.cameraHint.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(pose.cameraHint),
              ),
            if (pose.isUserReference)
              Wrap(
                spacing: 12,
                children: [
                  if (onRename != null)
                    TextButton(onPressed: onRename, child: const Text('编辑参考')),
                  if (onDelete != null)
                    TextButton(onPressed: onDelete, child: const Text('删除参考')),
                ],
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('open-camera'),
                    onPressed: onCamera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('跟着拍'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('导入照片'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
