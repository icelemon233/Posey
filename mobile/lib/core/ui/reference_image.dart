import 'dart:io';

import 'package:flutter/material.dart';

class ReferenceImage extends StatelessWidget {
  const ReferenceImage(
    this.path, {
    super.key,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.mirrored = false,
  });
  final String path;
  final BoxFit fit;
  final double? width, height;
  final bool mirrored;
  @override
  Widget build(BuildContext context) {
    Widget failure(BuildContext context, Object error, StackTrace? stack) =>
        const Center(child: Icon(Icons.broken_image_outlined));
    final image = path.startsWith('assets/')
        ? Image.asset(
            path,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: failure,
          )
        : Image.file(
            File(path),
            fit: fit,
            width: width,
            height: height,
            errorBuilder: failure,
          );
    return Transform.flip(flipX: mirrored, child: image);
  }
}
