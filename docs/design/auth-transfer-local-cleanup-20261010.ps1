param([switch]$Execute)
$ErrorActionPreference = 'Stop'
# Local completion entry only. The agent's delete calls were rejected by policy;
# this script is delivered for review/manual use and was not executed by the agent.
$repo = 'C:\Users\Administrator\Documents\ChatGPT\HnuHole'
$transfer = 'C:\Users\Administrator\Documents\HnuHole-transfer-20261010'
$key = 'C:\Users\Administrator\Documents\HnuHole-auth-archive-key-20261010.txt'
if (-not (Test-Path -LiteralPath $key)) { throw 'Preserve the separately delivered archive key first.' }
$manifest = Get-Content -LiteralPath (Join-Path $repo 'services\api\authlab\auth-machine-cache-archive-verification.json') -Raw | ConvertFrom-Json
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/zewbby/HnuHole/releases/tags/auth-machine-handoff-20261010' -Headers @{ Accept = 'application/vnd.github+json' }
if ($release.draft) { throw 'Require a published remote backup.' }
foreach ($archive in $manifest.archives) {
    foreach ($part in $archive.parts) {
        $asset = @($release.assets | Where-Object { $_.name -ceq $part.name })
        if ($asset.Count -ne 1 -or $asset[0].state -cne 'uploaded' -or $asset[0].size -ne $part.bytes -or $asset[0].digest -cne ('sha256:' + $part.sha256)) {
            throw ('Remote archive mismatch: ' + $part.name)
        }
    }
}
$actualTransfer = (Resolve-Path -LiteralPath $transfer).Path
if ($actualTransfer -cne $transfer) { throw 'Transfer path mismatch.' }
if ((Get-Content -LiteralPath (Join-Path $transfer 'OWNER') -Raw).Trim() -cne 'HNUHOLE_AUTH_MACHINE_TRANSFER_V1') { throw 'Transfer OWNER mismatch.' }
$targets = @(
    (Join-Path $repo 'infra\.cache\android-matrix'),
    (Join-Path $repo 'infra\.cache\android-fault'),
    (Join-Path $repo 'infra\.cache\finalize-auth-transfer.py'),
    $transfer
)
foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) {
        $actual = (Resolve-Path -LiteralPath $target).Path
        if ($actual -cne $target) { throw 'Cleanup target mismatch.' }
        $item = Get-Item -LiteralPath $actual -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reject linked cleanup root.' }
        Write-Output ('Confirmed task target: ' + $actual)
    }
}
if (-not $Execute) {
    Write-Output 'Dry run only. Review the targets; -Execute performs the manual cleanup.'
    exit 0
}
foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
Write-Output 'Removed the three exact task directories and historical cache script. SDK/AVD, phone data and the separate key were preserved.'
