# build_slim example

This folder demonstrates how to use `build_slim` in a Flutter project.

## 1. Add the package

```bash
flutter pub add --dev build_slim
```

Or activate it globally:

```bash
dart pub global activate build_slim
```

## 2. Analyze your project

```bash
dart run build_slim optimize --analyze-only
```

This prints a list of findings without modifying files or starting a build.

## 3. Build an optimized APK

```bash
dart run build_slim optimize --target apk --tree-shake-icons --obfuscate
```

The tool will:

1. Analyze your project.
2. Patch Android Gradle settings safely (with `.bak` backups).
3. Inject `--tree-shake-icons`, `--obfuscate`, and `--split-debug-info`.
4. Run `flutter build apk`.
5. Print a before/after summary.

## 4. Compare artifacts

If you already have two builds, compare them with:

```bash
build_slim report \
  --before ./build/app/outputs/flutter-apk/app-before.apk \
  --after ./build/app/outputs/flutter-apk/app-after.apk \
  --format html \
  --output ./size_diff.html
```
