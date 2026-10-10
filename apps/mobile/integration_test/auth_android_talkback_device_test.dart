import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

/// Actual TalkBack platform actions, product routes and encrypted draft. No
/// ensureSemantics, performSemanticsAction or fabricated accessibility features.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRunId = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'physical TalkBack navigation and independent draft restoration',
    (tester) async {
      expect(
        Platform.isAndroid && runId == 'hnuhole-android-live-matrix-20261006',
        isTrue,
      );
      expect(accountRunId, 'hnuhole-android-live-boundary-20261006');
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        {
          'phone-talkback-prepare',
          'phone-talkback-navigate',
          'phone-talkback-read',
        }.contains(phase),
        isTrue,
      );
      final c = Uri.parse(
        const String.fromEnvironment('AUTH_COMMUNITY_BASE_URL'),
      );
      final v = Uri.parse(
        const String.fromEnvironment('AUTH_VERIFIER_BASE_URL'),
      );
      validateDevelopmentOrigins(c, v);
      final scope = 'hnuhole.isolated.auth.v1|$c|$v';
      final store = AuthStore(
        FlutterAuthVault(
          namespace:
              'hnuhole.auth.v1.${AuthCrypto.domainDigest('HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1', utf8.encode(scope))}',
        ),
        scope: scope,
      );
      final marker = FlutterAuthVault(
        namespace: 'native.security.test.$runId.talkback',
      );
      final fixture =
          jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        client: createAppHttpClient(community: c, verifier: v),
      );
      final flags = <String, Object>{};
      var accepted = false;
      final priorPointers = binding.shouldPropagateDevicePointerEvents;
      final focusNodes = <int>{};
      final focusedTargets = <String>{};
      final tappedTargets = <String>{};
      var focusCount = 0, tapCount = 0;
      const targets = {
        'identity': '身份管理',
        'security': '设备与恢复凭据',
        'account': '账号与注销',
        'add': '添加身份',
        'nickname': '昵称',
        'cancel': '取消',
        'back': 'Back',
      };
      SemanticsNode? nodeById(int id) {
        final root =
            binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
        SemanticsNode? found;
        void visit(SemanticsNode node) {
          if (node.id == id) found = node;
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        if (root != null) visit(root);
        return found;
      }

      void observeAction(ui.SemanticsActionEvent event) {
        final node = nodeById(event.nodeId);
        if (node == null) return;
        final label = node.getSemanticsData().label;
        final keys = targets.entries
            .where((entry) => label.contains(entry.value))
            .map((entry) => entry.key);
        if (event.type == ui.SemanticsAction.didGainAccessibilityFocus) {
          focusCount++;
          focusNodes.add(event.nodeId);
          focusedTargets.addAll(keys);
        }
        if (event.type == ui.SemanticsAction.tap) {
          tapCount++;
          tappedTargets.addAll(keys);
        }
      }

      Future<void> stage(String value) =>
          driver.invokeMethod<void>('stage', value);
      Future<void> wait(FutureOr<bool> Function() ready, String name) =>
          _wait(tester, ready, name);
      try {
        binding.shouldPropagateDevicePointerEvents = true;
        binding.addSemanticsActionListener(observeAction);
        final original = await store.read();
        expect(
          original.registration == null &&
              original.pendingReset == null &&
              original.pendingClosure == null,
          isTrue,
        );
        var loginNeeded = original.session == null;
        if (phase == 'phone-talkback-prepare' && original.session != null) {
          try {
            await api.currentSession(original.session!.token);
          } on AuthFailure catch (error) {
            expect(error.unauthorized, isTrue);
            loginNeeded = true;
          }
        } else if (phase != 'phone-talkback-prepare') {
          expect(original.session?.accountId, fixture['accountId']);
          expect(
            AuthCrypto.domainDigest(
              'TALKBACK-SESSION',
              utf8.encode(original.session!.token),
            ),
            fixture['sessionDigest'],
          );
          expect(
            (await api.currentSession(original.session!.token)).accountId,
            fixture['accountId'],
          );
          expect(fixture['pid'] != pid, isTrue);
          expect(binding.platformDispatcher.semanticsEnabled, isTrue);
          expect(
            binding
                .platformDispatcher
                .accessibilityFeatures
                .accessibleNavigation,
            isTrue,
          );
        }
        app.main();
        await tester.pump();
        if (phase == 'phone-talkback-prepare' && loginNeeded) {
          await wait(
            () => find.text('登录或注册').evaluate().isNotEmpty,
            'explicit login',
          );
          await _tap(tester, find.text('登录或注册'));
          final username =
              'dev_${AuthCrypto.domainDigest('DEVICE-USERNAME', utf8.encode(accountRunId)).substring(0, 16)}'
                  .replaceAll('-', '_')
                  .toLowerCase();
          final password =
              'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode(accountRunId))}#9';
          await tester.enterText(
            find.byKey(const ValueKey('login-username')),
            username,
          );
          await tester.enterText(
            find.byKey(const ValueKey('login-password')),
            password,
          );
          await _tap(tester, find.text('登录并进入'));
          flags['explicitSyntheticLoginAfterGateRecovery'] = true;
        }
        await wait(
          () =>
              find.byType(ChannelTree).evaluate().isNotEmpty &&
              find.byType(AuthScreen).evaluate().isEmpty,
          'authoritative App',
        );
        final state = await store.read();
        final session = state.session!;
        final account = session.accountId;
        final current = await api.currentSession(session.token);
        expect(current.accountId, account);
        final directory = await api.identities(session.token);
        expect(
          directory.identities.isEmpty && directory.createdCount == 0,
          isTrue,
        );
        const expectedDraft = '输入法测试草稿';
        expect(
          (state.identityDrafts[account] as Map?)?['nickname'],
          expectedDraft,
        );
        if (phase == 'phone-talkback-prepare') {
          fixture['accountId'] = account;
          fixture['sessionDigest'] = AuthCrypto.domainDigest(
            'TALKBACK-SESSION',
            utf8.encode(session.token),
          );
          flags['existingNativeDraftPreserved'] = true;
        } else {
          await _tap(tester, find.byTooltip('My content'));
          await wait(
            () => find.widgetWithText(ListTile, '身份管理').evaluate().isNotEmpty,
            'settings',
          );
          if (phase == 'phone-talkback-navigate') {
            final semantics = tester
                .getSemantics(find.widgetWithText(ListTile, '身份管理'))
                .getSemanticsData();
            expect(
              semantics.label.contains('身份管理') &&
                  semantics.hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
            await stage('await-talkback-identity');
            await wait(
              () =>
                  focusedTargets.containsAll([
                    'identity',
                    'security',
                    'account',
                  ]) &&
                  tappedTargets.contains('identity') &&
                  find
                      .byKey(const ValueKey('identity-add'))
                      .evaluate()
                      .isNotEmpty,
              'actual settings focus and activation',
            );
            await stage('await-talkback-add');
            await wait(
              () =>
                  tappedTargets.contains('add') &&
                  find
                      .byKey(const ValueKey('identity-nickname'))
                      .evaluate()
                      .isNotEmpty,
              'actual identity add activation',
            );
            await stage('await-talkback-editor-cancel');
            await wait(
              () =>
                  focusedTargets.contains('nickname') &&
                  tappedTargets.contains('cancel') &&
                  find
                      .byKey(const ValueKey('identity-nickname'))
                      .evaluate()
                      .isEmpty,
              'actual nickname focus and cancel',
            );
            await stage('await-talkback-settings-back');
            await wait(
              () => find
                  .widgetWithText(ListTile, '设备与恢复凭据')
                  .evaluate()
                  .isNotEmpty,
              'return to settings',
            );
            await stage('await-talkback-security');
            await wait(
              () =>
                  tappedTargets.contains('security') &&
                  find.byType(SecurityManagementScreen).evaluate().isNotEmpty,
              'actual security activation',
            );
            await stage('await-talkback-security-back');
            await wait(
              () => find.widgetWithText(ListTile, '身份管理').evaluate().isNotEmpty,
              'return from security',
            );
            expect(
              focusNodes.length >= 4 && focusCount >= 4 && tapCount >= 4,
              isTrue,
            );
            flags['actualSettingsFocusTraversal'] = true;
            flags['actualIdentityEditorFocusAndCancel'] = true;
            flags['actualSecurityRouteAndReturn'] = true;
            fixture['navigationAccepted'] = true;
          } else {
            expect(fixture['navigationAccepted'], isTrue);
            await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
            await _tap(tester, find.byKey(const ValueKey('identity-add')));
            await wait(
              () => find
                  .byKey(const ValueKey('identity-nickname'))
                  .evaluate()
                  .isNotEmpty,
              'restored editor',
            );
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(const ValueKey('identity-nickname')),
                  )
                  .controller!
                  .text,
              expectedDraft,
            );
            await stage('await-talkback-restart-focus');
            await wait(
              () => focusedTargets.contains('nickname'),
              'actual restored nickname accessibility focus',
            );
            flags['sameSessionAndDraftRestoredInNewProcess'] = true;
            flags['actualRestoredEditorAccessibilityFocus'] = true;
          }
          flags['actualPlatformAccessibilityFocusEvents'] = focusCount;
          flags['actualPlatformAccessibilityTapEvents'] = tapCount;
          flags['distinctFocusedSemanticsNodes'] = focusNodes.length;
          flags['platformSemanticsEnabled'] =
              binding.platformDispatcher.semanticsEnabled;
          flags['platformAccessibleNavigation'] = binding
              .platformDispatcher
              .accessibilityFeatures
              .accessibleNavigation;
        }
        final after = await store.read();
        expect(after.session?.token, session.token);
        expect(
          (after.identityDrafts[account] as Map?)?['nickname'],
          expectedDraft,
        );
        final finalDirectory = await api.identities(session.token);
        expect(
          finalDirectory.identities.isEmpty && finalDirectory.createdCount == 0,
          isTrue,
        );
        await marker.write(
          jsonEncode({...fixture, 'pid': pid, 'lastPhase': phase}),
        );
        binding.reportData = {
          'phase': phase,
          'pid': pid,
          'actualApp': true,
          'actualCV': true,
          'nativeVault': true,
          'systemPasskey': false,
          'semanticsActionsInjected': false,
          'nicknameTextInjected': false,
          'identityCreated': false,
          ...flags,
        };
        accepted = true;
      } finally {
        binding.removeSemanticsActionListener(observeAction);
        binding.shouldPropagateDevicePointerEvents = priorPointers;
        if (accepted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        api.close();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: runId.isEmpty,
  );
}

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String name,
) async {
  final end = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await ready()) return;
  }
  throw StateError('TalkBack phase timed out: $name');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(
    tester,
    () => finder.evaluate().length == 1,
    'one preparation target',
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}
