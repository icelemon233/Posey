import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/app/import_recovery.dart';
import 'package:posey/features/poses/pose_picker.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/media/device_platform.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/core/storage/storage_transaction.dart';
import 'package:posey/core/ui/reference_image.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_job_repository.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';
import 'package:posey/features/ai_pose/native_background_ai.dart';
import 'package:posey/features/backup/backup_archive.dart';
import 'package:posey/features/camera/camera_gateway.dart';
import 'package:posey/features/camera/camera_screen.dart';
import 'package:posey/features/camera/camera_preferences.dart';
import 'package:posey/features/camera/camera_view_model.dart';
import 'package:posey/features/photo_review/photo_edit.dart';
import 'package:posey/features/photo_review/photo_editor_view_model.dart';
import 'package:posey/features/photo_review/photo_review_view_model.dart';
import 'package:posey/features/poses/pose_library_view_model.dart';
import 'package:posey/features/poses/pose_repository.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/works/photo_work.dart';
import 'package:posey/features/works/works_repository.dart';

import 'support.dart';

class FilePhotos implements PhotoLibrary {
  int gallerySaves = 0;
  @override
  Future<String?> pickPhoto() async => null;
  @override
  Future<Uint8List> readPhoto(String path) => File(path).readAsBytes();
  @override
  Future<void> saveToGallery(String path) async {
    await File(path).length();
    gallerySaves++;
  }
}

class FlakyStorage extends TestStorage {
  FlakyStorage(super.directory);
  String? rejectKey;
  bool rejectResult = false;
  bool persistent = false;
  @override
  Future<void> write(String name, String value) async {
    if (name == rejectKey) {
      if (!persistent) rejectKey = null;
      throw StateError('synthetic disk error');
    }
    await super.write(name, value);
  }

  @override
  Future<String> saveBytes(String name, Uint8List bytes) async {
    if (rejectResult && name.endsWith('-result.jpg')) {
      throw StateError('synthetic full disk');
    }
    return super.saveBytes(name, bytes);
  }
}

class ImportPlatform extends DevicePlatform {
  String? input;
  @override
  bool get supported => false;
  @override
  Future<String?> importFile() async => input;
}

class DownloadService extends DelayedService implements AiResultDownloader {
  int downloads = 0;
  Uint8List bytes = Uint8List(0);
  @override
  Future<Uint8List> downloadResult(String id, Uri uri) async {
    downloads++;
    return bytes;
  }
}

class RejectingNative extends NativeBackgroundAi {
  @override
  bool get supported => true;
  @override
  Future<List<Json>> jobs({List<String> knownResults = const []}) async => [
    {'id': 'synthetic-job', 'state': 'generating', 'createdAt': 1},
  ];
  @override
  Future<void> cancel(String id) async =>
      throw StateError('synthetic native rejection');
}

