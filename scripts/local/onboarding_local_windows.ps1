#!/usr/bin/env pwsh
<#
  Windows onboarding script
  • Optional WSL install + config
  • Installs Teams and VS Code via winget
  • Seeds VS Code extensions & settings
  • Generates SSH key and populates ~/.ssh/config
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host "`n🚀  Starting local onboarding process…" -ForegroundColor Cyan
$RemoteScript = Join-Path $PSScriptRoot "..\remote\onboarding_remote.sh"
$LOGFILE = Join-Path $PWD 'onboarding_local.log'
Start-Transcript -Path $LOGFILE -Append
# ──────────────────────────────────────────────────────────────
# 1. Install or update WSL and ensure networking settings
# ──────────────────────────────────────────────────────────────
$wslChoice = Read-Host -Prompt "Do you want to install WSL on this machine? (Y/n)"
if ($wslChoice -match '^[Yy]$') {
    $distroList = (wsl -l -q 2>$null) -join ''
    if ($distroList) {
        Write-Host "✔  WSL already installed (`"$distroList`"). Skipping install."
    } else {
        Write-Host "⏳  Installing WSL (this may reboot)…"
        wsl --install
    }

    # --- Ensure .wslconfig settings ---
    $wslConfigPath = "$HOME\.wslconfig"
    Write-Host "🔧  Configuring $wslConfigPath…"

    if (-not (Test-Path $wslConfigPath)) { New-Item -ItemType File -Path $wslConfigPath -Force | Out-Null }

    $config = Get-Content $wslConfigPath -Raw
    if ($config -notmatch '\[wsl2\]') { $config = "[wsl2]`n$config" }

    $needUpdate = $false
    $settings = @(
        'networkingMode = mirrored',
        'dnsTunneling   = true',
        'autoProxy      = true'
    )
    foreach ($line in $settings) {
        if ($config -notmatch [regex]::Escape($line.Split('=')[0])) {
            $config += "`n$line"
            $needUpdate = $true
        }
    }
    if ($needUpdate) {
        Set-Content -Path $wslConfigPath -Value $config -Encoding UTF8
        Write-Host "✔  WSL configuration updated."
    } else {
        Write-Host "✔  WSL configuration already up-to-date."
    }
} else {
    Write-Host "Skipping WSL installation."
}

# ──────────────────────────────────────────────────────────────
# 2. Optional desktop software via winget
# ──────────────────────────────────────────────────────────────
$teamsChoice = Read-Host -Prompt "Do you want to install Microsoft Teams? (Y/n)"
if ($teamsChoice -match '^[Yy]$') {
    Write-Host "⏳  Installing Microsoft Teams…"
    winget install --id Microsoft.Teams -e --silent
} else { Write-Host "Skipping Teams." }

$vscodeChoice = Read-Host -Prompt "Do you want to install VS Code? (Y/n)"
if ($vscodeChoice -match '^[Yy]$') {
    Write-Host "⏳  Installing Visual Studio Code…"
    winget install --id Microsoft.VisualStudioCode -e --silent
    Read-Host -Prompt "Press Enter after VS Code has finished installing"

    # Locate code.cmd
    $codeCmd = "$Env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    if (-not (Test-Path $codeCmd)) {
        Write-Host "❌  'code' CLI not found. Launch VS Code once and run *Shell Command: Install ''code'' command in PATH*." -ForegroundColor Red
        exit 1
    }

    Write-Host "🧩  Installing VS Code extensions…"
    & $codeCmd --install-extension ms-vscode-remote.remote-ssh  --force
    & $codeCmd --install-extension ms-python.python             --force
    & $codeCmd --install-extension ms-toolsai.jupyter           --force
    & $codeCmd --install-extension GitHub.copilot               --force

    # Seed User settings
    $settingsDir  = Join-Path $Env:APPDATA "Code\User"
    $settingsFile = Join-Path $settingsDir  "settings.json"
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir | Out-Null }

@'
{
  // Extensions that will be copied to every *remote* host
  "remote.SSH.defaultExtensions": [
    "ms-python.python",
    "ms-toolsai.jupyter"
  ]
}
'@ | Set-Content -Path $settingsFile -Encoding UTF8

    Write-Host "✔  VS Code settings written to $settingsFile"
} else {
    Write-Host "Skipping VS Code."
}

