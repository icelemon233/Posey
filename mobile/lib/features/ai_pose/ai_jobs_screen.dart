import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_jobs_view_model.dart';
import 'package:posey/features/ai_pose/ai_consent.dart';

class AiJobsScreen extends StatelessWidget {
  const AiJobsScreen({
    super.key,
    required this.viewModel,
    required this.onOpenResult,
  });
  final AiJobsViewModel viewModel;
  final ValueChanged<AiJob> onOpenResult;

  Future<void> remove(BuildContext context, AiJob job) async {
    if (job.state == AiJobState.awaitingResult ||
        job.archiveError != null ||
        job.active) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('移除任务？'),
          scrollable: true,
          content: Text(
            job.active
                ? '任务会停止等待和下载，服务可能已经处理并计费。'
                : '这张成片尚未留存到作品，移除任务会删除它的临时副本。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('移除'),
            ),
          ],
        ),
      );
      if (agreed != true || !context.mounted) return;
    }
    await runUiAction(context, () => viewModel.clear(job.id));
  }

  Future<void> retry(BuildContext context, AiJob job) async {
    if (viewModel.isRetrying(job.id)) return;
    final options = viewModel.retryOptions(job);
    if (await confirmAiGeneration(
          context,
          options: options,
          poseTitle:
              '${job.targetTitle}${job.targetSnapshot?['mirrorReference'] == true ? '（镜像）' : ''}',
          retry: true,
        ) &&
        context.mounted) {
      await runUiAction(
        context,
        () => viewModel.retry(job, consent: true, options: options),
      );
    }
  }

  Future<void> resetHistory(BuildContext context) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('重置任务记录？'),
        scrollable: true,
        content: const Text(
          '原有记录会先在本机保留恢复副本，再重新建立任务列表。收藏和系统相册里的照片会保留。此操作不会重新发送生成请求。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('备份并重置'),
          ),
        ],
      ),
    );
    if (agreed == true && context.mounted) {
      await runUiAction(context, viewModel.resetUnreadableHistory);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (viewModel.loadError != null) ...[
          Text(viewModel.loadError!),
          const SizedBox(height: 12),
          const Text('你仍然可以选择姿势、拍照和保存到相册。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: viewModel.recovering
                    ? null
                    : () => runUiAction(context, viewModel.reload),
                child: const Text('重新加载任务'),
              ),
              OutlinedButton(
                onPressed: viewModel.recovering
                    ? null
                    : () => resetHistory(context),
                child: const Text('备份并重置'),
              ),
            ],
          ),
        ] else ...[
          Text(
            '${viewModel.activeJobs} / 3 个进行中的任务',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            viewModel.backgroundSupported
                ? '可在后台继续处理任务。完成后会保留结果。'
                : '生成时请保持应用打开。中断的任务需要你确认重试。',
          ),
          const SizedBox(height: 8),
          const Text('生成的成片会留存在作品。这里保留最近 20 个成功任务。'),
          if (viewModel.jobs.any(
            (job) =>
                job.state == AiJobState.failed ||
                job.state == AiJobState.cancelled,
          ))
            TextButton(
              onPressed: () async {
                final agreed = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('清理失败和取消的任务？'),
                    content: const Text('作品和系统相册里的照片会保留。'),
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
                if (agreed == true && context.mounted) {
                  await runUiAction(context, () => viewModel.clearFinished());
                }
              },
              child: const Text('清理失败和取消的任务'),
            ),
          const SizedBox(height: 20),
          if (viewModel.persistenceError != null)
            ListTile(
              title: Text(viewModel.persistenceError!),
              trailing: TextButton(
                onPressed: () =>
                    runUiAction(context, viewModel.retryPersistence),
                child: const Text('重试保存'),
              ),
            ),
          if (viewModel.syncError != null)
            ListTile(
              title: Text(viewModel.syncError!),
              trailing: TextButton(
                onPressed: () => runUiAction(context, viewModel.syncNative),
                child: const Text('重试同步'),
              ),
            ),
          if (viewModel.jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                children: [
                  SvgPicture.asset(
                    'assets/brand/posey-ai-pose-glyph.svg',
                    width: 72,
                    height: 72,
                  ),
                  const SizedBox(height: 20),
                  const Text('跟着姿势拍一张，或导入照片开始。'),
                ],
              ),
            ),
          ...viewModel.jobs.map(
            (job) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            job.targetTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: '移除任务记录',
                          onPressed: () => remove(context, job),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (job.resultPath != null)
                      InkWell(
                        onTap: () => onOpenResult(job),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(job.resultPath!),
                            height: 230,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 100,
                              child: Center(child: Text('照片已移除')),
                            ),
                          ),
                        ),
                      ),
                    if (job.active) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                    ],
                    Text(switch (job.state) {
                      AiJobState.queued => '等待生成',
                      AiJobState.generating => '正在调整姿势…',
                      AiJobState.awaitingResult =>
                        job.message ?? '成片尚未留存，请重试保存。',
                      AiJobState.completed =>
                        '生成完成 · ${DateTime.fromMillisecondsSinceEpoch(job.completedAt ?? job.createdAt).toLocal().toString().substring(0, 16)}',
                      AiJobState.failed => job.message ?? '生成失败，请重试',
                      AiJobState.cancelled => '已取消',
                    }),
                    const SizedBox(height: 8),
                    if (job.state == AiJobState.awaitingResult)
                      TextButton.icon(
                        onPressed: viewModel.isRetryingResult(job.id)
                            ? null
                            : () => runUiAction(
                                context,
                                () => viewModel.retryResult(job.id),
                              ),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          job.pendingResult == PendingAiResult.download
                              ? '重试下载'
                              : '重试保存图片',
                        ),
                      ),
                    if (job.active)
                      TextButton(
                        onPressed: () => runUiAction(
                          context,
                          () => viewModel.cancel(job.id),
                        ),
                        child: const Text('取消生成'),
                      ),
                    if (!job.active &&
                        job.state != AiJobState.awaitingResult &&
                        job.sourcePath.isNotEmpty)
                      TextButton(
                        onPressed:
                            viewModel.activeJobs >= 3 ||
                                viewModel.isRetrying(job.id)
                            ? null
                            : () => retry(context, job),
                        child: Text(
                          viewModel.isRetrying(job.id)
                              ? '已重新提交'
                              : job.state == AiJobState.completed
                              ? '再次生成'
                              : '重新生成',
                        ),
                      ),
                    if (job.resultPath != null)
                      TextButton.icon(
                        onPressed: () => runUiAction(context, () async {
                          final saved = await viewModel.saveResult(job);
                          if (saved && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已保存到相册')),
                            );
                          }
                        }),
                        icon: const Icon(Icons.download),
                        label: const Text('保存成片'),
                      ),
                    if (job.archiveError != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job.archiveError!),
                          TextButton(
                            onPressed: () => runUiAction(
                              context,
                              () => viewModel.archiveResult(job.id),
                            ),
                            child: const Text('重试留存到作品'),
                          ),
                        ],
                      ),
                    if (job.requestMetadata != null)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('生成设置'),
                        children: [
                          ListTile(
                            title: Text('${job.requestMetadata!['model']}'),
                            subtitle: Text(
                              '${job.requestMetadata!['endpoint']}',
                            ),
                          ),
                          if (job.targetSnapshot?['mirrorReference'] == true)
                            const ListTile(title: Text('镜像参考')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
