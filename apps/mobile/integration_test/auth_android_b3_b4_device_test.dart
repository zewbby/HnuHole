import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

import 'owned_auth_device_helpers.dart';

const _driver = MethodChannel('hnuhole/owned_device_driver');
const _native = MethodChannel('hnuhole/auth_passkey');
const _accountRun = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
const _batch = '20261010-v16';
const _run = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
const _package = String.fromEnvironment(
  'AUTH_B3B4_PACKAGE',
  defaultValue: 'org.hnuhole.hnuhole_mobile',
);
String get _files => '/data/user/0/$_package/files/';
final _c = Uri.parse(const String.fromEnvironment('AUTH_COMMUNITY_BASE_URL'));
final _v = Uri.parse(const String.fromEnvironment('AUTH_VERIFIER_BASE_URL'));

/// Complete current product App, actual isolated C/V, native Keystore and
/// Credential Manager. Public reports contain booleans/counts, never secrets.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fixed B3/B4 actual Android boundaries',
    (tester) async {
      expect(
        Platform.isAndroid &&
            _run == 'hnuhole-android-live-matrix-20261006' &&
            _accountRun == 'hnuhole-android-live-b3-b4-20261009',
        true,
      );
      validateDevelopmentOrigins(_c, _v);
      final phase = (await _driver.invokeMethod<String>('phase'))!;
      final variant = (await _driver.invokeMethod<String>('variant'))!;
      expect(
        const {
          'ni-c01',
          'ni-d01',
          'ni-d02',
          'ni-d03',
          'ni-d04',
          'ni-d05',
          'ni-k01',
          'ni-k02',
        }.contains(phase),
        true,
      );
      if (phase.startsWith('ni-k')) {
        expect(_package == 'org.hnuhole.hnuhole_mobile.acceptance', true);
      }
      final vm = await developer.Service.getInfo();
      expect(vm.serverUri != null, true);
      await File('${_files}owned-device-driver-vm.json').writeAsString(
        jsonEncode({
          'pid': pid,
          'phase': phase,
          'uri': vm.serverUri.toString(),
        }),
      );
      final pointers = binding.shouldPropagateDevicePointerEvents;
      binding.shouldPropagateDevicePointerEvents = true;
      final flags = <String, Object>{};
      final api = _api();
      var accepted = false;
      try {
        app.main();
        await tester.pump();
        await _stage('ni-b3b4-ready');
        final ready = await tester.runAsync(() => _ack('ni-b3b4-ready'));
        final dynamic root = tester.widget(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_HnuholeApp',
          ),
        );
        final store = root.store as AuthStore;
        final sessions = root.sessions as AuthSessionController;
        final flows = root.flows as AuthFlows;
        final security = root.management as SecurityManagementController;
        final identities = root.identities as IdentityManagementController;
        final marker = FlutterAuthVault(
          namespace: 'native.security.test.$_accountRun.b3b4',
        );
        if (phase == 'ni-k01' && variant == 'no-key') {
          await waitOwned(
            tester,
            () => sessions.status == AuthStatus.storageFailure,
            'restored ciphertext has no device key',
          );
          expect(!sessions.isAuthenticated && store.current == null, true);
          await expectLater(store.read(), throwsA(isA<AuthStorageFailure>()));
          await expectLater(
            store.update((_) => const AuthState()),
            throwsA(isA<AuthStorageFailure>()),
          );
          await waitOwned(
            tester,
            () => find.text('安全存储暂不可用').evaluate().isNotEmpty,
            'actual storage-failure route rendered after native rejection',
          );
          flags['actualProductReadOverwriteAndAuthorityRejected'] = true;
        } else {
          await waitOwned(
            tester,
            () => store.current != null && !sessions.busy,
            'product native state restored',
          );
          final fixture =
              jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
          if (phase == 'ni-k01' && variant == 'fresh') {
            final state = await store.read();
            expect(
              state.session == null &&
                  state.registration == null &&
                  state.pendingCredentialChange == null &&
                  state.pendingReset == null &&
                  state.pendingClosure == null &&
                  state.identityDrafts.isEmpty &&
                  state.identityChanges.isEmpty &&
                  !sessions.isAuthenticated,
              true,
            );
            expect(find.text('登录或注册').evaluate().isNotEmpty, true);
            flags['freshProductGuestWithoutAutomaticAuthentication'] = true;
          } else if (phase == 'ni-k02') {
            if (fixture.isEmpty) {
              await _ensureAccount(tester, store, fixture, phase, flags);
              await marker.write(jsonEncode(fixture));
            }
            await _storageFault(
              tester,
              variant,
              store,
              sessions,
              fixture,
              flags,
            );
            fixture['pid'] = pid;
            await marker.write(jsonEncode(fixture));
          } else {
            if (phase == 'ni-d02' &&
                variant == 'control' &&
                ready?['reuseAssociationControl'] == true &&
                store.current!.session == null) {
              await _loginExistingAssociationControl(
                tester,
                store,
                fixture,
                flags,
              );
            }
            await _ensureAccount(
              tester,
              store,
              fixture,
              phase,
              flags,
              variant: variant,
            );
            await marker.write(jsonEncode(fixture));
            if (const {
              'ni-c01',
              'ni-d01',
              'ni-d02',
              'ni-d03',
              'ni-d05',
            }.contains(phase)) {
              await _labelAccount(store.current!.session!.accountId);
            }
            if (phase == 'ni-c01' && variant == 'control') {
              await _unknownBindingClosure(
                tester,
                store,
                sessions,
                flows,
                security,
                fixture,
                marker,
                flags,
              );
            } else if (phase == 'ni-c01') {
              await _closure(
                tester,
                store,
                sessions,
                flows,
                security,
                identities,
                fixture,
                marker,
                flags,
              );
            } else if (phase == 'ni-d04') {
              await _tls(store, api, flags);
            } else if (phase == 'ni-d01') {
              await _rp(tester, store, security, api, fixture, flags);
            } else if (phase == 'ni-d02' || phase == 'ni-d03') {
              await security.load();
              final before = await _nativeState();
              await _ceremony(
                tester,
                security.bindPasskey(fixture['password'] as String),
                'ni-association-create',
              );
              final after = await _nativeState();
              if (variant == 'control') {
                expect(
                  security.status == SecurityManagementStatus.committed,
                  true,
                );
                await security.acknowledgeResult();
                flags['approvedPackageAndCertificateActualBinding'] = true;
              } else {
                expect(
                  security.error != null &&
                      _count(after, 'nativeBegun') ==
                          _count(before, 'nativeBegun') + 1 &&
                      _count(after, 'nativeErrored') ==
                          _count(before, 'nativeErrored') + 1 &&
                      _count(after, 'actualAssociationRejected') ==
                          _count(before, 'actualAssociationRejected') + 1 &&
                      store.current!.pendingCredentialChange == null,
                  true,
                  reason:
                      'Require actual association diagnosis, not generic native failure: ${_errorCounters(after)}',
                );
                flags['actualProviderAssociationRejectedBeforeProofSubmission'] =
                    true;
              }
            } else if (phase == 'ni-d05') {
              await _removal(tester, store, security, api, fixture, flags);
            } else if (phase == 'ni-k01') {
              if (variant == 'source') {
                await identities.load();
                expect(await identities.saveInitialDraft('重装前草稿'), true);
                fixture['sourceToken'] = store.current!.session!.token;
                fixture['sourceAccount'] = store.current!.session!.accountId;
                fixture['sourcePid'] = pid;
                flags['actualProductSessionAndDraftPersisted'] = true;
              } else {
                expect(
                  variant == 'restart' &&
                      fixture['sourcePid'] != pid &&
                      store.current!.session!.token == fixture['sourceToken'] &&
                      store.current!.session!.accountId ==
                          fixture['sourceAccount'] &&
                      sessions.isAuthenticated,
                  true,
                );
                await identities.load();
                expect(identities.initialNickname == '重装前草稿', true);
                flags['independentProcessRestoredExactSessionAndDraft'] = true;
              }
            }
            fixture['pid'] = pid;
            await marker.write(jsonEncode(fixture));
          }
        }
        binding.reportData = {
          'phase': phase,
          'variant': variant,
          'pid': pid,
          'applicationId': _package,
          'actualApp': true,
          'nativeVault': true,
          'actualCV':
              !(phase == 'ni-k01' && {'fresh', 'no-key'}.contains(variant)),
          'physicalImeClaimed': false,
          'rawProofStored': false,
          ...flags,
        };
        await _stage('ni-b3b4-complete');
        await tester.runAsync(() => _ack('ni-b3b4-complete'));
        accepted = true;
      } finally {
        api.close();
        binding.shouldPropagateDevicePointerEvents = pointers;
        if (accepted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 40)),
    skip: _run.isEmpty,
  );
}

