# Posey

Posey 是一个移动端姿势参考相机。先从姿势库选择喜欢的线稿，再打开相机照着调整并手动拍摄；也可以上传人物照片，用 AI Pose 生成目标姿势。

## 当前功能

- 按女生 / 男生和站姿 / 半身 / 坐姿 / 蹲跪浏览内置姿势。
- 收藏姿势，并在独立收藏页查看。
- “随心拍”从全部或收藏中随机选择姿势。
- 相机页显示静态参考线稿，支持左右镜像和手动快门。
- 支持上传照片后使用 AI Pose。
- AI Pose 在发送前明确确认，生成中可以取消，结果会标明为 AI 生成。
- 首页主题、随心拍范围、产品说明和隐私说明集中在设置弹层。

Posey 不再包含实时姿势检测、动作匹配、语音提醒、自动拍摄、画面质量门槛、体验演示或从参考图生成姿势模板。

## AI Pose 与安全

普通拍照不会上传相机预览或照片。只有用户确认使用 AI Pose 后，当前画面或上传照片以及目标姿势图才会发送给火山方舟的豆包图片模型，用于本次生成。

AI 结果可能改变人物、服装或画面细节。拍摄时应留意脚下、车辆和周围障碍物，不要在道路、临边、水域等危险位置只看屏幕摆姿势。

### 火山方舟配置

长效 API Key 保存在项目根目录的 `doubao-api-key.txt`（已被 Git 忽略），内容可为纯 Key 或 `ARK_API_KEY=你的Key`。构建时 Vite 会把 Key 注入 App，图片生成接口使用模型 ID `doubao-seedream-5-0-pro-260628`。

直接接入意味着 API Key 会存在于编译后的 IPA / APK 中，能够被安装包分析工具提取。该方案只适合个人测试包；公开发布前应改为受控服务端代理，并设置额度和调用监控。

## 本地运行

```bash
npm install
npm run dev
```

验证与原生同步：

```bash
npm test
npm run build
npm run cap:sync
npm run android:debug
npm run ios:simulator
```

Android Debug APK 输出到 `android/app/build/outputs/apk/debug/app-debug.apk`。iOS 工程位于 `ios/App/App.xcworkspace`。

## 素材边界

`research/xiaohongshu/screenshots/` 只保存内部调研证据，不会进入发布资源。App 内置卡片使用 Posey 原创动漫姿势图与抽象骨架。
