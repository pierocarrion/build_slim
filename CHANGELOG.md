# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-06-25

### Added — advanced size strategies
- **`--aggressive`** flag: opt-in bundle of destructive optimizations. Every
  change ships with a `.bak` backup so users can roll back. Without the flag,
  `build_slim` keeps its historical, fully-safe behaviour.
  - **PNG/JPEG → WebP conversion** (`WebPConverter`): converts raster assets to
    WebP via `cwebp` and rewrites the references in `lib/**/*.dart` and
    `pubspec.yaml`. Atomic: if any conversion fails, no references are touched
    and the originals are preserved.
  - **R8 full mode** (`android.enableR8.fullMode=true`): injected into
    `android/gradle.properties` with backup. Removes substantially more
    unreachable code than the default safe mode.
  - **Strict resource shrinking** (`res/raw/keep.xml` with
    `tools:shrinkMode="strict"`): created only when absent; existing keep
    rules are never overwritten.
- **`--locales`** flag + auto-detection: injects Android `resConfigs` so
  third-party AARs (Play Services, AndroidX) no longer drag dozens of unused
  `values-xx` folders into the artifact. Locales are auto-detected from
  `*.arb` files and iOS `.lproj` directories when the flag is omitted.
- **`FindingSeverity.critical`** and **`Finding.breaking`**: new model fields
  surfaced by the console/HTML reporters with distinct styling so users
  immediately spot high-impact issues and changes that may break the build.

### Added — passive findings (analyze-only safe)
- **Heavy GIF audit**: GIFs above 300KB are flagged as `critical` recommending
  Lottie/Rive vector animations.
- **Font subsetting recommendation**: `.ttf`/`.otf` files above 200KB emit a
  warning suggesting `pyftsubset` (a 600KB Latin font typically drops to ~30KB).
- **Target-aware `extractNativeLibs` guidance**: AAB targets now recommend
  `extractNativeLibs="false"` (Play Store requirement for uncompressed native
  libs); APK/legacy targets preserve the previous warning. No more contradictory
  advice.
- **Deferred import suggestions**: heavy packages imported eagerly in `lib/`
  emit an info finding recommending `import ... deferred as ...` so App Bundles
  can ship them as on-demand splits.
- **R8 full mode audit** (`--analyze-only`): reports when the flag is missing,
  even without running the optimizer.

### Changed
- `OptimizerPipeline.run` and `ProjectAnalyzer` now accept the build `target`
  so target-aware findings can be emitted. The `target` parameter is optional
  on the analyzer to preserve backwards compatibility for direct callers.
- `pubspec.yaml` version bumped to `0.4.0`.

## [0.3.0] - 2026-06-22

### Fixed
- Android optimizer now emits correct Kotlin DSL when patching
  `build.gradle.kts`. Previously it injected Groovy syntax (`['arm64-v8a', ...]`
  list literals, `abiFilters.addAll(...)`, and bare `minifyEnabled`/`
  shrinkResources`) that failed to compile under the Kotlin DSL.
  - `abiFilters` now uses `ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }`.
  - Property names use the `is` prefix (`isMinifyEnabled`, `isShrinkResources`).
  - Release-only scoping: edits are confined to the `release { ... }` build type
    via brace matching, so a preceding `debug {}` block is never mutated.
  - Word-boundary matching prevents the substring corruption that produced
    invalid identifiers like `isminifyEnabled`. Re-running the optimizer also
    repairs files corrupted by previous versions.
- `NativeConfigAnalyzer.hasGradleBool` now recognizes the Kotlin `is`-prefixed
  property form (`isMinifyEnabled = true`) so analyze and optimize agree.

### Added
- Release signing resolution for Android targets (`apk`, `aab`) via a new
  `SigningConfigurator`. Follows the standard `android/key.properties` pattern
  with a deterministic, flag-driven flow (no interactive prompt — CI friendly).
  - `--keystore`, `--store-password`, `--key-alias`, `--key-password` generate
    `android/key.properties` from a keystore.
  - `--signing-config debug` temporarily signs the release build with the debug
    keystore (validation only) and creates a `.bak` backup.
  - Warns when `key.properties` is not covered by `.gitignore`.
  - Fails fast with actionable guidance when signing is unresolved.

### Changed
- `OptimizerPipeline.run` and `FakeOptimizerPipeline.run` accept the new signing
  parameters (`keystore`, `storePassword`, `keyAlias`, `keyPassword`,
  `debugSigning`). Callers that override `run` must add the new parameters.
- Android optimizer applies patches to whichever Gradle file was found and names
  it explicitly in the applied-optimizations message.

## [0.2.0] - 2026-06-21

### Added
- Comprehensive test suite: 279 tests covering all analyzers, optimizers,
  reporters, builders, CLI commands, and utilities (up from 17).
- End-to-end CLI tests that exercise the real `dart --version` and
  `flutter --version` probes against a fixture project.
- `@visibleForTesting` helpers on `NativeConfigAnalyzer` (`normalizeGradle`,
  `hasGradleBool`, `parseVersion`) to enable direct testing of fragile parsing.
- Injectable sink (`StringSink? sink`) on `Logger` to capture log output in
  tests without spawning real I/O.
- Optional dependency injection on `OptimizeCommand`, `ReportCommand`, and
  `BuildSlimRunner` for unit and integration testing of the CLI.
- `MockProcessRunner` improvements: `responseFor` callback, `RecordedInvocation`
  records (with working directory tracked separately), `throwIfUnmatched`.
- `FakeOptimizerPipeline` test helper.
- Pinned tests documenting known bugs (dead ternary in asset analyzer,
  non-monotonic `_parseVersion` for minor >= 100, Groovy-syntax detection gap,
  `_compressWith` adding success message on failure).

### Changed
- `Logger` constructor is no longer `const` (accepts a runtime `stdout` sink
  by default). Existing call sites using `const Logger(...)` should drop the
  `const` keyword.

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

[0.3.0]: https://github.com/pierocarrion/build_slim/releases/tag/v0.3.0
[0.2.0]: https://github.com/pierocarrion/build_slim/releases/tag/v0.2.0
[0.1.1]: https://github.com/pierocarrion/build_slim/releases/tag/v0.1.1
[0.1.0]: https://github.com/pierocarrion/build_slim/releases/tag/v0.1.0
