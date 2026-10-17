import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/media/image_format.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/works/photo_work.dart';
import 'package:posey/features/camera/camera_preferences.dart';

const maxBackupBytes = 1024 * 1024 * 1024,
    maxBackupMediaBytes = 24 * 1024 * 1024,
    maxManifestBytes = 8 * 1024 * 1024;

class BackupSnapshot {
  const BackupSnapshot({
    required this.poses,
    required this.works,
    required this.favorites,
    required this.recents,
    required this.interfaceSettings,
    required this.installationId,
    required this.assetReferences,
  });
  final List<PoseTemplate> poses;
  final List<PhotoWork> works;
  final Set<String> favorites;
  final Map<String, int> recents;
  final Json interfaceSettings;
  final String installationId;
  final Set<String> assetReferences;
}

class BackupEncoding {
  const BackupEncoding(this.manifest, this.files, this.output);
  final Json manifest;
  final Map<String, String> files;
  final String output;
}

BackupEncoding prepareBackup(
  BackupSnapshot snapshot,
  String output,
  Set<String> ownedPaths,
) {
  final files = <String, String>{}, aliases = <String, String>{};
  String media(String path) {
    if (!ownedPaths.contains(path))
      throw const FormatException('备份中有无法读取的本机照片，请先恢复或移除该记录。');
    return aliases.putIfAbsent(path, () {
      final name =
          'media/${aliases.length.toString().padLeft(5, '0')}.${path.split('.').last}';
      files[name] = path;
      return name;
    });
  }

  Json pose(PoseTemplate value) => {
    ...value.raw,
    if (value.isUserReference) 'illustration': media(value.illustration),
  };
  final works = [
    for (final work in snapshot.works)
      {
        ...work.toJson(),
        'path': media(work.path),
        if (work.originalPath != null)
          'originalPath': media(work.originalPath!),
        'pose': pose(work.pose),
      },
  ];
  final manifest = <String, dynamic>{
    'app': 'posey',
    'schemaVersion': 1,
    'installationId': snapshot.installationId,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'poses': snapshot.poses.map(pose).toList(),
    'works': works,
    'favorites': snapshot.favorites.toList(),
    'recents': snapshot.recents,
    'interfaceSettings': snapshot.interfaceSettings,
  };
  validateBackupManifest(manifest, {
    'manifest.json',
    ...files.keys,
  }, snapshot.assetReferences);
  return BackupEncoding(
    objectOf(jsonDecode(jsonEncode(manifest))),
    files,
    output,
  );
}

int encodeBackup(BackupEncoding input) {
  final encoded = utf8.encode(jsonEncode(input.manifest));
  if (encoded.length > maxManifestBytes || input.files.length > 3000)
    throw const FormatException('备份记录过多，请缩小范围。');
  var total = encoded.length;
  for (final path in input.files.values) {
    final size = File(path).lengthSync();
    if (size > maxBackupMediaBytes)
      throw const FormatException('单张照片超过 24 MB，请先压缩后再备份。');
    total += size;
  }
  if (total > maxBackupBytes - 1024 * 1024)
    throw const FormatException('备份超过 1 GB，请选择较少的作品。');
  final encoder = ZipFileEncoder();
  encoder.create(input.output);
  try {
    encoder.addArchiveFile(ArchiveFile.bytes('manifest.json', encoded));
    for (final entry in input.files.entries) {
      final source=InputFileStream(entry.value);
      try{encoder.addArchiveFile(ArchiveFile.stream(entry.key,source)..compression=CompressionType.none);}
      finally{source.closeSync();}
    }
  } finally {
    encoder.closeSync();
  }
  final size = File(input.output).lengthSync();
  if (size > maxBackupBytes) throw const FormatException('备份超过 1 GB，请缩小范围。');
  return size;
}

class DecodedBackup {
  const DecodedBackup(this.manifest, this.files);
  final Json manifest;
  final Map<String, String> files;
}

class BackupDecoding {
  const BackupDecoding(
    this.path,
    this.directory,
    this.prefix,
    this.assetReferences,
  );
  final String path, directory, prefix;
  final Set<String> assetReferences;
}

