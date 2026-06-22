import 'dart:io';

import 'package:args/command_runner.dart';

import '../builder/artifact_comparator.dart';
import '../reporter/console_reporter.dart';
import '../reporter/html_reporter.dart';
import '../reporter/json_reporter.dart';
import '../reporter/report_model.dart';
import '../util/logger.dart';

/// The `report` command: compare two existing artifacts.
class ReportCommand extends Command<int> {
  /// Creates the report command and defines its flags.
  ///
  /// Tests may inject [comparator] and [loggerSink] to avoid real file IO and
  /// to capture log output.
  ReportCommand({
    ArtifactComparator? comparator,
    StringSink? loggerSink,
  })  : _injectedComparator = comparator,
        _loggerSink = loggerSink {
    argParser
      ..addOption(
        'before',
        help: 'Path to the original artifact.',
      )
      ..addOption(
        'after',
        help: 'Path to the optimized artifact.',
      )
      ..addOption(
        'format',
        defaultsTo: 'console',
        allowed: const ['console', 'json', 'html'],
        help: 'Output format.',
      )
      ..addOption(
        'output',
        help: 'File path to write the report.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        defaultsTo: false,
        help: 'Verbose logging.',
      );
  }

  final ArtifactComparator? _injectedComparator;
  final StringSink? _loggerSink;

  @override
  String get name => 'report';

  @override
  String get description =>
      'Compare two build artifacts and produce a size diff report.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final level = args.flag('verbose') ? LogLevel.verbose : LogLevel.info;
    final logger = Logger(level: level, sink: _loggerSink);

    final beforePath = args.option('before');
    final afterPath = args.option('after');

    if (beforePath == null || afterPath == null) {
      logger.error('Both --before and --after are required.');
      return 1;
    }

    final comparator = _injectedComparator ?? const ArtifactComparator();
    final report = await comparator.compare(
      beforePath: beforePath,
      afterPath: afterPath,
      projectName: 'artifact-comparison',
      target: BuildTarget.apk,
      logger: logger,
    );

    final format = args.option('format')!;
    final reporter = _reporterFor(format, logger);
    final output = reporter.render(report);

    final outputPath = args.option('output');
    if (outputPath != null) {
      await File(outputPath).writeAsString(output);
      logger.success('Report written to $outputPath');
    } else {
      // ignore: avoid_print
      print(output);
    }

    return 0;
  }

  Reporter _reporterFor(String format, Logger logger) => switch (format) {
        'json' => const JsonReporter(),
        'html' => const HtmlReporter(),
        _ => ConsoleReporter(logger: logger),
      };
}
