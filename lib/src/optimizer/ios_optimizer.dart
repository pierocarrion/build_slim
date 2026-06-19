import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/logger.dart';

/// Injects safe iOS `.xcconfig` settings for size optimization.
class IosOptimizer {
  /// Creates an iOS optimizer.
  IosOptimizer({
    required this.projectDir,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Injects Release.xcconfig settings and returns applied changes.
  Future<List<String>> optimize() async {
    final applied = <String>[];
    final xcconfigPath = p.join(
      projectDir,
      'ios',
      'Flutter',
      'Release.xcconfig',
    );
    final xcconfig = File(xcconfigPath);

    if (!xcconfig.existsSync()) {
      logger.verbose('No iOS Release.xcconfig found; skipping iOS patches.');
      return applied;
    }

    var content = await xcconfig.readAsString();
    final additions = <String>[];

    if (!content.contains('ENABLE_BITCODE=NO')) {
      additions.add('ENABLE_BITCODE=NO');
    }
    if (!content.contains('STRIP_STYLE=all')) {
      additions.add('STRIP_STYLE=all');
    }
    if (!content.contains('DEAD_CODE_STRIPPING=YES')) {
      additions.add('DEAD_CODE_STRIPPING=YES');
    }
    if (!content.contains('GCC_OPTIMIZATION_LEVEL=s')) {
      additions.add('GCC_OPTIMIZATION_LEVEL=s');
    }
    if (!content.contains('SWIFT_OPTIMIZATION_LEVEL=-Osize')) {
      additions.add('SWIFT_OPTIMIZATION_LEVEL=-Osize');
    }

    if (additions.isNotEmpty) {
      content = '$content\n${additions.join('\n')}\n';
      await xcconfig.writeAsString(content);
      applied.add(
        'Injected iOS Release.xcconfig settings: ${additions.join(', ')}',
      );
      logger.verbose(
          'Patched Release.xcconfig with ${additions.length} settings.');
    }

    logger.info(
      'Manual iOS recommendation: open ios/Runner.xcworkspace in Xcode and '
      'verify ENABLE_BITCODE=NO, DEAD_CODE_STRIPPING=YES, and '
      'Swift optimization -Osize.',
    );

    return applied;
  }
}
