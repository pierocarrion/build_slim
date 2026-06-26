import 'dart:io';

import 'package:build_slim/src/analyzer/asset_analyzer.dart';
import 'package:build_slim/src/analyzer/dependency_analyzer.dart';
import 'package:build_slim/src/analyzer/native_config_analyzer.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('advanced_analyzers');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AssetAnalyzer GIF audit (#6)', () {
    test('flags heavy GIFs above 300KB as critical', () async {
      final assets = Directory(p.join(tempDir.path, 'assets'));
      await assets.create(recursive: true);
      final gif = File(p.join(assets.path, 'loading.gif'));
      await gif.create(recursive: true);
      gif.writeAsBytesSync(List<int>.filled(400 * 1024, 0));

      final analyzer = AssetAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze(_emptyPubspec());

      final heavy = findings.where((f) => f.id == 'heavy_gif').toList();
      expect(heavy, hasLength(1));
      expect(heavy.first.severity, FindingSeverity.critical);
      expect(heavy.first.recommendation, contains('Lottie'));
    });

    test('does not flag small GIFs', () async {
      final assets = Directory(p.join(tempDir.path, 'assets'));
      await assets.create(recursive: true);
      final gif = File(p.join(assets.path, 'small.gif'));
      await gif.create(recursive: true);
      gif.writeAsBytesSync(List<int>.filled(100 * 1024, 0));

      final analyzer = AssetAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze(_emptyPubspec());

      expect(findings.where((f) => f.id == 'heavy_gif'), isEmpty);
    });

    test('does not flag heavy non-GIF assets via the GIF check', () async {
      final assets = Directory(p.join(tempDir.path, 'assets'));
      await assets.create(recursive: true);
      final png = File(p.join(assets.path, 'big.png'));
      await png.create(recursive: true);
      png.writeAsBytesSync(List<int>.filled(2 * 1024 * 1024, 0));

      final analyzer = AssetAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze(_emptyPubspec());

      expect(findings.where((f) => f.id == 'heavy_gif'), isEmpty);
    });
  });

  group('AssetAnalyzer font subsetting (#5)', () {
    test('flags large TTF fonts above 200KB', () async {
      final fontsDir = Directory(p.join(tempDir.path, 'fonts'));
      await fontsDir.create(recursive: true);
      final font = File(p.join(fontsDir.path, 'Roboto.ttf'));
      await font.create(recursive: true);
      font.writeAsBytesSync(List<int>.filled(500 * 1024, 0));
      // Reference the font family so it is not flagged as unused.
      final lib = Directory(p.join(tempDir.path, 'lib'));
      await lib.create(recursive: true);
      await File(p.join(lib.path, 'main.dart'))
          .writeAsString("Text('x', style: TextStyle(fontFamily: 'Roboto'))");

      final analyzer = AssetAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze(_pubspecWithFont());

      final large = findings.where((f) => f.id == 'large_font_file').toList();
      expect(large, hasLength(1));
      expect(large.first.severity, FindingSeverity.warning);
      expect(large.first.recommendation, contains('pyftsubset'));
    });

    test('does not flag small fonts', () async {
      final fontsDir = Directory(p.join(tempDir.path, 'fonts'));
      await fontsDir.create(recursive: true);
      final font = File(p.join(fontsDir.path, 'Roboto.ttf'));
      await font.create(recursive: true);
      font.writeAsBytesSync(List<int>.filled(50 * 1024, 0));
      final lib = Directory(p.join(tempDir.path, 'lib'));
      await lib.create(recursive: true);
      await File(p.join(lib.path, 'main.dart'))
          .writeAsString("fontFamily: 'Roboto'");

      final analyzer = AssetAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze(_pubspecWithFont());

      expect(findings.where((f) => f.id == 'large_font_file'), isEmpty);
    });
  });

  group('NativeConfigAnalyzer target-aware extractNativeLibs (#7)', () {
    Future<File> writeGradle() async {
      final file = File(p.join(tempDir.path, 'android', 'app', 'build.gradle'));
      await file.create(recursive: true);
      await file.writeAsString('''
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            abiFilters 'arm64-v8a'
        }
    }
}
''');
      return file;
    }

    Future<File> writeManifest({required bool extractFalse}) async {
      final file = File(p.join(tempDir.path, 'android', 'app', 'src', 'main',
          'AndroidManifest.xml'));
      await file.create(recursive: true);
      await file.writeAsString(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application android:label="x" '
        '${extractFalse ? 'android:extractNativeLibs="false"' : ''} />\n'
        '</manifest>\n',
      );
      return file;
    }

    test('AAB target recommends extractNativeLibs=false when absent', () async {
      await writeGradle();
      await writeManifest(extractFalse: false);
      final analyzer = NativeConfigAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
        target: BuildTarget.aab,
      );
      final findings = await analyzer.analyze();
      expect(
        findings
            .any((f) => f.id == 'android_extract_native_libs_should_be_false'),
        isTrue,
      );
      expect(
        findings.any((f) => f.id == 'android_extract_native_libs_false'),
        isFalse,
      );
    });

    test('AAB target does not warn when extractNativeLibs=false present',
        () async {
      await writeGradle();
      await writeManifest(extractFalse: true);
      final analyzer = NativeConfigAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
        target: BuildTarget.aab,
      );
      final findings = await analyzer.analyze();
      expect(
        findings
            .any((f) => f.id == 'android_extract_native_libs_should_be_false'),
        isFalse,
      );
      expect(
        findings.any((f) => f.id == 'android_extract_native_libs_false'),
        isFalse,
      );
    });

    test('APK target warns when extractNativeLibs=false present (legacy)',
        () async {
      await writeGradle();
      await writeManifest(extractFalse: true);
      final analyzer = NativeConfigAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
        target: BuildTarget.apk,
      );
      final findings = await analyzer.analyze();
      expect(
        findings.any((f) => f.id == 'android_extract_native_libs_false'),
        isTrue,
      );
    });

    test('null target preserves the legacy warning (backwards compat)',
        () async {
      await writeGradle();
      await writeManifest(extractFalse: true);
      final analyzer = NativeConfigAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();
      expect(
        findings.any((f) => f.id == 'android_extract_native_libs_false'),
        isTrue,
      );
    });
  });

  group('NativeConfigAnalyzer R8 full mode audit', () {
    test('flags R8 full mode disabled as breaking finding', () async {
      final file = File(p.join(tempDir.path, 'android', 'gradle.properties'));
      await file.create(recursive: true);
      await file.writeAsString('org.gradle.jvmargs=-Xmx\n');

      final analyzer = NativeConfigAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      final r8 =
          findings.firstWhere((f) => f.id == 'android_r8_full_mode_disabled');
      expect(r8.severity, FindingSeverity.warning);
      expect(r8.breaking, isTrue);
    });

    test('does not flag when R8 full mode is already enabled', () async {
      final file = File(p.join(tempDir.path, 'android', 'gradle.properties'));
      await file.create(recursive: true);
      await file.writeAsString('android.enableR8.fullMode=true\n');

      final analyzer = NativeConfigAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();
      expect(findings.where((f) => f.id == 'android_r8_full_mode_disabled'),
          isEmpty);
    });

    test('flags R8 full mode when only present in a comment', () async {
      final file = File(p.join(tempDir.path, 'android', 'gradle.properties'));
      await file.create(recursive: true);
      await file.writeAsString(
          '# android.enableR8.fullMode=true\norg.gradle.jvmargs=-Xmx\n');

      final analyzer = NativeConfigAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();
      expect(
        findings.any((f) => f.id == 'android_r8_full_mode_disabled'),
        isTrue,
      );
    });
  });

  group('DependencyAnalyzer deferred import audit (#8)', () {
    test('suggests deferred import for heavy package imported eagerly',
        () async {
      // pubspec.lock with video_player.
      final lockFile = File(p.join(tempDir.path, 'pubspec.lock'));
      await lockFile.writeAsString('''
packages:
  video_player:
    dependency: "direct main"
    source: hosted
    version: "2.9.3"
''');
      final lib = Directory(p.join(tempDir.path, 'lib'));
      await lib.create(recursive: true);
      await File(p.join(lib.path, 'main.dart')).writeAsString(
        "import 'package:video_player/video_player.dart';\n"
        "void main() {}\n",
      );

      final analyzer = DependencyAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      final deferred =
          findings.where((f) => f.id == 'deferred_candidate_video_player');
      expect(deferred, isNotEmpty);
      expect(deferred.first.severity, FindingSeverity.info);
      expect(deferred.first.recommendation, contains('deferred'));
    });

    test('does not suggest deferred for already-deferred imports', () async {
      final lockFile = File(p.join(tempDir.path, 'pubspec.lock'));
      await lockFile.writeAsString('''
packages:
  video_player:
    dependency: "direct main"
    source: hosted
    version: "2.9.3"
''');
      final lib = Directory(p.join(tempDir.path, 'lib'));
      await lib.create(recursive: true);
      await File(p.join(lib.path, 'main.dart')).writeAsString(
        "import 'package:video_player/video_player.dart' deferred as vp;\n",
      );

      final analyzer = DependencyAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      expect(
        findings.where((f) => f.id == 'deferred_candidate_video_player'),
        isEmpty,
      );
    });

    test('does not suggest deferred when package is not heavy', () async {
      final lockFile = File(p.join(tempDir.path, 'pubspec.lock'));
      await lockFile.writeAsString('''
packages:
  http:
    dependency: "direct main"
    source: hosted
    version: "1.0.0"
''');
      final lib = Directory(p.join(tempDir.path, 'lib'));
      await lib.create(recursive: true);
      await File(p.join(lib.path, 'main.dart'))
          .writeAsString("import 'package:http/http.dart';\n");

      final analyzer = DependencyAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      expect(
        findings.where((f) => f.id.startsWith('deferred_candidate_')),
        isEmpty,
      );
    });
  });
}

YamlMap _emptyPubspec() => loadYaml('name: x\n') as YamlMap;

YamlMap _pubspecWithFont() => loadYaml('''
name: x
flutter:
  fonts:
    - family: Roboto
      fonts:
        - asset: fonts/Roboto.ttf
''') as YamlMap;
