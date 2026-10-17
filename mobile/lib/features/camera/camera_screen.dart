import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/camera/camera_view_model.dart';

class PoseyCameraScreen extends StatefulWidget {
  const PoseyCameraScreen({
    super.key,
    required this.viewModel,
    required this.poses,
    required this.onPhoto,
  });
  final CameraViewModel viewModel;
  final List<PoseTemplate> poses;
  final Future<void> Function(String, PoseTemplate) onPhoto;
  @override
  State<PoseyCameraScreen> createState() => _PoseyCameraScreenState();
}

class _PoseyCameraScreenState extends State<PoseyCameraScreen>
    with WidgetsBindingObserver {
  CameraViewModel get viewModel => widget.viewModel;
  CameraController? get camera => viewModel.preview;
  PoseTemplate get target => viewModel.target;
  List<CameraDescription> get cameras => viewModel.cameras;
  bool get grid => viewModel.grid;
  bool get mirror => viewModel.mirror;
  bool get showGuide => viewModel.showGuide;
  bool get captureBusy => viewModel.captureBusy;
  bool get initializing => viewModel.phase == CameraPhase.opening;
  String? get error => viewModel.error;
  double get opacity => viewModel.opacity;
  double get zoom => viewModel.zoom;
  double get minZoom => viewModel.minZoom;
  double get maxZoom => viewModel.maxZoom;
  bool _reviewing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(viewModel.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    viewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      viewModel.setActive(state == AppLifecycleState.resumed && !_reviewing);

  Future<void> reviewPhoto(String path, PoseTemplate pose) async {
    _reviewing = true;
    viewModel.setActive(false);
    try {
      await widget.onPhoto(path, pose);
    } finally {
      _reviewing = false;
      if (mounted) {
        final state = WidgetsBinding.instance.lifecycleState;
        viewModel.setActive(
          state == null || state == AppLifecycleState.resumed,
        );
      }
    }
  }

  Future<void> capture() => runUiAction(context, () async {
    final photo = await viewModel.capture();
    if (photo != null && mounted) {
      await reviewPhoto(photo.path, photo.target);
    }
  });
  Future<void> importPhoto() => runUiAction(context, () async {
    final photo = await viewModel.importPhoto();
    if (photo != null && mounted) {
      await reviewPhoto(photo.path, photo.target);
    }
  });
  Future<void> flash() => runUiAction(context, viewModel.toggleFlash);
  Future<void> choosePose() async {
    final next = await showModalBottomSheet<PoseTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.poses.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: .65,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final pose = widget.poses[index];
          return InkWell(
            onTap: () => Navigator.pop(context, pose),
            child: Column(
              children: [
                Expanded(
                  child: Image.asset(pose.illustration, fit: BoxFit.contain),
                ),
                Text(pose.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
    if (next != null && mounted) viewModel.selectPose(next);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => Scaffold(
      backgroundColor: const Color(0xFF171714),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171714),
        foregroundColor: Colors.white,
        title: Text(target.title),
        actions: [
          IconButton(
            onPressed: flash,
            tooltip: '闪光灯',
            icon: Icon(
              viewModel.flashAuto ? Icons.flash_auto : Icons.flash_off,
            ),
          ),
          IconButton(
            onPressed: viewModel.toggleGrid,
            tooltip: '构图网格',
            icon: Icon(grid ? Icons.grid_on : Icons.grid_off),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    if (camera?.value.isInitialized == true)
                      Center(
                        child: AspectRatio(
                          aspectRatio: 1 / camera!.value.aspectRatio,
                          child: CameraPreview(camera!),
                        ),
                      )
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (initializing)
                                const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              else ...[
                                Text(
                                  error ?? '准备相机',
                                  style: const TextStyle(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton(
                                  onPressed: viewModel.initialize,
                                  child: const Text('重新打开相机'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (grid)
                      const IgnorePointer(
                        child: CustomPaint(painter: CompositionGrid()),
                      ),
                    if (showGuide)
                      IgnorePointer(
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.flip(
                            flipX: mirror,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                                horizontal: 32,
                              ),
                              child: Image.asset(
                                target.illustration,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 12,
                      left: 16,
                      right: 16,
                      child: Text(
                        target.subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                    ),
                    if (camera != null && maxZoom > minZoom)
                      Positioned(
                        bottom: 10,
                        left: 24,
                        right: 24,
                        child: Row(
                          children: [
                            Text(
                              '${zoom.toStringAsFixed(1)}×',
                              style: const TextStyle(color: Colors.white),
                            ),
                            Expanded(
                              child: Slider(
                                value: zoom,
                                min: minZoom,
                                max: maxZoom,
                                onChanged: (value) => runUiAction(
                                  context,
                                  () => viewModel.setZoom(value),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: viewModel.toggleGuide,
                    tooltip: '显示或隐藏参考',
                    color: Colors.white,
                    icon: Icon(
                      showGuide ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: opacity,
                      min: .1,
                      max: .85,
                      onChanged: viewModel.setOpacity,
                    ),
                  ),
                  IconButton(
                    onPressed: viewModel.toggleMirror,
                    tooltip: '镜像参考图',
                    color: Colors.white,
                    icon: const Icon(Icons.flip),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: captureBusy ? null : importPhoto,
                    tooltip: '导入照片',
                    color: Colors.white,
                    iconSize: 30,
                    icon: const Icon(Icons.photo_library_outlined),
                  ),
                  IconButton.filled(
                    onPressed: captureBusy || initializing || camera == null
                        ? null
                        : capture,
                    tooltip: '拍照',
                    iconSize: 60,
                    icon: captureBusy
                        ? const SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(),
                          )
                        : const Icon(Icons.circle),
                  ),
                  IconButton(
                    onPressed: captureBusy || initializing || cameras.length < 2
                        ? null
                        : viewModel.switchCamera,
                    tooltip: '切换摄像头',
                    color: Colors.white,
                    iconSize: 30,
                    icon: const Icon(Icons.cameraswitch_outlined),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: choosePose, child: const Text('换个姿势')),
          ],
        ),
      ),
    ),
  );
}

class CompositionGrid extends CustomPainter {
  const CompositionGrid();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .4)
      ..strokeWidth = .7;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(size.width * i / 3, 0),
        Offset(size.width * i / 3, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CompositionGrid oldDelegate) => false;
}
