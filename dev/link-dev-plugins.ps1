# Makes one folder that holds both the real plugin and the beta dev tools, as directory
# junctions back into this repo, so one plugins_setpath loads both and edits show up on prl.
# Run: powershell -File dev\link-dev-plugins.ps1 [-Target <folder>]
param([string]$Target = (Join-Path $env:LOCALAPPDATA 'chunk-picker-dev-plugins'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $Target | Out-Null
$links = @{ 'chunk-picker' = (Join-Path $repo 'plugins\chunk-picker'); 'chunk-picker-dev' = (Join-Path $repo 'dev\chunk-picker-dev') }
foreach ($name in $links.Keys) {
  $link = Join-Path $Target $name
  if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link -Force
    if ($item.LinkType -ne 'Junction') { throw "$link exists and is not a junction; move it first" }
    if (($item.Target | Select-Object -First 1) -eq $links[$name]) { continue }
    # Only the junction itself goes; its target in the repo is untouched.
    $item.Delete()
  }
  New-Item -ItemType Junction -Path $link -Target $links[$name] | Out-Null
}
Write-Output "Linked into $Target. In the beta client's console:"
Write-Output "  plugins_setpath $Target"
Write-Output "  prf"
Write-Output "  pon chunk-picker"
Write-Output "  pon chunk-picker-dev"
