# opencode-anywhere security gate (PowerShell 5.1+, cross-platform for CI).
# Run from anywhere:  pwsh -File scripts/check.ps1   (repo root is auto-detected)
# Exits 0 when every check passes, 1 otherwise. The script skips its own file
# and .git so the patterns it looks for never trip its own scan.
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$self = [System.IO.Path]::GetFullPath($PSCommandPath)
$failures = @()

function Fail {
  param([string]$Message)
  $script:failures += $Message
}

function Get-RepoFiles {
  Get-ChildItem -LiteralPath $repo -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and $_.FullName -ne $self
  }
}

# ---- 1. opencode.jsonc must parse and contain the server-mode essentials ----
$jsoncPath = Join-Path $repo 'opencode.jsonc'
$jsonc = Get-Content -LiteralPath $jsoncPath -Raw

function ConvertFrom-Jsonc {
  param([string]$Text)
  # Strip // line comments only OUTSIDE double-quoted strings, then trailing commas, then parse.
  $sb = New-Object System.Text.StringBuilder
  $inString = $false
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $c = $Text[$i]
    if ($inString) {
      [void]$sb.Append($c)
      if ($c -eq '"') { $inString = $false }
    } elseif ($c -eq '"') {
      $inString = $true
      [void]$sb.Append($c)
    } elseif ($c -eq '/' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '/') {
      while ($i -lt $Text.Length -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") { $i++ }
    } else {
      [void]$sb.Append($c)
    }
  }
  $clean = [regex]::Replace($sb.ToString(), ',\s*([}\]])', '$1')
  return ($clean | ConvertFrom-Json)
}

try {
  $cfg = ConvertFrom-Jsonc $jsonc
  if ($null -eq $cfg.mcp -or $null -eq $cfg.mcp.playwright) { Fail 'opencode.jsonc: missing "mcp" or "mcp.playwright"' }
  if ($null -eq $cfg.agent.'vision-assistant') { Fail 'opencode.jsonc: missing agent "vision-assistant"' }
  if ($null -eq $cfg.server -or $cfg.server.port -ne 4096 -or $cfg.server.hostname -ne '127.0.0.1') { Fail 'opencode.jsonc: server block must be { port: 4096, hostname: "127.0.0.1" }' }
  if ($cfg.permission.playwright_browser_run_code_unsafe -ne 'deny') { Fail 'opencode.jsonc: playwright_browser_run_code_unsafe must be "deny"' }
  if ($cfg.permission.playwright_browser_evaluate -ne 'ask') { Fail 'opencode.jsonc: playwright_browser_evaluate must be "ask"' }
} catch {
  Fail "opencode.jsonc does not parse as JSON: $($_.Exception.Message)"
}

# ---- 2. Secret sweep: no personal names, key material, or password values ----
$secretPattern = 'witek|sk-proj-|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA|OPENAI_API_KEY=\S{16,}|BEGIN [A-Z ]*PRIVATE KEY|GITHUB_TOKEN=|GITLAB_TOKEN=|ocid1\.[A-Za-z0-9._-]+:oc1:|[?&]token=[A-Za-z0-9-]{20,}'
foreach ($file in Get-RepoFiles) {
  $lines = (Get-Content -LiteralPath $file.FullName -Raw) -split "`r?`n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $secretPattern) {
      Fail "secret sweep: $($file.Name):$($i + 1) contains a forbidden pattern"
    }
    if ($lines[$i] -match 'OPENCODE_SERVER_PASSWORD\s*=\s*([''"])?([^''"\r\n]*)\1?') {
      $v = $Matches[2].Trim()
      $placeholder = $v -match '^(<|your-|a-|example|changeme)' -or $v -eq 'password' -or $v -eq 'secret'
      $dynamic = $v -match '^\$' -or $v -match '\$\(' -or $v -match '`'
      if ($v -ne '' -and $v -ne '%s' -and -not $dynamic -and -not $placeholder) {
        Fail "secret sweep: $($file.Name):$($i + 1) contains an OPENCODE_SERVER_PASSWORD value"
      }
    }
  }
}

