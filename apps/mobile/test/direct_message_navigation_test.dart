import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_inbox.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_timeline.dart';

import 'direct_message_screen_test.dart' as chat;

const self = DmIdentity(id: 'self', name: '青柠汽水');
const other = DmIdentity(id: 'other', name: '科科');
List<DmMessage> messages(int start, int end) => [
  for (var i = start; i < end; i++)
    DmMessage(
      id: 'm$i',
      outgoing: i.isOdd,
      time: '12:00',
      text: '第$i条消息：保持阅读位置，不重复发送。',
      dayLabel: i < 0 ? '10月20日' : '10月21日',
    ),
];

Widget inbox({
  String scope = 'account-generation/self',
  DmIdentity identity = self,
  List<DmInboxEntry> entries = const [],
  ValueChanged<DmInboxTarget>? open,
  ValueChanged<DmIdentity>? select,
  VoidCallback? addIdentity,
  List<DmInboxIdentity>? identities,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: HhTelegramTheme.create(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: HhDmInboxScreen(
    scopeKey: scope,
    identity: identity,
    identities:
        identities ??
        const [
          DmInboxIdentity(self, unread: 3),
          DmInboxIdentity(other, unread: 8),
        ],
    entries: entries,
    onOpen: open ?? (_) {},
    onIdentitySelected: select ?? (_) {},
    onAddIdentity: addIdentity,
  ),
);

const entry = DmInboxEntry(
  id: 'pair',
  selfIdentityId: 'self',
  recipient: other,
  preview: '收到，谢谢！',
  time: '21:56',
  unread: 3,
);

void main() {
  testWidgets('scope replacement before menu first frame removes stale popup', (
    tester,
  ) async {
    var additions = 0;
    await tester.pumpWidget(inbox(addIdentity: () => additions++));
    await tester.tap(find.byKey(const ValueKey('dm-inbox-identity')));
    // Replace the authority before the popup header has ever built.
    await tester.pumpWidget(
      inbox(
        scope: 'replacement',
        identity: other,
        addIdentity: () => additions++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('切换身份'), findsNothing);
    expect(find.byKey(const ValueKey('inbox-add-identity:2')), findsNothing);
    expect(additions, 0);
    expect(tester.takeException(), isNull);
  });

  final renderDirectory =
      Platform.environment['HNUHOLE_DM_IDENTITY_RENDER_DIR'];
  if (renderDirectory != null) {
    testWidgets(
      'render actual inbox identity selector collapsed and expanded',
      (tester) async {
        final oldShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = oldShadows);
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': 'assets/fonts/Roboto-Regular.ttf',
            'HhNotoSansSC': 'assets/fonts/NotoSansSC-Variable.ttf',
            'MaterialIcons':
                Platform.environment['HNUHOLE_UI_RENDER_ICON_FONT'],
          }.entries) {
            if (entry.value == null) continue;
            await (FontLoader(entry.key)..addFont(
                  File(entry.value!).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          }
        });
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: inbox(
              identities: const [DmInboxIdentity(self)],
              addIdentity: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String name) async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final picture = await boundary.toImage(pixelRatio: 2);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(renderDirectory).create(recursive: true);
            await File('$renderDirectory/dm-identity-$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }

        await capture('collapsed');
        await tester.tap(find.byKey(const ValueKey('dm-inbox-identity')));
        await tester.pumpAndSettle();
        await capture('expanded');
        expect(tester.takeException(), isNull);
        debugDisableShadows = oldShadows;
      },
    );
  }

  testWidgets(
    'compact dropdown mirrors content, fills slots and opens add flow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var additions = 0;
      await tester.pumpWidget(
        inbox(
          identities: const [DmInboxIdentity(self)],
          addIdentity: () => additions++,
        ),
      );
      expect(find.text('最近聊天'), findsNothing);
      expect(find.text('搜索'), findsOneWidget);
      final trigger = find.byKey(const ValueKey('dm-inbox-identity'));
      expect(tester.getSize(trigger).height, greaterThanOrEqualTo(48));
      expect(
        tester.getRect(trigger).right,
        closeTo(
          tester.getRect(find.byKey(const ValueKey('dm-search'))).right,
          1,
        ),
      );
      final arrow = find.descendant(
        of: trigger,
        matching: find.byIcon(Icons.chevron_right_rounded),
      );
      final name = find.descendant(of: trigger, matching: find.text(self.name));
      expect(tester.getCenter(arrow).dx, lessThan(tester.getCenter(name).dx));
      expect(find.text('当前身份'), findsNothing);
      expect(tester.getCenter(arrow).dy, closeTo(tester.getCenter(name).dy, 1));
      await tester.tap(find.byKey(const ValueKey('dm-search')));
      await tester.enterText(find.byKey(const ValueKey('dm-search')), '查找');
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        find.byKey(const ValueKey('inbox-add-identity:1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inbox-add-identity:2')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('inbox-identity:self'))).dy,
        greaterThan(tester.getBottomLeft(trigger).dy),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('inbox-identity:self'))).right,
        closeTo(tester.getRect(trigger).right, 1),
      );
      await tester.tap(find.byKey(const ValueKey('inbox-add-identity:1')));
      await tester.pumpAndSettle();
      expect(additions, 1);
    },
  );

  testWidgets(
    'full identity menu has no add slot and stale scope dismisses it',
    (tester) async {
      var additions = 0;
      const third = DmIdentity(id: 'third', name: '第三个身份');
      await tester.pumpWidget(
        inbox(
          identities: const [
            DmInboxIdentity(self),
            DmInboxIdentity(other),
            DmInboxIdentity(third),
          ],
          addIdentity: () => additions++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dm-inbox-identity')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      await tester.pumpWidget(
        inbox(
          scope: 'replacement',
          identity: other,
          addIdentity: () => additions++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('切换身份'), findsNothing);
      expect(find.text('第三个身份'), findsNothing);
      expect(additions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('identity dropdown keeps last row above system navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    DmIdentity? chosen;
    await tester.pumpWidget(inbox(select: (identity) => chosen = identity));
    await tester.tap(find.byTooltip('切换身份'));
    await tester.pumpAndSettle();
    expect(find.text('切换身份'), findsOneWidget);
    final last = find.byKey(const ValueKey('inbox-identity:other'));
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(844 - 48));
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(chosen, other);
  });

  testWidgets(
    'first-send identity confirmation stays above system navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(chat.app(chat.view(locked: false, first: true)));
      await tester.tap(find.byKey(const ValueKey('dm-select-identity')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('dm-use-identity'));
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(844 - 48));
    },
  );

  testWidgets(
    'a decreasing unread count does not announce a new message while browsing',
    (tester) async {
      List<DmInboxEntry> rows(int unread) => [
        for (var i = 0; i < 30; i++)
          DmInboxEntry(
            id: 'p$i',
            selfIdentityId: 'self',
            recipient: other,
            preview: '会话$i',
            time: '$i',
            unread: unread,
          ),
      ];
      await tester.pumpWidget(inbox(entries: rows(1)));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.pumpWidget(inbox(entries: rows(0)));
      await tester.pump();
      expect(find.byKey(const ValueKey('dm-inbox-new')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late enqueue from a different sending identity cannot clear the current draft',
    (tester) async {
      final enqueue = Completer<bool>();
      await tester.pumpWidget(
        chat.app(
          chat.view(self: self, draft: '原身份文字'),
          send: (_) => enqueue.future,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dm-send')));
      await tester.pump();
      await tester.pumpWidget(
        chat.app(chat.view(self: other, draft: '新身份文字', revision: 1)),
      );
      enqueue.complete(true);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dm-input')))
            .controller!
            .text,
        '新身份文字',
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('dm-send')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'opening only emits the selected pair; inbox and identity switch do not clear unread',
    (tester) async {
      final opened = <DmInboxTarget>[];
      final selected = <DmIdentity>[];
      await tester.pumpWidget(
        inbox(entries: [entry], open: opened.add, select: selected.add),
      );
      expect(find.text('3'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.tap(find.byKey(const ValueKey('conversation:pair')));
      expect(opened.single.scopeKey, 'account-generation/self');
      expect(opened.single.identityId, 'self');
      expect(opened.single.conversationId, 'pair');
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dm-inbox-identity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inbox-identity:other')));
      await tester.pumpAndSettle();
      expect(selected.single.id, 'other');
      expect(opened.length, 1);
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets(
    'search is local and identity scoped; hidden entry is an exact open intent',
    (tester) async {
      DmInboxTarget? opened;
      await tester.pumpWidget(
        inbox(
          entries: const [
            entry,
            DmInboxEntry(
              id: 'hidden',
              selfIdentityId: 'self',
              recipient: other,
              preview: '[图片]',
              time: '昨天',
              privateNote: '图书馆',
              hidden: true,
            ),
            DmInboxEntry(
              id: 'foreign',
              selfIdentityId: 'other',
              recipient: self,
              preview: '不能泄漏',
              time: '昨天',
              privateNote: '图书馆',
            ),
          ],
          open: (value) => opened = value,
        ),
      );
      expect(find.byKey(const ValueKey('conversation:hidden')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('dm-search')), '图书馆');
      await tester.pump();
      expect(find.byKey(const ValueKey('conversation:hidden')), findsOneWidget);
      expect(find.byKey(const ValueKey('conversation:foreign')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('conversation:hidden')));
      expect(opened!.conversationId, 'hidden');
    },
  );

  testWidgets(
    'scope switch clears the search and never carries foreign rows into new inbox',
    (tester) async {
      await tester.pumpWidget(inbox(entries: [entry]));
      await tester.enterText(find.byKey(const ValueKey('dm-search')), '科科');
      await tester.pumpWidget(
        inbox(
          scope: 'account-generation/other',
          identity: other,
          entries: [entry],
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dm-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const ValueKey('conversation:pair')), findsNothing);
      expect(find.text('还没有会话'), findsOneWidget);
    },
  );

  testWidgets(
    'inbox retains row positions until new-message banner is explicitly opened',
    (tester) async {
      final rows = [
        for (var i = 0; i < 30; i++)
          DmInboxEntry(
            id: 'p$i',
            selfIdentityId: 'self',
            recipient: other,
            preview: '会话$i',
            time: '$i',
          ),
      ];
      await tester.pumpWidget(inbox(entries: rows));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final oldY = tester
          .getTopLeft(find.byKey(const ValueKey('conversation:p4')))
          .dy;
      await tester.pumpWidget(inbox(entries: [rows.last, ...rows.take(29)]));
      await tester.pump();
      expect(find.byKey(const ValueKey('dm-inbox-new')), findsOneWidget);
      // The banner itself is before the rows; row order remains the old order.
      final fourth = tester
          .getTopLeft(find.byKey(const ValueKey('conversation:p4')))
          .dy;
      expect((fourth - oldY).abs(), lessThan(60));
      await tester.ensureVisible(find.byKey(const ValueKey('dm-inbox-new')));
      await tester.tap(find.byKey(const ValueKey('dm-inbox-new')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('conversation:p29'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('conversation:p0'))).dy,
        ),
      );
    },
  );

  ScrollPosition timelinePosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(HhDmTimeline),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  String visibleId(WidgetTester tester, List<DmMessage> data) =>
      data.firstWhere((m) {
        final found = find.byKey(ValueKey('message:${m.id}'));
        return found.evaluate().isNotEmpty &&
            tester.getTopLeft(found).dy > 180 &&
            tester.getBottomLeft(found).dy < 480;
      }).id;

  testWidgets(
    'prepending local history preserves the visible message and its pixel position',
    (tester) async {
      final initial = messages(0, 40);
      await tester.pumpWidget(chat.app(chat.view(messages: initial)));
      timelinePosition(tester).jumpTo(380);
      await tester.pump();
      final id = visibleId(tester, initial);
      final before = tester.getTopLeft(find.byKey(ValueKey('message:$id'))).dy;
      await tester.pumpWidget(
        chat.app(chat.view(messages: [...messages(-20, 0), ...initial])),
      );
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(ValueKey('message:$id'))).dy,
        closeTo(before, 1),
      );
    },
  );

  testWidgets(
    'new incoming message preserves history position and offers return to latest',
    (tester) async {
      final initial = messages(0, 40);
      await tester.pumpWidget(chat.app(chat.view(messages: initial)));
      timelinePosition(tester).jumpTo(380);
      await tester.pump();
      final id = visibleId(tester, initial);
      final before = tester.getTopLeft(find.byKey(ValueKey('message:$id'))).dy;
      await tester.pumpWidget(
        chat.app(
          chat.view(
            messages: [
              ...initial,
              const DmMessage(
                id: 'new',
                outgoing: false,
                time: '12:01',
                text: '新到的消息',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(ValueKey('message:$id'))).dy,
        closeTo(before, 1),
      );
      expect(find.byTooltip('回到最新消息'), findsOneWidget);
      await tester.tap(find.byTooltip('回到最新消息'));
      await tester.pumpAndSettle();
      expect(timelinePosition(tester).pixels, closeTo(0, 1));
    },
  );

  testWidgets(
    'history failure is retryable without deleting messages or changing pair',
    (tester) async {
      var calls = 0;
      final requests = <DmHistoryRequest>[];
      await tester.pumpWidget(
        chat.app(
          chat.view(
            messages: messages(0, 2),
            history: DmHistoryState.available,
            cursor: 'older-than-m0',
          ),
          loadOlder: (request) async {
            requests.add(request);
            calls++;
            throw StateError('local store busy');
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dm-load-older')));
      await tester.pumpAndSettle();
      expect(find.text('历史消息加载失败，重试'), findsOneWidget);
      expect(find.byKey(const ValueKey('message:m1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dm-load-older')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(requests.last.scopeKey, 'pair-a');
      expect(requests.last.before, 'older-than-m0');
    },
  );

  testWidgets(
    'late history completion cannot show an error in a different pair',
    (tester) async {
      final load = Completer<void>();
      await tester.pumpWidget(
        chat.app(
          chat.view(history: DmHistoryState.available),
          loadOlder: (_) => load.future,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dm-load-older')));
      await tester.pump();
      await tester.pumpWidget(chat.app(chat.view(scope: 'pair-b')));
      load.completeError(StateError('old pair failure'));
      await tester.pump();
      expect(find.text('历史消息加载失败，重试'), findsNothing);
      expect(find.text('还没有消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date separators and first unread boundary are projection driven',
    (tester) async {
      await tester.pumpWidget(
        chat.app(chat.view(messages: messages(-1, 2), firstUnread: 'm0')),
      );
      expect(find.text('10月20日'), findsOneWidget);
      expect(find.text('10月21日'), findsOneWidget);
      expect(find.text('以下是未读消息'), findsOneWidget);
    },
  );

  testWidgets(
    'keyboard leaves send reachable and polling preserves Chinese composing text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(chat.app(chat.view()));
      await tester.tap(find.byKey(const ValueKey('dm-input')));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'nihao',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pumpWidget(chat.app(chat.view(draft: '旧草稿')));
      final value = tester
          .widget<TextField>(find.byKey(const ValueKey('dm-input')))
          .controller!
          .value;
      expect(value.composing, const TextRange(start: 0, end: 5));
      expect(value.text, 'nihao');
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('dm-send'))).dy,
        lessThanOrEqualTo(500),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('360dp inbox supports 200 percent text without dropping unread', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(inbox(entries: [entry], scale: 2));
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
