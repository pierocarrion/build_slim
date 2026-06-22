import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_slim/src/cli/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end tests that exercise the real CLI surface, including the real
/// `dart --version` and `flutter --version` probes. These tests run the
/// static fixture project shipped with the test suite in analyze-only mode
/// (no real Flutter build is performed).
void main() {
  late String fixtureDir;
  late BuildSlimRunner runner;

  setUp(() {
    fixtureDir = p.absolute(p.joinAll([
      'test',
      'test_helpers',
      'fixture_project',
    ]));
    runner = BuildSlimRunner();
  });

  group('End-to-end optimize --analyze-only', () {
    test('returns 0 against the fixture project', () async {
      final code = await runner.run([
        'optimize',
        '--analyze-only',
        '--project-dir',
        fixtureDir,
      ]);
      expect(code, 0);
    });

    test('prints a report containing findings for the fixture project',
        () async {
      final printed = <String>[];
      final code = await _capturePrintWithResult<int?>(() async {
        return await runner.run([
          'optimize',
          '--analyze-only',
          '--project-dir',
          fixtureDir,
        ]);
      }, printed);
      expect(code, 0);

      final output = printed.join('\n');
      expect(output, contains('Build Slim Report'));
      expect(output, contains('fixture_project'));
      // The fixture intentionally declares unused assets and heavy deps.
      expect(output, contains('unused_asset'));
      expect(output, contains('heavy_dependency'));
    });

    test('emits valid JSON with --report json', () async {
      final printed = <String>[];
      await _capturePrintWithResult<int?>(() async {
        return await runner.run([
          'optimize',
          '--analyze-only',
          '--project-dir',
          fixtureDir,
          '--report',
          'json',
        ]);
      }, printed);

      final decoded =
          jsonDecode(printed.join('\n').trim()) as Map<String, dynamic>;
      expect(decoded['projectName'], 'fixture_project');
      expect(decoded['target'], 'apk');
      expect(decoded['findings'], isA<List>());
      final findings = decoded['findings'] as List;
      final firstFinding = findings.first as Map<String, dynamic>;
      expect(firstFinding['id'], isA<String>());
    });

    test('emits a full HTML document with --report html', () async {
      final printed = <String>[];
      await _capturePrintWithResult<int?>(() async {
        return await runner.run([
          'optimize',
          '--analyze-only',
          '--project-dir',
          fixtureDir,
          '--report',
          'html',
        ]);
      }, printed);

      final html = printed.join('\n');
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('fixture_project'));
    });

    test('writes the report to --report-output file', () async {
      final tmp = await Directory.systemTemp.createTemp('e2e_report_output');
      try {
        final out = '${tmp.path}/report.txt';
        final code = await runner.run([
          'optimize',
          '--analyze-only',
          '--project-dir',
          fixtureDir,
          '--report',
          'console',
          '--report-output',
          out,
        ]);
        expect(code, 0);
        final written = await File(out).readAsString();
        expect(written, contains('fixture_project'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('returns 1 when --project-dir is missing pubspec.yaml', () async {
      final tmp = await Directory.systemTemp.createTemp('e2e_empty_dir');
      try {
        final code = await runner.run([
          'optimize',
          '--analyze-only',
          '--project-dir',
          tmp.path,
        ]);
        expect(code, 1);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('End-to-end CLI help', () {
    test('returns 0 for --help', () async {
      final code = await runner.run(['--help']);
      expect(code, 0);
    });

    test('returns 1 for unknown command', () async {
      final code = await runner.run(['unknown-command']);
      expect(code, 1);
    });
  });
}

Future<T> _capturePrintWithResult<T>(
    Future<T> Function() body, List<String> out) async {
  final spec = ZoneSpecification(print: (_, __, ___, line) {
    out.add(line);
  });
  return await runZoned(body, zoneSpecification: spec);
}
