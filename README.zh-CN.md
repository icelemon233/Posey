# Posey

[English](./README.md) | 简体中文

面向 Android 和 iOS 的姿势参考相机。找到喜欢的姿势，拍摄时对照构图；参考图只用于预览，不会出现在成片中。

## 可以做什么

- 按分类浏览姿势参考，搜索并收藏喜欢的姿势。
- 调整参考图透明度，按需要镜像显示。
- 使用相机控制、构图网格，或导入已有照片。
- 查看成片，保存到系统相册。
- 选择配置自己的服务，生成 AI 姿势图片。

## 从源码体验

准备 Flutter 3.47.7、Dart 3.13.5 和 Android 开发工具；运行 iOS 版本需要 macOS 和 Xcode。

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

相机与相册功能请使用实体手机体验，并在提示时授予所需权限。

## 可选的 AI 功能

在设置中填写受支持 AI 服务的 API Key、HTTPS 服务地址与图像模型。确认生成后，所选照片和参考图会发送到该服务，服务商可能按用量收费。

## 许可证

使用条款见 [LICENSE](./LICENSE)。
