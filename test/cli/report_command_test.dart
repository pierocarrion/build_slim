import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_slim/src/cli/report_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String beforePath;
  late String afterPath;
  late StringBuffer sink;
  late CommandRunner<int> runner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('report_command_test');
    beforePath = '${tempDir.path}/before.apk';
    afterPath = '${tempDir.path}/after.apk';
    await File(beforePath).writeAsBytes(List.filled(2000, 0));
    await File(afterPath).writeAsBytes(List.filled(1000, 0));
    sink = StringBuffer();
    final command = ReportCommand(loggerSink: sink);
    runner = CommandRunner<int>('build_slim', 'test')..addCommand(command);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ReportCommand flag validation', () {
    test('returns 1 when --before is missing', () async {
      final code = await runner.run(['report', '--after', afterPath]);
      expect(code, 1);
      expect(sink.toString(), contains('required'));
    });

    test('returns 1 when --after is missing', () async {
      final code = await runner.run(['report', '--before', beforePath]);
      expect(code, 1);
      expect(sink.toString(), contains('required'));
    });

    test('returns 1 when both --before and --after are missing', () async {
      final code = await runner.run(['report']);
      expect(code, 1);
      expect(sink.toString(), contains('required'));
    });
  });

  group('ReportCommand happy path', () {
    test('returns 0 and prints console report when both files exist', () async {
      final printed = <String>[];
      final code = await _capturePrintWithResult<int?>(() async {
        return await runner
            .run(['report', '--before', beforePath, '--after', afterPath]);
      }, printed);
      expect(code, 0);
      expect(printed.join('\n'), contains('artifact-comparison'));
      expect(printed.join('\n'), contains('Before:'));
      expect(printed.join('\n'), contains('After:'));
    });

    test('emits JSON report with --format json', () async {
      final printed = <String>[];
      await _capturePrint(() async {
        await runner.run([
          'report',
          '--before',
          beforePath,
          '--after',
          afterPath,
          '--format',
          'json',
        ]);
      }, printed);
      final decoded =
          jsonDecode(printed.join('\n').trim()) as Map<String, dynamic>;
      expect(decoded['projectName'], 'artifact-comparison');
      expect(decoded['beforeSizeBytes'], 2000);
      expect(decoded['afterSizeBytes'], 1000);
    });

    test('emits HTML report with --format html', () async {
      final printed = <String>[];
      await _capturePrint(() async {
        await runner.run([
          'report',
          '--before',
          beforePath,
          '--after',
          afterPath,
          '--format',
          'html',
        ]);
      }, printed);
      final html = printed.join('\n');
      expect(html, contains('<!DOCTYPE html>'));
    });

    test('writes the report to --output file', () async {
      final out = '${tempDir.path}/out.txt';
      final code = await runner.run([
        'report',
        '--before',
        beforePath,
        '--after',
        afterPath,
        '--output',
        out,
      ]);
      expect(code, 0);
      final written = await File(out).readAsString();
      expect(written, contains('artifact-comparison'));
      expect(sink.toString(), contains('Report written'));
    });
  });

  group('ReportCommand verbose flag', () {
    test('accepts --verbose without error', () async {
      final code = await runner.run([
        'report',
        '--before',
        beforePath,
        '--after',
        afterPath,
        '--verbose',
      ]);
      expect(code, 0);
    });
  });
}

Future<void> _capturePrint(
    Future<void> Function() body, List<String> out) async {
  final spec = ZoneSpecification(print: (_, __, ___, line) {
    out.add(line);
  });
  await runZoned(body, zoneSpecification: spec);
}

Future<T> _capturePrintWithResult<T>(
    Future<T> Function() body, List<String> out) async {
  final spec = ZoneSpecification(print: (_, __, ___, line) {
    out.add(line);
  });
  return await runZoned(body, zoneSpecification: spec);
}