HttpAuthApi _api({
  Duration timeout = const Duration(seconds: 12),
  Uri? community,
  HttpClient? client,
}) => HttpAuthApi(
  communityBaseUri: community ?? _c,
  verifierBaseUri: _v,
  passkeyRpId: developmentPasskeyRp(community: _c, verifier: _v),
  timeout: timeout,
  client: client ?? createAppHttpClient(community: _c, verifier: _v),
);

String _freshUsername(Map<String, dynamic> fixture, String stage) =>
    'dev_${AuthCrypto.domainDigest('B3B4-FRESH-USER', utf8.encode('$_accountRun|${fixture['username']}|$stage')).substring(0, 16)}'
        .replaceAll('-', '_')
        .toLowerCase();

Future<void> _ensureAccount(
  WidgetTester tester,
  AuthStore store,
  Map<String, dynamic> fixture,
  String phase,
  Map<String, Object> flags, {
  String variant = 'main',
}) async {
  if (phase == 'ni-c01' &&
      variant == 'main' &&
      fixture['draftCycleCompleted'] != true &&
      fixture['email'] is String &&
      store.current!.session == null &&
      store.current!.pendingClosure == null &&
      store.current!.registration != null) {
    expect(
      (store.current!.registration!['request'] as Map)['email'] ==
          fixture['email'],
      true,
    );
    expect(store.current!.registration!['commit'] == null, true);
    expect(
      store.current!.identityDrafts.containsKey(fixture['accountId']),
      true,
    );
    if (find.byType(AuthScreen).evaluate().isEmpty) {
      await tapOwned(tester, find.text('登录或注册'));
    }
    await waitOwned(
      tester,
      () => find.byType(AuthScreen).evaluate().isNotEmpty,
      'original product registration route',
    );
    if (find
            .byKey(const ValueKey('registration-username'))
            .evaluate()
            .isEmpty &&
        find.byKey(const ValueKey('registration-email')).evaluate().isEmpty) {
      await tapOwned(tester, find.text('新注册'));
    }
    flags['originalDraftRegistrationRetainedWithoutClosureResubmission'] = true;
    return;
  }
  if (fixture.isNotEmpty &&
      fixture['email'] is String &&
      store.current!.session == null &&
      store.current!.pendingClosure?['state'] == 'RELEASED') {
    // Reconcile the original terminal product receipt before a new complete
    // case. A disposed previous late controller cannot provide that evidence.
    await waitOwned(
      tester,
      () => find.text('创建全新账号').evaluate().isNotEmpty,
      'original released closure product action',
    );
    await tapOwned(tester, find.text('创建全新账号'));
    final name = _freshUsername(fixture, 'released');
    final marker = FlutterAuthVault(
      namespace: 'native.security.test.$_accountRun.b3b4',
    );
    final recovery = await registerOwned(
      tester,
      fixture['email'] as String,
      name,
      fixture['password'] as String,
      evidence: flags,
      onRecoveryPrepared: (code) async {
        fixture['nextUsername'] = name;
        fixture['nextRecovery'] = code;
        await marker.write(jsonEncode(fixture));
      },
    );
    fixture['priorClosedAccount'] = fixture['accountId'];
    fixture['username'] = name;
    fixture['recovery'] = recovery;
    fixture['accountId'] = store.current!.session!.accountId;
    if (phase == 'ni-c01' && variant == 'main') {
      fixture['priorDraftCycleCompleted'] = fixture['draftCycleCompleted'];
      fixture['draftCycleCompleted'] = false;
    }
    flags['terminalOriginalClosureReconciledBeforeFreshCompleteCase'] = true;
    await marker.write(jsonEncode(fixture));
    return;
  }
  if (phase == 'ni-c01' &&
      fixture.isNotEmpty &&
      fixture['draftCycleCompleted'] != true &&
      store.current!.session == null &&
      store.current!.pendingClosure != null) {
    // Resume this original closure, never try the already closed password.
    expect(
      {'PENDING', 'RELEASED'}.contains(store.current!.pendingClosure?['state']),
      true,
    );
    return;
  }
  if (store.current!.session != null) {
    if (fixture['accountId'] != store.current!.session!.accountId &&
        fixture['email'] != null &&
        store.current!.pendingClosure == null &&
        store.current!.pendingReset == null) {
      final api = _api();
      try {
        final actual = await api.currentSession(store.current!.session!.token);
        final next = '${fixture['username']}_new';
        expect(
          actual.accountId == store.current!.session!.accountId &&
              actual.username == next,
          true,
          reason: 'Only reconcile the already committed same-email replacement fixture',
        );
        fixture['reconciledClosedAccount'] = fixture['accountId'];
        fixture['username'] = next;
        fixture['accountId'] = actual.accountId;
        fixture.remove('recovery');
        flags['originalCommittedReplacementFixtureReconciledWithoutNewRegistration'] =
            true;
      } finally {
        api.close();
      }
    }
    expect(fixture['accountId'] == store.current!.session!.accountId, true);
    return;
  }
  if (store.current!.registration != null && store.current!.session == null) {
    final registration = store.current!.registration!;
    expect(
      registration['commit'] == null,
      true,
      reason:
          'Reconcile an unresolved registration commit before changing input',
    );
    final email = (registration['request'] as Map)['email'] as String;
    final seed = '$_accountRun-$_batch-$_package-$phase';
    fixture['email'] = email;
    fixture['username'] =
        'dev_${AuthCrypto.domainDigest('B3B4-USER', utf8.encode(seed)).substring(0, 8)}'
            .replaceAll('-', '_')
            .toLowerCase();
    fixture['password'] =
        'Dev-${AuthCrypto.domainDigest('B3B4-PASSWORD', utf8.encode(seed))}#9';
    if (find.byType(AuthScreen).evaluate().isEmpty) {
      await tapOwned(tester, find.text('登录或注册'));
    }
    if (find
            .byKey(const ValueKey('registration-username'))
            .evaluate()
            .isEmpty &&
        find.byKey(const ValueKey('registration-email')).evaluate().isEmpty) {
      await tapOwned(tester, find.text('新注册'));
    }
    final marker = FlutterAuthVault(
      namespace: 'native.security.test.$_accountRun.b3b4',
    );
    fixture['recovery'] = await registerOwned(
      tester,
      email,
      fixture['username'] as String,
      fixture['password'] as String,
      evidence: flags,
      onRecoveryPrepared: (code) async {
        fixture['recovery'] = code;
        await marker.write(jsonEncode(fixture));
      },
    );
    fixture['accountId'] = store.current!.session!.accountId;
    flags['originalUncommittedRegistrationContinuedWithoutDiscard'] = true;
    return;
  }
  if (fixture.isNotEmpty ||
      variant == 'bad-signature' ||
      variant == 'missing-package') {
    if (fixture.isEmpty) {
      const controlPackage = 'org.hnuhole.hnuhole_mobile.acceptance';
      const controlSeed = '$_accountRun-$_batch-$controlPackage-ni-d02';
      fixture['username'] =
          'dev_${AuthCrypto.domainDigest('B3B4-USER', utf8.encode(controlSeed)).substring(0, 8)}'
              .replaceAll('-', '_')
              .toLowerCase();
      fixture['password'] =
          'Dev-${AuthCrypto.domainDigest('B3B4-PASSWORD', utf8.encode(controlSeed))}#9';
    }
    expect(
      store.current!.pendingClosure == null &&
          store.current!.pendingReset == null &&
          store.current!.pendingCredentialChange == null &&
          store.current!.registration == null,
      true,
      reason: 'Never discard or replay an unresolved original operation',
    );
    await tapOwned(tester, find.text('登录或注册'));
    await inputOwned(tester, 'login-username', fixture['username'] as String);
    await inputOwned(tester, 'login-password', fixture['password'] as String);
    await tapOwned(tester, find.text('登录并进入'));
    await waitOwned(
      tester,
      () =>
          store.current!.session != null &&
          find.byType(AuthScreen).evaluate().isEmpty,
      'explicit product test account login',
    );
    fixture['accountId'] = store.current!.session!.accountId;
    return;
  }
  final seed = '$_accountRun-$_batch-$_package-$phase';
  fixture['email'] =
      'b3b4-${DateTime.now().microsecondsSinceEpoch}@hainanu.edu.cn';
  fixture['username'] =
      'dev_${AuthCrypto.domainDigest('B3B4-USER', utf8.encode(seed)).substring(0, 8)}'
          .replaceAll('-', '_')
          .toLowerCase();
  fixture['password'] =
      'Dev-${AuthCrypto.domainDigest('B3B4-PASSWORD', utf8.encode(seed))}#9';
  await tapOwned(tester, find.text('登录或注册'));
  await tapOwned(tester, find.text('新注册'));
  fixture['recovery'] = await registerOwned(
    tester,
    fixture['email'] as String,
    fixture['username'] as String,
    fixture['password'] as String,
    evidence: flags,
  );
  fixture['accountId'] = store.current!.session!.accountId;
}

