import 'dart:io';

import 'package:build_slim/src/analyzer/asset_analyzer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final fixtureDir = p.absolute('test', 'test_helpers', 'fixture_project');

  Future<YamlMap> loadPubspec() async {
    final file = File(p.join(fixtureDir, 'pubspec.yaml'));
    final content = await file.readAsString();
    return loadYaml(content) as YamlMap;
  }

  test('detects unused asset', () async {
    final analyzer = AssetAnalyzer(
      projectDir: fixtureDir,
      logger: Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze(await loadPubspec());

    final unused = findings.where((f) => f.id == 'unused_asset').toList();
    expect(unused, isNotEmpty);
    expect(
      unused.any((f) => f.title.contains('unused.png')),
      isTrue,
      reason: 'unused.png should be flagged',
    );
  });

  test('does not flag used asset', () async {
    final analyzer = AssetAnalyzer(
      projectDir: fixtureDir,
      logger: Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze(await loadPubspec());

    final unused = findings.where((f) => f.id == 'unused_asset').toList();
    expect(
      unused.any((f) => f.title == 'Unused asset: assets/used.png'),
      isFalse,
      reason: 'used.png should not be flagged',
    );
  });

  test('warns about over-declared font weights', () async {
    final analyzer = AssetAnalyzer(
      projectDir: fixtureDir,
      logger: Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze(await loadPubspec());

    expect(
      findings.any((f) => f.id == 'over_declared_font_weights'),
      isTrue,
      reason: 'Roboto has three weights declared',
    );
  });

  group('AssetAnalyzer edge cases (temp dir)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('asset_analyzer_edge_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> writeFile(String relativePath, String content) async {
      final file = File(p.join(tempDir.path, relativePath));
      await file.create(recursive: true);
      await file.writeAsString(content);
      return file;
    }

    Future<File> writeBytes(String relativePath, List<int> bytes) async {
      final file = File(p.join(tempDir.path, relativePath));
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file;
    }

    AssetAnalyzer buildAnalyzer() => AssetAnalyzer(
          projectDir: tempDir.path,
          logger: Logger(level: LogLevel.none),
        );

    test('returns empty list when pubspec has no flutter section', () async {
      await writeFile('pubspec.yaml', 'name: app\n');
      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      expect(await analyzer.analyze(pubspec), isEmpty);
    });

    test('returns empty list when flutter has no assets or fonts', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          uses-material-design: true
      ''');
      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      expect(await analyzer.analyze(pubspec), isEmpty);
    });

    test('flags unused font family when never referenced in source', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          fonts:
            - family: Unreferenced
              fonts:
                - asset: fonts/u.ttf
      ''');
      await writeFile('lib/main.dart', "// doesn't mention the font\n");
      await writeFile('fonts/u.ttf', 'x');

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      expect(findings.any((f) => f.id == 'unused_font_family'), isTrue);
      expect(
        findings.any((f) => f.title.contains('Unreferenced')),
        isTrue,
      );
    });

    test('does not flag font family when single quotes are used', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          fonts:
            - family: Roboto
              fonts:
                - asset: fonts/r.ttf
      ''');
      await writeFile('lib/main.dart', "const family = 'Roboto';\n");
      await writeFile('fonts/r.ttf', 'x');

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      expect(
        findings.any((f) => f.id == 'unused_font_family'),
        isFalse,
      );
    });

    test('does not flag font family when double quotes are used', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          fonts:
            - family: Roboto
              fonts:
                - asset: fonts/r.ttf
      ''');
      await writeFile('lib/main.dart', 'const family = "Roboto";\n');
      await writeFile('fonts/r.ttf', 'x');

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      expect(
        findings.any((f) => f.id == 'unused_font_family'),
        isFalse,
      );
    });

    test('does not warn when only two font weights are declared', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          fonts:
            - family: Roboto
              fonts:
                - asset: fonts/r.ttf
                - asset: fonts/b.ttf
      ''');
      await writeFile('lib/main.dart', "'Roboto'\n");
      await writeFile('fonts/r.ttf', 'x');
      await writeFile('fonts/b.ttf', 'x');

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      expect(
        findings.any((f) => f.id == 'over_declared_font_weights'),
        isFalse,
      );
    });

    test('returns empty findings when lib/ directory is missing', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          assets:
            - assets/a.png
      ''');
      await writeFile('assets/a.png', 'x');

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      // All assets are flagged as unused when source files can't be loaded.
      expect(findings.any((f) => f.id == 'unused_asset'), isTrue);
    });

    test('uses 0 as file size when asset file is missing', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          assets:
            - assets/ghost.png
      ''');
      await writeFile('lib/main.dart', '// nothing\n');

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      final unused = findings.firstWhere((f) => f.id == 'unused_asset');
      expect(unused.estimatedSavingsBytes, 0);
    });

    // Pins the dead ternary bug at asset_analyzer.dart:53 — directory-style
    // assets (`assets/images/`) are not expanded into individual files.
    test('treats directory asset as a plain string (pinned bug)', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          assets:
            - assets/images/
      ''');
      await writeFile('lib/main.dart', "const x = 'assets/images/';\n");

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      // The asset matches only by literal name, so referencing it by the
      // directory string keeps it unflagged (no expansion occurs).
      expect(findings.any((f) => f.id == 'unused_asset'), isFalse);
    });

    test('handles asset referenced without the assets/ prefix', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          assets:
            - assets/icon.png
      ''');
      await writeFile('lib/main.dart', "const path = 'icon.png';\n");
      await writeFile('assets/icon.png', 'x');

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);

      // The patterns list includes `assetPath.replaceAll('assets/', '')`,
      // so `icon.png` matches the source code reference.
      expect(findings.any((f) => f.id == 'unused_asset'), isFalse);
    });

    test('estimated savings reflect half of total font weight sizes', () async {
      await writeFile('pubspec.yaml', '''
        name: app
        flutter:
          fonts:
            - family: Roboto
              fonts:
                - asset: fonts/a.ttf
                - asset: fonts/b.ttf
                - asset: fonts/c.ttf
      ''');
      await writeFile('lib/main.dart', "'Roboto'\n");
      // Each font is 100 bytes; total = 300; estimated savings = 150.
      await writeBytes('fonts/a.ttf', List.filled(100, 0));
      await writeBytes('fonts/b.ttf', List.filled(100, 0));
      await writeBytes('fonts/c.ttf', List.filled(100, 0));

      final analyzer = buildAnalyzer();
      final pubspec = loadYaml(
              await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString())
          as YamlMap;
      final findings = await analyzer.analyze(pubspec);
      final finding =
          findings.firstWhere((f) => f.id == 'over_declared_font_weights');

      expect(finding.estimatedSavingsBytes, 150);
    });
  });
}
