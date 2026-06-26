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
    findings.addAll(await _analyzeLooseAssets());
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

      // Per-file subsetting recommendation: large TTF/OTF files ship
      // thousands of unused glyphs (CJK, Cyrillic, etc.).
      for (final entry in fontList) {
        if (entry is! YamlMap) continue;
        final asset = entry['asset'];
        if (asset is! String) continue;
        final ext = p.extension(asset).toLowerCase();
        if (ext != '.ttf' && ext != '.otf') continue;

        final size = _fileSize(p.join(projectDir, asset));
        if (size > _largeFontThresholdBytes) {
          findings.add(Finding(
            id: 'large_font_file',
            severity: FindingSeverity.warning,
            title: 'Large font file: $asset',
            description: '$asset is ${_formatBytes(size)}. Font files embed '
                'every glyph the typeface ships (CJK, Cyrillic, etc.) which '
                'a Latin-only app never renders.',
            recommendation: 'Subset the font to the scripts you actually use '
                'with `pyftsubset` (pip install fonttools). A Latin subset '
                'typically shrinks a 600KB file to ~30KB.',
            estimatedSavingsBytes: size ~/ 2,
          ));
        }
      }
    }

    return findings;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Scans the `assets/` directory for heavy media that bloats the artifact
  /// independently of pubspec declarations.
  ///
  /// Currently flags:
  /// - GIFs larger than [_heavyGifThresholdBytes] recommending Lottie/Rive.
  Future<List<Finding>> _analyzeLooseAssets() async {
    final findings = <Finding>[];
    final assetsDir = Directory(p.join(projectDir, 'assets'));
    if (!assetsDir.existsSync()) return findings;

    try {
      await for (final entity
          in assetsDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.gif') continue;

        final size = _fileSize(entity.path);
        if (size > _heavyGifThresholdBytes) {
          findings.add(Finding(
            id: 'heavy_gif',
            severity: FindingSeverity.critical,
            title:
                'Heavy GIF asset: ${p.relative(entity.path, from: projectDir)}',
            description: 'GIF animations are dramatically larger than modern '
                'vector formats. This file is ${_formatBytes(size)}.',
            recommendation: 'Replace with Lottie (.json) or Rive (.riv) for '
                '10-100x smaller animations with no quality loss.',
            estimatedSavingsBytes: size - (_heavyGifThresholdBytes ~/ 2),
          ));
        }
      }
    } on FileSystemException catch (e) {
      logger.verbose('Could not scan assets/ for heavy GIFs: ${e.message}');
    }
    return findings;
  }

  /// Bytes threshold above which a GIF triggers a critical finding.
  static const int _heavyGifThresholdBytes = 300 * 1024;

  /// Bytes threshold above which a font triggers a subsetting recommendation.
  static const int _largeFontThresholdBytes = 200 * 1024;

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
