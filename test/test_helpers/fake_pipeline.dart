import 'package:build_slim/src/builder/artifact_comparator.dart';
import 'package:build_slim/src/optimizer/optimizer_pipeline.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:build_slim/src/util/process_runner.dart';

/// A fake [OptimizerPipeline] that records calls and returns a canned
/// [OptimizationReport], or throws a [BuildOptimizerException] on demand.
class FakeOptimizerPipeline extends OptimizerPipeline {
  /// Creates a fake pipeline.
  FakeOptimizerPipeline({
    required this.report,
    this.shouldThrow = false,
  }) : super(
          logger: Logger(level: LogLevel.none),
          processRunner: _NoopProcessRunner(),
        );

  /// Report returned by [run].
  final OptimizationReport report;

  /// When true, [run] throws a [BuildOptimizerException].
  final bool shouldThrow;

  /// Last call arguments observed by [run], or null if never called.
  PipelineCall? lastCall;

  /// Number of times [run] was invoked.
  int callCount = 0;

  @override
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
    callCount++;
    lastCall = PipelineCall(
      projectDir: projectDir,
      target: target,
      flavor: flavor,
      dartDefines: List<String>.unmodifiable(dartDefines),
      obfuscate: obfuscate,
      treeShakeIcons: treeShakeIcons,
      analyzeOnly: analyzeOnly,
      aggressive: aggressive,
      locales: List<String>.unmodifiable(locales),
      keystore: keystore,
      storePassword: storePassword,
      keyAlias: keyAlias,
      keyPassword: keyPassword,
      debugSigning: debugSigning,
    );
    if (shouldThrow) {
      throw const BuildOptimizerException('pipeline failure');
    }
    return report;
  }
}

/// Snapshot of the arguments passed to [FakeOptimizerPipeline.run].
class PipelineCall {
  /// Creates a snapshot.
  const PipelineCall({
    required this.projectDir,
    required this.target,
    required this.flavor,
    required this.dartDefines,
    required this.obfuscate,
    required this.treeShakeIcons,
    required this.analyzeOnly,
    required this.aggressive,
    required this.locales,
    this.keystore,
    this.storePassword,
    this.keyAlias,
    this.keyPassword,
    this.debugSigning = false,
  });

  /// Project dir.
  final String projectDir;

  /// Build target.
  final BuildTarget target;

  /// Optional flavor.
  final String? flavor;

  /// Dart defines.
  final List<String> dartDefines;

  /// Obfuscate flag.
  final bool obfuscate;

  /// Tree-shake-icons flag.
  final bool treeShakeIcons;

  /// Analyze-only flag.
  final bool analyzeOnly;

  /// Aggressive optimizations flag.
  final bool aggressive;

  /// Locales override passed via --locales.
  final List<String> locales;

  /// Keystore path passed via --keystore, if any.
  final String? keystore;

  /// Store password passed via --store-password, if any.
  final String? storePassword;

  /// Key alias passed via --key-alias, if any.
  final String? keyAlias;

  /// Key password passed via --key-password, if any.
  final String? keyPassword;

  /// Whether debug signing was requested.
  final bool debugSigning;
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
  }
}
