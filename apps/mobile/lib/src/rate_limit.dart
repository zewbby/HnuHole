/// Strict Retry-After seconds used by the existing JSON error dialects.
int parseRetryAfterSeconds(String value) {
  if (!RegExp(r'^[1-9][0-9]{0,4}$').hasMatch(value)) {
    throw const FormatException('Invalid retry delay');
  }
  final seconds = int.parse(value);
  if (seconds > 86400) throw const FormatException('Invalid retry delay');
  return seconds;
}

/// Durable wall-clock deadline with a bounded conservative clock rollback.
/// A rollback can restore at most the original wait, never an unbounded delay.
class RateLimitWait {
  RateLimitWait(DateTime now, int seconds)
    : recordedAt = now.toUtc(),
      seconds = parseRetryAfterSeconds('$seconds'),
      notBefore = now.toUtc().add(Duration(seconds: seconds));

  RateLimitWait.fromJson(Map value)
    : recordedAt = DateTime.parse(value['recordedAt'] as String).toUtc(),
      notBefore = DateTime.parse(value['notBefore'] as String).toUtc(),
      seconds = parseRetryAfterSeconds('${value['seconds']}');

  final DateTime recordedAt, notBefore;
  final int seconds;
  final Stopwatch _elapsed = Stopwatch()..start();
  int remaining(DateTime now) {
    final wall =
        ((notBefore.difference(now.toUtc()).inMilliseconds + 999) ~/ 1000)
            .clamp(0, seconds);
    final bounded = (seconds - _elapsed.elapsed.inSeconds).clamp(0, seconds);
    return wall < bounded ? wall : bounded;
  }

  Map<String, Object> toJson() => {
    'recordedAt': recordedAt.toIso8601String(),
    'notBefore': notBefore.toIso8601String(),
    'seconds': seconds,
  };
}

String rateLimitDraftMessage(int seconds) =>
    '短时间内操作次数已达上限，请 $seconds 秒后重试。内容已保存为草稿';
