import 'dart:io';

import 'package:build_slim/src/util/process_runner.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessRunnerException', () {
    test('stores message, executable and workingDirectory', () {
      const exception = ProcessRunnerException(
        'boom',
        executable: 'flutter',
        workingDirectory: '/tmp',
      );
      expect(exception.message, 'boom');
      expect(exception.executable, 'flutter');
      expect(exception.workingDirectory, '/tmp');
    });

    test('toString includes only message when no extras provided', () {
      const exception = ProcessRunnerException('boom');
      expect(exception.toString(), 'ProcessRunnerException: boom');
    });

    test('toString includes executable when provided', () {
      const exception = ProcessRunnerException(
        'boom',
        executable: 'flutter',
      );
      final str = exception.toString();
      expect(str, contains('ProcessRunnerException: boom'));
      expect(str, contains('executable: flutter'));
      expect(str, isNot(contains('workingDirectory')));
    });

    test('toString includes workingDirectory when provided', () {
      const exception = ProcessRunnerException(
        'boom',
        workingDirectory: '/tmp',
      );
      final str = exception.toString();
      expect(str, contains('workingDirectory: /tmp'));
    });

    test('toString joins fields with newlines', () {
      const exception = ProcessRunnerException(
        'boom',
        executable: 'flutter',
        workingDirectory: '/tmp',
      );
      final lines = exception.toString().split('\n');
      expect(lines, hasLength(3));
      expect(lines[0], 'ProcessRunnerException: boom');
      expect(lines[1], 'executable: flutter');
      expect(lines[2], 'workingDirectory: /tmp');
    });
  });

  group('ProcessResult', () {
    test('round-trips all fields', () {
      const result = ProcessResult(
        exitCode: 42,
        stdout: 'out',
        stderr: 'err',
      );
      expect(result.exitCode, 42);
      expect(result.stdout, 'out');
      expect(result.stderr, 'err');
    });
  });

  group('IOProcessRunner.run', () {
    const runner = IOProcessRunner();

    test('returns exit code 0 for a successful command', () async {
      final result = await runner.run(
        Platform.isWindows ? 'cmd' : 'echo',
        Platform.isWindows ? ['/c', 'echo', 'hello'] : ['hello'],
      );
      expect(result.exitCode, 0);
      expect(result.stdout, contains('hello'));
    });

    test('throws ProcessRunnerException for missing executable', () async {
      // With runInShell:true the behavior is platform-dependent: POSIX shells
      // throw ProcessException, while Windows cmd.exe returns a non-zero exit
      // code. Only assert the exception on POSIX.
      if (Platform.isWindows) {
        // On Windows the command is reported as failed via exit code.
        final result = await runner.run(
          'this-binary-does-not-exist-12345',
          const [],
        );
        expect(result.exitCode, isNot(0));
      } else {
        expect(
          () => runner.run('this-binary-does-not-exist-12345', const []),
          throwsA(isA<ProcessRunnerException>()),
        );
      }
    }, skip: Platform.isWindows);

    test('captures non-zero exit codes without throwing', () async {
      final result = await runner.run(
        Platform.isWindows ? 'cmd' : 'sh',
        Platform.isWindows ? ['/c', 'exit', '3'] : ['-c', 'exit 3'],
      );
      expect(result.exitCode, 3);
    });

    test('exception includes executable and workingDirectory on failure',
        () async {
      if (Platform.isWindows) {
        // On Windows the wrapper does not throw; skip the field-assertion.
        return;
      }
      try {
        await runner.run(
          'this-binary-does-not-exist-12345',
          const ['--flag'],
          workingDirectory: '/tmp',
        );
        fail('expected ProcessRunnerException');
      } on ProcessRunnerException catch (e) {
        expect(e.executable, 'this-binary-does-not-exist-12345');
        expect(e.workingDirectory, '/tmp');
      }
    });
  });

  group('ProcessRunner contract', () {
    test('can be implemented by a fake', () {
      const fake = _FakeRunner();
      expect(fake, isA<ProcessRunner>());
    });
  });
}

class _FakeRunner implements ProcessRunner {
  const _FakeRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
  }
}
