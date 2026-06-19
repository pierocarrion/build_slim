import 'package:args/command_runner.dart';

import 'optimize_command.dart';
import 'report_command.dart';

/// Entrypoint runner for the `build_slim` CLI.
class BuildSlimRunner {
  /// Creates the runner.
  BuildSlimRunner() {
    _runner
      ..addCommand(OptimizeCommand())
      ..addCommand(ReportCommand());
  }

  final CommandRunner<int> _runner = CommandRunner<int>(
    'build_slim',
    'Analyze and reduce the size of Flutter APK, AAB, and IPA artifacts.',
  );

  /// Runs the CLI with [args] and returns an exit code.
  Future<int> run(List<String> args) async {
    try {
      return await _runner.run(args) ?? 0;
    } on UsageException catch (e) {
      // ignore: avoid_print
      print(e);
      return 1;
    }
  }
}
