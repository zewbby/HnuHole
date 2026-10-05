import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import '../test/identity_test_support.dart';

// Real platform vault and distinct app processes; explicit test APIs only.
// Injected composing events, text scaling and semantics do not prove OEM IME,
// TalkBack, a physical device, or the App -> actual C/V network path.
void registerIdentityDeviceScenarios(
  String phase,
  String namespace,
  bool native,
) {
  testWidgets(
    'native identity draft and original intent survive distinct processes and account switch',
    (tester) async {
      final owned = '$namespace.identity';
      final store = AuthStore(FlutterAuthVault(namespace: owned), scope: owned);
      final processVault = FlutterAuthVault(namespace: '$owned.pid');
      final sessionApi = IdentityTestSessionApi();
      final directory = ChannelDirectoryController(
        repository: IdentityTestChannels(),
      );
      final sessions = AuthSessionController(
        api: sessionApi,
        store: store,
        directory: directory,
      );
      final api = IdentityTestApi();
      final controller = IdentityManagementController(
        api: api,
        store: store,
        sessions: sessions,
      );
      addTearDown(() {
        controller.dispose();
        sessions.dispose();
        directory.dispose();
        store.dispose();
      });
      const other = '00000000-0000-0000-0000-000000000002';
      const otherUser = 'platform_other';
      final key = AuthCrypto.encode(List.filled(16, 29));
      if (phase == 'write') {
        await store.update(
          (_) => AuthState(
            session: SessionRecord(
              token: identityTestToken,
              accountId: identityTestAccount,
              expiresAt: identityTestExpiry,
            ),
          ),
        );
      } else {
        final previous =
            jsonDecode((await processVault.read())!) as Map<String, dynamic>;
        expect(previous['pid'], isNot(pid));
        final restored = await store.read();
        expect(restored.identityDrafts[identityTestAccount]['nickname'], '海风秋');
        expect(restored.identityChanges[other]['key'], key);
      }
      await sessions.start();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: IdentityManagementScreen(
              controller: controller,
              sessions: sessions,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final add = find.byKey(const ValueKey('identity-add'));
        expect(tester.getSemantics(add).label, contains('添加身份'));
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        final nickname = find.byKey(const ValueKey('identity-nickname'));
        if (phase == 'write') {
          await tester.showKeyboard(nickname);
          await tester.pumpAndSettle();
          final draftBeforeComposing = jsonEncode(
            store.current!.identityDrafts,
          );
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '海😀风',
              selection: TextSelection.collapsed(offset: 4),
              composing: TextRange(start: 0, end: 4),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(nickname).controller!.text,
            '海😀风',
          );
          expect(
            jsonEncode(store.current!.identityDrafts),
            draftBeforeComposing,
            reason:
                'Active composing input must not replace any committed draft',
          );
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '海😀风',
              selection: TextSelection.collapsed(offset: 4),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<TextFormField>(nickname).controller!.text, '海风');
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('identity-save')),
                )
                .onPressed,
            isNull,
          );
          await tester.enterText(nickname, '海风秋');
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('取消'));
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(
            store.current!.identityDrafts[identityTestAccount]['nickname'],
            '海风秋',
          );
          await store.update(
            (s) => s.copyWith(
              identityChanges: {
                other: {
                  'v': 1,
                  'key': key,
                  'username': otherUser,
                  'operation': 'CREATE',
                  'state': 'UNKNOWN',
                  'nickname': '北风',
                },
              },
            ),
          );
          await processVault.write(jsonEncode({'pid': pid}));
        } else {
          expect(
            tester.widget<TextFormField>(nickname).controller!.text,
            '海风秋',
          );
          sessionApi.account = other;
          sessionApi.username = otherUser;
          await sessions.login(otherUser, 'test password');
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('identity-nickname')), findsNothing);
          expect(find.text('海风秋'), findsNothing);
          await controller.load();
          await tester.pumpAndSettle();
          expect(controller.status, IdentityManagementStatus.retryRequired);
          expect(api.queries, isNotEmpty);
          expect(api.queries.every((query) => query['key'] == key), isTrue);
          expect(api.submissions, isEmpty);
          expect(store.current!.identityChanges[other]['key'], key);
          expect(
            store.current!.identityDrafts[identityTestAccount]['nickname'],
            '海风秋',
          );
          expect(controller.initialNickname, isEmpty);
          await store.update((_) => const AuthState());
          await processVault.write(jsonEncode({'cleaned': true}));
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    },
    skip: !native || phase.isEmpty,
  );
}
