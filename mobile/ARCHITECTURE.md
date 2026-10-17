# Posey 手机端架构

本项目属于 Cinna 系列。产品名称为 Posey，开发者为 Cinna。使用 Flutter 3.47.7、Dart 3.13.5 和原有 ChangeNotifier 状态方案；依赖由 `pubspec.lock` 锁定。

## 模块边界

- `lib/app` 组装依赖、路由、导入恢复、通知入口和跨功能数据操作。
- `features/poses` 管理内置参考、自有参考、收藏、最近使用及两套独立筛选。
- `features/camera` 通过 `CameraGateway` 隔离插件，管理会话、倒计时、对焦、缩放和参考变换。
- `features/photo_review` 管理查看、生成确认和副本编辑。图像变换在计算 isolate 中执行，连续编辑合并到最新草稿。
- `features/works` 留存照片与参考快照，管理原图关联、相册标记、批量删除与分享。
- `features/ai_pose` 管理冻结请求、队列、结果恢复、任务历史与公开错误。
- `features/settings` 管理已保存设置与表单草稿；`features/backup` 校验、导出和合并备份。
- `lib/core` 提供存储、平台桥接、媒体与通用 UI，不导入业务页面。

页面调用功能命令。插件、存储和网络协议集中在适配或数据层。相同功能共享必要加载任务，写入按冲突范围串行；晚到的结果不能更新已销毁页面。相机会话关闭完成后才进入照片查看或重新打开镜头。

## 数据与恢复

沿用 `posey.flutter.*`、安全存储键、生产 Android 应用 ID 与 iOS Bundle ID。作品、自有参考和任务分别持久化；私有媒体通过稳定文件名处理应用容器迁移。收藏、设置、作品或任务损坏时暂停对应写入，其他功能继续使用。显式恢复先保存原始记录的本机恢复副本；备份失败不能覆盖原记录。

作品保留原图与参考快照。删除作品先提交新列表，再按所有作品、参考、任务和恢复记录清理文件。任务清理保留未留存成片。系统相册属于外部存储；相册写入成功但本机标记失败时，同次运行重试只保存标记。跨重启无法保证系统相册的外部写入恰好一次。

未完成导入使用 `pending-import-v1` 恢复，不允许新导入覆盖。Android 进程回收后的图片选择结果由 image_picker 的 lost-data 接口接回。无法读取的导入记录可以先备份再清除。

备份使用有版本的 ZIP 清单和媒体别名，排除私有绝对路径、AI 配置、API Key 和任务凭据。导入检查大小、文件数量、路径、重复项、链接、CRC、图片格式、类型与内置资源引用；完整验证后按稳定编号合并。多记录写入保留回滚日志，启动时先恢复未完成事务。备份未加密。

## AI 与平台

每次提交先取得同意并保存本地任务，再启动生成。配置、姿势镜像与原图在同意时冻结；最多 3 个进行中的任务。最近 20 个成功任务保留临时副本，作品独立留存；留存失败的成片不自动裁掉。

Android 在前台提交后启动原生 dataSync 前台服务，使用顺序队列、通知和有时限的唤醒锁。凭据及临时下载地址由 Android Keystore 加密。iOS 使用后台 URLSession 上传和下载，结果地址保存在 Keychain。两端都保留任务元数据与源图，逐张读取成片，不通过历史列表传输全部图片。

进程中断后先核对持久化结果与系统任务；应用不会自动重新提交一个可能已处理的生成请求。结果写入失败保留内存成片，下载失败保留安全存储中的下载地址；重试结果只写文件或执行下载。内存成片在进程终止后可能丢失，服务端也可能使下载地址过期。用户明确取消只停止本机等待、连接与下载，不能保证撤销服务端处理或费用。

系统分享和文件导入导出使用原生界面。Android 分享通过只读 ContentProvider 授权；iOS 使用系统活动与文件选择器。通知入口在当前拍摄、编辑或备份操作结束后再打开结果。

## 构建与检查

在 `mobile/` 执行：

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug --flavor preview --no-pub
flutter build apk --release --flavor production --no-pub
flutter build apk --release --flavor preview --no-pub
# macOS:
flutter build ios --simulator --debug --no-codesign --no-pub
```

Release 默认未签名。生产 ID 为 `com.posey.camera`，可并存测试包为 `com.posey.camera.preview`。测试包使用独立且持续保留的签名；旧 CI Debug 签名的私钥不在仓库中，无法据此给旧安装签发覆盖更新。签名与产物核对见 [VERIFICATION.md](VERIFICATION.md)。

仓库研究工具独立于手机运行时：`npm run verify:research` 检查结构；`npm run verify:research-evidence` 结合 `POSEY_RESEARCH_EVIDENCE_DIR` 检查私人证据文件是否存在，不代表内容与使用权已复核。

相机、HTTP、相册和原生桥接替身测试只验证相应边界行为。真实权限、镜头、系统文件界面、付费 AI、锁屏与设备后台限制需要真机验收。实现参考 [Flutter 应用架构指南](https://docs.flutter.dev/app-architecture/guide)。
