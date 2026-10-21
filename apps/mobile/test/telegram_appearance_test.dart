import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/posts/post_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('declared app font families have real packaged font bytes', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in ['Roboto', 'HhNotoSansSC']) {
      final font = manifest.cast<Map<String, dynamic>>().singleWhere(
        (item) => item['family'] == family,
      );
      for (final face in font['fonts'] as List) {
        expect(
          (await rootBundle.load(face['asset'] as String)).lengthInBytes,
          greaterThan(1000),
        );
      }
    }
  });
  testWidgets('actual app root uses shared appearance outside the feed route', (
    tester,
  ) async {
    app.main();
    await tester.pump();
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = material.theme!;
    expect(theme.extension<HhTelegramPalette>(), isNotNull);
    expect(theme.textTheme.bodyLarge!.fontFamily, 'Roboto');
    expect(theme.colorScheme.onSurfaceVariant, PostTheme.muted);
    expect(material.darkTheme!.brightness, Brightness.dark);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'legacy post override keeps typography sans and existing page geometry',
    (tester) async {
      const padding = EdgeInsets.symmetric(horizontal: 21, vertical: 13);
      final original = ThemeData(
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          toolbarHeight: 63,
          centerTitle: true,
          titleSpacing: 19,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          contentPadding: padding,
        ),
      );
      final updated = HhTelegramTheme.applyAppearance(original);
      expect(
        updated.appBarTheme.toolbarHeight,
        original.appBarTheme.toolbarHeight,
      );
      expect(updated.appBarTheme.centerTitle, original.appBarTheme.centerTitle);
      expect(
        updated.appBarTheme.titleSpacing,
        original.appBarTheme.titleSpacing,
      );
      expect(updated.inputDecorationTheme.contentPadding, padding);
      expect(
        updated.textTheme.bodyLarge!.fontSize,
        original.textTheme.bodyLarge!.fontSize,
      );
      late ThemeData post;
      await tester.pumpWidget(
        MaterialApp(
          theme: updated,
          home: Builder(
            builder: (context) {
              post = PostTheme.of(context);
              return Theme(
                data: post,
                child: const Scaffold(body: Text('正文')),
              );
            },
          ),
        ),
      );
      expect(post.textTheme.bodyLarge!.fontFamily, 'Roboto');
      expect(PostTheme.dialogBody.fontFamily, 'Roboto');
      expect(PostTheme.dialogQuestion.fontFamilyFallback, ['HhNotoSansSC']);
      expect(post.colorScheme.primary, HhTelegramPalette.light.accent);
      expect(post.scaffoldBackgroundColor, HhTelegramPalette.light.surface);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
