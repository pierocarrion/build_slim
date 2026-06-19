import 'package:build_slim/src/analyzer/project_analyzer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixtureDir = p.join('test', 'test_helpers', 'fixture_project');

  test('loads project name from pubspec.yaml', () async {
    final analyzer = ProjectAnalyzer(
      projectDir: p.absolute(fixtureDir),
      logger: const Logger(level: LogLevel.none),
    );
    final name = await analyzer.projectName();
    expect(name, 'fixture_project');
  });

  test('reports findings for fixture project', () async {
    final analyzer = ProjectAnalyzer(
      projectDir: p.absolute(fixtureDir),
      logger: const Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze();

    final ids = findings.map((f) => f.id).toSet();
    expect(ids, contains('unused_asset'));
    expect(ids, contains('heavy_dependency_firebase_core'));
    expect(ids, contains('heavy_dependency_google_maps_flutter'));
    expect(ids, contains('android_minify_disabled'));
    expect(ids, contains('android_shrink_resources_disabled'));
    expect(ids, contains('android_abi_filters_missing'));
    expect(ids, contains('ios_deployment_target_low'));
  });

  test('throws when pubspec.yaml is missing', () async {
    final analyzer = ProjectAnalyzer(
      projectDir: p.absolute('non_existent_project'),
      logger: const Logger(level: LogLevel.none),
    );
    expect(analyzer.analyze(), throwsA(isA<Exception>()));
  });
}
