import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/photo_review/photo_edit.dart';
import 'package:posey/features/photo_review/photo_editor_view_model.dart';

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.viewModel});
  final PhotoEditorViewModel viewModel;
  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  PhotoEditorViewModel get model => widget.viewModel;
  PhotoEdit get edit => model.edit;
  bool get rendering => model.rendering;
  bool get saving => model.saving;
  double gestureZoom = 1, gestureX = .5, gestureY = .5;
  @override
  void initState() {
    super.initState();
    model.addListener(changed);
    model.load();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    model.removeListener(changed);
    model.dispose();
    super.dispose();
  }

  Future<void> render(PhotoEdit next) => model.render(next);
  Future<void> save() async {
    try {
      final saved = await model.save();
      if (mounted && saved) Navigator.pop(context);
    } catch (failure) {
      if (mounted) showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('编辑照片'),
        actions: [
          TextButton(
            onPressed: saving || rendering ? null : save,
            child: const Text('保存副本'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (rendering || saving) const LinearProgressIndicator(),
            Expanded(
              child: model.error != null
                  ? Center(
                      child: Text(model.error!, textAlign: TextAlign.center),
                    )
                  : model.preview == null
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      onScaleStart: (_) {
                        gestureZoom = edit.zoom;
                        gestureX = edit.x;
                        gestureY = edit.y;
                      },
                      onScaleUpdate: (details) {
                        render(
                          edit.copyWith(
                            zoom: (gestureZoom * details.scale).clamp(1, 4),
                            x: (gestureX - details.focalPointDelta.dx / 300)
                                .clamp(0, 1),
                            y: (gestureY - details.focalPointDelta.dy / 300)
                                .clamp(0, 1),
                          ),
                        );
                        gestureX = edit.x;
                        gestureY = edit.y;
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Image.memory(
                          model.preview!,
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '拖动调整裁剪位置，双指缩放。原图会保留。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  for (final entry in <double, String>{
                    0: '原比例',
                    1: '1:1',
                    .8: '4:5',
                    .75: '3:4',
                    16 / 9: '16:9',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: edit.ratio == entry.key,
                        onSelected: saving
                            ? null
                            : (_) => render(edit.copyWith(ratio: entry.key)),
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () =>
                            render(edit.copyWith(turns: (edit.turns + 1) % 4)),
                  icon: const Icon(Icons.rotate_right),
                  label: const Text('旋转'),
                ),
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () => render(edit.copyWith(flip: !edit.flip)),
                  icon: const Icon(Icons.flip),
                  label: const Text('镜像照片'),
                ),
                TextButton(
                  onPressed: saving ? null : () => render(const PhotoEdit()),
                  child: const Text('复位'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
