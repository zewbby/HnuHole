import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';

import '../tool/src/dm_preview_fixtures.dart';

Widget app(
  DmConversationView view, {
  Future<bool> Function(DmSendIntent)? send,
  ValueChanged<String>? draft,
  ValueChanged<DmIdentity>? identity,
  Future<List<DmImage>> Function()? pick,
  Future<void> Function(DmMessageTarget, DmMessageAction)? action,
  ValueChanged<DmMessageTarget>? retry,
  Future<void> Function(DmHistoryRequest)? loadOlder,
  Brightness brightness = Brightness.dark,
  String? fontFamily,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: HhTelegramTheme.create(brightness, fontFamily: fontFamily),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: HhDirectMessageScreen(
    view: view,
    identities: dmPreviewIdentities,
    imageBuilder: (_, image) => DmPreviewImage(image: image),
    onSend: send ?? (_) async => true,
    onDraftChanged: draft ?? (_) {},
    onIdentitySelected: identity ?? (_) {},
    onPickImages: pick ?? () async => dmPreviewImages,
    onMessageAction: action ?? (_, _) async {},
    onRetry: retry ?? (_) {},
    onImage: (_) {},
    onSource: () {},
    onBack: () {},
    onLoadOlder: loadOlder,
  ),
);

DmConversationView view({
  String scope = 'pair-a',
  String draft = '',
  int revision = 0,
  List<DmMessage> messages = const [],
  DmIdentity? self = const DmIdentity(id: 'fixture-lime', name: '青柠汽水'),
  bool locked = true,
  bool first = false,
  bool accepted = false,
  bool canSend = true,
  DmHistoryState history = DmHistoryState.complete,
  String? cursor,
  String? firstUnread,
}) => DmConversationView(
  scopeKey: scope,
  recipient: const DmIdentity(id: 'other', name: '海边的树'),
  sourceTitle: '图书馆东门现在开放吗？',
  selfIdentity: self,
  identityLocked: locked,
  firstContact: first,
  firstTextAccepted: accepted,
  canSend: canSend,
  messages: messages,
  draftText: draft,
  draftRevision: revision,
  historyState: history,
  historyCursor: cursor,
  firstUnreadMessageId: firstUnread,
);

void main() {
  final input = find.byKey(const ValueKey('dm-input'));
  final sendButton = find.byKey(const ValueKey('dm-send'));
  String currentText(WidgetTester tester) =>
      tester.widget<TextField>(input).controller!.text;

  testWidgets(
    'typed draft survives polling; explicit revision and identity pair restore it',
    (tester) async {
      await tester.pumpWidget(app(view(draft: '已保存的草稿')));
      await tester.enterText(input, '正在输入');
      await tester.pump();
      await tester.pumpWidget(app(view(draft: '旧轮询值')));
      expect(currentText(tester), '正在输入');
      await tester.pumpWidget(app(view(draft: '明确恢复', revision: 1)));
      expect(currentText(tester), '明确恢复');
      await tester.pumpWidget(app(view(scope: 'pair-b', draft: '另一个身份对的草稿')));
      expect(currentText(tester), '另一个身份对的草稿');
    },
  );

  testWidgets('local acceptance clears exactly the submitted input', (
    tester,
  ) async {
    DmSendIntent? intent;
    final savedDrafts = <String>[];
    await tester.pumpWidget(
      app(
        view(),
        send: (value) async {
          intent = value;
          return true;
        },
        draft: savedDrafts.add,
      ),
    );
    await tester.enterText(input, '下午见');
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    expect(intent!.scopeKey, 'pair-a');
    expect(intent!.identityId, dmPreviewIdentities.first.id);
    expect(intent!.text, '下午见');
    expect(currentText(tester), '');
    expect(savedDrafts.last, '');
  });

  testWidgets('rejected local save preserves unique text and attachments', (
    tester,
  ) async {
    await tester.pumpWidget(app(view(), send: (_) async => false));
    await tester.enterText(input, '不能丢失');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dm-attach')));
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    expect(currentText(tester), '不能丢失');
    expect(
      find.byKey(const ValueKey('remove-image:fixture-east-gate')),
      findsOneWidget,
    );
    expect(find.text('消息尚未保存，请重试'), findsOneWidget);
  });

  testWidgets('late acceptance never clears newly typed content', (
    tester,
  ) async {
    final result = Completer<bool>();
    await tester.pumpWidget(app(view(), send: (_) => result.future));
    await tester.enterText(input, '第一条');
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    await tester.enterText(input, '第二条还没发送');
    await tester.pump();
    result.complete(true);
    await tester.pump();
    expect(currentText(tester), '第二条还没发送');
  });

  testWidgets('late completion from another pair cannot alter its draft', (
    tester,
  ) async {
    final result = Completer<bool>();
    await tester.pumpWidget(app(view(), send: (_) => result.future));
    await tester.enterText(input, '旧会话');
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    await tester.pumpWidget(app(view(scope: 'pair-b', draft: '新会话')));
    result.complete(true);
    await tester.pump();
    expect(currentText(tester), '新会话');
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
  });

  testWidgets(
    'first identity is selected and confirmed without sending or binding',
    (tester) async {
      DmIdentity? selected;
      var sends = 0;
      await tester.pumpWidget(
        app(
          view(self: null, locked: false, first: true),
          identity: (value) => selected = value,
          send: (_) async {
            sends++;
            return true;
          },
        ),
      );
      await tester.enterText(input, '你好');
      await tester.pump();
      await tester.tap(sendButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('identity:fixture-tide')));
      await tester.pump();
      expect(selected, isNull);
      expect(sends, 0);
      await tester.tap(find.byKey(const ValueKey('dm-use-identity')));
      await tester.pumpAndSettle();
      expect(selected!.id, 'fixture-tide');
      expect(sends, 0);
      expect(currentText(tester), '你好');
    },
  );

  testWidgets('locked conversation exposes its identity without a switch', (
    tester,
  ) async {
    await tester.pumpWidget(app(view()));
    expect(find.text('青柠汽水'), findsOneWidget);
    expect(find.byKey(const ValueKey('dm-select-identity')), findsNothing);
  });

  testWidgets(
    'returning to the same pair cannot let an older completion unlock a newer send',
    (tester) async {
      final old = Completer<bool>();
      final latest = Completer<bool>();
      await tester.pumpWidget(app(view(), send: (_) => old.future));
      await tester.enterText(input, '第一轮');
      await tester.pump();
      await tester.tap(sendButton);
      await tester.pump();
      await tester.pumpWidget(app(view(scope: 'pair-b')));
      await tester.pumpWidget(
        app(view(draft: '新一轮'), send: (_) => latest.future),
      );
      await tester.tap(sendButton);
      await tester.pump();
      old.complete(true);
      await tester.pump();
      expect(currentText(tester), '新一轮');
      expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
      latest.complete(true);
      await tester.pump();
      expect(currentText(tester), '');
    },
  );

  testWidgets('attachment selection caps at nine without deleting text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        view(),
        pick: () async => [
          for (var i = 0; i < 12; i++) DmImage(id: 'i$i', description: '示意图$i'),
        ],
      ),
    );
    await tester.enterText(input, '九图');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dm-attach')));
    await tester.pump();
    expect(find.text('每次最多发送9张图片'), findsOneWidget);
    expect(currentText(tester), '九图');
    DmSendIntent? intent;
    await tester.pumpWidget(
      app(
        view(),
        send: (value) async {
          intent = value;
          return true;
        },
      ),
    );
    await tester.tap(sendButton);
    await tester.pump();
    expect(intent!.images.length, 9);
  });

  testWidgets(
    'invalid recipient preserves copyable draft and disables sending',
    (tester) async {
      await tester.pumpWidget(app(view(canSend: false, draft: '保留输入')));
      expect(tester.widget<TextField>(input).readOnly, isTrue);
      expect(currentText(tester), '保留输入');
      expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('dm-attach')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'first contact keeps image entry but blocks image send without data loss',
    (tester) async {
      var sends = 0;
      await tester.pumpWidget(
        app(
          view(first: true),
          send: (_) async {
            sends++;
            return true;
          },
        ),
      );
      await tester.enterText(input, '你好');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dm-attach')));
      await tester.pump();
      await tester.tap(sendButton);
      await tester.pump();
      expect(sends, 0);
      expect(find.text('对方回复前不允许发送图片'), findsOneWidget);
      expect(currentText(tester), '你好');
      expect(
        find.byKey(const ValueKey('remove-image:fixture-east-gate')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'waiting conversation disables send and retains visible image entry',
    (tester) async {
      await tester.pumpWidget(
        app(view(first: true, accepted: true, draft: '保留')),
      );
      expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('dm-attach')))
            .onPressed,
        isNotNull,
      );
      expect(currentText(tester), '保留');
    },
  );

  testWidgets('unknown is pending without a retry action', (tester) async {
    await tester.pumpWidget(
      app(
        view(
          messages: [
            const DmMessage(
              id: 'm',
              outgoing: true,
              time: '09:40',
              text: '结果未知',
              state: DmSendState.unknown,
            ),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('retry:m')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'explicit failure retries original message only after confirmation',
    (tester) async {
      DmMessageTarget? target;
      await tester.pumpWidget(
        app(
          view(
            messages: [
              const DmMessage(
                id: 'original',
                outgoing: true,
                time: '09:40',
                text: '失败',
                state: DmSendState.failed,
              ),
            ],
          ),
          retry: (value) => target = value,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('retry:original')));
      await tester.pumpAndSettle();
      expect(target, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(target, isNull);
      await tester.tap(find.byKey(const ValueKey('retry:original')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新发送'));
      await tester.pumpAndSettle();
      expect(target!.scopeKey, 'pair-a');
      expect(target!.messageId, 'original');
    },
  );

  testWidgets('image menu targets one image and never offers text copy', (
    tester,
  ) async {
    DmMessageTarget? target;
    DmMessageAction? action;
    await tester.pumpWidget(
      app(
        view(
          messages: [
            const DmMessage(
              id: 'group',
              outgoing: false,
              time: '09:40',
              images: dmPreviewImages,
            ),
          ],
        ),
        action: (value, selected) async {
          target = value;
          action = selected;
        },
      ),
    );
    await tester.longPress(find.byType(DmPreviewImage).first);
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
    expect(find.text('举报'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(target!.messageId, 'group');
    expect(target!.imageId, 'fixture-east-gate');
    expect(action, DmMessageAction.delete);
  });

  testWidgets(
    'recall eligibility is authoritative and success receipts are absent',
    (tester) async {
      await tester.pumpWidget(
        app(
          view(
            messages: [
              const DmMessage(
                id: 'm',
                outgoing: true,
                time: '09:40',
                text: '文字',
                canRecall: false,
              ),
            ],
          ),
        ),
      );
      await tester.longPress(find.text('文字'));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(tester.getTopLeft(find.text('复制')).dx, greaterThan(400));
      expect(find.text('撤回'), findsNothing);
      expect(find.byIcon(Icons.done_all), findsNothing);
      expect(find.byIcon(Icons.done), findsNothing);
    },
  );

  testWidgets('re-edit replaces draft without sending', (tester) async {
    var sends = 0;
    await tester.pumpWidget(
      app(
        view(
          draft: '旧草稿',
          messages: [
            const DmMessage(
              id: 'm',
              outgoing: true,
              time: '09:40',
              recalled: true,
              reeditableText: '撤回的原文',
            ),
          ],
        ),
        send: (_) async {
          sends++;
          return true;
        },
      ),
    );
    await tester.tap(find.text('重新编辑'));
    await tester.pump();
    expect(currentText(tester), '撤回的原文');
    expect(sends, 0);
  });

  testWidgets(
    'small screen and 200% text retain actions without layout overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          view(
            messages: [
              const DmMessage(
                id: 'm',
                outgoing: true,
                time: '09:40',
                text: '一段可以在大字下完整换行的消息。',
                state: DmSendState.failed,
              ),
            ],
          ),
          scale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.enterText(input, '大字输入');
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(sendButton).bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
    },
  );

  final renderDirectory = Platform.environment['HNUHOLE_DM_RENDER_DIR'];
  if (renderDirectory != null) {
    testWidgets('render actual Flutter DM scenes for visual review', (
      tester,
    ) async {
      debugDisableShadows = false;
      try {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto':
                Platform.environment['HNUHOLE_UI_RENDER_FONT'] ??
                'assets/fonts/Roboto-Regular.ttf',
            'HhNotoSansSC': 'assets/fonts/NotoSansSC-Variable.ttf',
            'MaterialIcons':
                Platform.environment['HNUHOLE_UI_RENDER_ICON_FONT'],
            'serif': Platform.environment['HNUHOLE_UI_RENDER_SERIF_FONT'],
          }.entries) {
            if (entry.value == null) continue;
            final loader = FontLoader(entry.key)
              ..addFont(
                File(entry.value!).readAsBytes().then(ByteData.sublistView),
              );
            await loader.load();
          }
        });
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Future<void> capture(
          String name,
          String scene, {
          Brightness brightness = Brightness.dark,
          double scale = 1,
          Future<void> Function()? prepare,
        }) async {
          final fixture = DmPreviewController(scene);
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: app(
                fixture.view,
                brightness: brightness,
                fontFamily: 'Roboto',
                scale: scale,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          if (prepare != null) {
            await prepare();
            await tester.pump(const Duration(milliseconds: 300));
          }
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final rendered = await boundary.toImage(pixelRatio: 2);
            final bytes = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = await Directory(renderDirectory)
                .create(recursive: true);
            await File('${directory.path}/telegram-dm-$name-v2.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            rendered.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          fixture.dispose();
        }

        await capture('dark', 'normal');
        await capture('empty', 'first-contact', brightness: Brightness.light);
        await capture('light', 'normal', brightness: Brightness.light);
        await capture('unknown', 'unknown');
        await capture(
          'failed',
          'failed',
          prepare: () async {
            await tester.ensureVisible(
              find.byKey(const ValueKey('retry:thanks')),
            );
            await tester.tap(find.byKey(const ValueKey('retry:thanks')));
          },
        );
        await capture(
          'identity',
          'first-contact',
          prepare: () async {
            await tester.tap(find.byKey(const ValueKey('dm-select-identity')));
          },
        );
        await capture(
          'image-menu',
          'normal',
          prepare: () async {
            await tester.longPress(find.byType(DmPreviewImage).first);
          },
        );
        await capture('waiting', 'waiting');
        await capture('large-text', 'normal', scale: 1.6);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
