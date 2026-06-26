/// A CLI tool and library to analyze and reduce the size of Flutter
/// APK, AAB, and IPA build artifacts.
library build_slim;

export 'src/analyzer/locale_detector.dart';
export 'src/builder/artifact_comparator.dart';
export 'src/builder/build_runner.dart';
export 'src/cli/runner.dart';
export 'src/optimizer/optimizer_pipeline.dart';
export 'src/optimizer/webp_optimizer.dart';
export 'src/reporter/console_reporter.dart';
export 'src/reporter/html_reporter.dart';
export 'src/reporter/json_reporter.dart';
export 'src/reporter/report_model.dart';
export 'src/util/file_size_util.dart';
export 'src/util/logger.dart';
export 'src/util/process_runner.dart';
