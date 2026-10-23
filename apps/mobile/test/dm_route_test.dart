import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';

import 'dm_reliability_test.dart' as f;

class _RouteRuntime extends ChangeNotifier implements DmRuntime {
  _RouteRuntime(this.controller);
  @override
  final DmController controller;
  @override
  DmIdentityStatus get identityStatus => controller.available
      ? DmIdentityStatus.ready
      : DmIdentityStatus.unavailable;
  @override
  List<DmIdentity> identities = [const DmIdentity(id: f.own, name: '我的面具')];
  @override
  final void Function(BuildContext, String)? openPost = null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'offline inbox opens the exact durable pair and restores its draft',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('hnuhole-dm-route-');
      final vault = f.Vault();
      final c = DmController(
        api: f.FakeDmApi()..offline = true,
        openStore: (_) => DmStore.open(
          File('${dir.path}/dm.sqlite'),
          'test',
          'account',
          vault,
        ),
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          await c.detach();
          c.dispose();
          await dir.delete(recursive: true);
        });
      });
      await tester.runAsync(() async {
        await c.bind(
          account: 'account',
          token: 'token',
          identities: [f.own],
          isCurrent: () => true,
        );
        await c.send(f.intent('离线已保存'), peerName: '对方面具');
        await c.sync();
        await c.saveDraft(f.own, f.peer, '下一条草稿');
      });
      await tester.pumpWidget(
        MaterialApp(home: DmInboxRoute(runtime: _RouteRuntime(c))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('离线已保存'), findsOneWidget);
      await tester.tap(find.text('对方面具'));
      await tester.pump();
      for (var i = 0; i < 20 && find.text('下一条草稿').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.descendant(
          of: find.byType(HhDirectMessageScreen),
          matching: find.text('离线已保存'),
        ),
        findsOneWidget,
      );
      expect(find.text('下一条草稿'), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-attach')), findsNothing);
      // Losing authority closes the visible projection as well as controller reads.
      var detached = false;
      final disconnect = c.detach().then((_) => detached = true);
      for (var i = 0; i < 50 && !detached; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(detached, isTrue);
      await disconnect;
      await tester.pumpAndSettle();
      expect(find.text('离线已保存'), findsNothing);
      expect(find.text('下一条草稿'), findsNothing);
      expect(find.text('请恢复当前账号后查看私信'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
