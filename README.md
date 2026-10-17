<p align="center"><img src="./docs/brand/cinna-app-icon.png" alt="Posey icon" width="128"></p>

<h1 align="center">Posey</h1>

<p align="center">English · <a href="./README.zh-CN.md">简体中文</a></p>

A pose-reference camera for Android and iOS, with a Chinese interface.

Choose from 50 illustrated references or add your own. Follow the pose instructions, move or mirror the guide, and frame your shot. The guide stays out of the saved photo.

- Search by pose, scene or prop, with favorites and recent references.
- Use focus, zoom, a composition grid and a manual shutter timer, or import a photo.
- Keep photos in Works, edit copies, compare originals, share and save to the system gallery.
- Export local backups and merge them after validation. API keys and AI task credentials are excluded.
- Use light, dark or system appearance.

## Try it on Android

[Download the Android preview](https://github.com/icelemon233/Posey/releases/tag/v0.3.0-preview.1).

The preview installs alongside older Posey packages and keeps their data intact. Future previews use the same signing identity. Camera, gallery and background behavior still need testing on your phone; automated checks and platform builds are recorded in [mobile verification](./mobile/VERIFICATION.md).

## AI pose images

AI generation is optional. In Settings, enter your own API key, an HTTPS endpoint and an image model for Volcengine Ark or a compatible service. Connection checks request the model list without uploading photos.

Each generation asks for confirmation before sending the selected photo and reference. Provider charges may apply. Tasks retain the settings used at submission; interrupted generation requires confirmation to retry. Downloading or saving an existing result does not submit another generation request. Android uses a foreground service and iOS uses background transfers, subject to system limits.

## Build from source

Use Flutter 3.47.7 and Dart 3.13.5. Android needs Android tooling; iOS requires macOS and Xcode.

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run --flavor preview # Android
# On iOS: flutter run
```

Grant camera and photo access when requested. Backups contain your photos and are not encrypted; keep them in a private location.

[Architecture and build checks](./mobile/ARCHITECTURE.md) · [License](./LICENSE)

Developer: Cinna.
