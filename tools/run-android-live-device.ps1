param(
    [Parameter(Mandatory)][string]$DeviceId,
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][string]$ConfigFile,
    [Parameter(Mandatory)][string]$DriverWorkspace,
    [Parameter(Mandatory)][string]$PubCache,
    [string]$EnvironmentRoot = 'D:\zewbbyTest\Hnuhole-env',
    [string]$FaultWork,
    [ValidateSet('account-closure-cancel','rotation','code-reset','lifecycle','passkey-bind','passkey-reconcile',
        'passkey-cancel','passkey-remove','passkey-recover','lock-state')]
    [string[]]$MatrixPhases,
    [ValidateSet('takeover-register','takeover-source','takeover-other','takeover-observe','v-gate-request',
        'v-gate-frozen-confirm','v-gate-old-confirm')]
    [string[]]$BoundaryPhases,
    [ValidateSet('storage-source','storage-restart','storage-fresh','storage-restored-no-key')]
    [string[]]$StoragePhases,
    [ValidateSet('phone-prime','phone-lock-cycle','phone-reboot-read')]
    [string[]]$LifecyclePhases,
    [ValidateSet('otp-continuation-request','otp-continuation-frozen','otp-continuation-cleaned','otp-continuation-resume')]
    [string[]]$OtpContinuationPhases,
    [ValidateSet('phone-ime-write','phone-ime-read','phone-ime-inspect')]
    [string[]]$ImePhases,
    [ValidateSet('phone-talkback-prepare','phone-talkback-navigate','phone-talkback-read')]
    [string[]]$TalkBackPhases,
    [ValidateSet('closure-draft-request','closure-draft-released','closure-draft-register',
        'closure-profile-request','closure-profile-released','closure-profile-register','closure-new-read')]
    [string[]]$ClosurePhases,
    [ValidateSet('batch-register','batch-phone-draft','batch-companion-draft','batch-phone-retake',
        'batch-account-isolation','batch-passkey-drop','batch-passkey-reconcile',
        'batch-passkey-origin-reject','batch-passkey-rejected-reconcile','batch-passkey-route-cancel',
        'batch-passkey-remove-existing','batch-passkey-timeout','batch-gate-session-recover',
        'batch-passkey-ack-interrupted-success')]
    [string[]]$BatchPhases,
    [switch]$BatchProxyControl,
    [ValidateSet('ni-l01','ni-l02','ni-l03','ni-l04','ni-u01','ni-u02','ni-u03',
        'ni-a01','ni-a02','ni-a03','ni-a04','ni-takeover')]
    [string[]]$NonIOSPhases,
    [ValidateSet('ni-c01','ni-d01','ni-d02','ni-d03','ni-d04','ni-d05','ni-k01','ni-k02')]
    [string[]]$B3B4Phases,
    [ValidateSet('main','control','bad-signature','missing-package','source','restart','fresh','no-key',
        'write-failure','write-failure-read','write-unknown','write-unknown-read')]
    [string]$B3B4Variant = 'main',
    [ValidateSet('org.hnuhole.hnuhole_mobile','org.hnuhole.hnuhole_mobile.acceptance','org.hnuhole.hnuhole_mobile.unassociated')]
    [string]$B3B4ApplicationId = 'org.hnuhole.hnuhole_mobile',
    [switch]$B3B4ResumeOriginalDraftClosure,
    [ValidateSet('write','unknown','reconcile','frozen','recovered','offline-logout','drain')]
    [string]$ResumeFrom
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env-hnuhole-windows.ps1') -EnvironmentRoot $EnvironmentRoot
$env:PUB_CACHE = $PubCache
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
$applicationId = 'org.hnuhole.hnuhole_mobile'
if ($B3B4ResumeOriginalDraftClosure -and
    ($DeviceId -ne '10CEAG17RY003M7' -or @($B3B4Phases).Count -ne 1 -or
     $B3B4Phases[0] -ne 'ni-c01' -or $B3B4Variant -ne 'main')) {
    throw 'Only the confirmed original B3 draft closure may resume'
}
if ($B3B4Phases) {
    foreach ($selector in @('FaultWork','ResumeFrom','MatrixPhases','BoundaryPhases','StoragePhases','LifecyclePhases',
        'OtpContinuationPhases','ImePhases','TalkBackPhases','ClosurePhases','BatchPhases','BatchProxyControl','NonIOSPhases')) {
        if ($PSBoundParameters.ContainsKey($selector)) { throw 'B3/B4 requires an independent fixed selector' }
    }
    if ($DeviceId -ne '10CEAG17RY003M7') { throw 'B3/B4 requires the owned physical vivo' }
    $applicationId = $B3B4ApplicationId
} elseif ($PSBoundParameters.ContainsKey('B3B4Variant') -or $PSBoundParameters.ContainsKey('B3B4ApplicationId')) {
    throw 'Isolated package/variant parameters require the fixed B3/B4 selector'
}
if ($NonIOSPhases -and ($BatchPhases -or $BatchProxyControl -or $FaultWork -or $ResumeFrom -or
    $MatrixPhases -or $BoundaryPhases -or $StoragePhases -or $LifecyclePhases -or
    $OtpContinuationPhases -or $ImePhases -or $TalkBackPhases -or $ClosurePhases)) {
    throw 'Fixed B1/B2 phases cannot combine with other device phase selectors'
}
$nonIOSController = Join-Path $PSScriptRoot 'control-android-b1-b2-device.py'
if ($BatchProxyControl -and !$BatchPhases) { throw 'Batch proxy control requires explicit batch phases' }
if ($BatchPhases -and ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $BoundaryPhases -or
    $StoragePhases -or $LifecyclePhases -or $OtpContinuationPhases -or $ImePhases -or
    $TalkBackPhases -or $ClosurePhases)) {
    throw 'Batch phases are independent from all other device phase selectors'
}
if ($ClosurePhases -and ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $BoundaryPhases -or
    $StoragePhases -or $LifecyclePhases -or $OtpContinuationPhases -or $ImePhases -or $TalkBackPhases)) {
    throw 'Formal closure phases are independent from all other device phases'
}
if ($TalkBackPhases -and ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $BoundaryPhases -or
    $StoragePhases -or $LifecyclePhases -or $OtpContinuationPhases -or $ImePhases)) {
    throw 'TalkBack phases are independent from all other device phases'
}
$config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
$phases = @('write','read')
$target = 'integration_test/auth_live_device_test.dart'
if ($B3B4Phases) {
    if ($config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-b3-b4-20261009' -or
        $config.AUTH_DEVICE_RUN_ID -ne 'hnuhole-android-live-matrix-20261006') { throw 'B3/B4 owned configuration required' }
    if ($B3B4ApplicationId -ne 'org.hnuhole.hnuhole_mobile' -and
        @($B3B4Phases | Where-Object {$_ -notin @('ni-c01','ni-d02','ni-d03','ni-k01','ni-k02')}).Count) {
        throw 'Only fixed association/storage phases may use an isolated package'
    }
    if ($B3B4ApplicationId -ne 'org.hnuhole.hnuhole_mobile' -and $B3B4Phases -contains 'ni-c01' -and
        ($B3B4ApplicationId -ne 'org.hnuhole.hnuhole_mobile.acceptance' -or $B3B4Variant -ne 'control')) {
        throw 'Only the approved isolated first-binding closure may use this selector'
    }
    if ($B3B4Phases -contains 'ni-k01' -or $B3B4Phases -contains 'ni-k02') {
        if ($applicationId -ne 'org.hnuhole.hnuhole_mobile.acceptance') { throw 'Storage tests must preserve the main package' }
    }
    $phases = $B3B4Phases
    $target = 'integration_test/auth_android_b3_b4_device_test.dart'
}
if ($NonIOSPhases) {
    if ($config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-batch-20261007' -or
        $config.AUTH_DEVICE_RUN_ID -ne 'hnuhole-android-live-matrix-20261006' -or
        $DeviceId -notin @('10CEAG17RY003M7','emulator-5554')) {
        throw 'Fixed B1/B2 requires the owned account and physical vivo/test emulator'
    }
    foreach ($fixedPhase in $NonIOSPhases) {
        if (($fixedPhase -in @('ni-u01','ni-takeover')) -ne ($DeviceId -eq 'emulator-5554')) {
            throw 'Unavailable/companion cases require emulator; other fixed cases require vivo'
        }
    }
    $phases = $NonIOSPhases
    $target = 'integration_test/auth_android_b1_b2_device_test.dart'
}
if ($BatchPhases) {
    if ($config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-batch-20261007' -or
        $config.AUTH_DEVICE_RUN_ID -ne 'hnuhole-android-live-matrix-20261006' -or
        $DeviceId -notin @('10CEAG17RY003M7','emulator-5554')) {
        throw 'Batch phases require the separate owned batch account and vivo/emulator configuration'
    }
    if (($DeviceId -eq 'emulator-5554' -and @($BatchPhases | Where-Object { $_ -ne 'batch-companion-draft' }).Count) -or
        ($DeviceId -eq '10CEAG17RY003M7' -and 'batch-companion-draft' -in $BatchPhases)) {
        throw 'Companion draft belongs only to the owned emulator; other batch phases require vivo'
    }
    $phases = $BatchPhases
    $target = 'integration_test/auth_android_batch_device_test.dart'
    if (@($BatchPhases | Where-Object { $_ -like 'batch-passkey-*' -or $_ -eq 'batch-gate-session-recover' }).Count -and !$BatchProxyControl) {
        throw 'Batch Passkey phases require count-verified owned proxy control'
    }
}
if ($FaultWork) {
    if ($OtpContinuationPhases -or $ImePhases) { throw 'Independent device phases cannot combine with fault phases' }
    if ($FaultWork -notmatch '^/var/tmp/hnuhole-android-live-faults-[a-z0-9-]+$') {
        throw 'Fault control requires an explicitly owned WSL development root'
    }
    $phases = @('write','unknown','reconcile','frozen','recovered','offline-logout','drain')
    $target = 'integration_test/auth_fault_device_test.dart'
}
if ($MatrixPhases) {
    if ($FaultWork -or $ResumeFrom -or $StoragePhases -or $LifecyclePhases -or $OtpContinuationPhases -or $ImePhases -or
        $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-faults-20261005-r2') {
        throw 'Matrix phases require the explicit accepted synthetic account configuration'
    }
    $phases = $MatrixPhases
    $target = 'integration_test/auth_android_matrix_device_test.dart'
}
if ($BoundaryPhases) {
    if ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $StoragePhases -or $LifecyclePhases -or $OtpContinuationPhases -or $ImePhases -or
        $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-boundary-20261006') {
        throw 'Boundary phases require the explicit accepted synthetic account configuration'
    }
    $phases = $BoundaryPhases
    $target = 'integration_test/auth_android_boundary_device_test.dart'
}
if ($StoragePhases) {
    if ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $BoundaryPhases -or $LifecyclePhases -or $OtpContinuationPhases -or $ImePhases -or
        $DeviceId -ne 'emulator-5554' -or $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-boundary-20261006') {
        throw 'Storage phases require the owned synthetic-account emulator configuration'
    }
    $phases = $StoragePhases
    $target = 'integration_test/auth_android_storage_device_test.dart'
}
if ($LifecyclePhases) {
    if ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $BoundaryPhases -or $StoragePhases -or $OtpContinuationPhases -or $ImePhases -or
        $DeviceId -ne '10CEAG17RY003M7' -or $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-boundary-20261006') {
        throw 'Physical lifecycle phases require the explicitly owned vivo test configuration'
    }
    $phases = $LifecyclePhases
    $target = 'integration_test/auth_android_lifecycle_device_test.dart'
}
if ($OtpContinuationPhases) {
    if ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $BoundaryPhases -or $StoragePhases -or $LifecyclePhases -or $ImePhases -or
        $DeviceId -ne 'emulator-5554' -or $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-boundary-20261006') {
        throw 'OTP continuation requires the owned synthetic-account emulator configuration'
    }
    $phases = $OtpContinuationPhases
    $target = 'integration_test/auth_android_otp_continuation_device_test.dart'
}
if ($ImePhases) {
    if ($FaultWork -or $ResumeFrom -or $MatrixPhases -or $BoundaryPhases -or $StoragePhases -or $LifecyclePhases -or $OtpContinuationPhases -or
        $DeviceId -ne '10CEAG17RY003M7' -or $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-boundary-20261006') {
        throw 'Real IME phases require the explicitly owned vivo test configuration'
    }
    $phases = $ImePhases
    $target = 'integration_test/auth_android_ime_device_test.dart'
}
if ($TalkBackPhases) {
    if ($DeviceId -ne '10CEAG17RY003M7' -or
        $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-boundary-20261006') {
        throw 'TalkBack requires the explicitly owned physical vivo test configuration'
    }
    $phases = $TalkBackPhases
    $target = 'integration_test/auth_android_talkback_device_test.dart'
}
if ($ClosurePhases) {
    if ($DeviceId -ne '10CEAG17RY003M7' -or
        $config.AUTH_MATRIX_ACCOUNT_RUN_ID -ne 'hnuhole-android-live-closure-20261007') {
        throw 'Formal closure requires the separate owned vivo closure test configuration'
    }
    $phases = $ClosurePhases
    $target = 'integration_test/auth_android_closure_device_test.dart'
}
if ($config.AUTH_DEVICE_RUN_ID -notmatch '^hnuhole-android-live-[A-Za-z0-9_-]+$') {
    throw 'An owned live-device configuration is required'
}
$driverRoot = (Resolve-Path -LiteralPath $DriverWorkspace).Path
$ownerPath = Join-Path $driverRoot '.device-app-owner'
$ownedMarker = "$DeviceId|$($config.AUTH_DEVICE_RUN_ID)"
$existing = & $adb -s $DeviceId shell pm path $applicationId
if (!$existing) { throw 'Install the reviewed test APK once before running this attach-only runner' }
if (!(Test-Path -LiteralPath $ownerPath) -or
    (Get-Content -LiteralPath $ownerPath -Raw) -ne $ownedMarker) {
    throw 'Refusing to launch an existing application without this run ownership marker'
}
$installedPath = [regex]::Match(($existing -join "`n"), '(?m)^package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)$')
if (!$installedPath.Success) { throw 'Expected one owned, monolithic test APK' }
$installedDigest = (& $adb -s $DeviceId shell sha256sum $installedPath.Groups[1].Value) -join ''
$digestMatch = [regex]::Match($installedDigest, '^([a-f0-9]{64})\s')
$reviewedDigest = (Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLowerInvariant()
if (!$digestMatch.Success -or $digestMatch.Groups[1].Value -ne $reviewedDigest) {
    throw 'Installed App differs from the reviewed test APK; update once before this attach-only runner'
}
if ($ResumeFrom) {
    if (!$FaultWork) { throw 'Resume is supported only for the owned fault runner' }
    $resumeIndex = [Array]::IndexOf($phases, $ResumeFrom)
    if ($resumeIndex -gt 0) {
        $acceptedDigestPath = Join-Path $driverRoot 'live-installed-apk-sha256.txt'
        if (!(Test-Path -LiteralPath $acceptedDigestPath) -or
            (Get-Content -LiteralPath $acceptedDigestPath -Raw).Trim() -ne $reviewedDigest) {
            throw 'Resume requires prior evidence from the same reviewed installed APK'
        }
        $previousPid = $null
        $acceptedPids = @()
        foreach ($acceptedPhase in $phases[0..($resumeIndex - 1)]) {
            $accepted = Get-Content -LiteralPath (Join-Path $driverRoot "live-$acceptedPhase.json") -Raw | ConvertFrom-Json
            if ($accepted.phase -ne $acceptedPhase -or !$accepted.actualApp -or
                !$accepted.actualCV -or !$accepted.nativeVault -or
                $accepted.pid -in $acceptedPids -or
                ($previousPid -and $accepted.priorPid -ne $previousPid)) {
                throw 'Prior accepted device phase chain is incomplete'
            }
            & wsl -d Ubuntu-24.04 -- test -f "$FaultWork/phase-evidence/$acceptedPhase.json"
            if ($LASTEXITCODE -ne 0) { throw 'Prior owned SQL/proxy evidence is missing' }
            $acceptedPids += $accepted.pid
            $previousPid = $accepted.pid
        }
    }
    $phases = $phases[$resumeIndex..($phases.Length - 1)]
}
# Marker is private host bookkeeping; it is not copied into an evidence report.
[IO.File]::WriteAllText($ownerPath, $ownedMarker)
$portsCreated = @()
$existingForwards = (& $adb -s $DeviceId reverse --list) -join "`n"
try {
    foreach ($name in @('AUTH_COMMUNITY_BASE_URL','AUTH_VERIFIER_BASE_URL','AUTH_DEVICE_MAILPIT_URL')) {
        $origin = [Uri]$config.$name
        if ($origin.Host -ne '127.0.0.1' -or $origin.Port -lt 1024 -or
            $origin.UserInfo -or $origin.Query -or $origin.Fragment -or $origin.AbsolutePath -ne '/' -or
            $origin.Scheme -ne $(if ($name -eq 'AUTH_DEVICE_MAILPIT_URL') { 'http' } else { 'https' })) {
            throw 'Only owned loopback service endpoints may be forwarded'
        }
        $endpoint = "tcp:$($origin.Port)"
        if ($existingForwards -notmatch "(?m) $([regex]::Escape($endpoint)) $([regex]::Escape($endpoint))$") {
            if ($existingForwards -match "(?m) $([regex]::Escape($endpoint)) ") {
                throw 'An existing USB mapping uses the requested port'
            }
            & $adb -s $DeviceId reverse $endpoint $endpoint
            if ($LASTEXITCODE -ne 0) { throw 'USB service forwarding failed' }
            $portsCreated += $endpoint
        }
    }
    Push-Location $driverRoot
    try {
        foreach ($phase in $phases) {
            $nonIOSPrepared = $false
            try {
            if ($B3B4Phases) {
                $taskB3PrepareArgs = @('prepare','--phase',$phase,'--variant',$B3B4Variant)
                if ($B3B4ResumeOriginalDraftClosure) { $taskB3PrepareArgs += '--resume-existing' }
                & wsl -d Ubuntu-24.04 -- python3 /var/tmp/hnuhole-android-live-b3-b4-20261009/repo/tools/control-android-b3-b4.py @taskB3PrepareArgs
                if ($LASTEXITCODE -ne 0) { throw 'B3/B4 immutable SQL/proxy anchor failed' }
            }
            if ($NonIOSPhases) {
                & wsl -d Ubuntu-24.04 -- python3 /var/tmp/hnuhole-android-live-batch-20261007/repo/tools/control-android-b1-b2.py prepare --phase $phase
                if ($LASTEXITCODE -ne 0) { throw 'Fixed B1/B2 immutable SQL/proxy anchor failed' }
                $nonIOSPrepared = $true
                & python $nonIOSController prepare --phase $phase --device $DeviceId
                if ($LASTEXITCODE -ne 0) { throw 'Fixed B1/B2 device baseline preparation failed' }
            }
            if ($BatchProxyControl -and ($phase -like 'batch-passkey-*' -or $phase -eq 'batch-gate-session-recover')) {
                & wsl -d Ubuntu-24.04 -- python3 /var/tmp/hnuhole-android-live-batch-20261007/repo/tools/control-android-batch-proxy.py prepare --phase $phase
                if ($LASTEXITCODE -ne 0) { throw 'Owned batch proxy preparation failed before App launch' }
            }
            if ($FaultWork) {
                & wsl -d Ubuntu-24.04 -- python3 "$FaultWork/repo/tools/control-android-auth-fault.py" `
                    --work $FaultWork --phase $phase
                if ($LASTEXITCODE -ne 0) { throw 'Owned host fault phase preparation failed' }
            }
            & $adb -s $DeviceId shell am force-stop $applicationId
            if ($LASTEXITCODE -ne 0) { throw 'Could not stop the prior owned test process' }
            $stopped = $false
            for($stopAttempt=0;$stopAttempt -lt 40;$stopAttempt++) {
                $remainingPid = ((& $adb -s $DeviceId shell pidof $applicationId) -join '').Trim()
                if (!$remainingPid) {$stopped=$true;break}
                Start-Sleep -Milliseconds 100
            }
            if (!$stopped) {throw 'Previous owned test process did not stop before new phase'}
            & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-device-driver-vm.json
            if ($LASTEXITCODE -ne 0) { throw 'Expected the owned debuggable test App' }
            & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-device-driver-stage.json
            # A surface-mode Activity waits for Flutter's first frame before
            # drawing its Android window. TalkBack needs that window while the
            # existing-app driver attaches; only this human-assisted phase
            # starts immediately and waits at its explicit host acknowledgments.
            $startPaused = if ($B3B4Phases -or ($NonIOSPhases -and $phase -eq 'ni-u03')) {'false'} else {'true'}
            $ownedActivity = if ($B3B4Phases) { "$applicationId/org.hnuhole.hnuhole_mobile.MainActivity" } else { "$applicationId/.MainActivity" }
            $launchArgs = @('-s', $DeviceId, 'shell', 'am', 'start', '-S',
                '-f', '0x10008000', '-n', $ownedActivity,
                '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER',
                '--ez', 'enable-checked-mode', 'true', '--ez', 'verify-entry-points', 'true',
                '--ez', 'start-paused', $startPaused, '--ez', 'hnuhole-device-driver', 'true')
            if ($MatrixPhases -or $BoundaryPhases -or $StoragePhases -or $LifecyclePhases -or $OtpContinuationPhases -or $ImePhases -or $TalkBackPhases -or $ClosurePhases -or $BatchPhases -or $NonIOSPhases) { $launchArgs += @('--es', 'hnuhole-device-phase', $phase) }
            if ($B3B4Phases) { $launchArgs += @('--es','hnuhole-device-phase',$phase,'--es','hnuhole-device-variant',$B3B4Variant) }
            $ErrorActionPreference='Continue'
            & $adb @launchArgs 2>&1
            $launchExit=$LASTEXITCODE
            $ErrorActionPreference='Stop'
            if ($launchExit -ne 0) { throw 'Could not launch the already installed App' }
            $deviceVmUri = $null
            for ($attempt = 0; $attempt -lt 45; $attempt++) {
                $appPid = ((& $adb -s $DeviceId shell pidof $applicationId) -join '').Trim()
                if ($appPid -match '^\d+$') {
                    & $adb -s $DeviceId shell run-as $applicationId test -f files/owned-device-driver-vm.json
                    if ($LASTEXITCODE -eq 0) {
                        $privateInfo = ((& $adb -s $DeviceId shell run-as $applicationId cat files/owned-device-driver-vm.json) -join '') | ConvertFrom-Json
                        $candidate = [Uri]$privateInfo.uri
                        if ($privateInfo.pid -eq [int]$appPid -and $candidate.Scheme -eq 'http' -and
                            $candidate.Host -eq '127.0.0.1' -and $candidate.Port -ge 1024 -and
                            !$candidate.UserInfo -and !$candidate.Query -and !$candidate.Fragment) {
                            $deviceVmUri = $candidate
                            break
                        }
                    }
                    $appLog = (& $adb -s $DeviceId logcat -d --pid=$appPid -s flutter:I) -join "`n"
                    $match = [regex]::Match($appLog, 'The Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)')
                    if ($match.Success) { $deviceVmUri = [Uri]$match.Groups[1].Value; break }
                }
                Start-Sleep -Seconds 1
            }
            if (!$deviceVmUri) { throw 'Installed App did not expose its debug VM service' }
            $hostPort = (& $adb -s $DeviceId forward tcp:0 "tcp:$($deviceVmUri.Port)").Trim()
            if ($LASTEXITCODE -ne 0 -or $hostPort -notmatch '^\d+$') { throw 'VM service forwarding failed' }
            try {
                $vmUri = "http://127.0.0.1:$hostPort$($deviceVmUri.AbsolutePath)"
                $priorLogcat = @(Get-CimInstance Win32_Process -Filter "Name = 'adb.exe'" | Select-Object -ExpandProperty ProcessId)
                $driveStart = Get-Date
                $lifecycleJob = $null
                if ($B3B4Phases) {
                    $taskB3Controller = Join-Path $PSScriptRoot 'control-android-b3-b4-device.py'
                    $lifecycleJob = Start-Job -ArgumentList $taskB3Controller,$phase,$B3B4Variant,$applicationId,$appPid,$PID -ScriptBlock {
                        param($ownedController,$ownedPhase,$ownedVariant,$ownedPackage,$ownedPid,$ownedRunnerPid)
                        $taskObserverLog="D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix/b3b4-evidence/$ownedPhase-$ownedVariant-observer.private.log"
                        & python $ownedController watch --phase $ownedPhase --variant $ownedVariant --package $ownedPackage --pid $ownedPid --runner-pid $ownedRunnerPid *> $taskObserverLog
                        if ($LASTEXITCODE -ne 0) { throw 'Fixed B3/B4 actual device witness failed' }
                    }
                }
                if ($NonIOSPhases) {
                    $lifecycleJob = Start-Job -ArgumentList $nonIOSController,$phase,$DeviceId,$appPid,$PID -ScriptBlock {
                        param($ownedController,$ownedPhase,$ownedDevice,$ownedPid,$ownedRunnerPid)
                        & python $ownedController watch --phase $ownedPhase --device $ownedDevice --pid $ownedPid --runner-pid $ownedRunnerPid
                        if ($LASTEXITCODE -ne 0) { throw 'Fixed actual device witness failed' }
                    }
                }
                if ($BatchProxyControl -and $phase -in @('batch-passkey-route-cancel','batch-passkey-timeout')) {
                    & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-batch-provider-ack.json
                    & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-batch-timeout-dismissed.json
                    if ($LASTEXITCODE -ne 0) {throw 'Could not clear the owned prior provider acknowledgement'}
                    $lifecycleJob = Start-Job -ArgumentList $adb, $DeviceId, $applicationId, $appPid, $phase -ScriptBlock {
                        param($ownedAdb, $ownedDevice, $ownedApp, $ownedPid, $ownedPhase)
                        $ErrorActionPreference='Stop'
                        for ($attempt=0; $attempt -lt 170; $attempt++) {
                            & $ownedAdb -s $ownedDevice shell run-as $ownedApp test -f files/owned-device-driver-stage.json | Out-Null
                            if ($LASTEXITCODE -eq 0) {
                                $stage=((& $ownedAdb -s $ownedDevice shell run-as $ownedApp cat files/owned-device-driver-stage.json) -join '') | ConvertFrom-Json
                                if ($stage.pid -eq [int]$ownedPid -and $stage.stage -eq 'await-batch-native-provider') {
                                    $foreground=(& $ownedAdb -s $ownedDevice shell dumpsys activity activities) -join "`n"
                                    if ($foreground -match 'topResumedActivity=.*com\.vivo\.credentialmanager/\.CredentialSelectorActivity') {
                                        $ack=@{pid=[int]$ownedPid;stage='await-batch-native-provider';providerComponent='com.vivo.credentialmanager/.CredentialSelectorActivity'} | ConvertTo-Json -Compress
                                        $ack | & $ownedAdb -s $ownedDevice shell run-as $ownedApp tee files/owned-batch-provider-ack.json | Out-Null
                                        if ($LASTEXITCODE -ne 0) {throw 'Could not acknowledge the actual owned native provider'}
                                        if ($ownedPhase -eq 'batch-passkey-timeout') {
                                            for($waiting=0;$waiting -lt 160;$waiting++) {
                                                $after=((& $ownedAdb -s $ownedDevice shell run-as $ownedApp cat files/owned-device-driver-stage.json) -join '') | ConvertFrom-Json
                                                if($after.pid -eq [int]$ownedPid -and $after.stage -eq 'batch-owned-native-timeout-returned') {
                                                    $top=(& $ownedAdb -s $ownedDevice shell dumpsys activity activities) -join "`n"
                                                    $hostBack=$top -match 'topResumedActivity=.*com\.vivo\.credentialmanager/\.CredentialSelectorActivity'
                                                    if($hostBack) {
                                                        & $ownedAdb -s $ownedDevice shell input keyevent KEYCODE_BACK
                                                        if($LASTEXITCODE -ne 0){throw 'Owned provider dismissal after native timeout failed'}
                                                    }
                                                    $done=@{pid=[int]$ownedPid;nativeResultBeforeHostBack=$true;hostBackUsed=$hostBack} | ConvertTo-Json -Compress
                                                    $done | & $ownedAdb -s $ownedDevice shell run-as $ownedApp tee files/owned-batch-timeout-dismissed.json | Out-Null
                                                    if($LASTEXITCODE -ne 0){throw 'Could not acknowledge native timeout provider cleanup'}
                                                    return 'PASS: actual provider observed; native cancellation returned before host UI cleanup'
                                                }
                                                Start-Sleep -Milliseconds 500
                                            }
                                            throw 'Native timeout result not observed; host did not cancel early'
                                        }
                                        return 'PASS: actual vivo CredentialSelectorActivity observed before controller cancellation'
                                    }
                                }
                            }
                            Start-Sleep -Milliseconds 500
                        }
                        throw 'Actual owned native provider not observed; unrelated background is insufficient'
                    }
                }
                if ($MatrixPhases -and $phase -eq 'lifecycle') {
                    $lifecycleJob = Start-Job -ArgumentList $adb, $DeviceId, $applicationId, $appPid -ScriptBlock {
                        param($ownedAdb, $ownedDevice, $ownedApp, $ownedPid)
                        $ErrorActionPreference = 'Stop'
                        for ($attempt = 0; $attempt -lt 90; $attempt++) {
                            $raw = $null
                            & $ownedAdb -s $ownedDevice shell run-as $ownedApp test -f files/owned-device-driver-stage.json | Out-Null
                            if ($LASTEXITCODE -eq 0) {
                                $raw = (& $ownedAdb -s $ownedDevice shell run-as $ownedApp cat files/owned-device-driver-stage.json) -join ''
                            }
                            if ($raw) {
                                $stage = $raw | ConvertFrom-Json
                                if ($stage.pid -eq [int]$ownedPid -and $stage.stage -eq 'await-real-background') {
                                    $foreground = (& $ownedAdb -s $ownedDevice shell dumpsys activity activities) -join "`n"
                                    if ($foreground -notmatch "(?:mResumedActivity:|topResumedActivity=|ResumedActivity:).*$([regex]::Escape($ownedApp))/.MainActivity") {
                                        throw 'Expected the owned App in the foreground before Home'
                                    }
                                    & $ownedAdb -s $ownedDevice shell input keyevent KEYCODE_HOME | Out-Null
                                    Start-Sleep -Seconds 3
                                    # am start can emit its normal "task brought
                                    # to front" warning on stderr with exit 0.
                                    # Windows PowerShell turns that into an
                                    # ErrorRecord; judge this command by its code.
                                    $ErrorActionPreference = 'Continue'
                                    & $ownedAdb -s $ownedDevice shell am start -n "$ownedApp/.MainActivity" 2>&1 | Out-Null
                                    $resumeExit = $LASTEXITCODE
                                    $ErrorActionPreference = 'Stop'
                                    if ($resumeExit -ne 0) { throw 'Owned activity could not resume' }
                                    return 'PASS: owned actual Android Home and foreground transition'
                                }
                            }
                            Start-Sleep -Seconds 1
                        }
                        throw 'Owned lifecycle stage did not become ready'
                    }
                }
                if ($LifecyclePhases -and $phase -eq 'phone-lock-cycle') {
                    $lifecycleJob = Start-Job -ArgumentList $adb, $DeviceId, $applicationId, $appPid -ScriptBlock {
                        param($ownedAdb, $ownedDevice, $ownedApp, $ownedPid)
                        $ErrorActionPreference = 'Stop'
                        for ($attempt = 0; $attempt -lt 120; $attempt++) {
                            & $ownedAdb -s $ownedDevice shell run-as $ownedApp test -f files/owned-device-driver-stage.json | Out-Null
                            if ($LASTEXITCODE -eq 0) {
                                $stage = ((& $ownedAdb -s $ownedDevice shell run-as $ownedApp cat files/owned-device-driver-stage.json) -join '') | ConvertFrom-Json
                                if ($stage.pid -eq [int]$ownedPid -and $stage.stage -eq 'await-real-lock') {
                                    $foreground = (& $ownedAdb -s $ownedDevice shell dumpsys activity activities) -join "`n"
                                    if ($foreground -notmatch "(?:mResumedActivity:|topResumedActivity=|ResumedActivity:).*$([regex]::Escape($ownedApp))/.MainActivity") {
                                        throw 'Owned App must be in foreground before the accepted lock cycle'
                                    }
                                    & $ownedAdb -s $ownedDevice shell input keyevent KEYCODE_SLEEP | Out-Null
                                    if ($LASTEXITCODE -ne 0) {throw 'Owned physical lock action failed'}
                                    return 'PASS: physical sleep requested; App still must observe locked, unlocked and resumed'
                                }
                            }
                            Start-Sleep -Seconds 1
                        }
                        throw 'Owned physical lock stage did not become ready'
                    }
                }
                # Windows PowerShell represents normal Flutter stderr (including
                # mirror notices) as ErrorRecord. Judge the CLI by its exit code.
                $ErrorActionPreference = 'Continue'
                & flutter drive --no-pub -d $DeviceId --driver test_driver/auth_live_device_driver.dart `
                    --target $target `
                    --use-existing-app $vmUri --keep-app-running 2>&1
                $driveExit = $LASTEXITCODE
                $ErrorActionPreference = 'Stop'
                if ($NonIOSPhases -and $phase -eq 'ni-l02') {
                    $firstDriveRecord = @{pid=[int]$appPid;firstDriveReturned=$true;exitCode=$driveExit}|ConvertTo-Json -Compress
                    [IO.File]::WriteAllText('D:\zewbbyTest\Hnuhole-android-live-faults-20261005\matrix\b1b2-evidence\ni-l02-first-drive-done.json',$firstDriveRecord)
                    # The old isolate must disappear during real engine destruction.
                    # Reattach once, only after independent Android counters prove it.
                    $life = ((& $adb -s $DeviceId shell run-as $applicationId cat files/owned-acceptance-lifecycle.json) -join '') | ConvertFrom-Json
                    $native = ((& $adb -s $DeviceId shell run-as $applicationId cat files/owned-acceptance-passkey.json) -join '') | ConvertFrom-Json
                    if ($life.pid -ne [int]$appPid -or $life.activityCreated -lt 2 -or $life.activityDestroyed -lt 1 -or
                        $life.engineAttached -lt 2 -or $native.engineDetached -lt 1 -or $native.nativeCancelled -lt 1) {
                        throw 'Reattach denied: actual Activity/engine teardown not established'
                    }
                    $privateInfo = $null
                    for($vmAttempt=0;$vmAttempt -lt 100;$vmAttempt++) {
                        $possible = ((& $adb -s $DeviceId shell run-as $applicationId cat files/owned-device-driver-vm.json) -join '') | ConvertFrom-Json
                        if ($possible.pid -eq [int]$appPid -and $possible.phase -eq 'ni-l02-read') {$privateInfo=$possible;break}
                        Start-Sleep -Milliseconds 100
                    }
                    if (!$privateInfo) {throw 'Recreated Dart engine did not publish its new private VM service'}
                    $candidate = [Uri]$privateInfo.uri
                    if ($privateInfo.pid -ne [int]$appPid -or $candidate.Scheme -ne 'http' -or $candidate.Host -ne '127.0.0.1' -or
                        $candidate.Port -lt 1024 -or $candidate.UserInfo -or $candidate.Query -or $candidate.Fragment) {
                        throw 'Recreated owned engine VM endpoint invalid'
                    }
                    & $adb -s $DeviceId forward --remove "tcp:$hostPort"
                    $hostPort = (& $adb -s $DeviceId forward tcp:0 "tcp:$($candidate.Port)").Trim()
                    if ($LASTEXITCODE -ne 0 -or $hostPort -notmatch '^\d+$') { throw 'Recreated owned engine forwarding failed' }
                    $vmUri = "http://127.0.0.1:$hostPort$($candidate.AbsolutePath)"
                    $ErrorActionPreference = 'Continue'
                    & flutter drive --no-pub -d $DeviceId --driver test_driver/auth_live_device_driver.dart `
                        --target $target --use-existing-app $vmUri --keep-app-running 2>&1
                    $driveExit = $LASTEXITCODE
                    $ErrorActionPreference = 'Stop'
                }
                if ($driveExit -ne 0) { throw "Actual App device phase failed: $phase" }
                if ($lifecycleJob) {
                    Wait-Job -Job $lifecycleJob -Timeout 10 | Out-Null
                    $lifecycleJob | Receive-Job -ErrorAction Stop
                    if ($lifecycleJob.State -ne 'Completed') { throw 'Owned host lifecycle control failed' }
                }
            } finally {
                if ($lifecycleJob) {
                    Stop-Job -Job $lifecycleJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $lifecycleJob -Force
                }
                & $adb -s $DeviceId forward --remove "tcp:$hostPort"
                & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-device-driver-vm.json
                & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-device-driver-stage.json
                if ($BatchProxyControl -and $phase -in @('batch-passkey-route-cancel','batch-passkey-timeout')) {
                    & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-batch-provider-ack.json
                    & $adb -s $DeviceId shell run-as $applicationId rm -f files/owned-batch-timeout-dismissed.json
                }
                # Flutter can leave its logcat child after drive exits. Only
                # collect newly spawned, orphaned logcat readers for this phone;
                # preserve the shared adb server and any preexisting readers.
                if ($driveStart) {
                    $expectedLogcat = "$adb -s $DeviceId shell -x logcat -v time -T 0"
                    foreach ($reader in @(Get-CimInstance Win32_Process -Filter "Name = 'adb.exe'")) {
                        if ($reader.ProcessId -notin $priorLogcat -and
                            $reader.CommandLine -ceq $expectedLogcat -and
                            $reader.CreationDate -ge $driveStart -and
                            !(Get-Process -Id $reader.ParentProcessId -ErrorAction SilentlyContinue)) {
                            Stop-Process -Id $reader.ProcessId
                        }
                    }
                }
            }
            $response = Join-Path $driverRoot 'build\integration_response_data.json'
            $data = Get-Content -LiteralPath $response -Raw | ConvertFrom-Json
            # Fresh/recovered-key storage phases deliberately stop before any
            # authenticated C/V request. Require their accurate false report.
            $expectedActualCV = !($StoragePhases -and $phase -in @('storage-fresh','storage-restored-no-key'))
            if ($B3B4Phases -and $phase -eq 'ni-k01' -and $B3B4Variant -in @('fresh','no-key')) { $expectedActualCV=$false }
            if ($data.phase -ne $phase -or !$data.actualApp -or
                $data.actualCV -ne $expectedActualCV -or !$data.nativeVault) {
                throw 'Device response does not match the expected actual App phase'
            }
            Copy-Item -LiteralPath $response -Destination (Join-Path $driverRoot "live-$phase.json")
            if ($B3B4Phases) {
                Copy-Item -LiteralPath $response -Destination (Join-Path $driverRoot "live-$phase-$B3B4Variant.json")
                & wsl -d Ubuntu-24.04 -- python3 /var/tmp/hnuhole-android-live-b3-b4-20261009/repo/tools/control-android-b3-b4.py capture --phase $phase --variant $B3B4Variant
                if ($LASTEXITCODE -ne 0) { throw 'B3/B4 independent SQL/proxy evidence failed' }
            }
            if ($NonIOSPhases) {
                & wsl -d Ubuntu-24.04 -- python3 /var/tmp/hnuhole-android-live-batch-20261007/repo/tools/control-android-b1-b2.py capture --phase $phase
                if ($LASTEXITCODE -ne 0) { throw 'B1/B2 SQL/proxy counts failed; App report alone is insufficient' }
            }
            if ($BatchProxyControl -and ($phase -like 'batch-passkey-*' -or $phase -eq 'batch-gate-session-recover')) {
                & wsl -d Ubuntu-24.04 -- python3 /var/tmp/hnuhole-android-live-batch-20261007/repo/tools/control-android-batch-proxy.py capture --phase $phase
                if ($LASTEXITCODE -ne 0) { throw 'Owned batch proxy counters failed; App report alone is not accepted' }
            }
            [IO.File]::WriteAllText((Join-Path $driverRoot 'live-installed-apk-sha256.txt'), $reviewedDigest)
            if ($FaultWork) {
                & wsl -d Ubuntu-24.04 -- python3 "$FaultWork/repo/tools/control-android-auth-fault.py" `
                    --work $FaultWork --phase $phase --capture
                if ($LASTEXITCODE -ne 0) { throw 'Owned SQL/proxy phase evidence capture failed' }
            }
            & $adb -s $DeviceId shell am force-stop $applicationId
            if ($LASTEXITCODE -ne 0) { throw 'Could not stop the owned test App process' }
            } finally {
                if ($nonIOSPrepared -and (Test-Path -LiteralPath "D:\zewbbyTest\Hnuhole-android-live-faults-20261005\matrix\b1b2-evidence\$phase-device-baseline.json")) {
                    & python $nonIOSController restore --phase $phase --device $DeviceId
                    if ($LASTEXITCODE -ne 0) {throw 'Original fixed-case device settings could not be restored'}
                }
            }
        }
    } finally {
        Pop-Location
    }
} finally {
    foreach ($endpoint in $portsCreated) {
        & $adb -s $DeviceId reverse --remove $endpoint
    }
}
# Retain this owned test App and reusable environment when requested by the user.
# Any later uninstall is separate and requires the same run ownership checks.
