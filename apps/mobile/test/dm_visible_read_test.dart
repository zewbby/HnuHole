import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';

void main() {
  testWidgets(
    'reading reports only rendered incoming rows and text phase hides unsupported actions',
    (tester) async {
      final visible = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: HhDirectMessageScreen(
            view: DmConversationView(
              scopeKey: 'account:pair',
              recipient: const DmIdentity(id: 'peer', name: '对方'),
              selfIdentity: const DmIdentity(id: 'own', name: '本人'),
              sourceTitle: '原帖',
              messages: List.generate(
                50,
                (i) => DmMessage(
                  id: 'm$i',
                  outgoing: i == 49,
                  time: '12:00',
                  text: '消息 $i\n足够的高度\n仅在可见时阅读',
                ),
              ),
            ),
            identities: const [],
            imageBuilder: (_, _) => const SizedBox.shrink(),
            onSend: (_) async => true,
            onDraftChanged: (_) {},
            onIdentitySelected: (_) {},
            onPickImages: () async => [],
            onMessageAction: (_, _) async {},
            onRetry: (_) {},
            onImage: (_) {},
            onSource: () {},
            onBack: () {},
            textOnly: true,
            onVisible: visible.addAll,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(visible, isNotEmpty);
      expect(visible.contains('m0'), isFalse);
      expect(visible.contains('m49'), isFalse);
      expect(visible.length, lessThan(15));
      expect(find.byKey(const ValueKey('dm-attach')), findsNothing);
      await tester.longPress(find.text('消息 49\n足够的高度\n仅在可见时阅读'));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsNothing);
      expect(find.text('复制'), findsOneWidget);
    },
  );
}
