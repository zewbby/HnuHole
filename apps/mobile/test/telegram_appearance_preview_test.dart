import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/quick_reply_preview.dart';

void main() {
  final output = Platform.environment['HNUHOLE_APPEARANCE_RENDER_DIR'];
  if (output == null) return;
  testWidgets('render quick reply proposal over existing feed', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': [
          'assets/fonts/Roboto-Regular.ttf',
          'assets/fonts/Roboto-Medium.ttf',
          'assets/fonts/Roboto-Bold.ttf',
        ],
        'HhNotoSansSC': ['assets/fonts/NotoSansSC-Variable.ttf'],
        'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final asset in entry.value) {
          loader.addFont(rootBundle.load(asset));
        }
        await loader.load();
      }
      await Directory(output).create(recursive: true);
    });
    tester.view.physicalSize = const Size(402, 806);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    final key = GlobalKey();
    try {
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const Preview()),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final bitmap = await boundary.toImage(pixelRatio: 2);
          final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
      }

      await capture('feed-appearance');
      // The first comment action is the actual existing feed button.
      await tester.tap(find.byTooltip('评论').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-reply-dialog')), findsOneWidget);
      expect(find.textContaining('回复给 ', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('quick-reply-empty');
      await tester.enterText(
        find.byKey(const ValueKey('reply-input')),
        '我也想去图书馆，周六上午可以一起。\n中午一起吃饭！',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('quick-reply');
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDisableShadows = previous;
    }
  });
}