# ---- 3. Template hygiene ----
if ($jsonc -notmatch '\{\{HOME\}\}') { Fail 'opencode.jsonc: {{HOME}} placeholder missing' }
foreach ($file in Get-RepoFiles) {
  $text = Get-Content -LiteralPath $file.FullName -Raw
  if ($text -match 'C:\\Users') { Fail "template hygiene: $($file.Name) contains a hardcoded C:\Users path" }
  if ($text -match '/Users/myau|/home/myau') { Fail "template hygiene: $($file.Name) contains a personal home path" }
  if ($text -match '\{\{USERPROFILE\}\}') { Fail "template hygiene: $($file.Name) still uses the {{USERPROFILE}} placeholder" }
}

# ---- 4. provision.sh safety ----
$provisionPath = Join-Path $repo 'provision.sh'
if (-not (Test-Path -LiteralPath $provisionPath)) { Fail 'provision.sh missing' } else {
  $prov = Get-Content -LiteralPath $provisionPath -Raw
  foreach ($pat in @('curl[^\r\n]*\|\s*(ba)?sh', 'wget[^\r\n]*\|\s*(ba)?sh', 'iwr[^\r\n]*\|\s*iex', 'Invoke-Expression', 'rm\s+-rf\s+/(\s|$|\*)', 'opencode\.ai/install')) {
    if ($prov -match $pat) { Fail "provision.sh: unsafe pattern: $pat" }
  }
  if ($prov -notmatch 'OPENCODE_SERVER_PASSWORD') { Fail 'provision.sh: must reference OPENCODE_SERVER_PASSWORD' }
  if ($prov -notmatch 'set\s+-euo\s+pipefail') { Fail 'provision.sh: missing "set -euo pipefail"' }
  if ($prov -notmatch 'add-slot\.sh') { Fail 'provision.sh: must delegate slot creation to add-slot.sh' }
  if ($prov -notmatch 'PasswordAuthentication no') { Fail 'provision.sh: missing sshd PasswordAuthentication hardening' }
}

# ---- 4b. Slot engine hardening (anti-drift across provisioning) ----
foreach ($slotScript in @('add-slot.sh', 'remove-slot.sh', 'list-slots.sh')) {
  $p = Join-Path $repo $slotScript
  if (-not (Test-Path -LiteralPath $p)) { Fail "$slotScript missing"; continue }
  $t = Get-Content -LiteralPath $p -Raw
  if ($t -notmatch 'set\s+-euo\s+pipefail') { Fail "${slotScript}: missing 'set -euo pipefail'" }
}
$addSlot = Get-Content -LiteralPath (Join-Path $repo 'add-slot.sh') -Raw
foreach ($must in @('EnvironmentFile=/etc/opencode/', 'OPENCODE_DISABLE_AUTOUPDATE=1', 'ForceCommand internal-sftp', 'chmod 0600', '--hostname 127.0.0.1', 'caddy validate',
                    'mkdir -p "$HOME_DIR/.codex"', '.codex/config.toml', '[approval_policy]', 'mode = "off"', 'chmod 0700 "$HOME_DIR/.codex"',
                    'mkdir -p "$HOME_DIR/.claude"', ': > "$HOME_DIR/.claude.json"', 'settings.json', 'chmod 0700 "$HOME_DIR/.claude"',
                    'chmod 0600 "$HOME_DIR/.claude.json" "$HOME_DIR/.claude/settings.json"')) {
  if ($addSlot -notmatch [regex]::Escape($must)) { Fail "add-slot.sh: hardening regression - missing '$must'" }
}
# 'admin off' is a Caddy GLOBAL option (base Caddyfile seeded by provision.sh
# only when absent) — add-slot appends proxy-only vhosts and must NOT re-add it.
$provision = Get-Content -LiteralPath (Join-Path $repo 'provision.sh') -Raw
if ($provision -notmatch [regex]::Escape('admin off')) { Fail "provision.sh: base Caddyfile must set 'admin off' (global)" }
if ($addSlot -match [regex]::Escape('admin off')) { Fail 'add-slot.sh: "admin off" belongs in the global Caddyfile options, not a per-slot vhost' }
if ($provision -notmatch '@openai/codex') { Fail "provision.sh: must install codex CLI" }
if ($provision -notmatch '@anthropic-ai/claude-code') { Fail "provision.sh: must install claude code CLI" }

