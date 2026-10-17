import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:posey/app/posey_app.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/features/backup/backup_screen.dart';
import 'package:posey/features/camera/camera_preferences.dart';
import 'package:posey/features/camera/camera_screen.dart';
import 'package:posey/features/camera/camera_view_model.dart';
import 'package:posey/features/photo_review/photo_editor.dart';
import 'package:posey/features/photo_review/photo_editor_view_model.dart';
import 'package:posey/features/photo_review/photo_review_screen.dart';
import 'package:posey/features/photo_review/photo_review_view_model.dart';
import 'package:posey/features/settings/ai_settings_screen.dart';

import 'support.dart';
import 'workflows_test.dart' show FilePhotos, ManualCamera, PreviewController;

void main() {
  final destination = Platform.environment['VISUAL_REVIEW_DIR'];
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'render feature flows in light, dark, compact and large text layouts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      late PoseyDependencies deps;
      late String path;
      final photos = FilePhotos();
      await tester.runAsync(() async {
        await Directory(destination!).create(recursive: true);
        for (final entry in {
          'Roboto': Platform.environment['REVIEW_FONT'],
          'MaterialIcons': Platform.environment['REVIEW_ICONS'],
        }.entries) {
          if (entry.value != null) {
            final bytes = await File(entry.value!).readAsBytes();
            await (FontLoader(
              entry.key,
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          }
        }
        final directory = await Directory.systemTemp.createTemp(
          'posey-visual-workflows-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = TestStorage(directory);
        deps = PoseyDependencies(
          storage: storage,
          aiService: DelayedService(),
          photos: photos,
        );
        await deps.initialize();
        final pixels = image.Image(width: 480, height: 640);
        for (var y = 0; y < 640; y++) {
          for (var x = 0; x < 480; x++) {
            pixels.setPixelRgb(x, y, 120 + x ~/ 5, 150 + y ~/ 10, 180);
          }
        }
        path = await storage.saveBytes(
          'synthetic-scene.jpg',
          Uint8List.fromList(image.encodeJpg(pixels)),
        );
        await deps.works.retain(path, deps.library.templates.first);
        await deps.library.toggleFavorite(deps.library.templates.first.id);
      });
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await tester.runAsync(() async {
          final pixels =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await pixels.toByteData(format: ui.ImageByteFormat.png);
          await File('$destination/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          pixels.dispose();
        });
      }

      for (final dark in [false, true]) {
        for (final compact in [false, true]) {
          final size = compact ? const Size(320, 568) : const Size(390, 844),
              scale = compact ? 1.7 : 1.0;
          final tag =
              '${dark ? 'dark' : 'light'}-${compact ? 'compact-large' : 'phone'}';
          tester.view.physicalSize = size;
          await tester.runAsync(
            () => deps.settings.setThemeMode(dark ? 'dark' : 'light'),
          );
          Widget wrap(Widget child) => RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: child,
            ),
          );
          await tester.pumpWidget(
            wrap(PoseyApp(key: ValueKey(tag), dependencies: deps)),
          );
          await capture('library-$tag');
          await tester.tap(find.text('作品'));
          await capture('works-$tag');
          await tester.tap(find.text('设置'));
          await capture('settings-$tag');
          ThemeData theme = ThemeData(
            useMaterial3: true,
            brightness: dark ? Brightness.dark : Brightness.light,
            colorSchemeSeed: const Color(0xFF366780),
            fontFamily: 'Roboto',
          );
          Widget page(Widget child) => wrap(
            MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: child,
            ),
          );
          final work = deps.works.works.first;
          final review = PhotoReviewViewModel(
            photos: photos,
            target: work.pose,
            path: work.path,
            workId: work.id,
            originalPath: path,
            hasConfiguration: () => true,
            serviceHost: () => 'example.test',
            submit: ({required consent}) async {},
          );
          await tester.pumpWidget(
            page(
              PhotoReviewScreen(
                viewModel: review,
                onConfigureAi: () async {},
                onEdit: () async {},
                onRetake: () {},
                onUseAsReference: () async {},
                onChoosePose: () async => work.pose,
              ),
            ),
          );
          await capture('review-$tag');
          await tester.tap(find.text('对比'));
          await capture('comparison-$tag');
          final editor = PhotoEditorViewModel(
            path: path,
            photos: photos,
            onSave: (_) async {},
          );
          await tester.runAsync(editor.load);
          await tester.pumpWidget(page(PhotoEditorScreen(viewModel: editor)));
          await capture('editor-$tag');
          await tester.pumpWidget(
            page(AiSettingsScreen(viewModel: deps.settings)),
          );
          await capture('ai-settings-$tag');
          await tester.pumpWidget(page(BackupScreen(manager: deps.backup)));
          await capture('backup-$tag');
          final gateway = ManualCamera()
            ..session.controller = PreviewController();
          final camera = CameraViewModel(
            work.pose,
            photos: photos,
            gateway: gateway,
            preferences: const CameraPreferences(grid: true),
          );
          await tester.pumpWidget(
            page(
              PoseyCameraScreen(
                viewModel: camera,
                poses: [work.pose],
                onPhoto: (_, _) async {},
              ),
            ),
          );
          await capture('camera-layout-$tag');
          await tester.pumpWidget(const SizedBox.shrink());
          await camera.waitForRelease();
        }
      }
      deps.dispose();
    },
    skip: destination == null,
  );
}
