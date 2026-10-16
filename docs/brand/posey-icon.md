# Posey 图标说明

## 设计目标

- App Icon 与 AI Pose 使用同一个核心符号，首页中间使用独立手写字标。
- 只使用抽象几何，不出现人物、人形、头部、手脚或人体剪影。
- 在 16–32 px 仍能分辨，并可转换为单色 Android 主题图标。

## 最终方向：取景框 × 手写体 P

符号由四个圆角取景框角与 Posey 手写字标的首字母 `P` 组成。外框表达拍摄与构图，内部手写笔势建立 Posey 的品牌识别；不描画具体人物，也不使用火柴人。

品牌色为深海蓝 `#2F6F91` 与暖珊瑚 `#F07A61`。App Icon 使用奶油与海盐浅色背景，外框使用深海蓝，手写体 `P` 使用暖珊瑚；两者采用一致线宽。

## 未采用方向

- 人物或火柴人：违反产品图标的明确限制，已从全部生产资产中移除。
- 独立四角取景框：缺少品牌识别，因此最终与 Posey 手写体 `P` 组合。
- 星光：容易被理解为通用修图工具。

## 尺寸适配

- 16、18、22、32 px：外框与 `P` 使用相同线宽，`P` 保持缩小后的独立留白。
- 128、512、1024 px：保持相同结构，以完整手写曲线和品牌双色呈现。
- iOS App Icon：使用 1024×1024 不预切圆角的全幅背景，由系统应用遮罩。

## 生产映射

- `public/brand/posey-mark.svg`：界面彩色标志。
- `public/brand/posey-mark-mono.svg`：单色源文件。
- `public/brand/posey-app-icon.svg`：1024 px App Icon 矢量源。
- `public/brand/posey-wordmark.png`：首页顶部透明手写字标。
- `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/`：iOS 图标。
- `mobile/android/app/src/main/res/`：Android 普通、圆形、自适应和单色图标。
- `docs/brand/exports/posey-mark/`：16、18、22、32、128、512 px 精确导出。