Future<void> _loginExistingAssociationControl(
  WidgetTester tester,
  AuthStore store,
  Map<String, dynamic> fixture,
  Map<String, Object> flags,
) async {
  expect(
    store.current!.registration?['commit'] == null &&
        store.current!.pendingReset == null &&
        store.current!.pendingClosure == null &&
        store.current!.pendingCredentialChange == null,
    true,
    reason: 'Never replace an unknown original operation with a control login',
  );
  const controlPackage = 'org.hnuhole.hnuhole_mobile.acceptance';
  const seed = '$_accountRun-$_batch-$controlPackage-ni-d02';
  fixture['username'] =
      'dev_${AuthCrypto.domainDigest('B3B4-USER', utf8.encode(seed)).substring(0, 8)}'
          .replaceAll('-', '_')
          .toLowerCase();
  fixture['password'] =
      'Dev-${AuthCrypto.domainDigest('B3B4-PASSWORD', utf8.encode(seed))}#9';
  if (find.byType(AuthScreen).evaluate().isEmpty) {
    await tapOwned(tester, find.text('登录或注册'));
  }
  if (find.byKey(const ValueKey('login-username')).evaluate().isEmpty) {
    await tapOwned(tester, find.text('登录'));
  }
  await inputOwned(tester, 'login-username', fixture['username'] as String);
  await inputOwned(tester, 'login-password', fixture['password'] as String);
  await tapOwned(tester, find.text('登录并进入'));
  await waitOwned(
    tester,
    () =>
        store.current!.session != null &&
        find.byType(AuthScreen).evaluate().isEmpty,
    'existing approved association control logged in through product UI',
  );
  fixture['accountId'] = store.current!.session!.accountId;
  flags['existingAssociationControlReusedThroughProductLogin'] = true;
}

