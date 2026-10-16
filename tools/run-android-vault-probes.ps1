param(
    [Parameter(Mandatory)][string]$DeviceId,
    [Parameter(Mandatory)][string]$TestApk,
    [string]$EnvironmentRoot = 'D:\zewbbyTest\Hnuhole-env',
    [switch]$UseInstalledApk
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env-hnuhole-windows.ps1') -EnvironmentRoot $EnvironmentRoot
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
$runner = 'org.hnuhole.authvault.test/androidx.test.runner.AndroidJUnitRunner'
$probeClass = 'org.hnuhole.authvault.AuthVaultProcessRestartTest'
if ($UseInstalledApk) {
    $installed = (& $adb -s $DeviceId shell pm path org.hnuhole.authvault.test) -join ''
    $match = [regex]::Match($installed, '^package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)$')
    if (!$match.Success) { throw 'Expected the installed owned monolithic vault probe APK' }
    $actual = (& $adb -s $DeviceId shell sha256sum $match.Groups[1].Value) -join ''
    $expected = (Get-FileHash -LiteralPath $TestApk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -notmatch "^$expected\s") { throw 'Installed vault probe differs from the reviewed test APK' }
} else {
    & $adb -s $DeviceId install --no-streaming -t -r $TestApk
    if ($LASTEXITCODE -ne 0) { throw 'Test APK installation failed' }
}

function Invoke-VaultInstrumentation {
    param([string]$TestClass, [string]$Phase, [string]$Namespace, [switch]$Interrupted)
    $arguments = @('-s', $DeviceId, 'shell', 'am', 'instrument', '-w', '-e', 'class', $TestClass)
    if ($Phase) {
        $arguments += @('-e', 'vault_restart_phase', $Phase, '-e', 'vault_restart_namespace', $Namespace)
    }
    $output = (& $adb @arguments $runner 2>&1 | Out-String)
    Write-Output $output
    if ($Interrupted) {
        if ($output -notmatch 'Process crashed|INSTRUMENTATION_FAILED') {
            throw "Expected process interruption was absent: $Phase"
        }
    } elseif ($LASTEXITCODE -ne 0 -or $output -notmatch 'OK \(\d+ tests?\)' -or $output -match 'FAILURES|INSTRUMENTATION_FAILED') {
        throw "Instrumentation did not pass: $TestClass $Phase"
    }
}

Invoke-VaultInstrumentation -TestClass 'org.hnuhole.authvault.AndroidAuthVaultTest'
$suffix = [Guid]::NewGuid().ToString('N')
$pairs = @(
    @('write', 'read'),
    @('kill-before-replace', 'read-before'),
    @('kill-after-sync', 'read-after')
)
for ($index = 0; $index -lt $pairs.Count; $index++) {
    $namespace = "native.restart.$suffix.$index"
    $writePhase = $pairs[$index][0]
    $readPhase = $pairs[$index][1]
    Invoke-VaultInstrumentation -TestClass $probeClass -Phase $writePhase -Namespace $namespace -Interrupted:($index -gt 0)
    & $adb -s $DeviceId shell am force-stop org.hnuhole.authvault.test
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop the test process' }
    Invoke-VaultInstrumentation -TestClass $probeClass -Phase $readPhase -Namespace $namespace
}
