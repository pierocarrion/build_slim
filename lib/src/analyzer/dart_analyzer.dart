import 'dart:io';

import 'package:path/path.dart' as p;

import '../reporter/report_model.dart';
import '../util/logger.dart';

/// Analyzes Dart source code for patterns that affect build size or
/// tree-shaking.
class DartAnalyzer {
  /// Creates a Dart analyzer.
  DartAnalyzer({
    required this.projectDir,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Analyzes Dart source files and returns findings.
  Future<List<Finding>> analyze() async {
    final findings = <Finding>[];
    final sourceFiles = await _collectSourceFiles();

    var hasReleaseGuards = false;
    var hasPrintCalls = false;
    var hasImageNetwork = false;
    var hasCachedNetworkImage = false;

    for (final file in sourceFiles) {
      String content;
      try {
        content = await file.readAsString();
      } on FileSystemException catch (e) {
        logger.verbose('Could not read ${file.path}: ${e.message}');
        continue;
      }

      if (content.contains("import 'dart:mirrors'") ||
          content.contains('import "dart:mirrors"')) {
        findings.add(Finding(
          id: 'dart_mirrors_import',
          severity: FindingSeverity.error,
          title: 'dart:mirrors import detected',
          description: '${file.path} imports dart:mirrors, which breaks '
              'Dart tree-shaking and can substantially increase binary size.',
          recommendation: 'Remove the import or move the reflective code to '
              'a separate build target.',
          estimatedSavingsBytes: 2 * 1024 * 1024,
        ));
      }

      if (content.contains('kReleaseMode') ||
          content.contains('kDebugMode') ||
          content.contains('!kReleaseMode')) {
        hasReleaseGuards = true;
      }

      if (content.contains('print(')) {
        hasPrintCalls = true;
      }

      if (content.contains('Image.network(')) {
        hasImageNetwork = true;
      }
      if (content.contains('CachedNetworkImage')) {
        hasCachedNetworkImage = true;
      }
    }

    if (hasPrintCalls && !hasReleaseGuards) {
      findings.add(const Finding(
        id: 'unguarded_print_calls',
        severity: FindingSeverity.warning,
        title: 'Unguarded print() calls detected',
        description: 'print() calls were found without kReleaseMode guards. '
            'These execute in release builds and may carry debug strings '
            'into the binary.',
        recommendation: 'Guard debug logs with `if (kDebugMode)` or use a '
            'proper logging framework.',
        estimatedSavingsBytes: 100 * 1024,
      ));
    }

    if (hasImageNetwork && !hasCachedNetworkImage) {
      findings.add(const Finding(
        id: 'image_network_without_cache',
        severity: FindingSeverity.info,
        title: 'Image.network used without caching wrapper',
        description: 'Network images are loaded without a disk-cache wrapper, '
            'which can increase data usage and re-downloads.',
        recommendation: 'Consider using cached_network_image for assets that '
            'are loaded repeatedly.',
      ));
    }

    return findings;
  }

  Future<List<File>> _collectSourceFiles() async {
    final libDir = Directory(p.join(projectDir, 'lib'));
    if (!libDir.existsSync()) return [];

    final files = <File>[];
    await for (final entity
        in libDir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }
    return files;
  }
}
