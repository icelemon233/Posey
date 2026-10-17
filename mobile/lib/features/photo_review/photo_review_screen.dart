import 'dart:io';

import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/core/ui/reference_image.dart';
import 'package:posey/features/ai_pose/ai_consent.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/photo_review/photo_review_view_model.dart';

class PhotoReviewScreen extends StatefulWidget {
  const PhotoReviewScreen({
    super.key,
    required this.viewModel,
    required this.onConfigureAi,
    this.onEdit,
    this.onShare,
    this.onRetake,
    this.onChoosePose,
    this.onSubmitted,
    this.onUseAsReference,
  });
  final PhotoReviewViewModel viewModel;
  final Future<void> Function() onConfigureAi;
  final Future<void> Function()? onEdit, onShare;
  final Future<void> Function()? onUseAsReference;
  final VoidCallback? onRetake, onSubmitted;
  final Future<PoseTemplate?> Function()? onChoosePose;
  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  PhotoReviewViewModel get model => widget.viewModel;
  bool confirming = false, allowDiscard = false;
  String view = 'photo';
  double comparison = .5;
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    if (confirming || model.busy) return;
    confirming = true;
    try {
      if (!model.target.available) {
        final pose = await widget.onChoosePose?.call();
        if (pose == null || !mounted) return;
        model.selectTarget(pose);
      }
      if (!model.hasConfiguration()) {
        await widget.onConfigureAi();
        if (!mounted || !model.hasConfiguration()) return;
      }
      if(!model.retained&&model.retainAction!=null){await model.retain();if(!mounted)return;}
      final request=model.createRequest();
      final options = request?.options??model.requestOptions?.call();
      final agreed = options != null
          ? await confirmAiGeneration(
              context,
              options: options,
              poseTitle: '${request?.target.title??model.target.title}${(request?.target.mirrored??model.target.mirrored)?'（镜像）':''}',
              retry: model.generated,
            )
          : await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('使用 AI 生成？'),
                    content: Text(
                      '照片和参考图将发送到 ${model.serviceHost()}，服务可能按用量收费。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('同意并生成'),
                      ),
                    ],
                  ),
                ) ??
                false;
      if (!mounted || !agreed) return;
      final accepted = await model.generate(consent: true, options: options,request:request);
      if (mounted && accepted) {
        if (widget.onSubmitted != null) {
          widget.onSubmitted!();
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已提交生成任务')));
        }
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      confirming = false;
    }
  }

  Future<void> leave(bool didPop) async {
    if (didPop) return;
    if (model.busy) {
      showFailure(context, '请等待当前操作完成');
      return;
    }
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('照片尚未留存'),
        content: const Text('可以先保存到作品或系统相册。直接离开后，可能无法找回这张照片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('继续查看'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('离开'),
          ),
        ],
      ),
    );
    if (mounted && agreed == true) {
      setState(() => allowDiscard = true);
      Navigator.pop(context);
    }
  }

  Widget photo(String path) => Image.file(
    File(path),
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const Center(child: Text('照片无法读取，请重新选择。')),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final canCompare =
          model.originalPath != null && model.originalPath != model.path;
      return PopScope(
        canPop:
            !model.busy &&
            (allowDiscard ||
                model.retained ||
                model.saved ||
                model.retainAction == null),
        onPopInvokedWithResult: (didPop, _) => leave(didPop),
        child: Scaffold(
          appBar: AppBar(
            title: Text(model.generated ? 'AI 成片' : '照片'),
            actions: [
              if (widget.onShare != null)
                IconButton(
                  tooltip: '分享照片',
                  onPressed: model.busy
                      ? null
                      : () => runUiAction(context, widget.onShare!),
                  icon: const Icon(Icons.share_outlined),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (!model.retained && model.retainAction != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Expanded(child: Text('照片尚未保存到作品。')),
                        TextButton(
                          onPressed: model.busy
                              ? null
                              : () => runUiAction(context, model.retain),
                          child: const Text('重试留存'),
                        ),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in {
                      'photo': '照片',
                      if (canCompare) 'original': '原图',
                      if (canCompare) 'compare': '对比',
                      'reference': '参考',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: view == entry.key,
                        onSelected: (_) => setState(() => view = entry.key),
                      ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: view == 'reference'
                        ? ReferenceImage(
                            model.target.illustration,
                            mirrored: model.target.mirrored,
                          )
                        : view == 'original' && canCompare
                        ? InteractiveViewer(child: photo(model.originalPath!))
                        : view == 'compare' && canCompare
                        ? Column(
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, size) => Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      photo(model.path),
                                      ClipRect(
                                        clipper: _ComparisonClip(comparison),
                                        child: photo(model.originalPath!),
                                      ),
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: Chip(label: const Text('原图')),
                                      ),
                                      const Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Chip(label: Text('成片')),
                                      ),
                                      Positioned(
                                        left: size.maxWidth * comparison,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 2,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Slider(
                                value: comparison,
                                onChanged: (value) =>
                                    setState(() => comparison = value),
                              ),
                            ],
                          )
                        : InteractiveViewer(child: photo(model.path)),
                  ),
                ),
                if (model.busy) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '参考：${model.target.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '镜像参考',
                            onPressed: model.busy
                                ? null
                                : () => model.selectTarget(
                                    model.target.withMirror(
                                      !model.target.mirrored,
                                    ),
                                  ),
                            icon: const Icon(Icons.flip),
                          ),
                          if (widget.onChoosePose != null)
                            TextButton(
                              onPressed: model.busy
                                  ? null
                                  : () async {
                                      final pose = await widget.onChoosePose!();
                                      if (pose != null && mounted) {
                                        model.selectTarget(pose);
                                      }
                                    },
                              child: const Text('换参考'),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: model.busy || model.saved
                                  ? null
                                  : () => runUiAction(context, model.save),
                              icon: Icon(
                                model.saved
                                    ? Icons.check
                                    : Icons.download_outlined,
                              ),
                              label: Text(model.saved ? '已保存到相册' : '保存到相册'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: model.busy ? null : generate,
                              icon: const Icon(Icons.auto_awesome),
                              label: Text(model.generated ? '用原图再生成' : 'AI 生成'),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          if (widget.onEdit != null)
                            TextButton.icon(
                              onPressed: model.busy
                                  ? null
                                  : () => runUiAction(context, widget.onEdit!),
                              icon: const Icon(Icons.crop_rotate),
                              label: const Text('编辑副本'),
                            ),
                          if (widget.onRetake != null)
                            TextButton.icon(
                              onPressed: model.busy ? null : widget.onRetake,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('重拍'),
                            ),
                          if (widget.onUseAsReference != null)
                            TextButton(
                              onPressed: model.busy
                                  ? null
                                  : () => runUiAction(
                                      context,
                                      widget.onUseAsReference!,
                                    ),
                              child: const Text('设为参考'),
                            ),
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
    },
  );
}

class _ComparisonClip extends CustomClipper<Rect> {
  _ComparisonClip(this.fraction);
  final double fraction;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  @override
  bool shouldReclip(covariant _ComparisonClip oldClipper) =>
      oldClipper.fraction != fraction;
}
