import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/core/json.dart';
import 'package:posey/core/media/photo_library.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_job_repository.dart';
import 'package:posey/features/ai_pose/ai_jobs_screen.dart';
import 'package:posey/features/ai_pose/ai_jobs_view_model.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';
import 'package:posey/features/ai_pose/native_background_ai.dart';
import 'package:posey/features/camera/camera_gateway.dart';
import 'package:posey/features/camera/camera_screen.dart';
import 'package:posey/features/camera/camera_view_model.dart';
import 'package:posey/features/poses/pose_repository.dart';
import 'package:posey/features/poses/pose_template.dart';

import 'support.dart';

class FaultStorage extends TestStorage {
  FaultStorage(super.directory);
  int jobsWrites = 0;
  int? failOnJobsWrite;
  bool rejectJobs = false, rejectBackups = false;
  @override
  Future<void> write(String name, String value) async {
    if (name == 'jobs' && (++jobsWrites == failOnJobsWrite || rejectJobs) ||
        rejectBackups && name.startsWith('jobs-recovery-')) {
      throw StateError('simulated storage failure');
    }
    await super.write(name, value);
  }
}

class TestPhotos implements PhotoLibrary {
  Completer<void>? readGate;
  int reads = 0;
  @override
  Future<String?> pickPhoto() async => 'synthetic.jpg';
  @override
  Future<Uint8List> readPhoto(String path) async {
    reads++;
    await readGate?.future;
    return Uint8List.fromList([1]);
  }

  @override
  Future<void> saveToGallery(String path) async {}
}

class RecordingNative extends NativeBackgroundAi {
  RecordingNative(this.storage);
  final FaultStorage storage;
  int starts = 0;
  String? id;
  bool savedBeforeStart = false;
  Completer<void>? jobsGate;
  @override
  bool get supported => true;
  @override
  Future<String> start(
    PreparedAiRequest request, {
    required String jobId,
  }) async {
    starts++;
    id = jobId;
    savedBeforeStart = storage.data['jobs']!.contains(jobId);
    return jobId;
  }

  @override
  Future<List<Json>> jobs({List<String> knownResults = const []}) async {
    final snapshot = <Json>[
      if (id != null) {'id': id!, 'state': 'generating', 'createdAt': 1},
    ];
    await jobsGate?.future;
    return snapshot;
  }
}

