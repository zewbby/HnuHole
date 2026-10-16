param(
    [Parameter(Mandatory)][ValidateSet('10CEAG17RY003M7')][string]$DeviceId,
    [Parameter(Mandatory)][string]$Work,
    [Parameter(Mandatory)][switch]$HumanReady
)
$ErrorActionPreference = 'Stop'
if (!$HumanReady) {throw 'User must be available to unlock the phone after the authorized reboot'}
$ownedRoot = (Resolve-Path -LiteralPath $Work).Path
if ($ownedRoot -ne 'D:\zewbbyTest\Hnuhole-android-live-faults-20261005\matrix' -or
    (Get-Content -LiteralPath "$ownedRoot\OWNER" -Raw).Trim() -ne 'HNUHOLE_ANDROID_MATRIX_V1') {
    throw 'Explicit development run owner required'
}
$driver = "$ownedRoot\driver\apps\mobile"
if ((Get-Content -LiteralPath "$driver\.device-app-owner" -Raw).Trim() -ne "$DeviceId|hnuhole-android-live-matrix-20261006") {
    throw 'Physical App owner mismatch'
}
$adb = 'D:\zewbbyTest\Hnuhole-env\android-sdk\platform-tools\adb.exe'
$package = 'org.hnuhole.hnuhole_mobile'
$apkSha = (Get-FileHash -LiteralPath "$ownedRoot\phone-lifecycle.apk" -Algorithm SHA256).Hash.ToLowerInvariant()
$installed = (& $adb -s $DeviceId shell pm path $package) -join ''
$path = [regex]::Match($installed, '^package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)$')
if (!$path.Success) {throw 'Owned monolithic physical test App required'}
$actualSha = ((& $adb -s $DeviceId shell sha256sum $path.Groups[1].Value) -join '').Split(' ')[0]
if ($actualSha -ne $apkSha) {throw 'Installed physical App differs from reviewed lifecycle APK'}
$acceptedLock = Get-Content -LiteralPath "$driver\live-phone-lock-cycle.json" -Raw | ConvertFrom-Json
if (!$acceptedLock.actualSecureKeyguardLockUnlockObserved -or !$acceptedLock.sameSessionAndDraftPreserved) {
    throw 'Accept the actual lock/unlock cycle before reboot'
}
$before = (& $adb -s $DeviceId shell settings get global boot_count) -join ''
if ($LASTEXITCODE -ne 0 -or $before -notmatch '^\d+$') {throw 'Cannot read boot-count prerequisite'}
& $adb -s $DeviceId reboot
if ($LASTEXITCODE -ne 0) {throw 'Authorized physical reboot request failed'}
Write-Output 'Phone reboot requested; unlock on the phone after startup'
$deadline = (Get-Date).AddMinutes(4)
$after = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $ErrorActionPreference = 'Continue'
    $state = (& $adb -s $DeviceId get-state 2>$null) -join ''
    $stateExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($stateExit -ne 0 -or $state -ne 'device') {continue}
    $completed = (& $adb -s $DeviceId shell getprop sys.boot_completed) -join ''
    if ($LASTEXITCODE -ne 0 -or $completed -ne '1') {continue}
    $after = (& $adb -s $DeviceId shell settings get global boot_count) -join ''
    if ($LASTEXITCODE -ne 0 -or $after -notmatch '^\d+$' -or [int]$after -le [int]$before) {throw 'Physical boot-count did not advance'}
    break
}
if (!$after) {throw 'Owned phone did not finish reboot; private test state retained'}
@{result='PASS';scope='HOST_REBOOT_ONLY_APP_READBACK_PENDING';device=$DeviceId;apkSha256=$apkSha;
  bootCountBefore=[int]$before;bootCountAfter=[int]$after;androidBootCompleted=$true;userUnlockRequired=$true} |
  ConvertTo-Json | Set-Content -LiteralPath "$ownedRoot\phone-reboot-host.json" -Encoding utf8
Write-Output 'PASS: actual physical reboot confirmed by boot-count; App readback still required'
