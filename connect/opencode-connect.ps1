# opencode-connect.ps1 - plug YOUR OWN opencode (Windows) into your cloud slot.
#
# Pushes / pulls your local opencode state (config, skills, MCPs, plugins,
# projects, chats, auth) between this machine and one slot on the
# opencode-anywhere VM over sftp (slot users are sftp-only). Requires the
# Windows OpenSSH client (ships with Windows 10/11: ssh.exe + scp.exe).
#
# Usage:
#   pwsh -File opencode-connect.ps1 <vm-ip> <slot-name> push|pull|info
#   (optional) point at your key, e.g. $env:OPENCODE_CONNECT_KEY = "$env:USERPROFILE\.ssh\id_ed25519"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Host2 = $args[0]; $Slot = $args[1]; $Cmd = $args[2]
if (-not $Host2 -or -not $Slot -or ($Cmd -notin @('push','pull','info'))) {
  Write-Host "usage: opencode-connect.ps1 <vm-ip> <slot-name> push|pull|info" -ForegroundColor Yellow
  exit 1
}
$User = "cl-$Slot"
$Dest = "$User@$Host2"
$KeyArgs = @()
if ($env:OPENCODE_CONNECT_KEY) { $KeyArgs = @('-i', $env:OPENCODE_CONNECT_KEY) }

$UProfile = $env:USERPROFILE  # opencode uses XDG-style paths on Windows too
$Pairs = @(
  @{ Local = "$UProfile\.config\opencode";             Remote = '.config/opencode' }
  @{ Local = "$UProfile\.agents\skills";               Remote = '.agents/skills' }
  @{ Local = "$UProfile\.local\share\opencode";        Remote = '.local/share/opencode' }
  @{ Local = "$UProfile\.local\state\opencode";        Remote = '.local/state/opencode' }
  @{ Local = "$UProfile\.codex";                       Remote = '.codex' }
  @{ Local = "$UProfile\.local\share\codex";           Remote = '.local/share/codex' }
  @{ Local = "$UProfile\.config\codex";                Remote = '.config/codex' }
  @{ Local = "$UProfile\.claude";                      Remote = '.claude' }
  @{ Local = "$UProfile\.claude.json";                 Remote = '.claude.json' }
  @{ Local = "$UProfile\.config\claude";               Remote = '.config/claude' }
  @{ Local = "$UProfile\.local\share\claude-code";     Remote = '.local/share/claude-code' }
)

function Test-SlotAuth {
  & ssh @KeyArgs -o BatchMode=yes -o StrictHostKeyChecking=accept-new $Dest "true" 2>$null
  return ($LASTEXITCODE -eq 0)
}

if ($Cmd -eq 'info') {
  Write-Host "slot '$Slot' on $Host2 (user $User, sftp-only)"
  foreach ($p in $Pairs) { Write-Host "  $($p.Local)  ->  ~/$($p.Remote)" }
  if (Test-SlotAuth) { Write-Host "OK - key auth to $Dest works" -ForegroundColor Green }
  else {
    Write-Host "FAILED - cannot authenticate as $User. Ask the VM admin to add your ssh public key." -ForegroundColor Red
    exit 1
  }
  exit 0
}

if ($Cmd -eq 'push') {
  foreach ($p in $Pairs) {
    if (-not (Test-Path $p.Local)) { Write-Host "skip: $($p.Local) does not exist"; continue }
    Write-Host "push $($p.Local) -> $Dest`:$($p.Remote)"
    & ssh @KeyArgs $Dest "mkdir -p '$($p.Remote)'"
    if ((Get-Item $p.Local).PSIsContainer) {
      Get-ChildItem -Force $p.Local | ForEach-Object {
        & scp @KeyArgs -q -r $_.FullName "$Dest`:$($p.Remote)/"
      }
    } else {
      # ponytail: file-type pair (e.g. ~/.claude.json) - scp it directly
      & scp @KeyArgs -q "$p.Local" "$Dest`:$($p.Remote)"
    }
  }
  Write-Host 'push done: slot now mirrors this machine. Open https://<slot>.<your-domain> in any browser.' -ForegroundColor Green
  exit 0
}

if ($Cmd -eq 'pull') {
  $Backup = "$UProfile\opencode-connect-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
  New-Item -ItemType Directory -Force -Path $Backup | Out-Null
  foreach ($p in $Pairs) {
    if (Test-Path $p.Local) { Copy-Item -Recurse -Force $p.Local "$Backup\$(Split-Path $p.Local -Leaf)" }
    if ($p.Remote -like '*.claude.json') {
      # ponytail: single-file pair - scp it directly
      New-Item -ItemType Directory -Force -Path (Split-Path $p.Local) | Out-Null
      Write-Host "pull $Dest`:$($p.Remote) -> $($p.Local)"
      & scp @KeyArgs -q "$Dest`:$($p.Remote)" $p.Local 2>$null
      if (-not $?) { Write-Host "  WARNING: remote $($p.Remote) missing is fine" }
      continue
    }
    New-Item -ItemType Directory -Force -Path $p.Local | Out-Null
    Write-Host "pull $Dest`:$($p.Remote) -> $($p.Local)"
    & scp @KeyArgs -q -r "$Dest`:$($p.Remote)/*" "$($p.Local)/" 2>$null
    if (-not $?) { Write-Host "  WARNING: empty/missing remote $($p.Remote) is fine" }
  }
  Write-Host "pull done; previous local state backed up under $Backup" -ForegroundColor Green
  exit 0
}