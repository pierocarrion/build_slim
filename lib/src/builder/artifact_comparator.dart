import 'dart:io';

import '../reporter/report_model.dart';
import '../util/file_size_util.dart';
import '../util/logger.dart';

/// Thrown when artifact comparison fails.
class BuildOptimizerException implements Exception {
  /// Creates a build optimizer exception.
  const BuildOptimizerException(this.message, {this.filePath, this.lineNumber});

  /// Human-readable message.
  final String message;

  /// File that caused the error, if known.
  final String? filePath;

  /// Line number related to the error, if known.
  final int? lineNumber;

  @override
  String toString() {
    final parts = <String>['BuildOptimizerException: $message'];
    if (filePath != null) parts.add('file: $filePath');
    if (lineNumber != null) parts.add('line: $lineNumber');
    return parts.join('\n');
  }
}

/// Base interface for report renderers.
abstract class Reporter {
  /// Renders the given [report] as a string.
  String render(OptimizationReport report);
}

/// Compares two artifact files and produces an [OptimizationReport].
class ArtifactComparator {
  /// Creates an artifact comparator.
  const ArtifactComparator();

  /// Compares [beforePath] and [afterPath].
  Future<OptimizationReport> compare({
    required String beforePath,
    required String afterPath,
    required String projectName,
    required BuildTarget target,
    required Logger logger,
  }) async {
    final beforeFile = File(beforePath);
    final afterFile = File(afterPath);

    if (!beforeFile.existsSync()) {
      throw BuildOptimizerException(
        'Artifact not found: $beforePath',
        filePath: beforePath,
      );
    }
    if (!afterFile.existsSync()) {
      throw BuildOptimizerException(
        'Artifact not found: $afterPath',
        filePath: afterPath,
      );
    }

    final beforeSize = beforeFile.lengthSync();
    final afterSize = afterFile.lengthSync();
    final saved = beforeSize - afterSize;
    final percent = FileSizeUtil.percentSaved(beforeSize, afterSize);

    logger.info(
      'Before: ${FileSizeUtil.format(beforeSize)} '
      '→ After: ${FileSizeUtil.format(afterSize)} '
      '(${saved >= 0 ? 'saved' : 'added'} ${FileSizeUtil.format(saved.abs())})',
    );

    return OptimizationReport(
      projectName: projectName,
      target: target,
      beforeSizeBytes: beforeSize,
      afterSizeBytes: afterSize,
      savedBytes: saved,
      savedPercent: percent,
      dartSdkVersion: 'unknown',
      flutterVersion: 'unknown',
      timestamp: DateTime.now().toUtc(),
    );
  }
}
