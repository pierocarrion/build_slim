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
      ..addFlag(
        'aggressive',
        defaultsTo: false,
        help: 'Enable destructive size optimizations (PNG→WebP conversion, '
            'R8 full mode, strict resource shrinking). Creates .bak backups '
            'of every modified file. Review changes before publishing.',
      )
      ..addMultiOption(
        'locales',
        help: 'Override the auto-detected supported locales (BCP-47 codes) '
            'injected as Android resConfigs, e.g. --locales en --locales es. '
            'When omitted, locales are detected from .arb / .lproj files.',
      )
      ..addOption(
        'keystore',
        help: 'Path to the release keystore (.jks/.keystore). When provided, '
            'android/key.properties is generated from the credentials below.',
      )
      ..addOption(
        'store-password',
        help: 'Password for the keystore file (use with --keystore).',
      )
      ..addOption(
        'key-alias',
        help: 'Alias of the key inside the keystore (use with --keystore).',
      )
      ..addOption(
        'key-password',
        help: 'Password for the key (use with --keystore).',
      )
      ..addOption(
        'signing-config',
        allowed: const ['debug', 'none'],
        defaultsTo: 'none',
        help: 'Set to "debug" to temporarily sign the release build with the '
            'debug keystore (validation only; do NOT publish). "none" leaves '
            'signing resolution to the standard key.properties flow.',
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
        aggressive: args.flag('aggressive'),
        locales: args.multiOption('locales'),
        keystore: args.option('keystore'),
        storePassword: args.option('store-password'),
        keyAlias: args.option('key-alias'),
        keyPassword: args.option('key-password'),
        debugSigning: args.option('signing-config') == 'debug',
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
