import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/navigation/community_material_labels.dart';
import 'package:hnuhole_mobile/src/navigation/entry_screen.dart';
import 'package:hnuhole_mobile/src/navigation/channel_directory_controller.dart';

import 'identity_test_support.dart';
import 'login_home_test_support.dart';

void main() {
  testWidgets('Chinese interface exposes Chinese speech locale for numerals', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          builder: (context, child) => CommunitySpokenLocale(child: child!),
          home: const Scaffold(body: Text('标题最多15字，正文最多3000字。')),
        ),
      );
      final data = tester
          .getSemantics(find.text('标题最多15字，正文最多3000字。'))
          .getSemanticsData();
      expect(data.locale, const Locale('zh', 'CN'));
      expect(data.label, '标题最多15字，正文最多3000字。');
    } finally {
      handle.dispose();
    }
  });

  testWidgets('login entry exposes an actionable Chinese semantic button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final directory = ChannelDirectoryController(
      repository: IdentityTestChannels(),
    );
    addTearDown(directory.dispose);
    var opened = false;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: EntryScreen(
            directory: directory,
            onLoginRequested: () => opened = true,
          ),
        ),
      );
      final node = tester.getSemantics(
        find.byKey(const ValueKey('auth-start')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(opened, isTrue);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'home profile entry is labelled in Chinese and stays actionable',
    (tester) async {
      final fixture = HomeTestFixture();
      await tester.pumpWidget(await fixture.create());
      await tester.pumpAndSettle();
      expect(find.byTooltip('My content'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('feed-account')));
      await tester.pumpAndSettle();
      expect(find.text('账号A的身份'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('SDK automatic back button is Chinese and still pops the route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [CommunityMaterialLabels.delegate],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      Scaffold(appBar: AppBar(title: const Text('设置'))),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
  });
}
