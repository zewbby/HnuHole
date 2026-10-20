// Manual shared/candidate lab probe. Read synthetic credentials from a private
// local file; never serialize credentials, tokens, content or resource IDs.
import 'dart:convert';
import 'dart:io';

import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/http_auth_api.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

void require(bool condition, String step) {
  if (!condition) throw StateError(step);
}

Future<void> main(List<String> args) async {
  if (args.length != 4 || !{'baseline', 'cas'}.contains(args[3])) {
    exitCode = 2;
    return;
  }
  var step = 'configuration';
  final checks = <String>[];
  HttpAuthApi? auth;
  HttpPostApi? posts;
  CommentHttp? comments;
  try {
    final private = jsonDecode(await File(args[0]).readAsString()) as Map;
    final config = jsonDecode(await File(args[1]).readAsString()) as Map;
    final manifestFile = File('${File(args[1]).parent.path}/manifest.json');
    final manifest = await manifestFile.exists()
        ? jsonDecode(await manifestFile.readAsString()) as Map
        : private;
    final c = Uri.parse(config['AUTH_COMMUNITY_BASE_URL'] as String);
    final v = Uri.parse(config['AUTH_VERIFIER_BASE_URL'] as String);
    for (final uri in [c, v]) {
      require(
        uri.scheme == 'https' &&
            {'127.0.0.1', 'localhost', '::1'}.contains(uri.host) &&
            uri.hasPort &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment &&
            uri.path.isEmpty,
        step,
      );
    }
    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(
        base64Decode(config['AUTH_DEV_CA_BASE64'] as String),
      );
    auth = HttpAuthApi(
      communityBaseUri: c,
      verifierBaseUri: v,
      client: HttpClient(context: trust),
    );
    posts = HttpPostApi(
      communityBaseUri: c,
      client: HttpClient(context: trust),
    );
    comments = CommentHttp(c, client: HttpClient(context: trust));
    final accounts = private['accounts'] as Map;
    step = 'two_synthetic_accounts';
    final tokens = <String>[];
    for (final label
        in accounts.containsKey('front_a')
            ? ['front_a', 'front_b']
            : ['author', 'reporter']) {
      final account = accounts[label] as Map;
      final session = await auth.login(
        username: account['username'] as String,
        password: account['password'] as String,
        installationId: AuthCrypto.randomEncoded(16),
        idempotencyKey: AuthCrypto.randomEncoded(32),
      );
      tokens.add(session.sessionToken);
    }
    checks.add(step);
    step = 'real_feed_pagination';
    final first = (await posts.timeline(sessionToken: tokens[0])).value;
    require(first.items.isNotEmpty, step);
    if (first.nextCursor != null) {
      final second = (await posts.timeline(
        sessionToken: tokens[0],
        cursor: first.nextCursor,
      )).value;
      require(
        second.items.isNotEmpty &&
            !first.items.any(
              (a) => second.items.any((b) => a.postId == b.postId),
            ),
        step,
      );
    } else {
      require(args[3] == 'cas', step);
      step = 'candidate_feed_single_page';
    }
    checks.add(step);
    final ids = first.items.map((p) => p.postId).toList();
    step = 'batch_comment_context_agreement';
    final batch = (await posts.interactions(
      sessionToken: tokens[0],
      postIds: ids,
    )).value;
    require(batch.length == ids.length, step);
    for (final summary in batch.take(3)) {
      final context = (await comments.send(
        tokens[0],
        'GET',
        '/api/v1/posts/${summary.postId}/comment-context',
      )).value;
      require(context['totalCount'] == summary.commentCount, step);
    }
    checks.add(step);
    step = 'large_interaction_batch';
    final widePage = (await posts.timeline(
      sessionToken: tokens[0],
      limit: 50,
    )).value;
    final wideIds = widePage.items.map((post) => post.postId).toList();
    require(wideIds.length >= 26, step);
    final wideBatch = (await posts.interactions(
      sessionToken: tokens[0],
      postIds: wideIds,
    )).value;
    require(
      jsonEncode({'postIds': wideIds}).length > 1024 &&
          wideBatch.length == wideIds.length &&
          List.generate(
            wideIds.length,
            (i) => i,
          ).every((i) => wideBatch[i].postId == wideIds[i]),
      step,
    );
    checks.add(step);
    step = 'protected_single_and_carousel_bytes';
    final mediaPosts = first.items
        .where((p) => p.imageCount > 0)
        .take(2)
        .toList();
    require(args[3] == 'cas' || mediaPosts.length == 2, step);
    for (final post in mediaPosts) {
      final manifest = (await posts.imageManifest(
        sessionToken: tokens[0],
        postId: post.postId,
      )).value;
      require(manifest.images.length == post.imageCount, step);
      for (final image in manifest.images) {
        final bytes = (await posts.imageBytes(
          sessionToken: tokens[0],
          postId: post.postId,
          image: image,
        )).value;
        require(bytes.length == image.byteLength, step);
      }
    }
    if (mediaPosts.isNotEmpty) checks.add(step);
    if (args[3] == 'cas') {
      final id = ids.first;
      step = 'conditional_write_and_account_flags';
      final original = await posts.postInteractions(
        sessionToken: tokens[0],
        postId: id,
      );
      final liked = await posts.setPostLike(
        sessionToken: tokens[0],
        postId: id,
        liked: !original.value.likedByMe,
        version: original.interactionVersion!,
      );
      final saved = await posts.setPostFavorite(
        sessionToken: tokens[0],
        postId: id,
        favorited: !original.value.favoritedByMe,
        version: liked.interactionVersion!,
      );
      final foreign = (await posts.postInteractions(
        sessionToken: tokens[1],
        postId: id,
      )).value;
      require(
        saved.value.likeCount == foreign.likeCount &&
            saved.value.favoriteCount == foreign.favoriteCount &&
            saved.value.likedByMe != original.value.likedByMe &&
            saved.value.favoritedByMe != original.value.favoritedByMe,
        step,
      );
      checks.add(step);
      step = 'restore_then_reject_late_condition';
      final undoLike = await posts.setPostLike(
        sessionToken: tokens[0],
        postId: id,
        liked: original.value.likedByMe,
        version: saved.interactionVersion!,
      );
      await posts.setPostFavorite(
        sessionToken: tokens[0],
        postId: id,
        favorited: original.value.favoritedByMe,
        version: undoLike.interactionVersion!,
      );
      try {
        await posts.setPostLike(
          sessionToken: tokens[0],
          postId: id,
          liked: !original.value.likedByMe,
          version: original.interactionVersion!,
        );
        throw StateError('late_condition_applied');
      } on PostFailure catch (error) {
        require(
          error.statusCode == 412 &&
              error.code == 'INTERACTION_VERSION_CONFLICT',
          step,
        );
      }
      final finalState = (await posts.postInteractions(
        sessionToken: tokens[0],
        postId: id,
      )).value;
      require(
        finalState.likedByMe == original.value.likedByMe &&
            finalState.favoritedByMe == original.value.favoritedByMe,
        step,
      );
      checks.add(step);
    }
    await File(args[2]).writeAsString(
      jsonEncode({
        'status': 'PASS',
        'mode': args[3],
        'backendSource': manifest['sourceSha'],
        'schema': manifest['schema'],
        'checks': checks,
        'cas': args[3] == 'cas' ? 'PASS' : 'NOT_RUN',
        'media': mediaPosts.isEmpty ? 'NOT_RUN' : 'PASS',
      }),
    );
    stdout.writeln('PASS staging ${args[3]} (${checks.length} checks)');
  } catch (error) {
    await File(args[2]).writeAsString(
      jsonEncode({
        'status': 'FAIL',
        'step': step,
        'kind': error.runtimeType.toString(),
        if (error is AuthFailure) 'category': error.kind.name,
        if (error is AuthFailure) 'code': error.code,
        'checks': checks,
      }),
    );
    stderr.writeln('FAIL staging at $step');
    exitCode = 1;
  } finally {
    auth?.close();
    posts?.close();
    comments?.close();
  }
}
