import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../reporter/report_model.dart';
import '../util/logger.dart';

/// Analyzes native Android and iOS configuration files for size issues.
class NativeConfigAnalyzer {
  /// Creates a native config analyzer.
  NativeConfigAnalyzer({
    required this.projectDir,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Analyzes Android and iOS native configuration and returns findings.
  Future<List<Finding>> analyze() async {
    final findings = <Finding>[];
    findings.addAll(await _analyzeAndroid());
    findings.addAll(await _analyzeIos());
    return findings;
  }

  Future<List<Finding>> _analyzeAndroid() async {
    final findings = <Finding>[];
    final gradlePaths = [
      p.join(projectDir, 'android', 'app', 'build.gradle'),
      p.join(projectDir, 'android', 'app', 'build.gradle.kts'),
    ];

    String? gradleContent;
    String? gradlePath;
    for (final path in gradlePaths) {
      final file = File(path);
      if (file.existsSync()) {
        gradleContent = await file.readAsString();
        gradlePath = path;
        break;
      }
    }

    if (gradleContent == null || gradlePath == null) {
      logger.verbose('No Android build.gradle found.');
      return findings;
    }
    logger.verbose('Auditing native Android config: $gradlePath');

    final normalized = normalizeGradle(gradleContent);

    if (!hasGradleBool(normalized, 'minifyEnabled', true)) {
      findings.add(const Finding(
        id: 'android_minify_disabled',
        severity: FindingSeverity.warning,
        title: 'Android minifyEnabled is not true',
        description: 'R8 code shrinking is disabled in release builds, '
            'which increases APK/AAB size.',
        recommendation: 'Set minifyEnabled true in the release build type '
            'of android/app/build.gradle.',
        estimatedSavingsBytes: 2 * 1024 * 1024,
      ));
    }

    if (!hasGradleBool(normalized, 'shrinkResources', true)) {
      findings.add(const Finding(
        id: 'android_shrink_resources_disabled',
        severity: FindingSeverity.warning,
        title: 'Android shrinkResources is not true',
        description: 'Unused resources are not removed from release builds.',
        recommendation: 'Set shrinkResources true in the release build type '
            'when minifyEnabled is also true.',
        estimatedSavingsBytes: 1024 * 1024,
      ));
    }

    if (!normalized.contains('abiFilters') &&
        !normalized.contains('ndk.abiFilters')) {
      findings.add(const Finding(
        id: 'android_abi_filters_missing',
        severity: FindingSeverity.warning,
        title: 'Android ABI filters not configured',
        description: 'Without ABI filters, the APK/AAB may bundle x86 '
            'libraries that are rarely needed.',
        recommendation: 'Add abiFilters ["arm64-v8a", "armeabi-v7a"] to '
            'reduce native library size.',
        estimatedSavingsBytes: 3 * 1024 * 1024,
      ));
    }

    final manifestPath = p.join(
      projectDir,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    );
    final manifestFile = File(manifestPath);
    if (manifestFile.existsSync()) {
      try {
        final manifestContent = await manifestFile.readAsString();
        final applicationMatch = RegExp(
          r'<application([^>]*)>',
          dotAll: true,
        ).firstMatch(manifestContent);
        if (applicationMatch != null) {
          final attrs = applicationMatch.group(1) ?? '';
          if (attrs.contains('android:extractNativeLibs="false"')) {
            findings.add(const Finding(
              id: 'android_extract_native_libs_false',
              severity: FindingSeverity.warning,
              title: 'android:extractNativeLibs="false"',
              description: 'Setting extractNativeLibs to false can increase '
                  'APK install size on older devices.',
              recommendation: 'Remove android:extractNativeLibs="false" unless '
                  'you specifically need uncompressed libraries.',
            ));
          }
        }
      } on FileSystemException catch (e) {
        logger.warning('Could not read AndroidManifest.xml: ${e.message}');
      }
    }

    return findings;
  }

  Future<List<Finding>> _analyzeIos() async {
    final findings = <Finding>[];
    final podfilePath = p.join(projectDir, 'ios', 'Podfile');
    final podfile = File(podfilePath);

    if (!podfile.existsSync()) {
      logger.verbose('No iOS Podfile found.');
      return findings;
    }

    final content = await podfile.readAsString();
    final platformMatch =
        RegExp("platform\\s+:ios,\\s*['\"]([^'\"]+)['\"]").firstMatch(content);
    final versionString = platformMatch?.group(1);

    if (versionString == null) {
      findings.add(const Finding(
        id: 'ios_deployment_target_missing',
        severity: FindingSeverity.warning,
        title: 'iOS deployment target not found',
        description: 'Could not determine the iOS deployment target from '
            'the Podfile.',
        recommendation: 'Add an explicit platform :ios line to your Podfile.',
      ));
    } else {
      final version = parseVersion(versionString);
      if (version < 12.0) {
        findings.add(Finding(
          id: 'ios_deployment_target_low',
          severity: FindingSeverity.warning,
          title: 'iOS deployment target below 12.0',
          description: 'The Podfile targets iOS $versionString. '
              'Modern Flutter plugins often require iOS 12 or later.',
          recommendation: "Raise the platform to at least :ios, '12.0'.",
        ));
      }
    }

    final xcconfigPath = p.join(
      projectDir,
      'ios',
      'Flutter',
      'Release.xcconfig',
    );
    final xcconfig = File(xcconfigPath);
    if (xcconfig.existsSync()) {
      final xcconfigContent = await xcconfig.readAsString();
      if (!xcconfigContent.contains('ENABLE_BITCODE=NO')) {
        findings.add(const Finding(
          id: 'ios_bitcode_enabled',
          severity: FindingSeverity.warning,
          title: 'iOS bitcode may be enabled',
          description: 'Bitcode is deprecated and can increase IPA size.',
          recommendation:
              'Add ENABLE_BITCODE=NO to ios/Flutter/Release.xcconfig.',
          estimatedSavingsBytes: 2 * 1024 * 1024,
        ));
      }
    }

    return findings;
  }

  /// Normalizes Gradle-like content by removing comments and whitespace
  /// around equals signs so boolean checks are more robust.
  @visibleForTesting
  String normalizeGradle(String content) {
    return content
        .replaceAll(RegExp(r'//.*'), '')
        .replaceAll(RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '')
        .replaceAll(RegExp(r'\s*=\s*'), '=')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Returns true if [content] contains `key=value` after normalization.
  ///
  /// Accepts both the Groovy form (`minifyEnabled=true`) and the Kotlin DSL
  /// form (`isMinifyEnabled=true`). A word boundary prevents matching the key
  /// as a substring of an unrelated identifier.
  @visibleForTesting
  bool hasGradleBool(String content, String key, bool value) {
    final v = value.toString();
    final pattern = RegExp('\\b(?:is)?$key\\b\\s*=\\s*$v', caseSensitive: false);
    return pattern.hasMatch(content);
  }

  /// Parses [version] (e.g. `'12.0'`) into a comparable double.
  @visibleForTesting
  double parseVersion(String version) {
    final clean = version.split('-').first;
    final parts = clean.split('.').map(double.tryParse).toList();
    final major = parts.isNotEmpty ? (parts[0] ?? 0) : 0;
    final minor = parts.length > 1 ? (parts[1] ?? 0) : 0;
    return major + minor / 100;
  }
}
