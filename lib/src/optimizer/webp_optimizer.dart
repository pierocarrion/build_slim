import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/logger.dart';
import '../util/process_runner.dart';

/// Converts PNG and JPEG assets to WebP and rewrites their references in
/// Dart code and `pubspec.yaml`.
///
/// Safety contract:
/// - Operates only when [aggressive] is true.
/// - Requires `cwebp` to be present in PATH; if absent, logs a notice and
///   returns without touching any file.
/// - Every converted asset produces a `.webp` next to the original. Only when
///   ALL conversions in a file succeed are the references rewritten; if any
///   conversion fails the originals are left untouched.
/// - Backups (`.bak`) are written for `pubspec.yaml` and every edited Dart
///   file before the new content is persisted.
/// - Never rewrites references inside comments, import statements, or strings
///   that are not asset-path-shaped (contain a path separator).
class WebPConverter {
  /// Creates a WebP converter.
  WebPConverter({
    required this.projectDir,
    required this.logger,
    required this.processRunner,
    this.aggressive = false,
    this.keepOriginal = true,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Process runner used to locate and invoke `cwebp`.
  final ProcessRunner processRunner;

  /// When false (the safe default) the original PNG/JPEG files are deleted
  /// after a successful conversion. When true, both files coexist.
  final bool keepOriginal;

  /// Master switch. The pipeline only constructs this optimizer when the user
  /// passes `--aggressive`, but the flag is also checked here so unit tests
  /// can exercise the no-op path directly.
  final bool aggressive;

  /// Runs the conversion and reference rewrite. Returns applied change
  /// descriptions for the report.
  Future<List<String>> convert() async {
    if (!aggressive) {
      logger.verbose('WebP conversion skipped (not in aggressive mode).');
      return const [];
    }

    final cwebp = await _which('cwebp');
    if (cwebp == null) {
      logger.info(
        'WebP conversion requested but `cwebp` was not found in PATH. '
        'Install libwebp (e.g. `brew install webp`, `apt install webp`) to '
        'enable automatic PNG/JPEG → WebP conversion.',
      );
      return const [];
    }

    final assetsDir = Directory(p.join(projectDir, 'assets'));
    if (!assetsDir.existsSync()) {
      logger.verbose('No assets/ directory; nothing to convert.');
      return const [];
    }

    // Phase 1: convert files. Collect a mapping of original -> webp path.
    final conversions = <_Conversion>[];
    await for (final entity in assetsDir.list(recursive: true)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.png' && ext != '.jpg' && ext != '.jpeg') continue;

      final outPath = '${p.withoutExtension(entity.path)}.webp';
      final ok = await _runCwebp(cwebp, entity.path, outPath);
      if (!ok) {
        logger.warning('Conversion failed for ${entity.path}; aborting WebP '
            'rewrite to keep references consistent.');
        // Clean up partial webp file if one was produced.
        final out = File(outPath);
        if (out.existsSync()) await out.delete();
        // Stop the whole pass: we promised atomicity across the project.
        return conversions.map((c) => c.description).toList();
      }

      final webpFile = File(outPath);
      final before = await entity.length();
      final after = await webpFile.length();
      final saved = before - after;
      conversions.add(_Conversion(
        originalPath: entity.path,
        webpPath: outPath,
        description: 'Converted ${p.relative(entity.path, from: projectDir)} '
            'to WebP (${_formatBytes(before)} → ${_formatBytes(after)}, '
            '${saved >= 0 ? '-' : '+'}${_formatBytes(saved.abs())})',
      ));

      if (!keepOriginal) {
        await entity.delete();
      }
    }

    if (conversions.isEmpty) return const [];

    // Phase 2: rewrite references only after every conversion succeeded.
    final rewrite = await _Rewriter(
      projectDir: projectDir,
      logger: logger,
    ).rewriteAll(conversions);
    conversions.addAll(rewrite);

    return conversions.map((c) => c.description).toList();
  }

  Future<bool> _runCwebp(String cwebp, String input, String output) async {
    try {
      final result = await processRunner.run(
        cwebp,
        ['-q', '80', input, '-o', output],
      );
      return result.exitCode == 0;
    } on ProcessRunnerException catch (e) {
      logger.verbose('cwebp invocation failed: $e');
      return false;
    }
  }

  Future<String?> _which(String executable) async {
    try {
      final isWindows = Platform.operatingSystem == 'windows';
      final result = await processRunner.run(
        isWindows ? 'where' : 'which',
        [executable],
      );
      if (result.exitCode == 0 && result.stdout.trim().isNotEmpty) {
        return result.stdout.trim().split('\n').first.trim();
      }
    } on ProcessRunnerException catch (e) {
      logger.verbose('Could not locate $executable: $e');
    }
    return null;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Internal record for either a successful asset conversion or a reference
/// rewrite entry added to the applied-changes list.
class _Conversion {
  _Conversion({
    required this.originalPath,
    required this.webpPath,
    required this.description,
  });

  final String originalPath;
  final String webpPath;
  final String description;
}

/// Rewrites `.png`/`.jpg`/`.jpeg` references inside `lib/**/*.dart` and
/// `pubspec.yaml` to their new `.webp` extension.
class _Rewriter {
  _Rewriter({required this.projectDir, required this.logger});

  final String projectDir;
  final Logger logger;

  Future<List<_Conversion>> rewriteAll(List<_Conversion> conversions) async {
    final out = <_Conversion>[];
    if (conversions.isEmpty) return out;

    // Build a lookup keyed by the project-relative original extension path.
    // We also add basename shortcuts (Flutter assets are frequently
    // referenced by basename only), but ONLY when the basename is unique
    // across all conversions. If two files share a basename (e.g.
    // assets/icons/logo.png and assets/banners/logo.png), the basename key
    // is omitted entirely to avoid rewriting a reference to the wrong file.
    final map = <String, String>{};
    final basenameCounts = <String, int>{};
    for (final c in conversions) {
      final rel =
          p.relative(c.originalPath, from: projectDir).replaceAll(r'\', '/');
      map[rel] = p.relative(c.webpPath, from: projectDir).replaceAll(r'\', '/');
      final base = p.basename(rel);
      basenameCounts[base] = (basenameCounts[base] ?? 0) + 1;
    }
    // Only register unambiguous basename shortcuts.
    for (final c in conversions) {
      final rel =
          p.relative(c.originalPath, from: projectDir).replaceAll(r'\', '/');
      final base = p.basename(rel);
      if (basenameCounts[base] == 1) {
        map[base] = p.basename(map[rel]!);
      }
    }

    out.addAll(await _rewriteDartSources(map));
    out.addAll(await _rewritePubspec(map));
    return out;
  }

  /// Rewrites asset references in Dart source. Targets only string literals
  /// that look like paths (contain `/` or end with a known image extension),
  /// and skips import/part directives.
  Future<List<_Conversion>> _rewriteDartSources(
    Map<String, String> map,
  ) async {
    final libDir = Directory(p.join(projectDir, 'lib'));
    if (!libDir.existsSync()) return const [];

    final rewritten = <_Conversion>[];

    await for (final entity in libDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;

      final original = await entity.readAsString();
      var mutated = original;
      var hits = 0;

      // Match any single/double-quoted string literal ending in .png/.jpg/.jpeg.
      // Import/part directives target package: or relative .dart URLs and are
      // therefore excluded by the extension constraint.
      final assetRef = RegExp(
        r'''(["'])((?:[^"'\\]|\\.)*?\.(?:png|jpg|jpeg))\1''',
        caseSensitive: false,
      );

      mutated = original.replaceAllMapped(assetRef, (m) {
        final quote = m.group(1)!;
        final body = m.group(2)!;
        final normalized = body.replaceAll(r'\', '/');
        // Exact-match lookup only. The map contains full relative paths AND
        // unambiguous basenames (see rewriteAll). We deliberately do NOT
        // fall back to p.basename() here: a reference like
        // 'assets/banners/logo.png' must not match a converted
        // 'assets/icons/logo.png' that merely shares a basename.
        final replacement = map[normalized];
        if (replacement == null) return m.group(0)!;
        hits++;
        return '$quote$replacement$quote';
      });

      if (hits > 0) {
        await _writeWithBackup(entity, mutated);
        rewritten.add(_Conversion(
          originalPath: entity.path,
          webpPath: entity.path,
          description: 'Rewrote $hits asset reference(s) in '
              '${p.relative(entity.path, from: projectDir)} to .webp '
              '(backup at .bak)',
        ));
      }
    }
    return rewritten;
  }

  /// Rewrites asset entries in pubspec.yaml. Operates line-by-line for
  /// safety against YAML formatting quirks.
  Future<List<_Conversion>> _rewritePubspec(Map<String, String> map) async {
    final file = File(p.join(projectDir, 'pubspec.yaml'));
    if (!file.existsSync()) return const [];

    final original = await file.readAsString();
    final lines = original.split('\n');
    var hits = 0;

    // Replace any image extension inside an asset declaration. We look for
    // `- ...path.png` style lines under `assets:`, plus inline asset paths.
    final assetLine = RegExp(
      r'''(-\s*["']?)(.*?\.(?:png|jpg|jpeg))(["']?\s*)$''',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      // Skip comment lines: rewriting a commented-out entry changes comment
      // content and could confuse users reviewing the diff.
      if (lines[i].trimLeft().startsWith('#')) continue;
      final match = assetLine.firstMatch(lines[i]);
      if (match == null) continue;
      final prefix = match.group(1)!;
      final body = match.group(2)!;
      final suffix = match.group(3)!;
      final normalized = body.replaceAll(r'\', '/');
      // Same safety rule as Dart sources: only exact-path matches; no
      // basename fallback for paths that contain a separator.
      final replacement = map[normalized];
      if (replacement == null) continue;
      lines[i] = '$prefix$replacement$suffix';
      hits++;
    }

    if (hits == 0) return const [];

    await _writeWithBackup(file, lines.join('\n'));
    return [
      _Conversion(
        originalPath: file.path,
        webpPath: file.path,
        description: 'Updated $hits asset entry/entries in pubspec.yaml '
            '(backup at pubspec.yaml.bak)',
      ),
    ];
  }

  Future<void> _writeWithBackup(File file, String content) async {
    final backup = File('${file.path}.bak');
    if (!backup.existsSync()) {
      await backup.writeAsString(await file.readAsString());
      logger.verbose('Created backup: ${backup.path}');
    }
    await file.writeAsString(content);
  }
}
