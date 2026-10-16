import 'package:flutter/material.dart';
import 'package:posey/core/ui/feedback.dart';
import 'package:posey/features/settings/settings_view_model.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, required this.viewModel});
  final SettingsViewModel viewModel;
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
  bool busy = false, visible = false;
  @override
  void dispose() {
    keyInput.dispose();
    endpoint.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.viewModel.saveConfiguration(
        AiConfiguration(
          key: keyInput.text,
          endpoint: endpoint.text.trim(),
          model: model.text.trim(),
        ),
        AiPreferences(face: face, expression: expression, gaze: gaze),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Pose 设置')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('使用你自己的火山方舟密钥。清空密钥并保存即可从设备移除。'),
        const SizedBox(height: 20),
        TextField(
          key: const Key('ai-api-key'),
          controller: keyInput,
          obscureText: !visible,
          autocorrect: false,
          enableSuggestions: false,
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
          decoration: const InputDecoration(
            labelText: '服务地址',
            helperText: 'HTTPS 地址，以 /api/v3 结尾',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: model,
          decoration: const InputDecoration(labelText: '图像模型'),
        ),
        const SizedBox(height: 24),
        Text('保留你的样子', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        dropdown('面部保真', face, const {
          'strict': '严格保留',
          'natural': '允许自然光影过渡',
        }, (value) => setState(() => face = value)),
        dropdown('表情', expression, const {
          'preserve': '保持原始表情',
          'subtle': '允许极轻微过渡',
        }, (value) => setState(() => expression = value)),
        dropdown('视线', gaze, const {
          'preserve': '保持原始视线',
          'follow-pose': '轻微顺应姿势',
        }, (value) => setState(() => gaze = value)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? '保存中…' : '保存设置'),
        ),
      ],
    ),
  );
  Widget dropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map(
            (entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) change(value);
      },
    ),
  );
}
