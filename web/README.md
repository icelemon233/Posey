# Posey Web

English | [简体中文](./README.zh-CN.md)

The browser demo of Posey's pose library, themes, camera interface, and AI Pose flow.

[Open the demo](https://icelemon233.github.io/posey/)

Use Node.js 22 or later. Run these commands from the repository root:

```sh
npm ci
npm run dev
```

Open [localhost:4173](http://localhost:4173/). Camera access needs localhost or HTTPS and browser permission.

## Test and build

```sh
npm run test:web
npm run build:web
npm run preview:web
```

The build is written to `web/dist/`. Set `POSEY_PUBLIC_BASE` to the hosting subpath when building; GitHub Actions uses `/posey/` for Pages. The workflow tests pull requests and publishes `main` to GitHub Pages.

The public demo shows the AI Pose interface without generating images. Provider credentials are never bundled in the browser build. For AI generation, run the Flutter app and configure your own service and API key in Settings.

The web source is maintained here alongside the Flutter app in `../mobile/`. Usage terms are in [LICENSE](../LICENSE).
