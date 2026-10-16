import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/features/camera/camera_gateway.dart';
import 'package:posey/features/poses/pose_template.dart';

enum CameraPhase { idle, opening, ready, failed }

typedef CapturedPhoto = ({String path, PoseTemplate target});

class CameraViewModel extends ChangeNotifier {
  CameraViewModel(
    this._target, {
    required this.photos,
    this.gateway = const DeviceCameraGateway(),
  });
  final CameraGateway gateway;
  final PhotoLibrary photos;
  CameraSession? _session;
  List<CameraDescription> _cameras = [];
  PoseTemplate _target;
  CameraPhase _phase = CameraPhase.idle;
  String? _error;
  bool _disposed = false, _active = true, _captureBusy = false;
  bool _grid = false, _mirror = false, _showGuide = true;
  double _opacity = .38, _zoom = 1, _minZoom = 1, _maxZoom = 1;
  int _cameraIndex = 0, _generation = 0, _zoomRequest = 0;
  CameraController? get preview => _session?.preview;
  List<CameraDescription> get cameras => List.unmodifiable(_cameras);
  PoseTemplate get target => _target;
  CameraPhase get phase => _phase;
  String? get error => _error;
  bool get captureBusy => _captureBusy;
  bool get grid => _grid;
  bool get mirror => _mirror;
  bool get showGuide => _showGuide;
  bool get flashAuto => _session?.flashAuto ?? false;
  double get opacity => _opacity;
  double get zoom => _zoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed && _active && generation == _generation;

  Future<void> initialize() async {
    if (_disposed || !_active || _phase == CameraPhase.opening) return;
    final generation = ++_generation;
    _phase = CameraPhase.opening;
    _error = null;
    _notify();
    CameraSession? next;
    try {
      final devices = await gateway.devices();
      if (!_current(generation)) return;
      if (devices.isEmpty) throw StateError('没有找到可用的摄像头，可以导入照片继续。');
      _cameras = devices;
      _cameraIndex %= devices.length;
      final previous = _session;
      _session = null;
      await previous?.close();
      if (!_current(generation)) return;
      next = gateway.create(devices[_cameraIndex]);
      await next.initialize();
      if (!_current(generation)) {
        await _close(next);
        return;
      }
      final limits = await next.zoomLimits();
      if (!_current(generation)) {
        await _close(next);
        return;
      }
      _session = next;
      _minZoom = limits[0];
      _maxZoom = math.max(_minZoom, math.min(limits[1], 5));
      _zoom = _minZoom;
      _phase = CameraPhase.ready;
    } catch (failure) {
      await _close(next);
      if (!_current(generation)) return;
      _phase = CameraPhase.failed;
      _error = failure is CameraException
          ? switch (failure.code) {
              'CameraAccessDenied' ||
              'CameraAccessDeniedWithoutPrompt' ||
              'CameraAccessRestricted' => '相机权限尚未打开。请在系统设置中允许相机，或导入照片继续。',
              _ => '相机暂时无法使用，请重试或导入照片。',
            }
          : failure.toString().replaceFirst('Bad state: ', '');
    }
    _notify();
  }

  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    if (value) {
      unawaited(initialize());
      return;
    }
    _generation++;
    final previous = _session;
    _session = null;
    _phase = CameraPhase.idle;
    unawaited(_close(previous));
    _notify();
  }

  Future<void> switchCamera() async {
    if (_captureBusy || _phase == CameraPhase.opening || _cameras.length < 2) {
      return;
    }
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await initialize();
  }

  Future<CapturedPhoto?> capture() async {
    final session = _session, pose = _target;
    if (_captureBusy ||
        _phase != CameraPhase.ready ||
        session == null ||
        _disposed) {
      return null;
    }
    final generation = _generation;
    _captureBusy = true;
    _notify();
    try {
      final path = await session.capture();
      return _current(generation) ? (path: path, target: pose) : null;
    } catch (_) {
      if (_current(generation)) throw StateError('拍摄失败，请稍后再试。');
      return null;
    } finally {
      _captureBusy = false;
      _notify();
    }
  }

  Future<CapturedPhoto?> importPhoto() async {
    if (_captureBusy || _disposed) return null;
    final pose = _target;
    _captureBusy = true;
    _notify();
    try {
      final path = await photos.pickPhoto();
      return path != null && !_disposed ? (path: path, target: pose) : null;
    } finally {
      _captureBusy = false;
      _notify();
    }
  }

  Future<void> toggleFlash() async {
    try {
      await _session?.toggleFlash();
    } catch (_) {
      throw StateError('当前摄像头不支持闪光灯。');
    }
    _notify();
  }

  Future<void> setZoom(double value) async {
    final session = _session,
        generation = _generation,
        request = ++_zoomRequest;
    if (session == null || _phase != CameraPhase.ready) return;
    final next = value.clamp(_minZoom, _maxZoom).toDouble();
    await session.setZoom(next);
    if (_current(generation) && request == _zoomRequest) {
      _zoom = next;
      _notify();
    }
  }

  void toggleGrid() {
    _grid = !_grid;
    _notify();
  }

  void toggleMirror() {
    _mirror = !_mirror;
    _notify();
  }

  void toggleGuide() {
    _showGuide = !_showGuide;
    _notify();
  }

  void setOpacity(double value) {
    _opacity = value.clamp(.1, .85).toDouble();
    _notify();
  }

  void selectPose(PoseTemplate pose) {
    _target = pose;
    _notify();
  }

  Future<void> _close(CameraSession? session) async {
    try {
      await session?.close();
    } catch (_) {
      // The plugin may already have released the device on a lifecycle change.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    final previous = _session;
    _session = null;
    unawaited(_close(previous));
    super.dispose();
  }
}
