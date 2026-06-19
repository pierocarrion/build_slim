import 'package:build_slim/src/util/process_runner.dart';

/// A fake [ProcessRunner] for tests.
class MockProcessRunner implements ProcessRunner {
  /// Creates a mock process runner.
  MockProcessRunner({this.responses = const {}});

  /// Map from command signature to a fake [ProcessResult].
  final Map<String, ProcessResult> responses;

  /// Records every command that was invoked.
  final List<List<String>> invocations = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final key = '$executable ${arguments.join(' ')}';
    invocations.add([
      executable,
      ...arguments,
      if (workingDirectory != null) workingDirectory
    ]);
    if (responses.containsKey(key)) {
      return responses[key]!;
    }
    return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
  }
}
