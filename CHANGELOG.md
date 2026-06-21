# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-06-21

### Changed
- Bumped `args` lower bound to `^2.5.0`.

## [0.1.0] - 2024-06-19

### Added
- Initial release of `build_slim`.
- `optimize` command to analyze and build APK, AAB, and IPA artifacts.
- `report` command to compare before/after artifact sizes.
- Asset analyzer that detects unused assets and over-declared font weights.
- Dependency analyzer that flags known heavy transitive packages.
- Native configuration analyzers for Android (`build.gradle`) and iOS (`Podfile`, `.xcconfig`, `.pbxproj`).
- Dart optimizer that injects `--tree-shake-icons`, `--obfuscate`, and `--split-debug-info`.
- Android optimizer that patches Gradle settings and verifies ProGuard rules.
- iOS optimizer that injects safe `.xcconfig` settings and emits manual instructions.
- Asset optimizer that compresses PNG/JPEG/WebP assets when `pngquant`, `optipng`, or `cwebp` are available.
- Console, JSON, and HTML reporters.
- Comprehensive unit tests and fixture project for analyzers.

[0.1.1]: https://github.com/pierocarrion/build_slim/releases/tag/v0.1.1
[0.1.0]: https://github.com/pierocarrion/build_slim/releases/tag/v0.1.0
