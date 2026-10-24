// Opt-in independent .ratelimit APK. Every API request uses real TLS, shared
// Redis admission and final SQL/Gate; all journals use the native Keystore and
// encrypted SQLite. Session capabilities come only from an app-private fixture.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/comments/comment_editor.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_journal.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/comments/comment_runtime.dart';
import 'package:hnuhole_mobile/src/comments/comment_views.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';

const _driver = MethodChannel('hnuhole/owned_device_driver');
const _postBody = '真机原文\r\ne\u0301，等待后只手动发布。';
void _check(bool ok, String label) {
  if (!ok) throw StateError(label);
}

Future<void> _until(
  Future<bool> Function() condition,
  String label, {
  int seconds = 35,
}) async {
  final until = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(until)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(label);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final lab = _DeviceLab();
  runApp(_DeviceApp(lab));
  String phase = 'rate-start';
  try {
    phase = (await _driver.invokeMethod<String>('phase'))!;
    _check(
      {'rate-write', 'rate-read', 'rate-unknown', 'rate-fault'}.contains(phase),
      'explicit-phase',
    );
    await lab.initialize(phase);
    await lab.exercise(phase);
    await lab.report(phase, true);
    await _driver.invokeMethod('stage', 'pass-$phase');
  } catch (error) {
    lab.status = error is StateError
        ? '断言未通过（${lab.initializationStage}）：${error.message}'
        : '验收未完成（${lab.initializationStage}）：${error.runtimeType}';
    lab.changed();
    await lab.report(phase, false);
    await _driver.invokeMethod(
      'stage',
      'fail-$phase-${error.runtimeType.toString().toLowerCase()}',
    );
  }
}

class _DeviceLab extends ChangeNotifier {
  String status = '正在打开本包私有夹具与原生加密存储';
  String page = 'chat';
  late Directory files;
  late Map<String, dynamic> f;
  Map<String, dynamic> saved = {};
  late FlutterAuthVault stateVault;
  late AuthStore authStore;
  late AuthSessionController sessions;
  late HttpAuthApi auth;
  late HttpPostUploadApi postApi;
  late PostController posts;
  late NativeCommentJournal journal;
  late CommentRuntime comments;
  late DmController dm;
  late DmStore dmStore;
  late SecurityContext trust;
  late Future<PostStore> postDb;
  final flags = <String, bool>{};
  final diagnostics = <String, Object>{};
  List<Map<String, dynamic>> rows = [];
  bool initialized = false, _refreshing = false, _reportDirectoryReady = false;
  String initializationStage = 'native-locator';
  String get account => f['accountId'] as String;
  String get token => f['token'] as String;
  String get own => f['identityId'] as String;
  String get peer => f['peerId'] as String;
  String get environment => 'shared-rate-device.${f['run']}';
  HttpClient client() =>
      HttpClient(context: trust)
        ..connectionTimeout = const Duration(seconds: 20);
  void changed() => notifyListeners();

