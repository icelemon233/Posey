import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posey/app.dart';
import 'package:posey/controller.dart';

import 'support.dart';

void main() {
  final destination = Platform.environment['VISUAL_REVIEW_DIR'];
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'render phone pose library, details and private-key settings for visual review',
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
      late PoseyController controller;
      final boundary = GlobalKey();
      await tester.runAsync(() async {
        controller = PoseyController(
          TestStorage(Directory(destination!)),
          DelayedService(),
        );
        await controller.initialize();
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
          child: PoseyApp(controller: controller),
        ),
      );
      await capture('posey-library');
      await tester.tap(find.text(controller.templates.first.title));
      await capture('posey-detail');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            key: const Key('settings-review'),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
            home: AiSettingsScreen(controller: controller),
          ),
        ),
      );
      await capture('posey-settings');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    skip: destination == null,
  );
}
