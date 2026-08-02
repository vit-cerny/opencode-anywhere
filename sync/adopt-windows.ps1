# adopt-windows.ps1 - pull an existing "opencode-anywhere" slot down onto an
# existing local Windows opencode install and point you at the realtime web UI.
#
# Companion to setup-windows.ps1 for people who ALREADY have opencode locally
# and just want to adopt a cloud slot (config, skills, MCPs, chats, shared)
# without re-provisioning anything. No admin rights. Nothing secret is written
# to disk or echoed.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File adopt-windows.ps1
#   (reads goto.env from the same folder - see goto.env.example)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root    = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $PSScriptRoot 'goto.env'

# --------------------------------------------------------- 1. read goto.env
if (-not (Test-Path -LiteralPath $EnvFile)) {
  Write-Host ''
  Write-Host 'No "goto.env" was found next to this script.' -ForegroundColor Yellow
  Write-Host 'Step 1:  copy sync/goto.env.example  to  sync/goto.env' -ForegroundColor Cyan
  Write-Host 'Step 2:  fill in DOMAIN / SLOT / VM_IP (your admin emailed them) then run again.' -ForegroundColor Cyan
  exit 1
}

# Parse  KEY=VALUE  lines; ignore blank lines and '#' comments. Nothing secret here.
$cfg = @{}
Get-Content -LiteralPath $EnvFile | ForEach-Object {
  $line = ($_ -replace '^\s*', '' -replace '\s*$', '').Trim()
  if ($line -eq '' -or $line.StartsWith('#')) { return }
  if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
    $cfg[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
  }
}
$Domain = $cfg['DOMAIN']; $Slot = $cfg['SLOT']; $VmIp = $cfg['VM_IP']; $SettingsRepo = $cfg['SETTINGS_REPO']

if (-not $Domain -or -not $Slot -or -not $VmIp) {
  Write-Host ''
  Write-Host 'goto.env is missing DOMAIN, SLOT and/or VM_IP.' -ForegroundColor Yellow
  Write-Host 'Example (plain values only, no secrets):' -ForegroundColor Cyan
  Write-Host '  DOMAIN=yourname.duckdns.org    SLOT=me    VM_IP=198.51.100.7' -ForegroundColor Cyan
  exit 1
}

# ------------------------------------------------------- 2. clone slot state
$Connect = Join-Path $Root 'connect\opencode-connect.ps1'
if (-not (Test-Path -LiteralPath $Connect)) {
  Write-Host 'Cannot find connect\opencode-connect.ps1 beside this repo.' -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host '== ADOPT ======================================' -ForegroundColor Green
Write-Host ("  Cloning slot '{0}' from {1}  (config, skills, MCPs, chats, shared) ..." -f $Slot, $VmIp) -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $Connect $VmIp $Slot pull
if ($LASTEXITCODE -ne 0) {
  Write-Host '  Pull failed. This usually means the slot does not know this PC yet.' -ForegroundColor Yellow
  Write-Host ('  Give the admin your public key:  {0}\.ssh\id_ed25519.pub' -f $env:USERPROFILE) -ForegroundColor Yellow
  Write-Host '  Then run this script again - it is safe to repeat (idempotent).' -ForegroundColor Yellow
  exit $LASTEXITCODE
}
Write-Host '  Slot state is now local. No token or password was written anywhere.' -ForegroundColor Green

# ------------------------------------------------- 3. the three steps to know
Write-Host ''
Write-Host '======== 3 STEPS, ONCE ========' -ForegroundColor Green
Write-Host ('{0,-12} your opencode now has the slot config, skills, chats' -f '1. ADOPT') -ForegroundColor Cyan
Write-Host ('{0,-12} launch opencode or the editor as you normally do - done' -f '2. CONFIGURE') -ForegroundColor Cyan
if ($SettingsRepo) { Write-Host ('           optional: settings repo -> {0}' -f $SettingsRepo) -ForegroundColor DarkCyan }
Write-Host ('{0,-12} realtime web UI (works anywhere, any device):' -f '3. USE') -ForegroundColor Cyan
Write-Host ('           https://{0}.{1}' -f $Slot, $Domain) -ForegroundColor Magenta
Write-Host ''
Write-Host 'Push local edits back to the slot any time (unrelated to adopt):' -ForegroundColor Yellow
Write-Host ('  powershell -File {0} {1} {2} push' -f $Connect, $VmIp, $Slot) -ForegroundColor Yellow