  Future<void> initialize(String phase) async {
    final locator = DurableBusinessVault(
      hashes.sha256
          .convert(utf8.encode('shared.rate.device.locator'))
          .toString(),
    );
    files = File(await locator.databasePath()).parent;
    _reportDirectoryReady = true;
    initializationStage = 'private-fixture';
    f = Map<String, dynamic>.from(
      jsonDecode(
        await File('${files.path}/shared-rate-fixture.json').readAsString(),
      ),
    );
    initializationStage = 'tls-ca';
    trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(f['certificatePem'] as String));
    initializationStage = 'native-state';
    stateVault = FlutterAuthVault(namespace: '$environment.state');
    final before = await stateVault.read();
    saved = before == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(before));
    if (phase != 'rate-write') {
      _check(
        saved['writePid'] is int && saved['writePid'] != pid,
        'actual-process-restart',
      );
    }
    initializationStage = 'api-origins';
    final origin = Uri.parse(f['url'] as String);
    auth = HttpAuthApi(
      communityBaseUri: origin,
      verifierBaseUri: Uri.parse(f['verifier'] as String),
      client: client(),
    );
    authStore = AuthStore(
      FlutterAuthVault(namespace: '$environment.auth'),
      scope: environment,
    );
    final directory = ChannelDirectoryController(
      repository: HttpChannelRepository(baseUri: origin, client: client()),
    );
    sessions = AuthSessionController(
      api: auth,
      store: authStore,
      directory: directory,
    );
    initializationStage = 'native-session';
    await sessions.start();
    if (phase == 'rate-write') {
      _check(
        authStore.current?.session == null,
        'independent-package-fresh-auth',
      );
      await sessions.acceptSession(
        AuthSession(
          accountId: account,
          sessionToken: token,
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
    }
    _check(
      sessions.isAuthenticated &&
          authStore.current?.session?.accountId == account,
      'native-authorized-scope',
    );
    initializationStage = 'business-controllers';
    final identities = IdentityManagementController(
      api: auth,
      store: authStore,
      sessions: sessions,
    );
    postDb = PostStore.openNative(
      environment: '$environment.posts',
      accountId: account,
    );
    postApi = HttpPostUploadApi(communityBaseUri: origin, client: client());
    posts = PostController(
      api: postApi,
      mediaApi: postApi,
      uploadApi: postApi,
      sessions: sessions,
      authStore: authStore,
      identities: auth,
      openStore: (_) => postDb,
      pollInterval: const Duration(seconds: 2),
    );
    journal = NativeCommentJournal(
      (a) => PostStore.openNative(
        environment: '$environment.comments',
        accountId: a,
      ),
    );
    comments = CommentRuntime(
      http: CommentHttp(origin, client: client()),
      sessions: sessions,
      authStore: authStore,
      identities: auth,
      identityManagement: identities,
      journal: journal,
    );
    initializationStage = 'controllers-ready';
    await _until(
      () async => comments.core.ready && posts.available,
      'real-controllers-ready',
    );
    initializationStage = 'native-dm';
    await openDm();
    initialized = true;
    initializationStage = 'ready';
    posts.addListener(changed);
    comments.addListener(changed);
    status = '真实 TLS／共享额度／原生加密数据库已连接';
    changed();
  }

  Future<void> openDm() async {
    dm = DmController(
      api: postApi,
      chatEnabled: true,
      openStore: (a) async =>
          dmStore = await DmStore.openNative('$environment.dm', a),
    );
    dm.addListener(refreshRows);
    await dm.bind(
      account: account,
      token: token,
      identities: [own, f['alternateIdentityId'] as String],
      isCurrent: () => sessions.isCurrentToken(token),
    );
    await refreshRows();
  }

  Future<void> refreshRows() async {
    if (_refreshing || !dm.available) return;
    _refreshing = true;
    try {
      rows = await dm.history(own, peer);
    } finally {
      _refreshing = false;
    }
    changed();
  }

  Future<void> persist() => stateVault.write(jsonEncode(saved));
  Future<Map<String, dynamic>> control(String path) async {
    final h = client();
    try {
      final request = await h.postUrl(Uri.parse('${f['control']}$path'));
      request.headers.set(
        'Authorization',
        'SharedRateLab ${f['controlToken']}',
      );
      final response = await request.close();
      final raw = await utf8.decoder.bind(response).join();
      _check(
        response.statusCode == 200,
        'private-control-${path.substring(1)}',
      );
      return Map<String, dynamic>.from(jsonDecode(raw));
    } finally {
      h.close(force: true);
    }
  }

  Map<String, Object> intent(String text, {bool other = false}) => {
    'identityId': own,
    'peerId': other ? f['thirdId'] as String : peer,
    'conversationId': other
        ? f['otherConversationId'] as String
        : f['conversationId'] as String,
    'sourcePostId': '',
    'sourceCommentId': '',
    'text': text,
    'attempt': 1,
  };
  Future<void> exercise(String phase) async {
    switch (phase) {
      case 'rate-write':
        await write();
      case 'rate-read':
        await read();
      case 'rate-unknown':
        await unknown();
      case 'rate-fault':
        await fault();
    }
  }

  Future<void> write() async {
    final db = await postDb;
    _check(
      (await db.list()).isEmpty && (await journal.read(account)).isEmpty,
      'fresh-business-scope',
    );
    // Prepare committed native work while no sender timer owns this store.
    // Rebinding below starts the real controller immediately after quota prime.
    await dm.detach();
    dmStore = await DmStore.openNative('$environment.dm', account);
    await dmStore.reconcileIdentities([
      own,
      f['alternateIdentityId'] as String,
    ]);
    await control('/prime-post');
    final draftId = AuthCrypto.randomEncoded(16), blob = dmId();
    final selection = PostImageSelection.fromJson(f['image']);
    final draft = DraftPostImage(
      blobId: blob,
      mediaId: selection.mediaId,
      selection: selection,
    );
    await db.saveMediaDraft(
      draftId,
      null,
      {
        'channelId': f['channelId'],
        'identityId': f['alternateIdentityId'],
        'title': '限流后保留原发帖草稿',
        'body': _postBody,
        'images': [draft.toJson()],
      },
      {blob: Uint8List.fromList(base64Decode(f['imageBytes'] as String))},
    );
    final editor = await posts.restoreDraft(draftId);
    _check(
      editor != null && await posts.publish(editor),
      'native-post-intent-journaled',
    );
    await _until(
      () async => (await db.get(draftId))?.data['rateLimitWait'] is Map,
      'real-post429',
    );
    var entry = (await db.get(draftId))!;
    _check(
      entry.data['identityId'] == f['alternateIdentityId'] &&
          entry.data['channelId'] == f['channelId'] &&
          entry.intents.length == 1 &&
          entry.data['body'] == _postBody &&
          entry.intents.single.payload['body'] == _postBody,
      'post-full-binding-original-key',
    );
    _check(
      (await db.readMedia(
            blob,
            selection.byteLength,
            selection.sha256,
          )).length ==
          selection.byteLength,
      'post-image-original-durable',
    );
    saved.addAll({
      'postDraft': draftId,
      'postCommand': entry.intents.single.commandId,
      'postBlob': blob,
    });
    flags['post429CompleteDraft'] = true;
    await control('/prime-comment');
    final image = CommentImage(blobId: dmId(), selection: selection);
    journal.staged[image.blobId] = Uint8List.fromList(
      base64Decode(f['imageBytes'] as String),
    );
    final commentId = commentUUID(), key = commentKey();
    await comments.core.submit(
      taskId: commentId,
      commandId: key,
      binding: CommentBinding(
        postId: f['postId'] as String,
        identityId: own,
        rootCommentId: f['rootCommentId'] as String,
        targetCommentId: f['targetCommentId'] as String,
      ),
      content: CommentContent(body: '评论原文与原图持久保存', image: image),
    );
    final comment = comments.core.entries.single;
    _check(
      comment.rateLimitWait != null &&
          comment.intent.commandId == key &&
          comment.intent.binding.identityId == own &&
          comment.intent.binding.postId == f['postId'] &&
          comment.intent.binding.rootCommentId == f['rootCommentId'] &&
          comment.intent.binding.targetCommentId == f['targetCommentId'],
      'comment429-full-binding',
    );
    _check(
      (await journal.bytes(account, image)).length == selection.byteLength,
      'comment-image-original-durable',
    );
    saved.addAll({'commentTask': commentId, 'commentCommand': key});
    flags['comment429CompleteDraft'] = true;
    final enqueueClock = Stopwatch()..start();
    final first = await dmStore.enqueue(intent('第一条：限流后沿用原命令'));
    final second = await dmStore.enqueue(intent('第二条：同会话必须保序'));
    final cancel = await dmStore.enqueue(intent('尚未提交，确定取消'));
    final independent = await dmStore.enqueue(intent('独立会话同账号等待', other: true));
    await dmStore.hideMessage(cancel);
    diagnostics['dmNativeEnqueueCancelMillis'] =
        enqueueClock.elapsedMilliseconds;
    await dmStore.close();
    await control('/incoming');
    await control('/prime-dm');
    final beforeDm = await control('/stats');
    final primeClock = Stopwatch()..start();
    await openDm();
    diagnostics['dmPrimeToBindSyncMillis'] = primeClock.elapsedMilliseconds;
    final dmEvidence = await control('/stats');
    diagnostics['dmPrimeAgeMillis'] = dmEvidence['dmPrimeAgeMillis'] as int;
    diagnostics['dmCallsAtFirstCheck'] = dmEvidence['dmCalls'] as int;
    diagnostics['dmSentAtFirstCheck'] = dmEvidence['dmSent'] as int;
    diagnostics['dmQuotaWindowSeconds'] = f['windowSeconds'] as int;
    diagnostics['dm429ResponsesAtFirstCheck'] =
        dmEvidence['dm429Responses'] as int;
    _check(
      (dmEvidence['dm429Responses'] as int) >
          (beforeDm['dm429Responses'] as int),
      'actual-public-dm-http429-observed',
    );
    final firstReceipt = (await postApi.dmRequest(
      token,
      'GET',
      'commands/$first',
    )).value;
    _check(
      firstReceipt['state'] == 'ABSENT',
      'rate-limited-first-key-not-accepted',
    );
    _check(
      await dmStore.cooldown('send') != null,
      'real-dm429-persistent-cooldown',
    );
    _check(
      (await dm.message(first))?['_state'] == 'unknown' &&
          (await dm.message(second))?['_state'] == 'queued',
      'dm-original-order-held',
    );
    _check(
      (await dm.message(cancel))?['_state'] == 'deleted',
      'queued-cancel-definite',
    );
    final stats = await control('/stats');
    _check(stats['pendingIncoming'] == 0, 'dm429-receive-ack-continues');
    flags['dm429KeepsOrderAndAck'] = true;
    final cancelled = (await postApi.dmRequest(
      token,
      'GET',
      'commands/$cancel',
    )).value;
    _check(cancelled['state'] == 'ABSENT', 'queued-cancel-server-absent');
    flags['queuedCancel'] = true;
    saved.addAll({
      'dmFirst': first,
      'dmSecond': second,
      'dmOther': independent,
      'dmCancelled': cancel,
      'writePid': pid,
      'beforeManual': stats,
    });
    await persist();
    final isolated = await DmStore.openNative(
      '$environment.dm',
      f['peerAccountId'] as String,
    );
    _check((await isolated.work()).isEmpty, 'native-account-isolation');
    await isolated.close();
    flags['nativeAccountIsolation'] = true;
    await refreshRows();
    // End this write window cleanly after FULL commits; the host then force-
    // stops the actual process and launches the read phase with a different PID.
    await dm.detach();
    status = '原生写入阶段完成：原稿与原键已保存，私信等待中；现在重启测试包。';
    changed();
  }

  Future<void> read() async {
    final db = await postDb;
    final before = (await db.get(saved['postDraft'] as String))!;
    final comment = (await journal.read(account)).single;
    _check(
      before.data['rateLimitWait'] is Map &&
          before.intents.single.commandId == saved['postCommand'] &&
          comment.rateLimitWait != null &&
          comment.intent.commandId == saved['commentCommand'],
      'restart-restores-original-drafts-and-wait',
    );
    _check(
      before.data['identityId'] == f['alternateIdentityId'] &&
          comment.content?.image != null,
      'restart-retains-identity-media',
    );
    final stats = await control('/stats');
    final baseline = Map<String, dynamic>.from(saved['beforeManual'] as Map);
    _check(
      stats['postTasks'] == baseline['postTasks'] &&
          stats['commentTasks'] == baseline['commentTasks'],
      'restart-does-not-auto-publish',
    );
    flags['differentPidNativeRestore'] = true;
    await _until(
      () async =>
          posts.rateLimitedSeconds(saved['postDraft'] as String) == 0 &&
          comments.core.rateLimitedSeconds(comments.core.entries.single) == 0,
      'wait-expiry',
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    final afterExpiry = await control('/stats');
    _check(
      afterExpiry['postTasks'] == baseline['postTasks'] &&
          afterExpiry['commentTasks'] == baseline['commentTasks'] &&
          afterExpiry['postCalls'] == baseline['postCalls'] &&
          afterExpiry['commentCalls'] == baseline['commentCalls'],
      'expired-poll-does-not-auto-publish',
    );
    flags['noAutomaticPostComment'] = true;
    await posts.retryRateLimited(saved['postDraft'] as String);
    await comments.core.retryRateLimited(saved['commentTask'] as String);
    final after = (await db.get(saved['postDraft'] as String))!;
    _check(
      after.intents.length == 1 &&
          after.intents.single.commandId == saved['postCommand'] &&
          after.data['rateLimitWait'] == null,
      'post-manual-original-key',
    );
    _check(
      comments.core.entries.single.intent.commandId ==
              saved['commentCommand'] &&
          comments.core.entries.single.rateLimitWait == null,
      'comment-manual-original-key',
    );
    final postReceipt = (await postApi.commandResult(
      sessionToken: token,
      commandId: saved['postCommand'] as String,
    )).value;
    _check(
      postReceipt.state == PostCommandState.accepted &&
          postReceipt.taskId == after.data['taskId'],
      'real-original-post-receipt-accepted',
    );
    final commentTask = await comments.api.query(
      comments.core.entries.single.intent.withoutContent(),
    );
    _check(
      commentTask != null &&
          {
            CommentTaskState.accepted,
            CommentTaskState.published,
          }.contains(commentTask.state) &&
          commentTask.taskId == saved['commentTask'],
      'real-original-comment-receipt-accepted',
    );
    Map<String, dynamic> originalRecord(
      Map<String, dynamic> stats,
      String list,
      String id,
    ) => Map<String, dynamic>.from(
      (stats[list] as List).singleWhere((r) => r['taskId'] == id) as Map,
    );
    final expectedImage = PostImageSelection.fromJson(f['image']);
    await _until(() async {
      final evidence = await control('/stats');
      final records = (evidence['postRecords'] as List).where(
        (r) => r['taskId'] == after.data['taskId'],
      );
      return records.length == 1 && (records.single['imageBytes'] as int) > 0;
    }, 'post-original-image-actually-uploaded');
    final acceptedEvidence = await control('/stats');
    _check(
      acceptedEvidence['postTasks'] == (baseline['postTasks'] as int) + 1 &&
          acceptedEvidence['commentTasks'] ==
              (baseline['commentTasks'] as int) + 1,
      'sql-exactly-one-original-task-each',
    );
    final actualPost = originalRecord(
          acceptedEvidence,
          'postRecords',
          after.data['taskId'] as String,
        ),
        actualComment = originalRecord(
          acceptedEvidence,
          'commentRecords',
          saved['commentTask'] as String,
        );
    final postBodyHash = hashes.sha256
            .convert(utf8.encode(_postBody))
            .toString(),
        commentBodyHash = hashes.sha256
            .convert(utf8.encode('评论原文与原图持久保存'))
            .toString();
    _check(
      {'ACCEPTED', 'PUBLISHED'}.contains(actualPost['state']) &&
          actualPost['identityId'] == f['alternateIdentityId'] &&
          actualPost['channelId'] == f['channelId'] &&
          actualPost['titleHash'] ==
              hashes.sha256.convert(utf8.encode('限流后保留原发帖草稿')).toString() &&
          actualPost['bodyHash'] == postBodyHash &&
          actualPost['imageHash'] == expectedImage.sha256 &&
          actualPost['imageBytes'] == expectedImage.byteLength,
      'sql-post-original-content-binding-and-image',
    );
    _check(
      {'ACCEPTED', 'PUBLISHED'}.contains(actualComment['state']) &&
          actualComment['identityId'] == own &&
          actualComment['postId'] == f['postId'] &&
          actualComment['rootCommentId'] == f['rootCommentId'] &&
          actualComment['targetCommentId'] == f['targetCommentId'] &&
          actualComment['bodyHash'] == commentBodyHash &&
          actualComment['imageHash'] == expectedImage.sha256 &&
          actualComment['imageBytes'] == expectedImage.byteLength,
      'sql-comment-original-target-body-and-image',
    );
    flags['manualRetrySameOriginalKeys'] = true;
    await _until(
      () async {
        await dm.sync();
        return (await dm.message(saved['dmFirst'] as String))?['_state'] ==
                'sent' &&
            (await dm.message(saved['dmSecond'] as String))?['_state'] ==
                'sent' &&
            (await dm.message(saved['dmOther'] as String))?['_state'] == 'sent';
      },
      'persistent-dm-auto-order',
      seconds: 50,
    );
    final first = await dm.message(saved['dmFirst'] as String),
        second = await dm.message(saved['dmSecond'] as String);
    _check(
      (first?['receipt']?['sequence'] as int) <
          (second?['receipt']?['sequence'] as int),
      'same-conversation-monotonic-sequence',
    );
    _check(
      (await dm.message(saved['dmCancelled'] as String))?['_state'] ==
          'deleted',
      'cancelled-never-replayed',
    );
    final cancelledAgain = (await postApi.dmRequest(
      token,
      'GET',
      'commands/${saved['dmCancelled']}',
    )).value;
    _check(
      cancelledAgain['state'] == 'ABSENT',
      'cancelled-stays-absent-after-all-queue-work',
    );
    flags['dmPersistentAutomaticSameIdsAndOrder'] = true;
    await control('/publish');
    await refreshRows();
    status = '不同进程原生恢复通过：发帖评论手动原键重试，私信到期原键自动保序。';
    changed();
  }

  Future<void> unknown() async {
    await Future<void>.delayed(const Duration(seconds: 13));
    await control('/capture-next');
    await control('/block-close');
    final id = await dmStore.enqueue(intent('丢失于准入前的原请求，隐藏后不得重发正文'));
    await dm.sync();
    _check(
      (await dm.message(id))?['_state'] == 'unknown' &&
          (await control('/stats'))['captured'] == true,
      'actual-network-unknown',
    );
    await dm.deleteLocal(id);
    final blocked = await dmStore.enqueue(intent('未知前项后续不得越过'));
    final independent = await dmStore.enqueue(intent('另一会话可以继续', other: true));
    await control('/incoming');
    await dm.sync();
    _check(
      (await dm.message(id))?['_state'] == 'unknown' &&
          (await dm.message(blocked))?['_state'] == 'queued',
      'hidden-unknown-blocks-same-pair',
    );
    _check(
      (await dm.message(independent))?['_state'] == 'sent',
      'independent-pair-progresses',
    );
    _check(
      (await control('/stats'))['pendingIncoming'] == 0,
      'hidden-unknown-does-not-block-ack',
    );
    await control('/allow-close');
    await dm.sync();
    _check(
      (await dm.message(id))?['_state'] == 'deleted',
      'authoritative-close-releases-hidden',
    );
    await control('/release-late');
    _check(
      (await control('/stats'))['lateCode'] == 'COMMAND_CLOSED',
      'real-late-put-cannot-revive-closed',
    );
    flags['unknownCloseAndLatePut'] = true;
    flags['independentPairAndAck'] = true;
    await _until(
      () async {
        await dm.sync();
        return (await dm.message(blocked))?['_state'] == 'sent';
      },
      'same-pair-unblocks-after-close',
      seconds: 30,
    );
    status = '原结果未知已可靠关闭；迟到原请求未复活，独立会话与ACK继续。';
    changed();
  }

  Future<void> fault() async {
    await Future<void>.delayed(const Duration(seconds: 13));
    await control('/incoming');
    final beforeFault = await control('/stats');
    await control('/redis-pause');
    final id = await dmStore.enqueue(intent('Redis真实暂停期间保留的原命令'));
    await dm.sync();
    _check(
      dm.available &&
          (await dm.message(id))?['_state'] == 'unknown' &&
          await dmStore.cooldown('send') != null,
      'real-redis503-preserves-window-and-original',
    );
    final faultEvidence = await control('/stats');
    diagnostics['dm503ResponsesAtFault'] =
        faultEvidence['dm503Responses'] as int;
    _check(
      (faultEvidence['dm503Responses'] as int) >
          (beforeFault['dm503Responses'] as int),
      'actual-public-dm-http503-observed',
    );
    _check(
      faultEvidence['pendingIncoming'] == 0,
      'real-redis503-keeps-read-ack',
    );
    await _until(
      () async {
        await dm.sync();
        return (await dm.message(id))?['_state'] == 'sent';
      },
      'redis-recovery-original-auto-retry',
      seconds: 30,
    );
    flags['realRedisFaultAndRecovery'] = true;
    status = '真实 Redis 故障恢复通过：保留窗口、继续收件ACK、原命令恢复发送。';
    changed();
  }

  Future<void> report(String phase, bool passed) async {
    if (!_reportDirectoryReady) return;
    final data = {
      'initializationStage': initializationStage,
      'status': passed ? 'PASS' : 'FAIL',
      'phase': phase,
      'pid': pid,
      'writePid': saved['writePid'],
      'checks': flags,
      'diagnostics': diagnostics,
      'assertion': status,
    };
    final file = File('${files.path}/shared-rate-report-$phase.json');
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Widget chat() {
    final messages = rows.map((r) {
      final outgoing = r['outgoing'] == true;
      final content = outgoing
          ? Map<String, dynamic>.from(r['intent'] as Map)
          : r;
      return DmMessage(
        id: r['_id'] as String,
        outgoing: outgoing,
        text: content['text'] as String? ?? '',
        time: '',
        state: switch (r['_state']) {
          'queued' => DmSendState.sending,
          'unknown' => DmSendState.unknown,
          'failed' => DmSendState.failed,
          _ => DmSendState.sent,
        },
      );
    }).toList();
    return HhDirectMessageScreen(
      view: DmConversationView(
        scopeKey: environment,
        recipient: DmIdentity(id: peer, name: '验收乙'),
        selfIdentity: DmIdentity(id: own, name: '验收甲'),
        sourceTitle: '真实原生共享限流验收',
        messages: messages,
      ),
      identities: [DmIdentity(id: own, name: '验收甲')],
      imageBuilder: (_, _) => const SizedBox.shrink(),
      onSend: (value) => dm.send(intent(value.text)),
      onDraftChanged: (value) {
        if (dm.available) unawaited(dm.saveDraft(own, peer, value));
      },
      onIdentitySelected: (_) {},
      onPickImages: () async => [],
      onMessageAction: (target, action) async {
        if (action == DmMessageAction.delete) {
          await dm.deleteLocal(target.messageId);
        }
      },
      onRetry: (target) {
        unawaited(dm.retry(target.messageId));
      },
      onImage: (_) {},
      onSource: () {},
      onBack: () {
        page = 'posts';
        changed();
      },
      textOnly: true,
      reportEnabled: false,
      syncError: dm.error,
    );
  }
}

class _DeviceApp extends StatelessWidget {
  const _DeviceApp(this.lab);
  final _DeviceLab lab;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: ListenableBuilder(
      listenable: lab,
      builder: (context, _) {
        if (!lab.initialized) {
          return Scaffold(body: Center(child: Text(lab.status)));
        }
        Widget body;
        if (lab.page == 'posts') {
          body = PersonalPostsScreen(
            controller: lab.posts,
            channelNames: {lab.f['channelId'] as String: '合成验收通道'},
            onManageIdentities: () async {},
            onAuthenticationRequired: () {},
            showNavigation: false,
          );
        } else if (lab.page == 'comments') {
          body = CommentScope(
            runtime: lab.comments,
            child: CommentComposer(
              runtime: lab.comments,
              editor: CommentEditor(
                CommentTarget(postId: lab.f['postId'] as String),
              ),
              contextText: '真实评论限流原稿',
              onSubmitted: () {},
              originals: const {},
              expanded: true,
            ),
          );
        } else {
          body = lab.chat();
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('独立共享限流验收'),
            actions: [
              TextButton(
                onPressed: () {
                  lab.page = 'posts';
                  lab.changed();
                },
                child: const Text('发帖草稿'),
              ),
              TextButton(
                onPressed: () {
                  lab.page = 'comments';
                  lab.changed();
                },
                child: const Text('评论'),
              ),
              TextButton(
                onPressed: () {
                  lab.page = 'chat';
                  lab.changed();
                },
                child: const Text('私信'),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(lab.status),
              ),
              if (lab.posts.errorMessage != null) Text(lab.posts.errorMessage!),
              if (lab.comments.core.rateLimitMessage != null)
                Text(lab.comments.core.rateLimitMessage!),
              Expanded(child: body),
            ],
          ),
        );
      },
    ),
  );
}
