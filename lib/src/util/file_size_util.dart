/// Utility functions for formatting file sizes.
class FileSizeUtil {
  FileSizeUtil._();

  static const int _bytesPerKB = 1024;
  static const int _bytesPerMB = 1024 * 1024;
  static const int _bytesPerGB = 1024 * 1024 * 1024;

  /// Formats [bytes] as a human-readable string.
  ///
  /// Examples:
  /// * `512 B`
  /// * `1.5 KB`
  /// * `18.5 MB`
  static String format(int bytes) {
    if (bytes < 0) return '-${format(-bytes)}';
    if (bytes < _bytesPerKB) return '$bytes B';
    if (bytes < _bytesPerMB) {
      return '${(bytes / _bytesPerKB).toStringAsFixed(1)} KB';
    }
    if (bytes < _bytesPerGB) {
      return '${(bytes / _bytesPerMB).toStringAsFixed(1)} MB';
    }
    return '${(bytes / _bytesPerGB).toStringAsFixed(1)} GB';
  }

  /// Returns the percentage reduction from [before] to [after].
  static double percentSaved(int before, int after) {
    if (before <= 0) return 0.0;
    return ((before - after) / before) * 100;
  }
}
