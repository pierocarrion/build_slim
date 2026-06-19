import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../builder/artifact_comparator.dart';
import '../reporter/report_model.dart';
import '../util/logger.dart';
import 'asset_analyzer.dart';
import 'dart_analyzer.dart';
import 'dependency_analyzer.dart';
import 'native_config_analyzer.dart';

/// Coordinates all analyzers and aggregates findings for a Flutter project.
class ProjectAnalyzer {
  /// Creates a project analyzer for [projectDir].
  ProjectAnalyzer({
    required this.projectDir,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Runs all registered analyzers and returns combined findings.
  Future<List<Finding>> analyze() async {
    final findings = <Finding>[];

    logger.verbose('Reading pubspec.yaml...');
    final pubspec = await _loadPubspec();

    findings.addAll(await AssetAnalyzer(projectDir: projectDir, logger: logger)
        .analyze(pubspec));
    findings.addAll(
        await DependencyAnalyzer(projectDir: projectDir, logger: logger)
            .analyze());
    findings.addAll(
        await NativeConfigAnalyzer(projectDir: projectDir, logger: logger)
            .analyze());
    findings.addAll(
        await DartAnalyzer(projectDir: projectDir, logger: logger).analyze());

    return findings;
  }

  /// Reads the project name from pubspec.yaml.
  Future<String> projectName() async {
    final pubspec = await _loadPubspec();
    final name = pubspec['name'];
    return name is String ? name : 'unknown';
  }

  Future<YamlMap> _loadPubspec() async {
    final file = File(p.join(projectDir, 'pubspec.yaml'));
    if (!file.existsSync()) {
      throw BuildOptimizerException(
        'pubspec.yaml not found in $projectDir',
        filePath: file.path,
      );
    }
    try {
      final content = await file.readAsString();
      final doc = loadYaml(content);
      if (doc is YamlMap) return doc;
      throw BuildOptimizerException(
        'pubspec.yaml is not a valid YAML map',
        filePath: file.path,
      );
    } on YamlException catch (e) {
      throw BuildOptimizerException(
        'Failed to parse pubspec.yaml: ${e.message}',
        filePath: file.path,
        lineNumber: e.span?.start.line,
      );
    }
  }
}
