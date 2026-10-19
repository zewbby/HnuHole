import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/comments/comment_runtime.dart';
import 'package:hnuhole_mobile/src/comments/comment_http.dart';
import 'package:hnuhole_mobile/src/comments/comment_journal.dart';
import 'package:hnuhole_mobile/src/comments/comment_models.dart';
import 'package:hnuhole_mobile/src/comments/comment_views.dart';
import 'package:hnuhole_mobile/src/development/app_transport.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real comments native journal, process recovery, image and notification actions',
    (tester) async {
      const encoded = String.fromEnvironment('COMMENT_DEVICE_FIXTURE_BASE64');
      expect(encoded, isNotEmpty);
      final f = jsonDecode(
        utf8.decode(base64Decode(encoded)),
      ) as Map<String, dynamic>;
      const driver = MethodChannel('hnuhole/owned_device_driver');
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        {
          'comment-write',
          'comment-read',
          'comment-view',
          'comment-picker',
        }.contains(phase),
        isTrue,
      );
      final device = await driver.invokeMapMethod<String, dynamic>(
        'deviceState',
      );
      if (phase == 'comment-picker') {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('选择本任务合成图，核对原格式和字节'))),
        );
        final files = await NativePostPhotoPicker().pick(1);
        expect(files.length, 1);
        final inspected = await inspectPostPhoto(files.single, commentUUID());
        expect(inspected.selection.sha256, (f['image'] as Map)['sha256']);
        expect(inspected.bytes, base64Decode(f['imageBytes'] as String));
        final vault = DurableBusinessVault(
          PostStore.scopeFor('picker:${f['run']}', f['accountId'] as String),
        );
        final report = File(
          '${File(await vault.databasePath()).parent.path}/comment-device-picker.json',
        );
        await report.writeAsString(
          jsonEncode({
            'status': 'PASS',
            'phase': phase,
            'pid': device!['pid'],
            'originalFormatAndHash': true,
          }),
        );
        binding.reportData = {'originalFormatAndHash': true};
        return;
      }
      final c = Uri.parse(f['url'] as String),
          v = Uri.parse(f['verifier'] as String);
      final ca = base64Encode(utf8.encode(f['certificatePem'] as String));
      HttpClient client() =>
          createAppHttpClient(community: c, verifier: v, developmentCa: ca);
      final scope = 'comments.device.${f['run']}';
      final store = AuthStore(FlutterAuthVault(namespace: scope), scope: scope);
      final auth = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        client: client(),
      );
      final repository = HttpChannelRepository(baseUri: c, client: client());
      final directory = ChannelDirectoryController(repository: repository);
      final sessions = AuthSessionController(
        api: auth,
        store: store,
        directory: directory,
      );
      await sessions.start();
      if (phase == 'comment-write') {
        expect(store.current?.session, isNull);
        await sessions.acceptSession(
          AuthSession(
            accountId: f['accountId'] as String,
            sessionToken: f['token'] as String,
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        );
      }
      expect(sessions.isAuthenticated, isTrue);
      final identities = IdentityManagementController(
        api: auth,
        store: store,
        sessions: sessions,
      );
      final environment = '${c.origin}|comments-device:${f['run']}';
      final journal = NativeCommentJournal(
        (a) => PostStore.openNative(environment: environment, accountId: a),
      );
      final runtime = CommentRuntime(
        http: CommentHttp(c, client: client()),
        sessions: sessions,
        authStore: store,
        identities: auth,
        identityManagement: identities,
        journal: journal,
      );
      Future<void> wait(bool Function() condition, String label) async {
        final until = DateTime.now().add(const Duration(seconds: 30));
        while (!condition() && DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          condition(),
          isTrue,
          reason:
              '$label; mediaSections=${find.byType(PostImagesSection).evaluate().length}; commentMediaSections=${find.descendant(of: find.byType(CommentImageView), matching: find.byType(PostImagesSection)).evaluate().length}; imageRect=${find.byType(CommentImageView).evaluate().isEmpty ? null : tester.getRect(find.byType(CommentImageView))}; imageLabels=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((t) => t.contains("图片")).join("|")}',
        );
      }

      await wait(() => runtime.core.ready, 'native journal ready');
      Future<void> control(String path) async {
        final h = client();
        try {
          final r = await h.postUrl(Uri.parse('${f['control']}$path'));
          r.headers.set('Authorization', 'CommentLab ${f['controlToken']}');
          final response = await r.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          h.close(force: true);
        }
      }

      final flags = <String, bool>{};
      final post = f['postId'] as String,
          account = f['accountId'] as String,
          task = f['taskId'] as String;
      final postApi = HttpPostUploadApi(communityBaseUri: c, client: client());
      final posts = PostController(
        api: postApi,
        mediaApi: postApi,
        uploadApi: postApi,
        photoPicker: NativePostPhotoPicker(),
        sessions: sessions,
        authStore: store,
        identities: auth,
        openStore: (a) => PostStore.openNative(
          environment: '$environment|posts',
          accountId: a,
        ),
        purgeStore: (a) => PostStore.purgeNativeClosedAccount(
          environment: '$environment|posts',
          accountId: a,
        ),
      );
      final governanceApi = HttpGovernanceApi(baseUri: c, client: client());
      final governance = GovernanceController(
        api: governanceApi,
        sessions: sessions,
        authStore: store,
        identitiesApi: auth,
        pendingStore: GovernancePendingStore(
          FlutterAuthVault(namespace: '$scope.governance'),
        ),
      );
      Widget app(Widget home) => MaterialApp(
        key: UniqueKey(),
        builder: (context, child) => CommentScope(
          runtime: runtime,
          child: GovernanceScope(controller: governance, child: child!),
        ),
        home: home,
      );
      Widget page() => app(PostDetailScreen(controller: posts, postId: post));
      try {
        if (phase == 'comment-write') {
          expect(await journal.read(account), isEmpty);
          final selection = PostImageSelection.fromJson(f['image']);
          final image = CommentImage(
            blobId: commentUUID(),
            selection: selection,
          );
          journal.staged[image.blobId] = base64Decode(
            f['imageBytes'] as String,
          );
          await runtime.core.submit(
            taskId: task,
            commandId: commentKey(),
            binding: CommentBinding(
              postId: post,
              identityId: f['identityId'] as String,
            ),
            content: CommentContent(body: '原生重开原文\r\ne\u0301', image: image),
          );
          final entry = (await journal.read(account)).single;
          expect(entry.intent.taskId, task);
          expect(
            await journal.bytes(account, image),
            base64Decode(f['imageBytes'] as String),
          );
          flags['originalCommittedBeforeUnknown'] = true;
          flags['unknownNotRetried'] =
              entry.transport == CommentTransportState.unknown;
          await tester.pumpWidget(page());
          await wait(
            () => find.text('评论真机验收').evaluate().isNotEmpty,
            'real detail route',
          );
          // Unsubmitted editor input is kept in this route only and absent from SQL.
          await tester.tap(find.text('写评论'));
          await wait(
            () => find.byType(TextField).evaluate().isNotEmpty,
            'real comment composer',
          );
          await tester.enterText(find.byType(TextField), '未发送临时输入');
          await tester.tap(find.byType(CloseButton));
          await tester.pumpAndSettle();
          expect(find.text('继续输入'), findsOneWidget);
          expect((await journal.read(account)).length, 1);
          flags['temporaryInputNotJournaled'] = true;
        } else {
          if (phase != 'comment-view') {
            final loaded = (await journal.read(account)).single;
            expect(loaded.intent.taskId, task);
            expect(loaded.content!.body, '原生重开原文\r\ne\u0301');
            flags['nativeJournalReopened'] = true;
          }
          await control('/resume');
          await runtime.reconcile();
          await wait(
            () =>
                phase == 'comment-view' ||
                runtime.core.resolvedTasks.any((t) => t.taskId == task),
            'original task published after reopen',
          );
          final published = phase == 'comment-view'
              ? (await runtime.api.queryTask(
                  taskId: task,
                  binding: CommentBinding(
                    postId: post,
                    identityId: f['identityId'] as String,
                  ),
                ))!
              : runtime.core.resolvedTasks.singleWhere((t) => t.taskId == task);
          final cid = published.commentId!;
          expect(await journal.read(account), isEmpty);
          flags['publishedOriginalRemovedFromJournal'] = true;
          final row = await runtime.request(
            'GET',
            '/api/v1/posts/$post/comments/$cid',
          );
          expect(row['body'], '原生重开原文\r\ne\u0301');
          expect(row['image'], isNotNull);
          final original = await runtime.http.image(
            f['token'] as String,
            '/api/v1/posts/$post/comments/$cid/images/${(row['image'] as Map)['contentVersionId']}/original',
            (row['image'] as Map)['mimeType'] as String,
          );
          expect(original.bytes, base64Decode(f['imageBytes'] as String));
          flags['exactOriginalAfterProcessDeath'] = true;
          await tester.pumpWidget(page());
          await wait(
            () => find.text('评论真机验收').evaluate().isNotEmpty,
            'detail after process restart',
          );
          await wait(
            () =>
                find.text('评论 1').evaluate().isNotEmpty ||
                find.text('原生重开原文\r\ne\u0301').evaluate().isNotEmpty,
            'current comment total or focused own publication',
          );
          if (find.text('原生重开原文\r\ne\u0301').evaluate().isEmpty) {
            await tester.tap(find.text('评论 1'));
          }
          await wait(
            () => find.text('原生重开原文\r\ne\u0301').evaluate().isNotEmpty,
            'published comment in actual page',
          );
          // Let the just-published comment's own location finish before moving
          // to its image; both operations intentionally use the comment scroll.
          await tester.pump(const Duration(milliseconds: 600));
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await Scrollable.ensureVisible(
            tester.element(find.byType(CommentImageView)),
            alignment: .5,
          );
          final thumbnail = find.byKey(
            ValueKey(('post-image', (row['image'] as Map)['contentVersionId'] as String)),
          );
          await wait(
            () => thumbnail.evaluate().isNotEmpty,
            'visible protected single-image thumbnail',
          );
          await tester.tap(thumbnail);
          await wait(
            () => find.byType(HnuImageViewer).evaluate().isNotEmpty,
            'comment image viewer',
          );
          await wait(
            () =>
                tester
                    .widget<HnuImageViewer>(find.byType(HnuImageViewer))
                    .controller
                    .snapshot
                    .status ==
                ViewerLoadStatus.ready,
            'full original viewer decode',
          );
          await tester.tap(find.byKey(const ValueKey('viewer-close')));
          await tester.pumpAndSettle();
          flags['protectedSingleImageViewerOpenedAndClosed'] = true;
          await control('/pause');
          final failedId = commentUUID();
          await runtime.core.submit(
            taskId: failedId,
            commandId: commentKey(),
            binding: CommentBinding(
              postId: post,
              identityId: f['identityId'] as String,
              rootCommentId: cid,
              targetCommentId: cid,
            ),
            content: CommentContent(body: '真机失败保留原身份和目标'),
          );
          await control('/fail');
          await runtime.core.reconcile(failedId);
          expect(runtime.core.failures.single.taskId, failedId);
          await governance.loadIdentities();
          await governance.selectIdentity(f['identityId'] as String);
          await governance.loadNotifications();
          expect(
            governance.items.any(
              (n) =>
                  n.route.name == 'COMMENT_FAILURE' &&
                  n.route.resourceId == failedId,
            ),
            isTrue,
          );
          flags['realIdentityFailureNotification'] = true;
          await tester.pumpWidget(
            app(SystemNotificationsScreen(controller: governance)),
          );
          await wait(
            () => find.text('评论发送失败').evaluate().isNotEmpty,
            'real system notification list',
          );
          await tester.tap(find.text('评论发送失败').first);
          await wait(
            () => find.text('按原身份和对象重试').evaluate().isNotEmpty,
            'connected failure detail',
          );
          await tester.ensureVisible(find.text('按原身份和对象重试'));
          await tester.tap(find.text('按原身份和对象重试'));
          await wait(
            () => runtime.core.entries.any(
              (e) => e.task?.state == CommentTaskState.accepted,
            ),
            'failure detail retried original task',
          );
          await control('/resume');
          await wait(() {
            unawaited(runtime.reconcile());
            return runtime.core.resolvedTasks.any((t) => t.taskId == failedId);
          }, 'explicit retry published');
          await governance.loadNotifications();
          expect(
            governance.items.where((n) => n.route.resourceId == failedId),
            isEmpty,
          );
          flags['retryClearedRealNotification'] = true;
          await runtime.mutate(cid, liked: true);
          final liked = await runtime.request(
            'GET',
            '/api/v1/posts/$post/comments/$cid',
          );
          expect(liked['likeCount'], 1);
          flags['realAccountLike'] = true;
          await sessions.acceptSession(
            AuthSession(
              accountId: f['otherAccountId'] as String,
              sessionToken: f['otherToken'] as String,
              expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            ),
          );
          await wait(
            () =>
                runtime.accountId == f['otherAccountId'] && runtime.core.ready,
            'account switch',
          );
          expect(runtime.core.entries, isEmpty);
          await runtime.mutate(cid, liked: true);
          final other = await runtime.request(
            'GET',
            '/api/v1/posts/$post/comments/$cid',
          );
          expect(other['likeCount'], 2);
          flags['accountIsolation'] = true;
          await sessions.acceptSession(
            AuthSession(
              accountId: account,
              sessionToken: f['token'] as String,
              expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            ),
          );
          await wait(
            () => runtime.accountId == account && runtime.core.ready,
            'original account restored',
          );
          await runtime.mutate(cid);
          if (!runtime.deleted.contains(cid)) {
            final diag = File(
              '${File(await DurableBusinessVault(PostStore.scopeFor(environment, account)).databasePath()).parent.path}/comment-delete-diagnostic.json',
            );
            await diag.writeAsString(
              jsonEncode({
                'error': runtime.error,
                'pending': runtime.mutations.values
                    .map((m) => m['operation'])
                    .toList(),
                'sameAccount': runtime.accountId == account,
              }),
            );
          }
          expect(runtime.deleted.contains(cid), isTrue);
          flags['ownerDeletedWholeFloor'] = true;
        }
        final native = DurableBusinessVault(
          PostStore.scopeFor(environment, account),
        );
        final file = File(
          '${File(await native.databasePath()).parent.path}/comment-device-$phase.json',
        );
        await file.writeAsString(
          jsonEncode({
            'status': 'PASS',
            'phase': phase,
            'pid': device!['pid'],
            'flags': flags,
          }),
        );
        binding.reportData = {'phase': phase, 'flags': flags};
      } finally {
        await tester.pumpWidget(const SizedBox());
        runtime.dispose();
        governance.dispose();
        governanceApi.close();
        posts.dispose();
        postApi.close();
        identities.dispose();
        sessions.dispose();
        directory.dispose();
        repository.close();
        auth.close();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
