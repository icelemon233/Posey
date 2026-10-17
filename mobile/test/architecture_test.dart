import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:posey/app/posey_bootstrap.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_job_repository.dart';
import 'package:posey/features/ai_pose/ai_jobs_view_model.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';
import 'package:posey/features/ai_pose/native_background_ai.dart';
import 'package:posey/features/camera/camera_gateway.dart';
import 'package:posey/features/camera/camera_view_model.dart';
import 'package:posey/features/photo_review/photo_review_view_model.dart';
import 'package:posey/features/poses/pose_library_view_model.dart';
import 'package:posey/features/poses/pose_repository.dart';
import 'package:posey/features/settings/settings_repository.dart';
import 'package:posey/features/settings/settings_view_model.dart';

import 'support.dart';

class RejectingPreferences implements SharedPreferences {
  String cached = '["saved"]';
  @override
  String? getString(String key) => cached;
  @override
  Future<bool> setString(String key, String value) async {
    cached = value;
    return false;
  }

  @override
  Future<void> reload() async {
    cached = '["saved"]';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FailingStorage extends TestStorage {
  FailingStorage(super.directory);
  String? failNextWrite;
  Completer<void>? writeGate;
  @override
  Future<void> write(String name, String value) async {
    await writeGate?.future;
    if (name == failNextWrite) {
      failNextWrite = null;
      throw StateError('storage unavailable');
    }
    await super.write(name, value);
  }
}

class FakePhotos implements PhotoLibrary {
  int saves = 0, reads = 0;
  bool failSave = false;
  Completer<void>? saveGate;
  @override
  Future<String?> pickPhoto() async => 'imported.jpg';
  @override
  Future<Uint8List> readPhoto(String path) async {
    reads++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> saveToGallery(String path) async {
    saves++;
    await saveGate?.future;
    if (failSave) throw StateError('gallery unavailable');
  }
}

class FakeSession implements CameraSession {
  Completer<void>? openGate;
  Completer<String>? captureGate;
  Object? openError;
  int closes = 0, captures = 0;
  @override
  CameraController? get preview => null;
  @override
  bool flashAuto = false;
  @override
  Future<void> initialize() async {
    await openGate?.future;
    if (openError != null) throw openError!;
  }

  @override
  Future<List<double>> zoomLimits() async => [1, 9];
  @override
  Future<void> setZoom(double value) async {}
  @override
  Future<bool> focusAt(Offset point) async => true;
  @override
  Future<void> toggleFlash() async {
    flashAuto = !flashAuto;
  }

  @override
  Future<String> capture() async {
    captures++;
    return await captureGate?.future ?? 'captured.jpg';
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

class FakeCamera implements CameraGateway {
  FakeCamera(this.session);
  final FakeSession session;
  @override
  Future<List<CameraDescription>> devices() async => [
    const CameraDescription(
      name: 'test',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  CameraSession create(CameraDescription device) => session;
}

class FakeNative extends NativeBackgroundAi {
  bool fail = false;
  List<Json> records = [];
  Completer<void>? jobsGate;
  Completer<String>? startGate;
  final started = Completer<void>();
  String? submittedId;
  @override
  Future<String> start(
    PreparedAiRequest request, {
    required String jobId,
  }) async {
    submittedId = jobId;
    started.complete();
    return await startGate?.future ?? jobId;
  }

  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> clear(String id) async {
    records.removeWhere((record) => record['id'] == id);
  }

  @override
  bool get supported => true;
  @override
  Future<List<Json>> jobs({List<String> knownResults = const []}) async {
    if (fail) throw StateError('native unavailable');
    final snapshot = records.map((record) => Json.from(record)).toList();
    await jobsGate?.future;
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FailingStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('posey-boundaries-');
    storage = FailingStorage(directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<PoseLibraryViewModel> library() async {
    final model = PoseLibraryViewModel(PoseRepository(storage));
    addTearDown(model.dispose);
    await model.load();
    return model;
  }

  test('device persistence rejects a false result and does not expose the unsaved cache', () async {
    final device = DevicePoseyStorage(RejectingPreferences(), directory);
    await expectLater(
      device.write('favorites', '["unsaved"]'),
      throwsStateError,
    );
    expect(await device.read('favorites'), '["saved"]');
  });

  test('favorite write failures preserve saved state and later commands can recover', () async {
    final model = await library();
    final poseId = model.templates.first.id;
    storage.failNextWrite = 'favorites';
    await expectLater(model.toggleFavorite(poseId), throwsStateError);
    expect(model.favorites, isEmpty);
    await model.toggleFavorite(poseId);
    expect(model.favorites, contains(poseId));
    expect(jsonDecode(storage.data['favorites']!), contains(poseId));
  });

  test('concurrent favorite writes retain both choices and publish after persistence', () async {
    final model = await library();
    storage.writeGate = Completer<void>();
    final ids = model.templates.take(2).map((pose) => pose.id).toList();
    final first = model.toggleFavorite(ids[0]),
        second = model.toggleFavorite(ids[1]);
    expect(model.favorites, isEmpty);
    storage.writeGate!.complete();
    await Future.wait([first, second]);
    expect(model.favorites, containsAll(ids));
    expect(jsonDecode(storage.data['favorites']!), containsAll(ids));
  });

  test(
    'settings failure restores secure credentials and metadata together',
    () async {
      final model = SettingsViewModel(SettingsRepository(storage));
      addTearDown(model.dispose);
      await model.load();
      await model.saveConfiguration(
        const AiConfiguration(
          key: 'old-test-key',
          endpoint: 'https://old.example/api/v3',
        ),
        const AiPreferences(),
      );
      storage.failNextWrite = 'ai-preferences';
      await expectLater(
        model.saveConfiguration(
          const AiConfiguration(
            key: 'new-test-key',
            endpoint: 'https://new.example/api/v3',
          ),
          const AiPreferences(face: 'natural'),
        ),
        throwsStateError,
      );
      expect(model.configuration.normalizedKey, 'old-test-key');
      expect(storage.key, 'old-test-key');
      expect(
        jsonDecode(storage.data['ai-config']!)['endpoint'],
        'https://old.example/api/v3',
      );
      expect(storage.data.values.join(), isNot(contains('test-key')));
      storage.failNextWrite = 'theme';
      await expectLater(model.setTheme('sea-breeze'), throwsStateError);
      expect(model.theme, 'sunny-cream');
    },
  );

  test(
    'corrupt favorites are isolated and preserved until explicit recovery',
    () async {
      storage.data['favorites'] = '{}';
      final dependencies = PoseyDependencies(
        storage: storage,
        aiService: DelayedService(),
        photos: FakePhotos(),
      );
      addTearDown(dependencies.dispose);
      await dependencies.initialize();
      expect(dependencies.state, AppLoadState.ready);
      expect(dependencies.library.loadErrors['favorites'], isNotNull);
      expect(storage.data['favorites'], '{}');
      await expectLater(
        dependencies.library.toggleFavorite(
          dependencies.library.templates.first.id,
        ),
        throwsStateError,
      );
      await dependencies.library.resetRecord('favorites');
      expect(dependencies.library.loadErrors['favorites'], isNull);
      expect(
        storage.data.keys.any((key) => key.startsWith('favorites-recovery-')),
        isTrue,
      );
      expect(dependencies.state, AppLoadState.ready);
      expect(dependencies.library.templates, hasLength(50));
    },
  );

  test('catalog boundary rejects duplicate pose identifiers', () async {
    final pose = (await library()).templates.first.raw;
    final repository = PoseRepository(
      storage,
      loadCatalog: () async => jsonEncode([pose, pose]),
    );
    await expectLater(repository.loadTemplates(), throwsFormatException);
  });

  test('late camera initialization releases the session after leaving the foreground', () async {
    final pose = (await library()).templates.first;
    final session = FakeSession()..openGate = Completer<void>();
    final model = CameraViewModel(
      pose,
      photos: FakePhotos(),
      gateway: FakeCamera(session),
    );
    addTearDown(model.dispose);
    final pending = model.initialize();
    await Future<void>.delayed(Duration.zero);
    model.setActive(false);
    session.openGate!.complete();
    await pending;
    expect(model.phase, CameraPhase.idle);
    expect(model.preview, isNull);
    expect(session.closes, 1);
  });

  test(
    'camera captures once and keeps the pose selected when shutter was pressed',
    () async {
      final poses = (await library()).templates;
      final session = FakeSession()..captureGate = Completer<String>();
      final model = CameraViewModel(
        poses[0],
        photos: FakePhotos(),
        gateway: FakeCamera(session),
      );
      addTearDown(model.dispose);
      await model.initialize();
      expect(model.maxZoom, 5);
      final pending = model.capture();
      expect(await model.capture(), isNull);
      model.selectPose(poses[1]);
      session.captureGate!.complete('captured.jpg');
      final photo = await pending;
      expect(photo?.target.id, poses[0].id);
      expect(session.captures, 1);
    },
  );

  test('camera disposal discards a late photo and permission failure still allows import', () async {
    final pose = (await library()).templates.first;
    final session = FakeSession()..captureGate = Completer<String>();
    final model = CameraViewModel(
      pose,
      photos: FakePhotos(),
      gateway: FakeCamera(session),
    );
    await model.initialize();
    final pending = model.capture();
    model.dispose();
    session.captureGate!.complete('late.jpg');
    expect(await pending, isNull);
    final denied = CameraViewModel(
      pose,
      photos: FakePhotos(),
      gateway: FakeCamera(
        FakeSession()
          ..openError = CameraException('CameraAccessDenied', 'denied'),
      ),
    );
    addTearDown(denied.dispose);
    await denied.initialize();
    expect(denied.phase, CameraPhase.failed);
    expect(denied.error, contains('相机权限'));
    expect((await denied.importPhoto())?.path, 'imported.jpg');
  });

  test(
    'photo commands require consent and prevent duplicate or conflicting work',
    () async {
      final pose = (await library()).templates.first, photos = FakePhotos();
      final gate = Completer<void>();
      var submissions = 0;
      final model = PhotoReviewViewModel(
        photos: photos,
        target: pose,
        path: 'photo.jpg',
        hasConfiguration: () => true,
        serviceHost: () => 'example.com',
        submit: ({required consent}) async {
          submissions++;
          await gate.future;
        },
      );
      addTearDown(model.dispose);
      await expectLater(model.generate(consent: false), throwsStateError);
      expect(submissions, 0);
      final pending = model.generate(consent: true);
      expect(await model.generate(consent: true), isFalse);
      expect(await model.save(), isFalse);
      gate.complete();
      expect(await pending, isTrue);
      expect(model.phase, PhotoReviewPhase.idle);
      expect(submissions, 1);
      photos.failSave = true;
      await expectLater(model.save(), throwsStateError);
      expect(model.saved, isFalse);
      expect(model.busy, isFalse);
    },
  );

  test(
    'disposing AI preparation leaves no photo copies or submitted jobs',
    () async {
      final target = (await library()).templates.first;
      final service = DelayedService()..prepareGate = Completer<void>();
      final repository = AiJobRepository(storage, service);
      final pending = repository.enqueue(
        target,
        Uint8List.fromList([1]),
        consent: true,
        configuration: const AiConfiguration(key: 'test-key'),
        preferences: const AiPreferences(),
      );
      repository.dispose();
      service.prepareGate!.complete();
      await expectLater(pending, throwsStateError);
      expect(directory.listSync(), isEmpty);
      expect(service.requests, isEmpty);
    },
  );

  test(
    'native task titles restore target links and sync errors can recover',
    () async {
      final poses = await library(), target = poses.templates.first;
      final native = FakeNative()
        ..records = [
          {
            'id': 'native-job',
            'state': 'generating',
            'targetTitle': target.title,
            'createdAt': 1,
          },
        ];
      final repository = AiJobRepository(
        storage,
        DelayedService(),
        native: native,
      );
      final model = AiJobsViewModel(
        repository,
        FakePhotos(),
        configuration: () => const AiConfiguration(),
        preferences: () => const AiPreferences(),
        targetFor: (job) => poses.find(job.targetId, title: job.targetTitle),
      );
      addTearDown(() {
        model.dispose();
        repository.dispose();
      });
      await repository.load();
      expect(model.targetFor(model.jobs.single)?.id, target.id);
      final snapshot = model.jobs.single;
      snapshot.state = AiJobState.cancelled;
      expect(model.jobs.single.state, AiJobState.generating);
      native.fail = true;
      await model.syncNative();
      expect(model.syncError, isNotNull);
      native.fail = false;
      await model.syncNative();
      expect(model.syncError, isNull);
    },
  );

  test('native polling during submission reconciles the same job without duplicates', () async {
    final target = (await library()).templates.first;
    final native = FakeNative()..startGate = Completer<String>();
    final repository = AiJobRepository(
      storage,
      DelayedService(),
      native: native,
    );
    addTearDown(repository.dispose);
    await repository.load();
    final pending = repository.enqueue(
      target,
      Uint8List.fromList([1]),
      consent: true,
      configuration: const AiConfiguration(key: 'test-key'),
      preferences: const AiPreferences(),
    );
    await native.started.future;
    native.records = [
      {
        'id': native.submittedId!,
        'state': 'generating',
        'targetTitle': target.title,
        'createdAt': 1,
      },
    ];
    await repository.syncNative();
    native.startGate!.complete(native.submittedId!);
    await pending;
    expect(repository.jobs, hasLength(1));
    expect(repository.jobs.single.targetId, target.id);
    expect(repository.jobs.single.sourcePath, isNotEmpty);
    expect(repository.jobs.single.state, AiJobState.generating);
    expect(repository.activeJobs, 1);
  });

  test('a stale native response cannot restore a removed task', () async {
    final target = (await library()).templates.first;
    final native = FakeNative()
      ..records = [
        {
          'id': 'native-job',
          'state': 'generating',
          'targetTitle': target.title,
          'createdAt': 1,
        },
      ];
    final repository = AiJobRepository(
      storage,
      DelayedService(),
      native: native,
    );
    addTearDown(repository.dispose);
    await repository.load();
    native.jobsGate = Completer<void>();
    final pending = repository.syncNative();
    await repository.clear('native-job');
    native.jobsGate!.complete();
    await pending;
    expect(repository.jobs, isEmpty);
  });

  testWidgets('storage startup failure presents a retry action', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      PoseyBootstrap(
        createDependencies: () async {
          attempts++;
          throw StateError('unavailable');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法打开设备存储，请重试。'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
