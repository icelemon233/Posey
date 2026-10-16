import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/ai_pose/ai_job.dart';
import 'package:posey/features/ai_pose/ai_jobs_view_model.dart';

class AiJobsScreen extends StatelessWidget {
  const AiJobsScreen({
    super.key,
    required this.viewModel,
    required this.onOpenResult,
  });
  final AiJobsViewModel viewModel;
  final ValueChanged<AiJob> onOpenResult;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${viewModel.activeJobs} / 3 个进行中的任务',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          viewModel.backgroundSupported
              ? 'iOS 可继续处理后台任务；完成后返回这里查看。'
              : '生成时请保持应用打开。中断的任务需要你确认重试。',
        ),
        const SizedBox(height: 8),
        const Text('保留最近 20 张成片，喜欢的照片记得保存到相册。'),
        const SizedBox(height: 20),
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
                        onPressed: () =>
                            runUiAction(context, () => viewModel.clear(job.id)),
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
                    AiJobState.completed =>
                      '生成完成 · ${DateTime.fromMillisecondsSinceEpoch(job.completedAt ?? job.createdAt).toLocal().toString().substring(0, 16)}',
                    AiJobState.failed => job.message ?? '生成失败，请重试',
                    AiJobState.cancelled => '已取消',
                  }),
                  const SizedBox(height: 8),
                  if (job.active)
                    TextButton(
                      onPressed: () =>
                          runUiAction(context, () => viewModel.cancel(job.id)),
                      child: const Text('取消生成'),
                    ),
                  if ((job.state == AiJobState.failed ||
                          job.state == AiJobState.cancelled) &&
                      job.sourcePath.isNotEmpty)
                    TextButton(
                      onPressed: viewModel.activeJobs >= 3
                          ? null
                          : () => runUiAction(
                              context,
                              () => viewModel.retry(job),
                            ),
                      child: const Text('重新生成'),
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
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
