param(
  [Parameter(Mandatory=$true)][string]$FixturePath,
  [Parameter(Mandatory=$true)][ValidateSet('live','down')][string]$Phase,
  [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$taskPackage='org.hnuhole.hnuhole_mobile.commentsnapshot'
$taskAdb='E:/Hnuhole-env/android-sdk/platform-tools/adb.exe'
$taskSerial='7e0660f1'
$taskLease=Get-Content -LiteralPath 'E:/Hnuhole-env/device-leases/7e0660f1.json' -Raw | ConvertFrom-Json
if($taskLease.state -ne 'acquired' -or $taskLease.owner -ne 'COMMENT-SNAPSHOT-REDIS-01'){throw 'Owned device lease required'}
$env:ANDROID_USER_HOME='E:/Hnuhole-env/android-user'
$env:ANDROID_SDK_HOME='E:/Hnuhole-env/android-user'
function Invoke-OwnedAdb([string[]]$Arguments) {
  $taskLines=@(& $taskAdb -s $taskSerial @Arguments 2>&1)
  if($LASTEXITCODE -ne 0){throw 'Owned adb command failed'}
  return ($taskLines -join "`n")
}
function Write-OwnedCache([string]$Name,[string]$Content) {
  $taskStart=[Diagnostics.ProcessStartInfo]::new($taskAdb)
  $taskStart.UseShellExecute=$false
  $taskStart.RedirectStandardInput=$true
  $taskStart.RedirectStandardOutput=$true
  $taskStart.RedirectStandardError=$true
  $taskStart.StandardInputEncoding=[Text.UTF8Encoding]::new($false)
  foreach($taskArg in @('-s',$taskSerial,'shell','run-as',$taskPackage,'sh','-c',"'cat > code_cache/$Name'")){$taskStart.ArgumentList.Add($taskArg)}
  $taskProcess=[Diagnostics.Process]::Start($taskStart)
  $taskProcess.StandardInput.Write($Content);$taskProcess.StandardInput.Close()
  $null=$taskProcess.StandardOutput.ReadToEnd();$null=$taskProcess.StandardError.ReadToEnd()
  $taskProcess.WaitForExit()
  if($taskProcess.ExitCode -ne 0){throw 'Private cache write failed'}
  $taskProcess.Dispose()
}
$taskMappingCreated=$false
$taskPort=$null
$taskResult=@{status='FAIL';phase=$Phase}
try {
  $taskFixtureText=Get-Content -LiteralPath $FixturePath -Raw
  $taskFixture=$taskFixtureText|ConvertFrom-Json
  $taskUrl=[uri]$taskFixture.url
  if($taskUrl.Scheme -ne 'https' -or $taskUrl.Host -ne '127.0.0.1' -or $taskUrl.Port -lt 1024){throw 'Only owned loopback TLS fixture allowed'}
  $taskPort=$taskUrl.Port
  $taskMappings=Invoke-OwnedAdb @('reverse','--list')
  $taskPattern='(?m)^\S+\s+tcp:'+ $taskPort +'\s+(\S+)\s*$'
  if($taskMappings -match $taskPattern){
    if($Matches[1] -ne "tcp:$taskPort"){throw 'Existing USB mapping belongs to another endpoint'}
  } else {
    $null=Invoke-OwnedAdb @('reverse',"tcp:$taskPort","tcp:$taskPort")
    $taskMappingCreated=$true
  }
  $null=Invoke-OwnedAdb @('shell','am','force-stop',$taskPackage)
  $null=Invoke-OwnedAdb @('shell','run-as',$taskPackage,'rm','-f','code_cache/comment-snapshot-native-output.json','code_cache/comment-snapshot-native-suite.json')
  Write-OwnedCache 'comment-snapshot-native-fixture.json' $taskFixtureText
  Write-OwnedCache 'comment-snapshot-native-phase.txt' $Phase
  $null=Invoke-OwnedAdb @('shell','am','start','-W','-n',"$taskPackage/org.hnuhole.hnuhole_mobile.MainActivity")
  $taskDeadline=[DateTime]::UtcNow.AddSeconds(40)
  do {
    $taskOutput=@(& $taskAdb -s $taskSerial shell run-as $taskPackage cat code_cache/comment-snapshot-native-output.json 2>$null)
    if($LASTEXITCODE -eq 0){
      $taskProbe=($taskOutput -join "`n")|ConvertFrom-Json
      if($taskProbe.status -eq 'FAIL'){throw 'Native production transport failed'}
      $taskSuiteLines=@(& $taskAdb -s $taskSerial shell run-as $taskPackage cat code_cache/comment-snapshot-native-suite.json 2>$null)
      if($LASTEXITCODE -eq 0){
        $taskSuite=($taskSuiteLines -join "`n")|ConvertFrom-Json
        $taskValues=@($taskSuite.results.PSObject.Properties.Value)
        if($taskSuite.status -ne 'PASS' -or $taskValues.Count -ne 10 -or @($taskValues|Where-Object {$_ -ne 'success'}).Count){throw 'Native suite did not fully pass'}
        if($taskProbe.phase -ne $Phase){throw 'Native phase mismatch'}
        $taskResult=@{status='PASS';phase=$Phase;requests=$taskProbe.requests;fixtureWidgetsPassed=9;nativeTransportPassed=1;scope='Android production reader with pinned TLS and real SQL/Redis; UI scenarios use fixture authorities/data; native vault not tested'}
        break
      }
    }
    Start-Sleep -Milliseconds 500
  } while([DateTime]::UtcNow -lt $taskDeadline)
  if($taskResult.status -ne 'PASS'){throw 'Native probe timed out'}
} catch {
  $taskResult.errorType=$_.Exception.GetType().Name
} finally {
  $null=& $taskAdb -s $taskSerial shell am force-stop $taskPackage
  $null=& $taskAdb -s $taskSerial shell run-as $taskPackage rm -f code_cache/comment-snapshot-native-fixture.json code_cache/comment-snapshot-native-phase.txt
  if($taskMappingCreated){$null=& $taskAdb -s $taskSerial reverse --remove "tcp:$taskPort"}
  $taskJson=$taskResult|ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText($OutputPath,$taskJson,[Text.UTF8Encoding]::new($false))
  $taskJson
}
if($taskResult.status -ne 'PASS'){exit 1}
