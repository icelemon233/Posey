<p align="center"><img src="./docs/brand/cinna-app-icon.png" alt="Posey 图标" width="128"></p>

<h1 align="center">Posey</h1>

<p align="center"><a href="./README.md">English</a> · 简体中文</p>

面向 Android 和 iOS 的姿势参考相机，界面使用中文。

从 50 个插画参考中选姿势，或导入自己的参考图。按照动作步骤调整姿势，移动、缩放或镜像参考后构图拍照。保存的照片不会带上参考图。

- 按姿势、场景和道具搜索，查看收藏与最近使用的参考。
- 使用点按对焦、缩放、构图网格和手动倒计时，或导入照片。
- 在作品中保留照片、编辑副本、对比原图、分享和保存到系统相册。
- 导出本机备份，校验后合并导入；备份不包含 API Key 与 AI 任务凭据。
- 切换浅色、深色或跟随系统外观。

## Android 试用

[下载 Android 测试包](https://github.com/icelemon233/Posey/releases/tag/v0.3.0-preview.1)。

测试包与旧版 Posey 分开安装，保留旧版及其数据。后续测试包沿用同一签名。相机、相册和后台行为仍需在你的手机上体验；自动检查与平台构建记录见[手机端验证](./mobile/VERIFICATION.md)。

## AI 姿势图片

AI 生成为可选功能。在设置中填写自己的 API Key、HTTPS 服务地址，以及火山方舟或兼容服务的图像模型。连接检查只查询模型列表，不上传照片。

每次生成前都会请求确认，再发送所选照片和参考图，服务商可能按用量收费。任务保留提交时的配置；生成中断后需确认才能重试。下载或保存已有成片不会再次提交生成。Android 使用前台服务，iOS 使用后台传输，两者均受系统限制。

## 从源码运行

需要 Flutter 3.47.7、Dart 3.13.5 和 Android 开发工具。iOS 需要 macOS 与 Xcode。

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run --flavor preview # Android
# iOS 使用 flutter run
```

按提示授予相机与照片访问权限。备份包含照片且未加密，请保存在私人位置。

[架构与构建检查](./mobile/ARCHITECTURE.md) · [使用条款](./LICENSE)

开发者：Cinna。
