# Posey

English | [简体中文](./README.zh-CN.md)

A pose-reference camera app for Android and iOS. Find a pose you like, use it as a guide while framing a photo, and keep the finished shot free of the reference overlay.

## What you can do

- Browse pose references by category, search, and save favorites.
- Adjust the reference's transparency and mirror it to suit the shot.
- Use camera controls, a composition grid, or an imported photo.
- Review photos and save them to the system gallery.
- Optionally generate AI pose images with your own service configuration.

## Try it from source

Use Flutter 3.47.7 with Dart 3.13.5, plus Android tooling or macOS with Xcode for iOS.

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

Use a physical phone to try the camera and gallery features, and grant the required permissions when prompted.

## Optional AI features

In Settings, provide your own API key, HTTPS service address, and image model for the supported AI service. When you confirm generation, the selected photo and reference are sent to that service. Provider usage charges may apply.

## License

See [LICENSE](./LICENSE) for usage terms.
