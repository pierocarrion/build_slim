import 'dart:convert';

import 'package:build_slim/src/reporter/json_reporter.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:test/test.dart';

void main() {
  const reporter = JsonReporter();

  OptimizationReport makeReport({
    List<Finding> findings = const [],
    List<String> appliedOptimizations = const [],
    int? beforeSizeBytes,
    int? afterSizeBytes,
    int? savedBytes,
    double? savedPercent,
    bool withRecommendation = true,
    bool withSavings = true,
  }) {
    final finding = findings.isEmpty
        ? Finding(
            id: 'f1',
            severity: FindingSeverity.warning,
            title: 't',
            description: 'd',
            recommendation: withRecommendation ? 'do something' : null,
            estimatedSavingsBytes: withSavings ? 1024 : null,
          )
        : null;
    return OptimizationReport(
      projectName: 'my-app',
      target: BuildTarget.apk,
      beforeSizeBytes: beforeSizeBytes,
      afterSizeBytes: afterSizeBytes,
      savedBytes: savedBytes,
      savedPercent: savedPercent,
      findings: finding == null ? findings : [finding],
      appliedOptimizations: appliedOptimizations,
      buildDurationMs: 100,
      dartSdkVersion: 'Dart 3.4.0',
      flutterVersion: 'Flutter 3.22.0',
      timestamp: DateTime.utc(2024, 1, 1),
    );
  }

  group('JsonReporter.render', () {
    test('returns valid indented JSON', () {
      final json = reporter.render(makeReport());
      expect(() => jsonDecode(json), returnsNormally);
      // 2-space indentation per JsonEncoder.withIndent('  ').
      expect(json, contains('\n  '));
    });

    test('round-trips with OptimizationReport.toJson', () {
      final report = makeReport();
      final rendered = reporter.render(report);
      expect(jsonDecode(rendered), report.toJson());
    });

    test('includes core top-level fields', () {
      final json = reporter.render(makeReport());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['projectName'], 'my-app');
      expect(decoded['target'], 'apk');
      expect(decoded['dartSdkVersion'], 'Dart 3.4.0');
      expect(decoded['flutterVersion'], 'Flutter 3.22.0');
      expect(decoded['timestamp'], isA<String>());
    });

    test('omits recommendation key when null', () {
      final json = reporter.render(makeReport(withRecommendation: false));
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final finding =
          (decoded['findings'] as List).first as Map<String, dynamic>;
      expect(finding.containsKey('recommendation'), isFalse);
    });

    test('omits estimatedSavingsBytes key when null', () {
      final json = reporter.render(makeReport(withSavings: false));
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final finding =
          (decoded['findings'] as List).first as Map<String, dynamic>;
      expect(finding.containsKey('estimatedSavingsBytes'), isFalse);
    });

    test('serializes nullable size fields as null when absent', () {
      final json = reporter.render(makeReport());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['beforeSizeBytes'], isNull);
      expect(decoded['afterSizeBytes'], isNull);
      expect(decoded['savedBytes'], isNull);
      expect(decoded['savedPercent'], isNull);
    });

    test('serializes empty findings and optimizations arrays', () {
      final report = OptimizationReport(
        projectName: 'p',
        target: BuildTarget.aab,
        findings: const [],
        appliedOptimizations: const [],
        dartSdkVersion: 'x',
        flutterVersion: 'y',
        timestamp: DateTime.utc(2024, 1, 1),
      );
      final json = reporter.render(report);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['findings'], isEmpty);
      expect(decoded['appliedOptimizations'], isEmpty);
    });

    test('serializes all enum values by name', () {
      for (final severity in FindingSeverity.values) {
        final report = OptimizationReport(
          projectName: 'p',
          target: BuildTarget.ipa,
          findings: [
            Finding(
              id: 'f',
              severity: severity,
              title: 't',
              description: 'd',
            ),
          ],
          dartSdkVersion: 'x',
          flutterVersion: 'y',
          timestamp: DateTime.utc(2024, 1, 1),
        );
        final json = reporter.render(report);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final finding =
            (decoded['findings'] as List).first as Map<String, dynamic>;
        expect(finding['severity'], severity.name);
      }
    });
  });
}