class ManualCamera implements CameraGateway {
  final session = ManualSession();
  @override
  Future<List<CameraDescription>> devices() async => [
    const CameraDescription(
      name: 'synthetic',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  CameraSession create(CameraDescription device) => session;
}

class ManualSession implements CameraSession {
  int captures = 0;
  Offset? focus;
  CameraController? controller;
  @override
  CameraController? get preview => controller;
  @override
  bool get flashAuto => false;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<double>> zoomLimits() async => [1, 5];
  @override
  Future<void> setZoom(double value) async {}
  @override
  Future<bool> focusAt(Offset point) async {
    focus = point;
    return true;
  }

  @override
  Future<void> toggleFlash() async {}
  @override
  Future<String> capture() async {
    captures++;
    return 'synthetic.jpg';
  }

  @override
  Future<void> close() async {
    await controller?.dispose();
  }
}

class PreviewController extends CameraController {
  PreviewController()
    : super(
        const CameraDescription(
          name: 'synthetic',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.medium,
      ) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1920, 1080),
    );
  }
  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF3B4346));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FlakyStorage storage;
  late FilePhotos photos;
  late PoseTemplate target;
  late Uint8List photo;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('posey-workflows-');
    storage = FlakyStorage(directory);
    photos = FilePhotos();
    target = (await PoseRepository(storage).loadTemplates()).first;
    final pixels = image.Image(width: 48, height: 32);
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 48; x++) {
        pixels.setPixelRgb(x, y, x < 24 ? 255 : 0, 0, x < 24 ? 0 : 255);
      }
    }
    photo = Uint8List.fromList(image.encodeJpg(pixels, quality: 100));
    path = await storage.saveBytes('synthetic-source.jpg', photo);
  });
  tearDown(() async => directory.delete(recursive: true));
  Future<void> waitFor(bool Function() ready) async {
    for (var i = 0; !ready() && i < 400; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue);
  }

  BackupSnapshot snapshot({
    List<PoseTemplate> poses = const [],
    List<PhotoWork> works = const [],
  }) => BackupSnapshot(
    poses: poses,
    works: works,
    favorites: {target.id},
    recents: {target.id: 1},
    installationId: 'synthetic-installation',
    assetReferences: {target.illustration},
    interfaceSettings: {
      'theme': 'cloud',
      'themeMode': 'dark',
      'shuffleFavorites': false,
      'camera': const CameraPreferences().toJson(),
    },
  );

  test('works reopen, deduplicate imports, retain shared originals and delete only unused files', () async {
    final works = WorksRepository(storage, photos);
    addTearDown(works.dispose);
    await works.load();
    final original = await works.retain(
      path,
      target,
      importId: 'synthetic-import',
    );
    expect(
      (await works.retain(path, target, importId: 'synthetic-import')).id,
      original.id,
    );
    final edited = await works.retainBytes(
      photo,
      target,
      sourceWorkId: original.id,
      originalPath: original.path,
    );
    final reopened = WorksRepository(storage, photos);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.works, hasLength(2));
    await reopened.delete({original.id});
    expect(await File(original.path).exists(), isTrue);
    expect(reopened.find(edited.id)?.original, original.path);
    await reopened.delete({edited.id});
    expect(await File(original.path).exists(), isFalse);
    expect(await File(edited.path).exists(), isFalse);
  });
  test('gallery retry saves its missing marker without duplicating the external photo', () async {
    final works = WorksRepository(storage, photos);
    addTearDown(works.dispose);
    await works.load();
    final work = await works.retain(path, target);
    storage.rejectKey = 'works-v1';
    await expectLater(works.saveToGallery(work.id), throwsStateError);
    expect(photos.gallerySaves, 1);
    expect(works.find(work.id)!.savedToGallery, isFalse);
    await works.saveToGallery(work.id);
    expect(photos.gallerySaves, 1);
    expect(works.find(work.id)!.savedToGallery, isTrue);
  });
  test('a rejected work commit removes staged copies and retains the original record', () async {
    final works = WorksRepository(storage, photos);
    addTearDown(works.dispose);
    await works.load();
    storage.rejectKey = 'works-v1';
    await expectLater(works.retain(path, target), throwsStateError);
    expect(works.works, isEmpty);
    expect(
      directory.listSync().whereType<File>().map(
        (file) => file.path.replaceAll('\\', '/'),
      ),
      [path],
    );
  });
  test('container relocation restores works and private reference snapshots by owned file names', () async {
    final works = WorksRepository(storage, photos);
    addTearDown(works.dispose);
    await works.load();
    final work = await works.retain(path, target);
    final raw = work.toJson();
    raw['path'] =
        '/old/application/container/${File(work.path).uri.pathSegments.last}';
    storage.data['works-v1'] = jsonEncode([raw]);
    await works.load();
    expect(works.works.single.path, work.path);
  });
  test('personal references persist edits and independent filters without deleting linked photos', () async {
    final library = PoseLibraryViewModel(
      PoseRepository(storage, photos: photos),
    );
    addTearDown(library.dispose);
    await library.load();
    await library.addReference(path, 'Synthetic reference', 'standing', 'all');
    final custom = library.custom.single;
    await library.renameReference(
      custom,
      'Renamed reference',
      category: 'seated',
      gender: 'female',
    );
    await library.toggleFavorite(custom.id);
    await library.markUsed(custom.id);
    library.setQuery('Renamed', favoritesOnly: true);
    library.setGender('male');
    expect(
      library.filtered(favoritesOnly: true).single.title,
      'Renamed reference',
    );
    expect(library.filtered().any((pose) => pose.id == custom.id), isFalse);
    library.resetFilters();
    expect(library.filters(favoritesOnly: true).query, 'Renamed');
    await library.load();
    expect(library.custom.single.category, 'seated');
    expect(library.recents[custom.id], greaterThan(0));
    await library.deleteReference(library.custom.single);
    expect(library.custom, isEmpty);
    expect(library.favorites, isNot(contains(custom.id)));
    expect(await File(custom.illustration).exists(), isTrue);
  });
  test('copy editing rotates, mirrors and crops actual pixels', () {
    image.Image decode(PhotoEdit edit) =>
        image.decodeJpg(editPhoto((bytes: photo, edit: edit, preview: false)))!;
    final rotated = decode(const PhotoEdit(turns: 1));
    expect([rotated.width, rotated.height], [32, 48]);
    final mirrored = decode(const PhotoEdit(flip: true));
    expect(mirrored.getPixel(2, 10).b, greaterThan(200));
    final cropped = decode(const PhotoEdit(ratio: 1, zoom: 2, x: 1, y: 0));
    expect([cropped.width, cropped.height], [16, 16]);
    expect(cropped.getPixel(8, 8).b, greaterThan(200));
  });
  test('editor coalesces rapid drafts and saves the latest copy while retaining the source', () async {
    Uint8List? saved;
    final model = PhotoEditorViewModel(
      path: path,
      photos: photos,
      onSave: (bytes) async => saved = bytes,
    );
    addTearDown(model.dispose);
    await model.load();
    final first = model.render(const PhotoEdit(turns: 1));
    await model.render(const PhotoEdit(ratio: 1, zoom: 2));
    await first;
    expect(model.rendering, isFalse);
    expect(await model.save(), isTrue);
    final result = image.decodeImage(saved!)!;
    expect([result.width, result.height], [16, 16]);
    expect(await File(path).readAsBytes(), photo);
  });
  test('backups round trip custom references and originals without private paths or credentials', () async {
    final custom = await PoseRepository(
      storage,
      photos: photos,
    ).createCustom(path, 'Synthetic', 'standing', 'all');
    final works = WorksRepository(storage, photos);
    addTearDown(works.dispose);
    await works.load();
    final work = await works.retain(path, custom);
    final archivePath = '${directory.path}/roundtrip.zip';
    final input = prepareBackup(
      snapshot(poses: [custom], works: [work]),
      archivePath,
      (await storage.mediaFiles()).map((file) => file.path).toSet(),
    );
    expect(jsonEncode(input.manifest), isNot(contains(directory.path)));
    expect(input.manifest.keys, isNot(contains('ai')));
    expect(input.manifest.keys, isNot(contains('jobs')));
    encodeBackup(input);
    final decoded = decodeBackup(
      BackupDecoding(archivePath, directory.path, 'roundtrip', {
        target.illustration,
      }),
    );
    expect(decoded.manifest['works'], hasLength(1));
    expect(decoded.files, hasLength(2));
    for (final restored in decoded.files.values) {
      expect(await File(restored).readAsBytes(), photo);
    }
  });
  test('malformed archives reject traversal and missing media before changing records', () async {
    final manifest = prepareBackup(snapshot(), 'unused', {}).manifest;
    final archive = Archive()
      ..add(
        ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
      )
      ..add(ArchiveFile.bytes('../escaped.jpg', photo));
    final archivePath = '${directory.path}/invalid.zip';
    await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));
    expect(
      () => decodeBackup(
        BackupDecoding(archivePath, directory.path, 'invalid', {
          target.illustration,
        }),
      ),
      throwsFormatException,
    );
    expect(storage.data, isEmpty);
    final broken = {
      ...manifest,
      'works': [
        {
          'id': 'missing',
          'kind': 'photo',
          'createdAt': 1,
          'path': 'media/missing.jpg',
          'pose': target.raw,
        },
      ],
    };
    expect(
      () => validateBackupManifest(
        broken,
        {'manifest.json'},
        {target.illustration},
      ),
      throwsFormatException,
    );
  });
  test('backup merge preserves local edits and keys, deduplicates works and refreshes settings', () async {
    final platform = ImportPlatform();
    final dependencies = PoseyDependencies(
      storage: storage,
      aiService: DelayedService(),
      photos: photos,
      platform: platform,
    );
    addTearDown(dependencies.dispose);
    await dependencies.initialize();
    await dependencies.settings.saveConfiguration(
      const AiConfiguration(key: 'synthetic-secret'),
      const AiPreferences(),
    );
    final work = await dependencies.works.retain(path, target);
    await dependencies.works.saveToGallery(work.id);
    final data = await dependencies.backup.snapshot(null);
    final archivePath = '${directory.path}/merge.zip';
    encodeBackup(
      prepareBackup(
        data,
        archivePath,
        (await storage.mediaFiles()).map((file) => file.path).toSet(),
      ),
    );
    await dependencies.settings.setThemeMode('light');
    platform.input = archivePath;
    await dependencies.backup.prepareImport();
    await dependencies.backup.applyImport(restoreInterface: true);
    expect(dependencies.works.works, hasLength(1));
    expect(dependencies.works.works.single.savedToGallery, isTrue);
    expect(storage.key, 'synthetic-secret');
    expect(
      dependencies.settings.themeMode,
      data.interfaceSettings['themeMode'],
    );
    expect(dependencies.backup.candidate, isNull);
  });
  test('transaction failure rolls back and an interrupted rollback survives restart', () async {
    storage.data.addAll({'a': 'before', 'b': 'before'});
    storage.rejectKey = 'b';
    await expectLater(
      writeStorageBatch(storage, {'a': 'after', 'b': 'after'}),
      throwsStateError,
    );
    expect(storage.data, {'a': 'before', 'b': 'before'});
    storage.rejectKey = 'b';
    storage.persistent = true;
    await expectLater(
      writeStorageBatch(storage, {'a': 'after', 'b': 'after'}),
      throwsStateError,
    );
    expect(storage.data['pending-transaction-v1'], isNotNull);
    storage.rejectKey = null;
    await recoverStorageTransaction(storage);
    expect(storage.data, {'a': 'before', 'b': 'before'});
  });
  test(
    'AI result disk failure retries saving without a second generation request',
    () async {
      final service = DelayedService();
      final jobs = AiJobRepository(storage, service);
      addTearDown(jobs.dispose);
      await jobs.load();
      await jobs.enqueue(
        target,
        photo,
        consent: true,
        configuration: const AiConfiguration(key: 'synthetic'),
        preferences: const AiPreferences(),
      );
      await waitFor(() => service.pending.isNotEmpty);
      storage.rejectResult = true;
      service.pending.values.single.complete(photo);
      await waitFor(() => jobs.jobs.single.state == AiJobState.awaitingResult);
      expect(jobs.jobs.single.pendingResult, PendingAiResult.save);
      storage.rejectResult = false;
      await jobs.retryResult(jobs.jobs.single.id);
      expect(jobs.jobs.single.state, AiJobState.completed);
      expect(service.requests, hasLength(1));
    },
  );
  test('AI result download survives restart in secure storage and retry makes no POST', () async {
    final service = DownloadService()..bytes = photo;
    final jobs = AiJobRepository(storage, service);
    await jobs.load();
    await jobs.enqueue(
      target,
      photo,
      consent: true,
      configuration: const AiConfiguration(key: 'synthetic'),
      preferences: const AiPreferences(),
    );
    await waitFor(() => service.pending.isNotEmpty);
    service.pending.values.single.completeError(
      AiDownloadException(
        Uri.parse('https://example.test/result?token=synthetic-private'),
      ),
    );
    await waitFor(
      () =>
          jobs.jobs.single.state == AiJobState.awaitingResult &&
          !jobs.hasPendingIO,
    );
    expect(storage.data.values.join(), isNot(contains('synthetic-private')));
    jobs.dispose();
    final reopened = AiJobRepository(storage, service);
    addTearDown(reopened.dispose);
    await reopened.load();
    await reopened.retryResult(reopened.jobs.single.id);
    expect(reopened.jobs.single.state, AiJobState.completed);
    expect(service.requests, hasLength(1));
    expect(service.downloads, 1);
    expect(storage.secrets, isEmpty);
  });
  test(
    'rejected native cancellation restores the active task for another attempt',
    () async {
      final jobs = AiJobRepository(
        storage,
        DelayedService(),
        native: RejectingNative(),
      );
      addTearDown(jobs.dispose);
      await jobs.load();
      storage.data['jobs'] = encodeJobs([
        AiJob(
          id: 'synthetic-job',
          targetId: target.id,
          targetTitle: target.title,
          sourcePath: path,
          createdAt: 1,
          state: AiJobState.generating,
        ),
      ]);
      // A rejected platform cancellation must not hide an ongoing native task.
      await jobs.load();
      final previous = jobs.jobs.single.state;
      await expectLater(jobs.cancel('synthetic-job'), throwsStateError);
      expect(jobs.jobs.single.state, previous);
    },
  );
  test('consent snapshot freezes source, mirror and configuration before subsequent edits', () async {
    final options = AiRequestOptions(
      const AiConfiguration(key: 'synthetic'),
      const AiPreferences(),
    );
    PhotoGenerationRequest? received;
    final model = PhotoReviewViewModel(
      path: path,
      target: target.withMirror(true),
      photos: photos,
      hasConfiguration: () => true,
      serviceHost: () => 'example.test',
      requestOptions: () => options,
      submit: ({required consent}) async {},
      submitRequest: (request, {required consent}) async {
        received = request;
      },
    );
    addTearDown(model.dispose);
    final request = model.createRequest()!;
    model.selectTarget(target.withMirror(false));
    await model.generate(consent: true, request: request);
    expect(received!.target.mirrored, isTrue);
    expect(received!.path, path);
    expect(identical(received!.options, options), isTrue);
  });
  test('connection checks list models without uploading images or claiming partial verification', () async {
    final requests = <http.Request>[];
    var status = 200;
    final service = ArkAiPoseService(
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          status == 200 ? '{"data":[{"id":"synthetic-model"}]}' : '',
          status,
        );
      }),
    );
    final check = await service.checkConnection(
      const AiConfiguration(
        key: 'synthetic',
        model: 'synthetic-model',
        endpoint: 'https://example.test/api/v3',
      ),
    );
    expect(check.verified, isTrue);
    expect(requests.single.method, 'GET');
    expect(requests.single.body, isEmpty);
    status = 404;
    final partial = await service.checkConnection(
      const AiConfiguration(
        key: 'synthetic',
        endpoint: 'https://example.test/api/v3',
      ),
    );
    expect(partial.verified, isFalse);
    status = 401;
    await expectLater(
      service.checkConnection(const AiConfiguration(key: 'synthetic')),
      throwsStateError,
    );
  });
  testWidgets(
    'editing a reference preserves its existing category and gender',
    (tester) async {
      ({String title, String category, String gender})? saved;
      final custom = PoseTemplate.fromJson({
        ...target.raw,
        'id': 'synthetic-reference',
        'title': 'Synthetic reference',
        'userReference': true,
        'category': 'seated',
        'gender': 'female',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog(
                  context: context,
                  builder: (_) => ReferenceForm(initial: custom),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved?.category, 'seated');
      expect(saved?.gender, 'female');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('unfinished imports are preserved and explicit repair backs up the original record', () async {
    final imports = ImportRecovery(storage, photos);
    final id = await imports.stage(target);
    await imports.selected(id, path);
    await expectLater(imports.stage(target), throwsStateError);
    expect((await imports.pending())?.id, id);
    storage.data['pending-import-v1'] = 'synthetic-corrupt-json';
    await expectLater(imports.pending(), throwsFormatException);
    await imports.backupAndClear();
    expect(storage.data['pending-import-v1'], isNull);
    expect(
      storage.data.entries
          .singleWhere(
            (entry) => entry.key.startsWith('pending-import-recovery-'),
          )
          .value,
      'synthetic-corrupt-json',
    );
  });
  test(
    'task cleanup retains completed results that have not reached Works',
    () async {
      final service = DelayedService();
      final jobs = AiJobRepository(
        storage,
        service,
        preserveResult: (_) async => throw StateError('synthetic work failure'),
      );
      addTearDown(jobs.dispose);
      await jobs.load();
      await jobs.enqueue(
        target,
        photo,
        consent: true,
        configuration: const AiConfiguration(key: 'synthetic'),
        preferences: const AiPreferences(),
      );
      await waitFor(() => service.pending.isNotEmpty);
      service.pending.values.single.complete(photo);
      await waitFor(
        () => jobs.jobs.single.archiveError != null && !jobs.hasPendingIO,
      );
      await jobs.clearFinished(includeCompleted: true);
      expect(jobs.jobs, hasLength(1));
      expect(await File(jobs.jobs.single.resultPath!).exists(), isTrue);
    },
  );
  testWidgets(
    'camera preview, grid and guide share the viewport through orientation changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PreviewController();
      final gateway = ManualCamera()..session.controller = controller;
      final model = CameraViewModel(
        target,
        photos: photos,
        gateway: gateway,
        preferences: const CameraPreferences(grid: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PoseyCameraScreen(
            viewModel: model,
            poses: [target],
            onPhoto: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is CompositionGrid,
      );
      void sharedBounds() {
        final rect = tester.getRect(find.byType(CameraPreview));
        expect(tester.getRect(grid), rect);
        final guide = find
            .ancestor(
              of: find.byType(ReferenceImage),
              matching: find.byType(Transform),
            )
            .first;
        expect(tester.getRect(guide), rect);
      }

      sharedBounds();
      final rect = tester.getRect(find.byType(CameraPreview));
      expect(rect.width / rect.height, closeTo(9 / 16, .001));
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(gateway.session.focus, const Offset(.5, .5));
      controller.value = controller.value.copyWith(
        deviceOrientation: DeviceOrientation.landscapeLeft,
      );
      await tester.pump();
      sharedBounds();
      expect(
        tester.getSize(find.byType(CameraPreview)).aspectRatio,
        closeTo(16 / 9, .001),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await model.waitForRelease();
    },
  );
  testWidgets(
    'manual countdown cancels on interruption and captures the frozen mirrored guide',
    (tester) async {
      final gateway = ManualCamera();
      final model = CameraViewModel(
        target,
        photos: photos,
        gateway: gateway,
        preferences: const CameraPreferences(timerSeconds: 3, mirror: true),
      );
      addTearDown(model.dispose);
      await model.initialize();
      final interrupted = model.capture();
      expect(model.countdown, 3);
      await tester.pump(const Duration(seconds: 1));
      expect(model.countdown, 2);
      model.setActive(false);
      expect(await interrupted, isNull);
      expect(gateway.session.captures, 0);
      await model.waitForRelease();
      model.setActive(true);
      await tester.pump();
      await tester.pump();
      model.setTimer(0);
      await model.focusAt(const Offset(2, -1));
      expect(gateway.session.focus, const Offset(1, 0));
      final captured = await model.capture();
      expect(captured!.target.mirrored, isTrue);
      expect(gateway.session.captures, 1);
      model.setActive(false);
      await model.waitForRelease();
    },
  );
}
