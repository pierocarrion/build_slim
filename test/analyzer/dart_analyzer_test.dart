import 'dart:io';

import 'package:build_slim/src/analyzer/dart_analyzer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dart_analyzer_test_');
    final libDir = Directory(p.join(tempDir.path, 'lib'))..createSync();
    await File(p.join(libDir.path, 'main.dart')).writeAsString('''
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

  test('detects dart:mirrors import', () async {
    final analyzer = DartAnalyzer(
      projectDir: tempDir.path,
      logger: const Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze();

    expect(
      findings.any((f) => f.id == 'dart_mirrors_import'),
      isTrue,
    );
  });

  test('detects unguarded print calls', () async {
    final analyzer = DartAnalyzer(
      projectDir: tempDir.path,
      logger: const Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze();

    expect(
      findings.any((f) => f.id == 'unguarded_print_calls'),
      isTrue,
    );
  });

  test('detects Image.network without cache wrapper', () async {
    final analyzer = DartAnalyzer(
      projectDir: tempDir.path,
      logger: const Logger(level: LogLevel.none),
    );
    final findings = await analyzer.analyze();

    expect(
      findings.any((f) => f.id == 'image_network_without_cache'),
      isTrue,
    );
  });
}
