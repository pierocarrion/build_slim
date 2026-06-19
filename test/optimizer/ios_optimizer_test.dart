import 'dart:io';

import 'package:build_slim/src/optimizer/ios_optimizer.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ios_optimizer_test_');
    final flutterDir = Directory(p.join(tempDir.path, 'ios', 'Flutter'))
      ..createSync(recursive: true);
    await File(p.join(flutterDir.path, 'Release.xcconfig')).writeAsString('''
#include "Generated.xcconfig"
''');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('injects Release.xcconfig settings', () async {
    final optimizer = IosOptimizer(
      projectDir: tempDir.path,
      logger: const Logger(level: LogLevel.none),
    );
    final applied = await optimizer.optimize();

    expect(applied, isNotEmpty);

    final xcconfig = File(
      p.join(tempDir.path, 'ios', 'Flutter', 'Release.xcconfig'),
    );
    final content = await xcconfig.readAsString();
    expect(content, contains('ENABLE_BITCODE=NO'));
    expect(content, contains('STRIP_STYLE=all'));
    expect(content, contains('DEAD_CODE_STRIPPING=YES'));
    expect(content, contains('GCC_OPTIMIZATION_LEVEL=s'));
    expect(content, contains('SWIFT_OPTIMIZATION_LEVEL=-Osize'));
  });
}
