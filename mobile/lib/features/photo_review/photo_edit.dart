import 'dart:typed_data';

import 'package:image/image.dart' as img;

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
  final info = img.findDecoderForData(input.bytes)?.startDecode(input.bytes);
  if (input.bytes.length > 24 * 1024 * 1024 ||
      info == null ||
      info.width * info.height > 16 * 1024 * 1024) {
    throw const FormatException('照片过大或格式无效。');
  }
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
