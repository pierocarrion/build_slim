import 'dart:io';

import 'package:build_slim/src/optimizer/webp_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:build_slim/src/util/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers/mock_process_runner.dart';

void main() {
  late Directory tempDir;
  late MockProcessRunner runner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('webp_optimizer');
    runner = MockProcessRunner();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Writes [bytes] to [relPath] under the temp project, creating parents.
  Future<File> writeFile(String relPath, List<int> bytes) async {
    final file = File(p.join(tempDir.path, relPath));
    await file.create(recursive: true);
    file.writeAsBytesSync(bytes);
    return file;
  }

  /// Configures the mock so `which cwebp` resolves and `cwebp` invocations
  /// succeed. The "converted" output file is created so length() works.
  void mockCwebpAvailable() {
    runner.responseFor = (executable, args) {
      if (executable == 'which' || executable == 'where') {
        return const ProcessResult(
            exitCode: 0, stdout: '/usr/bin/cwebp\n', stderr: '');
      }
      // convert() invokes the resolved path returned by `which`.
      if (executable.endsWith('cwebp')) {
        final outIdx = args.indexOf('-o');
        if (outIdx >= 0 && outIdx + 1 < args.length) {
          final out = File(args[outIdx + 1]);
          out.createSync(recursive: true);
          out.writeAsBytesSync(List<int>.filled(1024, 0));
        }
        return const ProcessResult(exitCode: 0, stdout: 'ok', stderr: '');
      }
      return null;
    };
  }

  WebPConverter newConverter({bool aggressive = true}) => WebPConverter(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
        processRunner: runner,
        aggressive: aggressive,
      );

  group('WebPConverter.convert safety', () {
    test('is a no-op when aggressive is false', () async {
      await writeFile('assets/logo.png', List<int>.filled(1024, 0));
      mockCwebpAvailable();

      final applied = await newConverter(aggressive: false).convert();

      expect(applied, isEmpty);
      expect(runner.callsFor('cwebp'), isEmpty);
    });

    test('is a no-op when cwebp is not available', () async {
      await writeFile('assets/logo.png', List<int>.filled(1024, 0));

      final applied = await newConverter().convert();

      expect(applied, isEmpty);
    });

    test('is a no-op when assets/ directory is missing', () async {
      mockCwebpAvailable();

      final applied = await newConverter().convert();

      expect(applied, isEmpty);
    });

    test('aborts and leaves references untouched when conversion fails',
        () async {
      await writeFile('assets/logo.png', List<int>.filled(5000, 0));
      await writeFile(
        'lib/main.dart',
        "final path = 'assets/logo.png';\n".codeUnits,
      );

      // cwebp resolves but fails for the conversion.
      runner.responseFor = (executable, args) {
        if (executable == 'which' || executable == 'where') {
          return const ProcessResult(
              exitCode: 0, stdout: '/usr/bin/cwebp\n', stderr: '');
        }
        if (executable.endsWith('cwebp')) {
          return const ProcessResult(exitCode: 1, stdout: '', stderr: 'boom');
        }
        return null;
      };

      final applied = await newConverter().convert();

      // No rewrite should have happened.
      final dart =
          await File(p.join(tempDir.path, 'lib', 'main.dart')).readAsString();
      expect(dart, contains('logo.png'));
      expect(dart, isNot(contains('logo.webp')));
      // No webp file should remain on disk.
      expect(
        File(p.join(tempDir.path, 'assets', 'logo.webp')).existsSync(),
        isFalse,
      );
      // The original PNG is untouched.
      expect(
        File(p.join(tempDir.path, 'assets', 'logo.png')).existsSync(),
        isTrue,
      );
      expect(applied, isEmpty);
    });
  });

  group('WebPConverter.convert happy path', () {
    test('converts PNG and rewrites references in lib/ and pubspec.yaml',
        () async {
      await writeFile('assets/logo.png', List<int>.filled(8000, 7));
      await writeFile(
        'lib/main.dart',
        "final logo = 'assets/logo.png';\n".codeUnits,
      );
      await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString(
        'name: demo\n'
        'flutter:\n'
        '  assets:\n'
        '    - assets/logo.png\n',
      );
      mockCwebpAvailable();

      final applied = await newConverter().convert();

      // References rewritten.
      final dart =
          await File(p.join(tempDir.path, 'lib', 'main.dart')).readAsString();
      expect(dart, contains("'assets/logo.webp'"));
      expect(dart, isNot(contains('logo.png')));
      // Backups created.
      expect(
        File(p.join(tempDir.path, 'lib', 'main.dart.bak')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(tempDir.path, 'pubspec.yaml.bak')).existsSync(),
        isTrue,
      );
      // pubspec entry updated.
      final pubspec =
          await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString();
      expect(pubspec, contains('assets/logo.webp'));
      expect(pubspec, isNot(contains('logo.png')));
      // Original PNG preserved by default (keepOriginal = true).
      expect(
        File(p.join(tempDir.path, 'assets', 'logo.png')).existsSync(),
        isTrue,
      );
      // WebP produced.
      expect(
        File(p.join(tempDir.path, 'assets', 'logo.webp')).existsSync(),
        isTrue,
      );
      // Report mentions both conversion and rewrite.
      expect(applied.any((s) => s.contains('Converted')), isTrue);
      expect(applied.any((s) => s.contains('Rewrote')), isTrue);
      expect(applied.any((s) => s.contains('pubspec.yaml')), isTrue);
    });

    test('does not rewrite unrelated string literals', () async {
      await writeFile('assets/hero.png', List<int>.filled(2000, 0));
      await writeFile(
        'lib/main.dart',
        "final unrelated = 'package:foo/bar.png';\n".codeUnits,
      );
      mockCwebpAvailable();

      await newConverter().convert();

      final dart =
          await File(p.join(tempDir.path, 'lib', 'main.dart')).readAsString();
      // Not in conversion map, so untouched.
      expect(dart, contains('package:foo/bar.png'));
      expect(dart, isNot(contains('bar.webp')));
    });
  });

  group('WebPConverter basename safety', () {
    test('does not rewrite basename of a different file with same name',
        () async {
      // Convert ONLY assets/icons/logo.png. A reference to
      // assets/banners/logo.png (NOT converted) must stay .png.
      await writeFile('assets/icons/logo.png', List<int>.filled(2000, 0));
      await writeFile(
        'lib/main.dart',
        "final a = 'assets/icons/logo.png';\n"
                "final b = 'assets/banners/logo.png';\n"
            .codeUnits,
      );
      mockCwebpAvailable();

      await newConverter().convert();

      final dart =
          await File(p.join(tempDir.path, 'lib', 'main.dart')).readAsString();
      // The converted file's reference IS updated.
      expect(dart, contains("'assets/icons/logo.webp'"));
      // The non-converted file with the same basename MUST NOT be touched.
      expect(dart, contains("'assets/banners/logo.png'"));
      expect(dart, isNot(contains('assets/banners/logo.webp')));
    });

    test('omits basename shortcut when two files share a basename', () async {
      // Both converted. Since they share a basename, the basename shortcut
      // is disabled to avoid ambiguity. Only full-path references should be
      // rewritten.
      await writeFile('assets/icons/logo.png', List<int>.filled(2000, 0));
      await writeFile('assets/banners/logo.png', List<int>.filled(2000, 0));
      await writeFile(
        'lib/main.dart',
        // Full paths should be rewritten; basename-only should NOT.
        "final a = 'assets/icons/logo.png';\n"
                "final b = 'assets/banners/logo.png';\n"
                "final c = 'logo.png';\n"
            .codeUnits,
      );
      mockCwebpAvailable();

      await newConverter().convert();

      final dart =
          await File(p.join(tempDir.path, 'lib', 'main.dart')).readAsString();
      expect(dart, contains("'assets/icons/logo.webp'"));
      expect(dart, contains("'assets/banners/logo.webp'"));
      // The ambiguous basename-only reference must be left alone.
      expect(dart, contains("'logo.png'"));
      expect(dart, isNot(contains("'logo.webp'")));
    });

    test('uses basename shortcut for unambiguous single-file case', () async {
      await writeFile('assets/logo.png', List<int>.filled(2000, 0));
      await writeFile(
        'lib/main.dart',
        // Basename-only reference is common in Flutter Image.asset calls.
        "Image.asset('logo.png');\n".codeUnits,
      );
      mockCwebpAvailable();

      await newConverter().convert();

      final dart =
          await File(p.join(tempDir.path, 'lib', 'main.dart')).readAsString();
      expect(dart, contains("'logo.webp'"));
    });

    test('does not rewrite commented-out asset entries in pubspec.yaml',
        () async {
      await writeFile('assets/logo.png', List<int>.filled(2000, 0));
      await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString(
        'name: demo\n'
        'flutter:\n'
        '  assets:\n'
        '    - assets/logo.png\n'
        '    # - assets/old.png\n',
      );
      mockCwebpAvailable();

      await newConverter().convert();

      final pubspec =
          await File(p.join(tempDir.path, 'pubspec.yaml')).readAsString();
      // Active entry updated.
      expect(pubspec, contains('- assets/logo.webp'));
      // Commented entry preserved verbatim.
      expect(pubspec, contains('# - assets/old.png'));
      expect(pubspec, isNot(contains('# - assets/old.webp')));
    });

    test('does not rewrite http(s) URLs ending in image extensions', () async {
      await writeFile('assets/logo.png', List<int>.filled(2000, 0));
      await writeFile(
        'lib/main.dart',
        "final url = 'https://example.com/banner.png';\n".codeUnits,
      );
      mockCwebpAvailable();

      await newConverter().convert();

      final dart =
          await File(p.join(tempDir.path, 'lib', 'main.dart')).readAsString();
      expect(dart, contains('https://example.com/banner.png'));
      expect(dart, isNot(contains('banner.webp')));
    });
  });
}