Future<void> _closure(
  WidgetTester tester,
  AuthStore store,
  AuthSessionController sessions,
  AuthFlows flows,
  SecurityManagementController security,
  IdentityManagementController identities,
  Map<String, dynamic> fixture,
  FlutterAuthVault marker,
  Map<String, Object> flags,
) async {
  // Check an actual discoverable assertion before any further formal closure.
  // No assertion is posted here; a provider/codec failure stops the batch early.
  if (store.current!.session != null &&
      fixture['assertionPreflightBatch'] != _batch) {
    await _labelAccount(store.current!.session!.accountId);
    await security.load();
    await _removeOwnedPasskeys(security, fixture['password'] as String);
    await _ceremony(
      tester,
      security.bindPasskey(fixture['password'] as String),
      'ni-preflight-binding',
    );
    expect(security.status == SecurityManagementStatus.committed, true);
    await security.acknowledgeResult();
    await security.load();
    final id = security.credentials!.passkeys.single.credentialId;
    final api = _api();
    try {
      await _assertion(
        tester,
        await api.createPasskeyResetOptions(),
        'ni-preflight-assertion',
        credentialId: id,
      );
    } finally {
      api.close();
    }
    await _removeOwnedPasskeys(security, fixture['password'] as String);
    fixture['assertionPreflightBatch'] = _batch;
    fixture['draftCycleCompleted'] = false;
    await marker.write(jsonEncode(fixture));
    await _checkpoint(tester, 'ni-assertion-preflight-passed');
    flags['actualDiscoverableAssertionPreflightBeforeClosure'] = true;
  }
  if (fixture['draftCycleCompleted'] != true) {
    // First prove actual pending draft isolation while the old account still
    // owns a draft. A subsequent identity creation normally consumes that draft;
    // absence after consumption alone would not test closure/new-account reuse.
    await identities.load();
    final draftAccount = fixture['accountId'] as String;
    final resumingRegistration =
        store.current!.session == null &&
        store.current!.pendingClosure == null &&
        store.current!.registration != null;
    if (resumingRegistration) {
      expect(
        (store.current!.registration!['request'] as Map)['email'] ==
            fixture['email'],
        true,
      );
      expect(store.current!.registration!['commit'] == null, true);
      expect(store.current!.identityDrafts[draftAccount] != null, true);
      await _checkpoint(tester, 'ni-resume-formal-close-draft');
    } else if (store.current!.pendingClosure == null) {
      expect(store.current!.session!.accountId == draftAccount, true);
      expect(await identities.saveInitialDraft('关闭前隔离草稿'), true);
      await _accountRoute(tester);
      await flows.requestClosure(fixture['password'] as String);
      expect(
        store.current!.pendingClosure?['state'] == 'PENDING' &&
            store.current!.session == null &&
            store.current!.identityDrafts[draftAccount] != null,
        true,
      );
      await _checkpoint(tester, 'ni-formal-close-draft');
    } else {
      expect(store.current!.identityDrafts[draftAccount] != null, true);
      flags['originalDraftClosureResumedWithoutResubmission'] = true;
    }
    if (!resumingRegistration) {
      await flows.reconcileClosure();
      expect(store.current!.pendingClosure?['state'] == 'RELEASED', true);
      await waitOwned(
        tester,
        () => find.text('创建全新账号').evaluate().isNotEmpty,
        'draft closure released',
      );
      await tapOwned(tester, find.text('创建全新账号'));
    }
    final draftFreshName = _freshUsername(fixture, 'draft');
    fixture['recovery'] = await registerOwned(
      tester,
      fixture['email'] as String,
      draftFreshName,
      fixture['password'] as String,
      evidence: flags,
      onRecoveryPrepared: (code) async {
        fixture['nextUsername'] = draftFreshName;
        fixture['nextRecovery'] = code;
        await marker.write(jsonEncode(fixture));
      },
    );
    final draftFresh = store.current!.session!;
    expect(
      draftFresh.accountId != draftAccount &&
          !store.current!.identityDrafts.containsKey(draftFresh.accountId),
      true,
    );
    await identities.load();
    expect(
      identities.initialNickname.isEmpty &&
          identities.directory?.createdCount == 0,
      true,
    );
    fixture['username'] = draftFreshName;
    fixture['accountId'] = draftFresh.accountId;
    fixture['draftCycleCompleted'] = true;
    await marker.write(jsonEncode(fixture));
    await _labelAccount(draftFresh.accountId);
    flags['actualRetainedOldDraftNotInheritedAfterSeparateFormalClosure'] =
        true;
  } else {
    flags['draftClosureIsolationPreviouslyVerifiedInRetainedAttempt'] = true;
  }
  final old = store.current!.session!;
  await identities.load();
  if (identities.directory!.identities.isEmpty) {
    expect(await identities.saveInitialDraft('关闭前隔离草稿'), true);
  }
  expect(
    identities.directory!.createdCount ==
            identities.directory!.identities.length &&
        identities.directory!.identities.length <= 2,
    true,
  );
  for (var i = identities.directory!.identities.length + 1; i <= 2; i++) {
    await identities.create('关闭身份$i');
    expect(identities.directory?.identities.length == i, true);
  }
  await security.load();
  if (security.credentials!.passkeys.isEmpty) {
    await _ceremony(
      tester,
      security.bindPasskey(fixture['password'] as String),
      'ni-closure-first-binding',
    );
    expect(security.status == SecurityManagementStatus.committed, true);
    await security.acknowledgeResult();
  } else {
    expect(
      security.credentials!.passkeys.length == 1 &&
          store.current!.pendingCredentialChange == null,
      true,
    );
    flags['originalActuallyCommittedBindingRecoveredWithoutResubmission'] =
        true;
  }
  final slow = _api(timeout: const Duration(seconds: 1200));
  final preflightApi = _api();
  try {
    await _assertion(
      tester,
      await preflightApi.createPasskeyResetOptions(),
      'ni-identity-preflight-assertion',
      credentialId: security.credentials!.passkeys.single.credentialId,
    );
  } finally {
    preflightApi.close();
  }
  await _checkpoint(tester, 'ni-identity-assertion-preflight-passed');
  final lateSecurity = SecurityManagementController(
    api: slow,
    store: store,
    passkey: NativePasskeyClient(),
    sessions: sessions,
  );
  final lateIdentity = IdentityManagementController(
    api: slow,
    store: store,
    sessions: sessions,
  );
  Future<void>? pendingIdentity;
  try {
    await lateSecurity.load();
    await lateIdentity.load();
    await _checkpoint(tester, 'ni-hold-two');
    pendingIdentity = lateIdentity.create('关闭身份3');
    await waitOwned(
      tester,
      () => store.current!.identityChanges[old.accountId] != null,
      'actual identity original UNKNOWN',
    );
    await _checkpoint(tester, 'ni-identity-reply-held');
    final originalIdentity = Map<String, dynamic>.from(
      store.current!.identityChanges[old.accountId] as Map,
    );
    final credentials = await slow.recoveryCredentials(old.token);
    final ids = credentials.passkeys.map((e) => e.credentialId).toSet();
    expect(ids.length == 1, true);
    fixture['closedCredentialId'] = ids.single;
    fixture['oldToken'] = old.token;
    fixture['oldAccount'] = old.accountId;
    await marker.write(jsonEncode(fixture));
    await _accountRoute(tester);
    await flows.requestClosure(fixture['password'] as String);
    expect(
      store.current!.session == null &&
          store.current!.pendingClosure?['state'] == 'PENDING' &&
          !sessions.isAuthenticated,
      true,
    );
    final originalClosure = Map<String, dynamic>.from(
      store.current!.pendingClosure!,
    );
    await _checkpoint(tester, 'ni-formal-close');
    await flows.reconcileClosure();
    expect(store.current!.pendingClosure?['state'] == 'RELEASED', true);
    final api = _api();
    try {
      final options = await api.createPasskeyResetOptions();
      final assertion = await _assertion(
        tester,
        options,
        'ni-closed-assertion',
        credentialId: ids.single,
      );
      expect(
        ids.contains(assertion['id']),
        true,
        reason: 'Actual system assertion must identify this closed account credential',
      );
      await _unauthorized(
        api.createPasskeyResetIntent(
          challengeId: options.challengeId,
          assertion: assertion,
        ),
      );
      await _unauthorized(api.currentSession(old.token));
      await _unauthorized(
        api.login(
          username: fixture['username'] as String,
          password: fixture['password'] as String,
          installationId: store.current!.cInstallationId!,
          idempotencyKey: AuthCrypto.randomEncoded(32),
        ),
      );
      await _unauthorized(
        api.createCodeResetIntent(fixture['recovery'] as String),
      );
      flags['closedSystemCredentialActualAssertionRejected'] = true;
      await waitOwned(
        tester,
        () => find.text('创建全新账号').evaluate().isNotEmpty,
        'released closure page',
      );
      await tapOwned(tester, find.text('创建全新账号'));
      final username = _freshUsername(fixture, 'identity-closed');
      fixture['recovery'] = await registerOwned(
        tester,
        fixture['email'] as String,
        username,
        fixture['password'] as String,
        evidence: flags,
        onRecoveryPrepared: (code) async {
          fixture['nextUsername'] = username;
          fixture['nextRecovery'] = code;
          await marker.write(jsonEncode(fixture));
        },
      );
      final fresh = store.current!.session!;
      expect(fresh.accountId != old.accountId, true);
      expect(store.current!.pendingCredentialChange == null, true);
      await _checkpoint(tester, 'ni-release-old-replies');
      await tester.runAsync(() async {
        await pendingIdentity!;
      });
      expect(
        store.current!.session?.token == fresh.token &&
            sessions.isAuthenticated &&
            store.current!.pendingCredentialChange == null &&
            !store.current!.identityChanges.containsKey(fresh.accountId) &&
            !store.current!.identityDrafts.containsKey(fresh.accountId),
        true,
      );
      await _unauthorized(
        api.identityChangeResult(
          sessionToken: old.token,
          idempotencyKey: originalIdentity['key'] as String,
        ),
      );
      final again = await api.closureStatus(
        closureId: originalClosure['closureId'] as String,
        statusSecret: originalClosure['statusSecret'] as String,
      );
      final directory = await api.identities(fresh.token);
      final newCredentials = await api.recoveryCredentials(fresh.token);
      expect(
        again.state == ClosureState.released &&
            directory.createdCount == 0 &&
            directory.identities.isEmpty &&
            newCredentials.passkeys.isEmpty &&
            store.current!.session!.token == fresh.token,
        true,
      );
      fixture['accountId'] = fresh.accountId;
      fixture['username'] = username;
      flags.addAll({
        'fixedCaseIds': ['NI-C01', 'NI-C03', 'NI-C04'],
        'actualNormalWorkerAndVerifierRelease': true,
        'actualIdentityDelayedReplyAfterFreshRegistration': true,
        'originalUnknownAnchorsRetainedUntilExplicitOwnerScopedEnd': true,
        'lateOriginalResponsesAndQueriesCannotMutateNewAccount': true,
        'sameExactEmailFreshAccountNoInheritedCredentialIdentityHistoryDraft':
            true,
        'controlledReplyHoldTransportTimeoutSeconds': 1200,
        'simulatedGateTime': true,
        'sqlDeadlineAndDeviceClockUnchanged': true,
      });
    } finally {
      api.close();
    }
  } finally {
    lateSecurity.dispose();
    lateIdentity.dispose();
    slow.close();
  }
}