class ExclusiveCamera implements CameraGateway {
  ExclusiveSession? owner;
  final firstClose = Completer<void>();
  Completer<void>? firstOpen;
  final sessions = <ExclusiveSession>[];
  @override
  Future<List<CameraDescription>> devices() async => [
    const CameraDescription(
      name: 'exclusive-camera',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  CameraSession create(CameraDescription device) {
    final session = ExclusiveSession(this, sessions.isEmpty);
    sessions.add(session);
    return session;
  }
}

class ExclusiveSession implements CameraSession {
  ExclusiveSession(this.gateway, this.first);
  final ExclusiveCamera gateway;
  final bool first;
  int closes = 0;
  @override
  CameraController? get preview => null;
  @override
  bool get flashAuto => false;
  @override
  Future<void> initialize() async {
    if (gateway.owner != null) throw StateError('camera still in use');
    gateway.owner = this;
    if (first) await gateway.firstOpen?.future;
  }

  @override
  Future<List<double>> zoomLimits() async => [1, 2];
  @override
  Future<void> setZoom(double value) async {}
  @override
  Future<bool> focusAt(Offset point) async => true;
  @override
  Future<void> toggleFlash() async {}
  @override
  Future<String> capture() async => 'synthetic.jpg';
  @override
  Future<void> close() async {
    closes++;
    if (first) await gateway.firstClose.future;
    if (identical(gateway.owner, this)) gateway.owner = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FaultStorage storage;
  late PoseTemplate target;
  const config = AiConfiguration(key: 'synthetic-test-key');
  const options = AiPreferences();
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('posey-reliability-');
    storage = FaultStorage(directory);
    target = (await PoseRepository(storage).loadTemplates()).first;
  });
  tearDown(() async => directory.delete(recursive: true));
  Future<void> flush() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; !condition() && i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  Future<void> submit(AiJobRepository repository) => repository.enqueue(
    target,
    Uint8List(1),
    consent: true,
    configuration: config,
    preferences: options,
  );

  test('rejected enqueue leaves no runnable job, photo copy or capacity reservation', () async {
    final service = DelayedService();
    final repository = AiJobRepository(storage, service);
    addTearDown(repository.dispose);
    await repository.load();
    storage.failOnJobsWrite = storage.jobsWrites + 1;
    await expectLater(submit(repository), throwsStateError);
    expect(repository.jobs, isEmpty);
    expect(repository.activeJobs, 0);
    expect(directory.listSync(), isEmpty);
    expect(service.requests, isEmpty);
    await submit(repository);
    await waitFor(() => service.requests.isNotEmpty);
    expect(repository.jobs, hasLength(1));
    expect(service.requests.keys.single, repository.jobs.single.id);
  });

  test(
    'one rejected concurrent submission cannot be run by another queue worker',
    () async {
      final service = DelayedService();
      final repository = AiJobRepository(storage, service);
      addTearDown(repository.dispose);
      await repository.load();
      storage.failOnJobsWrite = storage.jobsWrites + 1;
      final submissions = List.generate(3, (_) => submit(repository));
      final outcomes = await Future.wait(
        submissions.map((future) async {
          try {
            await future;
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      expect(outcomes.where((accepted) => accepted), hasLength(2));
      await waitFor(() => service.requests.isNotEmpty);
      expect(repository.jobs, hasLength(2));
      expect(repository.activeJobs, 2);
      final first = service.pending.keys.single;
      service.pending[first]!.complete(Uint8List(1));
      await waitFor(() => service.requests.length == 2);
      expect(
        service.requests.keys.toSet(),
        repository.jobs.map((job) => job.id).toSet(),
      );
    },
  );

  test('generating-state write failure becomes a failed job without an HTTP request', () async {
    final service = DelayedService();
    final repository = AiJobRepository(storage, service);
    addTearDown(repository.dispose);
    await repository.load();
    storage.failOnJobsWrite = storage.jobsWrites + 2;
    await submit(repository);
    await waitFor(() => repository.jobs.single.state == AiJobState.failed);
    expect(repository.activeJobs, 0);
    expect(service.requests, isEmpty);
    expect(repository.jobs.single.message, contains('storage failure'));
    await repository.retryPersistence();
    expect(jsonDecode(storage.data['jobs']!).single['state'], 'failed');
  });

  test('a generated result survives record-write failure and saving never repeats AI', () async {
    final service = DelayedService();
    final repository = AiJobRepository(storage, service);
    addTearDown(repository.dispose);
    await repository.load();
    await submit(repository);
    await waitFor(() => service.pending.isNotEmpty);
    storage.rejectJobs = true;
    service.pending.values.single.complete(Uint8List(1));
    await waitFor(() => repository.persistenceError != null);
    final job = repository.jobs.single;
    expect(job.state, AiJobState.completed);
    expect(await File(job.resultPath!).exists(), isTrue);
    expect(repository.activeJobs, 0);
    storage.rejectJobs = false;
    await repository.retryPersistence();
    expect(repository.persistenceError, isNull);
    expect(jsonDecode(storage.data['jobs']!).single['state'], 'completed');
    expect(service.requests, hasLength(1));
  });

  test(
    'history trimming waits for a successful commit before deleting old photos',
    () async {
      final previous = <AiJob>[];
      for (var i = 0; i < 20; i++) {
        final source = await storage.saveBytes(
          'old-$i-source.jpg',
          Uint8List(1),
        );
        final result = await storage.saveBytes(
          'old-$i-result.jpg',
          Uint8List(1),
        );
        previous.add(
          AiJob(
            id: 'old-$i',
            targetId: target.id,
            targetTitle: target.title,
            sourcePath: source,
            resultPath: result,
            createdAt: i,
            state: AiJobState.completed,
          ),
        );
      }
      storage.data['jobs'] = encodeJobs(previous);
      final service = DelayedService();
      final repository = AiJobRepository(storage, service);
      addTearDown(repository.dispose);
      await repository.load();
      await submit(repository);
      await waitFor(() => service.pending.isNotEmpty);
      storage.rejectJobs = true;
      service.pending.values.single.complete(Uint8List(1));
      await waitFor(() => repository.persistenceError != null);
      expect(await File(previous.first.resultPath!).exists(), isTrue);
      expect(repository.jobs, hasLength(21));
      storage.rejectJobs = false;
      await repository.retryPersistence();
      expect(repository.jobs, hasLength(20));
      expect(await File(previous.first.resultPath!).exists(), isFalse);
    },
  );

  test('failed task removal preserves its photos and record', () async {
    final path = await storage.saveBytes('kept.jpg', Uint8List(1));
    final job = AiJob(
      id: 'kept',
      targetId: target.id,
      targetTitle: target.title,
      sourcePath: path,
      resultPath: path,
      createdAt: 1,
      state: AiJobState.completed,
    );
    storage.data['jobs'] = encodeJobs([job]);
    final repository = AiJobRepository(storage, DelayedService());
    addTearDown(repository.dispose);
    await repository.load();
    storage.rejectJobs = true;
    await expectLater(repository.clear(job.id), throwsStateError);
    expect(repository.jobs.single.id, job.id);
    expect(await File(path).exists(), isTrue);
  });

  test('a retry is unique through photo reading, preparation and active generation', () async {
    final original = AiJob(
      id: 'original',
      targetId: target.id,
      targetTitle: target.title,
      sourcePath: 'synthetic.jpg',
      createdAt: 1,
      state: AiJobState.failed,
    );
    storage.data['jobs'] = encodeJobs([original]);
    final photos = TestPhotos()..readGate = Completer<void>();
    final service = DelayedService()..prepareGate = Completer<void>();
    final repository = AiJobRepository(storage, service);
    final model = AiJobsViewModel(
      repository,
      photos,
      configuration: () => config,
      preferences: () => options,
      targetFor: (_) => target,
    );
    addTearDown(() {
      model.dispose();
      repository.dispose();
    });
    await repository.load();
    final first = model.retry(original, consent: true);
    await model.retry(original, consent: true);
    expect(photos.reads, 1);
    photos.readGate!.complete();
    await flush();
    await model.retry(original, consent: true);
    expect(service.prepares, 1);
    service.prepareGate!.complete();
    await first;
    await waitFor(() => service.pending.isNotEmpty);
    await model.retry(original, consent: true);
    expect(repository.jobs, hasLength(2));
    expect(repository.jobs.first.retryOf, original.id);
    expect(model.isRetrying(original.id), isTrue);
    service.pending.values.single.completeError(
      StateError('simulated provider failure'),
    );
    await waitFor(() => !model.isRetrying(original.id));
    await model.retry(original, consent: true);
    expect(repository.jobs, hasLength(3));
  });

  test('resume waits for the old camera to close before reopening', () async {
    final gateway = ExclusiveCamera();
    final model = CameraViewModel(
      target,
      photos: TestPhotos(),
      gateway: gateway,
    );
    addTearDown(model.dispose);
    await model.initialize();
    model.setActive(false);
    model.setActive(true);
    await flush();
    expect(model.phase, CameraPhase.opening);
    expect(gateway.sessions, hasLength(1));
    gateway.firstClose.complete();
    await waitFor(() => model.phase == CameraPhase.ready);
    expect(gateway.sessions, hasLength(2));
    expect(gateway.owner, same(gateway.sessions.last));
  });

  test(
    'resume also waits for a stale initialization and its delayed cleanup',
    () async {
      final gateway = ExclusiveCamera()..firstOpen = Completer<void>();
      final model = CameraViewModel(
        target,
        photos: TestPhotos(),
        gateway: gateway,
      );
      addTearDown(model.dispose);
      final opening = model.initialize();
      await flush();
      model.setActive(false);
      model.setActive(true);
      gateway.firstOpen!.complete();
      await flush();
      expect(gateway.sessions, hasLength(1));
      gateway.firstClose.complete();
      await opening;
      await waitFor(() => model.phase == CameraPhase.ready);
      expect(gateway.sessions.first.closes, 1);
      expect(gateway.sessions, hasLength(2));
    },
  );

  testWidgets(
    'a covered camera stays closed across foreground events until review returns',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final gateway = ExclusiveCamera();
      final model = CameraViewModel(
        target,
        photos: TestPhotos(),
        gateway: gateway,
      );
      final review = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: PoseyCameraScreen(
            viewModel: model,
            poses: [target],
            onPhoto: (_, _) => review.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('导入照片'));
      await tester.pumpAndSettle();
      gateway.firstClose.complete();
      await tester.pumpAndSettle();
      expect(model.phase, CameraPhase.idle);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.sessions, hasLength(1));
      review.complete();
      await tester.pumpAndSettle();
      expect(model.phase, CameraPhase.ready);
      expect(gateway.sessions, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('corrupt AI history allows offline use and is backed up before explicit reset', () async {
    storage.data['jobs'] = '{broken';
    storage.data['favorites'] = '[]';
    storage.key = config.normalizedKey;
    final service = DelayedService();
    final dependencies = PoseyDependencies(
      storage: storage,
      aiService: service,
      photos: TestPhotos(),
    );
    addTearDown(dependencies.dispose);
    await dependencies.initialize();
    expect(dependencies.state, AppLoadState.ready);
    expect(dependencies.library.templates, hasLength(50));
    expect(dependencies.jobs.loadError, isNotNull);
    await dependencies.library.toggleFavorite(target.id);
    await expectLater(
      dependencies.jobs.submitPhoto(target, 'synthetic.jpg', consent: true),
      throwsStateError,
    );
    expect(service.prepares, 0);
    await dependencies.initialize();
    expect(dependencies.state, AppLoadState.ready);
    expect(storage.data['jobs'], '{broken');
    await dependencies.jobs.resetUnreadableHistory();
    expect(dependencies.jobs.loadError, isNull);
    expect(storage.data['jobs'], '[]');
    expect(
      storage.data.entries
          .singleWhere((e) => e.key.startsWith('jobs-recovery-'))
          .value,
      '{broken',
    );
    expect(dependencies.library.favorites, contains(target.id));
  });

  test(
    'a failed recovery backup never overwrites the original unreadable history',
    () async {
      storage.data['jobs'] = '{}';
      final repository = AiJobRepository(storage, DelayedService());
      addTearDown(repository.dispose);
      await expectLater(repository.load(), throwsFormatException);
      storage.rejectBackups = true;
      await expectLater(repository.resetUnreadableHistory(), throwsStateError);
      expect(storage.data['jobs'], '{}');
      expect(repository.loadError, isNotNull);
    },
  );

  testWidgets(
    'history recovery asks for confirmation and retains the original on cancel',
    (tester) async {
      storage.data['jobs'] = '{}';
      final repository = AiJobRepository(storage, DelayedService());
      final model = AiJobsViewModel(
        repository,
        TestPhotos(),
        configuration: () => config,
        preferences: () => options,
        targetFor: (_) => target,
      );
      addTearDown(() {
        model.dispose();
        repository.dispose();
      });
      await expectLater(repository.load(), throwsFormatException);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiJobsScreen(viewModel: model, onOpenResult: (_) {}),
          ),
        ),
      );
      await tester.tap(find.text('备份并重置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(storage.data['jobs'], '{}');
      await tester.tap(find.text('备份并重置'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '备份并重置'));
      await tester.pumpAndSettle();
      expect(storage.data['jobs'], '[]');
      expect(find.text('跟着姿势拍一张，或导入照片开始。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('native generation only starts after local acceptance with the same stable ID', () async {
    final native = RecordingNative(storage);
    final repository = AiJobRepository(
      storage,
      DelayedService(),
      native: native,
    );
    addTearDown(repository.dispose);
    await repository.load();
    storage.failOnJobsWrite = storage.jobsWrites + 1;
    await expectLater(submit(repository), throwsStateError);
    expect(native.starts, 0);
    expect(repository.jobs, isEmpty);
    await submit(repository);
    expect(native.starts, 1);
    expect(native.savedBeforeStart, isTrue);
    expect(repository.jobs.single.id, native.id);
  });

  test('the native bridge forwards the already persisted job ID', () async {
    const channel = MethodChannel('posey/reliability-native-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const id = '80d29761-d937-4ecd-a59b-a9cc540a777c';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'start');
      expect(call.arguments['jobId'], id);
      return {'jobId': id};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final prepared = await DelayedService().prepare(
      config,
      options,
      target,
      Uint8List(1),
    );
    expect(
      await const NativeBackgroundAi(channel: channel)
          .start(prepared, jobId: id),
      id,
    );
  });

  test('native recovery marks a locally saved task that never reached the native queue as interrupted', () async {
    storage.data['jobs'] = encodeJobs([
      AiJob(
        id: 'before-native-start',
        targetId: target.id,
        targetTitle: target.title,
        sourcePath: 'synthetic.jpg',
        createdAt: 1,
      ),
    ]);
    final native = RecordingNative(storage);
    final repository = AiJobRepository(
      storage,
      DelayedService(),
      native: native,
    );
    addTearDown(repository.dispose);
    await repository.load();
    expect(repository.jobs.single.state, AiJobState.failed);
    expect(repository.activeJobs, 0);
    expect(native.starts, 0);
  });

  test('native polling captured before a submission cannot mark the accepted task as missing', () async {
    final native = RecordingNative(storage);
    final repository = AiJobRepository(
      storage,
      DelayedService(),
      native: native,
    );
    addTearDown(repository.dispose);
    await repository.load();
    native.jobsGate = Completer<void>();
    final polling = repository.syncNative();
    await flush();
    await submit(repository);
    native.jobsGate!.complete();
    await polling;
    expect(repository.jobs.single.active, isTrue);
    native.jobsGate = null;
    await repository.syncNative();
    expect(repository.jobs.single.state, AiJobState.generating);
  });
}
