import 'dart:io';

import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/photo_review/photo_review_view_model.dart';

class PhotoReviewScreen extends StatefulWidget {
  const PhotoReviewScreen({
    super.key,
    required this.viewModel,
    required this.onConfigureAi,
  });
  final PhotoReviewViewModel viewModel;
  final Future<void> Function() onConfigureAi;
  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  PhotoReviewViewModel get viewModel => widget.viewModel;
  bool _confirming = false;
  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    if (_confirming || viewModel.busy) return;
    _confirming = true;
    try {
      if (!viewModel.hasConfiguration()) {
        await widget.onConfigureAi();
        if (!mounted || !viewModel.hasConfiguration()) return;
      }
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('使用 AI Pose 调整姿势'),
          content: Text(
            '这张照片和“${viewModel.target.title}”参考图将发送到你在设置中配置的 AI 服务（${viewModel.serviceHost()}）。'
            '服务可能按你的账户用量收费。请使用你有权处理的照片。原照片仍保留在本机。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('同意并生成'),
            ),
          ],
        ),
      );
      if (!mounted || agreed != true) return;
      final submitted = await viewModel.generate(consent: true);
      if (mounted && submitted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入 AI Pose，结果可在任务页查看。')));
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(viewModel.generated ? 'AI Pose 成片' : '这一次，很自然'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                child: Image.file(
                  File(viewModel.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('照片暂时无法读取，请重新选择。')),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('参考姿势 · ${viewModel.target.title}'),
                  const SizedBox(height: 16),
                  if (viewModel.busy) const LinearProgressIndicator(),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: viewModel.busy
                              ? null
                              : () => runUiAction(context, () async {
                                  await viewModel.save();
                                }),
                          icon: Icon(
                            viewModel.saved
                                ? Icons.check
                                : Icons.download_outlined,
                          ),
                          label: Text(viewModel.saved ? '已保存到相册' : '保存到相册'),
                        ),
                      ),
                      if (!viewModel.generated) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: viewModel.busy ? null : generate,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('AI Pose'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
