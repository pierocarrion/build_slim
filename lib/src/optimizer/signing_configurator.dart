import 'dart:io';

import 'package:path/path.dart' as p;

import '../builder/artifact_comparator.dart';
import '../util/logger.dart';

/// The action taken by [SigningConfigurator.configure].
enum SigningAction {
  /// No change was required.
  skipped,

  /// `android/key.properties` was generated from flag credentials.
  generated,

  /// The release build type was temporarily switched to debug signing.
  debugFallback,
}

/// Outcome of a signing configuration pass.
class SigningResult {
  /// Creates a signing result.
  const SigningResult({required this.action, this.reason});

  /// What was done.
  final SigningAction action;

  /// Human-readable detail, if any.
  final String? reason;

  /// Whether a non-trivial change was applied.
  bool get applied => action != SigningAction.skipped;
}

/// A located named block body bounded by `{ ... }`.
class _BlockRange {
  const _BlockRange(this.bodyStart, this.bodyEnd);

  final int bodyStart;
  final int bodyEnd;
}

/// Resolves Android release signing for a Flutter project.
///
/// The configurator follows the standard Flutter `key.properties` signing
/// pattern. It never prompts interactively; all credentials are supplied via
/// flags so the flow is deterministic and works in CI.
class SigningConfigurator {
  /// Creates a signing configurator.
  SigningConfigurator({required this.projectDir, required this.logger});

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Resolves release signing before a build.
  ///
  /// Resolution order:
  /// 1. If the project does not use the `key.properties` pattern, no-op.
  /// 2. If `android/key.properties` already exists, no-op.
  /// 3. If all keystore credentials are supplied, generate `key.properties`.
  /// 4. If [debugSigning] is true, temporarily wire the release build type to
  ///    the debug signing config.
  /// 5. Otherwise throw [BuildOptimizerException] with actionable guidance.
  Future<SigningResult> configure({
    String? keystore,
    String? storePassword,
    String? keyAlias,
    String? keyPassword,
    bool debugSigning = false,
  }) async {
    final gradleInfo = await _findGradle();
    if (gradleInfo == null) {
      return const SigningResult(
        action: SigningAction.skipped,
        reason: 'No Android build.gradle found; signing left untouched.',
      );
    }

    final gradleContent = await gradleInfo.file.readAsString();
    final usesKeyProperties = gradleContent.contains('key.properties');
    if (!usesKeyProperties) {
      return const SigningResult(
        action: SigningAction.skipped,
        reason: 'Project does not use the key.properties signing pattern.',
      );
    }

    final keyPropsFile = File(
      p.join(projectDir, 'android', 'key.properties'),
    );

    // (2) Already configured.
    if (keyPropsFile.existsSync()) {
      return const SigningResult(
        action: SigningAction.skipped,
        reason: 'android/key.properties already present.',
      );
    }

    // (3) Generate from flag credentials.
    if (keystore != null && keystore.isNotEmpty) {
      final missing = <String>[];
      if (storePassword == null || storePassword.isEmpty) {
        missing.add('--store-password');
      }
      if (keyAlias == null || keyAlias.isEmpty) {
        missing.add('--key-alias');
      }
      if (keyPassword == null || keyPassword.isEmpty) {
        missing.add('--key-password');
      }
      if (missing.isNotEmpty) {
        throw BuildOptimizerException(
          'Release signing via --keystore requires all credentials. '
          'Missing: ${missing.join(', ')}. Alternatively pass '
          '--signing-config debug for a debug-signed validation build.',
        );
      }

      final keystoreFile = File(keystore);
      if (!keystoreFile.existsSync()) {
        throw BuildOptimizerException('Keystore not found at: $keystore');
      }

      final storePath = p.absolute(keystore);
      await _writeKeyProperties(
        keyPropsFile,
        storeFile: storePath,
        storePassword: storePassword!,
        keyAlias: keyAlias!,
        keyPassword: keyPassword!,
      );
      logger.success('Generated ${keyPropsFile.path}');
      _warnIfNotGitignored();
      return SigningResult(
        action: SigningAction.generated,
        reason: 'Created ${keyPropsFile.path} for keystore $storePath.',
      );
    }

    // (4) Debug fallback.
    if (debugSigning) {
      final updated =
          _injectDebugSigning(gradleContent, isKotlin: gradleInfo.isKotlin);
      if (updated != gradleContent) {
        await _writeWithBackup(gradleInfo.file, updated);
        logger.warning(
          'TEMPORARY: the release build type is signed with the debug keystore. '
          'Do NOT publish this artifact. Remove the override or create '
          'android/key.properties before release.',
        );
        return const SigningResult(
          action: SigningAction.debugFallback,
          reason: 'Release build type switched to debug signing.',
        );
      }
      logger.warning(
        'Could not locate a release signingConfig to override; '
        'leaving the Gradle file unchanged.',
      );
      return const SigningResult(
        action: SigningAction.skipped,
        reason: 'No release signingConfig found to override.',
      );
    }

    // (5) Nothing provided.
    throw const BuildOptimizerException(
      'Release signing is not configured. The project references '
      'android/key.properties but the file is missing. Provide '
      '--keystore <path> --store-password <pw> --key-alias <alias> '
      '--key-password <pw>, or --signing-config debug for a debug-signed '
      'validation build.',
    );
  }

