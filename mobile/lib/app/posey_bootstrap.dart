import 'dart:async';

import 'package:flutter/material.dart';
import 'package:posey/app/posey_app.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/core/storage/posey_storage.dart';
import 'package:posey/features/ai_pose/ark_ai_pose_service.dart';

class PoseyBootstrap extends StatefulWidget {
  const PoseyBootstrap({super.key, this.createDependencies});
  final Future<PoseyDependencies> Function()? createDependencies;
  @override
  State<PoseyBootstrap> createState() => _PoseyBootstrapState();
}

class _PoseyBootstrapState extends State<PoseyBootstrap> {
  PoseyDependencies? _dependencies;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final dependencies =
          await (widget.createDependencies?.call() ?? _openDevice());
      if (!mounted) {
        dependencies.dispose();
        return;
      }
      setState(() => _dependencies = dependencies);
      await dependencies.initialize();
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开设备存储，请重试。');
    }
  }

  Future<PoseyDependencies> _openDevice() async => PoseyDependencies(
    storage: await DevicePoseyStorage.open(),
    aiService: ArkAiPoseService(),
  );
  @override
  void dispose() {
    _dependencies?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dependencies != null) return PoseyApp(dependencies: _dependencies!);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _start, child: const Text('重新加载')),
                  ],
                ),
        ),
      ),
    );
  }
}
