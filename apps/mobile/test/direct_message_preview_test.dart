import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/direct_message_gallery.dart';

import 'package:hnuhole_mobile/src/navigation/app_navigation.dart';

void main() {
  testWidgets(
    'four fixed destinations distinguish notifications and private messages',
    (tester) async {
      await tester.pumpWidget(const DmPreviewApp());
      final inbox = find.byKey(const ValueKey('conversation:normal'));
      expect(inbox, findsOneWidget);
      expect(find.byTooltip('首页'), findsOneWidget);
      expect(find.byTooltip('消息'), findsOneWidget);
      expect(find.byTooltip('私信'), findsOneWidget);
      expect(find.byTooltip('我的'), findsOneWidget);
      expect(
        tester.widget<HhAppNavigation>(find.byType(HhAppNavigation)).selected,
        AppDestination.directMessages,
      );
      await tester.tap(find.byTooltip('消息'));
      await tester.pumpAndSettle();
      expect(find.text('预览未连接通知服务'), findsOneWidget);
      expect(inbox, findsNothing);
      expect(
        tester.widget<HhAppNavigation>(find.byType(HhAppNavigation)).selected,
        AppDestination.messages,
      );
      await tester.tap(find.byTooltip('私信'));
      await tester.pumpAndSettle();
      expect(inbox, findsOneWidget);
      expect(
        tester.widget<HhAppNavigation>(find.byType(HhAppNavigation)).selected,
        AppDestination.directMessages,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'development gallery is labelled and opens the actual chat component',
    (tester) async {
      await tester.pumpWidget(const DmPreviewApp());
      expect(find.text('开发预览 · 不连接私信服务'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation:normal')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dm-input')), findsOneWidget);
      expect(find.text('开发预览 · 不连接私信服务'), findsOneWidget);
      expect(find.text('私密会话'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  final directory = Platform.environment['HNUHOLE_DM_RENDER_DIR'];
  if (directory != null) {
    testWidgets('render the gallery inbox with real bundled fonts', (
      tester,
    ) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': 'assets/fonts/Roboto-Regular.ttf',
            'HhNotoSansSC': 'assets/fonts/NotoSansSC-Variable.ttf',
          }.entries) {
            await (FontLoader(
              entry.key,
            )..addFont(rootBundle.load(entry.value))).load();
          }
          final icon = Platform.environment['HNUHOLE_UI_RENDER_ICON_FONT'];
          if (icon != null) {
            await (FontLoader(
                  'MaterialIcons',
                )..addFont(File(icon).readAsBytes().then(ByteData.sublistView)))
                .load();
          }
        });
        tester.view.physicalSize = const Size(402, 893);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: key, child: const DmPreviewApp()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final result = await boundary.toImage(pixelRatio: 2);
          final bytes = await result.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/telegram-inbox-light.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          result.dispose();
        });
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }
}
