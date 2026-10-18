import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' show HnuholeApp;

// Host substitutes only at native selection/secure-storage/gallery boundaries.
// Auth, posts, media, grants, publication and SQL are actual isolated processes.
class _FileVault implements AuthVault, BusinessKeyVault {
  _FileVault(this.file);
  final File file;
  @override
  Future<String?> read() async =>
      await file.exists() ? file.readAsString() : null;
  @override
  Future<void> write(String value) => file.writeAsString(value, flush: true);
}

class _Picker implements PostPhotoPicker {
  List<File> files = [];
  @override
  Future<List<PostPickedFile>> pick(int limit) async => [
    for (final file in files.take(limit))
      PostPickedFile(length: file.length, openRead: file.openRead),
  ];
  @override
  Future<void> discardUnboundLostSelection() async {}
}

class _CaptureGallery implements ViewerGalleryWriter {
  Uint8List? bytes;
  String? path;
  @override
  Future<bool> hasAccess() async => true;
  @override
  Future<bool> requestAccess() async => true;
  @override
  Future<void> putImage(String originalPath) async {
    path = originalPath;
    bytes = await File(originalPath).readAsBytes();
  }
}

class _Runtime {
  _Runtime(this.config, this.tester);
  final Map<String, dynamic> config;
  final WidgetTester tester;
  final clients = <HttpClient>[];
  final stores = <PostStore>[];
  final picker = _Picker();
  final checks = <String, bool>{};
  bool appOwnsControllers = false;
  late final String root = config['runDir'] as String;
  late final Uri c = Uri.parse(config['communityOrigin'] as String);
  late final Uri v = Uri.parse(config['verifierOrigin'] as String);
  late final trust = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificates(config['caPath'] as String);
  late final environment = MobileEnvironment(
    communityBaseUri: c,
    verifierBaseUri: v,
  );
  late final api = HttpAuthApi(
    communityBaseUri: c,
    verifierBaseUri: v,
    client: client(),
  );
  late final postApi = HttpPostUploadApi(communityBaseUri: c, client: client());
  late final repository = HttpChannelRepository(baseUri: c, client: client());
  late final directory = ChannelDirectoryController(repository: repository);
  late final store = AuthStore(
    _FileVault(File('$root/auth.json')),
    scope: environment.storageScope,
  );
  late final sessions = AuthSessionController(
    api: api,
    store: store,
    directory: directory,
  );
  late final posts = PostController(
    api: postApi,
    mediaApi: postApi,
    uploadApi: postApi,
    photoPicker: picker,
    sessions: sessions,
    authStore: store,
    identities: api,
    pollInterval: Duration.zero,
    openStore: (account) async {
      final opened = await PostStore.openFile(
        File('$root/$account.sqlite'),
        environment: environment.storageScope,
        accountId: account,
        vault: _FileVault(File('$root/$account.key')),
      );
      stores.add(opened);
      return opened;
    },
  );
  late final media = PostMediaRepository(posts);
  late final passkey = NativePasskeyClient();
  late final management = SecurityManagementController(
    api: api,
    store: store,
    passkey: passkey,
    sessions: sessions,
  );
  late final identities = IdentityManagementController(
    api: api,
    store: store,
    sessions: sessions,
  );
  late final flows = AuthFlows(
    api: api,
    store: store,
    acceptRegistrationSession: sessions.acceptSession,
    clearCommunityAccess: sessions.clearCommunityAccess,
    passkeyApi: api,
    passkey: passkey,
    sessionAuthorityVersion: () => sessions.authorityVersion,
    sessionAuthority: sessions,
    onAccountClosed: posts.purgeClosedAccount,
  );
  String get token => store.current!.session!.token;
  File get stateFile => File('$root/state.json');
  HttpClient client() {
    final value = HttpClient(context: trust);
    clients.add(value);
    return value;
  }

  void passed(String id) {
    checks[id] = true;
    debugPrint('Joint checkpoint $id PASS');
  }

