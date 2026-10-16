# Posey 网页版

[English](./README.md) | 简体中文

Posey 的浏览器演示，提供姿势库、主题、相机界面和可选的 AI 姿势生成功能。

[打开网页演示](https://icelemon233.github.io/posey/)

需要 Node.js 22 或更新版本。在仓库根目录执行：

```sh
npm ci
npm run dev
```

打开 [localhost:4173](http://localhost:4173/)。相机访问需要 localhost 或 HTTPS，并获得浏览器权限。

## 测试与构建

```sh
npm run test:web
npm run build:web
npm run preview:web
```

构建产物位于 `web/dist/`。部署到子路径时，构建前设置 `POSEY_PUBLIC_BASE`；GitHub Actions 使用 Pages 的 `/posey/` 路径。工作流会检查拉取请求，并将 `main` 发布到 GitHub Pages。

AI 生成使用你在设置中填写的服务和 API Key。网页构建不会内置服务凭据。

网页源码与 `../mobile/` 中的 Flutter 应用在同一仓库维护。使用条款见 [LICENSE](../LICENSE)。
