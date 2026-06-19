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

  test('finding serializes to JSON', () {
    const finding = Finding(
      id: 'x',
      severity: FindingSeverity.info,
      title: 'T',
      description: 'D',
    );
    final json = finding.toJson();
    expect(json['id'], 'x');
    expect(json['severity'], 'info');
    expect(json['recommendation'], isNull);
  });
}

final _fixedDate = DateTime.utc(2024, 1, 1);
