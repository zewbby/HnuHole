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

/// Human types with the real phone IME. No tester.enterText, injected editing
/// values or fabricated composing range is used in this acceptance entrypoint.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRunId = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'real phone IME composition and native committed draft restart',
    (tester) async {
      expect(
        Platform.isAndroid &&
            runId == 'hnuhole-android-live-matrix-20261006' &&
            accountRunId == 'hnuhole-android-live-boundary-20261006',
        isTrue,
      );
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        const {
          'phone-ime-write',
          'phone-ime-read',
          'phone-ime-inspect',
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
      final digest = AuthCrypto.domainDigest(
        'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1',
        utf8.encode(scope),
      );
      final store = AuthStore(
        FlutterAuthVault(namespace: 'hnuhole.auth.v1.$digest'),
        scope: scope,
      );
      final marker = FlutterAuthVault(
        namespace: 'native.security.test.$runId.real-ime',
      );
      final fixture =
          jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        client: createAppHttpClient(community: c, verifier: v),
      );
      const draft = '输入法测试草稿';
      final flags = <String, Object>{};
      var accepted = false;
      final priorDevicePointers = binding.shouldPropagateDevicePointerEvents;
      var devicePointerDowns = 0;
      void observePointer(PointerEvent event) {
        if (event is PointerDownEvent &&
            binding.pointerEventSource == TestBindingEventSource.device) {
          devicePointerDowns++;
        }
      }

      TextEditingController? observedController;
      VoidCallback? editingListener;
      try {
        // flutter_test drops physical pointer events by default. A manual IME
        // test must explicitly allow them and restore the test invariant.
        binding.shouldPropagateDevicePointerEvents = true;
        binding.pointerRouter.addGlobalRoute(observePointer);
        final state = await store.read();
        expect(
          state.session != null &&
              state.registration == null &&
              state.pendingReset == null &&
              state.pendingClosure == null,
          isTrue,
        );
        final account = state.session!.accountId;
        final current = await api.currentSession(state.session!.token);
        expect(current.accountId == account, isTrue);
        final directory = await api.identities(state.session!.token);
        expect(
          directory.identities.isEmpty && directory.createdCount == 0,
          isTrue,
        );
        final sessionDigest = AuthCrypto.domainDigest(
          'REAL-IME-SESSION',
          utf8.encode(state.session!.token),
        );
        if (phase == 'phone-ime-read') {
          expect(
            fixture['pid'] != pid &&
                fixture['accountId'] == account &&
                fixture['sessionDigest'] == sessionDigest &&
                fixture['compositionObserved'] == true,
            isTrue,
          );
        }
        app.main();
        await tester.pump();
        await _wait(
          tester,
          () => find.byType(ChannelTree).evaluate().isNotEmpty,
          'authoritative App',
        );
        await _tap(tester, find.byTooltip('My content'));
        await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
        await _tap(tester, find.byKey(const ValueKey('identity-add')));
        final finder = find.byKey(const ValueKey('identity-nickname'));
        await _wait(
          tester,
          () => finder.evaluate().isNotEmpty,
          'nickname editor',
        );
        final controller = tester.widget<TextFormField>(finder).controller!;
        if (phase == 'phone-ime-write') {
          var composingObserved = false, uncommittedDraftExcluded = false;
          var editingEvents = 0, composingEvents = 0;
          var committedTextMatches = false, durableDraftMatches = false;
          var compositionStageSent = false, exclusionStageSent = false;
          observedController = controller;
          editingListener = () {
            editingEvents++;
            final value = controller.value;
            if (value.composing.isValid && !value.composing.isCollapsed) {
              composingEvents++;
              composingObserved = true;
            }
          };
          controller.addListener(editingListener);
          await tester.ensureVisible(finder);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          final editable = tester.widget<EditableText>(
            find.descendant(of: finder, matching: find.byType(EditableText)),
          );
          final pointersBefore = devicePointerDowns;
          await driver.invokeMethod<void>('stage', 'await-real-ime-touch');
          await _wait(
            tester,
            () =>
                devicePointerDowns > pointersBefore &&
                editable.focusNode.hasFocus,
            'real device pointer focuses the editor',
          );
          flags['realDevicePointerFocusedEditor'] = true;
          flags['physicalPointerEventsEnabled'] = true;
          await driver.invokeMethod<void>('stage', 'await-human-real-ime');
          try {
            await _wait(
              tester,
              () async {
                final value = controller.value;
                final durable =
                    ((await store.read()).identityDrafts[account]
                        as Map?)?['nickname'];
                if (value.composing.isValid && !value.composing.isCollapsed) {
                  composingObserved = true;
                  if (controller.value == value && durable != value.text) {
                    uncommittedDraftExcluded = true;
                  }
                }
                if (composingObserved && !compositionStageSent) {
                  compositionStageSent = true;
                  await driver.invokeMethod<void>(
                    'stage',
                    'real-ime-composition-observed',
                  );
                }
                if (uncommittedDraftExcluded && !exclusionStageSent) {
                  exclusionStageSent = true;
                  await driver.invokeMethod<void>(
                    'stage',
                    'real-ime-uncommitted-draft-excluded',
                  );
                }
                committedTextMatches =
                    controller.text == draft &&
                    controller.value.composing.isCollapsed;
                durableDraftMatches = durable == draft;
                return composingObserved &&
                    uncommittedDraftExcluded &&
                    committedTextMatches &&
                    durableDraftMatches;
              },
              'actual human IME composition and committed draft',
              timeout: const Duration(minutes: 6),
            );
          } finally {
            fixture['lastWriteDiagnostic'] = {
              'editingEventCount': editingEvents,
              'composingEventCount': composingEvents,
              'composingObserved': composingObserved,
              'uncommittedDraftExcluded': uncommittedDraftExcluded,
              'committedTextMatches': committedTextMatches,
              'durableDraftMatches': durableDraftMatches,
            };
            await marker.write(jsonEncode(fixture));
          }
          fixture['accountId'] = account;
          fixture['sessionDigest'] = sessionDigest;
          fixture['compositionObserved'] = composingObserved;
          flags['actualPhoneImeCompositionObserved'] = true;
          flags['uncommittedComposingTextExcludedFromNativeDraft'] = true;
          flags['committedSyntheticDraftDurablySaved'] = true;
          flags['actualEditingEventCount'] = editingEvents;
          flags['actualComposingEventCount'] = composingEvents;
          FocusManager.instance.primaryFocus?.unfocus();
        } else if (phase == 'phone-ime-inspect') {
          // Read the actual earlier input before requesting another trace. No
          // product state, text/controller value or session is manufactured.
          flags['actualEditorMatchesPriorHumanInput'] =
              controller.text == draft;
          flags['nativeDraftMatchesPriorHumanInput'] =
              ((await store.read()).identityDrafts[account]
                  as Map?)?['nickname'] ==
              draft;
          flags['productStateReadOnly'] = true;
          expect(flags['actualEditorMatchesPriorHumanInput'], isTrue);
          expect(flags['nativeDraftMatchesPriorHumanInput'], isTrue);
          fixture['accountId'] = account;
          fixture['sessionDigest'] = sessionDigest;
          final diagnostic = fixture['lastWriteDiagnostic'];
          if (diagnostic is Map) {
            for (final key in [
              'editingEventCount',
              'composingEventCount',
              'composingObserved',
              'uncommittedDraftExcluded',
              'committedTextMatches',
              'durableDraftMatches',
            ]) {
              flags['previousWrite_$key'] = diagnostic[key] as Object;
            }
          }
        } else {
          expect(
            controller.text == draft && controller.value.composing.isCollapsed,
            isTrue,
          );
          expect(
            ((await store.read()).identityDrafts[account]
                    as Map?)?['nickname'] ==
                draft,
            isTrue,
          );
          flags['sameSessionAndCommittedImeDraftRestoredInNewProcess'] = true;
        }
        final after = await api.identities(state.session!.token);
        expect(after.identities.isEmpty && after.createdCount == 0, isTrue);
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
          'syntheticEditingValuesInjected': false,
          ...flags,
        };
        accepted = true;
      } finally {
        binding.pointerRouter.removeGlobalRoute(observePointer);
        binding.shouldPropagateDevicePointerEvents = priorDevicePointers;
        if (observedController != null && editingListener != null) {
          observedController.removeListener(editingListener);
        }
        if (accepted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        api.close();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: runId.isEmpty,
  );
}

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String stage, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await ready()) return;
  }
  throw StateError('Real IME phase timed out: $stage');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () => finder.evaluate().length == 1, 'single action');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}
