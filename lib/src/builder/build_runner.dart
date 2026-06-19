import 'dart:io';

import 'package:path/path.dart' as p;

import '../reporter/report_model.dart';
import '../util/logger.dart';
import '../util/process_runner.dart';

/// Runs `flutter build` subprocesses and locates the produced artifact.
class BuildRunner {
  /// Creates a build runner.
  BuildRunner({
    required this.projectDir,
    required this.processRunner,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Process runner used to invoke Flutter.
  final ProcessRunner processRunner;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Builds [target] with the given flags and returns a [BuildResult].
  Future<BuildResult> build({
    required BuildTarget target,
    String? flavor,
    List<String> dartDefines = const [],
    bool obfuscate = false,
    bool treeShakeIcons = false,
    String? splitDebugInfo,
  }) async {
    final stopwatch = Stopwatch()..start();

    final arguments = <String>['build', target.name];

    if (flavor != null) {
      arguments.addAll(['--flavor', flavor]);
    }

    for (final define in dartDefines) {
      arguments.addAll(['--dart-define', define]);
    }

    if (obfuscate) {
      arguments.add('--obfuscate');
      arguments.addAll([
        '--split-debug-info',
        splitDebugInfo ?? './build/debug-info',
      ]);
    }

    if (treeShakeIcons) {
      arguments.add('--tree-shake-icons');
    }

    arguments.add('--release');

    logger.verbose('Running: flutter ${arguments.join(' ')}');

    final result = await processRunner.run(
      'flutter',
      arguments,
      workingDirectory: projectDir,
    );

    stopwatch.stop();

    if (result.exitCode != 0) {
      logger.error(result.stderr);
      return BuildResult(
        exitCode: result.exitCode,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final artifactPath = _locateArtifact(target);
    final artifactSize =
        artifactPath == null ? null : File(artifactPath).lengthSync();

    return BuildResult(
      exitCode: 0,
      durationMs: stopwatch.elapsedMilliseconds,
      artifactPath: artifactPath,
      artifactSizeBytes: artifactSize,
    );
  }

  String? _locateArtifact(BuildTarget target) {
    switch (target) {
      case BuildTarget.apk:
        final candidates = [
          p.join(projectDir, 'build', 'app', 'outputs', 'flutter-apk',
              'app-release.apk'),
          p.join(
              projectDir, 'build', 'app', 'outputs', 'flutter-apk', 'app.apk'),
        ];
        return _firstExisting(candidates);
      case BuildTarget.aab:
        final candidates = [
          p.join(
            projectDir,
            'build',
            'app',
            'outputs',
            'bundle',
            'release',
            'app-release.aab',
          ),
          p.join(
            projectDir,
            'build',
            'app',
            'outputs',
            'bundle',
            'release',
            'app.aab',
          ),
        ];
        return _firstExisting(candidates);
      case BuildTarget.ipa:
        final dir = Directory(
          p.join(projectDir, 'build', 'ios', 'ipa'),
        );
        if (!dir.existsSync()) return null;
        final ipas = dir
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path).toLowerCase() == '.ipa')
            .toList();
        return ipas.isEmpty ? null : ipas.first.path;
    }
  }

  String? _firstExisting(List<String> paths) {
    for (final path in paths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}
