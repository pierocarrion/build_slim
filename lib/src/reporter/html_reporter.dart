import 'dart:convert';

import '../builder/artifact_comparator.dart';
import '../util/file_size_util.dart';
import 'report_model.dart';

/// Renders an [OptimizationReport] as a self-contained HTML page.
class HtmlReporter implements Reporter {
  /// Creates an HTML reporter.
  const HtmlReporter();

  @override
  String render(OptimizationReport report) {
    final before = report.beforeSizeBytes ?? 0;
    final after = report.afterSizeBytes ?? 0;
    final saved = report.savedBytes ?? (before - after);
    final percent =
        report.savedPercent ?? (before > 0 ? (saved / before * 100) : 0.0);

    final findingsHtml = report.findings.map((finding) {
      final badgeClass = 'badge-${finding.severity.name}';
      final savings = finding.estimatedSavingsBytes == null
          ? ''
          : '<span class="savings">~${FileSizeUtil.format(finding.estimatedSavingsBytes!)}</span>';
      return '''
      <div class="finding">
        <div class="finding-header">
          <span class="badge $badgeClass">${finding.severity.name}</span>
          <strong>${_escapeHtml(finding.title)}</strong>
          $savings
        </div>
        <p>${_escapeHtml(finding.description)}</p>
        ${finding.recommendation == null ? '' : '<p class="recommendation">→ ${_escapeHtml(finding.recommendation!)}</p>'}
      </div>
      ''';
    }).join('\n');

    final optimizationsHtml = report.appliedOptimizations
        .map((o) => '<li>${_escapeHtml(o)}</li>')
        .join('\n');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Build Slim Report - ${_escapeHtml(report.projectName)}</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; color: #222; }
    h1, h2 { font-weight: 600; }
    .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; margin: 1rem 0; }
    .card { border: 1px solid #ddd; border-radius: 8px; padding: 1rem; text-align: center; }
    .card .value { font-size: 1.5rem; font-weight: 700; }
    .finding { border: 1px solid #eee; border-radius: 6px; padding: 1rem; margin: 0.5rem 0; }
    .finding-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem; }
    .badge { border-radius: 4px; padding: 0.2rem 0.5rem; font-size: 0.8rem; text-transform: uppercase; color: #fff; }
    .badge-error { background: #d32f2f; }
    .badge-warning { background: #f57c00; }
    .badge-info { background: #1976d2; }
    .savings { color: #388e3c; font-weight: 600; margin-left: auto; }
    .recommendation { color: #00695c; }
    ul { line-height: 1.6; }
  </style>
</head>
<body>
  <h1>Build Slim Report</h1>
  <p>Project: <strong>${_escapeHtml(report.projectName)}</strong> · Target: <strong>${report.target.name}</strong></p>

  <div class="summary">
    <div class="card">
      <div class="value">${FileSizeUtil.format(before)}</div>
      <div>Before</div>
    </div>
    <div class="card">
      <div class="value">${FileSizeUtil.format(after)}</div>
      <div>After</div>
    </div>
    <div class="card">
      <div class="value">${FileSizeUtil.format(saved.abs())}</div>
      <div>${saved >= 0 ? 'Saved' : 'Added'}</div>
    </div>
    <div class="card">
      <div class="value">${percent.toStringAsFixed(1)}%</div>
      <div>Reduction</div>
    </div>
  </div>

  <h2>Applied Optimizations</h2>
  <ul>
    ${optimizationsHtml.isEmpty ? '<li>None</li>' : optimizationsHtml}
  </ul>

  <h2>Findings</h2>
  ${findingsHtml.isEmpty ? '<p>No findings. Your build is well optimized!</p>' : findingsHtml}

  <hr>
  <p><small>Generated at ${report.timestamp.toIso8601String()} · Dart ${report.dartSdkVersion} · Flutter ${report.flutterVersion}</small></p>
</body>
</html>
''';
  }

  String _escapeHtml(String text) {
    return const HtmlEscape().convert(text);
  }
}