DecodedBackup decodeBackup(BackupDecoding input) {
  if (File(input.path).lengthSync() > maxBackupBytes)
    throw const FormatException('备份文件超过 1 GB');
  final stream = InputFileStream(input.path);
  final staged = <String, String>{};
  try {
    _validateZipEnvelope(input.path);
    final directory=ZipDirectory()..read(stream);
    final rawNames=<String>{};var rawTotal=0;
    for(final header in directory.fileHeaders){
      final name=header.filename,size=header.uncompressedSize;
      if(!rawNames.add(name)||((header.externalFileAttributes>>16)&0xf000)==0xa000||(header.generalPurposeBitFlag&1)!=0)throw const FormatException('备份含有重复、链接或加密文件');
      if(size<0||size>(name=='manifest.json'?maxManifestBytes:maxBackupMediaBytes))throw const FormatException('备份文件大小无效');
      rawTotal+=size;if(rawTotal>maxBackupBytes)throw const FormatException('备份展开后超过 1 GB');
    }
    stream.setPosition(0);
    final archive = ZipDecoder().decodeStream(stream, verify: false);
    if (archive.length > 3001) throw const FormatException('备份文件数量过多');
    final names = <String>{};
    var total = 0;
    final mediaPattern = RegExp(r'^media/[a-zA-Z0-9_.-]+\.(jpg|png|webp)$');
    for (final file in archive) {
      if (file.isSymbolicLink ||
          !file.isFile ||
          !names.add(file.name) ||
          file.name != 'manifest.json' && !mediaPattern.hasMatch(file.name))
        throw const FormatException('备份含有无效或重复的文件路径');
      if (file.name.contains('..') ||
          file.size < 0 ||
          file.size >
              (file.name == 'manifest.json'
                  ? maxManifestBytes
                  : maxBackupMediaBytes))
        throw const FormatException('备份文件大小或路径无效');
      total += file.size;
      if (total > maxBackupBytes) throw const FormatException('备份展开后超过 1 GB');
    }
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) throw const FormatException('这不是 Posey 备份文件');
    final manifestBytes = manifestFile.content;
    if (manifestBytes.length != manifestFile.size ||
        manifestFile.crc32 != null &&
            getCrc32(manifestBytes) != manifestFile.crc32)
      throw const FormatException('备份清单校验失败');
    final raw = jsonDecode(utf8.decode(manifestBytes));
    if (raw is! Map) throw const FormatException('备份清单格式无效');
    final manifest = objectOf(raw);
    validateBackupManifest(manifest, names, input.assetReferences);
    for (final file in archive.where((file) => file.name != 'manifest.json')) {
      final extension = file.name.split('.').last;
      final path =
          '${input.directory}/backup-import-${input.prefix}-${staged.length}.$extension';
      staged[file.name] = path;
      final output = OutputFileStream(path);
      try {
        file.writeContent(output);
      } finally {
        output.closeSync();
      }
      final bytes = File(path).readAsBytesSync();
      if (bytes.length != file.size ||
          file.crc32 != null && getCrc32(bytes) != file.crc32 ||
          imageExtension(bytes) != extension)
        throw const FormatException('备份照片校验失败');
    }
    return DecodedBackup(manifest, staged);
  } catch (_) {
    for (final path in staged.values) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
    rethrow;
  } finally {
    stream.closeSync();
  }
}

void _validateZipEnvelope(String path) {
  final file=File(path).openSync();
  try{
    final length=file.lengthSync();if(length<22)throw const FormatException('备份文件不完整');
    final tailLength=length<65557?length:65557;file.setPositionSync(length-tailLength);
    final tail=file.readSync(tailLength),data=ByteData.sublistView(tail);
    for(var at=tail.length-22;at>=0;at--){
      if(data.getUint32(at,Endian.little)!=0x06054b50||at+22+data.getUint16(at+20,Endian.little)!=tail.length)continue;
      final count=data.getUint16(at+10,Endian.little),disk=data.getUint16(at+4,Endian.little),directoryDisk=data.getUint16(at+6,Endian.little);
      if(count>3001||disk!=0||directoryDisk!=0||data.getUint16(at+8,Endian.little)!=count)throw const FormatException('备份文件数量或分卷格式无效');
      return;
    }
    throw const FormatException('备份缺少 ZIP 目录');
  }finally{file.closeSync();}
}

