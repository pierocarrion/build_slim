import 'dart:io';

import 'package:build_slim/src/optimizer/asset_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:build_slim/src/util/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers/mock_process_runner.dart';

void main() {
  late Directory tempDir;
  late MockProcessRunner processRunner;
  late Logger logger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('asset_optimizer_test');
    processRunner = MockProcessRunner();
    logger = Logger(level: LogLevel.none);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> createAsset(String relativePath) async {
    final file = File(p.join(tempDir.path, 'assets', relativePath));
    await file.create(recursive: true);
    await file.writeAsBytes(List.filled(16, 0));
    return file;
  }

  AssetOptimizer buildOptimizer() => AssetOptimizer(
        projectDir: tempDir.path,
        logger: logger,
        processRunner: processRunner,
      );

  group('AssetOptimizer.optimize directory checks', () {
    test('returns empty list when assets directory does not exist', () async {
      final applied = await buildOptimizer().optimize();
      expect(applied, isEmpty);
    });
  });

  group('AssetOptimizer.optimize tool detection', () {
    test('returns empty list when no tools are available', () async {
      await createAsset('a.png');
      processRunner.responseFor = (executable, _) {
        // `where`/`which` always fails.
        if (executable == 'where' || executable == 'which') {
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return null;
      };

      final applied = await buildOptimizer().optimize();
      expect(applied, isEmpty);
    });

    test('skips files with unsupported extensions', () async {
      await createAsset('song.gif');
      await createAsset('logo.svg');
      await createAsset('clip.mp4');
      // Pretend pngquant exists so we get past the tool-presence gate.
      processRunner.responseFor = (executable, _) {
        if (executable == 'where' || executable == 'which') {
          return const ProcessResult(
              exitCode: 0, stdout: '/usr/bin/pngquant', stderr: '');
        }
        return null;
      };

      final applied = await buildOptimizer().optimize();
      expect(applied, isEmpty);
    });
  });

  group('AssetOptimizer.optimize PNG', () {
    test('uses pngquant when available', () async {
      final png = await createAsset('a.png');
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'pngquant') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/pngquant', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();

      expect(applied, hasLength(1));
      expect(applied.first, contains('pngquant'));
      expect(applied.first, contains(png.path));

      final pngquantCalls = processRunner.invocations
          .where((i) => i.executable.contains('pngquant'));
      expect(pngquantCalls, hasLength(1));
      final args = pngquantCalls.single.arguments;
      expect(args, ['--force', '--output', png.path, png.path]);
    });

    test('falls back to optipng when pngquant is missing', () async {
      final png = await createAsset('b.png');
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'optipng') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/optipng', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();

      expect(applied, hasLength(1));
      expect(applied.first, contains('optipng'));

      final optipngCalls = processRunner.invocations
          .where((i) => i.executable.contains('optipng'));
      expect(optipngCalls, hasLength(1));
      expect(optipngCalls.single.arguments, ['-o2', png.path]);
    });

    test('skips PNG when both pngquant and optipng are missing', () async {
      await createAsset('c.png');
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'cwebp') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/cwebp', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();
      expect(applied, isEmpty);
    });
  });

  group('AssetOptimizer.optimize JPEG', () {
    test('converts JPEG to WebP with cwebp', () async {
      final jpg = await createAsset('photo.jpg');
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'cwebp') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/cwebp', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();

      expect(applied, hasLength(1));
      expect(applied.first, contains('WebP'));

      final cwebpCalls = processRunner.invocations
          .where((i) => i.executable.contains('cwebp'));
      expect(cwebpCalls, hasLength(1));
      expect(cwebpCalls.single.arguments, [jpg.path, '-o', '${jpg.path}.webp']);
    });

    test('handles .jpeg extension too', () async {
      await createAsset('photo.jpeg');
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'cwebp') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/cwebp', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();
      expect(applied, hasLength(1));
    });

    test('skips JPEG when cwebp is missing', () async {
      await createAsset('photo.jpg');
      // Only pngquant available.
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'pngquant') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/pngquant', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();
      expect(applied, isEmpty);
    });
  });

  group('AssetOptimizer.optimize WebP', () {
    test('recompresses existing WebP in place', () async {
      final webp = await createAsset('anim.webp');
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'cwebp') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/cwebp', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();

      expect(applied, hasLength(1));
      expect(applied.first, contains('Recompressed'));

      final cwebpCalls = processRunner.invocations
          .where((i) => i.executable.contains('cwebp'));
      expect(cwebpCalls.single.arguments, [webp.path, '-o', webp.path]);
    });
  });

  group('AssetOptimizer.optimize resilience', () {
    test('swallows ProcessRunnerException from compression tool', () async {
      await createAsset('a.png');
      processRunner.responseFor = (executable, args) {
        if (executable == 'where' || executable == 'which') {
          if (args.last == 'pngquant') {
            return const ProcessResult(
                exitCode: 0, stdout: '/usr/bin/pngquant', stderr: '');
          }
          return const ProcessResult(exitCode: 1, stdout: '', stderr: '');
        }
        if (executable.contains('pngquant')) {
          throw const ProcessRunnerException('crashed', executable: 'pngquant');
        }
        return null;
      };

      final applied = await buildOptimizer().optimize();
      // Note: the optimizer adds the success message even when the underlying
      // compressor throws (the exception is swallowed inside _compressWith).
      // This pins the current behavior so any future change is intentional.
      expect(applied, hasLength(1));
      expect(applied.first, contains('pngquant'));
    });

    test('processes mixed assets recursively', () async {
      await createAsset('top.png');
      await createAsset('nested/inner.jpg');
      processRunner.responseFor = (executable, _) {
        if (executable == 'where' || executable == 'which') {
          return const ProcessResult(
              exitCode: 0, stdout: '/usr/bin/all-tools', stderr: '');
        }
        return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
      };

      final applied = await buildOptimizer().optimize();

      // PNG uses pngquant; JPEG uses cwebp. 2 ops.
      expect(applied, hasLength(2));
      expect(applied.any((m) => m.contains('pngquant')), isTrue);
      expect(applied.any((m) => m.contains('WebP')), isTrue);
    });
  });
}