  Future<_GradleInfo?> _findGradle() async {
    final candidates = [
      (p.join(projectDir, 'android', 'app', 'build.gradle.kts'), true),
      (p.join(projectDir, 'android', 'app', 'build.gradle'), false),
    ];
    for (final (path, isKotlin) in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        return _GradleInfo(file: file, isKotlin: isKotlin);
      }
    }
    return null;
  }

  Future<void> _writeKeyProperties(
    File file, {
    required String storeFile,
    required String storePassword,
    required String keyAlias,
    required String keyPassword,
  }) async {
    final content = 'storePassword=$storePassword\n'
        'keyPassword=$keyPassword\n'
        'keyAlias=$keyAlias\n'
        'storeFile=$storeFile\n';
    await file.writeAsString(content);
  }

  String _injectDebugSigning(String content, {required bool isKotlin}) {
    final release = _findNamedBlock(content, 'release');
    if (release == null) return content;

    final before = content.substring(0, release.bodyStart);
    final body = content.substring(release.bodyStart, release.bodyEnd);
    final after = content.substring(release.bodyEnd);

    final debugTarget =
        isKotlin ? 'signingConfigs.getByName("debug")' : 'signingConfigs.debug';

    final newBody = body
        .replaceAll(
          RegExp(
            r'signingConfig\s*=\s*signingConfigs\.getByName\(\s*"release"\s*\)',
          ),
          'signingConfig = $debugTarget',
        )
        .replaceAll(
          RegExp(r'signingConfig\s*=\s*signingConfigs\.release\b'),
          'signingConfig = $debugTarget',
        )
        .replaceAll(
          RegExp(r'signingConfig\s+signingConfigs\.release\b'),
          'signingConfig $debugTarget',
        );

    if (newBody == body) return content;
    return '$before$newBody$after';
  }

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

  void _warnIfNotGitignored() {
    final gitignore = File(p.join(projectDir, '.gitignore'));
    if (!gitignore.existsSync()) {
      logger.warning(
        'No .gitignore found. Ensure android/key.properties is ignored to '
        'avoid committing signing secrets.',
      );
      return;
    }
    final content = gitignore.readAsStringSync();
    if (!content.contains('key.properties')) {
      logger.warning(
        'android/key.properties does not appear in .gitignore. Add it to '
        'avoid committing signing secrets.',
      );
    }
  }

  Future<void> _writeWithBackup(File file, String content) async {
    final backup = File('${file.path}.bak');
    if (!backup.existsSync()) {
      await backup.writeAsString(await file.readAsString());
      logger.verbose('Created backup: ${backup.path}');
    }
    await file.writeAsString(content);
  }
}

class _GradleInfo {
  const _GradleInfo({required this.file, required this.isKotlin});

  final File file;
  final bool isKotlin;
}
