import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../builder/artifact_comparator.dart';

import '../optimizer/optimizer_pipeline.dart';
import '../reporter/console_reporter.dart';
import '../reporter/html_reporter.dart';
import '../reporter/json_reporter.dart';
import '../reporter/report_model.dart';
import '../util/logger.dart';
import '../util/process_runner.dart';

/// The `optimize` command: analyze, optionally patch, build, and report.
class OptimizeCommand extends Command<int> {
  /// Creates the optimize command and defines its flags.
  ///
  /// Tests may inject [pipeline] and [loggerSink] to avoid real subprocesses
  /// and to capture log output.
  OptimizeCommand({
    OptimizerPipeline? pipeline,
    StringSink? loggerSink,
  })  : _injectedPipeline = pipeline,
        _loggerSink = loggerSink {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        defaultsTo: 'apk',
        allowed: const ['apk', 'aab', 'ipa'],
        help: 'Build target: apk, aab, or ipa.',
      )
      ..addOption(
        'project-dir',
        defaultsTo: '.',
        help: 'Path to the Flutter project root.',
      )
      ..addOption(
        'flavor',
        help: 'Build flavor passed to flutter build.',
      )
      ..addMultiOption(
        'dart-define',
        help: 'Dart define passed to flutter build (KEY=VALUE).',
      )
      ..addFlag(
        'obfuscate',
        defaultsTo: false,
        help: 'Enable Dart obfuscation + split-debug-info.',
      )
      ..addFlag(
        'tree-shake-icons',
        defaultsTo: false,
        help: 'Remove unused Material icons.',
      )
      ..addFlag(
        'analyze-only',
        defaultsTo: false,
        help: 'Audit without building.',
      )
      ..addOption(
        'report',
        defaultsTo: 'console',
        allowed: const ['console', 'json', 'html'],
        help: 'Report output format.',
      )
      ..addOption(
        'report-output',
        help: 'File path to write the report.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        defaultsTo: false,
        help: 'Verbose logging.',
      );
  }

  final OptimizerPipeline? _injectedPipeline;
  final StringSink? _loggerSink;

  @override
  String get name => 'optimize';

  @override
  String get description =>
      'Analyze and optimize the size of a Flutter build artifact.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final level = args.flag('verbose') ? LogLevel.verbose : LogLevel.info;
    final logger = Logger(level: level, sink: _loggerSink);
    final projectDir = p.absolute(args.option('project-dir')!);

    final target = BuildTarget.values.byName(args.option('target')!);

    final pipeline = _injectedPipeline ??
        OptimizerPipeline(
          logger: logger,
          processRunner: const IOProcessRunner(),
        );

    try {
      final report = await pipeline.run(
        projectDir: projectDir,
        target: target,
        flavor: args.option('flavor'),
        dartDefines: args.multiOption('dart-define'),
        obfuscate: args.flag('obfuscate'),
        treeShakeIcons: args.flag('tree-shake-icons'),
        analyzeOnly: args.flag('analyze-only'),
      );

      final format = args.option('report')!;
      final reporter = _reporterFor(format, logger);
      final output = reporter.render(report);

      final outputPath = args.option('report-output');
      if (outputPath != null) {
        await File(outputPath).writeAsString(output);
        logger.success('Report written to $outputPath');
      } else {
        // ignore: avoid_print
        print(output);
      }

      return 0;
    } on BuildOptimizerException catch (e) {
      logger.error(e.toString());
      return 1;
    }
  }

  Reporter _reporterFor(String format, Logger logger) => switch (format) {
        'json' => const JsonReporter(),
        'html' => const HtmlReporter(),
        _ => ConsoleReporter(logger: logger),
      };
}
