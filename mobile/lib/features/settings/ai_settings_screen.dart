import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/settings/settings_view_model.dart';
import 'package:posey/features/settings/settings_recovery.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({
    super.key,
    required this.viewModel,
    this.checkConnection,
    this.cancelCheck,
  });
  final SettingsViewModel viewModel;
  final Future<AiConnectionCheck> Function(AiConfiguration)? checkConnection;
  final VoidCallback? cancelCheck;
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final keyInput = TextEditingController(
    text: widget.viewModel.configuration.key,
  );
  late final endpoint = TextEditingController(
    text: widget.viewModel.configuration.endpoint,
  );
  late final model = TextEditingController(
    text: widget.viewModel.configuration.model,
  );
  late String face = widget.viewModel.preferences.face,
      expression = widget.viewModel.preferences.expression,
      gaze = widget.viewModel.preferences.gaze;
  bool saving = false, checking = false, visible = false;
  int checkRevision = 0;
  AiConnectionCheck? check;
  late int savedRevision;
  @override
  void initState() {
    super.initState();
    savedRevision = widget.viewModel.revision;
    widget.viewModel.addListener(savedChanged);
  }

  void savedChanged() {
    if (savedRevision == widget.viewModel.revision) return;
    savedRevision = widget.viewModel.revision;
    checkRevision++;
    widget.cancelCheck?.call();
    keyInput.text = widget.viewModel.configuration.key;
    endpoint.text = widget.viewModel.configuration.endpoint;
    model.text = widget.viewModel.configuration.model;
    if (mounted) {
      setState(() {
        face = widget.viewModel.preferences.face;
        expression = widget.viewModel.preferences.expression;
        gaze = widget.viewModel.preferences.gaze;
        check = null;
        checking = false;
      });
    }
  }

  AiConfiguration draft() => AiConfiguration(
    key: keyInput.text,
    endpoint: endpoint.text.trim(),
    model: model.text.trim(),
  );
  @override
  void dispose() {
    widget.viewModel.removeListener(savedChanged);
    checkRevision++;
    widget.cancelCheck?.call();
    keyInput.dispose();
    endpoint.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> testConnection() async {
    if (checking || saving || widget.checkConnection == null) return;
    final options = draft(), request = ++checkRevision;
    setState(() {
      checking = true;
      check = null;
    });
    try {
      final result = await widget.checkConnection!(options);
      if (mounted && request == checkRevision) setState(() => check = result);
    } catch (error) {
      if (mounted && request == checkRevision) showFailure(context, error);
    } finally {
      if (mounted && request == checkRevision) setState(() => checking = false);
    }
  }

  Future<void> save() async {
    if (saving || checking) return;
    setState(() => saving = true);
    try {
      await widget.viewModel.saveConfiguration(
        draft(),
        AiPreferences(face: face, expression: expression, gaze: gaze),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void invalidate() {
    checkRevision++;
    widget.cancelCheck?.call();
    setState(() {
      checking = false;
      check = null;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) => PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('AI 设置')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsRecovery(model: widget.viewModel),
            const Text('使用自己的火山方舟或兼容图像服务。只有确认生成后，所选照片与参考图才会发送到服务。'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('ai-api-key'),
              controller: keyInput,
              obscureText: !visible,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => invalidate(),
              decoration: InputDecoration(
                labelText: 'API Key',
                suffixIcon: IconButton(
                  tooltip: '显示或隐藏密钥',
                  onPressed: () => setState(() => visible = !visible),
                  icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: endpoint,
              keyboardType: TextInputType.url,
              onChanged: (_) => invalidate(),
              decoration: const InputDecoration(
                labelText: '服务地址',
                helperText: 'HTTPS 根地址或完整的图像生成地址',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: model,
              onChanged: (_) => invalidate(),
              decoration: const InputDecoration(labelText: '图像模型或部署端点'),
            ),
            if (widget.checkConnection != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: saving || checking ? null : testConnection,
                icon: const Icon(Icons.network_check),
                label: Text(checking ? '正在检查…' : '检查连接'),
              ),
              const Text('仅查询模型列表，不发送照片或生成请求。'),
            ],
            if (check != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(check!.message),
              ),
            if (check?.models.isNotEmpty == true)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: check!.models.contains(model.text)
                    ? model.text
                    : null,
                decoration: const InputDecoration(labelText: '服务返回的模型'),
                items: [
                  for (final name in check!.models)
                    DropdownMenuItem(
                      value: name,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => model.text = value);
                },
              ),
            const SizedBox(height: 20),
            Text('生成偏好', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('这些选项用于提出保留要求。模型仍可能改变人物或背景，生成后可在作品页与原图对比。'),
            dropdown('面部', face, const {
              'strict': '优先保留原貌',
              'natural': '允许自然光影过渡',
            }, (value) => setState(() => face = value)),
            dropdown('表情', expression, const {
              'preserve': '保留原始表情',
              'subtle': '允许轻微过渡',
            }, (value) => setState(() => expression = value)),
            dropdown('视线', gaze, const {
              'preserve': '保留原始视线',
              'follow-pose': '轻微顺应姿势',
            }, (value) => setState(() => gaze = value)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  saving || checking || widget.viewModel.loadError != null
                  ? null
                  : save,
              child: Text(saving ? '保存中…' : '保存设置'),
            ),
            const SizedBox(height: 12),
            const Text('清空密钥并保存后，新任务将无法生成。已提交任务沿用提交时的配置，可在任务页取消。'),
          ],
        ),
      ),
    ),
  );
  Widget dropdown(
    String label,
    String value,
    Map<String, String> values,
    ValueChanged<String> changed,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in values.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (value) {
        if (value != null) changed(value);
      },
    ),
  );
}
