import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';

import 'dm_chat_test.dart' as chat;
import 'dm_reliability_test.dart' as p1;

void main() {
  late Directory root;
  late p1.Vault vault;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dm-ui-draft-');
    vault = p1.Vault();
  });
  tearDown(() async => root.delete(recursive: true));
  Future<DmController> controller(chat.ChatApi api) async {
    final c = DmController(
      api: api,
      chatEnabled: true,
      openStore: (_) =>
          DmStore.open(File('${root.path}/dm.sqlite'), 'ui', 'account', vault),
    );
    await c.bind(
      account: 'account',
      token: 'token',
      identities: [p1.own],
      isCurrent: () => true,
    );
    return c;
  }

  Future<void> close(DmController c) async {
    await c.detach();
    c.dispose();
  }

  testWidgets(
    'failed draft persistence is not overwritten by a later sync refresh',
    (tester) async {
      late DmController c;
      await tester.runAsync(() async {
        c = await controller(chat.ChatApi());
        await c.saveDraft(p1.own, p1.peer, '已落盘旧稿');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DmChatRoute(
            runtime: chat.ChatRuntime(c),
            own: const DmIdentity(id: p1.own, name: '本人面具'),
            peer: const DmIdentity(id: p1.peer, name: '对方当前昵称'),
            conversation: p1.conversation,
            sourcePost: p1.post,
          ),
        ),
      );
      Future<void> settleLoad() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      await settleLoad();
      final key = vault.value;
      vault.value = 'simulated-unavailable-key';
      await tester.enterText(
        find.byKey(const ValueKey('dm-input')),
        '不可丢失的新输入',
      );
      await settleLoad();
      expect(c.error, contains('草稿保存失败'));
      vault.value = key;
      await tester.runAsync(() => c.sync());
      await settleLoad();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dm-input')))
            .controller!
            .text,
        '不可丢失的新输入',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => close(c));
    },
  );
  testWidgets(
    'applied chat deletion clears the open composer text and photos',
    (tester) async {
      late DmController c;
      final api = chat.ChatApi();
      await tester.runAsync(() async {
        c = await controller(api);
        await c.saveDraft(p1.own, p1.peer, '删除前的草稿');
        final pixels = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAcAAAAFCAIAAAAG+GGPAAAAFElEQVR4nGOUXxvBgAGYMIWoIgoAfYsBLuUBRU4AAAAASUVORK5CYII=',
        );
        await c.savePhoto(p1.own, p1.peer, {
          ...chat.descriptor(dmId()),
          'sha256': hashes.sha256.convert(pixels).toString(),
          'byteLength': pixels.length,
          'width': 7,
          'height': 5,
        }, pixels);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DmChatRoute(
            runtime: chat.ChatRuntime(c),
            own: const DmIdentity(id: p1.own, name: '本人面具'),
            peer: const DmIdentity(id: p1.peer, name: '对方当前昵称'),
            conversation: p1.conversation,
            sourcePost: p1.post,
          ),
        ),
      );
      Future<void> settleLoad() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      await settleLoad();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dm-input')))
            .controller!
            .text,
        '删除前的草稿',
      );
      expect(
        tester
            .widget<HhDirectMessageScreen>(find.byType(HhDirectMessageScreen))
            .view
            .draftImages,
        hasLength(1),
      );
      await tester.runAsync(() async {
        await c.manage(c.conversations.single, 'DELETE');
        await c.sync();
      });
      await settleLoad();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dm-input')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<HhDirectMessageScreen>(find.byType(HhDirectMessageScreen))
            .view
            .draftImages,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => close(c));
    },
  );
}
