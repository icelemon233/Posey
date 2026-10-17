import 'package:posey/core/json.dart';

class CameraPreferences {
  const CameraPreferences({
    this.grid = false,
    this.mirror = false,
    this.showGuide = true,
    this.opacity = .38,
    this.guideScale = 1,
    this.guideX = 0,
    this.guideY = 0,
    this.timerSeconds = 0,
    this.poseId = '',
  });
  final bool grid, mirror, showGuide;
  final double opacity, guideScale, guideX, guideY;
  final int timerSeconds;
  final String poseId;
  factory CameraPreferences.fromJson(Json json) {
    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || !value.isFinite)
        throw const FormatException('相机设置格式无效');
      return value.toDouble().clamp(min, max);
    }

    return CameraPreferences(
      grid: json['grid'] == true,
      mirror: json['mirror'] == true,
      showGuide: json['showGuide'] != false,
      opacity: number('opacity', .38, .1, .85),
      guideScale: number('guideScale', 1, .3, 2.5),
      guideX: number('guideX', 0, -.6, .6),
      guideY: number('guideY', 0, -.6, .6),
      timerSeconds: [0, 3, 5, 10].contains(json['timerSeconds'])
          ? json['timerSeconds'] as int
          : 0,
      poseId: json['poseId'] as String? ?? '',
    );
  }
  Json toJson() => {
    'grid': grid,
    'mirror': mirror,
    'showGuide': showGuide,
    'opacity': opacity,
    'guideScale': guideScale,
    'guideX': guideX,
    'guideY': guideY,
    'timerSeconds': timerSeconds,
    'poseId': poseId,
  };
}
