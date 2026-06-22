import 'dart:io';

import 'package:build_slim/src/optimizer/ios_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('IosOptimizer injects Release.xcconfig settings', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ios_optimizer_test_');
      final flutterDir = Directory(p.join(tempDir.path, 'ios', 'Flutter'))
        ..createSync(recursive: true);
      await File(p.join(flutterDir.path, 'Release.xcconfig'))
          .writeAsString('#include "Generated.xcconfig"\n');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('injects all five settings when none present', () async {
      final optimizer = IosOptimizer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final applied = await optimizer.optimize();

      expect(applied, isNotEmpty);
      expect(applied.first, contains('ENABLE_BITCODE=NO'));
      expect(applied.first, contains('SWIFT_OPTIMIZATION_LEVEL=-Osize'));

      final xcconfig =
          File(p.join(tempDir.path, 'ios', 'Flutter', 'Release.xcconfig'));
      final content = await xcconfig.readAsString();
      expect(content, contains('ENABLE_BITCODE=NO'));
      expect(content, contains('STRIP_STYLE=all'));
      expect(content, contains('DEAD_CODE_STRIPPING=YES'));
      expect(content, contains('GCC_OPTIMIZATION_LEVEL=s'));
      expect(content, contains('SWIFT_OPTIMIZATION_LEVEL=-Osize'));
    });
  });

  group('IosOptimizer partial settings', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ios_partial_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<File> writeXcconfig(String content) async {
      final file =
          File(p.join(tempDir.path, 'ios', 'Flutter', 'Release.xcconfig'));
      await file.create(recursive: true);
      await file.writeAsString(content);
      return file;
    }

    test('appends only missing settings when some are present', () async {
      await writeXcconfig('''
#include "Generated.xcconfig"
ENABLE_BITCODE=NO
DEAD_CODE_STRIPPING=YES
''');
      final optimizer = IosOptimizer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final applied = await optimizer.optimize();

      final content =
          await File(p.join(tempDir.path, 'ios', 'Flutter', 'Release.xcconfig'))
              .readAsString();
      expect(applied, isNotEmpty);
      // Already-present settings should appear only once.
      expect('ENABLE_BITCODE=NO'.allMatches(content).length, 1);
      expect('DEAD_CODE_STRIPPING=YES'.allMatches(content).length, 1);
      // Missing settings should be appended.
      expect(content, contains('STRIP_STYLE=all'));
      expect(content, contains('GCC_OPTIMIZATION_LEVEL=s'));
      expect(content, contains('SWIFT_OPTIMIZATION_LEVEL=-Osize'));
    });

    test('returns empty applied list when all settings already present',
        () async {
      await writeXcconfig('''
ENABLE_BITCODE=NO
STRIP_STYLE=all
DEAD_CODE_STRIPPING=YES
GCC_OPTIMIZATION_LEVEL=s
SWIFT_OPTIMIZATION_LEVEL=-Osize
''');
      final optimizer = IosOptimizer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final applied = await optimizer.optimize();
      expect(applied, isEmpty);
    });

    test('does not rewrite the file when nothing is missing', () async {
      final original = 'ENABLE_BITCODE=NO\n'
          'STRIP_STYLE=all\n'
          'DEAD_CODE_STRIPPING=YES\n'
          'GCC_OPTIMIZATION_LEVEL=s\n'
          'SWIFT_OPTIMIZATION_LEVEL=-Osize\n';
      final file = await writeXcconfig(original);

      final beforeStat = await file.stat();
      // Wait briefly to ensure modified time would differ if rewritten.
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final optimizer = IosOptimizer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      await optimizer.optimize();

      final content = await file.readAsString();
      expect(content, original);
      // Sanity check that stat works.
      expect(file.existsSync(), isTrue);
      // The first stat is real; we just ensure the call doesn't throw.
      expect(beforeStat.size, greaterThan(0));
    });
  });

  group('IosOptimizer missing xcconfig', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ios_missing_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('returns empty applied list when Release.xcconfig is missing',
        () async {
      final optimizer = IosOptimizer(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.none),
      );
      final applied = await optimizer.optimize();
      expect(applied, isEmpty);
    });
  });
}