void validateBackupManifest(Json json, Set<String> files, Set<String> assets) {
  if (json['app'] != 'posey' || json['schemaVersion'] != 1)
    throw const FormatException('不支持此备份版本，请更新应用后再试。');
  List<dynamic> list(String key, int max) {
    final value = json[key];
    if (value is! List || value.length > max)
      throw const FormatException('备份记录数量或格式无效');
    return value;
  }

  void id(dynamic value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 160 ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value))
      throw const FormatException('备份编号无效');
  }

  void media(dynamic value) {
    if (value is! String ||
        !files.contains(value) ||
        !value.startsWith('media/'))
      throw const FormatException('备份缺少引用的照片');
  }

  void pose(Json value, {bool custom = false}) {
    final model = PoseTemplate.fromJson(value);
    id(model.id);
    if (custom && !model.isUserReference)
      throw const FormatException('备份自有参考类型无效');
    if (model.isUserReference) {
      media(model.illustration);
    } else if (model.available && !assets.contains(model.illustration)) {
      throw const FormatException('备份引用的内置参考不在当前版本，请更新应用。');
    }
    for (final key in ['steps', 'tags', 'scenes', 'props']) {
      final values = value[key];
      if (values != null &&
          (values is! List ||
              values.length > 30 ||
              values.any((text) => text is! String || text.length > 400)))
        throw const FormatException('参考说明格式无效');
    }
    if (value['category'] != null &&
        ![
          'standing',
          'half',
          'seated',
          'crouching',
        ].contains(value['category']))
      throw const FormatException('参考分类无效');
    if (value['gender'] != null &&
        !['male', 'female', 'all'].contains(value['gender']))
      throw const FormatException('参考筛选无效');
    if (value['source'] != null && value['source'] is! Map ||
        value['accent'] != null && value['accent'] is! String ||
        value['subtitle'] != null && value['subtitle'] is! String ||
        value['cameraHint'] != null && value['cameraHint'] is! String)
      throw const FormatException('参考字段格式无效');
  }

  final poses = list('poses', 500), poseIds = <String>{};
  for (final value in poses) {
    if (value is! Map) throw const FormatException('自有参考格式无效');
    final record = objectOf(value);
    pose(record, custom: true);
    if (!poseIds.add(record['id'])) throw const FormatException('备份参考编号重复');
  }
  final works = list('works', 1000), workIds = <String>{};
  for (final value in works) {
    if (value is! Map) throw const FormatException('作品格式无效');
    final record = objectOf(value);
    id(record['id']);
    if (!workIds.add(record['id'])) throw const FormatException('备份作品编号重复');
    media(record['path']);
    if (record['originalPath'] != null) media(record['originalPath']);
    if (record['pose'] is! Map) throw const FormatException('作品缺少参考记录');
    pose(objectOf(record['pose']));
    if (!['photo', 'edit', 'ai'].contains(record['kind']) ||
        record['createdAt'] is! num ||
        !(record['createdAt'] as num).isFinite ||
        record['createdAt'] < 0)
      throw const FormatException('作品时间或类型无效');
    for (final key in ['sourceWorkId', 'aiJobId', 'importId']) {
      if (record[key] != null) id(record[key]);
    }
    if (record['savedToGallery'] != null && record['savedToGallery'] is! bool)
      throw const FormatException('相册标记无效');
  }
  for (final value in list('favorites', 10000)) {
    id(value);
  }
  final recents = json['recents'];
  if (recents is! Map || recents.length > 1000)
    throw const FormatException('最近使用格式无效');
  for (final entry in recents.entries) {
    id(entry.key);
    if (entry.value is! num || !(entry.value as num).isFinite)
      throw const FormatException('最近使用时间无效');
  }
  final settings = json['interfaceSettings'];
  if (settings is! Map) throw const FormatException('界面设置格式无效');
  final values = objectOf(settings);
  if (values.keys.any(
        (key) =>
            !['theme', 'themeMode', 'shuffleFavorites', 'camera'].contains(key),
      ) ||
      !['system', 'light', 'dark'].contains(values['themeMode']) ||
      values['theme'] is! String ||
      values['shuffleFavorites'] is! bool ||
      values['camera'] is! Map)
    throw const FormatException('备份界面设置含有无效字段');
  CameraPreferences.fromJson(objectOf(values['camera']));
  if (json['installationId'] is! String)
    throw const FormatException('备份来源标记无效');
}
