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
      logger: const Logger(level: LogLevel.none),
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
      logger: const Logger(level: LogLevel.none),
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
      logger: const Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze(await loadPubspec());

    expect(
      findings.any((f) => f.id == 'over_declared_font_weights'),
      isTrue,
      reason: 'Roboto has three weights declared',
    );
  });
}
