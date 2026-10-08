import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/posts/post_protocol.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';

void main() {
  test('Dart validates all shared nine digest and seven Unicode16 vectors', () {
    final suite = jsonDecode(
      File('../../packages/post-protocol-vectors/post-command-v1.json')
          .readAsStringSync(),
    ) as Map;
    expect(suite['unicodeVersion'], PostContentRules.unicodeVersion);
    expect(suite['cases'], hasLength(9));
    expect(suite['graphemeCases'], hasLength(7));
    for (final c in suite['cases'] as List) {
      final input = c['input'] as Map;
      final frame = switch (c['operation']) {
        'CREATE' => PostProtocol.create(
          channelId: input['channelId'],
          identityId: input['identityId'],
          title: input['title'],
          body: input['body'],
        ),
        'RETRY' => PostProtocol.retry(
          taskId: input['taskId'],
          expectedAttemptVersion: input['expectedAttemptVersion'],
          title: input['title'],
          body: input['body'],
        ),
        'CANCEL' => PostProtocol.cancel(
          taskId: input['taskId'],
          expectedAttemptVersion: input['expectedAttemptVersion'],
        ),
        'HIDE_TASK' => PostProtocol.hide(
          taskId: input['taskId'],
          expectedAttemptVersion: input['expectedAttemptVersion'],
        ),
        'DELETE_POST' => PostProtocol.delete(postId: input['postId']),
        _ => throw StateError('Unknown shared operation'),
      };
      final hex = frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, c['frameHex'], reason: c['id']);
      expect(PostProtocol.digest(frame), c['requestDigest'], reason: c['id']);
    }
    for (final c in suite['graphemeCases'] as List) {
      expect(
        PostContentRules.count(c['text']),
        c['expectedClusters'],
        reason: c['id'],
      );
    }
  });

  test('all1093 official Unicode16 cases match every grapheme boundary', () {
    final lines = File(
      '../../services/api/internal/posts/testdata/GraphemeBreakTest-16.0.0.txt',
    ).readAsLinesSync();
    var cases = 0;
    for (var line = 0; line < lines.length; line++) {
      final data = lines[line].split('#').first.trim();
      if (data.isEmpty) continue;
      final expected = <String>[];
      final current = <int>[];
      for (final token in data.split(RegExp(r'\s+'))) {
        if (token == '÷') {
          if (current.isNotEmpty) {
            expected.add(String.fromCharCodes(current));
            current.clear();
          }
        } else if (token != '×') {
          current.add(int.parse(token, radix: 16));
        }
      }
      expect(current, isEmpty);
      final value = expected.join();
      expect(
        value.characters.toList(),
        expected,
        reason: 'official Unicode16 line ${line + 1}',
      );
      expect(PostContentRules.count(value), expected.length);
      cases++;
    }
    expect(cases, 1093);
  });

  test('content limits count visible clusters and preserve original Unicode and line endings', () {
    PostContentRules.validate(
      List.filled(15, '👩‍💻').join(),
      List.filled(3000, 'e\u0301').join(),
    );
    PostContentRules.validate(' \t\r\n字 ', ' !\n ');
    expect(PostContentRules.count('\r\n'), 1);
    expect(
      () => PostContentRules.validate(List.filled(16, '字').join(), 'a'),
      throwsFormatException,
    );
    expect(
      () => PostContentRules.validate('a', List.filled(3001, '字').join()),
      throwsFormatException,
    );
    String digest(String title, String body) => PostProtocol.digest(
      PostProtocol.create(
        channelId: _id,
        identityId: _other,
        title: title,
        body: body,
      ),
    );
    expect(digest('é', 'a\nb'), isNot(digest('e\u0301', 'a\nb')));
    expect(digest('é', 'a\nb'), isNot(digest('é', 'a\r\nb')));
    expect(digest('a', 'body'), isNot(digest(' a', 'body')));
  });

  test(
    'control, invisible-only, empty, and unpaired surrogate text is rejected',
    () {
      for (final invalid in [
        '',
        ' \t\r\n\u00a0\u2003 ',
        '\u200b\u200c\u200d\ufe0f\u{e0100}',
        'a\x00',
        'a\x1b',
        'a\u0085',
        '\ud800',
        '\udfff',
        'a\ud800b',
      ]) {
        expect(
          () => PostContentRules.validate(invalid, 'a'),
          throwsFormatException,
        );
        expect(
          () => PostContentRules.validate('a', invalid),
          throwsFormatException,
        );
      }
      expect(PostContentRules.count('😀'), 1);
    },
  );

  test('draft meaningful check preserves invalid editing text for later validation', () {
    for (final blank in ['', ' \t\r\n\u00a0\u2003 ', '\u200b\ufe0f\u{e0100}']) {
      expect(PostContentRules.hasMeaningfulText(blank), isFalse);
    }
    for (final edited in ['正文', ' ! ', '\u0301', '\ud800', 'a\x00']) {
      expect(PostContentRules.hasMeaningfulText(edited), isTrue);
    }
  });

  test('independent byte limits prevent combining-mark bypass', () {
    final title = '😀${List.filled(2046, '\u0301').join()}';
    final body = '😀${List.filled(32766, '\u0301').join()}';
    expect(utf8.encode(title), hasLength(4096));
    expect(utf8.encode(body), hasLength(65536));
    PostContentRules.validate(title, body);
    expect(
      () => PostContentRules.validate('$title\u0301', 'a'),
      throwsFormatException,
    );
    expect(
      () => PostContentRules.validate('a', '$body\u0301'),
      throwsFormatException,
    );
  });

  test('frozen whitespace/default-ignorable tables have exact Unicode16 cardinalities', () {
    var space = 0, ignored = 0;
    for (var scalar = 0; scalar <= 0x10ffff; scalar++) {
      if (PostContentRules.whiteSpace(scalar)) space++;
      if (PostContentRules.defaultIgnorable(scalar)) ignored++;
    }
    expect(space, 25);
    expect(ignored, 4174);
  });

  test('IDs, commands, versions and cursor are canonical bounded values', () {
    for (final invalid in [
      '',
      '00000000-0000-0000-0000-000000000000',
      'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
      '{$_id}',
      _id.replaceAll('-', ''),
    ]) {
      expect(() => PostProtocol.resourceId(invalid), throwsFormatException);
    }
    final command = AuthCrypto.encode(List.filled(16, 0x42));
    expect(PostProtocol.commandId(command), command);
    for (final invalid in [
      '',
      'AAAAAAAAAAAAAAAAAAAAAA',
      '$command==',
      '${command.substring(0, 21)}h',
      ' $command',
      '______________________',
    ]) {
      expect(() => PostProtocol.commandId(invalid), throwsFormatException);
    }
    for (final version in [0, -1, 2147483648]) {
      expect(
        () => PostProtocol.cancel(taskId: _id, expectedAttemptVersion: version),
        throwsFormatException,
      );
    }
    expect(PostProtocol.version(2147483647), 2147483647);
    for (final cursor in ['', 'abc=', List.filled(1025, 'a').join()]) {
      expect(() => PostProtocol.cursor(cursor), throwsFormatException);
    }
    expect(PostProtocol.cursor(null), isNull);
  });
}
