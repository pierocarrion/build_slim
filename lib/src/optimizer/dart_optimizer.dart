import '../util/logger.dart';

/// Optimizes Dart/Flutter build flags.
class DartOptimizer {
  /// Creates a Dart optimizer.
  DartOptimizer({required this.logger});

  /// Logger for diagnostic output.
  final Logger logger;

  /// Whether `--obfuscate` was injected.
  bool obfuscateInjected = false;

  /// Whether `--tree-shake-icons` was injected.
  bool treeShakeIconsInjected = false;

  /// Path used for `--split-debug-info`, if injected.
  String? splitDebugInfoPath;

  /// Injects missing Dart build flags and returns a list of applied changes.
  List<String> optimize({
    required bool obfuscate,
    required bool treeShakeIcons,
  }) {
    final applied = <String>[];

    if (!treeShakeIcons) {
      treeShakeIconsInjected = true;
      applied.add('Injected --tree-shake-icons');
      logger.verbose('Will inject --tree-shake-icons into flutter build.');
    }

    if (!obfuscate) {
      obfuscateInjected = true;
      splitDebugInfoPath = './build/debug-info';
      applied
          .add('Injected --obfuscate --split-debug-info=$splitDebugInfoPath');
      logger.verbose('Will inject --obfuscate and --split-debug-info.');
    }

    if (applied.isEmpty) {
      logger.verbose('All Dart build flags already optimal.');
    }

    return applied;
  }
}
