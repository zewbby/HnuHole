# Authentication vault

Single bounded state record, separate namespace per configured C/V deployment.
Android uses an unexported AES-GCM Android Keystore key, namespace AAD and
ciphertext under `noBackupFilesDir`. Writes synchronize the file, atomically
replace it, verify ciphertext and synchronize the containing directory before
acknowledgment. A missing key with an existing record is an error. iOS uses a
non-synchronizing `AfterFirstUnlockThisDeviceOnly` Keychain item; successful
`SecItemAdd`/`SecItemUpdate` is the platform acknowledgment. A non-secret, backup-excluded, synchronized installation marker removes stale Keychain state after reinstall before any authentication state is read. Both adapters run
serially, return fixed errors and provide no plaintext fallback.

The Dart owner serializes every read/update, validates version/scope/workflow
shape, awaits acknowledgment and verifies readback. Unknown writes invalidate
its cache; startup must read again before any community operation.

Flutter/Dart and MethodChannel tests do not prove native durability. Before
release, build on Android/iOS and test process kills at each write boundary,
Keystore/Keychain errors, locked device, disk exhaustion, backup/restore and
reinstall. Android SDK and Java are available, but a full Xcode/device environment is absent;
these checks remain pending. Dependency versions follow the generated Flutter
3.47.5 platform templates. Release signing and operational endpoints are not
configured.
