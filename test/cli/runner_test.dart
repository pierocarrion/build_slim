import 'dart:async';

import 'package:build_slim/src/cli/optimize_command.dart';
import 'package:build_slim/src/cli/report_command.dart';
import 'package:build_slim/src/cli/runner.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:test/test.dart';

import '../test_helpers/fake_pipeline.dart';

void main() {
  late OptimizationReport sampleReport;
  late FakeOptimizerPipeline pipeline;
  late BuildSlimRunner runner;

  setUp(() {
    sampleReport = OptimizationReport(
      projectName: 'sample',
      target: BuildTarget.apk,
      findings: const [],
      appliedOptimizations: const [],
      dartSdkVersion: 'Dart 3.4.0',
      flutterVersion: 'Flutter 3.22.0',
      timestamp: DateTime.utc(2024, 1, 1),
    );
    pipeline = FakeOptimizerPipeline(report: sampleReport);
    final optimize = OptimizeCommand(pipeline: pipeline);
    runner = BuildSlimRunner(
      optimizeCommand: optimize,
      reportCommand: ReportCommand(),
    );
  });

  group('BuildSlimRunner.run dispatch', () {
    test('returns 0 for the optimize command', () async {
      final code = await runner.run(['optimize']);
      expect(code, 0);
      expect(pipeline.callCount, 1);
    });

    test('returns 0 when no args are provided', () async {
      // CommandRunner.run returns null for top-level --help and similar;
      // BuildSlimRunner converts null to 0.
      final code = await runner.run([]);
      expect(code, 0);
    });

    test('returns 1 on UsageException (unknown command)', () async {
      final code = await runner.run(['bogus-command']);
      expect(code, 1);
    });

    test('returns 1 on UsageException (unknown flag)', () async {
      final code = await runner.run(['optimize', '--no-such-flag']);
      expect(code, 1);
    });
  });

  group('BuildSlimRunner.run --help', () {
    test('returns 0 for top-level --help (prints usage)', () async {
      final printed = <String>[];
      final code = await _capturePrintWithResult<int?>(() async {
        return await runner.run(['--help']);
      }, printed);
      expect(code, 0);
      expect(printed.join('\n'), contains('Usage'));
      expect(printed.join('\n'), contains('optimize'));
      expect(printed.join('\n'), contains('report'));
    });

    test('returns 0 for top-level -h', () async {
      final code = await runner.run(['-h']);
      expect(code, 0);
    });
  });

  group('BuildSlimRunner.run subcommand routing', () {
    test('passes args through to optimize', () async {
      await runner.run(['optimize', '--target', 'aab', '--analyze-only']);
      final call = pipeline.lastCall!;
      expect(call.target, BuildTarget.aab);
      expect(call.analyzeOnly, isTrue);
    });

    test('rejects invalid --target with exit code 1', () async {
      // The runner catches UsageException and returns 1.
      final code = await runner.run(['optimize', '--target', 'invalid']);
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
