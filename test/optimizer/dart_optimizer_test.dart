import 'package:build_slim/src/optimizer/dart_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:test/test.dart';

void main() {
  test('injects tree-shake-icons and obfuscate when disabled', () {
    final optimizer = DartOptimizer(
      logger: const Logger(level: LogLevel.none),
    );
    final applied = optimizer.optimize(obfuscate: false, treeShakeIcons: false);

    expect(applied, contains(contains('Injected --tree-shake-icons')));
    expect(applied, contains(contains('Injected --obfuscate')));
    expect(optimizer.treeShakeIconsInjected, isTrue);
    expect(optimizer.obfuscateInjected, isTrue);
    expect(optimizer.splitDebugInfoPath, isNotNull);
  });

  test('does not inject flags when already enabled', () {
    final optimizer = DartOptimizer(
      logger: const Logger(level: LogLevel.none),
    );
    final applied = optimizer.optimize(obfuscate: true, treeShakeIcons: true);

    expect(applied, isEmpty);
    expect(optimizer.treeShakeIconsInjected, isFalse);
    expect(optimizer.obfuscateInjected, isFalse);
  });
}