# ---- 4d. connect client must sync codex + claude state so slots stay whole ---
foreach ($connect in @('connect/opencode-connect.sh', 'connect/opencode-connect.ps1')) {
  $c = Get-Content -LiteralPath (Join-Path $repo $connect) -Raw
  foreach ($must in @('.codex', '.claude', '.local/share/claude-code')) {
    if ($c -notmatch [regex]::Escape($must)) { Fail "${connect}: missing codex/claude PAIRS entry '$must'" }
  }
}

# ---- 4c. Shell scripts must be LF ----
Get-ChildItem -LiteralPath $repo -Recurse -File -Filter *.sh | ForEach-Object {
  $raw = [System.IO.File]::ReadAllText($_.FullName)
  if ($raw -match "`r") { Fail "CRLF line endings in $($_.Name) - convert to LF (see .gitattributes)" }
}

# ---- 5. Helper scripts must exist and be safe ----
foreach ($script in @('qrcode.sh', 'backup.sh', 'restore.sh')) {
  $p = Join-Path $repo $script
  if (-not (Test-Path -LiteralPath $p)) { Fail "$script missing"; continue }
  $t = Get-Content -LiteralPath $p -Raw
  if ($t -notmatch 'set\s+-euo\s+pipefail') { Fail "${script}: missing 'set -euo pipefail'" }
}
$qrcode = Get-Content -LiteralPath (Join-Path $repo 'qrcode.sh') -Raw
if ($qrcode -notmatch 'qrencode') { Fail 'qrcode.sh: must invoke qrencode' }
$backup = Get-Content -LiteralPath (Join-Path $repo 'backup.sh') -Raw
if ($backup -notmatch 'tar\s+czf') { Fail 'backup.sh: must create a tar.gz archive' }
$restore = Get-Content -LiteralPath (Join-Path $repo 'restore.sh') -Raw
if ($restore -notmatch 'tar\s+xz?f') { Fail 'restore.sh: must extract a tar archive' }

# ---- 6. AGENTS.md: required sections ----
$agentsPath = Join-Path $repo 'AGENTS.md'
$agents = Get-Content -LiteralPath $agentsPath -Raw
foreach ($section in @('## Ponytail', '## Graphify', '## Karpathy Guidelines', '## Code Review & Quality', '## Security Guardrails', '## MCP Tools', '## Swarm Orchestration')) {
  if ($agents -notmatch [regex]::Escape($section)) { Fail "AGENTS.md: missing required section '$section'" }
}

# ---- 7. Required repo files ----
foreach ($req in @('.github/workflows/security.yml', 'README.md', 'SECURITY.md', 'LICENSE', '.gitignore', 'connect/opencode-connect.ps1')) {
  if (-not (Test-Path -LiteralPath (Join-Path $repo $req))) { Fail "required file missing: $req" }
}

# ---- Summary ----
if ($failures.Count -gt 0) {
  Write-Host ''
  Write-Host "SECURITY GATE FAILED ($($failures.Count) problem(s)):" -ForegroundColor Red
  $failures | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host 'SECURITY GATE PASSED (jsonc, secrets, slot engine, templates, helpers, AGENTS.md).' -ForegroundColor Green
exit 0