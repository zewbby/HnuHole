import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/posts/post_models.dart';
import 'package:hnuhole_mobile/src/posts/post_protocol.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _time = '2026-10-08T00:00:00Z';
Map<String, Object?> _card() => {
  'postId': _id,
  'channelId': _id,
  'title': '原文',
  'author': {'state': 'ACTIVE', 'nickname': '甲', 'avatar': 'default-v1'},
  'publishedAt': _time,
};
Map<String, Object?> _task() => {
  'task': {
    'taskId': _id,
    'postId': _id,
    'channelId': _id,
    'identityId': _id,
    'attemptVersion': 1,
    'state': 'ACCEPTED',
    'acceptedAt': _time,
    'serverSortAt': _time,
    'terminalAt': null,
    'failureCode': null,
    'visible': true,
    'contentAvailable': true,
    'canRetry': false,
    'canCancel': true,
    'canHide': false,
  },
  'content': {'title': '标题', 'body': '正文'},
};

void main() {
  test(
    'public card never accepts body previews or private owner/identity fields',
    () {
      expect(PostCard.fromJson(_card()).title, '原文');
      for (final extra in [
        'body',
        'bodyPreview',
        'accountId',
        'ownerId',
        'canDelete',
        'identityId',
      ]) {
        expect(
          () => PostCard.fromJson({..._card(), extra: _id}),
          throwsFormatException,
        );
        final card = _card();
        card['author'] = <String, Object?>{
          ...card['author'] as Map,
          extra: _id,
        };
        expect(() => PostCard.fromJson(card), throwsFormatException);
      }
      final detail = PostDetail.fromJson({..._card(), 'body': ' 原始\r\n正文 '});
      expect(detail.body, ' 原始\r\n正文 ');
    },
  );

  test(
    'independent inactive author code and projection branches are strict',
    () {
      for (final state in ['DELETED', 'ACCOUNT_CLOSED']) {
        final author = PostAuthor.fromJson({
          'state': state,
          'shortCode': 'ABCDEFGHIJK2',
          'avatar': 'inactive-v1',
        });
        expect(author.displayName, '注销身份 · ABCDEFGHIJK2');
        expect(author.inactiveMessage, state == 'DELETED' ? '身份已删除' : '账户已注销');
        expect(author.nickname, isNull);
      }
      for (final invalid in [
        {
          'state': 'ACTIVE',
          'nickname': '甲',
          'shortCode': 'ABCDEFGHIJK2',
          'avatar': 'default-v1',
        },
        {
          'state': 'DELETED',
          'nickname': '甲',
          'shortCode': 'ABCDEFGHIJK2',
          'avatar': 'inactive-v1',
        },
        {
          'state': 'ACCOUNT_CLOSED',
          'shortCode': '123456789012',
          'avatar': 'inactive-v1',
        },
        {'state': 'ACTIVE', 'nickname': '甲', 'avatar': 'inactive-v1'},
      ]) {
        expect(() => PostAuthor.fromJson(invalid), throwsFormatException);
      }
    },
  );

  test('command history accepts only the exact operation/state branch', () {
    final accepted = PostCommandResult.fromJson({
      'state': 'ACCEPTED',
      'operation': 'CREATE',
      'taskId': _id,
      'postId': _id,
      'attemptVersion': 1,
    });
    expect(accepted.state, PostCommandState.accepted);
    expect(accepted.operation, PostOperation.create);
    expect(
      PostCommandResult.fromJson({'state': 'UNKNOWN_NOT_OBSERVED'}).operation,
      isNull,
    );
    expect(
      PostCommandResult.fromJson({'state': 'RESULT_EXPIRED'}).state,
      PostCommandState.resultExpired,
    );
    expect(
      PostCommandResult.fromJson({
        'state': 'REJECTED',
        'operation': 'RETRY',
        'errorCode': 'TASK_VERSION_CONFLICT',
      }).errorCode,
      'TASK_VERSION_CONFLICT',
    );
    expect(
      PostCommandResult.fromJson({
        'state': 'NOT_ACCEPTED',
        'operation': 'CREATE',
        'reason': 'COMMAND_SEALED',
      }).state,
      PostCommandState.notAccepted,
    );
    for (final invalid in [
      {'state': 'UNKNOWN_NOT_OBSERVED', 'operation': 'CREATE'},
      {
        'state': 'ACCEPTED',
        'operation': 'CANCEL',
        'taskId': _id,
        'postId': _id,
        'attemptVersion': 1,
      },
      {
        'state': 'COMMITTED',
        'operation': 'CANCEL',
        'taskId': _id,
        'attemptVersion': 1,
        'taskState': 'ACCEPTED',
      },
      {
        'state': 'COMMITTED',
        'operation': 'HIDE_TASK',
        'taskId': _id,
        'attemptVersion': 1,
        'taskState': 'FAILED',
      },
      {'state': 'REJECTED', 'operation': 'CREATE', 'errorCode': 'SQL_FAILURE'},
      {'state': 'NOT_ACCEPTED', 'operation': 'CREATE', 'reason': 'TIMEOUT'},
    ]) {
      expect(() => PostCommandResult.fromJson(invalid), throwsFormatException);
    }
  });

  test('task content availability and authoritative state must agree', () {
    expect(PostTask.fromJson(_task()).content!.body, '正文');
    for (final update in [
      {'state': 'UNKNOWN'},
      {'attemptVersion': 1.0},
      {'attemptVersion': 0},
      {'state': 'FAILED'},
      {'terminalAt': _time},
      {'failureCode': 'PUBLISHING_STOPPED'},
      {'contentAvailable': false},
      {'canRetry': true},
      {'canCancel': false},
      {'canHide': true},
      {'serverSortAt': '2026-10-08T00:00:01Z'},
    ]) {
      final detail = _task();
      detail['task'] = <String, Object?>{...detail['task'] as Map, ...update};
      expect(
        () => PostTask.fromJson(detail),
        throwsFormatException,
        reason: '$update',
      );
    }
    final hidden = _task();
    hidden['task'] = <String, Object?>{
      ...hidden['task'] as Map,
      'state': 'FAILED',
      'terminalAt': _time,
      'failureCode': 'PUBLISHING_STOPPED',
      'visible': false,
      'contentAvailable': false,
      'canCancel': false,
    };
    hidden['content'] = null;
    expect(PostTask.fromJson(hidden).content, isNull);
    expect(PostTask.fromJson(hidden).visible, isFalse);
  });

  test('composer selection has no guessed default identity', () {
    for (final state in ['INITIAL_SETUP_REQUIRED', 'SELECTION_REQUIRED']) {
      expect(
        ComposerContext.fromJson({
          'selectionState': state,
          'defaultIdentityId': null,
        }).defaultIdentityId,
        isNull,
      );
      expect(
        () => ComposerContext.fromJson({
          'selectionState': state,
          'defaultIdentityId': _id,
        }),
        throwsFormatException,
      );
    }
    expect(
      ComposerContext.fromJson({
        'selectionState': 'DEFAULT_AVAILABLE',
        'defaultIdentityId': _id,
      }).selectionState,
      ComposerSelectionState.defaultAvailable,
    );
    expect(
      () => ComposerContext.fromJson({
        'selectionState': 'DEFAULT_AVAILABLE',
        'defaultIdentityId': null,
      }),
      throwsFormatException,
    );
  });

  test('UTC times reject offsets, invalid calendar, and empty fractions', () {
    expect(PostJson.utc('2026-10-08T00:00:00.123456789Z').isUtc, isTrue);
    for (final invalid in [
      '2026-02-30T00:00:00Z',
      '2026-10-08T24:00:00Z',
      '2026-10-08T00:00:00+00:00',
      '2026-10-08T00:00:00.Z',
      '2026-10-08 00:00:00Z',
    ]) {
      expect(() => PostJson.utc(invalid), throwsFormatException);
    }
  });

  test(
    'pages and private capabilities reject extensions and remain immutable',
    () {
      final page = PostsPage.fromJson({
        'items': [_card()],
        'nextCursor': null,
      }, PostCard.fromJson);
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(
        () => PostsPage.fromJson({
          'items': List.generate(51, (_) => _card()),
          'nextCursor': null,
        }, PostCard.fromJson),
        throwsFormatException,
      );
      expect(
        () => PostsPage.fromJson({
          'items': [],
          'nextCursor': '',
        }, PostCard.fromJson),
        throwsFormatException,
      );
      expect(
        PostCapabilities.fromJson({
          'postId': _id,
          'canDelete': true,
          'canEdit': false,
        }).canDelete,
        isTrue,
      );
      expect(
        () => PostCapabilities.fromJson({
          'postId': _id,
          'canDelete': true,
          'canEdit': true,
        }),
        throwsFormatException,
      );
    },
  );
}
