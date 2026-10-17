import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posey/app/posey_app.dart';
import 'package:posey/features/settings/ai_settings_screen.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/features/ai_pose/ai_jobs_screen.dart';

import 'support.dart';

void main() {
  final destination = Platform.environment['VISUAL_REVIEW_DIR'];
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'render phone library, settings and AI history recovery for visual review',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final font = Platform.environment['REVIEW_FONT'];
        if (font != null) {
          final bytes = await File(font).readAsBytes();
          await (FontLoader(
            'Roboto',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
        await Directory(destination!).create(recursive: true);
        final icons = Platform.environment['REVIEW_ICONS'];
        if (icons != null) {
          final bytes = await File(icons).readAsBytes();
          await (FontLoader(
            'MaterialIcons',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
      late PoseyDependencies dependencies;
      late TestStorage storage;
      final boundary = GlobalKey();
      await tester.runAsync(() async {
        dependencies = PoseyDependencies(
          storage: storage = TestStorage(Directory(destination!)),
          aiService: DelayedService(),
        );
        await dependencies.initialize();
      });
      Future<void> capture(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$destination/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: PoseyApp(dependencies: dependencies),
        ),
      );
      await capture('posey-library');
      await tester.tap(find.text(dependencies.library.templates.first.title));
      await capture('posey-detail');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            key: const Key('settings-review'),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
            home: AiSettingsScreen(viewModel: dependencies.settings),
          ),
        ),
      );
      await capture('posey-settings');
      await tester.runAsync(() async {
        storage.data['jobs'] = '{}';
        await expectLater(dependencies.jobs.reload(), throwsFormatException);
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            key: const Key('recovery-review'),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
            home: Scaffold(
              appBar: AppBar(title: const Text('AI Pose')),
              body: AiJobsScreen(
                viewModel: dependencies.jobs,
                onOpenResult: (_) {},
              ),
            ),
          ),
        ),
      );
      await capture('posey-ai-recovery');
      await tester.tap(find.text('备份并重置'));
      await capture('posey-ai-recovery-confirm');
      tester.view.physicalSize = const Size(320, 568);
      await capture('posey-ai-recovery-confirm-small');
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
    },
    skip: destination == null,
  );
}
