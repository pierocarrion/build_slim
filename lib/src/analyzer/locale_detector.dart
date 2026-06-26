import 'dart:io';

import 'package:path/path.dart' as p;

import '../reporter/report_model.dart';
import '../util/logger.dart';

/// Detects the locales a Flutter app actually ships.
///
/// Used to drive Android `resConfigs` so third-party AARs (Google Play
/// Services, AndroidX) do not drag dozens of unused `values-xx` resource
/// folders into the artifact.
class LocaleDetector {
  /// Creates a locale detector.
  LocaleDetector({required this.projectDir, required this.logger});

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Detects locales in priority order:
  /// 1. ARB files under `lib/` (e.g. `app_es.arb`, `intl_fr.arb`).
  /// 2. iOS `.lproj` directories under `ios/Runner/`.
  /// 3. Falls back to `['en']` and returns a [Finding] prompting the user to
  ///    pass `--locales` explicitly.
  Future<({List<String> locales, List<Finding> findings})> detect() async {
    final findings = <Finding>[];

    final arbLocales = await _detectFromArb();
    if (arbLocales.isNotEmpty) {
      logger.verbose('Detected locales from ARB files: $arbLocales');
      return (locales: arbLocales, findings: const <Finding>[]);
    }

    final lprojLocales = _detectFromLproj();
    if (lprojLocales.isNotEmpty) {
      logger.verbose('Detected locales from .lproj dirs: $lprojLocales');
      return (locales: lprojLocales, findings: const <Finding>[]);
    }

    findings.add(const Finding(
      id: 'locales_undetected',
      severity: FindingSeverity.info,
      title: 'Could not auto-detect supported locales',
      description: 'No ARB files (lib/*.arb) or iOS .lproj directories were '
          'found. Android resConfigs will default to "en" only, which may '
          'strip translations you ship via other mechanisms.',
      recommendation: 'Pass --locales explicitly, e.g. '
          '--locales en --locales es, to keep additional translations.',
    ));
    return (locales: const ['en'], findings: findings);
  }

  /// Extracts BCP-47 codes from ARB filenames.
  ///
  /// Recognised shapes: `app_en.arb`, `intl_es_AR.arb`, `messages_fr.arb`,
  /// `app_zh-Hans.arb`, `app_pt-BR.arb` (hyphen or underscore separators).
  /// Files without a locale suffix (e.g. `app.arb`) are treated as the
  /// base/template file and skipped.
  Future<List<String>> _detectFromArb() async {
    final libDir = Directory(p.join(projectDir, 'lib'));
    if (!libDir.existsSync()) return const [];

    final locales = <String>{};
    // Accept both underscore and hyphen separators for the region/script
    // subtag, matching Flutter's own gen-l10n conventions.
    final arbPattern = RegExp(
      r'[a-z]+[_-]([a-zA-Z]{2,3}(?:[_-][A-Za-z0-9]{2,4})?)\.arb$',
    );

    await for (final entity
        in libDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.arb')) continue;
      final match = arbPattern.firstMatch(name);
      if (match == null) continue;
      final code = match.group(1);
      if (code == null) continue;
      // Normalise: only the primary subtag (e.g. `es` from `es_AR`).
      // Android resConfigs accepts only the language portion.
      final primary = code.split(RegExp(r'[_-]')).first.toLowerCase();
      if (primary.isNotEmpty) {
        locales.add(primary);
      }
    }
    final sorted = locales.toList()..sort();
    return sorted;
  }

  /// Extracts locale codes from `<code>.lproj` directory names.
  /// The Xcode-shipped `Base.lproj` is always excluded since `base` is not
  /// a valid Android resource locale.
  List<String> _detectFromLproj() {
    final runnerDir = Directory(p.join(projectDir, 'ios', 'Runner'));
    if (!runnerDir.existsSync()) return const [];

    final locales = <String>{};
    for (final entity in runnerDir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.lproj')) continue;
      final code = name.substring(0, name.length - '.lproj'.length);
      // Filter out Base.lproj — Xcode's default for non-localised resources.
      // It is not a real locale and would produce an invalid resConfigs.
      if (code.toLowerCase() == 'base') continue;
      locales.add(code.toLowerCase());
    }
    final sorted = locales.toList()..sort();
    return sorted;
  }
}
