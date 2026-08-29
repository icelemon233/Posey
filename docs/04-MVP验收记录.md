# Posey MVP 实际验收记录（历史版本）

> 本文是早期版本的验收存档，不代表当前产品功能。当前产品已移除姿势检测、语音提醒、自动拍摄和体验演示。

首次验收日期：2026-08-17。交付收口日期：2026-08-24。

## 已通过

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 调研证据 | 收口通过 | 2194 篇去重候选、290 篇逐帖深读、194 个家族；`npm run verify:research` 验证 6 个来源准入家族。3000 / 800 长期扩量目标不再阻塞本次交付 |
| 姿势库 | 通过 | 6 个来源准入家族已用 Posey 原创抽象骨架接入默认库，全部标记 `supported` |
| 参考图参数化 | 草案通过 | 六个家族均保存完整 33 点、闭合轮廓、关键关系和三档容差，状态保持 `needs-review`；未宣称真机标定通过 |
| 实时匹配 | 通过 | 比例归一化、关节位置、肢体方向、关键关系、低置信度关节退出匹配 |
| 简单提示 | 通过 | 页面实测“右手再高一点”；不显示角度、厘米、顺逆时针或姿势分数 |
| 白 / 黄 / 绿 | 通过 | 演示序列从差距较大逐步过渡到绿色，局部箭头指向目标位置 |
| 手动拍摄 | 通过 | 白色状态下快门可按，进入结果页，无阻断弹窗 |
| 姿势触发自动拍摄 | 通过 | Web 生产构建与 iOS Debug 原生壳均在绿色稳定 600 ms 后自动进入结果页 |
| 完整质量门槛 | 生产实现通过 | 已实现景别裁切、排除人物框的背景帧差抖动、脸部亮度 / 黑位 / 细节分析，以及新鲜度与 600 ms 组合门槛；阈值未做真人 / 真机标定 |
| 离线核心资源 | 通过 | 5.5 MB Pose Landmarker 模型与三套 WASM 资源位于 `public/` 并进入移动端资源包 |
| 单元测试 | 通过 | `npm test`：31 / 31；匹配器 18 项、质量门槛 9 项、完整页面流程 4 项 |
| Web 生产构建 | 通过 | `npm run build` |
| Android 原生构建 | 通过 | `:app:assembleDebug`，APK 约 20 MB |
| iOS 原生依赖 | 通过 | Xcode 工程生成，`pod install` 成功 |
| iOS 模拟器构建 | 通过 | 当前脚本使用 Xcode 26.1.1 与 iOS 26.1 SDK / runtime |
| iOS 本地运行 | 通过 | iPhone 17 Pro / iOS 26.1 模拟器；最终流程截图位于 `docs/screenshots/ios26-*` |
| iOS 真机连接环境 | 通过 | iPhone 17 / iOS 26.6 当前有线连接、已配对且开发者模式开启；这里只证明调试环境可用，不等于三项质量门槛通过 |
| 最终页面回归 | 通过 | 390 × 844 视口；姿势库 → 调整提示 → 自动 / 手动拍照 → 结果页；应用控制台 0 error |

## iOS 本地调试结果

- 项目使用 `Xcode_26.1.1/Xcode.app`（Xcode 26.1.1，Build 17B100），通过 `DEVELOPER_DIR` 指向项目内 Xcode，不修改系统全局选择。
- 当前仅保留 iOS 26.1 runtime；`Posey iPhone 17 Pro` 模拟器已启动，UDID 为 `F61D4E3D-9A81-4812-BEEC-14001B5C5500`。
- `scripts/ios-simulator.sh` 已默认指向 Xcode 26.1.1、iOS 26.1 和 Posey iPhone 17 Pro，不再依赖 iOS 18 资源。
- 2026-08-18 通过 `devicectl` 复核到真机“初夏甜橙”：iPhone 17 / iOS 26.6，有线连接、已配对、Developer Mode enabled。
- Debug 构建提供 `-PoseyDebug` 状态入口，只用于稳定复现页面流程，不进入 Release 行为。演示入口和模拟器截图不能替代真实相机质量验收。

