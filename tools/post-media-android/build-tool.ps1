param(
  [Parameter(Mandatory=$true)][string]$KitRoot,
  [Parameter(Mandatory=$true)][string]$WorkingDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9._-]+$')][string]$LogName,
  [ValidateSet('flutter','dart','gradle','aapt','apksigner','keytool')][string]$Tool='flutter',
  [Parameter(Mandatory=$true)][string[]]$ToolArgs
)
$ErrorActionPreference='Stop'
$phase=(Resolve-Path -LiteralPath $KitRoot).Path
if((Get-Item -LiteralPath $phase).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Kit root cannot be a link.'}
if((Get-Content -Raw -LiteralPath (Join-Path $phase '.owner')).Trim() -ne 'HNUHOLE_POST_MEDIA_ANDROID_V1|E:/Hnuhole-post-media-joint-20261015/repo'){throw 'This task owner marker is required.'}
$repo='E:\Hnuhole-post-media-joint-20261015\repo'
$sdk=Join-Path $phase 'tools\flutter';$android=Join-Path $phase 'tools\android-sdk';$jdk=Join-Path $phase 'tools\jdk'
$integrationPhase=$phase
$profile=Join-Path $integrationPhase 'profile';$temp=Join-Path $integrationPhase 'temp';$logs=Join-Path $integrationPhase 'logs'
$cwd=(Resolve-Path -LiteralPath $WorkingDirectory).Path
if($cwd -ne (Join-Path $repo 'apps\mobile') -and $cwd -ne (Join-Path $repo 'packages\image_viewer') -and $cwd -ne (Join-Path $repo 'packages\image_viewer\example') -and $cwd -ne (Join-Path $repo 'apps\mobile\android')){throw 'Outside this integration scope.'}
if($ToolArgs -contains '-d' -or $ToolArgs -contains '--device-id'){throw 'No device window; device commands forbidden.'}
switch($Tool){
 'flutter'{
   if($ToolArgs[0] -notin @('--version','analyze','test','build','pub')){throw 'Flutter command outside build/host scope.'}
   if($ToolArgs[0] -eq 'pub' -and ($ToolArgs[1] -ne 'get' -or ($ToolArgs -notcontains '--offline'))){throw 'Only strictly locked offline pub get.'}
   if($ToolArgs[0] -eq 'test' -and ($ToolArgs -join ' ') -match 'integration_test'){throw 'Device tests must wait for authorization.'}
   if($ToolArgs[0] -eq 'build' -and ($ToolArgs[1] -notin @('apk','bundle') -or ($ToolArgs -notcontains '--debug' -and $ToolArgs -notcontains '--release') -or $ToolArgs -notcontains '--no-pub')){throw 'Only debug/release APK or debug bundle builds with no pub; isolated task outputs, no publishing.'}
   $executable=Join-Path $sdk 'bin\flutter.bat';$arguments=@('--suppress-analytics')+$ToolArgs
 }
 'dart'{$executable=Join-Path $sdk 'bin\cache\dart-sdk\bin\dart.exe';$arguments=$ToolArgs;if($ToolArgs[0] -ne 'format' -and ($ToolArgs -join ' ') -ne 'fix --apply --code=curly_braces_in_flow_control_structures'){throw 'Only formatter or scoped braces fix is permitted.'}}
 'gradle'{$executable=Join-Path $cwd 'gradlew.bat';if(-not(Test-Path -LiteralPath $executable)){$cachedGradle=@(Get-ChildItem -LiteralPath (Join-Path $phase 'gradle-cache\wrapper\dists\gradle-9.3.1-bin') -Filter gradle.bat -Recurse);if($cachedGradle.Count -ne 1){throw 'Matching cached Gradle 9.3.1 unavailable.'};$executable=$cachedGradle[0].FullName};$arguments=@('--no-daemon','--max-workers=2')+$ToolArgs;if(($ToolArgs -join ' ') -match '(?i)(install|uninstall|connected|device|stop|clean)'){throw 'No device or broad process/cleanup tasks.'}}
 'aapt'{$executable=Join-Path $android 'build-tools\36.0.0\aapt.exe';$arguments=$ToolArgs;if($ToolArgs[0] -ne 'dump'){throw 'Only APK inspection.'}}
 'apksigner'{$executable=Join-Path $android 'build-tools\36.0.0\apksigner.bat';$arguments=$ToolArgs;if($ToolArgs[0] -ne 'verify'){throw 'Only APK signature verification.'}}
 'keytool'{$executable=Join-Path $jdk 'bin\keytool.exe';$arguments=$ToolArgs;if($ToolArgs[0] -notin @('-list','-genkeypair')){throw 'Only private test key setup/inspection.'}; if($ToolArgs -contains '-keystore'){ $keyPath=$ToolArgs[[Array]::IndexOf($ToolArgs,'-keystore')+1];if(-not[IO.Path]::GetFullPath($keyPath).StartsWith($phase+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Signing files must be private to this task.'}}}
}
if(-not(Test-Path -LiteralPath $executable)){throw "Missing isolated tool: $Tool"}
foreach($root in @($sdk,$android,$jdk,(Join-Path $phase 'pub-cache'))){if((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Private tools cannot be links.'}}
$configPath=Join-Path $sdk 'packages\flutter_tools\.dart_tool\package_config.json'
$config=Get-Content -Raw -LiteralPath $configPath|ConvertFrom-Json
foreach($package in $config.packages){$packagePath=[Uri]::new([Uri]::new($configPath),[string]$package.rootUri).LocalPath;if(-not$packagePath.StartsWith($phase+'\',[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $packagePath)){throw "Tool package points outside this task: $($package.name)"}}
function Get-SourceManifest{
 $paths=@(& git -C $repo ls-files -- packages/image_viewer apps/mobile)+@(& git -C $repo ls-files --others --exclude-standard -- packages/image_viewer apps/mobile)
 if($LASTEXITCODE -ne 0){throw 'Source inventory failed.'}
 $entries=@($paths|Sort-Object -Unique|ForEach-Object{$path=Join-Path $repo $_;if(Test-Path -LiteralPath $path -PathType Leaf){[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}})
 $text=($entries|ForEach-Object{$_.path+' '+$_.sha256})-join "`n"
 return [ordered]@{digestSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant();files=$entries}
}
$gitDir=Split-Path -Parent (Get-Command git.exe).Source;$pwshDir=Split-Path -Parent (Get-Command pwsh.exe).Source
$envMap=@{
 FLUTTER_ROOT=$sdk;PUB_CACHE=(Join-Path $integrationPhase 'pub-cache');PUB_HOSTED_URL='https://pub.dev'
 FLUTTER_STORAGE_BASE_URL='https://storage.googleapis.com';FLUTTER_SKIP_UPDATE_CHECK='true';FLUTTER_SUPPRESS_ANALYTICS='true';DART_SUPPRESS_ANALYTICS='true';CI='true'
 USERPROFILE=$profile;APPDATA=(Join-Path $profile 'AppData\Roaming');LOCALAPPDATA=(Join-Path $profile 'AppData\Local');TEMP=$temp;TMP=$temp
 VIEWER_SCREENSHOT_DIR=(Join-Path $logs 'screenshots');VIEWER_ANIMATION_ANALYSIS_PATH=(Join-Path $logs ($LogName+'-animation-analysis.json'))
 GRADLE_USER_HOME=(Join-Path $phase 'gradle-cache');ANDROID_HOME=$android;ANDROID_SDK_ROOT=$android;ANDROID_USER_HOME=(Join-Path $profile '.android');ANDROID_AVD_HOME=(Join-Path $phase 'no-devices');JAVA_HOME=$jdk
 JAVA_TOOL_OPTIONS="-Duser.home=$($profile.Replace('\','/')) -Djava.io.tmpdir=$($temp.Replace('\','/'))";GRADLE_OPTS='-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2'
 GIT_CONFIG_GLOBAL=(Join-Path $profile 'empty-gitconfig');GIT_CONFIG_NOSYSTEM='1'
 GIT_DIR='';GIT_WORK_TREE='';FLUTTER_TOOL_ARGS='';FLUTTER_ENGINE='';FLUTTER_PREBUILT_ENGINE_VERSION='';DART_SDK='';GRADLE_RO_DEP_CACHE='';JDK_JAVA_OPTIONS='';_JAVA_OPTIONS=''
 PATH=(@((Join-Path $sdk 'bin'),(Join-Path $sdk 'bin\cache\dart-sdk\bin'),(Join-Path $jdk 'bin'),$gitDir,$pwshDir,"$env:SystemRoot\System32",$env:SystemRoot,"$env:SystemRoot\System32\WindowsPowerShell\v1.0")-join ';')
}
$saved=@{};$oldCwd=Get-Location;$started=[DateTimeOffset]::UtcNow;$logPath=Join-Path $logs ($LogName+'.log');$metadataPath=Join-Path $logs ($LogName+'.json');$exit=1
try{
 foreach($name in $envMap.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process');$value=[string]$envMap[$name];if($value.Length){[Environment]::SetEnvironmentVariable($name,$value,'Process')}else{Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue}}
 Set-Location -LiteralPath $cwd
 $before=Get-SourceManifest
 & $executable @arguments *> $logPath
 $exit=$LASTEXITCODE
 $after=Get-SourceManifest
 $meta=[ordered]@{recordedOn=[DateTimeOffset]::Now.ToString('yyyy-MM-dd');command=@($executable)+$arguments;workingDirectory=$cwd;startedAtUtc=$started.ToString('o');endedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');exitCode=$exit;head=(& git -C $repo rev-parse HEAD).Trim();sourceBefore=$before;sourceAfter=$after;sourceStableDuringCommand=($before.digestSha256 -eq $after.digestSha256);locks=@('apps/mobile/pubspec.lock','packages/image_viewer/pubspec.lock','packages/image_viewer/example/pubspec.lock'|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $repo $_) -Algorithm SHA256).Hash.ToLowerInvariant()}});log=$logPath;privateRoot=$phase;pubCache=(Join-Path $integrationPhase 'pub-cache');gradleCache=(Join-Path $phase 'gradle-cache');androidSdk=$android;jdk=$jdk;javaUserHome=$profile;temp=$temp;executionScope='host or build only';deviceWindowGranted=$false;deviceCommandsExecuted=$false;globalConfigChanged=$false;downloadScope='Existing exact-version tools/dependencies copied into this kit; offline only, no device commands'}
 $meta|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $metadataPath -Encoding utf8
 [ordered]@{exitCode=$exit;log=$logPath;metadata=$metadataPath;sourceStable=$meta.sourceStableDuringCommand;elapsedSeconds=[math]::Round(([DateTimeOffset]::UtcNow-$started).TotalSeconds,2)}|ConvertTo-Json
 Get-Content -LiteralPath $logPath -Tail 18
}finally{
 Set-Location -LiteralPath $oldCwd.Path
 foreach($name in $saved.Keys){if($null -eq $saved[$name]){Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue}else{[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
}
exit $exit
