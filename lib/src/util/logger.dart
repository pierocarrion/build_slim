import 'package:ansi_styles/ansi_styles.dart';

/// Verbosity level for [Logger].
enum LogLevel {
  /// No output.
  none,

  /// Errors only.
  error,

  /// Standard user-facing messages.
  info,

  /// Detailed diagnostic messages.
  verbose,
}

/// A scoped, ANSI-aware logger for CLI output.
class Logger {
  /// Creates a logger with the given [level] and optional [scope] prefix.
  const Logger({this.level = LogLevel.info, this.scope});

  /// The minimum level this logger emits.
  final LogLevel level;

  /// Optional prefix added to every message.
  final String? scope;

  String? get _prefix => scope == null ? null : '[$scope]';

  void _log(
    LogLevel messageLevel,
    String message,
    String? Function(String?)? color,
  ) {
    if (level.index < messageLevel.index) return;
    final prefix = _prefix;
    final output = prefix == null ? message : '$prefix $message';
    // ignore: avoid_print
    print(color?.call(output) ?? output);
  }

  /// Logs an informational message.
  void info(String message) => _log(LogLevel.info, message, null);

  /// Logs a success message (green).
  void success(String message) =>
      _log(LogLevel.info, message, (s) => AnsiStyles.green(s));

  /// Logs a warning message (yellow).
  void warning(String message) =>
      _log(LogLevel.info, message, (s) => AnsiStyles.yellow(s));

  /// Logs an error message (red).
  void error(String message) =>
      _log(LogLevel.error, message, (s) => AnsiStyles.red(s));

  /// Logs a verbose diagnostic message.
  void verbose(String message) =>
      _log(LogLevel.verbose, message, (s) => AnsiStyles.gray(s));
}
