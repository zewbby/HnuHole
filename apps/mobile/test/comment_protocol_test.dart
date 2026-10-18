import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/comments/comment_protocol.dart';
import 'package:hnuhole_mobile/src/posts/post_protocol.dart';
import 'package:hnuhole_mobile/src/posts/post_upload_models.dart';

String _id(int n) =>
    '11111111-1111-4111-8111-${n.toRadixString(16).padLeft(12, '0')}';

PostImageSelection _image([Map<String, dynamic> changes = const {}]) =>
    PostImageSelection.fromJson({
      'mediaId': _id(7),
      'sha256': 'ab' * 32,
      'mimeType': 'image/png',
      'byteLength': 123,
      'width': 20,
      'height': 30,
      ...changes,
    });

Uint8List _create({
  String? task,
  String? post,
  String? identity,
  String? root,
  String? target,
  String body = '回复 e\u0301\r\n👩‍💻',
  PostImageSelection? image,
}) => CommentProtocol.create(
  taskId: task ?? _id(1),
  postId: post ?? _id(2),
  identityId: identity ?? _id(3),
  rootCommentId: root ?? _id(4),
  targetCommentId: target ?? _id(5),
  body: body,
  image: image,
);

Uint8List _vector(Map<String, dynamic> vector) {
  final i = Map<String, dynamic>.from(vector['input'] as Map);
  final image = i['image'] == null
      ? null
      : PostImageSelection.fromJson(i['image']);
  return switch (vector['operation']) {
    'CREATE' => CommentProtocol.create(
      taskId: i['taskId'] as String,
      postId: i['postId'] as String,
      identityId: i['identityId'] as String,
      rootCommentId: i['rootCommentId'] as String?,
      targetCommentId: i['targetCommentId'] as String?,
      body: i['body'] as String,
      image: image,
    ),
    'RETRY' => CommentProtocol.retry(
      taskId: i['taskId'] as String,
      expectedAttemptVersion: i['expectedAttemptVersion'] as int,
      body: i['body'] as String,
      image: image,
    ),
    'ABANDON' => CommentProtocol.abandon(
      taskId: i['taskId'] as String,
      expectedAttemptVersion: i['expectedAttemptVersion'] as int,
    ),
    'DELETE' => CommentProtocol.delete(commentId: i['commentId'] as String),
    'SET_LIKE' => CommentProtocol.setLike(
      commentId: i['commentId'] as String,
      liked: i['liked'] as bool,
    ),
    _ => throw StateError('Unknown shared comment operation'),
  };
}

void main() {
  test('all twelve shared comment frames and digests match independent goldens', () {
    final suite = jsonDecode(
      File('../../packages/comment-protocol-vectors/v1.json').readAsStringSync(),
    ) as Map;
    expect(suite['version'], 1);
    expect(suite['domain'], 'HNUHOLE/COMMENT-COMMAND/V1');
    expect(suite['maxFrameBytes'], CommentProtocol.maxFrameBytes);
    expect(suite['vectors'], hasLength(12));
    for (final raw in suite['vectors'] as List) {
      final vector = Map<String, dynamic>.from(raw as Map);
      final frame = _vector(vector);
      expect(
        frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        vector['frameHex'],
        reason: vector['name'] as String,
      );
      expect(
        CommentProtocol.digest(frame),
        vector['requestDigest'],
        reason: vector['name'] as String,
      );
    }
  });

  test('every immutable binding and image field changes the digest', () {
    final original = CommentProtocol.digest(_create(image: _image()));
    final changes = <Uint8List>[
      _create(task: _id(101), image: _image()),
      _create(post: _id(102), image: _image()),
      _create(identity: _id(103), image: _image()),
      _create(root: _id(104), image: _image()),
      _create(target: _id(105), image: _image()),
      _create(body: '回复 e\u0301\r\n👩‍💻 ', image: _image()),
      _create(body: '回复 e\u0301\n👩‍💻', image: _image()),
      _create(body: '回复 é\r\n👩‍💻', image: _image()),
      _create(image: _image({'mediaId': _id(106)})),
      _create(image: _image({'sha256': 'cd' * 32})),
      _create(image: _image({'mimeType': 'image/webp'})),
      _create(image: _image({'byteLength': 124})),
      _create(image: _image({'width': 21})),
      _create(image: _image({'height': 31})),
      _create(),
    ];
    for (final changed in changes) {
      expect(CommentProtocol.digest(changed), isNot(original));
    }
    final retry = CommentProtocol.retry(
      taskId: _id(1), expectedAttemptVersion: 1, body: '',
    );
    expect(
      CommentProtocol.digest(CommentProtocol.retry(
        taskId: _id(1), expectedAttemptVersion: 2, body: '',
      )),
      isNot(CommentProtocol.digest(retry)),
    );
    expect(
      CommentProtocol.digest(CommentProtocol.setLike(commentId: _id(6), liked: true)),
      isNot(CommentProtocol.digest(CommentProtocol.setLike(commentId: _id(6), liked: false))),
    );
  });

  test('framing rejects invalid IDs, versions, targets and Unicode scalars', () {
    for (final id in [
      '',
      '00000000-0000-0000-0000-000000000000',
      'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
      '{11111111-1111-4111-8111-111111111111}',
    ]) {
      expect(() => _create(post: id), throwsFormatException);
    }
    for (final version in [-1, 0, 2147483648]) {
      expect(() => CommentProtocol.retry(
        taskId: _id(1), expectedAttemptVersion: version, body: '',
      ), throwsFormatException);
      expect(() => CommentProtocol.abandon(
        taskId: _id(1), expectedAttemptVersion: version,
      ), throwsFormatException);
    }
    for (final body in ['\ud800', '\udfff', 'a\ud800x']) {
      expect(() => _create(body: body), throwsFormatException);
    }
    expect(() => CommentProtocol.create(
      taskId: _id(1), postId: _id(2), identityId: _id(3),
      rootCommentId: _id(4), body: '',
    ), throwsFormatException);
    expect(() => _image({'sha256': 'AB' * 32}), throwsFormatException);
    expect(() => _image({'mimeType': 'image/apng'}), throwsFormatException);
    expect(() => _image({'byteLength': 10485761}), throwsFormatException);
  });

  test('stable rejection digests do not impose business text validation', () {
    for (final body in ['', ' \t\n', '\u0000', '文' * 3001]) {
      expect(_create(body: body), isNotEmpty);
    }
    final overhead = ascii.encode('HNUHOLE/COMMENT-COMMAND/V1').length +
        2 + 16 * 5 + 4 + 1;
    final body = 'a' * (CommentProtocol.maxFrameBytes - overhead);
    expect(_create(body: body), hasLength(CommentProtocol.maxFrameBytes));
    expect(() => _create(body: '${body}a'), throwsFormatException);
    expect(() => _create(body: 'a' * 262145), throwsFormatException);
  });

  test('comments have their own domain and canonical command keys', () {
    const command = 'AQEBAQEBAQEBAQEBAQEBAQ';
    expect(CommentProtocol.commandId(command), command);
    for (final invalid in ['', 'A' * 22, '$command==', '${command.substring(0, 21)}_']) {
      expect(() => CommentProtocol.commandId(invalid), throwsFormatException);
    }
    final comment = CommentProtocol.delete(commentId: _id(1));
    final post = PostProtocol.delete(postId: _id(1));
    expect(CommentProtocol.digest(comment), isNot(PostProtocol.digest(post)));
    const domain = 'HNUHOLE/COMMENT-COMMAND/V1';
    expect(ascii.decode(comment.take(ascii.encode(domain).length).toList()), domain);
  });
}
