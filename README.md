# climate_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Building for Release

To build the release APK and avoid common `tree-shake-icons` issues, use the provided build script:

```bash
./build_apk.sh
```

Alternatively, you can run the command manually:

```bash
flutter build apk --release --no-tree-shake-icons
```
