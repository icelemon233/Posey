# Posey

自然一点，就很好看。Posey 使用 Flutter，同一套 Dart 代码构建 Android 和 iOS 姿势参考相机。

## 开发

使用 Flutter **3.47.7** / Dart **3.13.5**：

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
```

Windows 本机项目位于 `D:Projectsposey`，SDK 位于 `D:Developmentlutter`。iOS 构建需要 macOS/Xcode，CI 自动构建模拟器应用；Android CI 产出开发调试 APK。正式签名及商店发布需要另行配置。

## 功能

- 50 个原有原创模板（女生 27、男生 23），保留来源标记、姿势分类、搜索、收藏、随心拍范围及 7 个主题。
- 原生相机、前后镜头、闪光灯、缩放、构图网格、参考透明度/镜像与相册导入。参考图只覆盖预览，不写进拍摄成片。
- 成片缩放查看与保存到系统相册。
- AI Pose 使用原有图像生成协议和面部/表情/视线偏好；最多 3 个进行中任务、保留最近 20 张成片、取消/移除/重试。
- iOS 延续原来的 URLSession 后台任务管理，使用 Flutter MethodChannel 接入；Android 在前台处理，应用重启后把中断任务标记为失败，需手动重试。

## AI 配置与照片

在应用设置中填写自己的火山方舟 API Key、HTTPS 服务地址和图像模型。密钥保存在 iOS Keychain / Android 系统安全存储中，常规配置与任务 JSON 不保存密钥，源码及安装包不内置私人密钥。

只有你确认生成后，所选照片和参考图才会上传到配置的服务。模型可能按账户用量收费；取消请求无法撤回服务端已消耗的用量。移除任务清理应用副本，系统相册内已保存照片由用户管理。

## 结构与验证

`mobile/lib/` 为共享客户端；`mobile/android/` 和 `mobile/ios/` 为原生工程，应用 ID 延续 `com.posey.camera`。

`mobile/test/` 覆盖 50 张参考图加载、收藏搜索、队列并发上限、取消后的迟到结果、任务配置快照、重启后的显式重试、成片保留与文件清理边界、AI 协议响应。测试中的模拟 HTTP 不能替代真实 AI 或相机验收。CI 构建结果和真机待验证项见 [mobile/README.md](mobile/README.md)。

`research/`、`contracts/` 和研究工具保留。Node.js 可继续运行 `node scripts/build-pose-families.mjs` 等工具；既有研究证据是否齐全须按原门禁判断，不因框架迁移改写其结论。

## 旧版本

完整 React/Capacitor 版本与原生实现保存在 [archive/react-web-20261015](https://github.com/icelemon233/posey/tree/archive/react-web-20261015)。主分支产品入口为 `mobile/`。独立的 `Posey-web-demo` 仓库未修改；`docs/` 中的旧 MVP 记录保留为历史材料。
