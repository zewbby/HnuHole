# Dot-source this file to configure the current PowerShell session.
param([string]$EnvironmentRoot = 'D:\zewbbyTest\Hnuhole-env')

$env:FLUTTER_ROOT = Join-Path $EnvironmentRoot 'windows\flutter'
$env:JAVA_HOME = Join-Path $EnvironmentRoot 'windows\jdk-17.0.20.1+1'
$env:ANDROID_HOME = Join-Path $EnvironmentRoot 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_USER_HOME = Join-Path $EnvironmentRoot 'android-user'
$env:ANDROID_AVD_HOME = Join-Path $EnvironmentRoot 'avd'
$env:PUB_CACHE = Join-Path $EnvironmentRoot 'pub-cache-windows'
$env:GRADLE_USER_HOME = Join-Path $EnvironmentRoot 'gradle-cache-windows'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

$toolPaths = @(
    (Join-Path $env:FLUTTER_ROOT 'bin'),
    (Join-Path $env:JAVA_HOME 'bin'),
    (Join-Path $env:ANDROID_HOME 'platform-tools'),
    (Join-Path $env:ANDROID_HOME 'emulator'),
    (Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin')
)
foreach ($required in @($env:FLUTTER_ROOT, $env:JAVA_HOME, $env:ANDROID_HOME)) {
    if (-not (Test-Path -LiteralPath $required -PathType Container)) {
        throw "Tool installation missing: $required"
    }
}
$remainingPaths = @($env:PATH -split ';' | Where-Object { $_ -and $_ -notin $toolPaths })
$env:PATH = ($toolPaths + $remainingPaths) -join ';'
