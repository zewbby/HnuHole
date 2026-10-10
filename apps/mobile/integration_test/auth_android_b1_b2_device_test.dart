import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
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

const _driver = MethodChannel('hnuhole/owned_device_driver');
const _native = MethodChannel('hnuhole/auth_passkey');
const _privateFiles = '/data/user/0/org.hnuhole.hnuhole_mobile/files/';
const _run = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
const _accountRun = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');

/// Actual product routes, C/V, Android vault and Credential Manager. Host
/// lifecycle/provider/SQL witnesses are independently required by the runner.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fixed B1 and B2 actual Android cases',
    (tester) async {
      expect(
        Platform.isAndroid &&
            _run == 'hnuhole-android-live-matrix-20261006' &&
            _accountRun == 'hnuhole-android-live-batch-20261007',
        true,
      );
      final entryPhase = await _driver.invokeMethod<String>('phase');
      // Engine recreation can replace the VM service while FlutterJNI still
      // exposes its prior URI. Publish the actual Dart service privately.
      if (entryPhase != 'ni-l02-read') await _publishVm(entryPhase!);
      final phase = entryPhase == 'ni-l02-read' ? 'ni-l02' : entryPhase!;
      expect(
        const {
          'ni-l01',
          'ni-l02',
          'ni-l03',
          'ni-l04',
          'ni-u01',
          'ni-u02',
          'ni-u03',
          'ni-a01',
          'ni-a02',
          'ni-a03',
          'ni-a04',
          'ni-takeover',
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
      final store = AuthStore(
        FlutterAuthVault(
          namespace:
              'hnuhole.auth.v1.${AuthCrypto.domainDigest('HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1', utf8.encode(scope))}',
        ),
        scope: scope,
      );
      final marker = FlutterAuthVault(
        namespace: 'native.security.test.$_accountRun.b1b2',
      );
      final fixture =
          jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        passkeyRpId: developmentPasskeyRp(community: c, verifier: v),
        client: createAppHttpClient(community: c, verifier: v),
      );
      final name =
          'dev_${AuthCrypto.domainDigest('DEVICE-USERNAME', utf8.encode('$_accountRun-source')).substring(0, 16)}'
              .replaceAll('-', '_')
              .toLowerCase();
      final password =
          'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode('$_accountRun-source'))}#9';
      final flags = <String, Object>{};
      final pointers = binding.shouldPropagateDevicePointerEvents;
      var accepted = false;
      try {
        binding.shouldPropagateDevicePointerEvents = true;
        final before = await store.read();
        if (phase == 'ni-takeover') {
          await _stage('ni-companion-ready');
          await tester.runAsync(() => _hostAck('ni-companion-login-start'));
        }
        app.main();
        await tester.pump();
        if (phase == 'ni-u01' || phase == 'ni-a02') {
          await _wait(
            tester,
            () =>
                find.text('登录或注册').evaluate().isNotEmpty ||
                (phase == 'ni-a02' && find.text('退出本机').evaluate().isNotEmpty),
            'guest or frozen entry',
          );
          if (phase == 'ni-a02' && find.text('退出本机').evaluate().isNotEmpty) {
            await _tap(tester, find.text('退出本机'));
            await _wait(
              tester,
              () => find
                  .byKey(const ValueKey('login-password'))
                  .evaluate()
                  .isNotEmpty,
              'local exit after freeze',
            );
          }
          if (find.byType(AuthScreen).evaluate().isEmpty) {
            await _tap(tester, find.text('登录或注册'));
          }
          if (phase == 'ni-a02' && find.text('退出本机').evaluate().isNotEmpty) {
            await _tap(tester, find.text('退出本机'));
          }
          await _wait(
            tester,
            () => find.text('恢复账号').evaluate().isNotEmpty,
            'recovery mode',
          );
          await _tap(tester, find.text('恢复账号'));
          final flows = tester
              .widget<AuthScreen>(find.byType(AuthScreen))
              .flows;
          final nativeBefore = await _nativeState();
          await _tap(tester, find.text('使用 Passkey 恢复'));
          await tester.runAsync(() async {
            final limit = DateTime.now().add(const Duration(seconds: 75));
            while (flows.busy && DateTime.now().isBefore(limit)) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          });
          await tester.pump();
          expect(
            !flows.busy &&
                flows.errorMessage != null &&
                (await store.read()).pendingReset == null,
            true,
          );
          expect(
            find.byKey(const ValueKey('recovery-code')).evaluate().length == 1,
            true,
          );
          final nativeAfter = await _nativeState();
          if (phase == 'ni-a02') {
            expect(flows.error?.statusCode == 503, true);
            expect(
              _count(nativeAfter, 'nativeBegun') ==
                  _count(nativeBefore, 'nativeBegun'),
              true,
            );
            flags['frozenOptionsRejectedBeforeNativeRequest'] = true;
          } else {
            expect(
              _count(nativeAfter, 'nativeBegun') -
                      _count(nativeBefore, 'nativeBegun') ==
                  1,
              true,
            );
            expect(
              _count(nativeAfter, 'nativeSucceeded') ==
                  _count(nativeBefore, 'nativeSucceeded'),
              true,
            );
            expect(
              _count(nativeAfter, 'actualNoCredential') +
                      _count(nativeAfter, 'actualProviderUnavailable') >
                  _count(nativeBefore, 'actualNoCredential') +
                      _count(nativeBefore, 'actualProviderUnavailable'),
              true,
            );
            flags['nativeCounts'] = nativeAfter;
            flags['actualNativeUnavailableOrNoCredentialReturnedWithoutProof'] =
                true;
          }
          flags['recoveryCodeEntryStillAvailable'] = true;
          flags['noResetIntentOrSessionInstalled'] = true;
        } else {
          await _wait(
            tester,
            () =>
                find.text('登录或注册').evaluate().isNotEmpty ||
                find.byType(ChannelTree).evaluate().isNotEmpty,
            'authoritative startup',
          );
          if (find.text('登录或注册').evaluate().isNotEmpty) {
            await _login(tester, name, password);
            flags['explicitProductLogin'] = true;
          }
          final session = (await store.read()).session!;
          expect(
            (await api.currentSession(session.token)).username == name,
            true,
          );
          if (fixture['accountId'] != null) {
            expect(session.accountId == fixture['accountId'], true);
          }
          fixture['accountId'] = session.accountId;
          if (phase == 'ni-takeover') {
            expect(before.session?.token != session.token, true);
            flags['explicitCompanionLoginSameAccount'] = true;
          } else if (phase == 'ni-u02') {
            await _draft(tester);
            final context = tester.element(
              find.byKey(const ValueKey('identity-nickname')),
            );
            final media = MediaQuery.of(context);
            expect(
              media.textScaler.scale(10) >= 15.9 && media.size.width <= 360,
              true,
            );
            const draft = '大字验收草稿';
            await _input(tester, 'identity-nickname', draft);
            await _wait(
              tester,
              () async =>
                  ((await store.read()).identityDrafts[session.accountId]
                      as Map?)?['nickname'] ==
                  draft,
              'native draft write',
            );
            await _tap(tester, find.text('取消'));
            await _tap(tester, find.byType(BackButton));
            await _tap(tester, find.widgetWithText(ListTile, '设备与恢复凭据'));
            await _wait(
              tester,
              () => find
                  .byKey(const ValueKey('management-password'))
                  .evaluate()
                  .isNotEmpty,
              'large text security',
            );
            await _input(
              tester,
              'management-password',
              'Wrong-OnlySynthetic-Password#7',
            );
            await _tap(tester, find.text('绑定新的 Passkey'));
            await _wait(
              tester,
              () => _securityController(tester).errorMessage != null,
              'actual password refusal',
            );
            await _tap(tester, find.byType(BackButton));
            await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
            await _tap(tester, find.byKey(const ValueKey('identity-add')));
            expect(
              tester
                      .widget<TextFormField>(
                        find.byKey(const ValueKey('identity-nickname')),
                      )
                      .controller!
                      .text ==
                  draft,
              true,
            );
            await _tap(tester, find.text('取消'));
            expect(tester.takeException() == null, true);
            flags['actualDeviceSmallScreenAndLargeFont'] = true;
            flags['draftPreservedAcrossProductCancelAndError'] = true;
            flags['fontScaleTimes100'] = (media.textScaler.scale(10) * 10)
                .round();
            flags['logicalWidth'] = media.size.width.round();
          } else {
            await _security(tester);
            final controller = _securityController(tester);
            if (phase == 'ni-u03' &&
                (await store.read()).pendingCredentialChange != null) {
              final prior = (await store.read()).pendingCredentialChange!;
              expect(
                prior['kind'] == 'ROTATION' &&
                    const {'UNKNOWN', 'COMMITTED'}.contains(prior['state']),
                true,
              );
              if (prior['state'] == 'UNKNOWN') {
                await _tap(tester, find.text('核对原结果'));
                await _wait(
                  tester,
                  () async =>
                      (await store.read()).pendingCredentialChange?['state'] ==
                      'COMMITTED',
                  'prior rotation original result',
                );
              }
              final resolved = (await store.read()).pendingCredentialChange!;
              expect(
                resolved['key'] == prior['key'] &&
                    resolved['intentId'] == prior['intentId'] &&
                    resolved['key'] == before.pendingCredentialChange?['key'] &&
                    resolved['intentId'] ==
                        before.pendingCredentialChange?['intentId'],
                true,
              );
              await _tap(tester, find.text('返回当前凭据'));
              await _wait(
                tester,
                () async =>
                    (await store.read()).pendingCredentialChange == null,
                'prior rotation acknowledgement',
              );
              await _stage('ni-talkback-prior-reconciled');
              await tester.runAsync(() => _hostAck('ni-talkback-prior-counts'));
              flags['priorRotationOriginalResultReconciledBeforeFreshCase'] =
                  true;
              flags['priorConfirmationReplayed'] = false;
              flags['priorRotationAlreadyCommittedAtStart'] =
                  before.pendingCredentialChange?['state'] == 'COMMITTED';
            }
            if ((await store.read()).pendingCredentialChange != null &&
                (phase == 'ni-a03' || phase == 'ni-a04')) {
              expect(
                controller.status ==
                    SecurityManagementStatus.previousSessionPending,
                true,
              );
              await _tap(tester, find.text('核对当前凭据后继续'));
              await _tap(tester, find.widgetWithText(FilledButton, '继续'));
              await _wait(
                tester,
                () async =>
                    (await store.read()).pendingCredentialChange == null,
                'explicit old-session anchor ending',
              );
              flags['oldUnknownExplicitlyEndedWithoutOutcomeClaimOrResubmission'] =
                  true;
            }
            expect((await store.read()).pendingCredentialChange == null, true);
            if (phase == 'ni-u03') {
              await _talkback(
                tester,
                binding,
                controller,
                store,
                marker,
                fixture,
                password,
                flags,
              );
            } else if (entryPhase == 'ni-l02-read') {
              final life = await _life();
              final native = await _nativeState();
              expect(
                life['recreateRequested'] == 1 &&
                    _count(life, 'activityCreated') >= 2 &&
                    _count(life, 'activityDestroyed') >= 1 &&
                    _count(life, 'engineAttached') >= 2,
                true,
              );
              expect(
                _count(native, 'engineDetached') >= 1 &&
                    _count(native, 'nativeCancelled') >= 1,
                true,
              );
              expect(life['activityId'] != fixture['l02ActivityId'], true);
              expect(
                AuthCrypto.domainDigest(
                      'B1-B2-SESSION',
                      utf8.encode(session.token),
                    ) ==
                    fixture['l02SessionDigest'],
                true,
              );
              await _hostAck('ni-native-cleaned');
              // Stop the old isolate's host driver before restarting the debug
              // listener, so its teardown cannot close this new server.
              await _publishVm(entryPhase!, restart: true);
              expect(
                (await store.read()).pendingCredentialChange == null &&
                    !controller.busy,
                true,
              );
              flags['actualActivityAndEngineDestroyed'] = true;
              flags['newActivityRestoredSameDurableSessionWithoutNativeRetry'] =
                  true;
              flags['lifecycleCounts'] = _publicLife(life);
              flags['nativeCounts'] = native;
            } else {
              await _input(tester, 'management-password', password);
              final initialLife = await _life();
              final initialNative = await _nativeState();
              final credentials = (await api.recoveryCredentials(session.token))
                  .passkeys
                  .length;
              if (phase == 'ni-a03') {
                await _stage('ni-prepare-companion');
                await tester.runAsync(() => _hostAck('ni-companion-ready'));
              }
              await _stage('ni-await-native-first');
              await tester.ensureVisible(find.text('绑定新的 Passkey'));
              await tester.tap(find.text('绑定新的 Passkey'));
              await tester.runAsync(() async {
                await _hostAck('ni-native-first');
                expect(controller.busy, true);
                if (phase == 'ni-l02') {
                  fixture['l02ActivityId'] = initialLife['activityId'];
                  fixture['l02SessionDigest'] = AuthCrypto.domainDigest(
                    'B1-B2-SESSION',
                    utf8.encode(session.token),
                  );
                  await marker.write(jsonEncode(fixture));
                  await _stage('ni-recreate-requested');
                  await _driver.invokeMethod<void>('acceptanceRecreate');
                  await Future<void>.delayed(const Duration(minutes: 2));
                  throw StateError(
                    'Actual Activity recreation did not replace the old engine',
                  );
                }
                if (phase == 'ni-l01' ||
                    phase == 'ni-l03' ||
                    phase == 'ni-l04') {
                  controller.cancelEphemeral();
                  await _stage('ni-native-returned');
                  await _hostAck('ni-native-cleaned');
                  if (phase == 'ni-l04') {
                    // Keep a new real request active while injecting old callback
                    // classes into the real native ownership fence, without proofs.
                    final next = controller.bindPasskey(password);
                    await _stage('ni-await-native-second');
                    await _hostAck('ni-native-second');
                    final oldIgnored = _count(
                      await _nativeState(),
                      'lateIgnored',
                    );
                    await _native.invokeMethod<void>(
                      'acceptanceLateCallback',
                      'success',
                    );
                    await _native.invokeMethod<void>(
                      'acceptanceLateCallback',
                      'error',
                    );
                    final injected = await _nativeState();
                    expect(
                      _count(injected, 'lateIgnored') - oldIgnored == 2,
                      true,
                    );
                    expect(
                      controller.busy &&
                          (await store.read()).pendingCredentialChange == null,
                      true,
                    );
                    controller.cancelEphemeral();
                    await next;
                    await _stage('ni-native-second-returned');
                    await _hostAck('ni-native-second-cleaned');
                    flags['deterministicOldSuccessAndErrorIgnoredWhileNewOperationOwned'] =
                        true;
                  }
                } else {
                  // Human UV is requested only after the host completed signed
                  // freezing or actual companion login, as appropriate.
                  final until = DateTime.now().add(const Duration(seconds: 75));
                  while (controller.busy && DateTime.now().isBefore(until)) {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 100),
                    );
                  }
                  expect(!controller.busy, true);
                }
              });
              await tester.pump();
              final nativeAfter = await _nativeState();
              final lifeAfter = await _life();
              if (phase.startsWith('ni-l')) {
                await _tap(tester, find.byType(BackButton));
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(seconds: 2)),
                );
                expect(
                  (await store.read()).pendingCredentialChange == null,
                  true,
                );
                expect(
                  (await api.recoveryCredentials(session.token))
                          .passkeys
                          .length ==
                      credentials,
                  true,
                );
                if (phase == 'ni-l01') {
                  expect(
                    lifeAfter['activityId'] == initialLife['activityId'] &&
                        _count(lifeAfter, 'configurationChanged') >
                            _count(initialLife, 'configurationChanged') &&
                        _count(lifeAfter, 'activityDestroyed') ==
                            _count(initialLife, 'activityDestroyed'),
                    true,
                  );
                  flags['actualConfigurationChangedWithoutActivityRecreation'] =
                      true;
                }
                if (phase == 'ni-l03') {
                  final host = await _hostAck('ni-native-first');
                  expect(host['actualHomeAndOwnedAppReturn'] == true, true);
                  flags['actualNativeRequestBackgroundReturnAndProductRouteExit'] =
                      true;
                }
                expect(
                  _count(nativeAfter, 'nativeCancelled') >
                      _count(initialNative, 'nativeCancelled'),
                  true,
                );
                flags['noPendingOrCredentialAddedAfterCancellation'] = true;
                flags['postCancellationObservationMillis'] = 2000;
              } else {
                final pending = (await store.read()).pendingCredentialChange;
                if (phase == 'ni-a04') {
                  expect(
                    pending?['state'] == 'COMMITTED' &&
                        (await api.recoveryCredentials(session.token))
                                .passkeys
                                .length ==
                            credentials + 1,
                    true,
                  );
                  await _wait(
                    tester,
                    () => find.text('返回当前凭据').evaluate().isNotEmpty,
                    'committed binding',
                  );
                  await _tap(tester, find.text('返回当前凭据'));
                  expect(
                    (await store.read()).pendingCredentialChange == null,
                    true,
                  );
                  flags['explicitFreshChallengeSucceededAfterRecoveryAndRelogin'] =
                      true;
                } else {
                  expect(
                    pending?['kind'] == 'PASSKEY_BINDING' &&
                        pending?['state'] == 'UNKNOWN',
                    true,
                  );
                  flags['actualOldAuthorityProofRefusedAndOriginalAnchorRetained'] =
                      true;
                  if (phase == 'ni-a03') {
                    expect((await store.read()).session == null, true);
                  }
                }
              }
              flags['lifecycleCounts'] = _publicLife(lifeAfter);
              flags['nativeCounts'] = nativeAfter;
            }
          }
        }
        await marker.write(
          jsonEncode({...fixture, 'lastPhase': phase, 'pid': pid}),
        );
        binding.reportData = {
          'phase': phase,
          'pid': pid,
          'caseId': phase == 'ni-takeover'
              ? 'NI-A03-COMPANION'
              : phase.toUpperCase().replaceFirst('NI-', 'NI-'),
          'actualApp': true,
          'actualCV': true,
          'nativeVault': true,
          'rawProofStored': false,
          'humanSpeechCaptured': false,
          ...flags,
        };
        accepted = true;
      } finally {
        binding.shouldPropagateDevicePointerEvents = pointers;
        if (accepted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        api.close();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: _run.isEmpty,
  );
}

