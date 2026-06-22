import 'package:build_slim/src/optimizer/dart_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:test/test.dart';

void main() {
  group('DartOptimizer.optimize injects everything when both flags are false',
      () {
    late DartOptimizer optimizer;

    setUp(() {
      optimizer = DartOptimizer(logger: Logger(level: LogLevel.none));
    });

    test('injects tree-shake-icons and obfuscate', () {
      final applied =
          optimizer.optimize(obfuscate: false, treeShakeIcons: false);

      expect(applied, contains(contains('Injected --tree-shake-icons')));
      expect(applied, contains(contains('Injected --obfuscate')));
      expect(optimizer.treeShakeIconsInjected, isTrue);
      expect(optimizer.obfuscateInjected, isTrue);
      expect(optimizer.splitDebugInfoPath, isNotNull);
    });

    test('uses ./build/debug-info as the split-debug-info path', () {
      optimizer.optimize(obfuscate: false, treeShakeIcons: true);
      expect(optimizer.splitDebugInfoPath, './build/debug-info');
    });

    test('emits exact obfuscate message including the path', () {
      final applied =
          optimizer.optimize(obfuscate: false, treeShakeIcons: true);
      expect(
        applied,
        contains(
          'Injected --obfuscate --split-debug-info=./build/debug-info',
        ),
      );
    });
  });

  group('DartOptimizer.optimize with mixed flags', () {
    test('injects only tree-shake-icons when obfuscate is true', () {
      final optimizer = DartOptimizer(logger: Logger(level: LogLevel.none));
      final applied =
          optimizer.optimize(obfuscate: true, treeShakeIcons: false);

      expect(applied, contains(contains('Injected --tree-shake-icons')));
      expect(applied, isNot(contains('obfuscate')));
      expect(optimizer.treeShakeIconsInjected, isTrue);
      expect(optimizer.obfuscateInjected, isFalse);
      expect(optimizer.splitDebugInfoPath, isNull);
    });

    test('injects only obfuscate when tree-shake-icons is true', () {
      final optimizer = DartOptimizer(logger: Logger(level: LogLevel.none));
      final applied =
          optimizer.optimize(obfuscate: false, treeShakeIcons: true);

      expect(applied, isNot(contains('tree-shake-icons')));
      expect(applied, contains(contains('Injected --obfuscate')));
      expect(optimizer.treeShakeIconsInjected, isFalse);
      expect(optimizer.obfuscateInjected, isTrue);
    });
  });

  group('DartOptimizer.optimize with all flags enabled', () {
    test('returns empty applied and leaves flags untouched', () {
      final optimizer = DartOptimizer(logger: Logger(level: LogLevel.none));
      final applied = optimizer.optimize(obfuscate: true, treeShakeIcons: true);

      expect(applied, isEmpty);
      expect(optimizer.treeShakeIconsInjected, isFalse);
      expect(optimizer.obfuscateInjected, isFalse);
      expect(optimizer.splitDebugInfoPath, isNull);
    });
  });

  group('DartOptimizer.optimize ordering', () {
    test('emits tree-shake-icons message before obfuscate', () {
      final optimizer = DartOptimizer(logger: Logger(level: LogLevel.none));
      final applied =
          optimizer.optimize(obfuscate: false, treeShakeIcons: false);

      final tsIndex =
          applied.indexWhere((m) => m.contains('Injected --tree-shake-icons'));
      final obfIndex =
          applied.indexWhere((m) => m.contains('Injected --obfuscate'));

      expect(tsIndex, greaterThanOrEqualTo(0));
      expect(obfIndex, greaterThanOrEqualTo(0));
      expect(tsIndex, lessThan(obfIndex));
    });
  });

  group('DartOptimizer verbose logging', () {
    test('logs verbose message when flags are injected', () {
      final sink = StringBuffer();
      final optimizer =
          DartOptimizer(logger: Logger(level: LogLevel.verbose, sink: sink));
      optimizer.optimize(obfuscate: false, treeShakeIcons: false);

      final out = sink.toString();
      expect(out, contains('tree-shake-icons'));
      expect(out, contains('obfuscate'));
    });

    test('logs "already optimal" message when nothing is injected', () {
      final sink = StringBuffer();
      final optimizer =
          DartOptimizer(logger: Logger(level: LogLevel.verbose, sink: sink));
      optimizer.optimize(obfuscate: true, treeShakeIcons: true);

      expect(sink.toString(), contains('already optimal'));
    });
  });
}
