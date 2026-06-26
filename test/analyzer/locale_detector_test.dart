import 'dart:io';

import 'package:build_slim/src/analyzer/locale_detector.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('locale_detector');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  LocaleDetector newDetector() => LocaleDetector(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );

  group('LocaleDetector.detect', () {
    test('detects locales from ARB files in lib/', () async {
      final l10n = Directory(p.join(tempDir.path, 'lib', 'l10n'));
      await l10n.create(recursive: true);
      await File(p.join(l10n.path, 'app.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'app_en.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'app_es.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'app_fr.arb')).writeAsString('{}');

      final result = await newDetector().detect();

      expect(result.locales, containsAll(['en', 'es', 'fr']));
      expect(result.findings, isEmpty);
    });

    test('normalises region subtags to primary language', () async {
      final l10n = Directory(p.join(tempDir.path, 'lib'));
      await l10n.create(recursive: true);
      await File(p.join(l10n.path, 'intl_es_AR.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'intl_pt_BR.arb')).writeAsString('{}');

      final result = await newDetector().detect();

      expect(result.locales, containsAll(['es', 'pt']));
      expect(result.locales, isNot(contains('ar')));
    });

    test('accepts hyphenated BCP-47 codes (zh-Hans, pt-BR)', () async {
      final l10n = Directory(p.join(tempDir.path, 'lib'));
      await l10n.create(recursive: true);
      await File(p.join(l10n.path, 'app_zh-Hans.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'app_pt-BR.arb')).writeAsString('{}');

      final result = await newDetector().detect();

      expect(result.locales, containsAll(['zh', 'pt']));
    });

    test('detects locales from iOS .lproj directories', () async {
      final runner = Directory(p.join(tempDir.path, 'ios', 'Runner'));
      await runner.create(recursive: true);
      await Directory(p.join(runner.path, 'en.lproj')).create(recursive: true);
      await Directory(p.join(runner.path, 'es.lproj')).create(recursive: true);

      final result = await newDetector().detect();

      expect(result.locales, containsAll(['en', 'es']));
      expect(result.findings, isEmpty);
    });

    test('excludes Base.lproj (not a valid Android locale)', () async {
      final runner = Directory(p.join(tempDir.path, 'ios', 'Runner'));
      await runner.create(recursive: true);
      await Directory(p.join(runner.path, 'Base.lproj'))
          .create(recursive: true);
      await Directory(p.join(runner.path, 'en.lproj')).create(recursive: true);

      final result = await newDetector().detect();

      expect(result.locales, ['en']);
      expect(result.locales, isNot(contains('base')));
    });

    test('AR detection takes precedence over .lproj', () async {
      final l10n = Directory(p.join(tempDir.path, 'lib'));
      await l10n.create(recursive: true);
      await File(p.join(l10n.path, 'app_de.arb')).writeAsString('{}');

      final runner = Directory(p.join(tempDir.path, 'ios', 'Runner'));
      await runner.create(recursive: true);
      await Directory(p.join(runner.path, 'fr.lproj')).create(recursive: true);

      final result = await newDetector().detect();

      expect(result.locales, ['de']);
    });

    test('falls back to en and emits a finding when nothing is found',
        () async {
      final result = await newDetector().detect();

      expect(result.locales, ['en']);
      expect(
        result.findings.any((f) => f.id == 'locales_undetected'),
        isTrue,
      );
    });

    test('skips ARB files without locale suffix (template files)', () async {
      final l10n = Directory(p.join(tempDir.path, 'lib'));
      await l10n.create(recursive: true);
      await File(p.join(l10n.path, 'app.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'messages.arb')).writeAsString('{}');

      final result = await newDetector().detect();

      // No locale-bearing ARB found, so fallback + finding.
      expect(result.locales, ['en']);
      expect(
        result.findings.any((f) => f.id == 'locales_undetected'),
        isTrue,
      );
    });

    test('returns sorted, deduplicated locales', () async {
      final l10n = Directory(p.join(tempDir.path, 'lib'));
      await l10n.create(recursive: true);
      await File(p.join(l10n.path, 'app_zh.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'app_en.arb')).writeAsString('{}');
      await File(p.join(l10n.path, 'app_en.arb')).writeAsString('{}');

      final result = await newDetector().detect();

      expect(result.locales, ['en', 'zh']);
    });
  });
}
