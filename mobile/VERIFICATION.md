# Posey 0.3.0 验证与安装

本轮修复范围见 [COMPLETION.md](COMPLETION.md)，实现与数据边界见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 自动检查

- Flutter / Dart 格式与静态分析。
- 63 项行为和边界测试：拍摄生命周期、倒计时、共同视口、冻结同意快照、任务并发与取消、结果下载 / 保存恢复、作品重开与删除、相册标记失败、自有参考编辑、独立筛选、导入保护、备份合并与事务回滚。
- 36 张 Flutter Widget 渲染：浅色 / 深色，390 × 844 常规字号、320 × 568 的 1.7 倍字号。照片样本和相机预览为合成测试资料；这些是共享界面的渲染检查。
- Android Preview Debug、Production / Preview 未签名 Release，以及 iOS 未签名模拟器构建，运行于 [GitHub Actions](https://github.com/icelemon233/Posey/actions/workflows/mobile.yml)。最终安装包采用发布记录中对应提交的成功构建。
- 研究结构校验；私人研究截图未在本轮核对。结构数字为 2195 篇去重候选、291 条深读、194 个家族、7 个来源准入家族和 6 个参数化草案，不能视作真机标定结论。

默认测试命令跳过两个需要本地字体和输出目录的视觉任务。运行完整视觉矩阵时设置 `VISUAL_REVIEW_DIR`、`REVIEW_FONT` 与 `REVIEW_ICONS`，再执行 `flutter test test/visual_workflows_test.dart`。既有视觉任务可单独运行。

## Android 安装与签名

可安装测试包使用 `com.posey.camera.preview`，显示名为 Posey，与旧版分开保存资料。生产构建继续使用 `com.posey.camera`。旧安装不必卸载；两个应用之间的数据不会自动共享。

测试包使用持续保留的专用签名，公钥证书位于 `android/preview-signing-certificate.pem`。私钥与密码不进入仓库、CI 构建或发布资产。后续 Preview 更新需沿用此私钥；旧 CI Debug 包的临时私钥不能由公钥或 APK 恢复。

构建默认输出未签名 Release。维护者可用 Android Build Tools 的 `zipalign` 和 `apksigner`，或运行 `tool/sign-preview.ps1`。脚本通过进程环境变量 `POSEY_SIGN_PASSWORD` 读取密码，核对 Preview 包名，执行 16 KB 页对齐、签名和验签，不允许意外覆盖输出。

每次交付核对包名、版本、ABI、资源、对齐和签名。发布资产的 `receipt.json` 记录源码提交、CI run、输入文件与最终 APK 的 SHA-256，以及签名证书指纹。下载安装包应与该记录对应。

## 真机验收边界

本轮没有连接物理手机，也没有使用真实密钥调用付费图像服务或上传用户照片。以下内容仍由实际手机体验验证：相机权限与镜头行为、系统相册与分享、原生文件选择、锁屏和厂商后台限制、真实图像服务权限及生成质量。

iOS CI 产物为模拟器应用，不是可安装到 iPhone 的 IPA。正式 iPhone 分发仍需对应 Apple 证书与配置。