Future<void> _unknownBindingClosure(
  WidgetTester tester,
  AuthStore store,
  AuthSessionController sessions,
  AuthFlows flows,
  SecurityManagementController security,
  Map<String, dynamic> fixture,
  FlutterAuthVault marker,
  Map<String, Object> flags,
) async {
  expect(_package == 'org.hnuhole.hnuhole_mobile.acceptance', true);
  final old = store.current!.session!;
  await security.load();
  expect(security.credentials!.passkeys.isEmpty, true);
  final slow = _api(timeout: const Duration(seconds: 1200));
  final late = SecurityManagementController(
    api: slow,
    store: store,
    passkey: NativePasskeyClient(),
    sessions: sessions,
  );
  try {
    await late.load();
    await _checkpoint(tester, 'ni-hold-two');
    final operation = late.bindPasskey(fixture['password'] as String);
    await _stage('ni-unknown-binding');
    await tester.runAsync(() => _ack('ni-unknown-binding'));
    await waitOwned(
      tester,
      () => store.current!.pendingCredentialChange?['state'] == 'UNKNOWN',
      'first actual binding original UNKNOWN persisted',
    );
    await _checkpoint(tester, 'ni-unknown-reply-held');
    final original = Map<String, dynamic>.from(
      store.current!.pendingCredentialChange!,
    );
    expect(
      (await slow.recoveryCredentials(old.token)).passkeys.length == 1,
      true,
    );
    await _accountRoute(tester);
    await flows.requestClosure(fixture['password'] as String);
    expect(
      store.current!.session == null &&
          store.current!.pendingClosure?['state'] == 'PENDING',
      true,
    );
    await _checkpoint(tester, 'ni-formal-close-unknown');
    await flows.reconcileClosure();
    expect(store.current!.pendingClosure?['state'] == 'RELEASED', true);
    await waitOwned(
      tester,
      () => find.text('创建全新账号').evaluate().isNotEmpty,
      'unknown binding account formally released',
    );
    await tapOwned(tester, find.text('创建全新账号'));
    final name = _freshUsername(fixture, 'binding-closed');
    fixture['recovery'] = await registerOwned(
      tester,
      fixture['email'] as String,
      name,
      fixture['password'] as String,
      evidence: flags,
      onRecoveryPrepared: (code) async {
        fixture['nextUsername'] = name;
        fixture['nextRecovery'] = code;
        await marker.write(jsonEncode(fixture));
      },
    );
    final fresh = store.current!.session!;
    expect(fresh.accountId != old.accountId, true);
    await security.load();
    expect(
      security.status == SecurityManagementStatus.previousSessionPending &&
          store.current!.pendingCredentialChange?['key'] == original['key'],
      true,
    );
    await security.abandonPending();
    await _checkpoint(tester, 'ni-release-unknown-replies');
    await tester.runAsync(() => operation);
    await _unauthorized(
      slow.credentialChangeResult(
        sessionToken: old.token,
        changeId: original['intentId'] as String,
        idempotencyKey: original['key'] as String,
      ),
    );
    final credentials = await slow.recoveryCredentials(fresh.token);
    expect(
      store.current!.session!.token == fresh.token &&
          sessions.isAuthenticated &&
          store.current!.pendingCredentialChange == null &&
          credentials.passkeys.isEmpty,
      true,
    );
    fixture['username'] = name;
    fixture['accountId'] = fresh.accountId;
    flags.addAll({
      'fixedCaseIds': ['NI-C02'],
      'actualFirstBindingCommittedWhileReplyHeld': true,
      'originalUnknownBindingRetainedAcrossFormalClosure': true,
      'lateOriginalBindingReplyAndQueryCannotMutateFreshAccount': true,
      'actualNormalWorkerAndVerifierRelease': true,
      'simulatedGateTime': true,
      'sqlDeadlineAndDeviceClockUnchanged': true,
    });
  } finally {
    late.dispose();
    slow.close();
  }
}

