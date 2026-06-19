import 'dart:io';

import 'package:build_slim/src/optimizer/android_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('android_optimizer_test_');
    final appDir = Directory(p.join(tempDir.path, 'android', 'app'))
      ..createSync(recursive: true);
    await File(p.join(appDir.path, 'build.gradle')).writeAsString('''
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
    final optimizer = AndroidOptimizer(
      projectDir: tempDir.path,
      logger: const Logger(level: LogLevel.none),
    );
    final applied = await optimizer.optimize();

    expect(applied, isNotEmpty);

    final gradle = File(p.join(tempDir.path, 'android', 'app', 'build.gradle'));
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
}
