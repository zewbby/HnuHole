import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

/// One owned build, several fresh App processes. All sessions, registrations,
/// credentials and result receipts come from the actual product and C/V.
/// Host proxy modes and device ordering must be captured separately; this
/// fixture alone cannot prove a response was deliberately lost by the proxy.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const run = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRun = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'actual Android batch boundaries',
    (tester) async {
      expect(
        Platform.isAndroid && run == 'hnuhole-android-live-matrix-20261006',
        true,
      );
      expect(accountRun == 'hnuhole-android-live-batch-20261007', true);
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        const {
          'batch-register',
          'batch-phone-draft',
          'batch-companion-draft',
          'batch-phone-retake',
          'batch-account-isolation',
          'batch-passkey-drop',
          'batch-passkey-reconcile',
          'batch-passkey-origin-reject',
          'batch-passkey-rejected-reconcile',
          'batch-passkey-route-cancel',
          'batch-passkey-remove-existing',
          'batch-gate-session-recover',
          'batch-passkey-timeout',
          'batch-passkey-ack-interrupted-success',
        }.contains(phase),
        true,
      );
      final c = Uri.parse(
        const String.fromEnvironment('AUTH_COMMUNITY_BASE_URL'),
      );
      final v = Uri.parse(
        const String.fromEnvironment('AUTH_VERIFIER_BASE_URL'),
      );
      validateDevelopmentOrigins(c, v);
      final scope = 'hnuhole.isolated.auth.v1|$c|$v';
      final digest = AuthCrypto.domainDigest(
        'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1',
        utf8.encode(scope),
      );
      final store = AuthStore(
        FlutterAuthVault(namespace: 'hnuhole.auth.v1.$digest'),
        scope: scope,
      );
      final marker = FlutterAuthVault(
        namespace: 'native.security.test.$accountRun.batch',
      );
      final fixture =
          jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        passkeyRpId: developmentPasskeyRp(community: c, verifier: v),
        client: createAppHttpClient(community: c, verifier: v),
      );
      String username(String owner) =>
          'dev_${AuthCrypto.domainDigest('DEVICE-USERNAME', utf8.encode('$accountRun-$owner')).substring(0, 16)}'
              .replaceAll('-', '_')
              .toLowerCase();
      String password(String owner) =>
          'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode('$accountRun-$owner'))}#9';
      const phoneDraft = '手机独立草稿', companionDraft = '模拟器独立草稿';
      final flags = <String, Object>{};
      var accepted = false;
      final originalPointerPropagation =
          binding.shouldPropagateDevicePointerEvents;
      binding.shouldPropagateDevicePointerEvents = true;
      try {
        final before = await store.read();
        if (phase == 'batch-register' || phase == 'batch-companion-draft') {
          expect(
            before.session == null &&
                before.registration == null &&
                before.identityDrafts.isEmpty &&
                before.pendingCredentialChange == null,
            true,
          );
        } else {
          expect(
            before.session != null &&
                before.session!.accountId == fixture['accountId'],
            true,
          );
          if (phase == 'batch-phone-retake' ||
              phase == 'batch-gate-session-recover') {
            await expectLater(
              api.currentSession(before.session!.token),
              throwsA(
                isA<AuthFailure>().having(
                  (e) => e.statusCode,
                  'stale bearer status',
                  401,
                ),
              ),
            );
            flags['actualOldBearerRejectedBeforeStartup'] = true;
          } else {
            expect(
              (await api.currentSession(before.session!.token)).username ==
                  username('source'),
              true,
            );
          }
        }
        app.main();
        await tester.pump();
        if (phase == 'batch-register') {
          final code = await _register(
            tester,
            username('source'),
            password('source'),
          );
          final state = await store.read();
          expect(state.session != null && state.registration == null, true);
          fixture['accountId'] = state.session!.accountId;
          fixture['recoveryCode'] = code; // Owned encrypted test marker only.
          final directory = await api.identities(state.session!.token);
          expect(
            directory.identities.isEmpty && directory.createdCount == 0,
            true,
          );
          flags['actualVSMTPAndFullRecoveryConfirmationCreatedAccount'] = true;
        } else if (phase == 'batch-gate-session-recover') {
          final original = before.pendingCredentialChange;
          expect(original?['state'] == 'UNKNOWN', true);
          await _wait(
            tester,
            () async =>
                find.text('登录或注册').evaluate().isNotEmpty &&
                (await store.read()).session == null,
            'guest after old Gate generation refusal',
          );
          expect(
            (await store.read()).pendingCredentialChange?['key'] ==
                original!['key'],
            true,
          );
          await _login(tester, username('source'), password('source'));
          final current = (await store.read()).session!;
          expect(
            current.accountId == fixture['accountId'] &&
                current.token != before.session!.token,
            true,
          );
          await _security(tester);
          await _wait(
            tester,
            () => find.text('核对当前凭据后继续').evaluate().isNotEmpty,
            'old-session unknown operation cannot be adopted',
          );
          final held = (await store.read()).pendingCredentialChange;
          expect(
            held?['key'] == original['key'] &&
                held?['intentId'] == original['intentId'] &&
                held?['state'] == 'UNKNOWN',
            true,
          );
          await _tap(tester, find.text('核对当前凭据后继续'));
          await _wait(
            tester,
            () => find.text('结束上次结果核对').evaluate().isNotEmpty,
            'explicit old-outcome warning',
          );
          await _tap(tester, find.widgetWithText(FilledButton, '继续'));
          await _wait(
            tester,
            () async => (await store.read()).pendingCredentialChange == null,
            'explicit product acknowledgement clears old anchor',
          );
          expect(
            (await api.recoveryCredentials(current.token)).passkeys.isEmpty,
            true,
          );
          flags['oldUnknownNotAdoptedByNewSession'] = true;
          flags['explicitProductAcknowledgementEndedOldAnchor'] = true;
          flags['previousOutcomeNotDeclaredCommittedOrNotCommitted'] = true;
          flags['sameAccountAndZeroPasskeysAfterFreshLogin'] = true;
        } else if (phase == 'batch-companion-draft' ||
            phase == 'batch-phone-retake') {
          await _wait(
            tester,
            () async =>
                find.text('登录或注册').evaluate().isNotEmpty &&
                (await store.read()).session == null,
            'guest before explicit login',
          );
          await _login(tester, username('source'), password('source'));
          final current = (await store.read()).session!;
          expect(
            (await api.currentSession(current.token)).username ==
                username('source'),
            true,
          );
          final directory = await api.identities(current.token);
          expect(
            directory.identities.isEmpty && directory.createdCount == 0,
            true,
          );
          await _draft(tester);
          final input = tester.widget<TextFormField>(
            find.byKey(const ValueKey('identity-nickname')),
          );
          if (phase == 'batch-companion-draft') {
            expect(input.controller!.text.isEmpty, true);
            fixture['accountId'] = current.accountId;
            await _input(tester, 'identity-nickname', companionDraft);
            await _savedDraft(tester, store, current.accountId, companionDraft);
            flags['companionDidNotInheritPhoneDraft'] = true;
            flags['companionSavedIndependentNativeDraft'] = true;
          } else {
            expect(current.accountId == fixture['accountId'], true);
            expect(input.controller!.text == phoneDraft, true);
            await _savedDraft(tester, store, current.accountId, phoneDraft);
            flags['phoneDraftRestoredAfterExplicitRetake'] = true;
            flags['companionDraftDidNotOverwritePhoneDraft'] = true;
          }
          flags['actualProductLoginAndZeroIdentityHistory'] = true;
        } else {
          await _wait(
            tester,
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'authoritative App startup',
          );
          if (phase == 'batch-phone-draft') {
            await _draft(tester);
            await _input(tester, 'identity-nickname', phoneDraft);
            await _savedDraft(
              tester,
              store,
              before.session!.accountId,
              phoneDraft,
            );
            flags['phoneSavedProductDraftToNativeVault'] = true;
          } else if (phase == 'batch-account-isolation') {
            await _savedDraft(
              tester,
              store,
              before.session!.accountId,
              phoneDraft,
            );
            await _logout(tester);
            await _register(tester, username('other'), password('other'));
            final other = (await store.read()).session!;
            expect(other.accountId != before.session!.accountId, true);
            final directory = await api.identities(other.token);
            expect(
              directory.identities.isEmpty && directory.createdCount == 0,
              true,
            );
            await _draft(tester);
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(const ValueKey('identity-nickname')),
                  )
                  .controller!
                  .text
                  .isEmpty,
              true,
            );
            final isolated = await store.read();
            expect(
              !isolated.identityDrafts.containsKey(other.accountId) &&
                  isolated.identityChanges.isEmpty &&
                  isolated.pendingCredentialChange == null,
              true,
            );
            await _tap(tester, find.text('取消'));
            await _tap(tester, find.byType(BackButton));
            await _tap(tester, find.byType(BackButton));
            await _logout(tester);
            await _login(tester, username('source'), password('source'));
            await _draft(tester);
            expect(
              (await store.read()).session!.accountId ==
                  before.session!.accountId,
              true,
            );
            expect(
              tester
                      .widget<TextFormField>(
                        find.byKey(const ValueKey('identity-nickname')),
                      )
                      .controller!
                      .text ==
                  phoneDraft,
              true,
            );
            flags['freshOtherAccountHasNoSourceDraftPendingOrIdentityHistory'] =
                true;
            flags['explicitReturnRestoresOnlySourceAccountDraft'] = true;
          } else {
            final credentials = await api.recoveryCredentials(
              before.session!.token,
            );
            await _security(tester);
            if (phase == 'batch-passkey-ack-interrupted-success') {
              final original = before.pendingCredentialChange;
              expect(
                original?['kind'] == 'PASSKEY_BINDING' &&
                    {'UNKNOWN', 'COMMITTED'}.contains(original?['state']),
                true,
              );
              expect(credentials.passkeys.length, 1);
              await _wait(
                tester,
                () => find.text('变更已确认提交。').evaluate().isNotEmpty,
                'interrupted successful binding original receipt',
              );
              final terminal = (await store.read()).pendingCredentialChange;
              expect(
                terminal?['key'] == original!['key'] &&
                    terminal?['intentId'] == original['intentId'] &&
                    terminal?['state'] == 'COMMITTED',
                true,
              );
              await _tap(tester, find.text('返回当前凭据'));
              await _wait(
                tester,
                () async =>
                    (await store.read()).pendingCredentialChange == null,
                'successful original binding acknowledged',
              );
              expect(
                (await store.read()).session!.token == before.session!.token,
                true,
              );
              flags['successfulBindingRetainedAfterFixtureFailure'] = true;
              flags['originalSuccessAcknowledgedWithoutNewNativeRequest'] =
                  true;
              flags['priorStateWasUnknown'] = original['state'] == 'UNKNOWN';
            } else if (phase == 'batch-passkey-remove-existing') {
              expect(before.pendingCredentialChange == null, true);
              expect(credentials.passkeys.length, 1);
              await _input(tester, 'management-password', password('source'));
              await _tap(tester, find.text('移除此 Passkey'));
              await _tap(tester, find.text('确认移除'));
              await _wait(
                tester,
                () =>
                    find.text('核对原结果').evaluate().isNotEmpty ||
                    find.text('变更已确认提交。').evaluate().isNotEmpty,
                'removal original receipt available',
              );
              if (find.text('核对原结果').evaluate().isNotEmpty) {
                await _tap(tester, find.text('核对原结果'));
              }
              await _wait(
                tester,
                () => find.text('变更已确认提交。').evaluate().isNotEmpty,
                'confirmed removal receipt',
              );
              await _tap(tester, find.text('返回当前凭据'));
              await _wait(
                tester,
                () async =>
                    (await store.read()).pendingCredentialChange == null,
                'removal receipt acknowledged',
              );
              final after = await store.read();
              expect(after.session!.token == before.session!.token, true);
              expect(
                (await api.recoveryCredentials(after.session!.token))
                    .passkeys
                    .isEmpty,
                true,
              );
              flags['actualExistingPasskeyRemovedBeforeFreshNativeCreation'] =
                  true;
              flags['currentSessionPreserved'] = true;
              flags['noUnknownOperationBeforeRemoval'] = true;
            } else if (phase == 'batch-passkey-reconcile' ||
                phase == 'batch-passkey-rejected-reconcile') {
              final original = before.pendingCredentialChange;
              expect(
                original?['kind'] == 'PASSKEY_BINDING' &&
                    original?['state'] == 'UNKNOWN',
                true,
              );
              final committed = phase == 'batch-passkey-reconcile';
              await _wait(
                tester,
                () => find
                    .text(committed ? '变更已确认提交。' : '本次变更未提交，可重新输入密码开始。')
                    .evaluate()
                    .isNotEmpty,
                'original binding commit receipt',
              );
              final result = (await store.read()).pendingCredentialChange;
              expect(
                result?['key'] == original!['key'] &&
                    result?['intentId'] == original['intentId'],
                true,
              );
              expect(
                credentials.passkeys.length ==
                    fixture[committed
                        ? 'bindingExpectedCount'
                        : 'rejectedExpectedCount'],
                true,
              );
              await _tap(tester, find.text('返回当前凭据'));
              await _wait(
                tester,
                () async =>
                    (await store.read()).pendingCredentialChange == null,
                'acknowledged original receipt',
              );
              flags['originalBindingKeyAndIntentReconciledAfterProcessRestart'] =
                  true;
              flags['originalBindingWasCommitted'] = committed;
              flags['noNewNativeRequestInReconciliationPhase'] = true;
            } else {
              expect(before.pendingCredentialChange == null, true);
              await _input(tester, 'management-password', password('source'));
              final controller = tester
                  .widget<SecurityManagementScreen>(
                    find.byType(SecurityManagementScreen),
                  )
                  .controller;
              final observer = _ProviderLifecycle();
              WidgetsBinding.instance.addObserver(observer);
              try {
                await driver.invokeMethod<void>('stage', phase);
                if (phase == 'batch-passkey-route-cancel' ||
                    phase == 'batch-passkey-timeout') {
                  // Do not pump Flutter frames while a native Activity owns
                  // the foreground. The owned host observes the real provider;
                  // an unrelated app background event cannot acknowledge it.
                  await driver.invokeMethod<void>(
                    'stage',
                    'await-batch-native-provider',
                  );
                  final action = find.text('绑定新的 Passkey');
                  await tester.ensureVisible(action);
                  final elapsed = Stopwatch()..start();
                  await tester.tap(action);
                  await tester.runAsync(() async {
                    final ack = File(
                      '/data/user/0/org.hnuhole.hnuhole_mobile/files/owned-batch-provider-ack.json',
                    );
                    final deadline = DateTime.now().add(
                      const Duration(seconds: 85),
                    );
                    var observed = false;
                    while (DateTime.now().isBefore(deadline)) {
                      if (await ack.exists()) {
                        final value =
                            jsonDecode(await ack.readAsString()) as Map;
                        if (value['pid'] == pid &&
                            value['stage'] == 'await-batch-native-provider' &&
                            value['providerComponent'] ==
                                'com.vivo.credentialmanager/.CredentialSelectorActivity') {
                          observed = true;
                          break;
                        }
                      }
                      await Future<void>.delayed(
                        const Duration(milliseconds: 100),
                      );
                    }
                    expect(observed, true);
                    // Invoke the same real controller cancellation used by
                    // route disposal before a native callback can grant state.
                    // The subsequent product Back action checks route cleanup.
                    if (phase == 'batch-passkey-timeout') {
                      while (controller.busy &&
                          elapsed.elapsed.inSeconds < 75) {
                        await Future<void>.delayed(
                          const Duration(milliseconds: 100),
                        );
                      }
                      final current = await store.read();
                      await File(
                        '/data/user/0/org.hnuhole.hnuhole_mobile/files/owned-batch-timeout-diagnostic.json',
                      ).writeAsString(
                        jsonEncode({
                          'phase': phase,
                          'pid': pid,
                          'elapsedMillis': elapsed.elapsed.inMilliseconds,
                          'controllerBusy': controller.busy,
                          'systemCancellationReported':
                              controller.errorMessage == '已取消系统 Passkey 操作。',
                          'pendingChangeState':
                              current.pendingCredentialChange?['state'],
                          'rawProofStored': false,
                        }),
                      );
                      expect(
                        !controller.busy &&
                            controller.errorMessage == '已取消系统 Passkey 操作。',
                        true,
                      );
                      expect(
                        elapsed.elapsed.inMilliseconds >= 55000 &&
                            elapsed.elapsed.inMilliseconds <= 75000,
                        true,
                      );
                      flags['nativeCancellationElapsedMillis'] =
                          elapsed.elapsed.inMilliseconds;
                      await driver.invokeMethod<void>(
                        'stage',
                        'batch-owned-native-timeout-returned',
                      );
                      final dismissed = File(
                        '/data/user/0/org.hnuhole.hnuhole_mobile/files/owned-batch-timeout-dismissed.json',
                      );
                      final closeDeadline = DateTime.now().add(
                        const Duration(seconds: 15),
                      );
                      var hostFinished = false;
                      while (DateTime.now().isBefore(closeDeadline)) {
                        if (await dismissed.exists()) {
                          final value =
                              jsonDecode(await dismissed.readAsString()) as Map;
                          if (value['pid'] == pid &&
                              value['nativeResultBeforeHostBack'] == true) {
                            hostFinished = true;
                            flags['hostDismissedProviderAfterNativeResult'] =
                                value['hostBackUsed'] == true;
                            break;
                          }
                        }
                        await Future<void>.delayed(
                          const Duration(milliseconds: 100),
                        );
                      }
                      expect(hostFinished, true);
                    } else {
                      controller.cancelEphemeral();
                      await driver.invokeMethod<void>(
                        'stage',
                        'batch-owned-controller-cancelled',
                      );
                    }
                  });
                  if (phase == 'batch-passkey-route-cancel') {
                    await _tap(tester, find.byType(BackButton));
                  } else {
                    await tester.pump();
                  }
                  await _wait(
                    tester,
                    () => !controller.busy,
                    'native route cancellation',
                  );
                  await tester.pump(const Duration(seconds: 2));
                  expect(
                    (await store.read()).pendingCredentialChange == null,
                    true,
                  );
                  expect(
                    (await api.recoveryCredentials(before.session!.token))
                            .passkeys
                            .length ==
                        credentials.passkeys.length,
                    true,
                  );
                  flags['hostObservedNativeProviderBeforeControllerCancellation'] =
                      true;
                  if (phase == 'batch-passkey-route-cancel') {
                    flags['realControllerCancellationBeforeProductBack'] = true;
                  } else {
                    flags['actualUnansweredNativeOperationCancelledWithinDeadline'] =
                        true;
                    flags['noHostBackBeforeNativeCancellation'] = true;
                  }
                  flags['credentialsUnchangedAfterRouteCancellation'] = true;
                  flags['postCancellationObservationMillis'] = 2000;
                } else {
                  final action = find.text('绑定新的 Passkey');
                  await tester.ensureVisible(action);
                  await tester.tap(action);
                  // Real async callbacks must continue while the OS provider
                  // owns the foreground. Do not wait for a Flutter frame here.
                  await tester.runAsync(() async {
                    final deadline = DateTime.now().add(
                      const Duration(seconds: 75),
                    );
                    while (DateTime.now().isBefore(deadline)) {
                      if (!controller.busy && controller.errorMessage != null) {
                        break;
                      }
                      await Future<void>.delayed(
                        const Duration(milliseconds: 100),
                      );
                    }
                    final state = await store.read();
                    await File(
                      '/data/user/0/org.hnuhole.hnuhole_mobile/files/owned-batch-native-diagnostic.json',
                    ).writeAsString(
                      jsonEncode({
                        'phase': phase,
                        'pid': pid,
                        'controllerBusy': controller.busy,
                        'serverErrorCode': controller.error?.code,
                        'systemCancellationReported':
                            controller.errorMessage == '已取消系统 Passkey 操作。',
                        'systemUnavailableReported':
                            controller.errorMessage ==
                            '系统 Passkey 暂不可用，请检查设备支持及关联配置后重试。',
                        'pendingChangeExists':
                            state.pendingCredentialChange != null,
                        'rawProofStored': false,
                      }),
                    );
                    if (controller.busy || controller.error == null) {
                      throw StateError(
                        'Native provider did not yield the expected HTTP failure; count-only diagnostic retained',
                      );
                    }
                  });
                  await tester.pump();
                  final state = await store.read();
                  final after = await api.recoveryCredentials(
                    before.session!.token,
                  );
                  if (phase == 'batch-passkey-drop') {
                    expect(
                      state.pendingCredentialChange?['kind'] ==
                              'PASSKEY_BINDING' &&
                          state.pendingCredentialChange?['state'] == 'UNKNOWN',
                      true,
                    );
                    expect(
                      after.passkeys.length == credentials.passkeys.length + 1,
                      true,
                    );
                    fixture['bindingExpectedCount'] = after.passkeys.length;
                    flags['actualServerBindingExistsWhileProductOutcomeUnknown'] =
                        true;
                    flags['durableOriginalBindingMetadataRetained'] = true;
                  } else {
                    expect(controller.error!.code == 'CHALLENGE_INVALID', true);
                    expect(
                      after.passkeys.length == credentials.passkeys.length,
                      true,
                    );
                    expect(
                      state.pendingCredentialChange?['state'] == 'UNKNOWN',
                      true,
                    );
                    fixture['rejectedExpectedCount'] = after.passkeys.length;
                    flags['actualServerRejectedAlteredNativeClientOrigin'] =
                        true;
                    flags['noCredentialAddedByRejectedProof'] = true;
                    // Keep the unknown operation for explicit original-result
                    // reconciliation. An error response is not a receipt.
                  }
                }
              } finally {
                WidgetsBinding.instance.removeObserver(observer);
              }
            }
          }
        }
        await marker.write(
          jsonEncode({...fixture, 'lastPhase': phase, 'pid': pid}),
        );
        binding.reportData = {
          'phase': phase,
          'pid': pid,
          'actualApp': true,
          'actualCV': true,
          'nativeVault': true,
          'systemPasskey':
              phase!.startsWith('batch-passkey-') &&
              phase != 'batch-passkey-remove-existing' &&
              phase != 'batch-passkey-ack-interrupted-success' &&
              phase != 'batch-passkey-reconcile' &&
              phase != 'batch-passkey-rejected-reconcile',
          ...flags,
        };
        accepted = true;
      } finally {
        // Do not replace an error page here. The test framework may still tear
        // down a failed root; native durable state and diagnostics are retained.
        binding.shouldPropagateDevicePointerEvents = originalPointerPropagation;
        if (accepted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        api.close();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: run.isEmpty,
  );
}