Future<void> _rp(
  WidgetTester tester,
  AuthStore store,
  SecurityManagementController security,
  HttpAuthApi api,
  Map<String, dynamic> fixture,
  Map<String, Object> flags,
) async {
  await security.load();
  await _removeOwnedPasskeys(security, fixture['password'] as String);
  final initial = await _nativeState();
  await _checkpoint(tester, 'ni-wrong-rp-options');
  await security.bindPasskey(fixture['password'] as String);
  final clientRejected = await _nativeState();
  expect(
    security.error != null &&
        _count(clientRejected, 'nativeBegun') == _count(initial, 'nativeBegun'),
    true,
  );
  await _checkpoint(tester, 'ni-normal');
  final options = await api.createPasskeyCreationOptions(
    sessionToken: store.current!.session!.token,
    password: fixture['password'] as String,
  );
  final wrong = Map<String, dynamic>.from(options.publicKey);
  wrong['rp'] = {
    ...(wrong['rp'] as Map),
    'id': 'unassociated.zewbby.github.io',
  };
  var rejected = false;
  final native = NativePasskeyClient();
  await _stage('ni-wrong-native-rp');
  final operation = native
      .create(wrong)
      .then<void>(
        (_) {},
        onError: (Object e) {
          rejected = e is PasskeyFailure;
        },
      );
  await _ceremony(tester, operation, 'ni-wrong-native-rp', publish: false);
  final nativeRejected = await _nativeState();
  final nativeAssociationRejected =
      rejected &&
      _count(nativeRejected, 'actualAssociationRejected') ==
          _count(clientRejected, 'actualAssociationRejected') + 1;
  // Complete the independent server boundary even if this provider exposes
  // only a generic/cancellation result. Such a result never accepts NI-D01.
  await File('${_files}owned-b3b4-rp-partial.json').writeAsString(
    jsonEncode({
      'pid': pid,
      'phase': 'ni-d01',
      'clientPinnedRpRejectedWithoutNativeStart': true,
      'actualNativeWrongRpAssociationRejected': nativeAssociationRejected,
      'nativeErrorCategories': _errorCounters(nativeRejected),
      'rawProofStored': false,
    }),
  );
  await _checkpoint(tester, 'ni-wrong-rp-hash');
  await _ceremony(
    tester,
    security.bindPasskey(fixture['password'] as String),
    'ni-server-rp-hash',
  );
  expect(
    security.error?.statusCode == 422 &&
        store.current!.pendingCredentialChange?['state'] == 'UNKNOWN',
    true,
  );
  await _stage('ni-original-expiry-wait');
  // Rejected proof does not prove a still-open original intent is terminal.
  // Query only its original anchor until the unchanged five-minute deadline.
  await tester.runAsync(() async {
    final end = DateTime.now().add(const Duration(seconds: 330));
    while (DateTime.now().isBefore(end)) {
      await security.reconcilePending();
      if (security.status == SecurityManagementStatus.notCommitted) break;
      expect(
        store.current!.pendingCredentialChange?['state'] == 'UNKNOWN',
        true,
      );
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  });
  expect(security.status == SecurityManagementStatus.notCommitted, true);
  await security.acknowledgeResult();
  flags.addAll({
    'clientPinnedRpRejectedWithoutNativeStart': true,
    'actualNativeWrongRpAssociationRejected': nativeAssociationRejected,
    'actualServerWrongRpHashRejected422': true,
    'originalResultQueriedWithoutProofReplay': true,
  });
  await File('${_files}owned-b3b4-rp-partial.json').writeAsString(
    jsonEncode({
      'pid': pid,
      'phase': 'ni-d01',
      ...flags,
      'rawProofStored': false,
    }),
  );
  expect(
    nativeAssociationRejected,
    true,
    reason: 'Native RP association diagnosis remains required; server rejection alone cannot accept NI-D01',
  );
}

Future<void> _removal(
  WidgetTester tester,
  AuthStore store,
  SecurityManagementController security,
  HttpAuthApi api,
  Map<String, dynamic> fixture,
  Map<String, Object> flags,
) async {
  await security.load();
  // Retire only this synthetic account's older keys to prepare one uniquely
  // labelled ceremony. Same-device duplicate enrollment is not a prerequisite
  // for removing one credential. Two-key retention is checked in real SQL.
  await _removeOwnedPasskeys(security, fixture['password'] as String);
  await _ceremony(
    tester,
    security.bindPasskey(fixture['password'] as String),
    'ni-removal-binding-1',
  );
  expect(security.status == SecurityManagementStatus.committed, true);
  await security.acknowledgeResult();
  final token = store.current!.session!.token;
  final ids = (await api.recoveryCredentials(token)).passkeys
      .map((e) => e.credentialId)
      .toSet();
  expect(ids.length == 1, true);
  final select = await api.createPasskeyResetOptions();
  final selected = await _assertion(
    tester,
    select,
    'ni-removal-select',
    credentialId: ids.first,
  );
  final target = selected['id'] as String;
  expect(
    ids.contains(target),
    true,
    reason: 'Select a credential created in this exact removal case',
  );
  await security.beginPasskeyRemoval(target, fixture['password'] as String);
  await security.confirmPasskeyRemoval();
  expect(security.status == SecurityManagementStatus.committed, true);
  await security.acknowledgeResult();
  final remaining = (await api.recoveryCredentials(token)).passkeys
      .map((e) => e.credentialId)
      .toSet();
  expect(
    !remaining.contains(target) &&
        ids.difference({target}).every(remaining.contains),
    true,
  );
  final options = await api.createPasskeyResetOptions();
  final assertion = await _assertion(
    tester,
    options,
    'ni-removed-assertion',
    credentialId: target,
  );
  expect(
    assertion['id'] == target,
    true,
    reason: 'Use the same removed system credential, never rewrite its id',
  );
  await _unauthorized(
    api.createPasskeyResetIntent(
      challengeId: options.challengeId,
      assertion: assertion,
    ),
  );
  expect(
    store.current!.session!.token == token &&
        (await api.currentSession(token)).username == fixture['username'],
    true,
  );
  // Successful recoveryCredentials reads require recoveryCodeAvailable=true;
  // the API rejects false/missing values. Verify before and after real removal.
  expect(fixture['recovery'] is String, true);
  flags.addAll({
    'productRemovalAndActualSameCredentialAssertionRejected': true,
    'currentSessionAndRecoveryCodeRetained': true,
    'otherPasskeyRetentionRequiresSeparateActualSqlEvidence': true,
    'recoveryCapabilityNotConsumed': true,
  });
}

Future<void> _tls(
  AuthStore store,
  HttpAuthApi api,
  Map<String, Object> flags,
) async {
  final token = store.current!.session!.token;
  await api.currentSession(token);
  final wrongCa = _api(
    client: HttpClient(context: SecurityContext(withTrustedRoots: false)),
  );
  final endpoint = _c.replace(host: 'b3b4-wrong-hostname.invalid');
  HttpClient wrongHostnameClient() =>
      createAppHttpClient(community: _c, verifier: _v)
        // Only the socket address changes. Dart still validates the TLS peer
        // against the URI hostname; the same valid C leaf lacks this DNS SAN.
        ..connectionFactory = (uri, proxyHost, proxyPort) async {
          expect(
            uri.host == endpoint.host &&
                uri.port == _c.port &&
                proxyHost == null,
            true,
          );
          final task = await Socket.startConnect('127.0.0.1', uri.port);
          final trust = SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificatesBytes(
              base64Decode(const String.fromEnvironment('AUTH_DEV_CA_BASE64')),
            );
          final secured = task.socket.then(
            (socket) =>
                SecureSocket.secure(socket, host: uri.host, context: trust),
          );
          return ConnectionTask.fromSocket<Socket>(secured, task.cancel);
        };
  final wrongHost = _api(community: endpoint, client: wrongHostnameClient());
  try {
    for (final candidate in [wrongCa, wrongHost]) {
      var refused = false;
      try {
        await candidate.currentSession(token);
      } on AuthFailure catch (e) {
        refused =
            e.kind == AuthFailureKind.unknownOutcome && e.statusCode == null;
      }
      expect(
        refused,
        true,
        reason:
            'Actual device transport refuses untrusted certificate or hostname',
      );
    }
    // HttpAuthApi deliberately maps TLS failures to uncertain transport. A
    // separate real-device handshake verifies the specific failure boundary.
    final handshakes = [
      (HttpClient(context: SecurityContext(withTrustedRoots: false)), _c),
      (wrongHostnameClient(), endpoint),
    ];
    for (final (client, origin) in handshakes) {
      var tlsRefused = false;
      try {
        final request = await client.getUrl(
          origin.resolve('/api/v1/auth/session'),
        );
        await request.close();
      } on HandshakeException {
        tlsRefused = true;
      } on TlsException {
        tlsRefused = true;
      } finally {
        client.close(force: true);
      }
      expect(
        tlsRefused,
        true,
        reason:
            'Require actual TLS rejection, not HTTP or unrelated network error',
      );
    }
    await api.currentSession(token);
    flags.addAll({
      'actualDeviceWrongCaRejected': true,
      'actualDeviceWrongHostnameRejected': true,
      'normalPinnedHttpsBeforeAndAfter': true,
      'tlsValidationDisabled': false,
    });
  } finally {
    wrongCa.close();
    wrongHost.close();
  }
}

Future<void> _storageFault(
  WidgetTester tester,
  String variant,
  AuthStore store,
  AuthSessionController sessions,
  Map<String, dynamic> fixture,
  Map<String, Object> flags,
) async {
  if (variant.endsWith('-read')) {
    expect(fixture['faultPid'] != pid, true);
    if (variant == 'write-failure-read') {
      expect(store.current!.session == null && !sessions.isAuthenticated, true);
    } else {
      expect(
        store.current!.session != null &&
            sessions.isAuthenticated &&
            sessions.username == fixture['username'],
        true,
      );
    }
    flags['independentProcessReadsOnlyActuallyDurableState'] = true;
    return;
  }
  expect(
    {'write-failure', 'write-unknown'}.contains(variant) &&
        fixture['username'] is String,
    true,
  );
  if (sessions.isAuthenticated) await sessions.logout();
  expect(
    store.current!.session == null && store.current!.cInstallationId != null,
    true,
  );
  await _checkpoint(tester, 'ni-arm-$variant');
  await sessions.login(
    fixture['username'] as String,
    fixture['password'] as String,
  );
  expect(
    !sessions.isAuthenticated &&
        store.current == null &&
        sessions.status == AuthStatus.storageFailure,
    true,
  );
  fixture['faultPid'] = pid;
  flags.addAll({
    'actualNativeKeystoreAtomicFileFault': true,
    'failedAcknowledgementPublishedNoAuthority': true,
    'isolatedTestBuildOnly': true,
    'faultBoundary': variant,
  });
}

Future<Map<String, dynamic>> _assertion(
  WidgetTester tester,
  PasskeyOptions options,
  String stage, {
  String? credentialId,
}) async {
  Map<String, dynamic>? value;
  final request = Map<String, dynamic>.from(options.publicKey);
  // Exercise the normal discoverable contract. Selection is human-readable via
  // a synthetic creation label; never fabricate a missing user handle or ID.
  final operation = NativePasskeyClient().get(request);
  await _ceremony(
    tester,
    operation.then((v) {
      value = v;
    }),
    stage,
  );
  expect(value != null, true);
  if (credentialId != null) {
    expect(
      value!['id'] == credentialId,
      true,
      reason:
          'Actual provider assertion must identify this exact test credential',
    );
  }
  return value!;
}

Future<void> _labelAccount(String accountId) async {
  final label =
      'HnuHole test ${AuthCrypto.domainDigest('B3B4-LABEL', utf8.encode(accountId)).substring(0, 8).toLowerCase()}';
  // Encode arbitrary digest alphabets as a fixed synthetic hexadecimal label.
  final hex = utf8
      .encode(label)
      .fold<int>(0, (v, b) => ((v * 31) + b) & 0xffffffff)
      .toRadixString(16)
      .padLeft(8, '0');
  final visible = 'HnuHole test $hex';
  await _native.invokeMethod<void>('acceptanceCreationLabel', visible);
  await File('${_files}owned-b3b4-ceremony-label.json')
      .writeAsString(jsonEncode({'pid': pid, 'label': visible}));
}

Future<void> _removeOwnedPasskeys(
  SecurityManagementController security,
  String password,
) async {
  // These accounts and IDs belong to the explicit synthetic fixture. Provider
  // credentials remain intact so later real assertions can test server denial.
  await security.load();
  final ids = security.credentials!.passkeys
      .map((p) => p.credentialId)
      .toList();
  for (final id in ids) {
    await security.beginPasskeyRemoval(id, password);
    await security.confirmPasskeyRemoval();
    expect(security.status == SecurityManagementStatus.committed, true);
    await security.acknowledgeResult();
  }
  await security.load();
}

Future<void> _ceremony(
  WidgetTester tester,
  Future<void> operation,
  String stage, {
  bool publish = true,
}) async {
  if (publish) await _stage(stage);
  try {
    await tester.runAsync(() async {
      // Watcher reports the actual provider, then human authorizes locally.
      await _ack(stage);
      await operation;
    });
  } finally {
    await _checkpoint(tester, 'ni-native-ended-return-$stage');
  }
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _checkpoint(WidgetTester tester, String stage) async {
  await _stage(stage);
  await tester.runAsync(() => _ack(stage));
}

Future<void> _accountRoute(WidgetTester tester) async {
  if (find.byType(AuthScreen).evaluate().isNotEmpty) return;
  final account = find.widgetWithText(ListTile, '账号与注销');
  if (account.evaluate().isEmpty) {
    await tapOwned(tester, find.byTooltip('My content'));
  }
  await tapOwned(tester, account);
  await waitOwned(
    tester,
    () => find.byType(AuthScreen).evaluate().isNotEmpty,
    'actual account and closure route',
  );
}

Future<void> _stage(String stage) => _driver.invokeMethod<void>('stage', stage);
Future<Map<String, dynamic>> _ack(String stage) async {
  final end = DateTime.now().add(const Duration(minutes: 4));
  final file = File('$_files${stage.replaceAll('-', '_')}.json');
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
  throw StateError('Owned independent acknowledgement absent: $stage');
}

Future<Map<String, dynamic>> _nativeState() async => Map<String, dynamic>.from(
  (await _native.invokeMapMethod<String, dynamic>('acceptanceState'))!,
);
int _count(Map<String, dynamic> v, String key) =>
    (v[key] as num?)?.toInt() ?? 0;
Map<String, int> _errorCounters(Map<String, dynamic> v) => {
  for (final key in [
    'nativeCreateCancelled',
    'nativeCreateDomSecurityError',
    'nativeCreateDomInvalidStateError',
    'nativeCreateDomNotAllowedError',
    'nativeCreateOtherDomError',
    'nativeCreateOtherFrameworkError',
    'nativeGetNoCredential',
    'nativeGetCancelled',
    'nativeGetDomSecurityError',
    'nativeGetDomNotAllowedError',
    'nativeGetOtherDomError',
    'nativeGetOtherFrameworkError',
    'actualAssociationRejected',
    'nativeTimeout',
    'nativeCreateSynchronousError',
    'nativeGetSynchronousError',
    'invalidAssertionUserHandle',
  ])
    key: _count(v, key),
};
Future<void> _unauthorized(Future<Object?> operation) => expectLater(
  operation,
  throwsA(
    isA<AuthFailure>().having(
      (e) => e.statusCode,
      'closed capability denied',
      401,
    ),
  ),
);
