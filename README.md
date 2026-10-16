<p align="center"><img src="./docs/brand/exports/posey-app-icon/128.png" alt="Posey" width="96"></p>

<h1 align="center">Posey</h1>

<p align="center">English · <a href="./README.zh-CN.md">简体中文</a></p>

A pose-reference camera for Android and iOS, with a browser demo.

Choose a reference, adjust its transparency or mirror it, and use it to frame your photo. The reference stays out of the saved shot.

- Browse categories, search for poses, and save favorites.
- Use camera controls and a composition grid, or import a photo.
- Review shots and save them to the system gallery.

[Try the browser demo](https://icelemon233.github.io/posey/). Browse poses, themes, and the camera interface. Browser camera features depend on support and permissions.

## Run on a phone

Use Flutter 3.47.7 and Dart 3.13.5 with Android tooling. iOS builds require macOS and Xcode.

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

Use a physical phone for camera and gallery features. Grant access when the app requests it.

## Run in a browser

Use Node.js 22 or later. From the repository root:

```sh
npm ci
npm run dev
```

Open [localhost:4173](http://localhost:4173/). The Flutter app is in `mobile/`; the browser source is in `web/`. See the [web development guide](./web/README.md) for testing and production builds.

## AI pose images

AI generation is optional in the mobile app. Configure a supported image service, HTTPS address, model, and your own API key in Settings. Confirming a generation sends the selected photo and reference to that service; provider charges may apply.

Usage terms are in [LICENSE](./LICENSE).
