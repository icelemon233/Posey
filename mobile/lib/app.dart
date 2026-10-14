import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_screen.dart';
import 'controller.dart';
import 'models.dart';
import 'services.dart';

const poseCategories = {
  'all': '全部',
  'standing': '站姿',
  'half': '半身',
  'seated': '坐姿',
  'crouching': '蹲跪',
};
const homeThemes = <String, (String, Color, Color)>{
  'sunny-cream': ('晴日奶油', Color(0xFFA9512F), Color(0xFFFFF6DB)),
  'sea-breeze': ('海风蓝', Color(0xFF366780), Color(0xFFEDF8FB)),
  'peach-sunset': ('蜜桃落日', Color(0xFFAC5361), Color(0xFFFFEEF0)),
  'lavender-evening': ('薰衣暮色', Color(0xFF67528E), Color(0xFFF3EFFC)),
  'mint-garden': ('薄荷花园', Color(0xFF33735A), Color(0xFFEAF8F0)),
  'sakura-mist': ('樱花薄雾', Color(0xFF9F587F), Color(0xFFFFF0F7)),
  'lemon-soda': ('柠檬汽水', Color(0xFF75803C), Color(0xFFF7F9DB)),
};
void showFailure(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.toString().replaceFirst(
            RegExp(r'^(Bad state: |FormatException: )'),
            '',
          ),
        ),
      ),
    );

class PoseyApp extends StatelessWidget {
  const PoseyApp({super.key, required this.controller});
  final PoseyController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final colors = homeThemes[controller.theme] ?? homeThemes['sunny-cream']!;
      return MaterialApp(
        title: 'Posey',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: colors.$2,
            surface: colors.$3,
          ),
          scaffoldBackgroundColor: colors.$3,
          appBarTheme: AppBarTheme(
            backgroundColor: colors.$3,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white.withValues(alpha: .8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        home: PoseyHome(controller: controller),
      );
    },
  );
}

class PoseyHome extends StatefulWidget {
  const PoseyHome({super.key, required this.controller});
  final PoseyController controller;
  @override
  State<PoseyHome> createState() => _PoseyHomeState();
}

