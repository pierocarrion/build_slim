import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/logger.dart';

/// Safely patches Android Gradle configuration for release size optimization.
class AndroidOptimizer {
  /// Creates an Android optimizer.
  AndroidOptimizer({
    required this.projectDir,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Patches `android/app/build.gradle` and returns applied changes.
  Future<List<String>> optimize() async {
    final applied = <String>[];
    final gradlePaths = [
      p.join(projectDir, 'android', 'app', 'build.gradle'),
      p.join(projectDir, 'android', 'app', 'build.gradle.kts'),
    ];

    String? gradlePath;
    File? gradleFile;
    for (final path in gradlePaths) {
      final file = File(path);
      if (file.existsSync()) {
        gradleFile = file;
        gradlePath = path;
        break;
      }
    }

    if (gradleFile == null || gradlePath == null) {
      logger
          .verbose('No Android build.gradle found; skipping Android patches.');
      return applied;
    }

    final originalContent = await gradleFile.readAsString();
    var content = originalContent;
    final isKotlin = gradlePath.endsWith('.kts');

    content = _ensureReleaseProperty(
      content,
      key: 'minifyEnabled',
      value: true,
      isKotlin: isKotlin,
    );
    content = _ensureReleaseProperty(
      content,
      key: 'shrinkResources',
      value: true,
      isKotlin: isKotlin,
    );
    content = _ensureAbiFilters(content, isKotlin: isKotlin);
    content = _ensureBundleLanguageSplit(content, isKotlin: isKotlin);

    if (content != originalContent) {
      await _writeWithBackup(gradleFile, content);
      applied.add('Patched android/app/build.gradle (minifyEnabled, '
          'shrinkResources, abiFilters, language split)');
    }

    final proguardRules = File(p.join(
      projectDir,
      'android',
      'app',
      'proguard-rules.pro',
    ));
    if (!proguardRules.existsSync()) {
      await proguardRules.writeAsString(_defaultProguardRules);
      applied.add('Created default proguard-rules.pro');
    }

    return applied;
  }

  String _ensureReleaseProperty(
    String content, {
    required String key,
    required bool value,
    required bool isKotlin,
  }) {
    final assignment = '$key = ${value.toString()}';
    final existing = RegExp('$key\\s*=\\s*(true|false)', caseSensitive: false);
    final releaseBlock = RegExp(
      r'release\s*\{',
      caseSensitive: false,
    );

    if (!releaseBlock.hasMatch(content)) return content;

    if (existing.hasMatch(content)) {
      return content.replaceFirstMapped(
        existing,
        (_) => assignment,
      );
    }

    return content.replaceFirstMapped(releaseBlock, (match) {
      return '${match.group(0)}\n            $assignment';
    });
  }

  String _ensureAbiFilters(String content, {required bool isKotlin}) {
    const filters = "['arm64-v8a', 'armeabi-v7a']";
    if (content.contains('abiFilters') || content.contains('ndk.abiFilters')) {
      return content;
    }

    final defaultConfig = RegExp(
      r'defaultConfig\s*\{',
      caseSensitive: false,
    );
    if (!defaultConfig.hasMatch(content)) return content;

    final line = isKotlin
        ? 'ndk { abiFilters.addAll($filters) }'
        : 'ndk { abiFilters $filters }';
    return content.replaceFirstMapped(defaultConfig, (match) {
      return '${match.group(0)}\n        $line';
    });
  }

  String _ensureBundleLanguageSplit(String content, {required bool isKotlin}) {
    final pattern = RegExp(
      r'android\s*\{',
      caseSensitive: false,
    );
    const line = 'bundle { language { enableSplit = true } }';

    if (content.contains('enableSplit')) return content;
    if (!pattern.hasMatch(content)) return content;

    return content.replaceFirstMapped(pattern, (match) {
      return '${match.group(0)}\n    $line';
    });
  }

  Future<void> _writeWithBackup(File file, String content) async {
    final backup = File('${file.path}.bak');
    if (!backup.existsSync()) {
      await backup.writeAsString(await file.readAsString());
      logger.verbose('Created backup: ${backup.path}');
    }
    await file.writeAsString(content);
  }

  static const String _defaultProguardRules = r'''
# Flutter ProGuard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn io.flutter.**
''';
}
