import 'dart:convert';

import '../builder/artifact_comparator.dart';
import 'report_model.dart';

/// Renders an [OptimizationReport] as indented JSON.
class JsonReporter implements Reporter {
  /// Creates a JSON reporter.
  const JsonReporter();

  @override
  String render(OptimizationReport report) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(report.toJson());
  }
}
