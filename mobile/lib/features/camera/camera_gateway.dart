import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';

abstract interface class CameraGateway {
  Future<List<CameraDescription>> devices();
  CameraSession create(CameraDescription device);
}

abstract interface class CameraSession {
  CameraController? get preview;
  bool get flashAuto;
  Future<void> initialize();
  Future<List<double>> zoomLimits();
  Future<void> setZoom(double value);
  Future<bool> focusAt(Offset point);
  Future<void> toggleFlash();
  Future<String> capture();
  Future<void> close();
}

class DeviceCameraGateway implements CameraGateway {
  const DeviceCameraGateway();
  @override
  Future<List<CameraDescription>> devices() => availableCameras();
  @override
  CameraSession create(CameraDescription device) =>
      _DeviceCameraSession(device);
}

class _DeviceCameraSession implements CameraSession {
  _DeviceCameraSession(CameraDescription device)
    : _controller = CameraController(
        device,
        ResolutionPreset.high,
        enableAudio: false,
      );
  final CameraController _controller;
  @override
  CameraController get preview => _controller;
  @override
  bool get flashAuto => _controller.value.flashMode == FlashMode.auto;
  @override
  Future<void> initialize() async {
    await _controller.initialize();
  }

  @override
  Future<List<double>> zoomLimits() => Future.wait([
    _controller.getMinZoomLevel(),
    _controller.getMaxZoomLevel(),
  ]);
  @override
  Future<void> setZoom(double value) => _controller.setZoomLevel(value);
  @override
  Future<bool> focusAt(Offset point) async {
    if (!_controller.value.focusPointSupported) return false;
    await _controller.setFocusPoint(point);
    if (_controller.value.exposurePointSupported) {
      await _controller.setExposurePoint(point);
    }
    return true;
  }

  @override
  Future<void> toggleFlash() =>
      _controller.setFlashMode(flashAuto ? FlashMode.off : FlashMode.auto);
  @override
  Future<String> capture() async => (await _controller.takePicture()).path;
  @override
  Future<void> close() => _controller.dispose();
}
