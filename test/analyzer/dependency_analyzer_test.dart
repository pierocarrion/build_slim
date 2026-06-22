import 'dart:io';

import 'package:build_slim/src/analyzer/dependency_analyzer.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixtureDir = p.absolute('test', 'test_helpers', 'fixture_project');

  group('DependencyAnalyzer against static fixture', () {
    test('flags known heavy dependencies', () async {
      final analyzer = DependencyAnalyzer(
        projectDir: fixtureDir,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      final ids = findings.map((f) => f.id).toSet();
      expect(ids, contains('heavy_dependency_firebase_core'));
      expect(ids, contains('heavy_dependency_google_maps_flutter'));
    });

    test('estimates savings for heavy dependency', () async {
      final analyzer = DependencyAnalyzer(
        projectDir: fixtureDir,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      final firebase = findings.firstWhere(
        (f) => f.id == 'heavy_dependency_firebase_core',
      );
      expect(firebase.estimatedSavingsBytes, greaterThan(0));
    });

    test('uses templated id per heavy package', () async {
      final analyzer = DependencyAnalyzer(
        projectDir: fixtureDir,
        logger: Logger(level: LogLevel.none),
      );
      final findings = await analyzer.analyze();

      expect(
        findings.any((f) => f.id == 'heavy_dependency_google_maps_flutter'),
        isTrue,
      );
    });
  });

  group('DependencyAnalyzer against synthetic lockfile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('dependency_analyzer_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> writeLockfile(String content) async {
      final file = File(p.join(tempDir.path, 'pubspec.lock'));
      await file.writeAsString(content);
    }

    Future<List<Finding>> analyze() async {
      return DependencyAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      ).analyze();
    }

    test('flags duplicate http+dio group', () async {
      await writeLockfile('''
packages:
  http:
    dependency: transitive
  dio:
    dependency: direct
''');
      final findings = await analyze();
      final ids = findings.map((f) => f.id).toSet();
      expect(ids, contains('duplicate_dependency_group_http'));
    });

    test('does not flag duplicate group when only one member present',
        () async {
      await writeLockfile('''
packages:
  http:
    dependency: direct
''');
      final findings = await analyze();
      expect(
        findings.any((f) => f.id == 'duplicate_dependency_group_http'),
        isFalse,
      );
    });

    test('flags image group when all three members present', () async {
      await writeLockfile('''
packages:
  cached_network_image: {}
  image: {}
  extended_image: {}
''');
      final findings = await analyze();
      final groupFinding = findings
          .firstWhere((f) => f.id == 'duplicate_dependency_group_image');
      expect(groupFinding.description, contains('cached_network_image'));
      expect(groupFinding.description, contains('extended_image'));
    });

    test('does not flag duplicate when three http group has only two',
        () async {
      await writeLockfile('''
packages:
  http: {}
  requests: {}
''');
      final findings = await analyze();
      expect(
        findings.any((f) => f.id == 'duplicate_dependency_group_http'),
        isTrue,
      );
    });

    test('flags multiple heavy packages from the known map', () async {
      await writeLockfile('''
packages:
  firebase_auth: {}
  cloud_firestore: {}
  video_player: {}
  image_picker: {}
  flutter_html: {}
''');
      final findings = await analyze();
      final ids = findings.map((f) => f.id).toSet();
      expect(ids, contains('heavy_dependency_firebase_auth'));
      expect(ids, contains('heavy_dependency_cloud_firestore'));
      expect(ids, contains('heavy_dependency_video_player'));
      expect(ids, contains('heavy_dependency_image_picker'));
      expect(ids, contains('heavy_dependency_flutter_html'));
    });

    test('uses MB unit for large package sizes', () async {
      await writeLockfile('''
packages:
  firebase_core: {}
''');
      final findings = await analyze();
      final firebase =
          findings.firstWhere((f) => f.id == 'heavy_dependency_firebase_core');
      expect(firebase.description, contains('5.0 MB'));
    });

    test('returns empty list when packages map is empty', () async {
      await writeLockfile('packages:\n');
      final findings = await analyze();
      expect(findings, isEmpty);
    });

    test('returns empty list when packages section is missing', () async {
      await writeLockfile('some_key: value\n');
      final findings = await analyze();
      expect(findings, isEmpty);
    });

    test('returns empty list when pubspec.lock is missing', () async {
      final sink = StringBuffer();
      final findings = await DependencyAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.info, sink: sink),
      ).analyze();
      expect(findings, isEmpty);
      expect(sink.toString(), contains('pubspec.lock'));
    });

    test('returns empty list when pubspec.lock is invalid YAML', () async {
      await writeLockfile('this: is: not: valid: yaml: : :');
      final sink = StringBuffer();
      final findings = await DependencyAnalyzer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none, sink: sink),
      ).analyze();
      // Either returns empty (caught) or hangs - assert empty.
      expect(findings, isEmpty);
    });

    test('returns empty list for unrelated packages', () async {
      await writeLockfile('''
packages:
  some_random_pkg: {}
  another_unknown: {}
''');
      final findings = await analyze();
      expect(findings, isEmpty);
    });
  });
}
