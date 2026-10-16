import 'package:flutter/material.dart';
import 'package:posey/features/poses/pose_template.dart';

class PoseDetailsSheet extends StatelessWidget {
  const PoseDetailsSheet({
    super.key,
    required this.pose,
    required this.onCamera,
    required this.onImport,
  });
  final PoseTemplate pose;
  final VoidCallback onCamera, onImport;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(pose.illustration, height: 260, fit: BoxFit.contain),
            Text(pose.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(pose.subtitle),
            const SizedBox(height: 12),
            Text(pose.tags.join(' · ')),
            const SizedBox(height: 12),
            const Text('跟着参考调整身体姿势，选择舒服自然的幅度。', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              pose.sourceLabel,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (pose.experimental) const Text('探索中的参考姿势，按身体感受调整。'),
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
