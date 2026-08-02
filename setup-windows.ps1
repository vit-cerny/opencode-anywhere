# setup-windows.ps1 - one-stop Windows walkthrough for opencode-anywhere
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File setup-windows.ps1
#
# Automates everything it can (SSH key, IP lock-in, remote install, verify);
# stops and waits at the two parts that only you can click (Oracle console,
# DuckDNS). Total hands-on time ~10 min.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Step($n, $text) { Write-Host "`n=== [$n] $text ===" -ForegroundColor Cyan }

$domain = $null
$ip     = $null

# ---------------------------------------------------------------- key pair
Step 1 "SSH key pair (this PC)"
if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
  Write-Host '  OpenSSH client: OK'
} else {
  Write-Host '  Installing OpenSSH client...' -ForegroundColor Yellow
  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
}

if (Test-Path "$env:USERPROFILE\.ssh\id_ed25519.pub") {
  Write-Host "  Key exists (reusing it)."
} else {
  ssh-keygen -t ed25519 -N '""' -f "$env:USERPROFILE\.ssh\id_ed25519" -C "opencode-vm" | Out-Null
  Write-Host '  New ed25519 key generated (no passphrase).'
}
$pub = (Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" -Raw).Trim()
Write-Host ''
Write-Host '  Your PUBLIC key (one line) - select + copy it:' -ForegroundColor Green
Write-Host $pub
Write-Host ''
Write-Host '  <= paste into Oracle later (step 3). Press Enter when copied.'
Read-Host

# ------------------------------------------------------------- oracle steps
Step 2 'Oracle signup (browser, ~5 min - do these 3 things)'
Write-Host @'
  1. Browser -> https://signup.cloud.oracle.com -> "Start for free"
     account + card (verification only, free tier never billed).
  2. After login: set Home Region (top-right, permanent choice).
  3. Menu (≡) -> Compute -> Instances -> Create instance:
       Name:         opencode
       Image:        Ubuntu 24.04
       Shape:        Arm  ->  VM.Standard.A1.Flex  (OCPU 2, RAM 12 GB)
                     (if "Out of host capacity": wait/retry, or free AMD
                      VM.Standard.E2.1.Micro)
       SSH keys:     Paste public keys  ->  the key from step 1
       Create. Wait for green "Running".
'@
Write-Host '  Enter the Public IP shown on the instance page:' -ForegroundColor Cyan
$ip = Read-Host
while (-not ($ip -match '^\d{1,3}(\.\d{1,3}){3}$')) { $ip = Read-Host '  Invalid IP, retype' }

# ---------------------------------------------------------- network reserve
Step 3 'Hold ports open + permanent IP (~2 min)'
Write-Host @'
  Do both in the Oracle console (always on, else site is unreachable):
  1. Menu -> Networking -> Reserved public IPs -> Create (Pool: public)
     -> row -> Assign -> your VM (keeps the same IP forever).
  2. Menu -> Networking -> Virtual Cloud Networks -> your VCN
     -> Security Lists -> default -> 3x "Add Ingress Rules":
        Source 0.0.0.0/0, TCP, ports 22 / 80 / 443
'@
Read-Host '  Enter when the rules are in (leave = continue)'

# ------------------------------------------------------------ duckdns step
Step 4 'DNS name (DuckDNS)'
Write-Host @'
  Browser -> https://www.duckdns.org -> sign in (Google/GitHub/X).
  Add your domain:         mybox  (choose your own)
  In the row -> Edit -> A record -> Enter your IP -> Save.
'@
$sub = Read-Host '  Your DuckDNS subdomain (e.g. mybox)'
while ($sub -notmatch '^[a-z0-9-]+$') { $sub = Read-Host '  Alphanumerics only, retype' }
$domain = "$sub.duckdns.org"

# -------------------------------------------------------- reachability
Step 5 'Waiting for the VM to accept SSH (first connect = trust prompt)'
ssh -o StrictHostKeyChecking=accept-new "ubuntu@$ip" 'uptime'   # first connect registers host key

Step 6 'Installing everything on the VM (one line, remote)'
Write-Host "  => curl one-liner installer on ubuntu@$ip  (you'll answer 3 prompts:"
Write-Host '     domain, owner password hidden, settings repo [Enter])'
ssh "ubuntu@$ip" "curl -fsSL https://raw.githubusercontent.com/vit-cerny/opencode-anywhere/main/setup.sh | sudo bash"

# ------------------------------------------------------- verify
Step 7 'Verify the site is live'
Start-Sleep -Seconds 6
$url = "https://me.$domain"
$code = curl.exe -sk -o NUL -w "%{http_code}" $url
if ("$code" -match '^(200|30[0-9])$') {
  Write-Host "  $url -> HTTP $code  (UP!)" -ForegroundColor Green
} else {
  Write-Host "  $url -> HTTP $code (hostname may await LetsEncrypt ~30s - refresh)" -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  DONE. Your slot: https://me.<sub>.duckdns.org' -ForegroundColor Green
Write-Host '  Login as opencode with the password you set during the install.'
Write-Host '  Next: add a friend -> ssh ubuntu@ip .  ./add-slot.sh alice'