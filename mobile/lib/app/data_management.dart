import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/media/device_platform.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/core/storage/storage_transaction.dart';
import 'package:posey/features/ai_pose/ai_jobs_view_model.dart';
import 'package:posey/features/backup/backup_archive.dart';
import 'package:posey/features/backup/backup_manager.dart';
import 'package:posey/features/poses/pose_library_view_model.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/settings/settings_view_model.dart';
import 'package:posey/features/works/works_repository.dart';
import 'package:posey/features/works/photo_work.dart';

BackupManager createBackupManager({
  required PoseyStorage storage,
  required DevicePlatform platform,
  required PoseLibraryViewModel library,
  required SettingsViewModel settings,
  required WorksRepository works,
  required AiJobsViewModel jobs,
  required Future<void> Function() reload,
  required void Function(String) fatal,
}) {
  Future<void> settle() =>
      Future.wait([library.settle(), settings.settle(), works.settle()]);
  Future<String> installation() async {
    final current = await storage.read('installation-id-v1');
    if (current != null) return current;
    final id = const Uuid().v4();
    await storage.write('installation-id-v1', id);
    return id;
  }

  Set<String> references() => {
    ...works.referencedPaths,
    ...library.custom.map((pose) => pose.illustration),
    for (final job in jobs.jobs) ...[
      job.sourcePath,
      if (job.resultPath != null) job.resultPath!,
      if (job.targetSnapshot?['userReference'] == true &&
          job.targetSnapshot?['illustration'] is String)
        job.targetSnapshot!['illustration'] as String,
    ],
  };
  return BackupManager(
    storage: storage,
    platform: platform,
    assets: () => library.templates
        .where((pose) => !pose.isUserReference)
        .map((pose) => pose.illustration)
        .toSet(),
    canImport: () =>
        jobs.activeJobs == 0 &&
        !jobs.hasPendingIO &&
        !works.hasPendingWrites &&
        library.loadErrors.isEmpty &&
        settings.loadError == null &&
        works.loadError == null,
    snapshot: (limit) async {
      await settle();
      if (library.loadErrors.isNotEmpty ||
          settings.loadError != null ||
          works.loadError != null) {
        throw StateError('部分资料尚未恢复，请恢复后再导出完整备份。');
      }
      return BackupSnapshot(
        poses: library.custom,
        works: limit == null ? works.works : works.works.take(limit).toList(),
        favorites: library.favorites,
        recents: library.recents,
        installationId: await installation(),
        interfaceSettings: {
          'theme': settings.theme,
          'themeMode': settings.themeMode,
          'shuffleFavorites': settings.shuffleFavorites,
          'camera': settings.camera.toJson(),
        },
        assetReferences: library.templates
            .where((pose) => !pose.isUserReference)
            .map((pose) => pose.illustration)
            .toSet(),
      );
    },
    apply: (data, restoreInterface) async {
      await settle();
      final incoming = data.manifest;
      String media(dynamic value) {
        final path = data.files[value];
        if (path == null) throw const FormatException('备份照片缺失');
        return path;
      }

      PoseTemplate pose(dynamic value) {
        final raw = objectOf(value);
        return PoseTemplate.fromJson({
          ...raw,
          if (raw['userReference'] == true)
            'illustration': media(raw['illustration']),
        });
      }

      final custom = [...library.custom],
          poseIds = custom.map((pose) => pose.id).toSet();
      for (final raw in incoming['poses'] as List) {
        final next = pose(raw);
        if (poseIds.add(next.id)) custom.add(next);
      }
      final allWorks = [...works.works],
          workIds = allWorks.map((work) => work.id).toSet(),
          aiIds = allWorks
              .map((work) => work.aiJobId)
              .whereType<String>()
              .toSet();
      final sameInstallation =
          incoming['installationId'] == await installation();
      for (final value in incoming['works'] as List) {
        final raw = objectOf(value);
        if (workIds.contains(raw['id']) ||
            raw['aiJobId'] != null && aiIds.contains(raw['aiJobId'])) {
          continue;
        }
        final next = PhotoWork.fromJson({
          ...raw,
          'path': media(raw['path']),
          if (raw['originalPath'] != null)
            'originalPath': media(raw['originalPath']),
          'pose': pose(raw['pose']).raw,
          'savedToGallery': sameInstallation && raw['savedToGallery'] == true,
        });
        allWorks.add(next);
        workIds.add(next.id);
        if (next.aiJobId != null) aiIds.add(next.aiJobId!);
      }
      allWorks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final recents = {...library.recents};
      for (final entry in objectOf(incoming['recents']).entries) {
        final time = (entry.value as num).toInt();
        if (time > (recents[entry.key] ?? 0)) recents[entry.key] = time;
      }
      final recentEntries = recents.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final changes = <String, String>{
        'custom-poses-v1': jsonEncode(custom.map((pose) => pose.raw).toList()),
        'works-v1': jsonEncode(allWorks.map((work) => work.toJson()).toList()),
        'favorites': jsonEncode(
          {...library.favorites, ...stringsOf(incoming['favorites'])}.toList(),
        ),
        'recent-poses-v1': jsonEncode(Map.fromEntries(recentEntries.take(100))),
      };
      if (restoreInterface) {
        final options = objectOf(incoming['interfaceSettings']);
        changes.addAll({
          'theme': options['theme'] as String,
          'theme-mode': options['themeMode'] as String,
          'shuffle-favorites': '${options['shuffleFavorites']}',
          'camera-preferences-v1': jsonEncode(options['camera']),
        });
      }
      try {
        await writeStorageBatch(storage, changes);
        await reload();
      } catch (_) {
        if (await storage.read('pending-transaction-v1') != null) {
          fatal('导入未完成，恢复记录已保留。请重新加载资料后再继续。');
        }
        rethrow;
      }
      return {
        for (final work in allWorks) ...[
          work.path,
          work.original,
          if (work.pose.isUserReference) work.pose.illustration,
        ],
        ...custom.map((pose) => pose.illustration),
      };
    },
    statistics: () async {
      final files = await storage.mediaFiles(),
          keys = await storage.recordKeys();
      final native = platform.supported
          ? await platform.storageUsage()
          : <String, dynamic>{};
      return {
        'bytes':
            files.fold<int>(0, (sum, file) => sum + file.bytes) +
            integerOf(native['bytes']),
        'works': works.works.length,
        'references': library.custom.length,
        'recovery':
            keys.where((key) => key.contains('-recovery-')).length +
            integerOf(native['recovery']),
      };
    },
    cleanup: () async {
      await settle();
      var bytes = platform.supported ? await platform.clearTemporaryFiles() : 0;
      final keys = await storage.recordKeys();
      if (jobs.activeJobs > 0 ||
          jobs.hasPendingIO ||
          works.hasPendingWrites ||
          library.loadErrors.isNotEmpty ||
          works.loadError != null ||
          jobs.loadError != null ||
          keys.any((key) => key.contains('-recovery-')) ||
          await storage.read('pending-transaction-v1') != null) {
        return bytes;
      }
      final retained = references();
      final pending = await storage.read('pending-import-v1');
      if (pending != null) return bytes;
      for (final file in await storage.mediaFiles()) {
        if (!retained.contains(file.path)) {
          await storage.deleteOwnedFile(file.path);
          bytes += file.bytes;
        }
      }
      return bytes;
    },
  );
}

Future<void> cleanRemovedMedia(
  PoseyStorage storage,
  PoseLibraryViewModel library,
  WorksRepository works,
  AiJobsViewModel jobs,
  Set<String> candidates,
) async {
  if (library.loadErrors.isNotEmpty ||
      works.loadError != null ||
      jobs.loadError != null ||
      jobs.hasPendingIO ||
      jobs.activeJobs > 0) {
    return;
  }
  if ((await storage.recordKeys()).any((key) => key.contains('-recovery-')) ||
      await storage.read('pending-transaction-v1') != null ||
      await storage.read('pending-import-v1') != null) {
    return;
  }
  final retained = {
    ...works.referencedPaths,
    ...library.custom.map((pose) => pose.illustration),
    for (final job in jobs.jobs) ...[
      job.sourcePath,
      if (job.resultPath != null) job.resultPath!,
      if (job.targetSnapshot?['userReference'] == true)
        job.targetSnapshot?['illustration'],
    ],
  };
  for (final path in candidates) {
    if (!retained.contains(path)) await storage.deleteOwnedFile(path);
  }
}