class _ProviderLifecycle extends WidgetsBindingObserver {
  bool providerBackgrounded = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) providerBackgrounded = true;
  }
}

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String stage, {
  int seconds = 60,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await ready()) return;
  }
  throw StateError('Owned batch phase timed out: $stage');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () {
    if (finder.evaluate().length != 1) return false;
    final button = find.ancestor(
      of: finder,
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    return button.evaluate().isEmpty ||
        tester.widget<ButtonStyleButton>(button.first).onPressed != null;
  }, 'enabled single action');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _input(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(
    tester,
    () =>
        finder.evaluate().length == 1 &&
        tester.widget<TextFormField>(finder).enabled != false,
    'enabled input',
  );
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.widget<TextFormField>(finder).controller!.text == value, true);
}

Future<void> _login(
  WidgetTester tester,
  String username,
  String password,
) async {
  await _tap(tester, find.text('登录或注册'));
  await _input(tester, 'login-username', username);
  await _input(tester, 'login-password', password);
  await _tap(tester, find.text('登录并进入'));
  await _wait(
    tester,
    () =>
        find.byType(AuthScreen).evaluate().isEmpty &&
        find.byType(ChannelTree).evaluate().isNotEmpty,
    'explicit product login',
  );
}

Future<void> _logout(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('My content'));
  await _tap(tester, find.widgetWithText(ListTile, '账号与注销'));
  await _tap(tester, find.text('退出本机'));
  await _wait(
    tester,
    () => find.byKey(const ValueKey('login-password')).evaluate().isNotEmpty,
    'signed out product account page',
  );
  await _tap(tester, find.byType(BackButton));
  await _tap(tester, find.byType(BackButton));
  await _wait(
    tester,
    () => find.text('登录或注册').evaluate().isNotEmpty,
    'product logout',
  );
}

