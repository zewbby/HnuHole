import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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

  testWidgets(
    'two repost rows and their detail reauthorize once at the shared deadline',
    (tester) async {
      Future<void> frames() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      api.bytes = (await tester.runAsync(
        () => File(
          '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
        ).readAsBytes(),
      ))!;
      api.manifest = mediaManifest(
        bytes: api.bytes.length,
        width: 640,
        height: 480,
      );
      final groups = <PostImages>[];
      Future<PostImages> load(String id) async {
        final group = await repository.load(id);
        groups.add(group);
        return group;
      }

      Widget section(String key, {bool preview = true}) => PostImagesSection(
        key: ValueKey(key),
        postId: mediaPostId,
        expectedCount: 1,
        loadImages: load,
        authority: posts,
        isCurrent: () => posts.available,
        feedPreview: preview,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('原帖详情')),
                          body: section('detail', preview: false),
                        ),
                      ),
                    ),
                    child: const Text('打开原帖详情'),
                  ),
                  Expanded(
                    child: SizedBox(
                      width: 280,
                      child: section('repost-identity-a'),
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      width: 280,
                      child: section('repost-identity-b'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await frames();
      await tester.pumpAndSettle();
      expect(api.manifestReads, 1);
      expect(groups.length, 2);
      await tester.pump(const Duration(seconds: 58));
      await tester.tap(find.text('打开原帖详情'));
      await frames();
      await tester.pumpAndSettle();
      expect(api.manifestReads, 1);
      expect(groups.length, 3);
      final old = groups.toList();
      await tester.pump(const Duration(seconds: 3));
      await frames();
      await tester.pumpAndSettle();
      expect(api.manifestReads, 2);
      expect(groups.length, 6);
      expect(old.every((group) => !group.accessGranted.value), isTrue);
      expect(
        groups.skip(3).every((group) => group.accessGranted.value),
        isTrue,
      );
      expect(find.text('图片已不可访问'), findsNothing);
      expect(find.byKey(const ValueKey('post-image-grid')), findsOneWidget);
      await tester.pageBack();
      await frames();
      await tester.pumpAndSettle();
      expect(find.text('图片已不可访问'), findsNothing);
      expect(find.byType(Image), findsNWidgets(2));
      expect(api.manifestReads, 2);
      expect(api.byteReads, 2);
      await tester.pumpWidget(const SizedBox());
      repository.dispose();
    },
  );

  test('explicit thumbnail retry refetches cached bytes and preserves the lease deadline', () async {
    final group = await repository.load(mediaPostId);
    final first = await group.images.single.loadThumbnail!();
    group.images.single.registerDecodeProvider!(
      ResizeImage(first, width: 64, height: 64, policy: ResizeImagePolicy.fit),
    );
    final second = await group.images.single.retryThumbnail!();
    expect(identical(first, second), isFalse);
    expect(api.byteReads, 2);
    expect(api.manifestReads, 1);
    expect(group.accessGranted.value, isTrue);
    group.onRelease!();
    expect(repository.idleBytes, greaterThanOrEqualTo(0));
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

  test('concurrent consumers share manifest and bytes; release does not revoke another consumer', () async {
    api.manifestWait = Completer();
    final one = repository.load(mediaPostId),
        two = repository.load(mediaPostId);
    await Future<void>.delayed(Duration.zero);
    expect(api.manifestReads, 1);
    api.manifestWait!.complete(
      _response(PostMediaManifest.fromJson(api.manifest, mediaPostId)),
    );
    final first = await one, second = await two;
    final firstImage = await first.images.single.loadThumbnail!();
    first.onRelease!();
    expect(first.accessGranted.value, isFalse);
    expect(first.isExpired!(), isFalse);
    expect(second.accessGranted.value, isTrue);
    expect(
      identical(await second.images.single.loadThumbnail!(), firstImage),
      isTrue,
    );
    second.onRelease!();
    expect(repository.idleGroupCount, 1);
    final third = await repository.load(mediaPostId);
    expect(
      identical(await third.images.single.loadThumbnail!(), firstImage),
      isTrue,
    );
    expect(api.manifestReads, 1);
    expect(api.byteReads, 1);
    third.onRelease!();
    third.onRelease!();
    expect(repository.idleGroupCount, 1);
  });

  test('a released consumer cannot receive late shared bytes held by another consumer', () async {
    final first = await repository.load(mediaPostId);
    final second = await repository.load(mediaPostId);
    api.bytesWait = Completer();
    final rejected = expectLater(
      first.images.single.loadThumbnail!(),
      throwsA(isA<PostFailure>()),
    );
    final active = second.images.single.loadThumbnail!();
    await Future<void>.delayed(Duration.zero);
    first.onRelease!();
    api.bytesWait!.complete(_response(api.bytes));
    await rejected;
    expect(await active, isA<MemoryImage>());
    expect(api.byteReads, 1);
    expect(second.accessGranted.value, isTrue);
  });

  test('LRU evicts idle posts and byte budget prevents retaining oversized entries', () async {
    repository.dispose();
    repository = PostMediaRepository(posts, maxIdleEntries: 1);
    final first = await repository.load(mediaPostId);
    await first.images.single.loadThumbnail!();
    first.onRelease!();
    api.manifest = mediaManifest(postId: mediaOtherId);
    final second = await repository.load(mediaOtherId);
    await second.images.single.loadThumbnail!();
    second.onRelease!();
    expect(repository.idleGroupCount, 1);
    api.manifest = mediaManifest();
    final third = await repository.load(mediaPostId);
    expect(api.manifestReads, 3);
    third.onRelease!();
    repository.dispose();
    repository = PostMediaRepository(posts, maxIdleBytes: 1);
    final large = await repository.load(mediaPostId);
    await large.images.single.loadThumbnail!();
    large.onRelease!();
    expect(repository.idleBytes, 0);
    expect(repository.idleGroupCount, 0);
  });

  test(
    'idle cache is cleared immediately when the account loses authority',
    () async {
      final group = await repository.load(mediaPostId);
      await group.images.single.loadThumbnail!();
      group.onRelease!();
      expect(repository.idleGroupCount, 1);
      await auth.sessions.logout();
      expect(repository.idleGroupCount, 0);
      await expectLater(
        repository.load(mediaPostId),
        throwsA(isA<PostFailure>()),
      );
    },
  );

  test(
    'negotiated preview is separate from full image and original save',
    () async {
      final row = (api.manifest['images'] as List).single as Map;
      row['thumbnail'] = {
        'path': (row['original'] as Map)['path'].toString().replaceFirst(
          '/original',
          '/thumbnail',
        ),
        'mimeType': 'image/webp',
        'maxByteLength': 512 * 1024,
      };
      final group = await repository.load(mediaPostId);
      final preview = await group.images.single.loadThumbnail!();
      final full = await group.images.single.item.loadSource();
      expect(identical(preview, full.provider), isFalse);
      expect(api.byteReads, 2);
      await group.images.single.item.resolveOriginal!();
      expect(api.byteReads, 3);
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
        expect(group.images.single.animated, isTrue);
        expect(
          (await group.images.single.item.resolveOriginal!()).format,
          format,
        );
        group.onRelease!();
        repository.dispose();
        repository = PostMediaRepository(posts);
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
    expect(first.isExpired!(), isTrue);
    await expectLater(
      first.images.single.item.loadSource(),
      throwsA(isA<PostFailure>()),
    );
    final second = await repository.load(mediaPostId);
    expect(second.accessGranted.value, isTrue);
    expect(first.accessGranted.value, isFalse);
  });

  test(
    'reusing an idle group never extends its original authorization deadline',
    () async {
      api.manifest = mediaManifest(lifetime: const Duration(milliseconds: 150));
      final first = await repository.load(mediaPostId);
      await first.images.single.loadThumbnail!();
      first.onRelease!();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      final second = await repository.load(mediaPostId);
      expect(api.manifestReads, 1);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(second.accessGranted.value, isFalse);
      final third = await repository.load(mediaPostId);
      expect(api.manifestReads, 2);
      expect(third.accessGranted.value, isTrue);
    },
  );

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
    for (final changedAccount in [true, false]) {
      test(
        'late media denial $status after ${changedAccount ? 'account change' : 'release'} cannot cross its lease',
        () async {
          final old = await repository.load(mediaPostId);
          final delayed = Completer<PostResponse<Uint8List>>();
          api.bytesWait = delayed;
          final oldRead = expectLater(
            old.images.single.item.loadSource(),
            throwsA(isA<PostFailure>()),
          );
          await Future<void>.delayed(Duration.zero);
          expect(api.byteReads, 1);
          api.bytesWait = null;
          if (changedAccount) {
            auth.sessionApi.account = '00000000-0000-0000-0000-000000000002';
            await auth.sessions.login('synthetic-b', 'synthetic-password');
          } else {
            old.onRelease!();
          }
          final fresh = await repository.load(mediaPostId);
          expect(fresh.accessGranted.value, isTrue);
          delayed.completeError(
            PostFailure(
              statusCode: status,
              kind: status == 401
                  ? PostFailureKind.unauthorized
                  : status == 503
                  ? PostFailureKind.unavailable
                  : PostFailureKind.rejected,
            ),
          );
          await oldRead;
          final stillAuthorized =
              changedAccount || !{401, 503}.contains(status);
          expect(old.accessGranted.value, isFalse);
          expect(posts.available, stillAuthorized);
          expect(fresh.accessGranted.value, stillAuthorized);
          if (stillAuthorized) {
            await fresh.images.single.item.loadSource();
            expect(fresh.accessGranted.value, isTrue);
          }
        },
      );
    }
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
        expect(first.isExpired!(), isFalse);
        expect(second.isExpired!(), isFalse);
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

  test('repository revocation evicts only its protected MemoryImage and resized keys', () async {
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
    final resized = ResizeImage(
      provider,
      width: 160,
      height: 120,
      policy: ResizeImagePolicy.fit,
    );
    group.images.single.registerDecodeProvider!(resized);
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
        onError: (Object error, StackTrace? stack) => done.completeError(error),
      );
      stream.addListener(listener);
      await done.future;
      stream.removeListener(listener);
    }

    await decode(provider);
    await decode(resized);
    await decode(unrelated);
    expect(
      PaintingBinding.instance.imageCache.containsKey(
        await provider.obtainKey(ImageConfiguration.empty),
      ),
      isTrue,
    );
    expect(
      PaintingBinding.instance.imageCache.containsKey(
        await resized.obtainKey(ImageConfiguration.empty),
      ),
      isTrue,
    );
    repository.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(
      PaintingBinding.instance.imageCache.containsKey(
        await provider.obtainKey(ImageConfiguration.empty),
      ),
      isFalse,
    );
    expect(
      PaintingBinding.instance.imageCache.containsKey(
        await resized.obtainKey(ImageConfiguration.empty),
      ),
      isFalse,
    );
    expect(PaintingBinding.instance.imageCache.containsKey(unrelated), isTrue);
    await unrelated.evict();
  });
}
