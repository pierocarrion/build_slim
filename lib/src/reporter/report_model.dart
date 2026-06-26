import 'package:meta/meta.dart';

/// Severity of an analysis finding.
enum FindingSeverity {
  /// An issue that prevents optimization or is likely to cause build failures.
  error,

  /// A high-priority issue with significant impact (e.g. large media assets).
  /// Rendered above [warning] but below [error].
  critical,

  /// A suboptimal configuration that should be addressed.
  warning,

  /// An informational observation.
  info,
}

/// Build artifact target.
enum BuildTarget {
  /// Android APK.
  apk,

  /// Android App Bundle.
  aab,

  /// iOS IPA.
  ipa,
}

/// A single analysis finding.
@immutable
class Finding {
  /// Creates a finding.
  const Finding({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    this.recommendation,
    this.estimatedSavingsBytes,
    this.breaking = false,
  });

  /// Stable identifier used for grouping and test assertions.
  final String id;

  /// Severity of the finding.
  final FindingSeverity severity;

  /// Short human-readable title.
  final String title;

  /// Detailed description.
  final String description;

  /// Optional recommendation for how to resolve the finding.
  final String? recommendation;

  /// Optional estimated byte savings if the finding is addressed.
  final int? estimatedSavingsBytes;

  /// Whether addressing this finding may break the build at runtime.
  ///
  /// Used by reporters to render a warning badge so users know to review the
  /// change carefully before publishing (e.g. R8 full mode, strict shrink).
  final bool breaking;

  /// Serializes this finding to JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'severity': severity.name,
        'title': title,
        'description': description,
        if (recommendation != null) 'recommendation': recommendation,
        if (estimatedSavingsBytes != null)
          'estimatedSavingsBytes': estimatedSavingsBytes,
        if (breaking) 'breaking': breaking,
      };
}

/// Result of a build invocation.
@immutable
class BuildResult {
  /// Creates a build result.
  const BuildResult({
    required this.exitCode,
    required this.durationMs,
    this.artifactPath,
    this.artifactSizeBytes,
  });

  /// Exit code returned by the build process.
  final int exitCode;

  /// Build duration in milliseconds.
  final int durationMs;

  /// Path to the produced artifact, if known.
  final String? artifactPath;

  /// Size of the produced artifact in bytes, if known.
  final int? artifactSizeBytes;
}

/// Final optimization report produced for a project.
@immutable
class OptimizationReport {
  /// Creates an optimization report.
  const OptimizationReport({
    required this.projectName,
    required this.target,
    this.beforeSizeBytes,
    this.afterSizeBytes,
    this.savedBytes,
    this.savedPercent,
    this.findings = const [],
    this.appliedOptimizations = const [],
    this.buildDurationMs = 0,
    required this.dartSdkVersion,
    required this.flutterVersion,
    required this.timestamp,
  });

  /// Project name, usually read from pubspec.yaml.
  final String projectName;

  /// Target artifact type.
  final BuildTarget target;

  /// Artifact size before optimization, if known.
  final int? beforeSizeBytes;

  /// Artifact size after optimization, if known.
  final int? afterSizeBytes;

  /// Bytes saved, if known.
  final int? savedBytes;

  /// Percentage saved, if known.
  final double? savedPercent;

  /// Analysis findings.
  final List<Finding> findings;

  /// Human-readable list of applied optimizations.
  final List<String> appliedOptimizations;

  /// Build duration in milliseconds.
  final int buildDurationMs;

  /// Dart SDK version detected at runtime.
  final String dartSdkVersion;

  /// Flutter version detected at runtime.
  final String flutterVersion;

  /// Time when the report was generated.
  final DateTime timestamp;

  /// Serializes this report to JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectName': projectName,
        'target': target.name,
        'beforeSizeBytes': beforeSizeBytes,
        'afterSizeBytes': afterSizeBytes,
        'savedBytes': savedBytes,
        'savedPercent': savedPercent,
        'findings': findings.map((f) => f.toJson()).toList(),
        'appliedOptimizations': appliedOptimizations,
        'buildDurationMs': buildDurationMs,
        'dartSdkVersion': dartSdkVersion,
        'flutterVersion': flutterVersion,
        'timestamp': timestamp.toIso8601String(),
      };
}
