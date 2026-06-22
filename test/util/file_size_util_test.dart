import 'package:build_slim/src/util/file_size_util.dart';
import 'package:test/test.dart';

void main() {
  group('FileSizeUtil.format', () {
    test('formats zero bytes', () {
      expect(FileSizeUtil.format(0), '0 B');
    });

    test('formats below 1 KB', () {
      expect(FileSizeUtil.format(1), '1 B');
      expect(FileSizeUtil.format(512), '512 B');
      expect(FileSizeUtil.format(1023), '1023 B');
    });

    test('formats KB range with one decimal', () {
      expect(FileSizeUtil.format(1024), '1.0 KB');
      expect(FileSizeUtil.format(1536), '1.5 KB');
      expect(FileSizeUtil.format(2048), '2.0 KB');
    });

    test('formats MB range with one decimal', () {
      expect(FileSizeUtil.format(1024 * 1024), '1.0 MB');
      expect(FileSizeUtil.format(18 * 1024 * 1024 + 512 * 1024), '18.5 MB');
    });

    test('formats GB range with one decimal', () {
      expect(FileSizeUtil.format(2 * 1024 * 1024 * 1024), '2.0 GB');
    });

    test('formats negative bytes with leading minus', () {
      expect(FileSizeUtil.format(-512), '-512 B');
      expect(FileSizeUtil.format(-2048), '-2.0 KB');
      expect(FileSizeUtil.format(-1), '-1 B');
    });

    test('boundary values between units', () {
      expect(FileSizeUtil.format(1023), '1023 B');
      expect(FileSizeUtil.format(1024), '1.0 KB');
      expect(FileSizeUtil.format(1024 * 1024 - 1), '1024.0 KB');
      expect(FileSizeUtil.format(1024 * 1024), '1.0 MB');
    });
  });

  group('FileSizeUtil.percentSaved', () {
    test('returns zero when before is zero', () {
      expect(FileSizeUtil.percentSaved(0, 0), 0.0);
    });

    test('returns zero when before is negative', () {
      expect(FileSizeUtil.percentSaved(-10, 0), 0.0);
    });

    test('computes positive savings', () {
      expect(FileSizeUtil.percentSaved(1000, 800), closeTo(20.0, 1e-9));
      expect(FileSizeUtil.percentSaved(2000, 500), closeTo(75.0, 1e-9));
    });

    test('computes zero savings when equal', () {
      expect(FileSizeUtil.percentSaved(1000, 1000), 0.0);
    });

    test('computes negative savings (size growth)', () {
      expect(FileSizeUtil.percentSaved(1000, 1200), closeTo(-20.0, 1e-9));
      expect(FileSizeUtil.percentSaved(1000, 2000), closeTo(-100.0, 1e-9));
    });

    test('computes total savings when after is zero', () {
      expect(FileSizeUtil.percentSaved(1000, 0), 100.0);
    });
  });
}
