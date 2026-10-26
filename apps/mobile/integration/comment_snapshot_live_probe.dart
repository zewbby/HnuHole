// Production Dart snapshot reader + strict pinned TLS transport, disposable Go
// SQL/Redis harness only. Never disable certificate verification.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_snapshot.dart';

Future<void> main(List<String> args) async {
  final fixture =
      jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
  final phase = args[1];
  final transport = CommentHttp(
    Uri.parse(fixture['url'] as String),
    client: HttpClient(
      context: SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(
          utf8.encode(fixture['certificatePem'] as String),
        ),
    ),
  );
  var requests = 0;
  final nonces = <String?>[];
  final reader = CommentSnapshotReader((
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Uint8List? bytes,
    String? mime,
    String? snapshotRequest,
  }) async {
    requests++;
    nonces.add(snapshotRequest);
    return (await transport.send(
      fixture['token'] as String,
      method,
      path,
      query: query,
      snapshotRequest: snapshotRequest,
    )).value;
  });
  void check(bool value, String code) {
    if (!value) throw FormatException(code);
  }

  final path = '/api/v1/posts/${fixture['postId']}/comments';
  try {
    if (phase == 'live') {
      final first = await reader.load(
        path,
        query: {'sort': 'recent', 'limit': '1'},
        current: () => true,
      );
      check(
        requests == 2 && nonces[0] != null && nonces[0] == nonces[1],
        'response-loss retry changed nonce or budget',
      );
      final cursor = first['nextCursor'] as String;
      check(
        cursor.length == 104 && (first['comments'] as List).length == 1,
        'V2 initial page',
      );
      final rest = await reader.load(
        path,
        query: {'cursor': cursor},
        current: () => true,
      );
      check(
        (rest['comments'] as List).length == 2 &&
            rest['nextCursor'] == null &&
            nonces.last == null,
        'frozen continuation',
      );
      final beforeQuota = requests;
      try {
        await reader.load(path, current: () => true);
        throw StateError('quota allowed');
      } on CommentHttpFailure catch (e) {
        check(
          e.status == 429 &&
              e.code == 'RATE_LIMITED' &&
              (e.retryAfterSeconds ?? 0) > 0,
          'quota classification',
        );
      }
      check(requests == beforeQuota + 1, 'quota automatically retried');
      final beforeInvalid = requests;
      final changed = cursor[50] == 'A' ? 'B' : 'A';
      try {
        await reader.load(
          path,
          query: {
            'cursor':
                '${cursor.substring(0, 50)}$changed${cursor.substring(51)}',
          },
          current: () => true,
        );
        throw StateError('forged cursor allowed');
      } on CommentHttpFailure catch (e) {
        check(commentCursorInvalid(e), 'invalid cursor classification');
      }
      check(
        requests == beforeInvalid + 1,
        'invalid cursor automatically retried',
      );
    } else if (phase == 'down') {
      try {
        await reader.load(
          path,
          query: {'cursor': fixture['cursor'] as String},
          current: () => true,
        );
        throw StateError('dead Redis succeeded');
      } on CommentHttpFailure catch (e) {
        check(
          e.status == 503 && e.code == 'COMMENT_SNAPSHOT_UNAVAILABLE',
          'outage became invalid cursor',
        );
      }
      check(
        requests == 2 && nonces.every((n) => n == null),
        'outage retry budget',
      );
    } else {
      throw StateError('unknown phase');
    }
    final result = jsonEncode({
      'status': 'PASS',
      'phase': phase,
      'requests': requests,
    });
    await File(args[2]).writeAsString(result, flush: true);
    stdout.write(result);
  } finally {
    transport.close();
  }
}