  Future<void> wait(bool Function() predicate, String label) async {
    final timer = Stopwatch()..start();
    while (!predicate() && timer.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(predicate(), isTrue, reason: label);
  }

  Future<Map<String, dynamic>> control(
    String path, [
    Map<String, dynamic> data = const {},
  ]) async {
    final request = await client().postUrl(
      Uri.parse(config['controlOrigin'] as String).resolve(path),
    );
    request.followRedirects = false;
    request.headers.set(
      'Authorization',
      'LabControl ${config['controlToken']}',
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(data));
    final response = await request.close();
    final raw = await utf8.decoder.bind(response).join();
    expect(response.statusCode, 200, reason: 'owned test control $path');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> open() async {
    posts;
    await sessions.start();
    if (sessions.isAuthenticated) {
      await wait(() => stores.isNotEmpty, 'business file opened');
    }
  }

  Future<void> register() async {
    await flows.requestOtp('jointmedia@hainanu.edu.cn');
    expect(flows.status, AuthFlowStatus.otpRequested);
    String? code;
    for (var i = 0; i < 100 && code == null; i++) {
      code =
          (await control('/otp', {
                'email': 'jointmedia@hainanu.edu.cn',
              }))['code']
              as String?;
      if (code == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    expect(code, isNotNull, reason: 'actual V SMTP delivery');
    await flows.confirmOtp(code!);
    await flows.createRegistration(
      'joint_media_user',
      'Joint synthetic long password 2026!',
    );
    expect(flows.recoveryCode, isNotNull);
    final recovery = flows.recoveryCode!;
    flows.hideRecoveryCode();
    await flows.commitRegistration(recovery);
    expect(flows.status, AuthFlowStatus.registrationComplete);
    expect(
      sessions.isAuthenticated,
      isTrue,
      reason: 'actual registration session accepted',
    );
    await wait(
      () =>
          posts.available && stores.isNotEmpty && directory.channels.isNotEmpty,
      'real registered directory',
    );
    passed('J01-real-C-V-HTTPS-registration-SMTP-and-directory');
  }

  Future<StoredPostEntry> local(String id) async =>
      (await stores.last.get(id))!;
  Future<void> uploadStopped(String id) => wait(
    () => posts.imageUploadProgress(id)?.busy == false,
    'upload settled',
  );
  Future<PostDraftEditor> selected(
    String channel,
    String identity,
    List<String> names, {
    String title = '图片联调',
  }) async {
    final e = posts.newDraft(channel)
      ..identityId = identity
      ..title = title;
    picker.files = [
      for (final name in names) File('${config['fixtures']}/$name.bin'),
    ];
    await posts.pickDraftPhotos(e);
    expect(e.images.length, names.length);
    expect(
      e.images.every((i) => i.ready),
      isTrue,
      reason: 'actual Flutter preflight',
    );
    return e;
  }

  Future<void> published(PostDraftEditor e) async {
    final timer = Stopwatch()..start();
    while ((await local(e.id)).state != 'PUBLISHED' &&
        timer.elapsed < const Duration(seconds: 30)) {
      await posts.reconcile(e.id);
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect((await local(e.id)).state, 'PUBLISHED');
  }

  Future<void> close(String phase) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    if (!appOwnsControllers) {
      media.dispose();
      posts.dispose();
      identities.dispose();
      management.dispose();
      flows.dispose();
      sessions.dispose();
      directory.dispose();
      postApi.close();
      api.close();
      repository.close();
      store.dispose();
    }
    for (final s in stores) {
      await s.close();
    }
    for (final c in clients) {
      c.close(force: true);
    }
    await File('$root/checks-$phase.json')
        .writeAsString(jsonEncode(checks), flush: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['POST_MEDIA_JOINT_CONFIG'];
  final phase = Platform.environment['POST_MEDIA_JOINT_PHASE'];
  if (path == null) {
    test(
      'post media requires owned actual C/V/SQL lab',
      () {},
      skip: 'tools/post-media-joint/run.py',
    );
    return;
  }
  HttpOverrides.global = null;
  testWidgets('actual post media frontend/backend $phase', (tester) async {
    tester.view.physicalSize = const Size(480, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final r = _Runtime(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
        tester,
      );
      try {
        if (phase == 'read') {
          await r.control('/fault', {'holdQuery': false});
        }
        await r.open();
        if (phase == 'write') {
          await r.register();
          final identity = await r.api.changeIdentity(
            sessionToken: r.token,
            idempotencyKey: AuthCrypto.randomEncoded(16),
            operation: IdentityOperation.create,
            nickname: '图片联调身份',
          );
          expect(identity.committed, isTrue);
          final channel = r.directory.channels.first;
          final e = r.posts.newDraft(channel.id)
            ..title = '九图联调'
            ..identityId = identity.identityId;
          r.picker.files = [
            for (final name in [
              'png',
              'jpeg',
              'gif',
              'webp',
              'oriented-jpeg',
              'png',
              'gif',
              'webp',
              'jpeg',
            ])
              File('${r.config['fixtures']}/$name.bin'),
          ];
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: const Scaffold(body: Text('原通道')),
            ),
          );
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => PostComposerScreen(
                  controller: r.posts,
                  editor: e,
                  channelName: channel.name,
                  onManageIdentities: () async {},
                  onAuthenticationRequired: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await r.wait(
            () => find
                .byKey(const ValueKey('post-add-images'))
                .evaluate()
                .isNotEmpty,
            'actual composer route mounted',
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('post-add-images')),
          );
          await tester.tap(find.byKey(const ValueKey('post-add-images')));
          await r.wait(
            () => !e.mediaBusy && e.images.length == 9,
            'nine selected originals',
          );
          expect(e.images.every((i) => i.ready), isTrue);
          expect(find.text('9/9'), findsOneWidget);
          r.passed('J02-production-composer-nine-originals-image-only');
          final moved = e.images.removeAt(0);
          e.images.insert(2, moved);
          e.mediaTouched = true;
          expect(await r.posts.saveDraft(e), isTrue);
          final manifests = [
            for (final image in e.images) image.selection!.toJson(),
          ];
          await r.control('/fault', {
            'dropCreate': true,
            'holdQuery': true,
            'dropBefore': [e.images[2].mediaId],
            'dropAfter': [e.images[4].mediaId],
          });
          await tester.ensureVisible(find.text('下一步'));
          await r.wait(
            () =>
                tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, '下一步'),
                    )
                    .onPressed !=
                null,
            'next action enabled after media save frame',
          );
          await tester.tap(find.text('下一步'));
          await r.wait(
            () => find.text('确认发布').evaluate().isNotEmpty,
            'real confirmation page',
          );
          await r.wait(
            () =>
                tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, '确认发布'),
                    )
                    .onPressed !=
                null,
            'real identity/context permits confirmation',
          );
          await tester.tap(find.text('确认发布'));
          await r.wait(
            () => e.submitted && find.text('原通道').evaluate().isNotEmpty,
            'durable intent returns original channel',
          );
          r.passed('J03-production-confirmation-durable-intent-and-return');
          await r.wait(
            () => r.posts.personalItems.any(
              (x) => {'UNKNOWN', 'submitted'}.contains(x.local?.state),
            ),
            'lost committed CREATE remains unknown',
          );
          var stats = await r.control('/stats');
          final receiptTimer = Stopwatch()..start();
          while (stats['postDrops'] == 0 &&
              receiptTimer.elapsed < const Duration(seconds: 10)) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            stats = await r.control('/stats');
          }
          expect(stats['creates'], 1);
          expect(
            stats['postDrops'],
            1,
            reason: 'actual C accepted before connection was dropped',
          );
          await r.stateFile.writeAsString(
            jsonEncode({
              'entryId': e.id,
              'channel': channel.id,
              'channelName': channel.name,
              'identity': identity.identityId,
              'manifest': manifests,
            }),
            flush: true,
          );
          r.passed(
            'J04-committed-CREATE-response-loss-one-command-before-process-exit',
          );
        } else {
          final state = jsonDecode(
            await r.stateFile.readAsString(),
          ) as Map<String, dynamic>;
          final channel = state['channel'] as String,
              identity = state['identity'] as String;
          if (phase == 'read') {
            await r.control('/fault', {'holdQuery': false});
            final id = state['entryId'] as String;
            await r.posts.reconcile(id);
            await r.wait(
              () =>
                  r.posts.imageUploadProgress(id)?.message != null &&
                  r.posts.imageUploadProgress(id)?.busy == false,
              'partial resumed upload',
            );
            final entry = await r.local(id);
            expect(entry.state, 'ACCEPTED');
            final task = entry.data['taskId'] as String,
                post = entry.data['postId'] as String;
            state['taskId'] = task;
            state['postId'] = post;
            final sql = await r.control('/snapshot', {'taskId': task});
            expect(sql['verified'], 8);
            expect(sql['public'], 0);
            expect((await r.control('/stats'))['creates'], 1);
            r.passed(
              'J05-fresh-Flutter-process-restores-original-intent-and-partial-upload',
            );
            r.passed('J06-real-SQL-eight-verified-no-public-until-complete');
            await r.posts.resumeImageUpload(id);
            final timer = Stopwatch()..start();
            while ((await r.local(id)).state != 'PUBLISHED' &&
                timer.elapsed < const Duration(seconds: 30)) {
              await r.posts.reconcile(id);
              await Future<void>.delayed(const Duration(milliseconds: 250));
            }
            expect((await r.local(id)).state, 'PUBLISHED');
            final counts = await r.control('/stats');
            final manifest = state['manifest'] as List;
            final puts = counts['puts'] as Map;
            expect(puts[manifest[2]['mediaId']], 2);
            expect(puts[manifest[4]['mediaId']], 1);
            expect(puts.values.fold<int>(0, (n, v) => n + v as int), 10);
            expect(counts['creates'], 1);
            r.passed(
              'J07-missing-only-retry-and-lost-PUT-receipt-no-duplicate',
            );
            final group = await r.media.load(post);
            expect(group.images.length, 9);
            final sqlDone = await r.control('/snapshot', {'taskId': task});
            expect(sqlDone['verified'], 9);
            expect(sqlDone['public'], 1);
            for (var i = 0; i < 9; i++) {
              final source = await group.images[i].item.loadSource();
              final bytes = (source.provider as MemoryImage).bytes;
              expect(
                hashes.sha256.convert(bytes).toString(),
                manifest[i]['sha256'],
              );
              final row = (sqlDone['payloads'] as List).singleWhere(
                (x) => x['position'] == i,
              );
              expect(row['sha256'], manifest[i]['sha256']);
              expect(row['bytes'], manifest[i]['byteLength']);
            }
            r.passed(
              'J08-ordered-manifest-original-hashes-JPEG-PNG-GIF-WebP-EXIF-through-SQL',
            );
            for (final mime in ['image/gif', 'image/webp']) {
              final at = manifest.indexWhere((x) => x['mimeType'] == mime);
              final writer = _CaptureGallery();
              final saver = ViewerSaveCoordinator(
                gallery: writer,
                createTemporaryDirectory: () =>
                    Directory(r.root).createTemp('host-save-'),
              );
              final result = await saver.save(
                itemId: group.images[at].item.id,
                resolveOriginal: group.images[at].item.resolveOriginal!,
                isCurrent: () => group.accessGranted.value,
              );
              expect(result.status, ViewerSaveStatus.saved);
              expect(
                hashes.sha256.convert(writer.bytes!).toString(),
                manifest[at]['sha256'],
              );
              expect(await File(writer.path!).exists(), isFalse);
              saver.dispose();
            }
            r.passed(
              'J09-fresh-protected-save-resolver-original-animation-bytes-host-writer-only',
            );
            group.onRelease!();
            r.appOwnsControllers = true;
            await tester.pumpWidget(
              HnuholeApp(
                directory: r.directory,
                repository: r.repository,
                api: r.api,
                sessions: r.sessions,
                flows: r.flows,
                management: r.management,
                identities: r.identities,
                store: r.store,
                posts: r.posts,
                postApi: r.postApi,
                postMedia: r.media,
                loadPostImages: r.media.load,
              ),
            );
            await r.wait(
              () =>
                  r.directory.channels.isNotEmpty && r.sessions.isAuthenticated,
              'real main root',
            );
            await tester.pump(const Duration(milliseconds: 300));
            final channelName = state['channelName'] as String;
            await tester.tap(find.text(channelName).first);
            await r.wait(
              () => find.byType(ChannelPostsScreen).evaluate().isNotEmpty,
              'main channel route',
            );
            await r.wait(
              () => find.text('九图联调').evaluate().isNotEmpty,
              'real feed contains image-only post',
            );
            await tester.tap(find.text('九图联调').first);
            await r.wait(
              () => find.bySemanticsLabel('查看第1张图片，共9张').evaluate().isNotEmpty,
              'actual detail preview',
            );
            await tester.ensureVisible(find.bySemanticsLabel('查看第1张图片，共9张'));
            await tester.tap(find.bySemanticsLabel('查看第1张图片，共9张'));
            await r.wait(
              () => find.byType(HnuImageViewer).evaluate().isNotEmpty,
              'real viewer route',
            );
            r.passed(
              'J10-production-main-channel-detail-viewer-real-media-entry',
            );
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(milliseconds: 300));
            await r.stateFile.writeAsString(jsonEncode(state), flush: true);
          } else {
            expect(phase, 'edges');
            final post = state['postId'] as String,
                task = state['taskId'] as String;
            final group = await r.media.load(post);
            expect(await r.posts.deletePost(post), isTrue);
            expect(group.accessGranted.value, isFalse);
            await expectLater(
              r.postApi.imageManifest(sessionToken: r.token, postId: post),
              throwsA(
                isA<PostFailure>().having((e) => e.statusCode, 'status', 404),
              ),
            );
            final erased = await r.control('/snapshot', {'taskId': task});
            expect(erased['verified'], 0);
            expect(erased['erased'], 9);
            expect(erased['public'], 0);
            r.passed(
              'J11-delete-immediately-revokes-group-protected-read-and-erases-SQL-originals',
            );
            final e = await r.selected(channel, identity, ['png', 'gif']);
            await r.control('/fault', {
              'dropBefore': [for (final i in e.images) i.mediaId],
            });
            expect(await r.posts.publish(e), isTrue);
            await r.uploadStopped(e.id);
            final active = await r.local(e.id);
            final capability = await r.postApi.uploadGrant(
              sessionToken: r.token,
              taskId: active.data['taskId'] as String,
              version: 1,
              mediaId: e.images.first.mediaId,
            );
            final forbidden = await r.client().getUrl(
              r.c.resolve('/api/v1/posts/$post/images'),
            );
            forbidden.headers.set(
              'Authorization',
              'Upload ${capability.value.uploadToken}',
            );
            final denied = await forbidden.close();
            await denied.drain<void>();
            expect(denied.statusCode, 401);
            r.passed('J17-upload-capability-cannot-read-protected-images');
            await r.posts.cancelTask(active.data['taskId'] as String);
            await expectLater(
              r.postApi.putOriginal(
                uploadToken: capability.value.uploadToken,
                taskId: active.data['taskId'] as String,
                version: 1,
                image: e.images.first.selection!,
                bytes: await r.posts.draftPhotoBytes(
                  (await r.posts.restoreDraft('cancelled-${e.id}'))!,
                  e.images.first,
                ),
              ),
              throwsA(
                isA<PostFailure>().having((e) => e.statusCode, 'status', 403),
              ),
            );
            r.passed('J18-cancelled-upload-capability-cannot-write-originals');
            final rows = await r.stores.last.list();
            final draft = rows.singleWhere((x) => x.isDraft);
            final restored = (await r.posts.restoreDraft(draft.id))!;
            expect(restored.images.length, 2);
            for (final i in restored.images) {
              expect(await r.posts.draftPhotoBytes(restored, i), isNotEmpty);
            }
            await r.wait(
              () => r.posts.imageUploadProgress(e.id)?.busy != true,
              'cancel settles',
            );
            final cancel = await r.control('/snapshot', {
              'taskId': active.data['taskId'],
            });
            expect(cancel['verified'], 0);
            expect(cancel['public'], 0);
            r.passed(
              'J12-real-cancel-preserves-local-original-draft-and-no-public-post',
            );
            final failed = await r.selected(channel, identity, [
              'png',
              'gif',
            ], title: '失败重试联调');
            await r.control('/fault', {
              'dropBefore': [failed.images.last.mediaId],
            });
            expect(await r.posts.publish(failed), isTrue);
            await r.uploadStopped(failed.id);
            final failedTask =
                (await r.local(failed.id)).data['taskId'] as String;
            await r.control('/mute', {'taskId': failedTask});
            final failedTimer = Stopwatch()..start();
            while ((await r.local(failed.id)).state != 'FAILED' &&
                failedTimer.elapsed < const Duration(seconds: 15)) {
              await r.posts.reconcile(failed.id);
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
            expect((await r.local(failed.id)).state, 'FAILED');
            await Future<void>.delayed(const Duration(seconds: 4));
            final retry = (await r.posts.editFailedTask(failedTask))!;
            expect(retry.identityId, identity);
            expect(retry.channelId, channel);
            expect(retry.images.length, 2);
            retry.images.removeLast();
            retry.mediaTouched = true;
            retry.title = '新尝试联调';
            expect(await r.posts.publish(retry), isTrue);
            await r.published(retry);
            final retried = await r.control('/snapshot', {
              'taskId': failedTask,
            });
            expect(retried['public'], 1);
            expect(
              retried['states'],
              containsAll([
                {'version': 1, 'state': 'FAILED'},
                {'version': 2, 'state': 'PUBLISHED'},
              ]),
            );
            r.passed(
              'J16-real-worker-stop-failure-edited-RETRY-new-attempt-fixed-identity-channel',
            );
            final unavailable = await r.selected(channel, identity, ['webp']);
            await r.control('/validator', {'tamper': true});
            expect(await r.posts.publish(unavailable), isTrue);
            await r.uploadStopped(unavailable.id);
            expect(r.posts.imageUploadProgress(unavailable.id)!.failed, {0});
            expect(r.sessions.isAuthenticated, isTrue);
            await r.control('/validator', {'tamper': false});
            await r.posts.resumeImageUpload(unavailable.id);
            await r.published(unavailable);
            r.passed(
              'J13-real-validator-drift-503-pauses-without-Bearer-revocation-then-recovers',
            );
            final available = await r.local(unavailable.id);
            final publicId = available.data['postId'] as String;
            final frozen = await r.media.load(publicId);
            await r.control('/freeze');
            await expectLater(
              frozen.images.first.item.loadSource(),
              throwsA(isA<PostFailure>()),
            );
            expect(frozen.accessGranted.value, isFalse);
            expect(r.posts.available, isFalse);
            await r.control('/recover');
            await r.sessions.retry();
            // A real Gate recovery advances generation and rejects the old
            // session. Reauthenticate; never weaken that boundary for media.
            expect(r.posts.available, isFalse);
            await r.sessions.login(
              'joint_media_user',
              'Joint synthetic long password 2026!',
            );
            await r.wait(
              () => r.posts.available,
              'fresh C generation recovered',
            );
            expect(frozen.accessGranted.value, isFalse);
            r.passed(
              'J14-real-C-Gate-freeze-revokes-media-and-explicit-recovery',
            );
            final expiring = await r.media.load(publicId);
            await Future<void>.delayed(const Duration(seconds: 61));
            expect(expiring.accessGranted.value, isFalse);
            await expectLater(
              expiring.images.first.item.loadSource(),
              throwsA(isA<PostFailure>()),
            );
            r.passed(
              'J19-real-sixty-second-lease-expires-without-clock-substitute',
            );
            final late = await r.media.load(publicId);
            await r.control('/read-hold', {'hold': true});
            var rejected = false;
            final reading = late.images.first.item.loadSource().then<void>(
              (_) => fail('Late pixels disclosed'),
              onError: (Object _) {
                rejected = true;
              },
            );
            final timer = Stopwatch()..start();
            while ((await r.control('/stats'))['readWaiting'] != true &&
                timer.elapsed < const Duration(seconds: 10)) {
              await Future<void>.delayed(const Duration(milliseconds: 40));
            }
            expect((await r.control('/stats'))['readWaiting'], isTrue);
            await r.sessions.logout();
            expect(late.accessGranted.value, isFalse);
            await r.control('/read-hold', {'hold': false});
            await reading;
            expect(rejected, isTrue);
            r.passed(
              'J15-real-protected-response-late-after-logout-never-discloses-pixels',
            );
          }
        }
      } finally {
        await r.close(phase!);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
