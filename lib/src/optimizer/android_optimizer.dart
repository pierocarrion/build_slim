import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/logger.dart';

/// A located named block body bounded by `{ ... }`.
class _BlockRange {
  _BlockRange(this.bodyStart, this.bodyEnd);

  /// Index just after the opening `{`.
  final int bodyStart;

  /// Index of the matching closing `}`.
  final int bodyEnd;
}

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
    content = _ensureBundleLanguageSplit(content);

    if (content != originalContent) {
      await _writeWithBackup(gradleFile, content);
      applied.add('Patched ${p.basename(gradlePath)} (minifyEnabled, '
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

  /// Ensures [key] is set to [value] inside the `release { ... }` build type.
  ///
  /// Edits are scoped to the release block only (so a `debug {}` block is never
  /// mutated) and use the correct property name per DSL: Kotlin DSL requires the
  /// `is` prefix (`isMinifyEnabled`), while Groovy uses the bare name
  /// (`minifyEnabled`). A word-boundary regex prevents the substring-match
  /// corruption that the previous implementation suffered from.
  String _ensureReleaseProperty(
    String content, {
    required String key,
    required bool value,
    required bool isKotlin,
  }) {
    final block = _findNamedBlock(content, 'release');
    if (block == null) return content;

    final canonicalName = isKotlin ? 'is${_capitalize(key)}' : key;
    final assignment = '$canonicalName = ${value.toString()}';

    final before = content.substring(0, block.bodyStart);
    final body = content.substring(block.bodyStart, block.bodyEnd);
    final after = content.substring(block.bodyEnd);

    // Matches the property name with an optional `is` prefix (so re-running the
    // optimizer also repairs prior corrupted casing like `isminifyEnabled`),
    // followed by an optional `=` and a boolean literal.
    final existing = RegExp(
      '\\b(?:is)?$key\\b\\s*=?\\s*(?:true|false)',
      caseSensitive: false,
    );

    String newBody;
    final match = existing.firstMatch(body);
    if (match != null) {
      newBody = body.replaceRange(match.start, match.end, assignment);
    } else {
      newBody = '\n            $assignment$body';
    }

    return '$before$newBody$after';
  }

  /// Ensures ABI filters are configured to exclude rare x86 targets.
  ///
  /// Emits DSL-correct syntax: `abiFilters += listOf(...)` for Kotlin DSL and
  /// the idiomatic `abiFilters 'a', 'b'` call form for Groovy.
  String _ensureAbiFilters(String content, {required bool isKotlin}) {
    if (content.contains('abiFilters') || content.contains('ndk.abiFilters')) {
      return content;
    }

    final defaultConfig = _findNamedBlock(content, 'defaultConfig');
    if (defaultConfig == null) return content;

    final line = isKotlin
        ? 'ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }'
        : "ndk { abiFilters 'arm64-v8a', 'armeabi-v7a' }";

    final before = content.substring(0, defaultConfig.bodyStart);
    final after = content.substring(defaultConfig.bodyStart);
    return '$before\n        $line$after';
  }

  /// Ensures the `bundle { language { enableSplit = true } }` block exists so
  /// language resources are split per-device in AAB uploads.
  String _ensureBundleLanguageSplit(String content) {
    if (content.contains('enableSplit')) return content;

    final androidBlock = _findNamedBlock(content, 'android');
    if (androidBlock == null) return content;

    const line = 'bundle { language { enableSplit = true } }';
    final before = content.substring(0, androidBlock.bodyStart);
    final after = content.substring(androidBlock.bodyStart);
    return '$before\n    $line$after';
  }

  /// Locates the body of the first `<name> { ... }` block by brace matching.
  _BlockRange? _findNamedBlock(String content, String name) {
    final header = RegExp('\\b$name\\s*\\{');
    final match = header.firstMatch(content);
    if (match == null) return null;

    final openBrace = match.end - 1;
    var depth = 0;
    for (var i = openBrace; i < content.length; i++) {
      final ch = content[i];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return _BlockRange(openBrace + 1, i);
        }
      }
    }
    return null;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

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
