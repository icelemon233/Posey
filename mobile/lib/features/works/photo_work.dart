import 'package:posey/core/json.dart';
import 'package:posey/features/poses/pose_template.dart';

enum WorkKind { photo, edit, ai }

class PhotoWork {
  const PhotoWork({
    required this.id,
    required this.path,
    required this.pose,
    required this.createdAt,
    this.kind = WorkKind.photo,
    this.originalPath,
    this.sourceWorkId,
    this.aiJobId,
    this.savedToGallery = false,
    this.importId,
  });
  final String id, path;
  final PoseTemplate pose;
  final int createdAt;
  final WorkKind kind;
  final String? originalPath, sourceWorkId, aiJobId;
  final bool savedToGallery;
  final String? importId;
  String get original => originalPath ?? path;
  PhotoWork copyWith({bool? savedToGallery}) => PhotoWork(
    id: id,
    path: path,
    pose: pose,
    createdAt: createdAt,
    kind: kind,
    originalPath: originalPath,
    sourceWorkId: sourceWorkId,
    aiJobId: aiJobId,
    savedToGallery: savedToGallery ?? this.savedToGallery,
    importId: importId,
  );
  factory PhotoWork.fromJson(Json json) {
    if (json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['path'] is! String ||
        json['createdAt'] is! num ||
        json['pose'] is! Map) {
      throw const FormatException('作品记录不完整');
    }
    if (!(json['createdAt'] as num).isFinite ||
        (json['createdAt'] as num) < 0 ||
        json['kind'] != null &&
            !WorkKind.values.any((kind) => kind.name == json['kind']) ||
        json['savedToGallery'] != null && json['savedToGallery'] is! bool) {
      throw const FormatException('作品时间、类型或相册标记无效');
    }
    return PhotoWork(
      id: json['id'],
      path: json['path'],
      createdAt: integerOf(json['createdAt']),
      pose: PoseTemplate.fromJson(objectOf(json['pose'])),
      kind: WorkKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => WorkKind.photo,
      ),
      originalPath: json['originalPath'] as String?,
      sourceWorkId: json['sourceWorkId'] as String?,
      aiJobId: json['aiJobId'] as String?,
      savedToGallery: json['savedToGallery'] == true,
      importId: json['importId'] as String?,
    );
  }
  Json toJson() => {
    'id': id,
    'path': path,
    'pose': pose.raw,
    'createdAt': createdAt,
    'kind': kind.name,
    'originalPath': originalPath,
    'sourceWorkId': sourceWorkId,
    'aiJobId': aiJobId,
    'savedToGallery': savedToGallery,
    if (importId != null) 'importId': importId,
  };
}
