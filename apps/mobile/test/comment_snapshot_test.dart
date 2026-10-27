import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_snapshot.dart';

void main() {
  for (final failure in [
    const CommentHttpFailure(null, 'TIMEOUT'),
    const CommentHttpFailure(null, 'TRANSPORT'),
    const CommentHttpFailure(503, 'COMMENT_SNAPSHOT_UNAVAILABLE'),
  ]) {
    test(
      'one read retries ${failure.code} once with the same initial nonce',
      () async {
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
          nonces.add(snapshotRequest);
          if (nonces.length == 1) throw failure;
          return {'comments': <Object>[], 'nextCursor': null};
        }, pause: () async {});
        await reader.load(
          '/api/v1/posts/fixture/comments',
          current: () => true,
        );
        expect(nonces.length, 2);
        expect(nonces[0], isNotNull);
        expect(nonces[0], nonces[1]);
      },
    );
  }
  for (final failure in [
    const CommentHttpFailure(400, 'CURSOR_INVALID'),
    const CommentHttpFailure(429, 'RATE_LIMITED'),
    const CommentHttpFailure(422, 'COMMENT_SNAPSHOT_TOO_LARGE'),
    const CommentHttpFailure(503, 'COMMENT_SNAPSHOT_CAPACITY'),
    const CommentHttpFailure(503, 'COMMENT_SNAPSHOT_INTEGRITY'),
    const CommentHttpFailure(503, 'AUTHORIZATION_UNAVAILABLE'),
    const CommentHttpFailure(403, 'FORBIDDEN'),
  ]) {
    test('${failure.code} never retries or creates another snapshot', () async {
      var calls = 0;
      final reader = CommentSnapshotReader((
        String method,
        String path, {
        Map<String, dynamic>? body,
        Map<String, String>? query,
        Uint8List? bytes,
        String? mime,
        String? snapshotRequest,
      }) async {
        calls++;
        throw failure;
      }, pause: () async {});
      await expectLater(
        reader.load('/comments', current: () => true),
        throwsA(same(failure)),
      );
      expect(calls, 1);
    });
  }
  test(
    'retry exhaustion stays at two and never sends a nonce with a cursor',
    () async {
      var calls = 0;
      final reader = CommentSnapshotReader((
        String method,
        String path, {
        Map<String, dynamic>? body,
        Map<String, String>? query,
        Uint8List? bytes,
        String? mime,
        String? snapshotRequest,
      }) async {
        calls++;
        expect(snapshotRequest, isNull);
        expect(query, {'cursor': 'original'});
        throw const CommentHttpFailure(null, 'TRANSPORT');
      }, pause: () async {});
      await expectLater(
        reader.load(
          '/comments',
          query: {'cursor': 'original'},
          current: () => true,
        ),
        throwsA(isA<CommentHttpFailure>()),
      );
      expect(calls, 2);
    },
  );
  test(
    'disposal or account change during short delay cancels the second attempt',
    () async {
      var active = true, calls = 0;
      final pause = Completer<void>();
      final started = Completer<void>();
      final reader = CommentSnapshotReader(
        (
          String method,
          String path, {
          Map<String, dynamic>? body,
          Map<String, String>? query,
          Uint8List? bytes,
          String? mime,
          String? snapshotRequest,
        }) async {
          calls++;
          throw const CommentHttpFailure(null, 'TIMEOUT');
        },
        pause: () {
          started.complete();
          return pause.future;
        },
      );
      final result = reader.load('/comments', current: () => active);
      final assertion = expectLater(
        result,
        throwsA(isA<CommentReadCancelled>()),
      );
      await started.future;
      active = false;
      pause.complete();
      await assertion;
      expect(calls, 1);
    },
  );
}