class _PoseyHomeState extends State<PoseyHome> with WidgetsBindingObserver {
  int page = 0;
  String category = 'all', gender = 'all', query = '';
  final random = math.Random();
  PoseyController get controller => widget.controller;
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
    if (state == AppLifecycleState.resumed) controller.syncNative();
  }

  List<PoseTemplate> get filtered => controller.templates
      .where(
        (pose) =>
            pose.matches(query, gender, category) &&
            (page != 1 || controller.favorites.contains(pose.id)),
      )
      .toList();
  void openPose(PoseTemplate pose) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(pose.illustration, height: 260, fit: BoxFit.contain),
              Text(pose.title, style: Theme.of(sheet).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(pose.subtitle),
              const SizedBox(height: 12),
              Text(pose.tags.join(' · ')),
              const SizedBox(height: 12),
              const Text('跟着参考调整身体姿势，选择舒服自然的幅度。', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                objectOf(pose.raw['source'])['label'] as String? ??
                    'Posey 姿势参考',
                style: Theme.of(sheet).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (objectOf(pose.raw['source'])['evidenceStatus'] ==
                  'experimental')
                const Text('探索中的参考姿势，按身体感受调整。'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('open-camera'),
                      onPressed: () {
                        Navigator.pop(sheet);
                        openCamera(pose);
                      },
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('跟着拍'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheet);
                        importPhoto(pose);
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('导入照片'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  void openCamera(PoseTemplate pose) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PoseyCameraScreen(
        controller: controller,
        target: pose,
        onPhoto: (path, target) => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                PhotoReview(controller: controller, target: target, path: path),
          ),
        ),
      ),
    ),
  );
  Future<void> importPhoto(PoseTemplate pose) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (file == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PhotoReview(
            controller: controller,
            target: pose,
            path: file.path,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  void shuffle() {
    final choices = controller.shuffleFavorites
        ? filtered
              .where((pose) => controller.favorites.contains(pose.id))
              .toList()
        : filtered;
    if (choices.isEmpty) {
      showFailure(context, '当前范围没有姿势，调整筛选或先收藏几个喜欢的姿势。');
      return;
    }
    openPose(choices[random.nextInt(choices.length)]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
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
            : Text(['', '我的收藏', 'AI Pose', '设置'][page]),
        actions: page < 2
            ? [
                IconButton(
                  onPressed: shuffle,
                  tooltip: '随心拍',
                  icon: const Icon(Icons.shuffle),
                ),
              ]
            : null,
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(controller.error!),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: controller.initialize,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            )
          : switch (page) {
              0 || 1 => library(),
              2 => JobList(controller: controller),
              _ => SettingsScreen(controller: controller),
            },
      bottomNavigationBar: NavigationBar(
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
          NavigationDestination(
            icon: Badge(
              isLabelVisible: controller.activeJobs > 0,
              label: Text('${controller.activeJobs}'),
              child: const Icon(Icons.auto_awesome_outlined),
            ),
            label: 'AI Pose',
          ),
          const NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
        ],
      ),
    ),
  );
  Widget library() => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (page == 0) ...[
                Text(
                  '自然一点，就很好看。',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('选一个喜欢的姿势，让每一次拍照都有灵感。'),
                const SizedBox(height: 20),
              ],
              TextField(
                key: const Key('pose-search'),
                decoration: const InputDecoration(
                  hintText: '搜索站姿、旅行、手部…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('全部')),
                  ButtonSegment(value: 'female', label: Text('女生')),
                  ButtonSegment(value: 'male', label: Text('男生')),
                ],
                selected: {gender},
                onSelectionChanged: (values) =>
                    setState(() => gender = values.first),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: poseCategories.entries
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: category == entry.key,
                            onSelected: (_) =>
                                setState(() => category = entry.key),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${filtered.length} 个姿势',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
      if (filtered.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('还没有匹配的姿势。')),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.crossAxisExtent > 650 ? 3 : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: .67,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final pose = filtered[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openPose(pose),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(
                                color: Color(pose.accent).withValues(alpha: .2),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Image.asset(
                                    pose.illustration,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  key: Key('favorite-${pose.id}'),
                                  tooltip: '收藏${pose.title}',
                                  onPressed: () =>
                                      controller.toggleFavorite(pose.id),
                                  icon: Icon(
                                    controller.favorites.contains(pose.id)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pose.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pose.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ],
  );
}

class PhotoReview extends StatefulWidget {
  const PhotoReview({
    super.key,
    required this.controller,
    required this.target,
    required this.path,
    this.generated = false,
  });
  final PoseyController controller;
  final PoseTemplate target;
  final String path;
  final bool generated;
  @override
  State<PhotoReview> createState() => _PhotoReviewState();
}

class _PhotoReviewState extends State<PhotoReview> {
  bool busy = false, saved = false;
  Future<void> save() async {
    setState(() => busy = true);
    try {
      await const GalleryService().save(widget.path);
      if (mounted) setState(() => saved = true);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> generate() async {
    if (widget.controller.configuration.normalizedKey.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AiSettingsScreen(controller: widget.controller),
        ),
      );
      if (!mounted || widget.controller.configuration.normalizedKey.isEmpty) {
        return;
      }
    }
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用 AI Pose 调整姿势'),
        content: Text(
          '这张照片和“${widget.target.title}”参考图将发送到你在设置中配置的 AI 服务（${widget.controller.configuration.uri.host}）。'
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
    if (agreed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.controller.enqueue(
        widget.target,
        await File(widget.path).readAsBytes(),
        consent: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入 AI Pose，结果可在任务页查看。')));
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.generated ? 'AI Pose 成片' : '这一次，很自然')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.file(
                File(widget.path),
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
                Text('参考姿势 · ${widget.target.title}'),
                const SizedBox(height: 16),
                if (busy) const LinearProgressIndicator(),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : save,
                        icon: Icon(
                          saved ? Icons.check : Icons.download_outlined,
                        ),
                        label: Text(saved ? '已保存到相册' : '保存到相册'),
                      ),
                    ),
                    if (!widget.generated) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : generate,
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
  );
}

class JobList extends StatelessWidget {
  const JobList({super.key, required this.controller});
  final PoseyController controller;
  Future<void> run(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      if (context.mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${controller.activeJobs} / 3 个进行中的任务',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          controller.native.supported
              ? 'iOS 可继续处理后台任务；完成后返回这里查看。'
              : '生成时请保持应用打开。中断的任务需要你确认重试。',
        ),
        const SizedBox(height: 8),
        const Text('保留最近 20 张成片，喜欢的照片记得保存到相册。'),
        const SizedBox(height: 20),
        if (controller.jobs.isEmpty)
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
        ...controller.jobs.map(
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
                            run(context, () => controller.clear(job.id)),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (job.resultPath != null)
                    InkWell(
                      onTap: () {
                        final targets = controller.templates.where(
                          (pose) => pose.id == job.targetId,
                        );
                        if (targets.isEmpty) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PhotoReview(
                              controller: controller,
                              target: targets.first,
                              path: job.resultPath!,
                              generated: true,
                            ),
                          ),
                        );
                      },
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
                          run(context, () => controller.cancel(job.id)),
                      child: const Text('取消生成'),
                    ),
                  if ((job.state == AiJobState.failed ||
                          job.state == AiJobState.cancelled) &&
                      job.sourcePath.isNotEmpty)
                    TextButton(
                      onPressed: controller.activeJobs >= 3
                          ? null
                          : () => run(context, () => controller.retry(job)),
                      child: const Text('重新生成'),
                    ),
                  if (job.resultPath != null)
                    TextButton.icon(
                      onPressed: () => run(context, () async {
                        await const GalleryService().save(job.resultPath!);
                        if (context.mounted) {
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final PoseyController controller;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('让 Posey 更像你', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      Card(
        child: ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('AI Pose 设置'),
          subtitle: Text(
            controller.configuration.normalizedKey.isEmpty
                ? '连接你的火山方舟账户'
                : '已保存设备密钥',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AiSettingsScreen(controller: controller),
            ),
          ),
        ),
      ),
      Card(
        child: SwitchListTile(
          title: const Text('随心拍只从收藏中选'),
          subtitle: const Text('仍遵循当前的性别与姿势筛选'),
          value: controller.shuffleFavorites,
          onChanged: controller.setShuffleFavorites,
        ),
      ),
      const SizedBox(height: 16),
      Text('首页主题', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      RadioGroup<String>(
        groupValue: homeThemes.containsKey(controller.theme)
            ? controller.theme
            : 'sunny-cream',
        onChanged: (value) {
          if (value != null) controller.setTheme(value);
        },
        child: Column(
          children: homeThemes.entries
              .map(
                (entry) => Card(
                  child: RadioListTile<String>(
                    title: Text(entry.value.$1),
                    secondary: CircleAvatar(
                      backgroundColor: entry.value.$2,
                      radius: 12,
                    ),
                    value: entry.key,
                  ),
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 20),
      const Text('关于 Posey', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('50 个原创姿势参考。使用相机叠加参考图，或用 AI Pose 调整已有照片。参考图不会出现在你拍摄的成片里。'),
      const SizedBox(height: 16),
      const Text('照片与隐私', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text(
        '拍摄、收藏和参考图在本机处理。只有你确认 AI 生成后，选中的照片才会发送到配置的服务。API Key 保存在此设备的系统安全存储中。'
        '移除任务只清理应用中的副本，已保存到系统相册的照片由你管理。',
      ),
      const SizedBox(height: 20),
      const Text('Posey · Flutter 0.2.0', textAlign: TextAlign.center),
    ],
  );
}

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, required this.controller});
  final PoseyController controller;
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final keyInput = TextEditingController(
    text: widget.controller.configuration.key,
  );
  late final endpoint = TextEditingController(
    text: widget.controller.configuration.endpoint,
  );
  late final model = TextEditingController(
    text: widget.controller.configuration.model,
  );
  late String face = widget.controller.preferences.face,
      expression = widget.controller.preferences.expression,
      gaze = widget.controller.preferences.gaze;
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
      await widget.controller.saveConfiguration(
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
