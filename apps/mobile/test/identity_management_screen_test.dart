import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

Future<void> _show(WidgetTester tester, IdentityTestFixture fixture) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: IdentityManagementScreen(
        controller: fixture.controller,
        sessions: fixture.sessions,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'settings exposes implemented identity, security and account closure routes',
    (tester) async {
      var identity = 0, security = 0, account = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            onManageIdentity: () => identity++,
            onManageSecurity: () => security++,
            onManageAccount: () => account++,
          ),
        ),
      );
      await tester.tap(find.text('身份管理'));
      await tester.tap(find.text('设备与恢复凭据'));
      await tester.tap(find.text('账号与注销'));
      expect(identity, 1);
      expect(security, 1);
      expect(account, 1);
      expect(find.text('自己的帖子'), findsNothing);
    },
  );

  testWidgets(
    'zero-identity account can create default-avatar identity and preserves legal input',
    (tester) async {
      final f = await IdentityTestFixture.create();
      await _show(tester, f);
      expect(find.textContaining('仍可浏览社区'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('identity-add')));
      expect(find.text('默认头像'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '春😀风',
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('identity-nickname')),
      );
      expect(field.controller!.text, '春风');
      expect(find.textContaining('已移除非法字符'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('identity-save')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '春风秋',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('identity-save')));
      expect(f.api.submissions.single['nickname'], '春风秋');
      expect(f.controller.directory!.identities.single.avatar, 'default-v1');
      expect(f.store.current!.identityDrafts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );

  testWidgets(
    'first setup cancel restores durable nickname and explicit discard disables edits while saving',
    (tester) async {
      final f = await IdentityTestFixture.create();
      await _show(tester, f);
      await _tap(tester, find.byKey(const ValueKey('identity-add')));
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '春风',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('取消'));
      expect(
        f.store.current!.identityDrafts[identityTestAccount]['nickname'],
        '春风',
      );
      await _tap(tester, find.byKey(const ValueKey('identity-add')));
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('identity-nickname')),
            )
            .controller!
            .text,
        '春风',
      );
      final release = Completer<void>();
      f.vault.nextReadWait = release;
      await tester.ensureVisible(find.text('放弃已填昵称'));
      await tester.tap(find.text('放弃已填昵称'));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('identity-nickname')),
            )
            .enabled,
        isFalse,
      );
      release.complete();
      await tester.pumpAndSettle();
      expect(f.store.current!.identityDrafts, isEmpty);
      expect(find.byKey(const ValueKey('identity-nickname')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );

  testWidgets(
    'last identity cannot delete and successful creation has no initial rename cooldown',
    (tester) async {
      final f = await IdentityTestFixture.create();
      f.api.items = [identityTestItem()];
      f.api.createdCount = 1;
      await _show(tester, f);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '最后一个身份不能删除'))
            .onPressed,
        isNull,
      );
      await _tap(tester, find.text('面具一'));
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('identity-nickname')),
            )
            .enabled,
        isTrue,
      );
      await _tap(tester, find.text('取消'));
      expect(f.api.submissions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );

  testWidgets(
    'delete confirmation shows avatar name consequences and Shanghai next-create day',
    (tester) async {
      final f = await IdentityTestFixture.create();
      f.api.items = [
        identityTestItem(),
        identityTestItem(id: identityTestSecondId, name: '秋雨', original: false),
      ];
      f.api.createdCount = 3;
      f.api.nextCreateAt = DateTime.utc(2027, 3, 12, 16);
      await _show(tester, f);
      await _tap(tester, find.text('删除此身份').first);
      expect(find.byType(DefaultIdentityAvatar), findsWidgets);
      expect(find.textContaining('旧帖子和评论仍保留'), findsOneWidget);
      expect(find.textContaining('私人备注'), findsOneWidget);
      expect(find.textContaining('发布失败'), findsOneWidget);
      expect(find.textContaining('2027年3月13日'), findsWidgets);
      await _tap(tester, find.text('取消'));
      expect(f.api.submissions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );

  testWidgets(
    'session change hides closes delete and edit surfaces before another account can confirm',
    (tester) async {
      final f = await IdentityTestFixture.create();
      f.api.items = [
        identityTestItem(name: '私有旧名字'),
        identityTestItem(id: identityTestSecondId, name: '秋雨', original: false),
      ];
      f.api.createdCount = 2;
      await _show(tester, f);
      await _tap(tester, find.text('删除此身份').first);
      await f.sessions.logout();
      await tester.pumpAndSettle();
      expect(find.text('删除身份'), findsNothing);
      expect(find.text('私有旧名字'), findsNothing);
      expect(f.api.submissions, isEmpty);
      f.sessionApi.account = '00000000-0000-0000-0000-000000000002';
      f.sessionApi.username = 'other_user';
      f.api.items = [];
      f.api.createdCount = 0;
      await f.sessions.login('other_user', 'valid password');
      await f.controller.load();
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('identity-add')));
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '新名字',
      );
      await tester.pumpAndSettle();
      await f.sessions.logout();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('identity-nickname')), findsNothing);
      expect(find.text('新名字'), findsNothing);
      expect(f.api.submissions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );

  testWidgets(
    'creation and rename limits use server dates and large text remains scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      final f = await IdentityTestFixture.create();
      f.api.items = [identityTestItem(renameAt: DateTime.utc(2026, 11, 2))];
      f.api.createdCount = 3;
      f.api.nextCreateAt = DateTime.utc(2027, 4, 1);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: IdentityManagementScreen(
            controller: f.controller,
            sessions: f.sessions,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('identity-add')))
            .onPressed,
        isNull,
      );
      await _tap(tester, find.text('面具一'));
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('identity-nickname')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('identity-save')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
