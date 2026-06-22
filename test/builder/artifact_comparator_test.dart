import 'dart:io';

import 'package:build_slim/src/builder/artifact_comparator.dart';
import 'package:build_slim/src/reporter/report_model.dart';
import 'package:build_slim/src/util/logger.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Logger logger;
  late StringBuffer sink;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('artifact_comparator_test');
    sink = StringBuffer();
    logger = Logger(level: LogLevel.verbose, sink: sink);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeArtifact(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  group('BuildOptimizerException', () {
    test('stores message, filePath, lineNumber', () {
      const exception = BuildOptimizerException(
        'boom',
        filePath: '/a/b',
        lineNumber: 42,
      );
      expect(exception.message, 'boom');
      expect(exception.filePath, '/a/b');
      expect(exception.lineNumber, 42);
    });

    test('toString with only message', () {
      const exception = BuildOptimizerException('boom');
      expect(exception.toString(), 'BuildOptimizerException: boom');
    });

    test('toString includes filePath when set', () {
      const exception = BuildOptimizerException('boom', filePath: '/a/b');
      final str = exception.toString();
      expect(str, 'BuildOptimizerException: boom\nfile: /a/b');
    });

    test('toString includes lineNumber when set', () {
      const exception = BuildOptimizerException('boom', lineNumber: 7);
      final str = exception.toString();
      expect(str, 'BuildOptimizerException: boom\nline: 7');
    });

    test('toString includes both filePath and lineNumber when set', () {
      const exception = BuildOptimizerException(
        'boom',
        filePath: '/a/b',
        lineNumber: 7,
      );
      final lines = exception.toString().split('\n');
      expect(lines, [
        'BuildOptimizerException: boom',
        'file: /a/b',
        'line: 7',
      ]);
    });
  });

  group('Reporter contract', () {
    test('Reporter is an abstract class with render method', () {
      final reporter = _DummyReporter();
      expect(reporter.render(_emptyReport()), 'dummy');
    });
  });

  group('ArtifactComparator.compare', () {
    const comparator = ArtifactComparator();

    test('returns report with computed sizes when both artifacts exist',
        () async {
      final before = await writeArtifact('before.apk', List.filled(2000, 0));
      final after = await writeArtifact('after.apk', List.filled(1000, 0));

      final report = await comparator.compare(
        beforePath: before.path,
        afterPath: after.path,
        projectName: 'my-app',
        target: BuildTarget.apk,
        logger: logger,
      );

      expect(report.projectName, 'my-app');
      expect(report.target, BuildTarget.apk);
      expect(report.beforeSizeBytes, 2000);
      expect(report.afterSizeBytes, 1000);
      expect(report.savedBytes, 1000);
      expect(report.savedPercent, closeTo(50.0, 1e-9));
      expect(report.dartSdkVersion, 'unknown');
      expect(report.flutterVersion, 'unknown');
      expect(report.timestamp, isA<DateTime>());
    });

    test('computes negative savedBytes when after is larger than before',
        () async {
      final before = await writeArtifact('before.apk', List.filled(500, 0));
      final after = await writeArtifact('after.apk', List.filled(1500, 0));

      final report = await comparator.compare(
        beforePath: before.path,
        afterPath: after.path,
        projectName: 'app',
        target: BuildTarget.aab,
        logger: logger,
      );

      expect(report.savedBytes, -1000);
      expect(report.savedPercent, closeTo(-200.0, 1e-9));
    });

    test('logs "saved" word when after is smaller', () async {
      final before = await writeArtifact('before.apk', List.filled(2000, 0));
      final after = await writeArtifact('after.apk', List.filled(1000, 0));

      await comparator.compare(
        beforePath: before.path,
        afterPath: after.path,
        projectName: 'app',
        target: BuildTarget.apk,
        logger: logger,
      );

      expect(sink.toString(), contains('saved'));
      expect(sink.toString(), isNot(contains('added')));
    });

    test('logs "added" word when after is larger', () async {
      final before = await writeArtifact('before.apk', List.filled(500, 0));
      final after = await writeArtifact('after.apk', List.filled(1500, 0));

      await comparator.compare(
        beforePath: before.path,
        afterPath: after.path,
        projectName: 'app',
        target: BuildTarget.apk,
        logger: logger,
      );

      expect(sink.toString(), contains('added'));
    });

    test('throws BuildOptimizerException when before path does not exist',
        () async {
      final after = await writeArtifact('after.apk', [0]);

      expect(
        () => comparator.compare(
          beforePath: '${tempDir.path}/missing.apk',
          afterPath: after.path,
          projectName: 'app',
          target: BuildTarget.apk,
          logger: logger,
        ),
        throwsA(
          isA<BuildOptimizerException>()
              .having((e) => e.message, 'message', contains('missing.apk'))
              .having(
                  (e) => e.filePath, 'filePath', '${tempDir.path}/missing.apk'),
        ),
      );
    });

    test('throws BuildOptimizerException when after path does not exist',
        () async {
      final before = await writeArtifact('before.apk', [0]);

      expect(
        () => comparator.compare(
          beforePath: before.path,
          afterPath: '${tempDir.path}/missing.apk',
          projectName: 'app',
          target: BuildTarget.apk,
          logger: logger,
        ),
        throwsA(
          isA<BuildOptimizerException>().having(
              (e) => e.filePath, 'filePath', '${tempDir.path}/missing.apk'),
        ),
      );
    });
  });
}

OptimizationReport _emptyReport() => OptimizationReport(
      projectName: 'p',
      target: BuildTarget.apk,
      dartSdkVersion: 'x',
      flutterVersion: 'y',
      timestamp: DateTime.utc(2024, 1, 1),
    );

class _DummyReporter implements Reporter {
  @override
  String render(OptimizationReport report) => 'dummy';
}
