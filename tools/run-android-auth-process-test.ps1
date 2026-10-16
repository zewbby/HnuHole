param(
    [Parameter(Mandatory)][string]$DeviceId,
    [Parameter(Mandatory)][string]$WriteApk,
    [Parameter(Mandatory)][string]$ReadApk,
    [string]$EnvironmentRoot = 'D:\zewbbyTest\Hnuhole-env',
    [string]$PubCache
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env-hnuhole-windows.ps1') -EnvironmentRoot $EnvironmentRoot
if ($PubCache) { $env:PUB_CACHE = $PubCache }
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
$mobile = Join-Path (Split-Path $PSScriptRoot) 'apps\mobile'
Push-Location $mobile
try {
    foreach ($apk in @($WriteApk, $ReadApk)) {
        # Flutter drive's default stop() uninstalls the application. Keep it
        # installed, then force-stop explicitly so the next process keeps data.
        & flutter drive -d $DeviceId --driver test_driver/auth_security_test.dart `
            --target integration_test/auth_security_device_test.dart `
            --use-application-binary $apk --keep-app-running
        if ($LASTEXITCODE -ne 0) { throw "Flutter device phase failed: $apk" }
        & $adb -s $DeviceId shell am force-stop org.hnuhole.hnuhole_mobile
        if ($LASTEXITCODE -ne 0) { throw 'Could not stop the test app process' }
    }
} finally {
    Pop-Location
}
