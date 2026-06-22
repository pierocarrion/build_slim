import 'package:build_slim/src/util/process_runner.dart';

/// A single recorded invocation of the mock process runner.
class RecordedInvocation {
  /// Creates a recorded invocation.
  const RecordedInvocation({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
  });

  /// Executable name.
  final String executable;

  /// Arguments passed (without the working directory).
  final List<String> arguments;

  /// Working directory, if any.
  final String? workingDirectory;

  /// Signature key: `"<executable> <args joined by space>"`.
  String get key => '$executable ${arguments.join(' ')}';
}

/// A fake [ProcessRunner] for tests.
///
/// Match precedence (first match wins):
/// 1. [responseFor] (function) if it returns non-null.
/// 2. Exact key match in [responses] (`"<executable> <args joined by space>"`).
/// 3. Default success (`exitCode: 0`, empty stdout/stderr).
///
/// [invocations] records every call as a [RecordedInvocation], preserving the
/// working directory separately from the arguments.
class MockProcessRunner implements ProcessRunner {
  /// Creates a mock process runner.
  MockProcessRunner({
    Map<String, ProcessResult>? responses,
    this.responseFor,
    this.throwIfUnmatched = false,
  }) : responses = responses ?? <String, ProcessResult>{};

  /// Map from command signature (`"<exe> <arg1> <arg2> ..."`) to a fake
  /// [ProcessResult]. Always mutable.
  final Map<String, ProcessResult> responses;

  /// Optional function used to resolve responses dynamically.
  ProcessResult? Function(String executable, List<String> arguments)?
      responseFor;

  /// When true, an unmatched invocation throws a [StateError] instead of
  /// returning a default success. Useful to catch unmocked calls in tests.
  final bool throwIfUnmatched;

  /// Records every command that was invoked.
  final List<RecordedInvocation> invocations = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    invocations.add(RecordedInvocation(
      executable: executable,
      arguments: List<String>.unmodifiable(arguments),
      workingDirectory: workingDirectory,
    ));
    final dynamic custom = responseFor?.call(executable, arguments);
    if (custom != null) {
      return custom;
    }
    final key = '$executable ${arguments.join(' ')}';
    if (responses.containsKey(key)) {
      return responses[key]!;
    }
    if (throwIfUnmatched) {
      throw StateError('MockProcessRunner: unmatched call "$key"');
    }
    return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
  }

  /// Returns the recorded invocations matching [executable].
  List<RecordedInvocation> callsFor(String executable) =>
      invocations.where((c) => c.executable == executable).toList();
}
