import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'controller.dart';
import 'models.dart';

class PoseyCameraScreen extends StatefulWidget {
  const PoseyCameraScreen({
    super.key,
    required this.controller,
    required this.target,
    required this.onPhoto,
  });
  final PoseyController controller;
  final PoseTemplate target;
  final Future<void> Function(String path, PoseTemplate target) onPhoto;
  @override
  State<PoseyCameraScreen> createState() => _PoseyCameraScreenState();
}

class _PoseyCameraScreenState extends State<PoseyCameraScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  List<CameraDescription> cameras = [];
  late PoseTemplate target = widget.target;
  String? error;
  bool initializing = false,
      captureBusy = false,
      grid = false,
      mirror = false,
      showGuide = true,
      active = true;
  double opacity = .38, zoom = 1, minZoom = 1, maxZoom = 1;
  int cameraIndex = 0, generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(initialize());
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(camera?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) {
      generation++;
      final previous = camera;
      camera = null;
      unawaited(previous?.dispose());
      if (mounted) setState(() => initializing = false);
    } else {
      unawaited(initialize());
    }
  }

  Future<void> initialize() async {
    if (!mounted || !active || initializing) return;
    final epoch = ++generation;
    setState(() {
      initializing = true;
      error = null;
    });
    CameraController? next;
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('没有找到可用的摄像头，可以导入照片继续。');
      cameraIndex %= cameras.length;
      final previous = camera;
      camera = null;
      await previous?.dispose();
      next = CameraController(
        cameras[cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await next.initialize();
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      final limits = await Future.wait([
        next.getMinZoomLevel(),
        next.getMaxZoomLevel(),
      ]);
      if (!mounted || !active || generation != epoch) {
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        minZoom = limits[0];
        maxZoom = math.min(limits[1], 5);
        zoom = minZoom;
      });
    } on CameraException catch (failure) {
      await next?.dispose();
      if (mounted && epoch == generation) {
        setState(
          () => error = switch (failure.code) {
            'CameraAccessDenied' ||
            'CameraAccessDeniedWithoutPrompt' ||
            'CameraAccessRestricted' => '相机权限尚未打开。请在系统设置中允许相机，或导入照片继续。',
            _ => '相机暂时无法使用，请重试或导入照片。',
          },
        );
      }
    } catch (failure) {
      await next?.dispose();
      if (mounted && epoch == generation) {
        setState(
          () => error = failure.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted && epoch == generation) setState(() => initializing = false);
    }
  }

  void message(Object failure) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> capture() async {
    final current = camera;
    if (captureBusy || current == null || !current.value.isInitialized) return;
    setState(() => captureBusy = true);
    try {
      final file = await current.takePicture();
      if (mounted) await widget.onPhoto(file.path, target);
    } catch (_) {
      message('拍摄失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => captureBusy = false);
    }
  }

  Future<void> importPhoto() async {
    if (captureBusy) return;
    setState(() => captureBusy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (file != null && mounted) await widget.onPhoto(file.path, target);
    } catch (_) {
      message('照片无法读取，请重新选择。');
    } finally {
      if (mounted) setState(() => captureBusy = false);
    }
  }

  Future<void> flash() async {
    final current = camera;
    if (current == null) return;
    try {
      await current.setFlashMode(
        current.value.flashMode == FlashMode.off
            ? FlashMode.auto
            : FlashMode.off,
      );
      if (mounted) setState(() {});
    } catch (_) {
      message('当前摄像头不支持闪光灯。');
    }
  }

  Future<void> choosePose() async {
    final next = await showModalBottomSheet<PoseTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.controller.templates.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: .65,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final pose = widget.controller.templates[index];
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
    if (next != null && mounted) setState(() => target = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
            camera?.value.flashMode == FlashMode.auto
                ? Icons.flash_auto
                : Icons.flash_off,
          ),
        ),
        IconButton(
          onPressed: () => setState(() => grid = !grid),
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
                                onPressed: initialize,
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
                              onChanged: (value) async {
                                try {
                                  await camera?.setZoomLevel(value);
                                  if (mounted) setState(() => zoom = value);
                                } catch (_) {}
                              },
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
                  onPressed: () => setState(() => showGuide = !showGuide),
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
                    onChanged: (value) => setState(() => opacity = value),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => mirror = !mirror),
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
                      : () {
                          cameraIndex = (cameraIndex + 1) % cameras.length;
                          initialize();
                        },
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
