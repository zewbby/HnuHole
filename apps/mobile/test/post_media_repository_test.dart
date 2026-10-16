import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';
import 'post_media_test_support.dart';

final _at = DateTime.utc(2026, 10, 8);
PostResponse<T> _response<T>(T value) => PostResponse(
  value: value,
  serverTime: _at,
  sessionExpiresAt: identityTestRenewed,
  requestId: AuthCrypto.encode(List.filled(16, 3)),
  statusCode: 200,
);

/// Transport/session-store substitutes. These tests do not prove C Gate/SQL or
/// native vault/gallery behavior; the real controller renewal path is exercised.
class _Api implements PostApi, PostMediaApi {
  PostTask? retryTask;
  Map<String, Object?> manifest = mediaManifest();
  Uint8List bytes = Uint8List.fromList(List.filled(8, 1));
  PostFailure? failure;
  Completer<PostResponse<PostMediaManifest>>? manifestWait;
  Completer<PostResponse<Uint8List>>? bytesWait;
  final tokens = <String>[];
  int manifestReads = 0, byteReads = 0;
  @override
  Future<PostResponse<PostTask>> task({
    required String sessionToken,
    required String taskId,
  }) async => _response(retryTask!);
  @override
  Future<PostResponse<PostMediaManifest>> imageManifest({
    required String sessionToken,
    required String postId,
  }) async {
    manifestReads++;
    tokens.add(sessionToken);
    return manifestWait?.future ??
        _response(PostMediaManifest.fromJson(manifest, postId));
  }

