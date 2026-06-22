import 'dart:io';

import 'package:build_slim/src/analyzer/project_analyzer.dart';
import 'package:build_slim/src/builder/artifact_comparator.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixtureDir = p.join('test', 'test_helpers', 'fixture_project');

  group('ProjectAnalyzer against static fixture', () {
    test('loads project name from pubspec.yaml', () async {
      final analyzer = ProjectAnalyzer(
        projectDir: p.absolute(fixtureDir),
        logger: Logger(level: LogLevel.none),
      );
      final name = await analyzer.projectName();
      expect(name, 'fixture_project');
    });

    test('reports findings for fixture project', () async {
      final analyzer = ProjectAnalyzer(
        projectDir: p.absolute(fixtureDir),
        logger: Logger(level: LogLevel.none),
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

    test('runs all sub-analyzers in canonical order', () async {
      final analyzer = ProjectAnalyzer(
        projectDir: p.absolute(fixtureDir),
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      // Asset findings come first, then dependency, then native, then dart.
      final firstAssetIdx = findings.indexWhere((f) => f.id == 'unused_asset');
      final firstDepIdx =
          findings.indexWhere((f) => f.id == 'heavy_dependency_firebase_core');
      final firstNativeIdx =
          findings.indexWhere((f) => f.id == 'android_minify_disabled');

      expect(firstAssetIdx, greaterThanOrEqualTo(0));
      expect(firstDepIdx, greaterThan(firstAssetIdx));
      expect(firstNativeIdx, greaterThan(firstDepIdx));
    });
  });

  group('ProjectAnalyzer error handling', () {
    test('throws BuildOptimizerException when pubspec.yaml is missing',
        () async {
      final analyzer = ProjectAnalyzer(
        projectDir: p.absolute('non_existent_project'),
        logger: Logger(level: LogLevel.none),
      );
      await expectLater(
        analyzer.analyze(),
        throwsA(
          isA<BuildOptimizerException>()
              .having((e) => e.message, 'message', contains('pubspec.yaml'))
              .having((e) => e.filePath, 'filePath', isNotNull),
        ),
      );
    });

    test('throws BuildOptimizerException with filePath populated', () async {
      final dir = await Directory.systemTemp.createTemp('project_analyzer');
      try {
        final analyzer = ProjectAnalyzer(
          projectDir: dir.path,
          logger: Logger(level: LogLevel.none),
        );
        await expectLater(
          analyzer.analyze(),
          throwsA(
            isA<BuildOptimizerException>().having(
                (e) => e.filePath, 'filePath', contains('pubspec.yaml')),
          ),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throws BuildOptimizerException when pubspec is not a YAML map',
        () async {
      final dir = await Directory.systemTemp.createTemp('not_a_map');
      try {
        await File(p.join(dir.path, 'pubspec.yaml'))
            .writeAsString('- just\n- a\n- list\n');
        final analyzer = ProjectAnalyzer(
          projectDir: dir.path,
          logger: Logger(level: LogLevel.none),
        );
        await expectLater(
          analyzer.analyze(),
          throwsA(
            isA<BuildOptimizerException>().having(
                (e) => e.message, 'message', contains('not a valid YAML map')),
          ),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('ProjectAnalyzer.projectName', () {
    test('returns "unknown" when name is not a string', () async {
      final dir = await Directory.systemTemp.createTemp('no_name');
      try {
        await File(p.join(dir.path, 'pubspec.yaml')).writeAsString('''
description: only description
''');
        final analyzer = ProjectAnalyzer(
          projectDir: dir.path,
          logger: Logger(level: LogLevel.none),
        );
        expect(await analyzer.projectName(), 'unknown');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns the declared name when present', () async {
      final dir = await Directory.systemTemp.createTemp('with_name');
      try {
        await File(p.join(dir.path, 'pubspec.yaml')).writeAsString('''
name: my_awesome_app
''');
        final analyzer = ProjectAnalyzer(
          projectDir: dir.path,
          logger: Logger(level: LogLevel.none),
        );
        expect(await analyzer.projectName(), 'my_awesome_app');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
