# Owned Passkey callback diagnosis

This observer attaches to the exact reviewed, already installed debuggable
`org.hnuhole.hnuhole_mobile.acceptance` APK and its current PID. It does not
start a ceremony, install an APK, change providers, select credentials, or
perform authentication.

From the repository root, with the existing Java JDK on PATH:

```powershell
python tools/android-passkey-diagnostic/run.py --compile-only
python tools/android-passkey-diagnostic/run.py --pid <current-owned-app-pid>
```

Only use the second command during an explicitly requested diagnostic window.
The listener observes `onError` in this app's Passkey plugin, verifies the
exception's Credential Manager superclass, and reports whether it came from a
callback argument or a named callback local variable. If neither is available,
it waits for another matching callback and does not enumerate the heap.

Output contains exception class names, message lengths/hashes and fixed keyword
categories. Raw messages, proof bytes and account names are not recorded. No
target VM method is invoked; the event thread is resumed in `finally`, and the
exact ADB forwarding entry is removed after the observer exits. Class artifacts
and the bounded diagnostic JSON stay in the owned local matrix environment.

Attaching a debugger can affect timing. An observed error is diagnostic evidence
under that condition, not functional acceptance or proof of the provider's root
cause. A generic cancellation does not establish that the human canceled, or
that an app/domain association was rejected. Existing prototype records that
did not distinguish callback values from heap objects retain that limitation;
this observer does not retroactively validate them.

## Public Google FIDO contrast probe

`GoogleFidoDiagnosticActivity` and `GoogleFidoDiagnosticPolicy` live only in
`apps/mobile/android/app/src/debug/java/org/hnuhole/hnuhole_mobile`. The product
Passkey plugin and C API are unchanged. Cached Google FIDO 21.0.0 public APIs
provide `isUserVerifyingPlatformAuthenticatorAvailable()` and
`getRegisterPendingIntent(PublicKeyCredentialCreationOptions)`; the probe does
not use reflection or privileged APIs. A fresh challenge and synthetic user ID
are generated inside the probe. RP is fixed to `zewbby.github.io`, ES256,
resident key required, UV required and attestation none.

The default run prepares the PendingIntent without launching it. An optional
native window requires both a fresh private admission and an explicit Intent
boolean `launchPendingIntent=true`; it belongs to a separately authorized
human diagnostic window. Any generated credential is a diagnostic credential,
with no C submission, and cannot establish NI-D01/02/03 acceptance.

An admitted run requires a debuggable
`org.hnuhole.hnuhole_mobile.acceptance`, the approved certificate, the exact
installed APK hash, and the fixed `ni-d02/control` phase. The host places
`no_backup/google-fido-diagnostic-admission.json`, with exactly these keys:

```json
{
  "schemaVersion": 1,
  "owner": "HNUHOLE_GOOGLE_FIDO_DIAGNOSTIC_V1",
  "phase": "ni-d02",
  "variant": "control",
  "runId": "gfd-<32 lowercase hexadecimal characters>",
  "nonce": "<64 lowercase hexadecimal characters>",
  "apkSha256": "<exact diagnostic APK SHA-256>",
  "launchPendingIntent": false
}
```

The one-use admission has a maximum age of 120 seconds. Intent extras `runId`
and `nonce` must match; omitted `launchPendingIntent` means false. No caller can
provide options, RP, account details or credential IDs. Results are stored in
`no_backup/google-fido-diagnostic-<runId>.json` and contain only bounded stage,
PID, numeric status/error code, error enum, exception class, message length and
SHA-256, secure-keyguard state and booleans. Raw messages, Intents, challenge,
user fields, credential IDs and proof bytes are never stored or logged.

`finished` means this Activity completed its local diagnostic work.
`nativeOutcomeUnknown` stays true after a native launch until a typed
AuthenticatorErrorResponse or actual attestation result is decoded. A timeout,
decode failure or untyped cancellation cannot prove that Google's window has
terminated or that no credential was created. The host must retain and
reconcile that same run before starting another one.

The build-only entry, after sourcing the existing WSL environment and selecting
the existing owned `PUB_CACHE`/`GRADLE_USER_HOME`, is
`python3 tools/android-passkey-diagnostic/build-google-fido-diagnostic.py`.
It builds one debug isolation APK entirely offline into
`D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix/google-direct-diagnostic/`,
checks its approved certificate and merged manifest, executes the host JVM
policy test, and runs real Gradle release source-set and merged-manifest checks.
It restores temporary build mirror overlays and preserves all canonical APKs
and `builds.json`. It never installs an APK or accesses a phone.

The release check covers the new Activity, Policy and direct debug compilation
dependency declarations. FIDO libraries already used by the product's
Credential Manager runtime may remain in release. It does not claim a new
release APK build or device/API verification.

Official API references:
[Fido2ApiClient](https://developers.google.com/android/reference/com/google/android/gms/fido/fido2/Fido2ApiClient),
[creation options](https://developers.google.com/android/reference/com/google/android/gms/fido/fido2/api/common/PublicKeyCredentialCreationOptions),
[Fido result constants](https://developers.google.com/android/reference/com/google/android/gms/fido/Fido),
[AuthenticatorErrorResponse](https://developers.google.com/android/reference/com/google/android/gms/fido/fido2/api/common/AuthenticatorErrorResponse).
