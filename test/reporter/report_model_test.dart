import 'package:build_slim/src/reporter/report_model.dart';
import 'package:test/test.dart';

void main() {
  final report = OptimizationReport(
    projectName: 'test_app',
    target: BuildTarget.apk,
    beforeSizeBytes: 1000,
    afterSizeBytes: 800,
    savedBytes: 200,
    savedPercent: 20.0,
    findings: [
      const Finding(
        id: 'test_finding',
        severity: FindingSeverity.warning,
        title: 'Test Finding',
        description: 'A finding used in tests.',
        recommendation: 'Fix it.',
        estimatedSavingsBytes: 200,
      ),
    ],
    appliedOptimizations: ['Injected --tree-shake-icons'],
    buildDurationMs: 1234,
    dartSdkVersion: '3.4.0',
    flutterVersion: '3.22.0',
    timestamp: _fixedDate,
  );

  group('OptimizationReport.toJson', () {
    test('serializes report to JSON', () {
      final json = report.toJson();
      expect(json['projectName'], 'test_app');
      expect(json['target'], 'apk');
      expect(json['beforeSizeBytes'], 1000);
      expect(json['afterSizeBytes'], 800);
      expect(json['savedBytes'], 200);
      expect(json['savedPercent'], 20.0);
      expect((json['findings'] as List).length, 1);
      expect((json['appliedOptimizations'] as List).first,
          'Injected --tree-shake-icons');
    });

    test('serializes nullable size fields as null when absent', () {
      final r = OptimizationReport(
        projectName: 'p',
        target: BuildTarget.aab,
        dartSdkVersion: 'x',
        flutterVersion: 'y',
        timestamp: _fixedDate,
      );
      final json = r.toJson();
      expect(json['beforeSizeBytes'], isNull);
      expect(json['afterSizeBytes'], isNull);
      expect(json['savedBytes'], isNull);
      expect(json['savedPercent'], isNull);
    });

    test('serializes empty findings and appliedOptimizations arrays', () {
      final r = OptimizationReport(
        projectName: 'p',
        target: BuildTarget.ipa,
        findings: const [],
        appliedOptimizations: const [],
        dartSdkVersion: 'x',
        flutterVersion: 'y',
        timestamp: _fixedDate,
      );
      final json = r.toJson();
      expect(json['findings'], isEmpty);
      expect(json['appliedOptimizations'], isEmpty);
    });

    test('uses default buildDurationMs of 0', () {
      final r = OptimizationReport(
        projectName: 'p',
        target: BuildTarget.apk,
        dartSdkVersion: 'x',
        flutterVersion: 'y',
        timestamp: _fixedDate,
      );
      expect(r.buildDurationMs, 0);
      expect(r.toJson()['buildDurationMs'], 0);
    });

    test('serializes target enum by name for all variants', () {
      for (final target in BuildTarget.values) {
        final r = OptimizationReport(
          projectName: 'p',
          target: target,
          dartSdkVersion: 'x',
          flutterVersion: 'y',
          timestamp: _fixedDate,
        );
        expect(r.toJson()['target'], target.name);
      }
    });

    test('serializes timestamp as ISO-8601 string', () {
      expect(report.toJson()['timestamp'], _fixedDate.toIso8601String());
    });
  });

  group('Finding.toJson', () {
    test('serializes with recommendation when provided', () {
      const finding = Finding(
        id: 'x',
        severity: FindingSeverity.warning,
        title: 'T',
        description: 'D',
        recommendation: 'do something',
        estimatedSavingsBytes: 42,
      );
      final json = finding.toJson();
      expect(json['recommendation'], 'do something');
      expect(json['estimatedSavingsBytes'], 42);
    });

    test('omits recommendation key when null', () {
      const finding = Finding(
        id: 'x',
        severity: FindingSeverity.info,
        title: 'T',
        description: 'D',
      );
      final json = finding.toJson();
      expect(json.containsKey('recommendation'), isFalse);
    });

    test('omits estimatedSavingsBytes key when null', () {
      const finding = Finding(
        id: 'x',
        severity: FindingSeverity.warning,
        title: 'T',
        description: 'D',
      );
      final json = finding.toJson();
      expect(json.containsKey('estimatedSavingsBytes'), isFalse);
    });

    test('serializes all severity enum values by name', () {
      for (final severity in FindingSeverity.values) {
        final finding = Finding(
          id: 'x',
          severity: severity,
          title: 'T',
          description: 'D',
        );
        expect(finding.toJson()['severity'], severity.name);
      }
    });
  });

  group('BuildResult', () {
    test('round-trips all fields with values', () {
      const result = BuildResult(
        exitCode: 0,
        durationMs: 500,
        artifactPath: '/tmp/out.apk',
        artifactSizeBytes: 1234,
      );
      expect(result.exitCode, 0);
      expect(result.durationMs, 500);
      expect(result.artifactPath, '/tmp/out.apk');
      expect(result.artifactSizeBytes, 1234);
    });

    test('allows nullable artifactPath and artifactSizeBytes', () {
      const result = BuildResult(exitCode: 1, durationMs: 0);
      expect(result.artifactPath, isNull);
      expect(result.artifactSizeBytes, isNull);
    });
  });
}

final _fixedDate = DateTime.utc(2024, 1, 1);
