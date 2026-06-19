import 'dart:io';

/// Exception thrown when a [ProcessRunner] invocation fails in an unexpected
/// way (e.g., executable not found).
class ProcessRunnerException implements Exception {
  /// Creates a process runner exception.
  const ProcessRunnerException(this.message,
      {this.executable, this.workingDirectory});

  /// Human-readable description of the failure.
  final String message;

  /// The executable that was invoked, if known.
  final String? executable;

  /// The working directory for the invocation, if known.
  final String? workingDirectory;

  @override
  String toString() {
    final parts = <String>[
      'ProcessRunnerException: $message',
      if (executable != null) 'executable: $executable',
      if (workingDirectory != null) 'workingDirectory: $workingDirectory',
    ];
    return parts.join('\n');
  }
}

/// Result of running a process.
class ProcessResult {
  /// Creates a process result.
  const ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Exit code returned by the process.
  final int exitCode;

  /// Standard output from the process.
  final String stdout;

  /// Standard error from the process.
  final String stderr;
}

/// Abstract interface for running OS processes.
///
/// Tests can provide a fake implementation to avoid shelling out to real
/// executables.
abstract class ProcessRunner {
  /// Runs [executable] with [arguments] in [workingDirectory].
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

/// Default implementation that delegates to [Process.run].
class IOProcessRunner implements ProcessRunner {
  /// Creates the default IO process runner.
  const IOProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: true,
      );
      return ProcessResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } on ProcessException catch (e) {
      throw ProcessRunnerException(
        'Failed to run "$executable": ${e.message}',
        executable: executable,
        workingDirectory: workingDirectory,
      );
    }
  }
}
