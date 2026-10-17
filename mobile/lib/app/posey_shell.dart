import 'dart:async';

import 'package:flutter/material.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_jobs_screen.dart';
import 'package:posey/features/camera/camera_screen.dart';
import 'package:posey/features/camera/camera_view_model.dart';
import 'package:posey/features/photo_review/photo_editor.dart';
import 'package:posey/features/photo_review/photo_editor_view_model.dart';
import 'package:posey/features/photo_review/photo_review_screen.dart';
import 'package:posey/features/photo_review/photo_review_view_model.dart';
import 'package:posey/features/poses/pose_details_sheet.dart';
import 'package:posey/features/poses/pose_library_screen.dart';
import 'package:posey/features/poses/pose_picker.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/settings/ai_settings_screen.dart';
import 'package:posey/features/settings/settings_screen.dart';
import 'package:posey/features/works/photo_work.dart';
import 'package:posey/features/works/works_screen.dart';
import 'package:posey/features/backup/backup_screen.dart';
import 'package:posey/features/settings/onboarding_card.dart';

class PoseyShell extends StatefulWidget {
  const PoseyShell({super.key, required this.dependencies});
  final PoseyDependencies dependencies;
  @override
  State<PoseyShell> createState() => _PoseyShellState();
}

class _PoseyShellState extends State<PoseyShell> with WidgetsBindingObserver {
  int page = 0;
  bool picking = false, addingReference = false;
  bool openingNotification = false;
  final pendingNotifications = <String>{};
  Timer? notificationTimer;
  StreamSubscription<String>? notifications;
  PoseyDependencies get dependencies => widget.dependencies;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notifications = dependencies.platform.openedJobs.listen(
      (id) => unawaited(openNotification(id)),
    );
    if (dependencies.platform.supported) unawaited(consumeNotification());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationTimer?.cancel();
    unawaited(notifications?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(dependencies.jobs.syncNative());
    }
  }

  Future<void> consumeNotification() async {
    try {
      final id = await dependencies.platform.pendingJob();
      if (id != null && mounted) await openNotification(id);
    } catch (_) {
      /* Tasks remain accessible from the AI page if a notification cannot be opened. */
    }
  }

  Future<void> openNotification(String id) async {
    pendingNotifications.add(id);
    if (openingNotification) return;
    if (dependencies.backup.busy ||
        picking ||
        addingReference ||
        ModalRoute.of(context)?.isCurrent == false) {
      notificationTimer ??= Timer(const Duration(milliseconds: 350), () {
        notificationTimer = null;
        if (mounted && pendingNotifications.isNotEmpty) {
          unawaited(openNotification(pendingNotifications.first));
        }
      });
      return;
    }
    openingNotification = true;
    try {
      if (dependencies.state != AppLoadState.ready) {
        await dependencies.initialize();
      }
      await dependencies.jobs.syncNative();
      if (!mounted) return;
      if (dependencies.backup.busy ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      setState(() => page = 3);
      pendingNotifications.remove(id);
      if (dependencies.platform.supported) {
        await dependencies.platform.acknowledgeJob(id);
      }
      final job = dependencies.jobs.jobs
          .where((job) => job.id == id)
          .firstOrNull;
      if (job?.state == AiJobState.completed) await openResult(job!);
    } catch (error) {
      pendingNotifications.remove(id);
      if (mounted) showFailure(context, error);
    } finally {
      openingNotification = false;
      if (mounted && pendingNotifications.isNotEmpty) {
        unawaited(openNotification(pendingNotifications.first));
      }
    }
  }

  Future<void> configureAi() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AiSettingsScreen(
        viewModel: dependencies.settings,
        checkConnection: dependencies.checkAiConnection,
        cancelCheck: dependencies.cancelAiConnectionCheck,
      ),
    ),
  );
  Future<void> reviewPhoto(
    String path,
    PoseTemplate target, {
    String? importId,
  }) async {
    PhotoWork? work;
    try {
      work = await dependencies.works.retain(path, target, importId: importId);
    } catch (error) {
      if (mounted) showFailure(context, '照片未能留存到作品：$error');
    }
    if (importId != null && work != null) {
      try {
        await dependencies.importRecovery.complete(importId);
      } catch (_) {
        /* importId prevents duplicate recovery. */
      }
    }
    try {
      await dependencies.library.markUsed(target.id);
    } catch (_) {
      /* Photo retention is independent of recent-use preferences. */
    }
    if (mounted) await review(work, path, target, importId: importId);
  }

  Future<void> review(
    PhotoWork? work,
    String fallbackPath,
    PoseTemplate target, {
    String? importId,
    AiJob? job,
  }) async {
    late PhotoReviewViewModel model;
    model = PhotoReviewViewModel(
      photos: dependencies.photos,
      target: work?.pose ?? target,
      path: work?.path ?? fallbackPath,
      generated: work?.kind == WorkKind.ai || job != null,
      workId: work?.id,
      originalPath:
          work?.original ??
          (job?.sourcePath.isNotEmpty == true ? job!.sourcePath : null),
      hasConfiguration: () =>
          dependencies.settings.configuration.normalizedKey.isNotEmpty,
      serviceHost: () => dependencies.settings.configuration.baseUri.host,
      requestOptions: dependencies.jobs.currentOptions,
      submitRequest: (request, {required consent}) =>
          dependencies.jobs.submitPhoto(
            request.target,
            request.path,
            consent: consent,
            options: request.options,
            sourceWorkId: request.workId,
          ),
      submit: ({required consent}) => dependencies.jobs.submitPhoto(
        model.target,
        model.path,
        consent: consent,
        sourceWorkId: model.workId,
      ),
      submitWithOptions: (options, {required consent}) =>
          dependencies.jobs.submitPhoto(
            model.target,
            model.generated ? model.originalPath ?? model.path : model.path,
            consent: consent,
            options: options,
            sourceWorkId: model.workId,
          ),
      retainAction: () async {
        final retained = await dependencies.works.retain(
          model.path,
          model.target,
          kind: model.generated ? WorkKind.ai : WorkKind.photo,
          originalPath: model.originalPath,
          aiJobId: job?.id,
          importId: importId,
        );
        if (importId != null) {
          try {
            await dependencies.importRecovery.complete(importId);
          } catch (_) {
            /* Retained work has the same importId. */
          }
        }
        return retained;
      },
      savedState: () =>
          dependencies.works.find(model.workId ?? '')?.savedToGallery ?? false,
      saveAction: () async {
        final id = model.workId;
        if (id == null) {
          await dependencies.photos.saveToGallery(model.path);
        } else {
          await dependencies.works.saveToGallery(id);
        }
      },
    );
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PhotoReviewScreen(
          viewModel: model,
          onConfigureAi: configureAi,
          onShare: () => dependencies.platform.shareFiles([model.path]),
          onUseAsReference: () => addReferenceFrom(model.path),
          onChoosePose: () => pickPose(context, dependencies.library.templates),
          onEdit: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PhotoEditorScreen(
                viewModel: PhotoEditorViewModel(
                  path: model.path,
                  photos: dependencies.photos,
                  onSave: (bytes) async {
                    final edited = await dependencies.works.retainBytes(
                      bytes,
                      model.target,
                      sourceWorkId: model.workId,
                      originalPath: model.originalPath ?? model.path,
                    );
                    model.replacePhoto(edited);
                  },
                ),
              ),
            ),
          ),
          onRetake: () {
            Navigator.popUntil(context, (route) => route.isFirst);
            openCamera(model.target);
          },
          onSubmitted: () {
            Navigator.popUntil(context, (route) => route.isFirst);
            setState(() => page = 3);
          },
        ),
      ),
    );
  }

  Future<void> openWork(PhotoWork work) => review(work, work.path, work.pose);
  Future<void> openResult(AiJob job) async {
    var work = dependencies.works.works
        .where((work) => work.aiJobId == job.id)
        .firstOrNull;
    if (work == null) {
      try {
        await dependencies.jobs.archiveResult(job.id);
        work = dependencies.works.works
            .where((work) => work.aiJobId == job.id)
            .firstOrNull;
      } catch (_) {
        /* The review can still save a generated result to the gallery. */
      }
    }
    if (!mounted) return;
    if (work != null) {
      await openWork(work);
      return;
    }
    final target = dependencies.jobs.targetFor(job);
    if (target == null || job.resultPath == null) {
      showFailure(context, '照片或参考记录暂时不可用');
      return;
    }
    await review(null, job.resultPath!, target, job: job);
  }

  Future<void> openCamera(PoseTemplate pose) async {
    if (!pose.available) {
      final selected = await pickPose(context, dependencies.library.templates);
      if (selected == null || !mounted) return;
      pose = selected;
    }
    String? importId;
    final model = CameraViewModel(
      pose,
      photos: dependencies.photos,
      preferences: dependencies.settings.camera,
      onPreferencesChanged: dependencies.settings.setCameraPreferences,
      beforeImport: (target) async {
        importId = await dependencies.importRecovery.stage(target);
      },
      importCancelled: () async {
        if (importId != null) {
          await dependencies.importRecovery.complete(importId!);
        }
      },
      importSelected: (path, target) async {
        if (importId != null) {
          await dependencies.importRecovery.selected(importId!, path);
          try {
            await dependencies.works.retain(path, target, importId: importId);
          } catch (_) {
            dependencies.noteImportFailure();
            rethrow;
          }
        }
      },
    );
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PoseyCameraScreen(
          viewModel: model,
          poses: dependencies.library.templates,
          onPhoto: reviewPhoto,
          onImportedPhoto: (path, target) =>
              reviewPhoto(path, target, importId: importId),
          onOpenSettings: dependencies.platform.openSettings,
        ),
      ),
    );
  }

  Future<void> importPhoto(PoseTemplate pose) async {
    if (picking) return;
    picking = true;
    try {
      final id = await dependencies.importRecovery.stage(pose);
      final path = await dependencies.photos.pickPhoto();
      if (path == null) {
        await dependencies.importRecovery.complete(id);
        return;
      }
      await dependencies.importRecovery.selected(id, path);
      if (mounted) await reviewPhoto(path, pose, importId: id);
    } catch (error) {
      dependencies.noteImportFailure();
      if (mounted) showFailure(context, error);
    } finally {
      picking = false;
    }
  }

  Future<void> addReference() async {
    if (addingReference) return;
    addingReference = true;
    try {
      final id = await dependencies.importRecovery.stage(
        PoseTemplate.fromJson({
          'id': 'unselected-reference',
          'title': '未选择参考',
          'illustration': '',
          'unavailable': true,
        }),
      );
      final path = await dependencies.photos.pickPhoto();
      if (path == null) {
        await dependencies.importRecovery.complete(id);
        return;
      }
      if (!mounted) return;
      await dependencies.importRecovery.selected(id, path);
      await saveReferenceFrom(path);
      await dependencies.importRecovery.complete(id);
    } catch (error) {
      dependencies.noteImportFailure();
      if (mounted) showFailure(context, error);
    } finally {
      addingReference = false;
    }
  }

  Future<void> addReferenceFrom(String path) async {
    if (addingReference) return;
    addingReference = true;
    try {
      await saveReferenceFrom(path);
    } finally {
      addingReference = false;
    }
  }

  Future<void> saveReferenceFrom(String path) async {
    final values =
        await showDialog<({String title, String category, String gender})>(
          context: context,
          builder: (_) => const ReferenceForm(),
        );
    if (values != null) {
      await dependencies.library.addReference(
        path,
        values.title,
        values.category,
        values.gender,
      );
    }
  }

  Future<void> renameReference(PoseTemplate pose) async {
    final values =
        await showDialog<({String title, String category, String gender})>(
          context: context,
          builder: (_) => ReferenceForm(initial: pose),
        );
    if (values != null && mounted) {
      await runUiAction(
        context,
        () => dependencies.library.renameReference(
          pose,
          values.title,
          category: values.category,
          gender: values.gender,
        ),
      );
    }
  }

  Future<void> deleteReference(PoseTemplate pose) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('删除“${pose.title}”？'),
        content: const Text('相关作品和已提交的 AI 任务会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (agreed == true && mounted) {
      await runUiAction(
        context,
        () => dependencies.library.deleteReference(pose),
      );
    }
  }

  void openPose(PoseTemplate pose) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => PoseDetailsSheet(
      pose: pose,
      onCamera: () {
        Navigator.pop(sheet);
        unawaited(openCamera(pose));
      },
      onImport: () {
        Navigator.pop(sheet);
        unawaited(importPhoto(pose));
      },
      onRename: pose.isUserReference
          ? () {
              Navigator.pop(sheet);
              unawaited(renameReference(pose));
            }
          : null,
      onDelete: pose.isUserReference
          ? () {
              Navigator.pop(sheet);
              unawaited(deleteReference(pose));
            }
          : null,
    ),
  );
  void shuffle() {
    final pose = dependencies.library.randomPose(
      favoritesOnly: page == 1,
      onlySaved: dependencies.settings.shuffleFavorites,
    );
    if (pose == null) {
      showFailure(context, '当前筛选没有可选姿势。请清除筛选或添加收藏。');
      return;
    }
    openPose(pose);
  }

  Future<void> openBackup() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => BackupScreen(manager: dependencies.backup),
    ),
  );
  Future<void> resetImport() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('清除导入恢复记录？'),
        scrollable: true,
        content: const Text('先在本机保留原始记录的恢复副本，再清除这次未完成的导入。已留存的作品会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('备份并清除'),
          ),
        ],
      ),
    );
    if (agreed == true) await dependencies.resetImportRecovery();
  }

  Future<void> notificationsPermission() async {
    if (!await dependencies.platform.requestNotifications(force: true)) {
      throw StateError('通知尚未允许，请在系统设置中开启。');
    }
  }

  Future<void> clearTaskCopies() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('清理已结束任务的副本？'),
        scrollable: true,
        content: const Text('作品、系统相册、进行中的任务和未留存成片会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (agreed == true && mounted) {
      await runUiAction(
        context,
        () => dependencies.jobs.clearFinished(includeCompleted: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: dependencies,
    builder: (context, _) => PopScope(
      canPop: page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => page = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: page == 0
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/brand/posey-icon.png',
                      width: 30,
                      height: 30,
                    ),
                    const SizedBox(width: 10),
                    const Text('Posey'),
                  ],
                )
              : Text(['', '收藏', '作品', 'AI 任务', '设置'][page]),
          actions: page < 2
              ? [
                  IconButton(
                    onPressed: shuffle,
                    tooltip: '随机参考',
                    icon: const Icon(Icons.shuffle),
                  ),
                ]
              : page == 2
              ? [
                  IconButton(
                    tooltip: '导入照片',
                    onPressed: () async {
                      final pose = await pickPose(
                        context,
                        dependencies.library.templates,
                      );
                      if (pose != null) await importPhoto(pose);
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
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
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: dependencies.initialize,
                    child: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          ),
          AppLoadState.ready => switch (page) {
            0 || 1 => Column(
              children: [
                if (page == 0) OnboardingCard(model: dependencies.settings),
                Expanded(
                  child: PoseLibraryScreen(
                    viewModel: dependencies.library,
                    favoritesOnly: page == 1,
                    onOpenPose: openPose,
                    onAddReference: addReference,
                  ),
                ),
              ],
            ),
            2 => WorksScreen(
              repository: dependencies.works,
              onOpen: (work) => unawaited(openWork(work)),
              onShare: dependencies.platform.shareFiles,
            ),
            3 => AiJobsScreen(
              viewModel: dependencies.jobs,
              onOpenResult: (job) => unawaited(openResult(job)),
            ),
            _ => SettingsScreen(
              viewModel: dependencies.settings,
              onConfigureAi: configureAi,
              onBackup: openBackup,
              onOpenSettings: dependencies.platform.openSettings,
              onNotifications: notificationsPermission,
              deviceInfo: dependencies.deviceInfo(),
              importError: dependencies.importError,
              onRecoverImport: dependencies.retryImportRecovery,
              onResetImport: resetImport,
              onClearTasks: clearTaskCopies,
            ),
          },
        },
        bottomNavigationBar: AnimatedBuilder(
          animation: dependencies.jobs,
          builder: (context, _) => NavigationBar(
            selectedIndex: page,
            onDestinationSelected: (value) => setState(() => page = value),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.grid_view_rounded),
                label: '姿势库',
              ),
              const NavigationDestination(
                icon: Icon(Icons.favorite_border),
                label: '收藏',
              ),
              const NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                label: '作品',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible:
                      dependencies.jobs.loadError != null ||
                      dependencies.jobs.activeJobs > 0,
                  label: Text(
                    dependencies.jobs.loadError != null
                        ? '!'
                        : '${dependencies.jobs.activeJobs}',
                  ),
                  child: const Icon(Icons.auto_awesome_outlined),
                ),
                label: 'AI 任务',
              ),
              const NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
            ],
          ),
        ),
      ),
    ),
  );
}
