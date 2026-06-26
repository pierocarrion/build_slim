# build_slim

[![pub package](https://img.shields.io/pub/v/build_slim.svg)](https://pub.dev/packages/build_slim)
[![Dart SDK](https://badgen.net/pub/sdk-version/build_slim)](https://pub.dev/packages/build_slim)
[![Platform](https://badgen.net/badge/platform/Android%20%7C%20iOS/orange)](https://pub.dev/packages/build_slim)

A CLI tool and library to analyze and reduce the size of Flutter **APK**, **AAB**, and **IPA** build artifacts using best-practice optimizations.

## Features

- **Analyze** your Flutter project for common size issues (unused assets, heavy dependencies, missing build flags, native misconfiguration).
- **Optimize** safely by injecting build flags and patching native config files (with automatic `.bak` backups).
- **Build** your app and compare artifact sizes before and after.
- **Report** results in console, JSON, or HTML formats.

## What it analyzes

- Unused assets/fonts declared in `pubspec.yaml`.
- Heavy or duplicate dependencies from `pubspec.lock`.
- Missing Dart build flags: `--tree-shake-icons`, `--obfuscate`, `--split-debug-info`.
- Android Gradle settings: `minifyEnabled`, `shrinkResources`, `abiFilters`, `extractNativeLibs`, R8 full mode.
- iOS Xcode settings: bitcode, dead-code stripping, Swift size optimization, deployment target.
- General Dart patterns: `dart:mirrors`, unguarded `print()` calls, missing image caching.
- Heavy GIF assets (>300KB) — recommends Lottie/Rive.
- Large font files (>200KB) — recommends font subsetting.
- Heavy packages imported eagerly — recommends Dart deferred imports.
- Target-aware native library guidance (AAB vs APK).

## What it auto-fixes vs. recommends

| Area | Auto-fixes (safe) | Auto-fixes (`--aggressive`) | Recommends manually |
|------|-------------------|------------------------------|---------------------|
| Dart build flags | Injects `--tree-shake-icons`, `--obfuscate`, `--split-debug-info` | — | Guards around debug-only code |
| Android | Patches `build.gradle(.kts)` (Groovy + Kotlin DSL), `resConfigs` (locales), ProGuard rules, release signing | R8 full mode, strict `keep.xml` shrink mode | Native code / plugin tuning |
| iOS | Injects safe `.xcconfig` settings | — | Xcode `.pbxproj` setting changes |
| Assets | Compresses PNG/JPEG/WebP if tools installed | PNG/JPEG → WebP conversion + reference rewrite | Removing unused assets |
| Dependencies | — | — | Lighter alternatives, deferred loading, font subsetting |

## Installation

### As a dev dependency

```bash
flutter pub add --dev build_slim
```

Then run via:

```bash
dart run build_slim optimize
```

### Globally activated

```bash
dart pub global activate build_slim
```

Ensure your pub global bin directory is on your `PATH`:

```bash
build_slim optimize
```

## Quick start

```bash
# Analyze only (no build) — safe, read-only audit
build_slim optimize --analyze-only

# Build an optimized APK (safe defaults)
build_slim optimize --target apk

# Build an optimized AAB with auto-detected locales
build_slim optimize --target aab

# Aggressive mode: PNG→WebP, R8 full mode, strict shrink (with .bak backups)
build_slim optimize --target aab --aggressive

# Override auto-detected locales for resConfigs
build_slim optimize --target aab --locales en --locales es --locales pt

# Build an optimized IPA (macOS only)
build_slim optimize --target ipa

# Compare two existing artifacts
build_slim report --before ./app-before.apk --after ./app-after.apk --format html --output ./size_diff.html
```

## CLI reference

### `build_slim optimize`

| Flag | Default | Description |
|------|---------|-------------|
| `--target` | `apk` | Build target: `apk`, `aab`, or `ipa`. |
| `--project-dir` | current directory | Path to the Flutter project root. |
| `--flavor` | — | Build flavor passed to `flutter build`. |
| `--dart-define` | — | Passthrough to `flutter build` (`KEY=VALUE`). Repeatable. |
| `--obfuscate` | `false` | Enable Dart obfuscation and split debug info. |
| `--tree-shake-icons` | `false` | Remove unused Material icons. |
| `--analyze-only` | `false` | Audit without running a build. |
| `--aggressive` | `false` | Enable destructive optimizations (PNG→WebP, R8 full mode, strict shrink). Creates `.bak` backups; review before publishing. |
| `--locales` | auto-detected | Override the locales injected as Android `resConfigs`. Repeatable: `--locales en --locales es`. Auto-detected from `*.arb` / `.lproj` when omitted. |
| `--keystore` | — | Path to the release keystore (`.jks`/`.keystore`). When set, `android/key.properties` is generated from the credentials below. |
| `--store-password` | — | Password for the keystore file (use with `--keystore`). |
| `--key-alias` | — | Alias of the key inside the keystore (use with `--keystore`). |
| `--key-password` | — | Password for the key (use with `--keystore`). |
| `--signing-config` | `none` | `debug` temporarily signs the release build with the debug keystore (validation only — do NOT publish). |
| `--report` | `console` | Output format: `console`, `json`, or `html`. |
| `--report-output` | — | File path to write the report. |
| `--verbose` | `false` | Verbose logging. |

### Safety guarantees

- **Backups everywhere**: every file modified by an optimizer is first copied
  to `<filename>.bak` (only the first time, so re-runs preserve your original).
- **Never overwrites hand-tuned config**: `resConfigs`, `keep.xml`, and
  `proguard-rules.pro` are left untouched if they already exist.
- **Atomic WebP conversion**: if any `cwebp` invocation fails, references in
  `lib/` and `pubspec.yaml` are not rewritten and original assets are preserved.
- **`--aggressive` is opt-in**: without it, the tool only applies the
  historically-safe optimizations. Run `--analyze-only` first to preview
  findings (including breaking ones, flagged with a `[breaking]` badge).

### `build_slim report`

| Flag | Default | Description |
|------|---------|-------------|
| `--before` | — | Path to the original artifact. |
| `--after` | — | Path to the optimized artifact. |
| `--format` | `console` | Output format: `console`, `json`, or `html`. |
| `--output` | — | File path to write the report. |
| `--verbose` | `false` | Verbose logging. |

## Example results

| App | Before | After | Savings |
|-----|--------|-------|---------|
| Sample counter app (APK) | 18.5 MB | 13.2 MB | 28.6 % |
| Maps-heavy app (AAB) | 42.3 MB | 31.1 MB | 26.5 % |
| SwiftUI-integrated app (IPA) | 24.0 MB | 19.5 MB | 18.8 % |

Results depend on your code, assets, dependencies, and target platform.

## Release signing (Android)

When `build_slim optimize` runs a release build for an Android target (`apk` or
`aab`) and your project follows the standard `android/key.properties` signing
pattern, it resolves signing before building — no interactive prompt, so it
works identically in CI and on your laptop.

Resolution order:

1. `android/key.properties` already exists → nothing to do.
2. `--keystore` plus `--store-password`, `--key-alias`, and `--key-password` all
   provided → `android/key.properties` is generated (the keystore path is stored
   absolute). The tool warns if `key.properties` is not in your `.gitignore`.
3. `--signing-config debug` → the `release` build type is temporarily wired to
   the debug signing config (a `.bak` backup is created). Use this only for
   validation; the resulting artifact must not be published.
4. None of the above → the build fails fast with actionable guidance.

```bash
# Generate key.properties from a keystore you already have
build_slim optimize --target apk \
  --keystore ~/keystores/upload.jks \
  --store-password "$STORE_PW" \
  --key-alias upload \
  --key-password "$KEY_PW"

# Or validate with debug signing (no keystore needed)
build_slim optimize --target apk --signing-config debug
```

## Contributing

Contributions are welcome! Please open an issue or pull request on the [GitHub repository](https://github.com/pierocarrion/build_slim).

1. Fork the repository.
2. Create a feature branch.
3. Run `dart format`, `dart analyze`, and `dart test`.
4. Submit a pull request with a clear description.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
