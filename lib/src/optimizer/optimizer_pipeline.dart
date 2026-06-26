import '../analyzer/locale_detector.dart';
import '../analyzer/project_analyzer.dart';
import '../builder/artifact_comparator.dart';
import '../builder/build_runner.dart';
import '../reporter/report_model.dart';
import '../util/logger.dart';
import '../util/process_runner.dart';
import 'android_optimizer.dart';
import 'asset_optimizer.dart';
import 'dart_optimizer.dart';
import 'ios_optimizer.dart';
import 'signing_configurator.dart';
import 'webp_optimizer.dart';

/// Orchestrates analysis, patching, build, and report generation.
class OptimizerPipeline {
  /// Creates the optimizer pipeline.
  OptimizerPipeline({
    required this.logger,
    required this.processRunner,
  });

  /// Logger for diagnostic output.
  final Logger logger;

  /// Process runner used for build commands and version lookups.
  final ProcessRunner processRunner;

  /// Runs the full optimization pipeline for [projectDir].
  Future<OptimizationReport> run({
    required String projectDir,
    required BuildTarget target,
    String? flavor,
    List<String> dartDefines = const [],
    bool obfuscate = false,
    bool treeShakeIcons = false,
    bool analyzeOnly = false,
    bool aggressive = false,
    List<String> locales = const [],
    String? keystore,
    String? storePassword,
    String? keyAlias,
    String? keyPassword,
    bool debugSigning = false,
  }) async {
    logger.info('Analyzing project at $projectDir...');
    final analyzer = ProjectAnalyzer(
      projectDir: projectDir,
      logger: logger,
      target: target,
    );
    final findings = await analyzer.analyze();
    final projectName = await analyzer.projectName();

    // Resolve supported locales: explicit --locales wins, otherwise auto-detect
    // from ARB / .lproj. Auto-detected findings surface in the report so users
    // know to override when the heuristic misses.
    List<String> resolvedLocales = locales;
    if (resolvedLocales.isEmpty) {
      final detection = await LocaleDetector(
        projectDir: projectDir,
        logger: logger,
      ).detect();
      resolvedLocales = detection.locales;
      findings.addAll(detection.findings);
    }

    if (analyzeOnly) {
      logger.info('Analyze-only mode; skipping build.');
      return OptimizationReport(
        projectName: projectName,
        target: target,
        findings: findings,
        dartSdkVersion: await _dartVersion(),
        flutterVersion: await _flutterVersion(),
        timestamp: DateTime.now().toUtc(),
      );
    }

    final appliedOptimizations = <String>[];

    logger.info('Applying safe optimizations...');

    final dartOptimizer = DartOptimizer(logger: logger);
    appliedOptimizations.addAll(
      dartOptimizer.optimize(
        obfuscate: obfuscate,
        treeShakeIcons: treeShakeIcons,
      ),
    );

    final androidOptimizer = AndroidOptimizer(
      projectDir: projectDir,
      logger: logger,
      aggressive: aggressive,
      locales: resolvedLocales,
    );
    appliedOptimizations.addAll(await androidOptimizer.optimize());

    final iosOptimizer = IosOptimizer(
      projectDir: projectDir,
      logger: logger,
    );
    appliedOptimizations.addAll(await iosOptimizer.optimize());

    // WebP conversion runs before generic asset compression so the latter can
    // still recompress any WebP that cwebp left suboptimal. Only active under
    // --aggressive; otherwise a documented no-op.
    final webpConverter = WebPConverter(
      projectDir: projectDir,
      logger: logger,
      processRunner: processRunner,
      aggressive: aggressive,
    );
    appliedOptimizations.addAll(await webpConverter.convert());

    final assetOptimizer = AssetOptimizer(
      projectDir: projectDir,
      logger: logger,
      processRunner: processRunner,
    );
    appliedOptimizations.addAll(await assetOptimizer.optimize());

    // Resolve release signing for Android targets before building.
    if (target == BuildTarget.apk || target == BuildTarget.aab) {
      final signingConfigurator = SigningConfigurator(
        projectDir: projectDir,
        logger: logger,
      );
      final signingResult = await signingConfigurator.configure(
        keystore: keystore,
        storePassword: storePassword,
        keyAlias: keyAlias,
        keyPassword: keyPassword,
        debugSigning: debugSigning,
      );
      if (signingResult.applied) {
        appliedOptimizations.add(
          'Signing: ${signingResult.reason ?? signingResult.action.name}',
        );
      }
    }

    logger.info('Building $target...');
    final buildRunner = BuildRunner(
      projectDir: projectDir,
      processRunner: processRunner,
      logger: logger,
    );
    final buildResult = await buildRunner.build(
      target: target,
      flavor: flavor,
      dartDefines: dartDefines,
      obfuscate: obfuscate || dartOptimizer.obfuscateInjected,
      treeShakeIcons: treeShakeIcons || dartOptimizer.treeShakeIconsInjected,
      splitDebugInfo: dartOptimizer.splitDebugInfoPath,
    );

    if (buildResult.exitCode != 0) {
      throw BuildOptimizerException(
        'Build failed with exit code ${buildResult.exitCode}.',
      );
    }

    logger.success(
      'Build complete: ${buildResult.artifactPath ?? 'unknown artifact'} '
      '(${_formatSize(buildResult.artifactSizeBytes)})',
    );

    return OptimizationReport(
      projectName: projectName,
      target: target,
      afterSizeBytes: buildResult.artifactSizeBytes,
      findings: findings,
      appliedOptimizations: appliedOptimizations,
      buildDurationMs: buildResult.durationMs,
      dartSdkVersion: await _dartVersion(),
      flutterVersion: await _flutterVersion(),
      timestamp: DateTime.now().toUtc(),
    );
  }

  Future<String> _dartVersion() async {
    try {
      final result = await processRunner.run('dart', const ['--version']);
      final output = result.stderr.trim().isEmpty
          ? result.stdout.trim()
          : result.stderr.trim();
      return output.split('\n').first.trim();
    } on ProcessRunnerException catch (e) {
      logger.verbose('Could not detect Dart version: $e');
      return 'unknown';
    }
  }

  Future<String> _flutterVersion() async {
    try {
      final result = await processRunner.run('flutter', const ['--version']);
      return result.stdout.trim().split('\n').first.trim();
    } on ProcessRunnerException catch (e) {
      logger.verbose('Could not detect Flutter version: $e');
      return 'unknown';
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return 'unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
