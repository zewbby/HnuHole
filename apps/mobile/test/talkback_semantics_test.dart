import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/channels/channel.dart';
import 'package:hnuhole_mobile/src/navigation/channel_tree.dart';
import 'package:hnuhole_mobile/src/navigation/community_material_labels.dart';
import 'package:hnuhole_mobile/src/navigation/entry_screen.dart';
import 'package:hnuhole_mobile/src/navigation/channel_directory_controller.dart';

import 'identity_test_support.dart';

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

  testWidgets('channel has one spoken name and a working semantic tap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      const channel = Channel(
        id: 'owned-channel',
        code: 'vent',
        name: '吐槽',
        initiallyVisible: true,
        displayOrder: 0,
      );
      Channel? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChannelTree(
              channels: const [channel],
              session: ChannelTreeSession(),
              onChannelSelected: (value) => selected = value,
            ),
          ),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('吐槽'));
      final data = node.getSemanticsData();
      expect(data.label, '吐槽');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(selected, same(channel));
      expect(find.bySemanticsLabel('吐槽\n吐槽'), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('profile entry is labelled in Chinese and stays actionable', (
    tester,
  ) async {
    final directory = ChannelDirectoryController(
      repository: IdentityTestChannels(),
    );
    addTearDown(directory.dispose);
    await directory.authenticate(identityTestToken);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(
          directory: directory,
          onLoginRequested: () {},
          onProfilePressed: () => opened = true,
          onChannelSelected: (_) {},
        ),
      ),
    );
    expect(find.byTooltip('My content'), findsNothing);
    await tester.tap(find.byTooltip('我的'));
    expect(opened, isTrue);
  });

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
