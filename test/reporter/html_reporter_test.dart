import 'package:build_slim/src/reporter/html_reporter.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:test/test.dart';

void main() {
  const reporter = HtmlReporter();

  OptimizationReport makeReport({
    List<Finding> findings = const [],
    List<String> appliedOptimizations = const [],
    int? beforeSizeBytes,
    int? afterSizeBytes,
    int? savedBytes,
    double? savedPercent,
    String projectName = 'my-app',
    BuildTarget target = BuildTarget.apk,
  }) =>
      OptimizationReport(
        projectName: projectName,
        target: target,
        beforeSizeBytes: beforeSizeBytes,
        afterSizeBytes: afterSizeBytes,
        savedBytes: savedBytes,
        savedPercent: savedPercent,
        findings: findings,
        appliedOptimizations: appliedOptimizations,
        dartSdkVersion: 'Dart 3.4.0',
        flutterVersion: 'Flutter 3.22.0',
        timestamp: DateTime.utc(2024, 1, 1),
      );

  group('HtmlReporter.render structure', () {
    test('returns a complete HTML document', () {
      final html = reporter.render(makeReport());
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<html'));
      expect(html, contains('</html>'));
    });

    test('renders project name in title and body', () {
      final html = reporter.render(makeReport(projectName: 'My-App'));
      expect(html, contains('Build Slim Report - My-App'));
      expect(html, contains('Project:'));
      expect(html, contains('My-App'));
    });

    test('renders target name in body', () {
      final html = reporter.render(makeReport(target: BuildTarget.aab));
      expect(html, contains('Target:'));
      expect(html, contains('aab'));
    });

    test('renders Dart and Flutter versions in footer', () {
      final html = reporter.render(makeReport());
      expect(html, contains('Dart 3.4.0'));
      expect(html, contains('Flutter 3.22.0'));
    });
  });

  group('HtmlReporter.render summary cards', () {
    test('shows Before / After / Saved / Reduction cards', () {
      final html = reporter.render(makeReport(
        beforeSizeBytes: 2 * 1024 * 1024,
        afterSizeBytes: 1 * 1024 * 1024,
        savedBytes: 1 * 1024 * 1024,
        savedPercent: 50.0,
      ));
      expect(html, contains('Before'));
      expect(html, contains('After'));
      expect(html, contains('Saved'));
      expect(html, contains('Reduction'));
      expect(html, contains('50.0%'));
    });

    test('shows "Added" label when savings are negative', () {
      final html = reporter.render(makeReport(
        beforeSizeBytes: 1000,
        afterSizeBytes: 2000,
        savedBytes: -1000,
        savedPercent: -100.0,
      ));
      expect(html, contains('Added'));
    });

    test('computes savedBytes when null using before - after', () {
      final html = reporter.render(makeReport(
        beforeSizeBytes: 2000,
        afterSizeBytes: 1000,
        savedBytes: null,
        savedPercent: null,
      ));
      // savedBytes defaults to before-after = 1000; percent computed.
      expect(html, contains('50.0%'));
    });

    test('uses 0.0 percent when before <= 0 and savedPercent null', () {
      final html = reporter.render(makeReport(
        beforeSizeBytes: 0,
        afterSizeBytes: 0,
        savedBytes: null,
        savedPercent: null,
      ));
      expect(html, contains('0.0%'));
    });

    test('defaults before/after to 0 when null', () {
      final html = reporter.render(makeReport());
      // Both cards should show "0 B".
      expect(html, contains('0 B'));
    });
  });

  group('HtmlReporter.render optimizations', () {
    test('lists applied optimizations', () {
      final html = reporter.render(makeReport(
        appliedOptimizations: ['Injected --obfuscate', 'Patched gradle'],
      ));
      expect(html, contains('Injected --obfuscate'));
      expect(html, contains('Patched gradle'));
    });

    test('shows None when no optimizations applied', () {
      final html = reporter.render(makeReport());
      expect(html, contains('None'));
    });
  });

  group('HtmlReporter.render findings', () {
    test('shows "No findings" message when empty', () {
      final html = reporter.render(makeReport());
      expect(html, contains('No findings'));
    });

    test('renders each finding with badge class and title', () {
      final html = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f1',
          severity: FindingSeverity.error,
          title: 'Boom',
          description: 'Desc',
        ),
        const Finding(
          id: 'f2',
          severity: FindingSeverity.warning,
          title: 'Careful',
          description: 'Desc2',
        ),
        const Finding(
          id: 'f3',
          severity: FindingSeverity.info,
          title: 'Heads up',
          description: 'Desc3',
        ),
      ]));
      expect(html, contains('badge-error'));
      expect(html, contains('badge-warning'));
      expect(html, contains('badge-info'));
      expect(html, contains('Boom'));
      expect(html, contains('Careful'));
      expect(html, contains('Heads up'));
    });

    test('renders recommendation paragraph when present', () {
      final html = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f1',
          severity: FindingSeverity.warning,
          title: 'T',
          description: 'D',
          recommendation: 'Fix it',
        ),
      ]));
      expect(html, contains('Fix it'));
      expect(html, contains('recommendation'));
    });

    test('renders savings span when estimatedSavingsBytes present', () {
      final html = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f1',
          severity: FindingSeverity.warning,
          title: 'T',
          description: 'D',
          estimatedSavingsBytes: 2 * 1024 * 1024,
        ),
      ]));
      expect(html, contains('savings'));
      expect(html, contains('2.0 MB'));
    });
  });

  group('HtmlReporter.render HTML escaping', () {
    test('escapes project name to prevent XSS', () {
      final html =
          reporter.render(makeReport(projectName: '<script>x</script>'));
      expect(html, isNot(contains('<script>x</script>')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('escapes finding title and description', () {
      final html = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f',
          severity: FindingSeverity.warning,
          title: '<b>bold</b>',
          description: '<i>italic</i>',
        ),
      ]));
      expect(html, isNot(contains('<b>bold</b>')));
      expect(html, isNot(contains('<i>italic</i>')));
      expect(html, contains('&lt;b&gt;'));
    });

    test('escapes applied optimization strings', () {
      final html = reporter.render(makeReport(
        appliedOptimizations: ['<iframe>'],
      ));
      expect(html, isNot(contains('<iframe>')));
      expect(html, contains('&lt;iframe&gt;'));
    });

    test('escapes recommendation text', () {
      final html = reporter.render(makeReport(findings: [
        const Finding(
          id: 'f',
          severity: FindingSeverity.warning,
          title: 't',
          description: 'd',
          recommendation: '<script>alert(1)</script>',
        ),
      ]));
      expect(html, contains('alert(1)'));
      expect(html, isNot(contains('<script>alert(1)</script>')));
    });
  });
}
