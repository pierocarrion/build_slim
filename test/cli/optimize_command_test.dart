import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_slim/src/cli/optimize_command.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers/fake_pipeline.dart';

void main() {
  late OptimizationReport sampleReport;
  late FakeOptimizerPipeline pipeline;
  late CommandRunner<int> runner;
  late StringBuffer sink;

  setUp(() {
    sampleReport = OptimizationReport(
      projectName: 'sample',
      target: BuildTarget.apk,
      beforeSizeBytes: 2000,
      afterSizeBytes: 1000,
      savedBytes: 1000,
      savedPercent: 50.0,
      findings: const [
        Finding(
          id: 'sample_finding',
          severity: FindingSeverity.warning,
          title: 'Some finding',
          description: 'Some description',
        ),
      ],
      appliedOptimizations: const ['Injected --obfuscate'],
      dartSdkVersion: 'Dart 3.4.0',
      flutterVersion: 'Flutter 3.22.0',
      timestamp: DateTime.utc(2024, 1, 1),
    );
    pipeline = FakeOptimizerPipeline(report: sampleReport);
    sink = StringBuffer();
    final command = OptimizeCommand(
      pipeline: pipeline,
      loggerSink: sink,
    );
    runner = CommandRunner<int>('build_slim', 'test')..addCommand(command);
  });

  group('OptimizeCommand flag parsing', () {
    test('passes default values to the pipeline', () async {
      final code = await runner.run(['optimize']);
      expect(code, 0);
      expect(pipeline.callCount, 1);
      final call = pipeline.lastCall!;
      expect(call.target, BuildTarget.apk);
      expect(call.analyzeOnly, isFalse);
      expect(call.obfuscate, isFalse);
      expect(call.treeShakeIcons, isFalse);
      expect(call.flavor, isNull);
      expect(call.dartDefines, isEmpty);
    });

    test('passes --target aab', () async {
      await runner.run(['optimize', '--target', 'aab']);
      expect(pipeline.lastCall!.target, BuildTarget.aab);
    });

    test('passes --target ipa', () async {
      await runner.run(['optimize', '--target', 'ipa']);
      expect(pipeline.lastCall!.target, BuildTarget.ipa);
    });

    test('rejects invalid --target value', () async {
      // args parser throws UsageException for invalid allowed values.
      expect(
        () => runner.run(['optimize', '--target', 'windows']),
        throwsA(isA<UsageException>()),
      );
    });

    test('passes --flavor', () async {
      await runner.run(['optimize', '--flavor', 'prod']);
      expect(pipeline.lastCall!.flavor, 'prod');
    });

    test('passes multiple --dart-define entries', () async {
      await runner.run([
        'optimize',
        '--dart-define=A=1',
        '--dart-define=B=2',
      ]);
      expect(pipeline.lastCall!.dartDefines, ['A=1', 'B=2']);
    });

    test('passes --obfuscate flag', () async {
      await runner.run(['optimize', '--obfuscate']);
      expect(pipeline.lastCall!.obfuscate, isTrue);
    });

    test('passes --tree-shake-icons flag', () async {
      await runner.run(['optimize', '--tree-shake-icons']);
      expect(pipeline.lastCall!.treeShakeIcons, isTrue);
    });

    test('passes --analyze-only flag', () async {
      await runner.run(['optimize', '--analyze-only']);
      expect(pipeline.lastCall!.analyzeOnly, isTrue);
    });

    test('resolves --project-dir to an absolute path', () async {
      await runner.run(['optimize', '--project-dir', '.']);
      final projectDir = pipeline.lastCall!.projectDir;
      // Should be absolute (the absolute normalization keeps the trailing '.'
      // per package:path semantics).
      expect(p.isAbsolute(projectDir), isTrue);
      expect(projectDir, endsWith('.'));
    });
  });

  group('OptimizeCommand output format', () {
    test('prints console report to stdout by default', () async {
      final printed = <String>[];
      await _capturePrintWithResult<int?>(() async {
        return await runner.run(['optimize']);
      }, printed);
      expect(printed.any((s) => s.contains('Build Slim Report')), isTrue);
    });

    test('renders JSON when --report json', () async {
      final printed = <String>[];
      await _capturePrintWithResult<int?>(() async {
        return await runner.run(['optimize', '--report', 'json']);
      }, printed);
      final decoded = _decode(printed.join('\n')) as Map<String, dynamic>;
      expect(decoded['projectName'], 'sample');
    });

    test('renders HTML when --report html', () async {
      final printed = <String>[];
      await _capturePrintWithResult<int?>(() async {
        return await runner.run(['optimize', '--report', 'html']);
      }, printed);
      final html = printed.join('\n');
      expect(html, contains('<!DOCTYPE html>'));
    });

    test('writes the report to a file when --report-output is set', () async {
      final tmp =
          await Directory.systemTemp.createTemp('optimize_command_test');
      try {
        final out = '${tmp.path}/report.txt';
        await runner
            .run(['optimize', '--report', 'console', '--report-output', out]);
        final written = await File(out).readAsString();
        expect(written, contains('Build Slim Report'));
        // The success log goes to the logger sink.
        expect(sink.toString(), contains('Report written'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('OptimizeCommand error handling', () {
    test('returns 1 when pipeline throws BuildOptimizerException', () async {
      final throwing = FakeOptimizerPipeline(
        report: sampleReport,
        shouldThrow: true,
      );
      final command = OptimizeCommand(
        pipeline: throwing,
        loggerSink: sink,
      );
      final r = CommandRunner<int>('build_slim', 'test')..addCommand(command);

      final code = await r.run(['optimize']);
      expect(code, 1);
      expect(sink.toString(), contains('pipeline failure'));
    });
  });

  group('OptimizeCommand verbose flag', () {
    test('uses verbose log level when --verbose', () async {
      final code = await runner.run(['optimize', '--verbose']);
      expect(code, 0);
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

dynamic _decode(String json) {
  final trimmed = json.trim();
  return const JsonDecoder().convert(trimmed);
}
