import 'dart:io';

import 'package:build_slim/src/analyzer/native_config_analyzer.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('NativeConfigAnalyzer.normalizeGradle', () {
    final analyzer = NativeConfigAnalyzer(
      projectDir: '.',
      logger: Logger(level: LogLevel.none),
    );

    test('removes single-line comments', () {
      final out = analyzer.normalizeGradle(
        'minifyEnabled = true // comment',
      );
      expect(out.contains('//'), isFalse);
      expect(out, contains('minifyEnabled=true'));
    });

    test('removes block comments', () {
      final out = analyzer.normalizeGradle(
        '/* keep this */ minifyEnabled = true /* trailing */',
      );
      expect(out.contains('/*'), isFalse);
      expect(out.contains('*/'), isFalse);
      expect(out, contains('minifyEnabled=true'));
    });

    test('collapses whitespace around equals sign', () {
      expect(
        analyzer.normalizeGradle('minifyEnabled   =   true'),
        contains('minifyEnabled=true'),
      );
    });

    test('collapses runs of whitespace into single space', () {
      expect(
        analyzer.normalizeGradle('a    b\tc\nd'),
        'a b c d',
      );
    });

    test('passes through content without comments unchanged (modulo ws)', () {
      expect(
        analyzer.normalizeGradle('release { minifyEnabled = true }'),
        'release { minifyEnabled=true }',
      );
    });
  });

  group('NativeConfigAnalyzer.hasGradleBool', () {
    final analyzer = NativeConfigAnalyzer(
      projectDir: '.',
      logger: Logger(level: LogLevel.none),
    );

    test('returns true when key=true present', () {
      expect(
          analyzer.hasGradleBool('minifyEnabled=true', 'minifyEnabled', true),
          isTrue);
    });

    test('returns true when key=false present', () {
      expect(
          analyzer.hasGradleBool(
              'shrinkResources=false', 'shrinkResources', false),
          isTrue);
    });

    test('returns false when key=value not present', () {
      expect(
          analyzer.hasGradleBool('minifyEnabled=false', 'minifyEnabled', true),
          isFalse);
    });

    test('returns false when key entirely absent', () {
      expect(analyzer.hasGradleBool('release { }', 'minifyEnabled', true),
          isFalse);
    });
  });

  group('NativeConfigAnalyzer.parseVersion', () {
    final analyzer = NativeConfigAnalyzer(
      projectDir: '.',
      logger: Logger(level: LogLevel.none),
    );

    test('parses major.minor', () {
      expect(analyzer.parseVersion('12.0'), 12.0);
      expect(analyzer.parseVersion('13.4'), closeTo(13.04, 1e-9));
    });

    test('parses major only (defaults minor to 0)', () {
      expect(analyzer.parseVersion('12'), 12.0);
    });

    test('strips pre-release suffix', () {
      expect(analyzer.parseVersion('12.0-beta'), 12.0);
      expect(analyzer.parseVersion('14.2-rc1'), closeTo(14.02, 1e-9));
    });

    test('parses three-part versions (ignores third component)', () {
      expect(analyzer.parseVersion('12.0.1'), 12.0);
    });

    test('handles non-numeric components as 0', () {
      expect(analyzer.parseVersion('abc.def'), 0.0);
    });

    // Pinned behavior: minor/100 produces non-monotonic comparisons for
    // minor >= 100. This test documents the current limitation.
    test('minor/100 has non-monotonic behavior for minor >= 100', () {
      // 12.30 should be > 12.0 mathematically, but minor/100 yields 0.30.
      expect(analyzer.parseVersion('12.30'), closeTo(12.3, 1e-9));
      // 12.100 collapses to 12 + 100/100 = 13.0 (bug).
      expect(analyzer.parseVersion('12.100'), 13.0);
    });
  });

  group('NativeConfigAnalyzer.analyze Android', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('native_analyzer_android');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> writeAndroidFile(String content,
        {String filename = 'build.gradle'}) async {
      final file = File(p.join(tempDir.path, 'android', 'app', filename));
      await file.create(recursive: true);
      await file.writeAsString(content);
    }

    test('returns no findings when gradle has all settings correct', () async {
      await writeAndroidFile('''
        release {
          minifyEnabled = true
          shrinkResources = true
          abiFilters 'arm64-v8a'
        }
      ''');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      final ids = findings.map((f) => f.id).toSet();
      expect(ids, isNot(contains('android_minify_disabled')));
      expect(ids, isNot(contains('android_shrink_resources_disabled')));
      expect(ids, isNot(contains('android_abi_filters_missing')));
    });

    test('flags minifyEnabled, shrinkResources and abiFilters when missing',
        () async {
      await writeAndroidFile('''
        release {
          minifyEnabled false
          shrinkResources false
        }
      ''');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      final ids = findings.map((f) => f.id).toSet();

      expect(
          ids,
          containsAll([
            'android_minify_disabled',
            'android_shrink_resources_disabled',
            'android_abi_filters_missing',
          ]));
    });

    test('respects Kotlin DSL build.gradle.kts path', () async {
      await writeAndroidFile('''
        release {
          minifyEnabled = true
          shrinkResources = true
          ndk.abiFilters 'arm64-v8a'
        }
      ''', filename: 'build.gradle.kts');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      // The Kotlin DSL file is found via the second gradlePaths candidate.
      expect(findings, isEmpty);
    });

    test('recognizes Kotlin is-prefixed property names as enabled', () async {
      await writeAndroidFile('''
        release {
          isMinifyEnabled = true
          isShrinkResources = true
          abiFilters 'arm64-v8a'
        }
      ''', filename: 'build.gradle.kts');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      final ids = findings.map((f) => f.id).toSet();
      expect(ids, isNot(contains('android_minify_disabled')));
      expect(ids, isNot(contains('android_shrink_resources_disabled')));
    });

    test('flags is-prefixed properties when set to false', () async {
      await writeAndroidFile('''
        release {
          isMinifyEnabled = false
          isShrinkResources = false
          abiFilters 'arm64-v8a'
        }
      ''', filename: 'build.gradle.kts');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      final ids = findings.map((f) => f.id).toSet();

      expect(ids, contains('android_minify_disabled'));
      expect(ids, contains('android_shrink_resources_disabled'));
    });

    // Pins the current Groovy-syntax limitation: when `minifyEnabled true` is
    // written without an explicit `=`, the analyzer treats it as disabled.
    test('treats Groovy `minifyEnabled true` (no `=`) as disabled (pinned bug)',
        () async {
      await writeAndroidFile('''
        release {
          minifyEnabled true
          shrinkResources true
          abiFilters 'arm64-v8a'
        }
      ''');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      final ids = findings.map((f) => f.id).toSet();

      expect(ids, contains('android_minify_disabled'));
      expect(ids, contains('android_shrink_resources_disabled'));
    });

    test('returns empty list when no gradle file exists', () async {
      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      expect(findings, isEmpty);
    });

    test('flags extractNativeLibs=false in AndroidManifest', () async {
      await writeAndroidFile('''
        release { minifyEnabled true shrinkResources true abiFilters 'a' }
      ''');
      final manifest = File(p.join(tempDir.path, 'android', 'app', 'src',
          'main', 'AndroidManifest.xml'));
      await manifest.create(recursive: true);
      await manifest.writeAsString('''
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
          <application android:extractNativeLibs="false" />
        </manifest>
      ''');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      expect(
        findings.any((f) => f.id == 'android_extract_native_libs_false'),
        isTrue,
      );
    });

    test('does not flag extractNativeLibs when not set to false', () async {
      await writeAndroidFile('''
        release { minifyEnabled true shrinkResources true abiFilters 'a' }
      ''');
      final manifest = File(p.join(tempDir.path, 'android', 'app', 'src',
          'main', 'AndroidManifest.xml'));
      await manifest.create(recursive: true);
      await manifest.writeAsString('<application android:label="hi" />');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      expect(
        findings.any((f) => f.id == 'android_extract_native_libs_false'),
        isFalse,
      );
    });

    test('findings have correct severity and savings estimates', () async {
      await writeAndroidFile('release { minifyEnabled false }');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      final minify =
          findings.firstWhere((f) => f.id == 'android_minify_disabled');

      expect(minify.severity, FindingSeverity.warning);
      expect(minify.estimatedSavingsBytes, 2 * 1024 * 1024);
      expect(minify.recommendation, isNotNull);
    });
  });

  group('NativeConfigAnalyzer.analyze iOS', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('native_analyzer_ios');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> writePodfile(String content) async {
      final file = File(p.join(tempDir.path, 'ios', 'Podfile'));
      await file.create(recursive: true);
      await file.writeAsString(content);
    }

    Future<void> writeXcconfig(String content) async {
      final file =
          File(p.join(tempDir.path, 'ios', 'Flutter', 'Release.xcconfig'));
      await file.create(recursive: true);
      await file.writeAsString(content);
    }

    test('flags deployment target below 12.0', () async {
      await writePodfile("platform :ios, '11.0'\n");

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) => f.id == 'ios_deployment_target_low'),
        isTrue,
      );
    });

    test('does not flag deployment target equal to 12.0', () async {
      await writePodfile("platform :ios, '12.0'\n");

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) =>
            f.id == 'ios_deployment_target_low' ||
            f.id == 'ios_deployment_target_missing'),
        isFalse,
      );
    });

    test('does not flag deployment target above 12.0', () async {
      await writePodfile("platform :ios, '13.0'\n");

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) => f.id == 'ios_deployment_target_low'),
        isFalse,
      );
    });

    test('accepts double-quoted platform version', () async {
      await writePodfile('platform :ios, "11.0"\n');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) => f.id == 'ios_deployment_target_low'),
        isTrue,
      );
    });

    test('flags missing platform line', () async {
      await writePodfile('# no platform here\ntarget Runner do\nend\n');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) => f.id == 'ios_deployment_target_missing'),
        isTrue,
      );
    });

    test('flags bitcode enabled when ENABLE_BITCODE=NO is missing', () async {
      await writePodfile("platform :ios, '13.0'\n");
      await writeXcconfig('#include? Generated.xcconfig\n');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) => f.id == 'ios_bitcode_enabled'),
        isTrue,
      );
    });

    test('does not flag bitcode when ENABLE_BITCODE=NO is present', () async {
      await writePodfile("platform :ios, '13.0'\n");
      await writeXcconfig('ENABLE_BITCODE=NO\n');

      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) => f.id == 'ios_bitcode_enabled'),
        isFalse,
      );
    });

    test('returns empty list when Podfile is missing', () async {
      final analyzer = NativeConfigAnalyzer(
          projectDir: tempDir.path, logger: Logger(level: LogLevel.none));
      final findings = await analyzer.analyze();
      expect(findings, isEmpty);
    });
  });
}