Future<void> _draft(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('My content'));
  await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
  await _tap(tester, find.byKey(const ValueKey('identity-add')));
  await _wait(
    tester,
    () => find.byKey(const ValueKey('identity-nickname')).evaluate().isNotEmpty,
    'product draft editor',
  );
}

Future<void> _savedDraft(
  WidgetTester tester,
  AuthStore store,
  String account,
  String draft,
) => _wait(
  tester,
  () async =>
      ((await store.read()).identityDrafts[account] as Map?)?['nickname'] ==
      draft,
  'native committed draft',
);

Future<void> _security(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('My content'));
  await _tap(tester, find.widgetWithText(ListTile, '设备与恢复凭据'));
  await _wait(
    tester,
    () =>
        find.byType(SecurityManagementScreen).evaluate().isNotEmpty &&
        !tester
            .widget<SecurityManagementScreen>(
              find.byType(SecurityManagementScreen),
            )
            .controller
            .busy,
    'product credential page',
  );
}

Future<String> _register(
  WidgetTester tester,
  String username,
  String password,
) async {
  await _tap(tester, find.text('登录或注册'));
  await _tap(tester, find.text('新注册'));
  final email = 'batch-${DateTime.now().microsecondsSinceEpoch}@hainanu.edu.cn';
  await _input(tester, 'registration-email', email);
  await _tap(tester, find.text('获取验证码'));
  await _wait(
    tester,
    () => find.text('确认验证码').evaluate().isNotEmpty,
    'V request',
  );
  final mailpit = Uri.parse(
    const String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL'),
  );
  final otp = await _smtpOtp(mailpit, email);
  await _input(tester, 'registration-otp', otp);
  await _tap(tester, find.text('确认验证码'));
  await _input(tester, 'registration-username', username);
  await _input(tester, 'registration-password', password);
  await _tap(tester, find.text('生成并保存恢复码'));
  final codeFinder = find.byKey(const ValueKey('displayed-recovery-code'));
  await _wait(
    tester,
    () => codeFinder.evaluate().isNotEmpty,
    'C recovery code',
  );
  final code = tester.widget<Text>(codeFinder).data!;
  await _tap(tester, find.text('我已保存，隐藏原码并确认'));
  await _input(tester, 'recovery-confirmation', code);
  await _tap(tester, find.text('确认恢复码并创建账号'));
  await _wait(
    tester,
    () =>
        find.byType(AuthScreen).evaluate().isEmpty &&
        find.byType(ChannelTree).evaluate().isNotEmpty,
    'actual C registration',
  );
  return code;
}

Future<String> _smtpOtp(Uri origin, String email) async {
  expect(
    origin.scheme == 'http' && origin.host == '127.0.0.1' && origin.hasPort,
    true,
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    for (var i = 0; i < 100; i++) {
      final request = await client.getUrl(
        origin.resolve('/api/v1/message/latest/raw'),
      );
      request.followRedirects = false;
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 16384) {
          throw StateError('Owned SMTP response too large');
        }
        bytes.addAll(chunk);
      }
      final raw = utf8.decode(bytes);
      final match = RegExp(
        r'Your Hnuhole campus verification code is ([0-9]{6})\.',
      ).firstMatch(raw);
      if (response.statusCode == 200 && raw.contains(email) && match != null) {
        return match[1]!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('Owned SMTP delivery absent');
  } finally {
    client.close(force: true);
  }
}
