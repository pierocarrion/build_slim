import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../reporter/report_model.dart';
import '../util/logger.dart';

/// Analyzes dependencies and flags known heavy or duplicate packages.
class DependencyAnalyzer {
  /// Creates a dependency analyzer.
  DependencyAnalyzer({
    required this.projectDir,
    required this.logger,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Known heavy packages and their approximate release-size impact in bytes.
  static const Map<String, int> _knownHeavyPackages = {
    'firebase_core': 5 * 1024 * 1024,
    'firebase_auth': 4 * 1024 * 1024,
    'cloud_firestore': 6 * 1024 * 1024,
    'google_maps_flutter': 8 * 1024 * 1024,
    'video_player': 3 * 1024 * 1024,
    'image_picker': 2 * 1024 * 1024,
    'flutter_html': 2 * 1024 * 1024,
  };

  /// Package groups that often duplicate functionality.
  static const Map<String, List<String>> _duplicateGroups = {
    'image': ['cached_network_image', 'image', 'extended_image'],
    'http': ['http', 'dio', 'requests'],
  };

  /// Analyzes pubspec.lock and returns findings.
  Future<List<Finding>> analyze() async {
    final findings = <Finding>[];
    final lockFile = File(p.join(projectDir, 'pubspec.lock'));

    if (!lockFile.existsSync()) {
      logger.warning('pubspec.lock not found; run `flutter pub get` first.');
      return findings;
    }

    final YamlMap lock;
    try {
      lock = loadYaml(await lockFile.readAsString()) as YamlMap;
    } on YamlException catch (e) {
      logger.warning('Could not parse pubspec.lock: ${e.message}');
      return findings;
    }

    final packages = lock['packages'];
    if (packages is! YamlMap) return findings;

    final packageNames = packages.keys.cast<String>().toSet();

    for (final name in packageNames) {
      final impact = _knownHeavyPackages[name];
      if (impact != null) {
        findings.add(Finding(
          id: 'heavy_dependency_$name',
          severity: FindingSeverity.warning,
          title: 'Heavy dependency: $name',
          description: '$name is known to add approximately '
              '${_formatBytes(impact)} to release artifacts.',
          recommendation: 'Evaluate whether all features are needed, or '
              'consider lazy loading via deferred imports if applicable.',
          estimatedSavingsBytes: impact,
        ));
      }
    }

    for (final groupName in _duplicateGroups.keys) {
      final group = _duplicateGroups[groupName]!;
      final present = group.where(packageNames.contains).toList();
      if (present.length > 1) {
        findings.add(Finding(
          id: 'duplicate_dependency_group_$groupName',
          severity: FindingSeverity.warning,
          title: 'Duplicate $groupName dependencies',
          description: 'Multiple packages from the same group are present: '
              '${present.join(', ')}.',
          recommendation: 'Consolidate on a single package to reduce binary '
              'size and maintenance overhead.',
        ));
      }
    }

    return findings;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
