import 'package:build_slim/src/reporter/console_reporter.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:test/test.dart';

void main() {
  late StringBuffer sink;
  late Logger logger;
  late ConsoleReporter reporter;

  setUp(() {
    sink = StringBuffer();
    logger = Logger(level: LogLevel.none, sink: sink);
    reporter = ConsoleReporter(logger: logger);
  });

  OptimizationReport makeReport({
    List<Finding> findings = const [],
    List<String> appliedOptimizations = const [],
    int? beforeSizeBytes,
    int? afterSizeBytes,
    double? savedPercent,
    String projectName = 'my-app',
    BuildTarget target = BuildTarget.apk,
  }) =>
      OptimizationReport(
        projectName: projectName,
        target: target,
        beforeSizeBytes: beforeSizeBytes,
        afterSizeBytes: afterSizeBytes,
        savedPercent: savedPercent,
        findings: findings,
        appliedOptimizations: appliedOptimizations,
        dartSdkVersion: 'Dart 3.4.0',
        flutterVersion: 'Flutter 3.22.0',
        timestamp: DateTime.utc(2024, 1, 1),
      );

  group('ConsoleReporter.render header', () {
    test('renders project name and target', () {
      final out = reporter.render(makeReport());
      expect(out, contains('Build Slim Report: my-app'));
      expect(out, contains('Target: apk'));
    });

    test('renders Dart and Flutter versions', () {
      final out = reporter.render(makeReport());
      expect(out, contains('Dart: Dart 3.4.0'));
      expect(out, contains('Flutter: Flutter 3.22.0'));
    });

    test('renders different target name when provided', () {
      final out = reporter.render(makeReport(target: BuildTarget.ipa));
      expect(out, contains('Target: ipa'));
    });
  });

  group('ConsoleReporter.render applied optimizations block', () {
    test('lists applied optimizations when present', () {
      final out = reporter.render(makeReport(
        appliedOptimizations: ['Injected --obfuscate', 'Patched gradle'],
      ));
      expect(out, contains('Applied optimizations:'));
      expect(out, contains('Injected --obfuscate'));
      expect(out, contains('Patched gradle'));
    });

    test('omits applied optimizations section when empty', () {
      final out = reporter.render(makeReport(appliedOptimizations: const []));
      expect(out, isNot(contains('Applied optimizations:')));
    });
  });

  group('ConsoleReporter.render findings block', () {
    test('prints well-optimized message when findings empty', () {
      final out = reporter.render(makeReport());
      expect(out, contains('well-optimized'));
      expect(out, isNot(contains('Findings:')));
    });

    test('renders each finding with id, title, description', () {
      final out = reporter.render(makeReport(findings: [
        const Finding(
          id: 'my_finding',
          severity: FindingSeverity.warning,
          title: 'Some issue',
          description: 'Longer description text',
        ),
      ]));
      expect(out, contains('my_finding'));
      expect(out, contains('Some issue'));
      expect(out, contains('Longer description text'));
    });

    test('renders recommendation when present', () {
      final out = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f1',
          severity: FindingSeverity.warning,
          title: 'T',
          description: 'D',
          recommendation: 'Do something',
        ),
      ]));
      expect(out, contains('Do something'));
    });

    test('omits recommendation line when absent', () {
      final out = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f1',
          severity: FindingSeverity.warning,
          title: 'T',
          description: 'D',
        ),
      ]));
      // The arrow marker is only emitted for recommendations.
      expect(out, isNot(contains('→')));
    });

    test('renders estimated savings hint when present', () {
      final out = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f1',
          severity: FindingSeverity.warning,
          title: 'T',
          description: 'D',
          estimatedSavingsBytes: 2 * 1024 * 1024,
        ),
      ]));
      expect(out, contains('~2.0 MB saved'));
    });

    test('renders all three severity labels', () {
      final out = reporter.render(makeReport(findings: [
        const Finding(
            id: 'e',
            severity: FindingSeverity.error,
            title: 't',
            description: 'd'),
        const Finding(
            id: 'w',
            severity: FindingSeverity.warning,
            title: 't',
            description: 'd'),
        const Finding(
            id: 'i',
            severity: FindingSeverity.info,
            title: 't',
            description: 'd'),
      ]));
      expect(out, contains('error'));
      expect(out, contains('warning'));
      expect(out, contains('info'));
    });
  });

  group('ConsoleReporter.render size summary', () {
    test('renders before/after/saved when both sizes present', () {
      final out = reporter.render(makeReport(
        beforeSizeBytes: 2000,
        afterSizeBytes: 1000,
        savedPercent: 50.0,
      ));
      expect(out, contains('Before:'));
      expect(out, contains('After:'));
      expect(out, contains('50.0%'));
    });

    test('renders artifact size line when only after is present', () {
      final out = reporter.render(makeReport(afterSizeBytes: 1500));
      expect(out, contains('Artifact size:'));
      expect(out, isNot(contains('Before:')));
    });

    test('omits size line when neither before nor after present', () {
      final out = reporter.render(makeReport());
      expect(out, isNot(contains('Artifact size')));
      expect(out, isNot(contains('Before:')));
    });
  });
}
