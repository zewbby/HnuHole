// Compiled pure Dart probe. Only a private loopback fixture and its pinned CA.
import 'dart:convert';
import 'dart:io';

import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

void check(bool value, String step) {
  if (!value) throw StateError(step);
}

Future<void> main(List<String> args) async {
  if (args.length != 3 || args[1] != 'feed') {
    exitCode = 2;
    return;
  }
  final output = File(args[2]);
  HttpPostApi? api;
  var step = 'fixture';
  try {
    final fixture =
        jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
    final uri = Uri.parse(fixture['url'] as String);
    check(
      uri.scheme == 'https' &&
          {'127.0.0.1', 'localhost', '::1'}.contains(uri.host),
      'loopback_required',
    );
    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(
        utf8.encode(fixture['certificatePem'] as String),
      );
    api = HttpPostApi(
      communityBaseUri: uri,
      client: HttpClient(context: trust),
    );
    final reader = fixture['readerToken'] as String,
        owner = fixture['ownerToken'] as String;
    final postId = fixture['postId'] as String,
        channelId = fixture['channelId'] as String;
    step = 'preferences';
    check(
      (await api.feedPreferences(sessionToken: reader))
          .value
          .blockedChannelIds
          .isEmpty,
      step,
    );
    step = 'pagination';
    final first = (await api.timeline(sessionToken: reader, limit: 1)).value;
    check(
      first.items.length == 1 &&
          first.nextCursor != null &&
          first.items.single.body.isNotEmpty,
      step,
    );
    final second = (await api.timeline(
      sessionToken: reader,
      limit: 1,
      cursor: first.nextCursor,
    )).value;
    check(
      second.items.length == 1 &&
          second.items.single.postId != first.items.single.postId,
      step,
    );
    check(
      (await api.timeline(sessionToken: reader)).value.items
          .every((p) => p.viewCount == 0),
      'exposure_no_count',
    );
    check(
      (await api.timeline(sessionToken: reader)).value.items
              .map((p) => p.channelId)
              .toSet()
              .length ==
          2,
      'cross_channel',
    );
    step = 'author_excluded';
    check(
      (await api.registerPostView(
            sessionToken: owner,
            postId: postId,
          )).value.viewCount ==
          0,
      step,
    );
    step = 'real_detail';
    check(
      (await api.detail(
        sessionToken: reader,
        postId: postId,
      )).value.body.isNotEmpty,
      step,
    );
    step = 'view_dedup';
    for (var i = 0; i < 2; i++) {
      check(
        (await api.registerPostView(
              sessionToken: reader,
              postId: postId,
            )).value.viewCount ==
            1,
        step,
      );
    }
    check(
      (await api.timeline(sessionToken: reader)).value.items
              .firstWhere((p) => p.postId == postId)
              .viewCount ==
          1,
      'server_total',
    );
    step = 'block';
    await api.saveFeedPreferences(
      sessionToken: reader,
      blockedChannelIds: {channelId},
    );
    check(
      (await api.feedPreferences(sessionToken: reader)).value.blockedChannelIds
          .contains(channelId),
      step,
    );
    check(
      (await api.feedPreferences(sessionToken: owner))
          .value
          .blockedChannelIds
          .isEmpty,
      'account_isolation',
    );
    check(
      (await api.timeline(
        sessionToken: reader,
        channelId: channelId,
      )).value.items.isEmpty,
      'blocked_channel_selectable',
    );
    step = 'invalidated_cursor';
    try {
      await api.timeline(
        sessionToken: reader,
        limit: 1,
        cursor: first.nextCursor,
      );
      throw StateError('stale_cursor_accepted');
    } on PostFailure catch (e) {
      check(e.code == 'CURSOR_INVALID', step);
    }
    step = 'reset';
    await api.saveFeedPreferences(sessionToken: reader, blockedChannelIds: {});
    check(
      (await api.timeline(sessionToken: reader)).value.items.length == 3,
      step,
    );
    await output.writeAsString(
      jsonEncode({
        'status': 'PASS',
        'checks': [
          'real_preferences',
          'cross_channel_pagination',
          'exposure_no_count',
          'author_excluded',
          'legacy_detail',
          'view_dedup',
          'server_total',
          'saved_block',
          'account_isolation',
          'blocked_channel_selectable',
          'cursor_invalidated',
          'reset',
        ],
      }),
    );
    stdout.writeln('PASS feed real C HTTPS/SQL');
  } catch (e) {
    await output.writeAsString(
      jsonEncode({
        'status': 'FAIL',
        'step': step,
        'kind': e.runtimeType.toString(),
      }),
    );
    stderr.writeln('FAIL feed at $step');
    exitCode = 1;
  } finally {
    api?.close();
  }
}
