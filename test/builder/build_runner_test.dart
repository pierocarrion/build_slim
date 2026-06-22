import 'dart:io';

import 'package:build_slim/src/builder/build_runner.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:build_slim/src/util/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers/mock_process_runner.dart';

void main() {
  late Directory tempDir;
  late MockProcessRunner processRunner;
  late Logger logger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('build_runner_test');
    processRunner = MockProcessRunner();
    logger = Logger(level: LogLevel.none);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Creates a fake artifact at [relativePath] under [tempDir].
  Future<void> createArtifact(String relativePath, int sizeBytes) async {
    final file = File(p.join(tempDir.path, relativePath));
    await file.create(recursive: true);
    await file.writeAsBytes(List.filled(sizeBytes, 0));
  }

  BuildRunner buildRunner() => BuildRunner(
        projectDir: tempDir.path,
        processRunner: processRunner,
        logger: logger,
      );

  group('BuildRunner.build argument assembly', () {
    test('builds minimal apk command with --release', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 10);

      final result = await buildRunner().build(target: BuildTarget.apk);

      expect(result.exitCode, 0);
      expect(processRunner.invocations, hasLength(1));
      final call = processRunner.invocations.single;
      expect(call.executable, 'flutter');
      expect(call.arguments, ['build', 'apk', '--release']);
      expect(call.workingDirectory, tempDir.path);
    });

    test('appends --flavor when flavor provided', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 10);

      await buildRunner().build(target: BuildTarget.apk, flavor: 'prod');

      expect(
        processRunner.invocations.single.arguments,
        ['build', 'apk', '--flavor', 'prod', '--release'],
      );
    });

    test('appends --dart-define per entry', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 10);

      await buildRunner().build(
        target: BuildTarget.apk,
        dartDefines: const ['A=1', 'B=2'],
      );

      expect(
        processRunner.invocations.single.arguments,
        [
          'build',
          'apk',
          '--dart-define',
          'A=1',
          '--dart-define',
          'B=2',
          '--release',
        ],
      );
    });

    test('appends obfuscate with default split-debug-info path', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 10);

      await buildRunner().build(
        target: BuildTarget.apk,
        obfuscate: true,
      );

      expect(
        processRunner.invocations.single.arguments,
        [
          'build',
          'apk',
          '--obfuscate',
          '--split-debug-info',
          './build/debug-info',
          '--release',
        ],
      );
    });

    test('appends obfuscate with custom split-debug-info path', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 10);

      await buildRunner().build(
        target: BuildTarget.apk,
        obfuscate: true,
        splitDebugInfo: '/custom/path',
      );

      expect(
        processRunner.invocations.single.arguments,
        [
          'build',
          'apk',
          '--obfuscate',
          '--split-debug-info',
          '/custom/path',
          '--release',
        ],
      );
    });

    test('appends --tree-shake-icons when enabled', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 10);

      await buildRunner().build(
        target: BuildTarget.apk,
        treeShakeIcons: true,
      );

      expect(
        processRunner.invocations.single.arguments,
        ['build', 'apk', '--tree-shake-icons', '--release'],
      );
    });

    test('combines all flags in canonical order', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 10);

      await buildRunner().build(
        target: BuildTarget.aab,
        flavor: 'dev',
        dartDefines: const ['K=V'],
        obfuscate: true,
        treeShakeIcons: true,
        splitDebugInfo: '/out',
      );

      expect(
        processRunner.invocations.single.arguments,
        [
          'build',
          'aab',
          '--flavor',
          'dev',
          '--dart-define',
          'K=V',
          '--obfuscate',
          '--split-debug-info',
          '/out',
          '--tree-shake-icons',
          '--release',
        ],
      );
    });
  });

  group('BuildRunner.build success and artifact location', () {
    test('locates app-release.apk when present', () async {
      await createArtifact('build/app/outputs/flutter-apk/app-release.apk', 42);

      final result = await buildRunner().build(target: BuildTarget.apk);

      expect(result.exitCode, 0);
      expect(result.artifactPath, isNotNull);
      expect(result.artifactPath, endsWith('app-release.apk'));
      expect(result.artifactSizeBytes, 42);
      expect(result.durationMs, greaterThanOrEqualTo(0));
    });

    test('falls back to app.apk when app-release.apk missing', () async {
      await createArtifact('build/app/outputs/flutter-apk/app.apk', 17);

      final result = await buildRunner().build(target: BuildTarget.apk);

      expect(result.exitCode, 0);
      expect(result.artifactPath, endsWith('app.apk'));
      expect(result.artifactSizeBytes, 17);
    });

    test('returns null artifact when no apk candidates exist', () async {
      final result = await buildRunner().build(target: BuildTarget.apk);

      expect(result.exitCode, 0);
      expect(result.artifactPath, isNull);
      expect(result.artifactSizeBytes, isNull);
    });

    test('locates app-release.aab when present', () async {
      await createArtifact(
        'build/app/outputs/bundle/release/app-release.aab',
        99,
      );

      final result = await buildRunner().build(target: BuildTarget.aab);

      expect(result.exitCode, 0);
      expect(result.artifactPath, endsWith('app-release.aab'));
      expect(result.artifactSizeBytes, 99);
    });

    test('falls back to app.aab when app-release.aab missing', () async {
      await createArtifact('build/app/outputs/bundle/release/app.aab', 5);

      final result = await buildRunner().build(target: BuildTarget.aab);

      expect(result.artifactPath, endsWith('app.aab'));
      expect(result.artifactSizeBytes, 5);
    });

    test('locates any .ipa in build/ios/ipa/', () async {
      await createArtifact('build/ios/ipa/Runner.ipa', 100);

      final result = await buildRunner().build(target: BuildTarget.ipa);

      expect(result.exitCode, 0);
      expect(result.artifactPath, endsWith('.ipa'));
      expect(result.artifactSizeBytes, 100);
    });

    test('returns null artifact when ipa directory is empty', () async {
      await Directory(p.join(tempDir.path, 'build', 'ios', 'ipa'))
          .create(recursive: true);

      final result = await buildRunner().build(target: BuildTarget.ipa);

      expect(result.artifactPath, isNull);
      expect(result.artifactSizeBytes, isNull);
    });

    test('returns null artifact when ipa directory does not exist', () async {
      final result = await buildRunner().build(target: BuildTarget.ipa);

      expect(result.artifactPath, isNull);
    });
  });

  group('BuildRunner.build failure path', () {
    test('returns non-zero exit code and null artifact on build failure',
        () async {
      final failingRunner = MockProcessRunner(
        responses: {
          'flutter build apk --release': const ProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'boom',
          ),
        },
      );
      final runner = BuildRunner(
        projectDir: tempDir.path,
        processRunner: failingRunner,
        logger: Logger(level: LogLevel.none),
      );

      final result = await runner.build(target: BuildTarget.apk);

      expect(result.exitCode, 1);
      expect(result.artifactPath, isNull);
      expect(result.artifactSizeBytes, isNull);
    });
  });
}
