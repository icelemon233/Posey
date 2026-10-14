import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:posey/app.dart';
import 'package:posey/controller.dart';
import 'package:posey/models.dart';
import 'package:posey/services.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late TestStorage storage;
  late DelayedService service;
  late PoseyController controller;
  final photo = Uint8List.fromList(
    image.encodeJpg(image.Image(width: 12, height: 16)),
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('posey-test-');
    storage = TestStorage(temp);
    service = DelayedService();
    controller = PoseyController(storage, service);
    await controller.initialize();
    controller.configuration = const AiConfiguration(key: 'test-key');
  });
  tearDown(() async {
    controller.dispose();
    await temp.delete(recursive: true);
  });
  Future<void> flush() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('all fifty native templates and reference images load with source provenance', () async {
    expect(controller.templates.length, 50);
    expect(controller.templates.map((pose) => pose.id).toSet().length, 50);
    expect(
      controller.templates.where((pose) => pose.gender == 'male').length,
      23,
    );
    expect(
      controller.templates.where((pose) => pose.gender == 'female').length,
      27,
    );
    for (final pose in controller.templates) {
      expect(
        (await rootBundle.load(pose.illustration)).lengthInBytes,
        greaterThan(0),
      );
      expect(objectOf(pose.raw['source'])['usageStatus'], 'owned');
    }
  });
  test('parallel submission reserves capacity and cancelled late replies never create results', () async {
    service.prepareGate = Completer<void>();
    final tasks = List.generate(
      3,
      (_) =>
          controller.enqueue(controller.templates.first, photo, consent: true),
    );
    expect(controller.activeJobs, 3);
    await expectLater(
      controller.enqueue(controller.templates.first, photo, consent: true),
      throwsStateError,
    );
    service.prepareGate!.complete();
    await Future.wait(tasks);
    await flush();
    expect(controller.activeJobs, 3);
    expect(service.pending.length, 1);
    final id = service.pending.keys.first;
    await controller.cancel(id);
    service.pending[id]!.complete(photo);
    await flush();
    final job = controller.jobs.firstWhere((job) => job.id == id);
    expect(job.state, AiJobState.cancelled);
    expect(job.resultPath, isNull);
    expect(service.cancelled, contains(id));
    expect(controller.activeJobs, 2);
  });
  test('queued jobs freeze their credentials and prompt, and metadata never contains keys', () async {
    final first = controller.templates.first;
    await controller.enqueue(first, photo, consent: true);
    await flush();
    await controller.enqueue(first, photo, consent: true);
    await controller.saveConfiguration(
      const AiConfiguration(key: 'different-key'),
      const AiPreferences(face: 'natural'),
    );
    final id = service.pending.keys.first;
    service.pending[id]!.complete(photo);
    await flush();
    expect(service.requests.length, 2);
    expect(
      service.requests.values.last.configuration.normalizedKey,
      'test-key',
    );
    expect(service.requests.values.last.body['prompt'], contains('严格锁定'));
    expect(storage.data.values.join(), isNot(contains('different-key')));
    expect(storage.key, 'different-key');
    expect(
      controller.jobs
          .where((job) => job.state == AiJobState.completed)
          .single
          .resultPath,
      isNotNull,
    );
  });
  test('no consent means no photo copy and no remote preparation', () async {
    await expectLater(
      controller.enqueue(controller.templates.first, photo, consent: false),
      throwsStateError,
    );
    expect(service.prepares, 0);
    expect(temp.listSync(), isEmpty);
  });
  test('only twenty successful results are retained without discarding active or failed jobs', () {
    final jobs = List.generate(
      25,
      (i) => AiJob(
        id: '$i',
        targetId: 't',
        targetTitle: 't',
        sourcePath: '',
        createdAt: i,
        state: AiJobState.completed,
      ),
    );
    jobs.add(
      AiJob(
        id: 'pending',
        targetId: 't',
        targetTitle: 't',
        sourcePath: '',
        createdAt: 0,
      ),
    );
    jobs.add(
      AiJob(
        id: 'failed',
        targetId: 't',
        targetTitle: 't',
        sourcePath: '',
        createdAt: 0,
        state: AiJobState.failed,
      ),
    );
    final retained = retainRecentJobs(jobs);
    expect(retained.length, 22);
    expect(retained.any((job) => job.id == '0'), isFalse);
    expect(retained.any((job) => job.id == 'pending'), isTrue);
    expect(retained.any((job) => job.id == 'failed'), isTrue);
  });
  test('Android restart marks interrupted work for explicit retry instead of billing twice', () async {
    final job = AiJob(
      id: 'interrupted',
      targetId: 't',
      targetTitle: 't',
      sourcePath: '',
      createdAt: 1,
      state: AiJobState.generating,
    );
    storage.data['jobs'] = encodeJobs([job]);
    await controller.initialize();
    expect(controller.jobs.single.state, AiJobState.failed);
    expect(service.requests, isEmpty);
  });
  test(
    'device cleanup cannot remove a photo outside its private directory',
    () async {
      SharedPreferences.setMockInitialValues({});
      final appDir = Directory('${temp.path}/app');
      await appDir.create();
      final outside = File('${temp.path}/outside.jpg');
      await outside.writeAsBytes(photo);
      final device = DevicePoseyStorage(
        await SharedPreferences.getInstance(),
        appDir,
      );
      await device.deleteOwnedFile('${appDir.path}/../outside.jpg');
      expect(await outside.exists(), isTrue);
      final own = await device.saveBytes('own.jpg', photo);
      await device.deleteOwnedFile(own);
      expect(await File(own).exists(), isFalse);
      await expectLater(
        device.saveBytes('../outside.jpg', photo),
        throwsFormatException,
      );
    },
  );
  test('AI image requests preserve identity controls and parse real response contracts', () async {
    final transport = MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.headers['authorization'], 'Bearer test-key');
      final body = jsonDecode(request.body) as Map;
      expect((body['image'] as List).length, 2);
      expect(body['watermark'], false);
      expect(body['size'], '2K');
      expect(body['prompt'], contains('不要新增微笑'));
      return http.Response(
        jsonEncode({
          'data': [
            {'b64_json': base64Encode(photo)},
          ],
        }),
        200,
      );
    });
    final api = ArkAiPoseService(clientFactory: () => transport);
    final request = await api.prepare(
      controller.configuration,
      const AiPreferences(),
      controller.templates.first,
      photo,
    );
    expect(await api.generate('contract', request), photo);
    expect(
      () => const AiConfiguration(
        key: 'k',
        endpoint: 'http://example.com',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => resizeForAi(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final large = resizeForAi(
      Uint8List.fromList(
        image.encodeJpg(image.Image(width: 3000, height: 1500)),
      ),
    );
    expect(image.decodeImage(large)!.width, 2048);
    expect(image.decodeImage(large)!.height, 1024);
  });
  testWidgets(
    'favorite and search flows render native reference images and preserve choices',
    (tester) async {
      await tester.pumpWidget(PoseyApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('50 个姿势'), findsOneWidget);
      final first = controller.templates.first;
      await tester.tap(find.byKey(Key('favorite-${first.id}')));
      await tester.pumpAndSettle();
      expect(controller.favorites, contains(first.id));
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('1 个姿势'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pose-search')), '不存在的姿势');
      await tester.pumpAndSettle();
      expect(find.text('还没有匹配的姿势。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
