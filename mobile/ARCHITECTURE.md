# Posey 手机端架构

Posey 使用 Flutter 3.47.7、Dart 3.13.5，同时提供 Android 和 iOS 应用。依赖由 `pubspec.lock` 锁定，继续使用 Flutter 的 `ChangeNotifier` 管理界面状态。

## 模块与依赖

- `lib/app/`：启动、依赖组装、导航和跨功能流程。`PoseyBootstrap` 处理设备存储打开失败，`PoseyDependencies` 并行加载各功能，`PoseyShell` 组合页面和照片流程。
- `lib/features/poses/`：姿势模型、资源读取、收藏持久化、搜索筛选和姿势详情。界面只读取 `PoseLibraryViewModel`，筛选结果按当前条件推导。
- `lib/features/settings/`：主题、随机范围、AI 配置和编辑表单。`SettingsRepository` 负责存储边界，`SettingsViewModel` 只在保存成功后更新已保存状态。
- `lib/features/camera/`：相机界面、会话状态和设备适配。`CameraGateway` / `CameraSession` 隔离插件，`CameraViewModel` 管理初始化、切换、缩放、拍摄和生命周期。
- `lib/features/photo_review/`：照片查看、保存和生成确认。`PhotoReviewViewModel` 通过明确的操作阶段阻止重复提交；导航与配置入口通过回调传入。
- `lib/features/ai_pose/`：生成配置、HTTP 协议、iOS 后台桥接、任务记录和任务界面。`AiJobRepository` 独立管理队列、取消、恢复、轮询和保留策略，`AiJobsViewModel` 提供页面操作。
- `lib/core/`：设备存储、相册适配、JSON 基础处理、共享主题与反馈。这里不导入业务页面。

界面依赖本功能的公开 ViewModel 和模型，数据访问由 Repository 或平台适配处理。跨功能协作在 `app/` 组装，例如为 AI 任务传入当前配置、姿势查找和照片访问能力。没有全局单例、服务定位器或额外状态管理框架。

## 状态与持久化

导航位置、弹窗和设置表单草稿属于界面；搜索条件属于姿势库 ViewModel；主题与已保存配置属于设置 ViewModel；任务事实来源为 `AiJobRepository`。页面不维护另一份任务缓存。

保留现有 `posey.flutter.*` 存储键和 JSON 格式，原有收藏、主题、AI 偏好与任务记录可以继续读取。收藏和设置写入按顺序执行，写入失败不会显示为保存成功。AI 配置同时涉及普通存储和安全存储，失败时尝试恢复原配置并明确报告错误。

API Key 继续使用系统安全存储；配置元数据、任务记录、构建参数和日志不保存密钥。照片副本位于应用私有目录，清理只作用于该目录，已经保存到系统相册的照片由用户管理。

每次 AI 提交冻结配置与偏好，要求用户确认，最多保留 3 个进行中的任务和最近 20 个成功结果。Android 中断任务等待显式重试；iOS 通过现有 URLSession 桥接同步后台结果，暂时同步失败有可重试提示。原生记录按目标标题恢复姿势关联。

AI 提交先保存本地任务和照片副本，保存成功后才允许执行；iOS 也使用已保存的同一个任务编号启动原生请求。提交保存失败不会留下可执行任务，执行状态保存失败会结束该任务并报告错误。已生成的结果遇到记录写入失败时仍保留在本机，任务页可重试保存，重试保存不会再调用 AI。历史裁剪和任务移除均在记录保存成功后删除照片副本。

重试任务通过可选的 `retryOf` 字段关联原任务，兼容没有该字段的旧记录。读取照片、准备请求和执行期间，同一原任务只能有一个进行中的重试。AI 记录损坏只影响 AI 功能，任务页显示恢复入口；重置需由用户确认，并先成功保存原始记录的本机恢复副本。备份失败时保留原记录。

iOS 同步时将本地进行中、但已不在原生队列的任务标记为中断，等待用户确认重试。正在提交的任务暂不参与这一判断，提交前的旧轮询响应也不能覆盖新任务。

相机初始化和缩放使用请求代次忽略旧结果。离开前台或销毁页面时释放会话；较晚到达的初始化、拍摄和生成结果不能更新已销毁的界面或创建多余成片。

相机会话的初始化与关闭按顺序执行，前台恢复需等待旧会话完全释放。照片查看页覆盖相机时释放会话，覆盖期间的前台事件不会重开相机，返回相机页且应用位于前台时才恢复预览。

## 验证

在 `mobile/` 中执行：

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug
flutter build apk --release
```

CI 使用相同的 Flutter 版本和锁文件，并构建 Android debug / release APK 与 iOS 未签名模拟器应用。Android release 产物沿用仓库的开发签名，仅用于预览；商店发布需要单独配置正式签名。测试覆盖姿势与收藏、持久化失败、任务容量和取消、冻结配置、相机生命周期及照片提交。模拟相机、HTTP 和相册仅验证边界行为；实际权限、拍摄、相册保存与后台恢复需要 Android/iPhone 真机验收。

实现依据：[Flutter 应用架构指南](https://docs.flutter.dev/app-architecture/guide)。