  @override
  Future<PostResponse<Uint8List>> imageBytes({
    required String sessionToken,
    required String postId,
    required PostMediaImage image,
  }) async {
    byteReads++;
    tokens.add(sessionToken);
    if (failure != null) throw failure!;
    return bytesWait?.future ?? _response(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected text operation');
}

class _TaskStore implements PostStore {
  @override
  Future<StoredPostEntry> createSubmitted(
    String id,
    StoredPostIntent intent,
    Map<String, dynamic> data, {
    String state = 'submitted',
  }) async => StoredPostEntry(
    id: id,
    revision: 1,
    state: state,
    data: data,
    intents: [intent],
  );
  @override
  Future<StoredPostEntry?> findRetryBuffer(
    String taskId,
    int attemptVersion,
  ) async => null;
  @override
  String get accountId => identityTestAccount;
  @override
  Future<List<StoredPostEntry>> list() async => [];
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected draft write');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IdentityTestFixture auth;
  late PostController posts;
  late PostMediaRepository repository;
  late _Api api;
  setUp(() async {
    auth = await IdentityTestFixture.create();
    api = _Api();
    posts = PostController(
      api: api,
      mediaApi: api,
      sessions: auth.sessions,
      authStore: auth.store,
      identities: auth.api,
      pollInterval: Duration.zero,
      openStore: (_) async => throw const PostStorageFailure(),
    );
    repository = PostMediaRepository(posts);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    repository.dispose();
    posts.dispose();
    auth.dispose();
  });

  test(
    'missing local originals do not silently retry an image task as text',
    () async {
      repository.dispose();
      posts.dispose();
      api.retryTask = PostTask(
        taskId: mediaPostId,
        postId: mediaPostId,
        channelId: mediaOtherId,
        identityId: identityTestId,
        attemptVersion: 1,
        state: PostTaskState.failed,
        acceptedAt: _at,
        serverSortAt: _at,
        terminalAt: _at,
        failureCode: 'PUBLICATION_FAILED',
        visible: true,
        contentAvailable: true,
        canRetry: true,
        canCancel: false,
        canHide: true,
        content: const PostContent(title: '图片', body: '', imageCount: 1),
      );
      posts = PostController(
        api: api,
        mediaApi: api,
        sessions: auth.sessions,
        authStore: auth.store,
        identities: auth.api,
        pollInterval: Duration.zero,
        openStore: (_) async => _TaskStore(),
      );
      repository = PostMediaRepository(posts);
      expect(await posts.editFailedTask(mediaPostId), isNull);
      expect(posts.errorMessage, contains('此设备没有原草稿图片'));
    },
  );

  test('manifest is lazy; preview/full coalesce; saving reauthorizes original bytes', () async {
    final group = await repository.load(mediaPostId);
    expect(api.byteReads, 0);
    expect(auth.store.current!.session!.expiresAt, identityTestRenewed);
    final preview = group.images.single.loadThumbnail!();
    final full = group.images.single.item.loadSource();
    expect(identical(await preview, (await full).provider), isTrue);
    expect(api.byteReads, 1);
    final original = await group.images.single.item.resolveOriginal!();
    expect(original.format, ViewerOriginalFormat.png);
    expect(api.byteReads, 2);
    expect(api.tokens.every((token) => token == identityTestToken), isTrue);
  });

  test(
    'saveAllowed is retained and GIF/WebP originals are not converted',
    () async {
      for (final format in [
        ViewerOriginalFormat.gif,
        ViewerOriginalFormat.webp,
      ]) {
        api.manifest = mediaManifest(mime: 'image/${format.name}', frames: 3);
        final group = await repository.load(mediaPostId);
        expect(
          (await group.images.single.item.resolveOriginal!()).format,
          format,
        );
        group.onRelease!();
      }
      api.manifest = mediaManifest();
      ((api.manifest['images'] as List).single as Map)['saveAllowed'] = false;
      final group = await repository.load(mediaPostId);
      expect(group.images.single.item.saveAllowed, isFalse);
      expect(group.images.single.item.resolveOriginal, isNull);
    },
  );

  test('lease expiry is terminal and rereading creates a new group', () async {
    api.manifest = mediaManifest(lifetime: const Duration(milliseconds: 100));
    final first = await repository.load(mediaPostId);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(first.accessGranted.value, isFalse);
    await expectLater(
      first.images.single.item.loadSource(),
      throwsA(isA<PostFailure>()),
    );
    final second = await repository.load(mediaPostId);
    expect(second.accessGranted.value, isTrue);
    expect(first.accessGranted.value, isFalse);
  });

  test(
    'account replacement rejects a late manifest and never restores old media',
    () async {
      api.manifestWait = Completer();
      final pending = repository.load(mediaPostId);
      final rejected = expectLater(pending, throwsA(isA<PostFailure>()));
      await Future<void>.delayed(Duration.zero);
      await auth.sessions.acceptSession(
        AuthSession(
          accountId: identityTestAccount,
          sessionToken: identityTestOtherToken,
          expiresAt: identityTestExpiry,
        ),
      );
      api.manifestWait!.complete(
        _response(PostMediaManifest.fromJson(mediaManifest(), mediaPostId)),
      );
      await rejected;
      expect(api.byteReads, 0);
    },
  );

  test(
    'release rejects late bytes and queued reads never start after revocation',
    () async {
      api.manifest = mediaManifest(count: 3);
      final group = await repository.load(mediaPostId);
      api.bytesWait = Completer();
      final checks = [
        for (final image in group.images)
          expectLater(image.item.loadSource(), throwsA(isA<PostFailure>())),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(
        api.byteReads,
        2,
      ); // Host byte concurrency is bounded, including saves.
      group.onRelease!();
      api.bytesWait!.complete(_response(api.bytes));
      await Future.wait(checks);
      expect(api.byteReads, 2);
      expect(group.accessGranted.value, isFalse);
    },
  );

  test(
    'transient byte failure can retry within the same valid lease',
    () async {
      final group = await repository.load(mediaPostId);
      api.failure = const PostFailure(kind: PostFailureKind.transport);
      await expectLater(
        group.images.single.item.loadSource(),
        throwsA(isA<PostFailure>()),
      );
      expect(group.accessGranted.value, isTrue);
      api.failure = null;
      await group.images.single.item.loadSource();
      expect(api.byteReads, 2);
    },
  );

  for (final status in [401, 403, 404, 503]) {
    test(
      'protected byte denial $status revokes all groups for that post',
      () async {
        final first = await repository.load(mediaPostId);
        final second = await repository.load(mediaPostId);
        api.failure = PostFailure(
          statusCode: status,
          kind: status == 401
              ? PostFailureKind.unauthorized
              : status == 503
              ? PostFailureKind.unavailable
              : PostFailureKind.rejected,
        );
        await expectLater(
          first.images.single.item.loadSource(),
          throwsA(isA<PostFailure>()),
        );
        expect(first.accessGranted.value, isFalse);
        expect(second.accessGranted.value, isFalse);
        if (status == 401 || status == 503) expect(posts.available, isFalse);
      },
    );
  }

  test(
    'failed durable renewal cannot expose a manifest or start byte reads',
    () async {
      auth.vault.failContaining = identityTestRenewed.toIso8601String();
      await expectLater(
        repository.load(mediaPostId),
        throwsA(isA<PostFailure>()),
      );
      expect(api.byteReads, 0);
    },
  );

  test(
    'revocation evicts only this lease MemoryImage and clears reuse',
    () async {
      api.bytes = await File(
        '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
      ).readAsBytes();
      api.manifest = mediaManifest(
        bytes: api.bytes.length,
        width: 640,
        height: 480,
      );
      final group = await repository.load(mediaPostId);
      final provider = await group.images.single.loadThumbnail!();
      final unrelated = MemoryImage(Uint8List.fromList(api.bytes));
      Future<void> decode(ImageProvider provider) async {
        final done = Completer<void>();
        final stream = provider.resolve(ImageConfiguration.empty);
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (image, sync) {
            image.dispose();
            done.complete();
          },
          onError: (Object error, StackTrace? stack) =>
              done.completeError(error),
        );
        stream.addListener(listener);
        await done.future;
        stream.removeListener(listener);
      }

      await decode(provider);
      await decode(unrelated);
      expect(
        PaintingBinding.instance.imageCache.containsKey(
          await provider.obtainKey(ImageConfiguration.empty),
        ),
        isTrue,
      );
      group.onRelease!();
      await Future<void>.delayed(Duration.zero);
      expect(
        PaintingBinding.instance.imageCache.containsKey(
          await provider.obtainKey(ImageConfiguration.empty),
        ),
        isFalse,
      );
      expect(
        PaintingBinding.instance.imageCache.containsKey(unrelated),
        isTrue,
      );
      await unrelated.evict();
    },
  );
}
