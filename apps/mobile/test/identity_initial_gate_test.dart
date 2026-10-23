import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/identity/identity_initial_gate.dart';

import 'identity_test_support.dart';

Widget gate(IdentityTestFixture f, {Key? boundary}) => RepaintBoundary(
  key: boundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: HhTelegramTheme.create(Brightness.light),
    home: IdentityInitialGate(
      controller: f.controller,
      sessions: f.sessions,
      child: const Scaffold(body: Text('社区目录')),
    ),
  ),
);
void main() {
  testWidgets(
    'timed out initial avatar recovers then legal nickname completes gate once',
    (tester) async {
      final api = IdentityAvatarTestApi()..drops = 1;
      final f = await IdentityTestFixture.create(api: api);
      await f.controller.load();
      const id = '10000000-0000-4000-8000-000000000001';
      expect(
        await f.controller.uploadAvatar(
          id,
          Uint8List.fromList([1]),
          'image/png',
        ),
        isNull,
      );
      await tester.pumpWidget(gate(f));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '恢复海风',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('identity-save')));
      await tester.tap(find.byKey(const ValueKey('identity-save')));
      await tester.pumpAndSettle();
      expect(find.text('社区目录'), findsOneWidget);
      expect(api.submissions.single['avatar'], 'avatar-v1:$id');
      expect(api.uploads, [id]);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
  testWidgets(
    'zero identity entry cannot dismiss by outside/back and waits for authoritative creation',
    (tester) async {
      final f = await IdentityTestFixture.create();
      await tester.pumpWidget(gate(f));
      await tester.pumpAndSettle();
      expect(find.text('设置你的初始身份'), findsOneWidget);
      expect(find.text('社区目录'), findsNothing);
      await tester.tapAt(const Offset(2, 2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('设置你的初始身份'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '初始海风',
      );
      await tester.pumpAndSettle();
      f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
      await tester.ensureVisible(find.byKey(const ValueKey('identity-save')));
      await tester.tap(find.byKey(const ValueKey('identity-save')));
      await tester.pumpAndSettle();
      expect(find.text('社区目录'), findsNothing);
      expect(f.controller.hasPending, isTrue);
      f.api.queryOutcome = IdentityChangeOutcome(
        committed: true,
        operation: IdentityOperation.create,
        identityId: identityTestId,
        sessionExpiresAt: identityTestRenewed,
      );
      f.api.items = [identityTestItem()];
      f.api.createdCount = 1;
      await f.controller.reconcilePending();
      await tester.pumpAndSettle();
      expect(find.text('社区目录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
  testWidgets(
    'existing identity stays in community while avatar mutation is unknown',
    (tester) async {
      final f = await IdentityTestFixture.create(
        api: IdentityTestApi()
          ..items = [identityTestItem()]
          ..createdCount = 1,
      );
      await tester.pumpWidget(gate(f));
      await tester.pumpAndSettle();
      expect(find.text('社区目录'), findsOneWidget);
      f.api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
      await f.controller.changeAvatar(identityTestId, 'default-v1');
      await tester.pumpAndSettle();
      expect(find.text('社区目录'), findsOneWidget);
      expect(find.text('设置你的初始身份'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
  testWidgets(
    '360dp initial dialog keyboard has reachable save and Telegram rendering',
    (tester) async {
      final render = Platform.environment['HNUHOLE_IDENTITY_RENDER_DIR'];
      if (render != null) {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': 'assets/fonts/Roboto-Regular.ttf',
            'HhNotoSansSC': 'assets/fonts/NotoSansSC-Variable.ttf',
            'MaterialIcons':
                Platform.environment['HNUHOLE_UI_RENDER_ICON_FONT'],
          }.entries) {
            if (entry.value != null) {
              await (FontLoader(entry.key)..addFont(
                    File(entry.value!).readAsBytes().then(ByteData.sublistView),
                  ))
                  .load();
            }
          }
        });
      }
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      final f = await IdentityTestFixture.create();
      final key = GlobalKey();
      await tester.pumpWidget(gate(f, boundary: key));
      await tester.pumpAndSettle();
      Future<void> snapshot(String name) async {
        if (render == null) return;
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(render).create(recursive: true);
          await File('$render/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await snapshot('identity-initial-360');
      tester.view.viewInsets = const FakeViewPadding(bottom: 310);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '海风',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('identity-save')));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const ValueKey('identity-save')));
      expect(rect.bottom, lessThanOrEqualTo(470));
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(tester.takeException(), isNull);
      await snapshot('identity-initial-360-keyboard');
      await tester.tap(find.byKey(const ValueKey('identity-save')));
      await tester.pumpAndSettle();
      expect(find.text('社区目录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
}
