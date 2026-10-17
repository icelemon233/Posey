import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/core/ui/reference_image.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/poses/pose_picker.dart';
import 'package:posey/features/camera/camera_view_model.dart';

class PoseyCameraScreen extends StatefulWidget {
  const PoseyCameraScreen({
    super.key,
    required this.viewModel,
    required this.poses,
    required this.onPhoto,
    this.onImportedPhoto,
    this.onOpenSettings,
  });
  final CameraViewModel viewModel;
  final List<PoseTemplate> poses;
  final Future<void> Function(String, PoseTemplate) onPhoto;
  final Future<void> Function(String, PoseTemplate)? onImportedPhoto;
  final Future<void> Function()? onOpenSettings;
  @override
  State<PoseyCameraScreen> createState() => _PoseyCameraScreenState();
}

class _PoseyCameraScreenState extends State<PoseyCameraScreen>
    with WidgetsBindingObserver {
  CameraViewModel get model => widget.viewModel;
  bool reviewing = false, adjustGuide = false;
  int step = 0;
  double gestureZoom = 1, gestureScale = 1, gestureX = 0, gestureY = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(model.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      model.setActive(state == AppLifecycleState.resumed && !reviewing);
  Future<void> reviewPhoto(
    String path,
    PoseTemplate pose, {
    bool imported = false,
  }) async {
    reviewing = true;
    model.setActive(false);
    try {
      await model.waitForRelease();
      if (mounted)
        await (imported
            ? widget.onImportedPhoto ?? widget.onPhoto
            : widget.onPhoto)(path, pose);
    } finally {
      reviewing = false;
      if (mounted) {
        final state = WidgetsBinding.instance.lifecycleState;
        model.setActive(state == null || state == AppLifecycleState.resumed);
      }
    }
  }

  Future<void> capture() => runUiAction(context, () async {
    final photo = await model.capture();
    if (photo != null && mounted) await reviewPhoto(photo.path, photo.target);
  });
  Future<void> importPhoto() => runUiAction(context, () async {
    final photo = await model.importPhoto();
    if (photo != null && mounted)
      await reviewPhoto(photo.path, photo.target, imported: true);
  });
  Future<void> choosePose() async {
    final pose = await pickPose(context, widget.poses);
    if (pose != null && mounted) {
      setState(() => step = 0);
      model.selectPose(pose);
    }
  }

  Future<void> controls() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => AnimatedBuilder(
      animation: model,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('显示参考'),
                value: model.showGuide,
                onChanged: (_) => model.toggleGuide(),
              ),
              SwitchListTile(
                title: const Text('镜像参考'),
                value: model.mirror,
                onChanged: (_) => model.toggleMirror(),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('参考透明度'),
              ),
              Slider(
                value: model.opacity,
                min: .1,
                max: .85,
                onChanged: model.setOpacity,
              ),
              TextButton.icon(
                onPressed: model.resetGuide,
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('复位参考位置与大小'),
              ),
              if (model.preferencesError != null) Text(model.preferencesError!),
              const Text('点按画面对焦。切换到移动参考后，可拖动参考或双指调整大小。'),
            ],
          ),
        ),
      ),
    ),
  );
  Widget viewport(
    CameraController camera,
  ) => ValueListenableBuilder<CameraValue>(
    valueListenable: camera,
    builder: (context, value, _) {
      final orientation =
          value.lockedCaptureOrientation ?? value.deviceOrientation;
      final landscape =
          orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight;
      return Center(
        child: AspectRatio(
          aspectRatio: landscape ? value.aspectRatio : 1 / value.aspectRatio,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, size) => Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: adjustGuide || model.captureBusy
                        ? null
                        : (details) => runUiAction(
                            context,
                            () => model.focusAt(
                              Offset(
                                details.localPosition.dx / size.maxWidth,
                                details.localPosition.dy / size.maxHeight,
                              ),
                            ),
                          ),
                    onScaleStart: model.captureBusy
                        ? null
                        : (_) {
                            gestureZoom = model.zoom;
                            gestureScale = model.guideScale;
                            gestureX = model.guideX;
                            gestureY = model.guideY;
                          },
                    onScaleUpdate: model.captureBusy
                        ? null
                        : (details) {
                            if (adjustGuide) {
                              gestureX +=
                                  details.focalPointDelta.dx / size.maxWidth;
                              gestureY +=
                                  details.focalPointDelta.dy / size.maxHeight;
                              model.transformGuide(
                                gestureScale * details.scale,
                                gestureX,
                                gestureY,
                              );
                            } else if (details.pointerCount > 1) {
                              unawaited(
                                runUiAction(
                                  context,
                                  () => model.setZoom(
                                    gestureZoom * details.scale,
                                  ),
                                ),
                              );
                            }
                          },
                    onScaleEnd: adjustGuide ? (_) => model.saveGuide() : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(camera),
                        if (model.grid)
                          const IgnorePointer(
                            child: CustomPaint(painter: CompositionGrid()),
                          ),
                        if (model.showGuide)
                          IgnorePointer(
                            child: Transform.translate(
                              offset: Offset(
                                model.guideX * size.maxWidth,
                                model.guideY * size.maxHeight,
                              ),
                              child: Transform.scale(
                                scale: model.guideScale,
                                child: Opacity(
                                  opacity: model.opacity,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: ReferenceImage(
                                      model.target.illustration,
                                      mirrored: model.mirror,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (model.focusPoint != null)
                    Positioned(
                      left: model.focusPoint!.dx * size.maxWidth - 22,
                      top: model.focusPoint!.dy * size.maxHeight - 22,
                      child: IgnorePointer(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (model.countdown > 0)
                    Center(
                      child: Text(
                        '${model.countdown}',
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                    ),
                  if (adjustGuide)
                    const Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: IgnorePointer(
                        child: Text(
                          '移动参考：拖动或双指缩放',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  if (model.target.steps.isNotEmpty && !adjustGuide)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '上一步',
                              onPressed: step <= 0
                                  ? null
                                  : () => setState(() => step--),
                              icon: const Icon(
                                Icons.chevron_left,
                                color: Colors.white,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                model.target.steps[step.clamp(
                                  0,
                                  model.target.steps.length - 1,
                                )],
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            IconButton(
                              tooltip: '下一步',
                              onPressed: step >= model.target.steps.length - 1
                                  ? null
                                  : () => setState(() => step++),
                              icon: const Icon(
                                Icons.chevron_right,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (model.maxZoom > model.minZoom)
                    Positioned(
                      bottom: 0,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          Text(
                            '${model.zoom.toStringAsFixed(1)}×',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Expanded(
                            child: Slider(
                              value: model.zoom,
                              min: model.minZoom,
                              max: model.maxZoom,
                              onChanged: model.captureBusy
                                  ? null
                                  : (value) => runUiAction(
                                      context,
                                      () => model.setZoom(value),
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
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => PopScope(
      canPop: !model.captureBusy && !reviewing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (model.countdown > 0) {
          model.cancelCountdown();
          await Future<void>.delayed(Duration.zero);
          if (context.mounted) Navigator.pop(context);
        } else {
          showFailure(context, '请等待拍摄或照片留存完成');
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF171714),
        appBar: AppBar(
          backgroundColor: const Color(0xFF171714),
          foregroundColor: Colors.white,
          title: Text(
            model.target.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: '闪光灯',
              onPressed: model.captureBusy
                  ? null
                  : () => runUiAction(context, model.toggleFlash),
              icon: Icon(model.flashAuto ? Icons.flash_auto : Icons.flash_off),
            ),
            IconButton(
              tooltip: '构图网格',
              onPressed: model.toggleGrid,
              icon: Icon(model.grid ? Icons.grid_on : Icons.grid_off),
            ),
            PopupMenuButton<int>(
              tooltip: '倒计时',
              initialValue: model.timerSeconds,
              onSelected: model.setTimer,
              icon: Icon(
                model.timerSeconds == 0
                    ? Icons.timer_off_outlined
                    : Icons.timer_outlined,
              ),
              itemBuilder: (_) => [
                for (final seconds in [0, 3, 5, 10])
                  PopupMenuItem(
                    value: seconds,
                    child: Text(seconds == 0 ? '关闭倒计时' : '$seconds 秒'),
                  ),
              ],
            ),
            IconButton(
              tooltip: '参考设置',
              onPressed: controls,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: model.preview?.value.isInitialized == true
                    ? viewport(model.preview!)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (model.phase == CameraPhase.opening)
                                  const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                else ...[
                                  Text(
                                    model.error ?? '准备相机',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  TextButton(
                                    onPressed: model.initialize,
                                    child: const Text('重新打开相机'),
                                  ),
                                  if (widget.onOpenSettings != null)
                                    TextButton(
                                      onPressed: () => runUiAction(
                                        context,
                                        widget.onOpenSettings!,
                                      ),
                                      child: const Text('打开系统设置'),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: '导入照片',
                    onPressed: model.captureBusy || reviewing
                        ? null
                        : importPhoto,
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: '镜像参考图',
                    onPressed: model.captureBusy ? null : model.toggleMirror,
                    icon: Icon(
                      Icons.flip,
                      color: model.mirror
                          ? const Color(0xFFA8DFF1)
                          : Colors.white,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: model.countdown > 0 ? '取消倒计时' : '拍照',
                    iconSize: 56,
                    onPressed: model.countdown > 0
                        ? model.cancelCountdown
                        : model.captureBusy ||
                              reviewing ||
                              model.phase != CameraPhase.ready
                        ? null
                        : capture,
                    icon: model.captureBusy && model.countdown == 0
                        ? const SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(),
                          )
                        : Icon(
                            model.countdown > 0 ? Icons.close : Icons.circle,
                          ),
                  ),
                  IconButton(
                    tooltip: '移动参考',
                    onPressed: model.captureBusy
                        ? null
                        : () => setState(() => adjustGuide = !adjustGuide),
                    icon: Icon(
                      Icons.open_with,
                      color: adjustGuide
                          ? const Color(0xFFA8DFF1)
                          : Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: '切换摄像头',
                    onPressed:
                        model.captureBusy ||
                            model.phase == CameraPhase.opening ||
                            model.cameras.length < 2
                        ? null
                        : model.switchCamera,
                    icon: const Icon(
                      Icons.cameraswitch_outlined,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: model.captureBusy ? null : choosePose,
                child: const Text('换参考'),
              ),
            ],
          ),
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
