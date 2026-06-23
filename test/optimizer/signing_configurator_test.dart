import 'dart:io';

import 'package:build_slim/src/builder/artifact_comparator.dart';
import 'package:build_slim/src/optimizer/signing_configurator.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  Future<File> writeGradle(String content,
      {String filename = 'build.gradle.kts'}) async {
    final file = File(p.join(tempDir.path, 'android', 'app', filename));
    await file.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  Future<File> writeKeyProperties(String content) async {
    final file = File(p.join(tempDir.path, 'android', 'key.properties'));
    await file.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  Future<File> writeKeystore() async {
    final file = File(p.join(tempDir.path, 'keystores', 'upload.jks'));
    await file.create(recursive: true);
    await file.writeAsBytes([0, 1, 2, 3]);
    return file;
  }

  SigningConfigurator newConfigurator(StringSink sink) => SigningConfigurator(
        projectDir: tempDir.path,
        logger: Logger(level: LogLevel.verbose, sink: sink),
      );

  group('SigningConfigurator.detect / skip', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('signing_skip_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('skips when no Android build.gradle exists', () async {
      final result = await newConfigurator(StringBuffer()).configure();
      expect(result.action, SigningAction.skipped);
    });

    test('skips when project does not use key.properties pattern', () async {
      await writeGradle('''
android {
    buildTypes {
        release { signingConfig = signingConfigs.getByName("debug") }
    }
}
''');
      final result = await newConfigurator(StringBuffer()).configure();
      expect(result.action, SigningAction.skipped);
    });

    test('skips when key.properties already exists', () async {
      await writeGradle('''
val keystoreProperties = java.util.Properties()
android { buildTypes { release { } } }
''');
      await writeKeyProperties('storePassword=x\n');
      final result = await newConfigurator(StringBuffer()).configure();
      expect(result.action, SigningAction.skipped);
    });
  });

  group('SigningConfigurator.generate', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('signing_generate_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('writes key.properties when all credentials are provided', () async {
      await writeGradle('''
android { buildTypes { release { } } }
// reads key.properties
''');
      final keystore = await writeKeystore();

      final result = await newConfigurator(StringBuffer()).configure(
        keystore: keystore.path,
        storePassword: 'store-pw',
        keyAlias: 'alias',
        keyPassword: 'key-pw',
      );

      expect(result.action, SigningAction.generated);
      final written =
          await File(p.join(tempDir.path, 'android', 'key.properties'))
              .readAsString();
      expect(written, contains('storePassword=store-pw'));
      expect(written, contains('keyPassword=key-pw'));
      expect(written, contains('keyAlias=alias'));
      expect(written, contains('storeFile='));
    });

    test('throws when keystore is given but other credentials are missing',
        () async {
      await writeGradle('''
android { buildTypes { release { } } }
// loads key.properties
''');
      final keystore = await writeKeystore();

      expect(
        () => newConfigurator(StringBuffer()).configure(
          keystore: keystore.path,
          storePassword: 'store-pw',
        ),
        throwsA(isA<BuildOptimizerException>()),
      );
    });

    test('throws when the keystore path does not exist', () async {
      await writeGradle('''
android { buildTypes { release { } } }
// loads key.properties
''');

      expect(
        () => newConfigurator(StringBuffer()).configure(
          keystore: p.join(tempDir.path, 'missing.jks'),
          storePassword: 's',
          keyAlias: 'a',
          keyPassword: 'k',
        ),
        throwsA(isA<BuildOptimizerException>()),
      );
    });

    test('warns when key.properties is not in .gitignore', () async {
      await writeGradle('''
android { buildTypes { release { } } }
// loads key.properties
''');
      final keystore = await writeKeystore();
      final sink = StringBuffer();

      await newConfigurator(sink).configure(
        keystore: keystore.path,
        storePassword: 's',
        keyAlias: 'a',
        keyPassword: 'k',
      );

      expect(sink.toString().toLowerCase(), contains('gitignore'));
    });
  });

  group('SigningConfigurator.debugFallback', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('signing_debug_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('switches Kotlin release signingConfig to debug', () async {
      final gradle = await writeGradle('''
android {
    signingConfigs { create("release") { } }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
        }
    }
}
// loads key.properties
''');

      final result =
          await newConfigurator(StringBuffer()).configure(debugSigning: true);
      expect(result.action, SigningAction.debugFallback);

      final content = await gradle.readAsString();
      expect(content,
          contains('signingConfig = signingConfigs.getByName("debug")'));
      expect(content, isNot(contains('getByName("release")')));
      // Untouched sibling property preserved.
      expect(content, contains('isMinifyEnabled = true'));
    });

    test('switches Groovy release signingConfig to debug', () async {
      final gradle = await writeGradle('''
android {
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
// loads key.properties
''', filename: 'build.gradle');

      final result =
          await newConfigurator(StringBuffer()).configure(debugSigning: true);
      expect(result.action, SigningAction.debugFallback);

      final content = await gradle.readAsString();
      expect(content, contains('signingConfig signingConfigs.debug'));
      expect(content, isNot(contains('signingConfigs.release')));
    });

    test('skips when no release signingConfig line is found', () async {
      await writeGradle('''
android { buildTypes { release { } } }
// loads key.properties
''');
      final result =
          await newConfigurator(StringBuffer()).configure(debugSigning: true);
      expect(result.action, SigningAction.skipped);
    });

    test('creates a backup before injecting debug signing', () async {
      final gradle = await writeGradle('''
android { buildTypes { release { signingConfig = signingConfigs.getByName("release") } } }
// loads key.properties
''');
      await newConfigurator(StringBuffer()).configure(debugSigning: true);
      final backup = File('${gradle.path}.bak');
      expect(backup.existsSync(), isTrue);
      expect(await backup.readAsString(), contains('getByName("release")'));
    });
  });

  group('SigningConfigurator.error path', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('signing_error_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('throws actionable error when signing is unresolved', () async {
      await writeGradle('''
android { buildTypes { release { } } }
// loads key.properties
''');

      expect(
        () => newConfigurator(StringBuffer()).configure(),
        throwsA(isA<BuildOptimizerException>()),
      );
    });
  });
}
