import 'package:args/command_runner.dart';

import 'optimize_command.dart';
import 'report_command.dart';

/// Entrypoint runner for the `build_slim` CLI.
class BuildSlimRunner {
  /// Creates the runner.
  ///
  /// Tests may pass [optimizeCommand] and [reportCommand] to inject fake
  /// dependencies or to capture log output via a sink.
  BuildSlimRunner({
    OptimizeCommand? optimizeCommand,
    ReportCommand? reportCommand,
    StringSink? commandSink,
  }) : _commandSink = commandSink {
    _runner
      ..addCommand(optimizeCommand ?? OptimizeCommand(loggerSink: _commandSink))
      ..addCommand(reportCommand ?? ReportCommand(loggerSink: _commandSink));
  }

  final StringSink? _commandSink;

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
