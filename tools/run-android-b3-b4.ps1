param(
 [Parameter(Mandatory)][ValidateSet('ni-c01','ni-d01','ni-d02','ni-d03','ni-d04','ni-d05','ni-k01','ni-k02')][string]$Phase,
 [ValidateSet('main','control','bad-signature','missing-package','source','restart','fresh','no-key','write-failure','write-failure-read','write-unknown','write-unknown-read')][string]$Variant='main',
 [switch]$ResumeOriginalDraftClosure
)
$ErrorActionPreference='Stop'
if($ResumeOriginalDraftClosure -and ($Phase -ne 'ni-c01' -or $Variant -ne 'main')) {throw 'Only the original B3 draft closure may resume'}
$repo='C:/Users/Administrator/Documents/ChatGPT/HnuHole'
$root='D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix'
if((Get-Content -LiteralPath "$root/OWNER" -Raw).Trim() -ne 'HNUHOLE_ANDROID_MATRIX_V1'){throw 'Owned matrix required'}
$package='org.hnuhole.hnuhole_mobile';$apkName='phone-b3b4.apk';$config='b3b4-device-config.json'
if($Phase -in @('ni-k01','ni-k02') -or ($Phase -eq 'ni-c01' -and $Variant -eq 'control') -or ($Phase -eq 'ni-d02' -and $Variant -in @('control','bad-signature'))){
 $package+='.acceptance';$apkName=if($Variant -eq 'bad-signature'){'b3b4-bad-signature.apk'}else{'b3b4-acceptance.apk'};$config='b3b4-acceptance-config.json'
}elseif($Phase -eq 'ni-d03' -and $Variant -eq 'missing-package'){
 $package+='.unassociated';$apkName='b3b4-unassociated.apk';$config='b3b4-unassociated-config.json'
}elseif($Variant -ne 'main'){throw 'Variant does not belong to the fixed phase'}
$valid=@{
 'ni-c01'=@('main','control');'ni-d01'=@('main');'ni-d02'=@('control','bad-signature');
 'ni-d03'=@('missing-package');'ni-d04'=@('main');'ni-d05'=@('main');
 'ni-k01'=@('source','restart','fresh','no-key');'ni-k02'=@('write-failure','write-failure-read','write-unknown','write-unknown-read')
}
if($Variant -notin $valid[$Phase]){throw 'Fixed B3/B4 phase/variant mismatch'}
$manifest=Get-Content -LiteralPath "$root/b3b4-evidence/builds.json" -Raw|ConvertFrom-Json
$entry=@($manifest.apks|Where-Object {$_.fileName -eq $apkName -and $_.applicationId -eq $package})
if($entry.Count -ne 1){throw 'Exact reviewed APK variant missing'}
$apkHash=(Get-FileHash -LiteralPath "$root/$apkName" -Algorithm SHA256).Hash.ToLowerInvariant()
if($apkHash -ne $entry[0].apkSha256){throw 'Reviewed build variant changed'}
$sources=@('apps/mobile/integration_test/auth_android_b3_b4_device_test.dart','apps/mobile/integration_test/owned_auth_device_helpers.dart',
 'apps/mobile/android/app/src/main/kotlin/org/hnuhole/hnuhole_mobile/MainActivity.kt',
 'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/AuthPasskeyPlugin.kt',
 'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/PasskeyCodec.kt',
 'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/PendingOperation.kt',
 'packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/PasskeyAcceptanceErrors.kt',
 'packages/auth_vault/android/src/main/kotlin/org/hnuhole/authvault/AndroidAuthVault.kt',
 'packages/auth_vault/android/src/main/kotlin/org/hnuhole/authvault/AuthVaultPlugin.kt',
 'tools/run-android-live-device.ps1','tools/control-android-b3-b4-device.py','tools/control-android-b3-b4.py',
 'tools/android-auth-b3-b4-proxy.py','tools/control-android-closure.py','tools/start-android-b3-b4-service.py')
$hashes=@{}
foreach($path in $sources){
 $hashes[$path]=(Get-FileHash -LiteralPath "$repo/$path" -Algorithm SHA256).Hash.ToLowerInvariant()
 if($path.StartsWith('apps/') -or $path.StartsWith('packages/')){
  if($hashes[$path] -ne $manifest.sourceFilesSha256.$path){throw 'Compiled product/fixture source changed before actual launch'}
 }
}
$prefix="$root/b3b4-evidence/$Phase-$Variant"
if(Test-Path -LiteralPath "$prefix-version.json"){throw 'Retain previous actual attempt before resuming'}
@{phase=$Phase;variant=$Variant;applicationId=$package;apkSha256=$apkHash;sourceFilesSha256=$hashes;capturedAtLaunch=$true}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$prefix-version.json" -Encoding UTF8
try{
 & "$repo/tools/run-android-live-device.ps1" -DeviceId '10CEAG17RY003M7' -Apk "$root/$apkName" -ConfigFile "$root/$config" `
  -DriverWorkspace "$root/driver/apps/mobile" -PubCache 'D:/zewbbyTest/Hnuhole-android-live-faults-20261005/pub-windows' `
  -B3B4Phases $Phase -B3B4Variant $Variant -B3B4ApplicationId $package -B3B4ResumeOriginalDraftClosure:$ResumeOriginalDraftClosure *> "$prefix.private.log"
 if($LASTEXITCODE -ne 0){throw 'Fixed B3/B4 runner failed'}
 Copy-Item -LiteralPath "$root/driver/apps/mobile/live-$Phase-$Variant.json" -Destination "$prefix-report.json"
 Write-Output "PASS: fixed actual App phase $Phase / $Variant with independent device and SQL evidence"
}catch{
 Add-Content -LiteralPath "$prefix.private.log" -Value $_.Exception.ToString()
 # The parent can stop its witness before the witness catch runs. Preserve
 # actual facts, but never leave a failed/ended phase labelled RUNNING.
 $deviceRecord="$prefix-device.json"
 if(Test-Path -LiteralPath $deviceRecord){
  $device=Get-Content -LiteralPath $deviceRecord -Raw|ConvertFrom-Json
  if($device.phase -eq $Phase -and $device.variant -eq $Variant -and
     $device.apkSha256 -eq $apkHash -and $device.result -eq 'RUNNING'){
   $device.result='FAIL'
   $device|Add-Member -NotePropertyName runnerEndedBeforeAcceptance -NotePropertyValue $true -Force
   $device|Add-Member -NotePropertyName failureType -NotePropertyValue 'OwnedAppRunnerFailed' -Force
   $device|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $deviceRecord -Encoding UTF8
  }
 }
 Write-Output "FAIL: fixed phase $Phase / $Variant; original pending state and private evidence retained"
 exit 1
}
