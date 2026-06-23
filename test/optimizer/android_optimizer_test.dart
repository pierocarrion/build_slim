import 'dart:io';

import 'package:build_slim/src/optimizer/android_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  Future<File> writeGradle(String content,
      {String filename = 'build.gradle'}) async {
    final file = File(p.join(tempDir.path, 'android', 'app', filename));
    await file.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  Future<List<String>> runOptimizer() async {
    final optimizer = AndroidOptimizer(
      projectDir: tempDir.path,
      logger: Logger(level: LogLevel.none),
    );
    return optimizer.optimize();
  }

  group('AndroidOptimizer patches Groovy build.gradle', () {
    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('android_optimizer_groovy_');
      await writeGradle('''
plugins {
    id "com.android.application"
}

android {
    defaultConfig {
        applicationId "com.example.test"
    }

    buildTypes {
        release {
            minifyEnabled false
        }
    }
}
''');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('patches build.gradle and creates backup', () async {
      final applied = await runOptimizer();

      expect(applied, isNotEmpty);

      final gradle =
          File(p.join(tempDir.path, 'android', 'app', 'build.gradle'));
      final content = await gradle.readAsString();
      expect(content, contains('minifyEnabled = true'));
      expect(content, contains('shrinkResources = true'));
      expect(content, contains('abiFilters'));
      expect(content, contains('enableSplit = true'));

      final backup = File('${gradle.path}.bak');
      expect(backup.existsSync(), isTrue);

      final proguard =
          File(p.join(tempDir.path, 'android', 'app', 'proguard-rules.pro'));
      expect(proguard.existsSync(), isTrue);
      expect(await proguard.readAsString(), contains('io.flutter'));
    });

    test('records applied message mentioning all patched properties', () async {
      final applied = await runOptimizer();
      final message = applied.where((m) => m.contains('Patched')).first;
      expect(message, contains('minifyEnabled'));
      expect(message, contains('shrinkResources'));
      expect(message, contains('abiFilters'));
    });
  });

  group('AndroidOptimizer patches Kotlin build.gradle.kts', () {
    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('android_optimizer_kotlin_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('emits is-prefixed property names and listOf abiFilters', () async {
      await writeGradle('''
android {
    defaultConfig {
        applicationId = "com.example.test"
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
''', filename: 'build.gradle.kts');

      final applied = await runOptimizer();
      expect(applied, isNotEmpty);

      final content = await File(
        p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'),
      ).readAsString();
      expect(content, contains('isMinifyEnabled = true'));
      expect(content, contains('isShrinkResources = true'));
      expect(
        content,
        contains('abiFilters += listOf("arm64-v8a", "armeabi-v7a")'),
      );
      // Regression guards: never emit Groovy-style names or list literals.
      expect(content, isNot(contains('isminifyEnabled')));
      expect(content, isNot(contains("['arm64-v8a'")));
      expect(content, isNot(contains('abiFilters.addAll')));
    });

    test('scopes edits to release and leaves a preceding debug block alone',
        () async {
      await writeGradle('''
android {
    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
''', filename: 'build.gradle.kts');

      await runOptimizer();

      final content = await File(
        p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'),
      ).readAsString();

      // The release block must be enabled...
      final releaseStart = content.indexOf('release {');
      final debugStart = content.indexOf('debug {');
      expect(releaseStart, greaterThan(-1));
      expect(debugStart, greaterThan(-1));

      final releaseSlice = content.substring(releaseStart);
      expect(releaseSlice, contains('isMinifyEnabled = true'));
      expect(releaseSlice, contains('isShrinkResources = true'));

      // ...while the debug block (which appears first) stays disabled.
      final debugSlice =
          content.substring(debugStart, content.indexOf('release {'));
      expect(debugSlice, contains('isMinifyEnabled = false'));
      expect(debugSlice, contains('isShrinkResources = false'));
    });

    test('repairs previously corrupted isminifyEnabled casing', () async {
      await writeGradle('''
android {
    buildTypes {
        release {
            isminifyEnabled = true
            isshrinkResources = true
        }
    }
}
''', filename: 'build.gradle.kts');

      await runOptimizer();

      final content = await File(
        p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'),
      ).readAsString();
      expect(content, contains('isMinifyEnabled = true'));
      expect(content, contains('isShrinkResources = true'));
      expect(content, isNot(contains('isminifyEnabled')));
      expect(content, isNot(contains('isshrinkResources')));
    });

    test('is idempotent on Kotlin DSL', () async {
      await writeGradle('''
android {
    defaultConfig { }
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}
''', filename: 'build.gradle.kts');

      await runOptimizer();
      final afterFirst = await File(
        p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'),
      ).readAsString();
      final firstMinify =
          'isMinifyEnabled'.allMatches(afterFirst).length;

      await runOptimizer();
      final afterSecond = await File(
        p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'),
      ).readAsString();
      final secondMinify =
          'isMinifyEnabled'.allMatches(afterSecond).length;

      expect(secondMinify, firstMinify);
    });
  });

  group('AndroidOptimizer idempotency', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('android_idempotency_');
      await writeGradle('''
android {
    defaultConfig {
        applicationId "com.example.test"
    }
    buildTypes {
        release {
            minifyEnabled false
        }
    }
}
''');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('does not overwrite the original backup on subsequent runs', () async {
      final gradlePath = p.join(tempDir.path, 'android', 'app', 'build.gradle');
      final backupPath = '$gradlePath.bak';

      // First run: creates backup with the original content.
      await runOptimizer();
      final firstBackup = await File(backupPath).readAsString();
      expect(firstBackup, contains('minifyEnabled false'));
      expect(firstBackup, isNot(contains('minifyEnabled = true')));

      // Second run: backup file should not be modified.
      await runOptimizer();
      final secondBackup = await File(backupPath).readAsString();
      expect(secondBackup, firstBackup);
    });

    test('does not duplicate abiFilters on the second run', () async {
      await runOptimizer();
      final gradlePath = p.join(tempDir.path, 'android', 'app', 'build.gradle');
      final afterFirst = await File(gradlePath).readAsString();
      final firstOccurrences = 'abiFilters'.allMatches(afterFirst).length;

      await runOptimizer();
      final afterSecond = await File(gradlePath).readAsString();
      final secondOccurrences = 'abiFilters'.allMatches(afterSecond).length;

      expect(secondOccurrences, firstOccurrences);
    });

    test('does not duplicate enableSplit on the second run', () async {
      await runOptimizer();
      final gradlePath = p.join(tempDir.path, 'android', 'app', 'build.gradle');
      final afterFirst = await File(gradlePath).readAsString();
      final firstOccurrences = 'enableSplit'.allMatches(afterFirst).length;

      await runOptimizer();
      final afterSecond = await File(gradlePath).readAsString();
      final secondOccurrences = 'enableSplit'.allMatches(afterSecond).length;

      expect(secondOccurrences, firstOccurrences);
    });
  });

  group('AndroidOptimizer edge cases', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('android_edge_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('returns empty list when no gradle file exists', () async {
      final applied = await runOptimizer();
      expect(applied, isEmpty);
    });

    test('does not patch minify/shrink when release block is missing',
        () async {
      await writeGradle('android { defaultConfig { } }\n');
      final applied = await runOptimizer();
      // abiFilters / enableSplit may still be patched, but minifyEnabled and
      // shrinkResources require a release block.
      final gradlePath = p.join(tempDir.path, 'android', 'app', 'build.gradle');
      final content = await File(gradlePath).readAsString();
      expect(content, isNot(contains('minifyEnabled')));
      expect(content, isNot(contains('shrinkResources')));
      // Proguard may still be created.
      expect(applied.any((m) => m.contains('proguard-rules.pro')), isTrue);
    });

    test('does not create abiFilters when defaultConfig is missing', () async {
      await writeGradle('buildTypes { release { minifyEnabled false } }\n');
      await runOptimizer();
      final content =
          await File(p.join(tempDir.path, 'android', 'app', 'build.gradle'))
              .readAsString();
      expect(content, isNot(contains('abiFilters')));
    });

    test('does not create enableSplit when android block is missing', () async {
      await writeGradle('buildTypes { release { minifyEnabled false } }\n');
      await runOptimizer();
      final content =
          await File(p.join(tempDir.path, 'android', 'app', 'build.gradle'))
              .readAsString();
      expect(content, isNot(contains('enableSplit')));
    });

    test('preserves existing proguard-rules.pro', () async {
      final original = '# custom proguard\n-keep class com.x { *; }\n';
      await writeGradle('android { buildTypes { release { } } }\n');
      final proguard =
          File(p.join(tempDir.path, 'android', 'app', 'proguard-rules.pro'));
      await proguard.writeAsString(original);

      final applied = await runOptimizer();

      expect(await proguard.readAsString(), original);
      expect(applied.any((m) => m.contains('proguard-rules.pro')), isFalse);
    });

    test('inserts property when release block exists but key is absent',
        () async {
      await writeGradle('android { buildTypes { release { } }\n}\n');
      await runOptimizer();
      final content =
          await File(p.join(tempDir.path, 'android', 'app', 'build.gradle'))
              .readAsString();
      expect(content, contains('minifyEnabled = true'));
      expect(content, contains('shrinkResources = true'));
    });

    test('respects Kotlin DSL build.gradle.kts path', () async {
      await writeGradle('''
android {
    defaultConfig { }
    buildTypes {
        release {
            minifyEnabled false
        }
    }
}
''', filename: 'build.gradle.kts');

      final applied = await runOptimizer();

      final gradle =
          File(p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'));
      expect(gradle.existsSync(), isTrue);
      final content = await gradle.readAsString();
      expect(applied, isNotEmpty);
      // Kotlin DSL uses the is-prefixed property names and listOf syntax.
      expect(content, contains('isMinifyEnabled = true'));
      expect(content, contains('isShrinkResources = true'));
      expect(content, contains('abiFilters += listOf("arm64-v8a", "armeabi-v7a")'));
    });
  });
}
