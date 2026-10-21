import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/x_detail_layout_preview.dart';

void main() {
  final output = Platform.environment['HNUHOLE_DETAIL_LAYOUT_RENDER_DIR'];
  if (output == null) return;
  testWidgets('render isolated X detail layout proposal', (tester) async {
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
        for (final path in entry.value) {
          loader.addFont(rootBundle.load(path));
        }
        await loader.load();
      }
      await Directory(output).create(recursive: true);
    });
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const XDetailLayoutPreview()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/x-detail-hnuhole.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
}
