import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/logger.dart';
import '../util/process_runner.dart';

/// Compresses project assets when external tools are available.
class AssetOptimizer {
  /// Creates an asset optimizer.
  AssetOptimizer({
    required this.projectDir,
    required this.logger,
    required this.processRunner,
  });

  /// Root directory of the Flutter project.
  final String projectDir;

  /// Logger for diagnostic output.
  final Logger logger;

  /// Process runner used to invoke compression tools.
  final ProcessRunner processRunner;

  /// Compresses supported assets and returns applied changes.
  Future<List<String>> optimize() async {
    final applied = <String>[];
    final assetsDir = Directory(p.join(projectDir, 'assets'));

    if (!assetsDir.existsSync()) {
      logger.verbose('No assets directory found; skipping asset compression.');
      return applied;
    }

    final pngquant = await _which('pngquant');
    final optipng = await _which('optipng');
    final cwebp = await _which('cwebp');

    if (pngquant == null && optipng == null && cwebp == null) {
      logger.info(
        'Asset compression tools not found. Install pngquant, optipng, or '
        'cwebp to compress PNG/JPEG/WebP assets.',
      );
      return applied;
    }

    await for (final entity in assetsDir.list(recursive: true)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();

      if (ext == '.png') {
        if (pngquant != null) {
          await _compressWith(
            pngquant,
            ['--force', '--output', entity.path, entity.path],
          );
          applied.add('Compressed ${entity.path} with pngquant');
        } else if (optipng != null) {
          await _compressWith(optipng, ['-o2', entity.path]);
          applied.add('Compressed ${entity.path} with optipng');
        }
      } else if (ext == '.jpg' || ext == '.jpeg') {
        if (cwebp != null) {
          final outPath = '${entity.path}.webp';
          await _compressWith(cwebp, [entity.path, '-o', outPath]);
          applied.add('Converted ${entity.path} to WebP with cwebp');
        }
      } else if (ext == '.webp' && cwebp != null) {
        await _compressWith(cwebp, [entity.path, '-o', entity.path]);
        applied.add('Recompressed ${entity.path} with cwebp');
      }
    }

    return applied;
  }

  Future<void> _compressWith(String executable, List<String> arguments) async {
    try {
      await processRunner.run(executable, arguments);
    } on ProcessRunnerException catch (e) {
      logger.verbose('Compression command failed: $e');
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
}
