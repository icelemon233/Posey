import 'package:posey/core/json.dart';

class AiPreferences {
  const AiPreferences({
    this.face = 'strict',
    this.expression = 'preserve',
    this.gaze = 'preserve',
  });
  final String face, expression, gaze;
  factory AiPreferences.fromJson(Json json) => AiPreferences(
    face: ['strict', 'natural'].contains(json['faceFidelity'])
        ? json['faceFidelity'] as String
        : 'strict',
    expression: ['preserve', 'subtle'].contains(json['expression'])
        ? json['expression'] as String
        : 'preserve',
    gaze: ['preserve', 'follow-pose'].contains(json['gaze'])
        ? json['gaze'] as String
        : 'preserve',
  );
  Json toJson() => {
    'faceFidelity': face,
    'expression': expression,
    'gaze': gaze,
  };
}

class AiConfiguration {
  const AiConfiguration({
    this.key = '',
    this.endpoint = 'https://ark.cn-beijing.volces.com/api/v3',
    this.model = 'doubao-seedream-5-0-pro-260628',
  });
  final String key, endpoint, model;
  String get normalizedKey => key
      .replaceFirst(RegExp(r'^ARK_API_KEY\s*=\s*'), '')
      .replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '');
  Uri get baseUri {
    final parsed = Uri.parse(endpoint.trim());
    var path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/images/generations')) {
      path = path.substring(0, path.length - 19);
    }
    return parsed.replace(path: path);
  }

  Uri get uri => baseUri.replace(path: '${baseUri.path}/images/generations');
  void validate() {
    if (normalizedKey.isEmpty) {
      throw const FormatException('请先在设置中填写你的火山方舟 API Key');
    }
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('AI 服务需要有效的 HTTPS 地址');
    }
    if (model.trim().isEmpty) throw const FormatException('请选择可用的图像模型');
  }

  Json metadata() => {'endpoint': baseUri.toString(), 'model': model.trim()};
}

class AiRequestOptions {
  const AiRequestOptions(
    this.configuration,
    this.preferences, {
    this.frozenPrompt,
  });
  final AiConfiguration configuration;
  final AiPreferences preferences;
  final String? frozenPrompt;
  Json metadata() => {
    ...configuration.metadata(),
    'preferences': preferences.toJson(),
  };
}

class AiConnectionCheck {
  const AiConnectionCheck(this.message, this.models, {this.verified = false});
  final String message;
  final List<String> models;
  final bool verified;
}

abstract interface class AiConnectionTester {
  Future<AiConnectionCheck> checkConnection(AiConfiguration configuration);
  void cancelConnectionCheck();
}

String buildPosePrompt(String title, AiPreferences preferences) {
  final safeTitle = title.length > 80 ? title.substring(0, 80) : title;
  return [
    '这是一次局部姿势编辑，不是重新生成人像。生成一张写实且自然的人像编辑照片。',
    '图1是待修改的原始照片。必须保留同一个人物的身份、发型、服装、身材比例、背景、光线、相机角度、构图和照片风格。',
    preferences.face == 'strict'
        ? '面部是不可编辑的身份区域：严格锁定图1的脸型、五官形状与比例、皮肤真实纹理、妆容、年龄特征和头发边界。不要重新绘制、对称化、美颜、磨皮或替换人脸；当目标姿势与面部保持冲突时，优先保持图1面部不变。'
        : '保持图1人物身份、脸型、五官比例、年龄特征、妆容和真实皮肤纹理，只允许为新的头部角度做极轻微且自然的光影过渡；不要美颜、磨皮、对称化或替换人脸。',
    preferences.expression == 'preserve'
        ? '严格保持图1的原始表情和情绪：眉形、眼睑开合、面部肌肉、嘴唇形状与开合、牙齿可见状态必须一致，不要新增微笑、张嘴、皱眉或其他微表情。'
        : '保持图1的原始情绪类别，只允许为身体姿势做极轻微的面部肌肉过渡；嘴唇开合、牙齿可见状态和主要表情不能改变。',
    preferences.gaze == 'preserve'
        ? '严格保持图1的视线方向、瞳孔位置和眼睛开合，不要让人物改看镜头或看向其他方向。'
        : '视线可以轻微顺应目标姿势，但必须保持图1的眼睛形状、开合、虹膜外观和自然聚焦，不要产生空洞、斜视或不一致的双眼。',
    '图2只作为“$safeTitle”的目标姿势参考，不要复制图2的人物身份、服装、颜色、插画风格或背景。',
    '只改变完成目标姿势所必需的躯干和四肢位置，使其尽可能自然地贴合图2；头部和面部保持受保护。',
    '保持人物数量不变，四肢连接自然、人体结构合理，不要裁掉图1中原本可见的肢体。',
    '不要添加文字、字幕、边框、标志或水印。',
  ].join();
}
