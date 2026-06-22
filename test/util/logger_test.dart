import 'package:build_slim/src/util/logger.dart';
import 'package:test/test.dart';

void main() {
  late StringBuffer sink;

  Logger build(LogLevel level, {String? scope}) =>
      Logger(level: level, scope: scope, sink: sink);

  setUp(() {
    sink = StringBuffer();
  });

  group('Logger level filtering', () {
    test('LogLevel.none emits nothing', () {
      final logger = build(LogLevel.none);
      logger
        ..info('i')
        ..success('s')
        ..warning('w')
        ..error('e')
        ..verbose('v');
      expect(sink.toString(), '');
    });

    test('LogLevel.error emits only error', () {
      final logger = build(LogLevel.error);
      logger
        ..info('i')
        ..success('s')
        ..warning('w')
        ..error('e')
        ..verbose('v');
      final out = sink.toString();
      expect(out, contains('e'));
      expect(out, isNot(contains(' i')));
      expect(out, isNot(contains('s')));
      expect(out, isNot(contains('w')));
      expect(out, isNot(contains('v')));
    });

    test('LogLevel.info emits info, success, warning, error but not verbose',
        () {
      final logger = build(LogLevel.info);
      logger
        ..info('info-msg')
        ..success('success-msg')
        ..warning('warn-msg')
        ..error('err-msg')
        ..verbose('verbose-msg');
      final out = sink.toString();
      expect(out, contains('info-msg'));
      expect(out, contains('success-msg'));
      expect(out, contains('warn-msg'));
      expect(out, contains('err-msg'));
      expect(out, isNot(contains('verbose-msg')));
    });

    test('LogLevel.verbose emits everything', () {
      final logger = build(LogLevel.verbose);
      logger
        ..info('i')
        ..success('s')
        ..warning('w')
        ..error('e')
        ..verbose('v');
      final out = sink.toString();
      expect(out, contains('i'));
      expect(out, contains('s'));
      expect(out, contains('w'));
      expect(out, contains('e'));
      expect(out, contains('v'));
    });
  });

  group('Logger default level', () {
    test('defaults to LogLevel.info', () {
      final logger = Logger(sink: sink);
      logger.verbose('hidden');
      expect(sink.toString(), '');
      logger.info('shown');
      expect(sink.toString(), contains('shown'));
    });
  });

  group('Logger scope prefix', () {
    test('prepends [scope] to every emitted message', () {
      final logger = build(LogLevel.verbose, scope: 'analyzer');
      logger.info('hello');
      logger.error('boom');
      final lines = sink.toString().split('\n').where((l) => l.isNotEmpty);
      for (final line in lines) {
        expect(line, startsWith('[analyzer]'));
      }
    });

    test('omits prefix when scope is null', () {
      final logger = build(LogLevel.info);
      logger.info('hello');
      final out = sink.toString().trim();
      expect(out, 'hello');
    });
  });

  group('Logger writes to sink with newline', () {
    test('each emitted message ends with a newline', () {
      final logger = build(LogLevel.info);
      logger.info('one');
      logger.info('two');
      final out = sink.toString();
      expect(out, 'one\ntwo\n');
    });
  });
}
