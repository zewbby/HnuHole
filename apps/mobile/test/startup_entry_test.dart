import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

void main() {
  testWidgets('startup suspension shows welcome without a session error page', (
    tester,
  ) async {
    final directory = ChannelDirectoryController(
      repository: IdentityTestChannels(),
    );
    addTearDown(directory.dispose);
    directory.suspend();
    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(
          directory: directory,
          restoringSession: true,
          onLoginRequested: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-start')), findsOneWidget);
    expect(find.text('会话暂时无法确认，请重试。'), findsNothing);
    expect(find.text('重新核对会话'), findsNothing);
    directory.signOut();
    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(directory: directory, onLoginRequested: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-start')), findsOneWidget);
    expect(find.text('重新核对会话'), findsNothing);
  });
}
