# Posey Flutter

共享实现与配置说明见 [项目说明](../README.md)。执行 `flutter pub get --enforce-lockfile`、`flutter analyze`、`flutter test`，再 `flutter run`。

`.github/workflows/mobile.yml` 构建 Android 开发调试 APK、iOS 未签名模拟器应用；两端共用 Dart 业务与界面，iOS 的后台 URLSession 管理器位于 `ios/Runner/AppDelegate.swift`。

测试数据的手机界面渲染可通过 `VISUAL_REVIEW_DIR` 运行 `test/visual_review_test.dart` 导出。没有真实 API Key 与用户照片时，真实 AI 生成记为未运行。物理相机、系统授权、真机保存、切换后台和系统终止后的恢复，需要 Android/iPhone 设备验收；编译成功或模拟 HTTP 测试不能替代这些验证。

通过设置页保存自己的 AI Key，安装包不含私人密钥。保存到系统相册的成片不会随应用内任务记录删除。
