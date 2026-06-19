import 'package:ansi_styles/ansi_styles.dart';

import '../builder/artifact_comparator.dart';
import '../util/file_size_util.dart';
import '../util/logger.dart';
import 'report_model.dart';

/// Renders an [OptimizationReport] as ANSI-colored console output.
class ConsoleReporter implements Reporter {
  /// Creates a console reporter.
  const ConsoleReporter({required this.logger});

  /// Logger used for styling context.
  final Logger logger;

  @override
  String render(OptimizationReport report) {
    final buffer = StringBuffer();

    buffer.writeln(
      AnsiStyles.bold('Build Slim Report: ${report.projectName}'),
    );
    buffer.writeln('Target: ${report.target.name}');
    buffer.writeln('Dart: ${report.dartSdkVersion}');
    buffer.writeln('Flutter: ${report.flutterVersion}');
    buffer.writeln('');

    if (report.appliedOptimizations.isNotEmpty) {
      buffer.writeln(AnsiStyles.bold('Applied optimizations:'));
      for (final optimization in report.appliedOptimizations) {
        buffer.writeln('  ${AnsiStyles.green('✓')} $optimization');
      }
      buffer.writeln('');
    }

    if (report.findings.isEmpty) {
      buffer.writeln(
        AnsiStyles.green(
          'Your build is already well-optimized. No changes needed.',
        ),
      );
    } else {
      buffer.writeln(AnsiStyles.bold('Findings:'));
      buffer.writeln(
        '${AnsiStyles.gray('ID'.padRight(28))} '
        '${AnsiStyles.gray('Severity'.padRight(10))} '
        '${AnsiStyles.gray('Title')}',
      );
      for (final finding in report.findings) {
        final icon = _severityIcon(finding.severity);
        final savings = finding.estimatedSavingsBytes == null
            ? ''
            : ' (~${FileSizeUtil.format(finding.estimatedSavingsBytes!)} saved)';
        buffer.writeln(
          '${finding.id.padRight(28)} '
          '${_severityLabel(finding.severity).padRight(10)} '
          '$icon ${finding.title}$savings',
        );
        buffer.writeln('    ${AnsiStyles.gray(finding.description)}');
        if (finding.recommendation != null) {
          buffer.writeln(
            '    ${AnsiStyles.cyan('→ ${finding.recommendation!}')}',
          );
        }
      }
    }

    buffer.writeln('');
    if (report.beforeSizeBytes != null && report.afterSizeBytes != null) {
      buffer.writeln(
        AnsiStyles.bold(
          'Before: ${FileSizeUtil.format(report.beforeSizeBytes!)} '
          '→ After: ${FileSizeUtil.format(report.afterSizeBytes!)} '
          '(saved ${report.savedPercent?.toStringAsFixed(1)}%)',
        ),
      );
    } else if (report.afterSizeBytes != null) {
      buffer.writeln(
        AnsiStyles.bold(
          'Artifact size: ${FileSizeUtil.format(report.afterSizeBytes!)}',
        ),
      );
    }

    return buffer.toString();
  }

  String _severityIcon(FindingSeverity severity) => switch (severity) {
        FindingSeverity.error => AnsiStyles.red('✖'),
        FindingSeverity.warning => AnsiStyles.yellow('⚠'),
        FindingSeverity.info => AnsiStyles.blue('ℹ'),
      };

  String _severityLabel(FindingSeverity severity) => switch (severity) {
        FindingSeverity.error => AnsiStyles.red('error'),
        FindingSeverity.warning => AnsiStyles.yellow('warning'),
        FindingSeverity.info => AnsiStyles.blue('info'),
      };
}
