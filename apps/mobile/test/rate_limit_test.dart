import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/rate_limit.dart';

void main() {
  test('Retry-After accepts exact integer seconds through one day', () {
    for (final value in ['1', '301', '3600', '86400']) {
      expect(parseRetryAfterSeconds(value), int.parse(value));
    }
    for (final value in [
      '0',
      '01',
      '-1',
      '1.0',
      ' 1',
      '1 ',
      '+1',
      '86401',
      '999999',
      'Thu, 01 Jan 2026 00:00:00 GMT',
    ]) {
      expect(() => parseRetryAfterSeconds(value), throwsFormatException);
    }
  });

  test(
    'durable wait rounds up, survives restart and bounds wall-clock rollback',
    () {
      final now = DateTime.utc(2026, 10, 24);
      final restored = RateLimitWait.fromJson(RateLimitWait(now, 60).toJson());
      expect(restored.remaining(now.add(const Duration(milliseconds: 1))), 60);
      expect(restored.remaining(now.add(const Duration(seconds: 30))), 30);
      expect(restored.remaining(now.add(const Duration(seconds: 60))), 0);
      expect(restored.remaining(now.subtract(const Duration(days: 365))), 60);
    },
  );
}
