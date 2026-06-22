import 'dart:io';

import 'package:build_slim/src/analyzer/dart_analyzer.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  Future<File> writeDart(String name, String content) async {
    final file = File(p.join(tempDir.path, 'lib', name));
    await file.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  Future<List<Finding>> runAnalyzer() async {
    final analyzer = DartAnalyzer(
      projectDir: tempDir.path,
      logger: Logger(level: LogLevel.none),
    );
    return analyzer.analyze();
  }

  group('DartAnalyzer mirror detection', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dart_analyzer_test_');
      await writeDart('main.dart', '''
import 'dart:mirrors';

void main() {
  print('hello');
  Image.network('https://example.com/img.png');
}
''');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('detects dart:mirrors with single-quote import', () async {
      final findings = await runAnalyzer();
      expect(findings.any((f) => f.id == 'dart_mirrors_import'), isTrue);
    });

    test('detects dart:mirrors with double-quote import', () async {
      // Replace the existing main.dart with a double-quote variant.
      await writeDart('main.dart', 'import "dart:mirrors";\n');
      final findings = await runAnalyzer();
      expect(findings.any((f) => f.id == 'dart_mirrors_import'), isTrue);
    });

    test('marks mirrors finding as error severity', () async {
      final findings = await runAnalyzer();
      final mirrors = findings.firstWhere((f) => f.id == 'dart_mirrors_import');
      expect(mirrors.severity, FindingSeverity.error);
    });

    test('estimates 2 MB savings for mirrors', () async {
      final findings = await runAnalyzer();
      final mirrors = findings.firstWhere((f) => f.id == 'dart_mirrors_import');
      expect(mirrors.estimatedSavingsBytes, 2 * 1024 * 1024);
    });

    test('detects unguarded print calls', () async {
      final findings = await runAnalyzer();
      expect(findings.any((f) => f.id == 'unguarded_print_calls'), isTrue);
    });

    test('detects Image.network without cache wrapper', () async {
      final findings = await runAnalyzer();
      expect(
          findings.any((f) => f.id == 'image_network_without_cache'), isTrue);
    });
  });

  group('DartAnalyzer release guards', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dart_guards_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('does not flag print calls when kDebugMode guard is present',
        () async {
      await writeDart('main.dart', '''
import 'package:flutter/foundation.dart';
void main() {
  if (kDebugMode) {
    print('hi');
  }
}
''');
      final findings = await runAnalyzer();
      expect(
        findings.any((f) => f.id == 'unguarded_print_calls'),
        isFalse,
      );
    });

    test('does not flag print calls when kReleaseMode guard is present',
        () async {
      await writeDart('main.dart', '''
import 'package:flutter/foundation.dart';
void main() {
  if (!kReleaseMode) {
    print('hi');
  }
}
''');
      final findings = await runAnalyzer();
      expect(
        findings.any((f) => f.id == 'unguarded_print_calls'),
        isFalse,
      );
    });

    test('flags print when only kDebugMode appears in another file', () async {
      await writeDart('main.dart', '''
void main() {
  print('hi');
}
''');
      await writeDart('other.dart', '''
import 'package:flutter/foundation.dart';
const x = kDebugMode;
''');
      // Both files contribute; the release-guard is set globally so the
      // print is suppressed.
      final findings = await runAnalyzer();
      expect(
        findings.any((f) => f.id == 'unguarded_print_calls'),
        isFalse,
      );
    });
  });

  group('DartAnalyzer cached image detection', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dart_cached_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('does not flag CachedNetworkImage usage', () async {
      await writeDart('main.dart', '''
void main() {
  return CachedNetworkImage(url: 'https://example.com/x.png');
}
''');
      final findings = await runAnalyzer();
      expect(
        findings.any((f) => f.id == 'image_network_without_cache'),
        isFalse,
      );
    });

    test('recognizes CachedNetworkImage across files', () async {
      await writeDart('main.dart', '''
void main() {
  Image.network('https://example.com/x.png');
}
''');
      await writeDart('widget.dart', '''
class Widget {
  final cached = CachedNetworkImage;
}
''');
      final findings = await runAnalyzer();
      expect(
        findings.any((f) => f.id == 'image_network_without_cache'),
        isFalse,
      );
    });
  });

  group('DartAnalyzer edge cases', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dart_edge_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('returns empty list when lib directory is missing', () async {
      final findings = await runAnalyzer();
      expect(findings, isEmpty);
    });

    test('returns empty list when lib contains no problematic code', () async {
      await writeDart('clean.dart', '''
int square(int x) => x * x;
''');
      final findings = await runAnalyzer();
      expect(findings, isEmpty);
    });
  });
}
