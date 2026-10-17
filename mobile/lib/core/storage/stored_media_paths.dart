import 'package:posey/core/json.dart';
import 'package:posey/core/storage/posey_storage.dart';

/// App containers may move during iOS updates. Restore only files already owned
/// by the current installation, using their generated, unique file names.
class StoredMediaPaths {
  StoredMediaPaths(List<StoredMediaFile> files)
    : _names = {
        for (final file in files)
          file.path.replaceAll('\\', '/').split('/').last: file.path.replaceAll(
            '\\',
            '/',
          ),
      };
  final Map<String, String> _names;
  String resolve(String path) =>
      _names[path.replaceAll('\\', '/').split('/').last] ?? path;
  Json pose(Json raw) =>
      raw['userReference'] == true && raw['illustration'] is String
      ? {...raw, 'illustration': resolve(raw['illustration'] as String)}
      : raw;
  Json work(Json raw) => {
    ...raw,
    if (raw['path'] is String) 'path': resolve(raw['path'] as String),
    if (raw['originalPath'] is String)
      'originalPath': resolve(raw['originalPath'] as String),
    if (raw['pose'] is Map) 'pose': pose(objectOf(raw['pose'])),
  };
  Json job(Json raw) => {
    ...raw,
    if (raw['sourcePath'] is String)
      'sourcePath': resolve(raw['sourcePath'] as String),
    if (raw['resultPath'] is String)
      'resultPath': resolve(raw['resultPath'] as String),
    if (raw['targetSnapshot'] is Map)
      'targetSnapshot': pose(objectOf(raw['targetSnapshot'])),
  };
}
