<p align="center"><img src="./docs/brand/cinna-app-icon.png" alt="Posey Cinna icon" width="128"></p>

<h1 align="center">Posey</h1>

<p align="center">English · <a href="./README.zh-CN.md">简体中文</a></p>

A pose-reference camera for Android and iOS.

Choose a reference, adjust its transparency or mirror it, and use it to frame your photo. The reference stays out of the saved shot.

- Browse categories, search for poses, and save favorites.
- Use camera controls and a composition grid, or import a photo.
- Review shots and save them to the system gallery.

## Run on a phone

Use Flutter 3.47.7 and Dart 3.13.5 with Android tooling. iOS builds require macOS and Xcode.

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

Use a physical phone for camera and gallery features. Grant access when the app requests it.

## AI pose images

AI generation is optional. Configure a supported image service, HTTPS address, model, and your own API key in Settings. Confirming a generation sends the selected photo and reference to that service; provider charges may apply.

Usage terms are in [LICENSE](./LICENSE).