Future<void> _talkback(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  SecurityManagementController controller,
  AuthStore store,
  FlutterAuthVault marker,
  Map<String, dynamic> fixture,
  String password,
  Map<String, Object> flags,
) async {
  const targets = {
    'error': '密码复验失败',
    'rotate': '轮换恢复码',
    'hide': '我已保存，隐藏原码并确认',
    'confirmation': '新恢复码完整确认',
    'confirm': '确认并激活新恢复码',
    'unknown': '提交结果尚未确定',
    'query': '核对原结果',
    'committed': '变更已确认提交',
    'ack': '返回当前凭据',
  };
  final focused = <String>{}, tapped = <String>{};
  var focusCount = 0, tapCount = 0;
  var rawFocusCount = 0, rawTapCount = 0;
  var viewLookupMissCount = 0, nodeLookupMissCount = 0;
  var diagnosticWriteFailures = 0;
  var currentStage = 'ni-talkback-enable';
  var requiredPublicTargets = <String>[];
  var missingPublicTargets = <String>[];
  final publicFocusCounts = <String, int>{};
  final publicTapCounts = <String, int>{};
  final rawActionCounts = <String, int>{};
  final labelMatchCounts = <String, int>{};
  final hintMatchCounts = <String, int>{};
  final publicEvents = <Map<String, Object>>[];
  final diagnostic = File(
    '${_privateFiles}owned-device-talkback-observation-$pid.json',
  );
  Future<void> diagnosticTail = Future<void>.value();

  List<String> matches(String publicText) => targets.entries
      .where((entry) => publicText.contains(entry.value))
      .map((entry) => entry.key)
      .toList();

  List<Map<String, Object>> publicNodes() {
    final result = <Map<String, Object>>[];
    for (final view in binding.renderViews) {
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root == null) continue;
      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        final labels = matches(data.label), hints = matches(data.hint);
        final names = {...labels, ...hints}.toList()..sort();
        if (names.isNotEmpty) {
          result.add({
            'viewId': view.flutterView.viewId,
            'nodeId': node.id,
            'publicTargets': names,
            'labelMatches': labels,
            'hintMatches': hints,
            'isTextField': data.flagsCollection.isTextField,
            'isObscured': data.flagsCollection.isObscured,
            'isHidden': data.flagsCollection.isHidden,
            'hasTapAction': data.hasAction(ui.SemanticsAction.tap),
            'localRect': [
              node.rect.left,
              node.rect.top,
              node.rect.right,
              node.rect.bottom,
            ],
          });
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(root);
    }
    return result;
  }

  Future<void> writeDiagnostic(String reason) async {
    final rawState = (await store.read()).pendingCredentialChange?['state'];
    final state = rawState == null
        ? 'NONE'
        : const {'UNKNOWN', 'COMMITTED', 'NOT_COMMITTED'}.contains(rawState)
        ? rawState as String
        : 'OTHER';
    final snapshot = <String, Object>{
      'pid': pid,
      'phase': 'ni-u03',
      'stage': currentStage,
      'reason': reason,
      'requiredPublicTargets': List<String>.from(requiredPublicTargets),
      'missingPublicTargets': List<String>.from(missingPublicTargets),
      'publicTargetPreflightPassed': missingPublicTargets.isEmpty,
      'diagnosticOnly': true,
      'countsAsAcceptance': false,
      'semanticsActionsInjected': false,
      'speechCaptured': false,
      'rawFocusEvents': rawFocusCount,
      'rawTapEvents': rawTapCount,
      'resolvedFocusEvents': focusCount,
      'resolvedTapEvents': tapCount,
      'viewLookupMisses': viewLookupMissCount,
      'nodeLookupMisses': nodeLookupMissCount,
      'diagnosticWriteFailures': diagnosticWriteFailures,
      'publicFocusCounts': Map<String, int>.from(publicFocusCounts),
      'publicTapCounts': Map<String, int>.from(publicTapCounts),
      'rawActionCounts': Map<String, int>.from(rawActionCounts),
      'labelMatchCounts': Map<String, int>.from(labelMatchCounts),
      'hintMatchCounts': Map<String, int>.from(hintMatchCounts),
      'focusedPublicTargets': focused.toList()..sort(),
      'tappedPublicTargets': tapped.toList()..sort(),
      'pendingState': state,
      'controllerBusy': controller.busy,
      'controllerStatus': controller.status.name,
      'gates': {
        'errorFocused': focused.contains('error'),
        'rotateTapped': tapped.contains('rotate'),
        'hideTapped': tapped.contains('hide'),
        'confirmationFocused': focused.contains('confirmation'),
        'confirmTapped': tapped.contains('confirm'),
        'pendingIsUnknown': state == 'UNKNOWN',
        'unknownFocused': focused.contains('unknown'),
        'queryTapped': tapped.contains('query'),
        'pendingIsCommitted': state == 'COMMITTED',
        'committedFocused': focused.contains('committed'),
        'ackTapped': tapped.contains('ack'),
        'pendingCleared': state == 'NONE',
      },
      'publicNodes': publicNodes(),
      'recentPublicEvents': List<Map<String, Object>>.from(publicEvents),
    };
    final temporary = File('${diagnostic.path}.tmp');
    await temporary.writeAsString(jsonEncode(snapshot), flush: true);
    await temporary.rename(diagnostic.path);
  }

  Future<void> persistDiagnostic(String reason) {
    diagnosticTail = diagnosticTail
        .then((_) => writeDiagnostic(reason))
        .catchError((Object _) {
          diagnosticWriteFailures++;
        });
    return diagnosticTail;
  }

  Future<void> publicStage(String stage, List<String> requiredTargets) async {
    currentStage = stage;
    requiredPublicTargets = List<String>.from(requiredTargets);
    // Durable state can change between the preceding pump and an async read.
    // Wait for actual rendered semantics before checking the new page.
    final renderDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(renderDeadline)) {
      await tester.pump(const Duration(milliseconds: 150));
      final currentNodes = publicNodes();
      if (requiredTargets.every(
        (name) => currentNodes.any(
          (node) =>
              node['isHidden'] == false &&
              (node['publicTargets'] as List<String>).contains(name),
        ),
      )) {
        break;
      }
    }
    final candidates = publicNodes();
    missingPublicTargets = requiredTargets
        .where(
          (name) => !candidates.any(
            (node) =>
                node['isHidden'] == false &&
                (node['publicTargets'] as List<String>).contains(name),
          ),
        )
        .toList();
    await persistDiagnostic(
      missingPublicTargets.isEmpty ? 'stage-preflight' : 'stage-preflight-fail',
    );
    expect(diagnosticWriteFailures, 0);
    expect(
      missingPublicTargets,
      isEmpty,
      reason: 'Public TalkBack preflight targets missing',
    );
    await _stage(stage);
  }

  Future<void> publicWait(
    FutureOr<bool> Function() ready,
    String label, {
    int seconds = 180,
  }) async {
    var savedAt = DateTime.fromMillisecondsSinceEpoch(0);
    await _wait(
      tester,
      () async {
        final complete = await ready();
        final now = DateTime.now();
        if (complete || now.difference(savedAt).inSeconds >= 2) {
          await persistDiagnostic(complete ? 'gate-satisfied' : 'gate-waiting');
          expect(diagnosticWriteFailures, 0);
          savedAt = now;
        }
        return complete;
      },
      label,
      seconds: seconds,
    );
  }

  void observe(ui.SemanticsActionEvent event) {
    final isFocus = event.type == ui.SemanticsAction.didGainAccessibilityFocus;
    final isTap = event.type == ui.SemanticsAction.tap;
    final actionName = isFocus
        ? 'didGainAccessibilityFocus'
        : isTap
        ? 'tap'
        : event.type == ui.SemanticsAction.focus
        ? 'focus'
        : event.type == ui.SemanticsAction.didLoseAccessibilityFocus
        ? 'didLoseAccessibilityFocus'
        : event.type == ui.SemanticsAction.showOnScreen
        ? 'showOnScreen'
        : null;
    if (actionName == null) return;
    rawActionCounts[actionName] = (rawActionCounts[actionName] ?? 0) + 1;
    if (isFocus) rawFocusCount++;
    if (isTap) rawTapCount++;
    SemanticsNode? target;
    void visit(SemanticsNode node) {
      if (node.id == event.nodeId) target = node;
      if (target == null) {
        node.visitChildren((child) {
          visit(child);
          return target == null;
        });
      }
    }

    var foundView = false;
    for (final view in binding.renderViews) {
      if (view.flutterView.viewId != event.viewId) continue;
      foundView = true;
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) visit(root);
    }
    if (!foundView) viewLookupMissCount++;
    if (target == null) nodeLookupMissCount++;
    final data = target?.getSemanticsData();
    final labels = data == null ? <String>[] : matches(data.label);
    final hints = data == null ? <String>[] : matches(data.hint);
    final names = {...labels, ...hints}.toList()..sort();
    for (final name in labels) {
      labelMatchCounts[name] = (labelMatchCounts[name] ?? 0) + 1;
    }
    for (final name in hints) {
      hintMatchCounts[name] = (hintMatchCounts[name] ?? 0) + 1;
    }
    if (isFocus && target != null) {
      focusCount++;
      focused.addAll(names);
      for (final name in names) {
        publicFocusCounts[name] = (publicFocusCounts[name] ?? 0) + 1;
      }
    }
    if (isTap && target != null) {
      tapCount++;
      tapped.addAll(names);
      for (final name in names) {
        publicTapCounts[name] = (publicTapCounts[name] ?? 0) + 1;
      }
    }
    publicEvents.add({
      'type': actionName,
      'viewId': event.viewId,
      'nodeId': event.nodeId,
      'viewFound': foundView,
      'nodeFound': target != null,
      'publicTargets': names,
      'labelMatches': labels,
      'hintMatches': hints,
      'stage': currentStage,
    });
    if (publicEvents.length > 64) publicEvents.removeAt(0);
    unawaited(persistDiagnostic('platform-event'));
  }

  binding.addSemanticsActionListener(observe);
  try {
    await _stage('ni-talkback-enable');
    await _wait(
      tester,
      () =>
          binding.platformDispatcher.semanticsEnabled &&
          binding.platformDispatcher.accessibilityFeatures.accessibleNavigation,
      'actual TalkBack enabled',
      seconds: 240,
    );
    await _hostAck('ni-talkback-loaded');
    await _prepareTalkBackInput(
      tester,
      'management-password',
      'Wrong-OnlySynthetic-Password#7',
    );
    await _tap(tester, find.text('轮换恢复码'));
    await _wait(
      tester,
      () => controller.errorMessage != null,
      'actual invalid password error',
    );
    await tester.ensureVisible(find.text(controller.errorMessage!));
    await tester.pump(const Duration(milliseconds: 200));
    await publicStage('ni-talkback-error', ['error']);
    await publicWait(
      () => focused.contains('error'),
      'human actual error focus',
      seconds: 300,
    );
    await _prepareTalkBackInput(tester, 'management-password', password);
    await tester.ensureVisible(find.text('轮换恢复码'));
    await tester.pump(const Duration(milliseconds: 200));
    await publicStage('ni-talkback-rotate', ['rotate']);
    await publicWait(
      () => tapped.contains('rotate') && controller.recoveryCode != null,
      'human rotation action',
      seconds: 180,
    );
    final code = controller.recoveryCode!;
    await tester.ensureVisible(find.text('我已保存，隐藏原码并确认'));
    await tester.pump(const Duration(milliseconds: 200));
    await publicStage('ni-talkback-hide', ['hide']);
    await publicWait(
      () =>
          tapped.contains('hide') &&
          find
              .byKey(const ValueKey('rotation-confirmation'))
              .evaluate()
              .isNotEmpty,
      'human hide recovery code',
      seconds: 180,
    );
    await _prepareTalkBackInput(tester, 'rotation-confirmation', code);
    await tester.ensureVisible(
      find.byKey(const ValueKey('rotation-confirmation')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await publicStage('ni-talkback-confirm', ['confirmation', 'confirm']);
    await publicWait(
      () async =>
          focused.contains('confirmation') &&
          tapped.contains('confirm') &&
          !controller.busy &&
          (await store.read()).pendingCredentialChange?['state'] == 'UNKNOWN',
      'human confirmation with actual lost response',
      seconds: 180,
    );
    final original = (await store.read()).pendingCredentialChange!;
    await publicStage('ni-talkback-unknown', ['unknown', 'query']);
    await publicWait(
      () async =>
          focused.contains('unknown') &&
          tapped.contains('query') &&
          (await store.read()).pendingCredentialChange?['state'] == 'COMMITTED',
      'human original result query',
      seconds: 180,
    );
    final committed = (await store.read()).pendingCredentialChange!;
    expect(
      committed['key'] == original['key'] &&
          committed['intentId'] == original['intentId'],
      true,
    );
    await publicStage('ni-talkback-ack', ['committed', 'ack']);
    await publicWait(
      () async =>
          focused.contains('committed') &&
          tapped.contains('ack') &&
          (await store.read()).pendingCredentialChange == null,
      'human acknowledgement',
      seconds: 180,
    );
    fixture['recoveryCode'] = code; // Owned encrypted test marker only.
    await marker.write(jsonEncode(fixture));
    final originalMarker = FlutterAuthVault(
      namespace: 'native.security.test.$_accountRun.batch',
    );
    final originalFixture =
        jsonDecode(await originalMarker.read() ?? '{}') as Map<String, dynamic>;
    expect(originalFixture['accountId'] == fixture['accountId'], true);
    await originalMarker.write(
      jsonEncode({...originalFixture, 'recoveryCode': code}),
    );
    flags['actualTalkBackErrorConfirmationUnknownAndTerminalActions'] = true;
    flags['originalUnknownKeyAndIntentReconciledWithoutNewConfirmation'] = true;
    flags['actualPlatformFocusEvents'] = focusCount;
    flags['actualPlatformTapEvents'] = tapCount;
    flags['syntheticFieldPreparationUsesProductTextControllers'] = true;
    flags['textInputPlatformAcceptance'] = false;
    flags['focusedPublicTargets'] = focused.toList()..sort();
    flags['tappedPublicTargets'] = tapped.toList()..sort();
  } finally {
    binding.removeSemanticsActionListener(observe);
    await persistDiagnostic('finished-or-failed');
  }
}

int _count(Map<String, dynamic> value, String key) => value[key] as int? ?? 0;
Future<void> _publishVm(String phase, {bool restart = false}) async {
  var vm = await developer.Service.getInfo();
  if (restart) {
    await developer.Service.controlWebServer(enable: false);
    vm = await developer.Service.controlWebServer(enable: true);
  } else if (vm.serverUri == null) {
    vm = await developer.Service.controlWebServer(enable: true);
  }
  final uri = vm.serverUri!;
  expect(
    uri.scheme == 'http' && uri.host == '127.0.0.1' && uri.port >= 1024,
    true,
  );
  await File('${_privateFiles}owned-device-driver-vm.json').writeAsString(
    jsonEncode({'pid': pid, 'phase': phase, 'uri': uri.toString()}),
  );
}

Map<String, Object> _publicLife(Map<String, dynamic> value) => {
  for (final key in [
    'activityCreated',
    'activityDestroyed',
    'engineAttached',
    'configurationChanged',
    'resumed',
    'paused',
  ])
    key: _count(value, key),
};
Future<Map<String, dynamic>> _life() async => Map<String, dynamic>.from(
  (await _driver.invokeMapMethod<String, dynamic>('acceptanceLifecycle'))!,
);
Future<Map<String, dynamic>> _nativeState() async => Map<String, dynamic>.from(
  (await _native.invokeMapMethod<String, dynamic>('acceptanceState'))!,
);
Future<void> _stage(String value) => _driver.invokeMethod<void>('stage', value);
Future<Map<String, dynamic>> _hostAck(String stage) async {
  final end = DateTime.now().add(const Duration(seconds: 100));
  final file = File('$_privateFiles${stage.replaceAll('-', '_')}.json');
  while (DateTime.now().isBefore(end)) {
    if (await file.exists()) {
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (value['pid'] == pid &&
          value['stage'] == stage &&
          value['observed'] == true) {
        return value;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Owned host acknowledgement missing: $stage');
}

SecurityManagementController _securityController(WidgetTester tester) => tester
    .widget<SecurityManagementScreen>(find.byType(SecurityManagementScreen))
    .controller;

/// Prepare owned synthetic secrets without opening the IME during TalkBack.
/// NI-U03 accepts real accessibility focus/tap actions and actual C results;
/// physical typing and composing input have a separate device acceptance case.
Future<void> _prepareTalkBackInput(
  WidgetTester tester,
  String key,
  String value,
) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(
    tester,
    () =>
        finder.evaluate().length == 1 &&
        tester.widget<TextFormField>(finder).enabled != false,
    'enabled synthetic TalkBack field',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 150));
  final controller = tester.widget<TextFormField>(finder).controller!;
  controller.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
  await tester.pump(const Duration(milliseconds: 200));
  expect(controller.text == value, true);
}

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String label, {
  int seconds = 60,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (await ready()) return;
  }
  throw StateError('Fixed B1/B2 stage timed out: $label');
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
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _input(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(
    tester,
    () =>
        finder.evaluate().length == 1 &&
        tester.widget<TextFormField>(finder).enabled != false,
    'enabled field',
  );
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 150));
  expect(tester.widget<TextFormField>(finder).controller!.text == value, true);
}

Future<void> _login(WidgetTester tester, String name, String password) async {
  await _tap(tester, find.text('登录或注册'));
  await _input(tester, 'login-username', name);
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

Future<void> _security(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('My content'));
  await _tap(tester, find.widgetWithText(ListTile, '设备与恢复凭据'));
  await _wait(
    tester,
    () =>
        find.byType(SecurityManagementScreen).evaluate().isNotEmpty &&
        !_securityController(tester).busy,
    'product credential route',
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
