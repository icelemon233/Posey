import 'package:flutter/material.dart';

import 'app.dart';
import 'controller.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = PoseyController(
    await DevicePoseyStorage.open(),
    ArkAiPoseService(),
  );
  runApp(PoseyApp(controller: controller));
  await controller.initialize();
}
