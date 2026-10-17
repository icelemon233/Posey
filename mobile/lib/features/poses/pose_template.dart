import 'package:posey/core/json.dart';

class PoseTemplate {
  PoseTemplate(Json raw) : raw = Map.unmodifiable(raw);
  final Json raw;
  factory PoseTemplate.fromJson(Json json) {
    if (json['id'] is! String ||
        json['title'] is! String ||
        json['illustration'] is! String ||
        (json['id'] as String).isEmpty ||
        (json['title'] as String).trim().isEmpty ||
        (json['title'] as String).length > 80) {
      throw const FormatException('姿势模板不完整');
    }
    for (final key in ['steps', 'scenes', 'props', 'tags']) {
      if (json[key] != null &&
          (json[key] is! List ||
              (json[key] as List).length > 100 ||
              (json[key] as List).any((value) => value is! String))) {
        throw const FormatException('参考说明格式无效');
      }
    }
    if (json['category'] != null &&
            ![
              'standing',
              'half',
              'seated',
              'crouching',
            ].contains(json['category']) ||
        json['gender'] != null &&
            !['male', 'female', 'all'].contains(json['gender'])) {
      throw const FormatException('参考分类格式无效');
    }
    for (final key in ['subtitle', 'cameraHint', 'accent']) {
      if (json[key] != null && json[key] is! String) {
        throw const FormatException('参考文字格式无效');
      }
    }
    if (json['source'] != null && json['source'] is! Map) {
      throw const FormatException('参考来源格式无效');
    }
    for (final key in ['label', 'evidenceStatus', 'usageStatus']) {
      if (objectOf(json['source'])[key] != null &&
          objectOf(json['source'])[key] is! String) {
        throw const FormatException('参考来源格式无效');
      }
    }
    return PoseTemplate(json);
  }
  String get id => raw['id'] as String;
  String get title => raw['title'] as String;
  String get subtitle => raw['subtitle'] as String? ?? '';
  String get illustration => raw['illustration'] as String;
  String get category => raw['category'] as String? ?? 'standing';
  String get gender => raw['gender'] as String? ?? 'female';
  bool get isUserReference => raw['userReference'] == true;
  bool get available => raw['unavailable'] != true;
  bool get mirrored => raw['mirrorReference'] == true;
  PoseTemplate withMirror(bool value) =>
      PoseTemplate({...raw, 'mirrorReference': value});
  List<String> get steps => stringsOf(raw['steps']);
  List<String> get scenes => stringsOf(raw['scenes']);
  List<String> get props => stringsOf(raw['props']);
  String get cameraHint => raw['cameraHint'] as String? ?? '';
  List<String> get tags => stringsOf(raw['tags']);
  Json get landmarks => objectOf(raw['landmarks']);
  int get accent =>
      (int.tryParse(
            (raw['accent'] as String? ?? '#E7C7FF').replaceFirst('#', ''),
            radix: 16,
          )?.toUnsigned(32) ??
          0xE7C7FF) |
      0xFF000000;
  String get sourceLabel =>
      objectOf(raw['source'])['label'] as String? ?? 'Posey 姿势参考';
  bool get experimental =>
      objectOf(raw['source'])['evidenceStatus'] == 'experimental';
  bool matches(String query, String selectedGender, String selectedCategory) =>
      (selectedGender == 'all' ||
          gender == 'all' ||
          gender == selectedGender) &&
      (selectedCategory == 'all' || category == selectedCategory) &&
      ('$title $subtitle ${tags.join(' ')} ${scenes.join(' ')} ${props.join(' ')}'
          .toLowerCase()
          .contains(query.trim().toLowerCase()));
}
