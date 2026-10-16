import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_jobs_screen.dart';
import 'package:posey/features/camera/camera_screen.dart';
import 'package:posey/features/camera/camera_view_model.dart';
import 'package:posey/features/photo_review/photo_review_screen.dart';
import 'package:posey/features/photo_review/photo_review_view_model.dart';
import 'package:posey/features/poses/pose_details_sheet.dart';
import 'package:posey/features/poses/pose_library_screen.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/settings/ai_settings_screen.dart';
import 'package:posey/features/settings/settings_screen.dart';

class PoseyShell extends StatefulWidget {
  const PoseyShell({super.key, required this.dependencies});
  final PoseyDependencies dependencies;
  @override
  State<PoseyShell> createState() => _PoseyShellState();
}

class _PoseyShellState extends State<PoseyShell> with WidgetsBindingObserver {
  int _page = 0;
  PoseyDependencies get dependencies => widget.dependencies;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) dependencies.jobs.syncNative();
  }

  Future<void> _configureAi() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AiSettingsScreen(viewModel: dependencies.settings),
    ),
  );

  Future<void> _review(
    String path,
    PoseTemplate target, {
    bool generated = false,
  }) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PhotoReviewScreen(
        viewModel: PhotoReviewViewModel(
          photos: dependencies.photos,
          target: target,
          path: path,
          generated: generated,
          hasConfiguration: () =>
              dependencies.settings.configuration.normalizedKey.isNotEmpty,
          serviceHost: () =>
              Uri.tryParse(dependencies.settings.configuration.endpoint)
                  ?.host ??
              'AI 服务',
          submit: ({required consent}) =>
              dependencies.jobs.submitPhoto(target, path, consent: consent),
        ),
        onConfigureAi: _configureAi,
      ),
    ),
  );

  void _openResult(AiJob job) {
    final target = dependencies.jobs.targetFor(job);
    if (target == null || job.resultPath == null) {
      showFailure(context, '照片或参考姿势已不可用。');
      return;
    }
    _review(job.resultPath!, target, generated: true);
  }

  void _openCamera(PoseTemplate pose) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PoseyCameraScreen(
        viewModel: CameraViewModel(pose, photos: dependencies.photos),
        poses: dependencies.library.templates,
        onPhoto: _review,
      ),
    ),
  );

  Future<void> _import(PoseTemplate pose) => runUiAction(context, () async {
    final path = await dependencies.photos.pickPhoto();
    if (path != null && mounted) await _review(path, pose);
  });

  void _openPose(PoseTemplate pose) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => PoseDetailsSheet(
      pose: pose,
      onCamera: () {
        Navigator.pop(sheet);
        _openCamera(pose);
      },
      onImport: () {
        Navigator.pop(sheet);
        _import(pose);
      },
    ),
  );

  void _shuffle() {
    final pose = dependencies.library.randomPose(
      favoritesOnly: _page == 1,
      onlySaved: dependencies.settings.shuffleFavorites,
    );
    if (pose == null) {
      showFailure(context, '当前范围没有姿势，调整筛选或先收藏几个喜欢的姿势。');
      return;
    }
    _openPose(pose);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: dependencies,
    builder: (context, _) => PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _page = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: _page == 0
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/brand/posey-mark.svg',
                      width: 32,
                      height: 32,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Posey',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                )
              : Text(['', '我的收藏', 'AI Pose', '设置'][_page]),
          actions: _page < 2
              ? [
                  IconButton(
                    onPressed: _shuffle,
                    tooltip: '随心拍',
                    icon: const Icon(Icons.shuffle),
                  ),
                ]
              : null,
        ),
        body: switch (dependencies.state) {
          AppLoadState.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          AppLoadState.failed => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dependencies.error ?? '加载失败'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: dependencies.initialize,
                    child: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          ),
          AppLoadState.ready => switch (_page) {
            0 || 1 => PoseLibraryScreen(
              viewModel: dependencies.library,
              favoritesOnly: _page == 1,
              onOpenPose: _openPose,
            ),
            2 => AiJobsScreen(
              viewModel: dependencies.jobs,
              onOpenResult: _openResult,
            ),
            _ => SettingsScreen(viewModel: dependencies.settings),
          },
        },
        bottomNavigationBar: AnimatedBuilder(
          animation: dependencies.jobs,
          builder: (context, _) => NavigationBar(
            selectedIndex: _page,
            onDestinationSelected: (value) => setState(() => _page = value),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.grid_view_rounded),
                label: '姿势库',
              ),
              const NavigationDestination(
                icon: Icon(Icons.favorite_border),
                label: '收藏',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: dependencies.jobs.activeJobs > 0,
                  label: Text('${dependencies.jobs.activeJobs}'),
                  child: const Icon(Icons.auto_awesome_outlined),
                ),
                label: 'AI Pose',
              ),
              const NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
            ],
          ),
        ),
      ),
    ),
  );
}
