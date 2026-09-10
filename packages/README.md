# Vendored packages

## google_mlkit_commons / google_mlkit_text_recognition

Copies of the pub.dev packages with the **iOS implementation removed** (the
`ios/` directory and the `ios:` entry under `flutter.plugin.platforms`).

Why: ML Kit is only the *Android* OCR path — iOS uses Apple Vision natively
(`lib/data/services/ocr/text_scanner.dart`). The ML Kit CocoaPods ship no
arm64-simulator slice, so linking them broke every iOS-simulator build on
Apple silicon (iOS 26+ simulators are arm64-only). With the iOS side gone the
pods are never installed, simulator builds work, and the shipped iOS app
loses ~30 MB of frameworks it never called.

When upgrading: copy the new package version from `~/.pub-cache/hosted/pub.dev/`,
delete its `ios/` directory, remove the `ios:` block from `flutter.plugin.platforms`
in its pubspec.yaml, and keep the versions in `dependency_overrides` consistent.
