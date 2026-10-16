import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';
import 'post_storage_test.dart' show TestBusinessVault;

const composerChannel = '11111111-1111-4111-8111-111111111111';
const composerTask = '22222222-2222-4222-8222-222222222222';
const composerPost = '33333333-3333-4333-8333-333333333333';
final composerAt = DateTime.utc(2026, 10, 15);
PostResponse<T> composerReply<T>(T value) => PostResponse(
  value: value,
  serverTime: composerAt,
  sessionExpiresAt: identityTestRenewed,
  requestId: AuthCrypto.encode(List.filled(16, 9)),
  statusCode: 200,
);
PostPickedFile pickedBytes(Uint8List bytes) => PostPickedFile(
  length: () async => bytes.length,
  openRead: () => Stream.value(bytes),
);

class ComposerPicker implements PostPhotoPicker {
  List<PostPickedFile> next = [];
  Completer<List<PostPickedFile>>? wait;
  Completer<void>? lostWait;
  int discarded = 0;
  @override
  Future<List<PostPickedFile>> pick(int limit) async => wait?.future ?? next;
  @override
  Future<void> discardUnboundLostSelection() async {
    discarded++;
    await lostWait?.future;
  }
}

class ComposerApi implements PostApi, PostUploadApi {
  List<PostImageSelection> images = [];
  final receipts = <String, PostCommandResult>{};
  final putIndices = <int>[];
  final received = <int, Uint8List>{};
  final rejected = <int>{};
  final losePutOnce = <int>{};
  PostTaskState state = PostTaskState.accepted;
  int creates = 0, retries = 0, version = 1, uploadQueries = 0;
  bool autoPublish = true, loseCreate = false;
  Completer<void>? createWait, putWait;
  String title = '图片标题', body = '';
  String identity = identityTestId;
  PostTask taskValue() => PostTask(
    taskId: composerTask,
    postId: composerPost,
    channelId: composerChannel,
    identityId: identity,
    attemptVersion: version,
    state: state,
    acceptedAt: composerAt,
    serverSortAt: composerAt,
    visible: state == PostTaskState.accepted || state == PostTaskState.failed,
    terminalAt: state == PostTaskState.accepted ? null : composerAt,
    contentAvailable: state != PostTaskState.cancelled,
    canRetry: state == PostTaskState.failed,
    canCancel: state == PostTaskState.accepted,
    canHide: state == PostTaskState.failed,
    failureCode: state == PostTaskState.failed ? 'PUBLICATION_FAILED' : null,
    content: state == PostTaskState.cancelled
        ? null
        : PostContent(title: title, body: body, imageCount: images.length),
  );
  @override
  Future<PostResponse<PostCommandResult>> createWithImages({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
    required List<PostImageSelection> images,
  }) async {
    creates++;
    this.images = List.of(images);
    this.title = title;
    this.body = body;
    identity = identityId;
    state = PostTaskState.accepted;
    final result = PostCommandResult(
      state: PostCommandState.accepted,
      operation: PostOperation.create,
      taskId: composerTask,
      postId: composerPost,
      attemptVersion: version,
    );
    receipts[commandId] = result;
    if (createWait != null) await createWait!.future;
    if (loseCreate) {
      loseCreate = false;
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return composerReply(result);
  }

  @override
  Future<PostResponse<PostCommandResult>> retryWithImages({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
    required List<PostImageSelection> images,
  }) async {
    retries++;
    version++;
    received.clear();
    this.images = List.of(images);
    this.title = title;
    this.body = body;
    state = PostTaskState.accepted;
    final result = PostCommandResult(
      state: PostCommandState.accepted,
      operation: PostOperation.retry,
      taskId: composerTask,
      postId: composerPost,
      attemptVersion: version,
    );
    receipts[commandId] = result;
    return composerReply(result);
  }

  @override
  Future<PostResponse<PostTask>> task({
    required String sessionToken,
    required String taskId,
  }) async => composerReply(taskValue());
  @override
  Future<PostResponse<PostCommandResult>> commandResult({
    required String sessionToken,
    required String commandId,
  }) async => composerReply(receipts[commandId]!);
  @override
  Future<PostResponse<PostUploadState>> uploads({
    required String sessionToken,
    required String taskId,
    required int version,
  }) async {
    uploadQueries++;
    return composerReply(
      PostUploadState.fromJson(
        {
          'taskId': composerTask,
          'postId': composerPost,
          'attemptVersion': version,
          'items': [
            for (var i = 0; i < images.length; i++)
              {
                ...images[i].toJson(),
                'position': i,
                'uploaded': received.containsKey(i),
              },
          ],
        },
        taskId,
        version,
      ),
    );
  }

  @override
  Future<PostResponse<PostUploadGrant>> uploadGrant({
    required String sessionToken,
    required String taskId,
    required int version,
    required String mediaId,
  }) async => composerReply(
    PostUploadGrant(
      uploadToken: AuthCrypto.encode(List.filled(32, 21)),
      expiresAt: composerAt.add(const Duration(minutes: 10)),
    ),
  );
  @override
  Future<DateTime> putOriginal({
    required String uploadToken,
    required String taskId,
    required int version,
    required PostImageSelection image,
    required Uint8List bytes,
  }) async {
    final index = images.indexWhere((e) => e.mediaId == image.mediaId);
    putIndices.add(index);
    if (putWait != null) await putWait!.future;
    if (rejected.contains(index)) {
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        statusCode: 422,
        code: 'MEDIA_INVALID',
      );
    }
    received[index] = Uint8List.fromList(bytes);
    if (received.length == images.length && autoPublish) {
      state = PostTaskState.published;
    }
    if (losePutOnce.remove(index)) {
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return composerAt;
  }

  @override
  Future<PostResponse<PostCommandResult>> cancel({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  }) async {
    state = PostTaskState.cancelled;
    final value = PostCommandResult(
      state: PostCommandState.committed,
      operation: PostOperation.cancel,
      taskId: composerTask,
      postId: composerPost,
      attemptVersion: version,
      taskState: PostTaskState.cancelled,
    );
    receipts[commandId] = value;
    return composerReply(value);
  }

  @override
  Future<PostResponse<PostDetail>> detail({
    required String sessionToken,
    required String postId,
  }) async => composerReply(
    PostDetail(
      postId: composerPost,
      channelId: composerChannel,
      title: title,
      body: body,
      imageCount: images.length,
      author: const PostAuthor(
        state: PostAuthorState.active,
        avatar: 'default-v1',
        nickname: '测试身份',
      ),
      publishedAt: composerAt,
    ),
  );
  @override
  Future<PostResponse<PostsPage<PostCard>>> feed({
    required String sessionToken,
    required String channelId,
    String? cursor,
    int limit = 20,
  }) async => composerReply(PostsPage(items: [], nextCursor: null));
  @override
  Future<PostResponse<ComposerContext>> composerContext({
    required String sessionToken,
  }) async => composerReply(
    const ComposerContext(
      selectionState: ComposerSelectionState.defaultAvailable,
      defaultIdentityId: identityTestId,
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected synthetic endpoint');
}

class MediaComposerFixture {
  MediaComposerFixture(this.auth, this.root);
  final IdentityTestFixture auth;
  final Directory root;
  final api = ComposerApi();
  final picker = ComposerPicker();
  final vault = TestBusinessVault();
  final stores = <PostStore>[];
  late PostController posts;
  PostStore? current;
  static Future<MediaComposerFixture> create() async {
    final auth = await IdentityTestFixture.create(
      api: IdentityTestApi()..items = [identityTestItem()],
    );
    final value = MediaComposerFixture(
      auth,
      await Directory.systemTemp.createTemp('hnuhole-composer-media-'),
    );
    value.start();
    await value.until(() => value.current != null);
    return value;
  }

  void start() {
    current = null;
    posts = PostController(
      api: api,
      uploadApi: api,
      photoPicker: picker,
      sessions: auth.sessions,
      authStore: auth.store,
      identities: auth.api,
      pollInterval: Duration.zero,
      clock: () => composerAt,
      openStore: (owner) async {
        final store = await PostStore.openFile(
          File('${root.path}/draft.sqlite3'),
          environment: 'https://synthetic.invalid',
          accountId: owner,
          vault: vault,
        );
        stores.add(store);
        current = store;
        return store;
      },
    );
  }

  PostDraftEditor editor() => posts.newDraft(composerChannel)
    ..identityId = identityTestId
    ..title = '图片标题';
  Future<void> until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail('Synthetic fixture timed out');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> restart() async {
    posts.dispose();
    for (final store in stores) {
      await store.close();
    }
    start();
    await until(() => current != null);
  }

  Future<void> close() async {
    posts.dispose();
    for (final store in stores) {
      await store.close();
    }
    auth.dispose();
    await root.delete(recursive: true);
  }
}
