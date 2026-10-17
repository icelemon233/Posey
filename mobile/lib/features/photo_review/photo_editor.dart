import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/core/ui/feedback.dart';

class PhotoEdit {
  const PhotoEdit({
    this.turns = 0,
    this.flip = false,
    this.ratio = 0,
    this.zoom = 1,
    this.x = .5,
    this.y = .5,
  });
  final int turns;
  final bool flip;
  final double ratio, zoom, x, y;
  PhotoEdit copyWith({
    int? turns,
    bool? flip,
    double? ratio,
    double? zoom,
    double? x,
    double? y,
  }) => PhotoEdit(
    turns: turns ?? this.turns,
    flip: flip ?? this.flip,
    ratio: ratio ?? this.ratio,
    zoom: zoom ?? this.zoom,
    x: x ?? this.x,
    y: y ?? this.y,
  );
}

Uint8List editPhoto(({Uint8List bytes, PhotoEdit edit, bool preview}) input) {
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) {
    throw const FormatException('无法编辑这张照片，请改用 JPEG、PNG 或 WebP 图片。');
  }
  var image = img.bakeOrientation(decoded);
  if (input.edit.turns % 4 != 0) {
    image = img.copyRotate(image, angle: 90 * (input.edit.turns % 4));
  }
  if (input.edit.flip) image = img.flipHorizontal(image);
  final ratio = input.edit.ratio > 0
      ? input.edit.ratio
      : image.width / image.height;
  final baseWidth = image.width / image.height > ratio
      ? image.height * ratio
      : image.width.toDouble();
  final baseHeight = baseWidth / ratio;
  final width = (baseWidth / input.edit.zoom.clamp(1, 4)).round().clamp(
    1,
    image.width,
  );
  final height = (baseHeight / input.edit.zoom.clamp(1, 4)).round().clamp(
    1,
    image.height,
  );
  final left = ((image.width - width) * input.edit.x.clamp(0, 1)).round();
  final top = ((image.height - height) * input.edit.y.clamp(0, 1)).round();
  image = img.copyCrop(image, x: left, y: top, width: width, height: height);
  if (input.preview && (image.width > 1200 || image.height > 1200)) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1200 : null,
      height: image.height > image.width ? 1200 : null,
    );
  }
  return Uint8List.fromList(
    img.encodeJpg(image, quality: input.preview ? 85 : 95),
  );
}

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({
    super.key,
    required this.path,
    required this.photos,
    required this.onSave,
  });
  final String path;
  final PhotoLibrary photos;
  final Future<void> Function(Uint8List) onSave;
  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  Uint8List? original, preview;
  PhotoEdit edit = const PhotoEdit();
  String? error;
  int revision = 0;
  bool rendering = false, saving = false;
  double gestureZoom = 1, gestureX = .5, gestureY = .5;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.photos.readPhoto(widget.path);
      if (!mounted) return;
      original = bytes;
      await render(edit);
    } catch (failure) {
      if (mounted) setState(() => error = '照片无法读取：$failure');
    }
  }

  Future<void> render(PhotoEdit next) async {
    if (original == null || saving) return;
    final request = ++revision;
    setState(() {
      edit = next;
      rendering = true;
      error = null;
    });
    try {
      final bytes = await compute(editPhoto, (
        bytes: original!,
        edit: next,
        preview: true,
      ));
      if (mounted && request == revision) setState(() => preview = bytes);
    } catch (failure) {
      if (mounted && request == revision) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted && request == revision) setState(() => rendering = false);
    }
  }

  Future<void> save() async {
    if (original == null || saving || rendering) return;
    setState(() => saving = true);
    try {
      final bytes = await compute(editPhoto, (
        bytes: original!,
        edit: edit,
        preview: false,
      ));
      await widget.onSave(bytes);
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) showFailure(context, failure);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
            child: error != null
                ? Center(child: Text(error!, textAlign: TextAlign.center))
                : preview == null
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
                        preview!,
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
                    : () => render(edit.copyWith(turns: (edit.turns + 1) % 4)),
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
  );
}