# ──────────────────────────────────────────────────────────────
# 3. Run remote onboarding script on ml007
# ──────────────────────────────────────────────────────────────
try {
    $mghUser = Read-Host -Prompt "Enter your MGH username for remote onboarding"
    $mghUser = $mghUser.ToLower()
    if ([string]::IsNullOrWhiteSpace($mghUser)) {
        Write-Host "❌ Username cannot be empty." | Tee-Object -FilePath $LOGFILE -Append
        Stop-Transcript
        exit 1
    }

    $jupyterChoice = Read-Host -Prompt "Will you be using Jupyter Lab? (Y/n)"
    $jupyterPassword = ""
    if ($jupyterChoice -match '^[Yy]$') {
        $jupyterPassword = Read-Host -Prompt "Enter a password for Jupyter Lab" -AsSecureString | ConvertFrom-SecureString
        if ([string]::IsNullOrWhiteSpace($jupyterPassword)) {
            Write-Host "❌ Jupyter password cannot be empty if Jupyter Lab is selected." | Tee-Object -FilePath $LOGFILE -Append
            Stop-Transcript
            exit 1
        }
    }

    $vscodeChoice = Read-Host -Prompt "Will you be using Visual Studio Code? (Y/n)"
    Write-Host "📡  Executing remote onboarding on ml007…"
    if ($jupyterChoice -match '^[Yy]$') {
        $plainPassword = if ($jupyterPassword) { $jupyterPassword | ConvertTo-SecureString | ConvertFrom-SecureString -AsPlainText -Force } else { "" }
        $envVars = @("JUPYTER_CHOICE='$jupyterChoice'", "JUPYTER_PASSWORD='$plainPassword'", "VSCODE_CHOICE='$vscodeChoice'") -join ' '
        ssh "$($mghUser)@ml007.research.partners.org" "$envVars bash -s" < $RemoteScript | Tee-Object -FilePath ./onboarding_remote.log
    } else {
        $envVars = @("JUPYTER_CHOICE='$jupyterChoice'", "VSCODE_CHOICE='$vscodeChoice'") -join ' '
        ssh "$($mghUser)@ml007.research.partners.org" "$envVars bash -s" < $RemoteScript | Tee-Object -FilePath ./onboarding_remote.log
    }
} catch {
    Write-Host "❌ Error: $_" | Tee-Object -FilePath $LOGFILE -Append
    Stop-Transcript
    exit 1
}
Stop-Transcript
# ──────────────────────────────────────────────────────────────
# 4. Generate (or reuse) SSH key
# ──────────────────────────────────────────────────────────────
$keyPath = "$HOME\.ssh\id_rsa"
if (-not (Test-Path $HOME\.ssh)) { New-Item -ItemType Directory -Path $HOME\.ssh | Out-Null }

if (Test-Path $keyPath) {
    Write-Host "🔑  Existing SSH key found – reusing."
} else {
    Write-Host "🔑  Generating a new 4096-bit RSA key…"
    ssh-keygen -t rsa -b 4096 -f $keyPath -N ""
}

Write-Host "🔐  Copying public key to ml007…"
ssh-copy-id "$($mghUser)@ml007.research.partners.org"

# ──────────────────────────────────────────────────────────────
# 5. Populate ~/.ssh/config
# ──────────────────────────────────────────────────────────────
$sshConfigPath = "$HOME\.ssh\config"
if (-not (Test-Path $sshConfigPath)) { New-Item -ItemType File -Path $sshConfigPath | Out-Null }

function Add-HostConfig {
    param(
        [string]$Host, [string]$FQDN, [string]$User
    )
    $sshConfig = "$HOME/.ssh/config"
    if (-not (Test-Path $sshConfig)) { New-Item -ItemType File -Path $sshConfig | Out-Null }
    $configContent = Get-Content $sshConfig -Raw
    if ($configContent -notmatch "HostName $FQDN") {
        Add-Content $sshConfig "`nHost $Host`n    HostName $FQDN`n    User $User"
        Write-Host "➕  Added $Host to SSH config."
    } else {
        Write-Host "ℹ️  HostName $FQDN already in SSH config – skipping."
    }
}

Add-HostConfig -Host 'ml003' -Fqdn 'ml003.research.partners.org' -User $mghUser
Add-HostConfig -Host 'ml007' -Fqdn 'ml007.research.partners.org' -User $mghUser
Add-HostConfig -Host 'ml008' -Fqdn 'ml008.research.partners.org' -User $mghUser

Write-Host "`n✅  Local onboarding complete!" -ForegroundColor Green
