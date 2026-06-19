import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../reporter/report_model.dart';
import '../util/logger.dart';

/// Analyzes declared assets and fonts for unused or over-declared entries.
class AssetAnalyzer {
  /// Creates an asset analyzer.
  AssetAnalyzer({
    required this.projectDir,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Analyzes assets and fonts declared in [pubspec].
  Future<List<Finding>> analyze(YamlMap pubspec) async {
    final findings = <Finding>[];
    findings.addAll(await _analyzeAssets(pubspec));
    findings.addAll(await _analyzeFonts(pubspec));
    return findings;
  }

  Future<List<Finding>> _analyzeAssets(YamlMap pubspec) async {
    final findings = <Finding>[];
    final flutter = pubspec['flutter'];
    if (flutter is! YamlMap) return findings;

    final assets = flutter['assets'];
    if (assets is! YamlList) return findings;

    final sourceFiles = await _collectSourceFiles();
    final sourceContent = StringBuffer();
    for (final file in sourceFiles) {
      try {
        sourceContent.writeln(await file.readAsString());
      } on FileSystemException catch (e) {
        logger.verbose('Could not read ${file.path}: ${e.message}');
      }
    }
    final code = sourceContent.toString();

    for (final asset in assets) {
      if (asset is! String) continue;

      final assetPath = asset.endsWith('/') ? asset : asset;
      final patterns = <String>[
        assetPath,
        assetPath.replaceAll('assets/', ''),
      ];

      final referenced = patterns.any((pattern) => code.contains(pattern));
      if (!referenced) {
        final filePath = p.join(projectDir, assetPath);
        final size = _fileSize(filePath);
        findings.add(Finding(
          id: 'unused_asset',
          severity: FindingSeverity.warning,
          title: 'Unused asset: $assetPath',
          description: 'The asset is declared in pubspec.yaml but not '
              'referenced in lib/.',
          recommendation: 'Remove the asset from pubspec.yaml and delete the '
              'file if it is no longer needed.',
          estimatedSavingsBytes: size,
        ));
      }
    }

    return findings;
  }

  Future<List<Finding>> _analyzeFonts(YamlMap pubspec) async {
    final findings = <Finding>[];
    final flutter = pubspec['flutter'];
    if (flutter is! YamlMap) return findings;

    final fonts = flutter['fonts'];
    if (fonts is! YamlList) return findings;

    final sourceFiles = await _collectSourceFiles();
    final sourceContent = StringBuffer();
    for (final file in sourceFiles) {
      try {
        sourceContent.writeln(await file.readAsString());
      } on FileSystemException catch (e) {
        logger.verbose('Could not read ${file.path}: ${e.message}');
      }
    }
    final code = sourceContent.toString();

    for (final font in fonts) {
      if (font is! YamlMap) continue;
      final family = font['family'];
      if (family is! String) continue;

      final fontList = font['fonts'];
      if (fontList is! YamlList) continue;

      final used = code.contains("'$family'") || code.contains('"$family"');
      if (!used) {
        findings.add(Finding(
          id: 'unused_font_family',
          severity: FindingSeverity.warning,
          title: 'Unused font family: $family',
          description: 'The font family is declared but never referenced '
              'in lib/.',
          recommendation: 'Remove the unused font family from pubspec.yaml.',
        ));
        continue;
      }

      if (fontList.length > 2) {
        var totalSize = 0;
        for (final entry in fontList) {
          if (entry is YamlMap) {
            final asset = entry['asset'];
            if (asset is String) {
              totalSize += _fileSize(p.join(projectDir, asset));
            }
          }
        }
        findings.add(Finding(
          id: 'over_declared_font_weights',
          severity: FindingSeverity.info,
          title: 'Many font weights declared for $family',
          description: '${fontList.length} font weights are declared. '
              'Consider keeping only the weights actually used.',
          recommendation: 'Audit your UI and remove unused font weights.',
          estimatedSavingsBytes: totalSize ~/ 2,
        ));
      }
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

  int _fileSize(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }
}