## 尚未完成的真机边界

- 三项质量门槛已有生产分析器和组合门槛，但阈值仍是工程初值；按本轮交付范围不做真人 / 真机标定，因此没有误判率结论。算法和验收边界见 [`05-画面质量门槛.md`](05-画面质量门槛.md)。

- iOS 真机虽然已连接，但 20 分钟发热、后台恢复、不同真实人物通过率和质量门槛误判率仍需逐项验收；“设备可连接”不能替代这些结论。
- iOS Simulator 没有真实后置相机，因此模拟器验收的是原生壳、页面状态机、匹配演示和姿势触发快门；MediaPipe 对真人、真实曝光和抖动门槛仍须真机验证。
- Chrome 扩展未开启“Allow access to file URLs”，导致自动化无法把本地参考图送入文件选择器；图片推理代码、模型文件和 UI 流程已经构建通过，但这一项未冒充真实上传验收。

## 调研证据审计

- 290 篇深读记录均为不同 note id；候选池按 note id 去重为 2194 篇。曝光、标题和搜索卡片不作为单独准入证据。
- 评论区只记录当时页面可见片段；93551 是 177 篇帖子的页面评论计数之和，不是逐条阅读量，也不是对姿势的支持票。
- [`template-evidence.json`](../research/xiaohongshu/template-evidence.json) 将当前六个准入模板映射到合格 note id 与截图，六者均为 `supported`；截图只用于研究证据。
- [`pose-families.json`](../research/xiaohongshu/pose-families.json) 记录 194 个家族，其中 6 个来源准入、84 个仍缺证据、104 个只有排除证据。`standing-look-back-one-hand-pocket` 已达到 5 帖 / 5 位稳定创作者。
- 六个参数化草案见 [`research/pose-parameterizations`](../research/pose-parameterizations)。它们只使用 Posey 自有抽象骨架，研究校验器检查 33 点、产品使用权、闭合轮廓、关键关系、三档容差和 `needs-review` 状态。
- [`next-deep-read-queue.json`](../research/xiaohongshu/next-deep-read-queue.json) 当前为 20 篇、覆盖 2 个近准入家族；本轮不再扩量。
- 所以本轮能支持“绿色代表接近所选参考”，不能支持“绿色代表好看”。

## 截图

- `docs/screenshots/mvp-library.png`：姿势库。
- `docs/screenshots/mvp-camera-adjust.png`：白色轮廓和一句动作提示。
- `docs/screenshots/mvp-camera-green.png`：绿色达到状态与手动模式。
- `docs/screenshots/mvp-result.png`：自动 / 手动拍摄结果页。
- `docs/screenshots/ios-library.png`：iPhone 16 模拟器姿势库首屏。
- `docs/screenshots/ios-library-bottom.png`：6 个模板、实验模板“试用”标记和隐私说明。
- `docs/screenshots/ios-camera-adjust.png`：iOS 手动模式白色轮廓与“右手再高一点”。
- `docs/screenshots/ios-camera-green.png`：同一原生流程达到绿色并保留手动快门。
- `docs/screenshots/ios-result-auto.png`：自动模式绿色稳定后进入结果页。
- `docs/ios-simulator.log`：模拟器原生日志；未见 App crash 或 JS fatal，出现的 TTS asset 查询失败是 Simulator 语音资源噪声。

## 本轮明确排除的真机工作

1. 先用 10 组不同身高、衣着与模板的视频校准三档阈值，记录首次变绿耗时和错误变绿率。
2. 长裙或桌面遮挡时检查膝、踝置信度，确认灰色关节不会阻塞自动快门。
3. 分别在 iPhone 与中端 Android 连续运行 20 分钟；若发热，先把检测频率从约 11 fps 降到 8 fps。
4. 收集用户没有一次听懂的话术，直接替换为“身体部位 + 上下 / 里外”，不增加专业解释。
