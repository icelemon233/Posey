<p align="center"><img src="./docs/brand/exports/posey-app-icon/128.png" alt="Posey" width="96"></p>

<h1 align="center">Posey</h1>

<p align="center"><a href="./README.md">English</a> · 简体中文</p>

面向 Android 和 iOS 的姿势参考相机，并提供浏览器演示。

选择参考姿势，调整透明度或镜像显示，再对照构图拍照。保存的成片不会带上参考图。

- 按分类浏览、搜索姿势，收藏喜欢的参考。
- 使用相机控制和构图网格，或导入照片。
- 查看成片，保存到系统相册。

[打开网页演示](https://icelemon233.github.io/posey/)，体验姿势库、主题和相机界面。网页相机功能取决于浏览器支持和权限。

## 在手机上运行

需要 Flutter 3.47.7、Dart 3.13.5 和 Android 开发工具。构建 iOS 版本需要 macOS 和 Xcode。

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

相机与相册功能请在实体手机上体验，并按提示授予访问权限。

## 在浏览器中运行

需要 Node.js 22 或更新版本。在仓库根目录执行：

```sh
npm ci
npm run dev
```

打开 [localhost:4173](http://localhost:4173/)。Flutter 应用位于 `mobile/`，网页源码位于 `web/`。测试和生产构建见[网页开发说明](./web/README.zh-CN.md)。

## AI 姿势图片

手机端的 AI 生成为可选功能。在设置中填写受支持图像服务的 HTTPS 地址、模型和自己的 API Key。确认生成后，所选照片和参考图会发送到该服务，服务商可能按用量收费。

使用条款见 [LICENSE](./LICENSE)。
