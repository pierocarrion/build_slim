import 'package:build_slim/src/analyzer/dependency_analyzer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixtureDir = p.absolute('test', 'test_helpers', 'fixture_project');

  test('flags known heavy dependencies', () async {
    final analyzer = DependencyAnalyzer(
      projectDir: fixtureDir,
      logger: const Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze();

    final ids = findings.map((f) => f.id).toSet();
    expect(ids, contains('heavy_dependency_firebase_core'));
    expect(ids, contains('heavy_dependency_google_maps_flutter'));
  });

  test('estimates savings for heavy dependency', () async {
    final analyzer = DependencyAnalyzer(
      projectDir: fixtureDir,
      logger: const Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze();

    final firebase = findings.firstWhere(
      (f) => f.id == 'heavy_dependency_firebase_core',
    );
    expect(firebase.estimatedSavingsBytes, greaterThan(0));
  });
}
