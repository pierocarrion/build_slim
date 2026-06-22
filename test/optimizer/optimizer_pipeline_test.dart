import 'dart:io';

import 'package:build_slim/src/builder/artifact_comparator.dart';
import 'package:build_slim/src/optimizer/optimizer_pipeline.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:build_slim/src/util/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers/mock_process_runner.dart';

/// Path of the static fixture project shipped with the test suite.
final String fixtureProjectPath = p
    .joinAll(['test', 'test_helpers', 'fixture_project']).replaceAll('\\', '/');

String fixturePath() => p.absolute(fixtureProjectPath);

void main() {
  late MockProcessRunner processRunner;
  late Logger logger;

  setUp(() {
    processRunner = MockProcessRunner();
    logger = Logger(level: LogLevel.none);
  });

  /// Creates a mock that returns canned versions for `dart --version` and
  /// `flutter --version`.
  void stubVersions() {
    processRunner.responses['dart --version'] = const ProcessResult(
      exitCode: 0,
      stdout: '',
      stderr: 'Dart SDK 3.4.0 (stable)',
    );
    processRunner.responses['flutter --version'] = const ProcessResult(
      exitCode: 0,
      stdout: 'Flutter 3.22.0 • channel stable',
      stderr: '',
    );
  }

  group('OptimizerPipeline.run analyze-only', () {
    test('returns findings from fixture without building', () async {
      stubVersions();
      final pipeline = OptimizerPipeline(
        logger: logger,
        processRunner: processRunner,
      );

      final report = await pipeline.run(
        projectDir: fixturePath(),
        target: BuildTarget.apk,
        analyzeOnly: true,
      );

      expect(report.projectName, 'fixture_project');
      expect(report.target, BuildTarget.apk);
      expect(report.findings, isNotEmpty);
      expect(report.dartSdkVersion, 'Dart SDK 3.4.0 (stable)');
      expect(report.flutterVersion, 'Flutter 3.22.0 • channel stable');
      expect(report.afterSizeBytes, isNull);
      expect(report.appliedOptimizations, isEmpty);
      expect(report.buildDurationMs, 0);
      expect(report.timestamp, isA<DateTime>());
    });

    test('does not invoke flutter build in analyze-only mode', () async {
      stubVersions();
      final pipeline = OptimizerPipeline(
        logger: logger,
        processRunner: processRunner,
      );

      await pipeline.run(
        projectDir: fixturePath(),
        target: BuildTarget.apk,
        analyzeOnly: true,
      );

      final buildCalls =
          processRunner.invocations.where((i) => i.arguments.first == 'build');
      expect(buildCalls, isEmpty);
    });
  });

  group('OptimizerPipeline.run version probes', () {
    test('uses stdout when stderr is empty for dart --version', () async {
      processRunner.responses['dart --version'] = const ProcessResult(
        exitCode: 0,
        stdout: 'Dart 3.0.0',
        stderr: '',
      );
      processRunner.responses['flutter --version'] = const ProcessResult(
        exitCode: 0,
        stdout: 'Flutter 3.0.0',
        stderr: '',
      );

      final pipeline = OptimizerPipeline(
        logger: logger,
        processRunner: processRunner,
      );

      final report = await pipeline.run(
        projectDir: fixturePath(),
        target: BuildTarget.apk,
        analyzeOnly: true,
      );

      expect(report.dartSdkVersion, 'Dart 3.0.0');
    });

    test('uses stderr when non-empty for dart --version', () async {
      processRunner.responses['dart --version'] = const ProcessResult(
        exitCode: 0,
        stdout: '',
        stderr: 'Dart 3.5.0\n',
      );
      processRunner.responses['flutter --version'] = const ProcessResult(
        exitCode: 0,
        stdout: 'Flutter 3.0.0',
        stderr: '',
      );

      final pipeline = OptimizerPipeline(
        logger: logger,
        processRunner: processRunner,
      );

      final report = await pipeline.run(
        projectDir: fixturePath(),
        target: BuildTarget.apk,
        analyzeOnly: true,
      );

      expect(report.dartSdkVersion, 'Dart 3.5.0');
    });

    test('returns "unknown" when ProcessRunnerException is thrown', () async {
      // Throw on any call to emulate missing dart/flutter binaries.
      processRunner.responseFor = (_, __) {
        throw const ProcessRunnerException('not found', executable: 'dart');
      };

      final pipeline = OptimizerPipeline(
        logger: logger,
        processRunner: processRunner,
      );

      final report = await pipeline.run(
        projectDir: fixturePath(),
        target: BuildTarget.apk,
        analyzeOnly: true,
      );

      expect(report.dartSdkVersion, 'unknown');
      expect(report.flutterVersion, 'unknown');
    });

    test('uses only first line of version output', () async {
      processRunner.responses['dart --version'] = const ProcessResult(
        exitCode: 0,
        stdout: '',
        stderr: 'Dart 3.5.0\nextra line 1\nextra line 2',
      );
      processRunner.responses['flutter --version'] = const ProcessResult(
        exitCode: 0,
        stdout: 'Flutter 3.22.0 • channel stable\nmore',
        stderr: '',
      );

      final pipeline = OptimizerPipeline(
        logger: logger,
        processRunner: processRunner,
      );

      final report = await pipeline.run(
        projectDir: fixturePath(),
        target: BuildTarget.apk,
        analyzeOnly: true,
      );

      expect(report.dartSdkVersion, 'Dart 3.5.0');
      expect(report.flutterVersion, 'Flutter 3.22.0 • channel stable');
    });
  });

  group('OptimizerPipeline.run full build', () {
    Future<Directory> makeTempProjectWithPubspec() async {
      final dir =
          await Directory.systemTemp.createTemp('optimizer_pipeline_test');
      await File(p.join(dir.path, 'pubspec.yaml'))
          .writeAsString('name: tmp_app\n');
      await Directory(p.join(dir.path, 'lib')).create(recursive: true);
      await File(p.join(dir.path, 'lib', 'main.dart')).writeAsString('');
      // Create the artifact so the BuildRunner can locate it.
      final apkFile = File(p.join(
        dir.path,
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-release.apk',
      ));
      await apkFile.create(recursive: true);
      await apkFile.writeAsBytes(List.filled(256, 0));
      return dir;
    }

    test('returns report with afterSizeBytes on successful build', () async {
      stubVersions();
      final projectDir = await makeTempProjectWithPubspec();
      try {
        processRunner.responseFor = (executable, args) {
          if (executable == 'flutter' && args.first == 'build') {
            return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
          }
          return null;
        };

        final pipeline = OptimizerPipeline(
          logger: logger,
          processRunner: processRunner,
        );

        final report = await pipeline.run(
          projectDir: projectDir.path,
          target: BuildTarget.apk,
        );

        expect(report.afterSizeBytes, 256);
        expect(report.appliedOptimizations, isNotEmpty);
        expect(report.buildDurationMs, greaterThanOrEqualTo(0));
        expect(report.target, BuildTarget.apk);
      } finally {
        await projectDir.delete(recursive: true);
      }
    });

    test('throws BuildOptimizerException on build failure', () async {
      stubVersions();
      final projectDir = await makeTempProjectWithPubspec();
      try {
        processRunner.responseFor = (executable, args) {
          if (executable == 'flutter' && args.first == 'build') {
            return const ProcessResult(
              exitCode: 7,
              stdout: '',
              stderr: 'build error',
            );
          }
          return null;
        };

        final pipeline = OptimizerPipeline(
          logger: logger,
          processRunner: processRunner,
        );

        await expectLater(
          pipeline.run(
            projectDir: projectDir.path,
            target: BuildTarget.apk,
          ),
          throwsA(
            isA<BuildOptimizerException>()
                .having((e) => e.message, 'message', contains('exit code 7')),
          ),
        );
      } finally {
        await projectDir.delete(recursive: true);
      }
    });

    test('propagates injected obfuscate to build', () async {
      stubVersions();
      final projectDir = await makeTempProjectWithPubspec();
      try {
        processRunner.responseFor = (executable, args) {
          if (executable == 'flutter' && args.first == 'build') {
            return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
          }
          return null;
        };

        final pipeline = OptimizerPipeline(
          logger: logger,
          processRunner: processRunner,
        );

        await pipeline.run(
          projectDir: projectDir.path,
          target: BuildTarget.apk,
        );

        // Even though we did not pass obfuscate/treeShakeIcons, the
        // DartOptimizer injects them when they are absent.
        final buildCall = processRunner.invocations.firstWhere(
          (i) => i.executable == 'flutter' && i.arguments.first == 'build',
        );
        expect(buildCall.arguments, contains('--obfuscate'));
        expect(buildCall.arguments, contains('--tree-shake-icons'));
        expect(
          buildCall.arguments,
          containsAll(['--split-debug-info', './build/debug-info']),
        );
      } finally {
        await projectDir.delete(recursive: true);
      }
    });
  });
}
