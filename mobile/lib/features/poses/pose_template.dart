import 'package:posey/core/json.dart';

class PoseTemplate {
  PoseTemplate(Json raw) : raw = Map.unmodifiable(raw);
  final Json raw;
  factory PoseTemplate.fromJson(Json json) {
    if (json['id'] is! String ||
        json['title'] is! String ||
        json['illustration'] is! String) {
      throw const FormatException('姿势模板不完整');
    }
    return PoseTemplate(json);
  }
  String get id => raw['id'] as String;
  String get title => raw['title'] as String;
  String get subtitle => raw['subtitle'] as String? ?? '';
  String get illustration => raw['illustration'] as String;
  String get category => raw['category'] as String? ?? 'standing';
  String get gender => raw['gender'] as String? ?? 'female';
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
      (selectedGender == 'all' || gender == selectedGender) &&
      (selectedCategory == 'all' || category == selectedCategory) &&
      ('$title $subtitle ${tags.join(' ')}'.toLowerCase().contains(
        query.trim().toLowerCase(),
      ));
}
