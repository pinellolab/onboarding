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
    Write-Host "Executing remote onboarding on ml007..."
    
    # Create a temporary file with proper Unix line endings
    $tempFile = [System.IO.Path]::GetTempFileName()
    
    try {
        # Read the script and clean it
        $scriptBytes = [System.IO.File]::ReadAllBytes($RemoteScript)
        $scriptText = [System.Text.Encoding]::UTF8.GetString($scriptBytes)
        
        # Remove ALL carriage returns and normalize to Unix line endings
        $scriptText = $scriptText -replace "`r`n", "`n" -replace "`r", "`n"
        $scriptText = $scriptText -replace [char]13, ""  # Remove any remaining carriage returns (ASCII 13)
        
        # Ensure the script ends with a single newline
        $scriptText = $scriptText.TrimEnd() + "`n"
        
        # Write to temp file with UTF8 encoding and Unix line endings
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempFile, $scriptText, $utf8NoBom)
        
        if ($jupyterChoice -match '^[Yy]$') {
            $plainPassword = if ($jupyterPassword) { $jupyterPassword | ConvertTo-SecureString | ConvertFrom-SecureString -AsPlainText -Force } else { "" }
            $envVars = "JUPYTER_CHOICE='$jupyterChoice' JUPYTER_PASSWORD='$plainPassword' VSCODE_CHOICE='$vscodeChoice'"
            # Use cat on Windows (or Get-Content with specific encoding) to pipe the file
            & cmd /c "type `"$tempFile`"" | ssh "$($mghUser)@ml007.research.partners.org" "$envVars bash -s" | Tee-Object -FilePath ./onboarding_remote.log
        } else {
            $envVars = "JUPYTER_CHOICE='$jupyterChoice' VSCODE_CHOICE='$vscodeChoice'"
            & cmd /c "type `"$tempFile`"" | ssh "$($mghUser)@ml007.research.partners.org" "$envVars bash -s" | Tee-Object -FilePath ./onboarding_remote.log
        }
    } finally {
        # Clean up temp file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
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
$typePubKey = Get-Content "$keyPath.pub"

# Use standard SSH to copy the public key instead of PowerShell remoting
try {
    # Check if key already exists in authorized_keys before adding
    $keyCheck = ssh "$($mghUser)@ml007.research.partners.org" "grep -q '$typePubKey' ~/.ssh/authorized_keys 2>/dev/null && echo 'exists' || echo 'missing'"
    
    if ($keyCheck -eq "exists") {
        Write-Host "✅  Public key already exists in ml007 authorized_keys."
    } else {
        # Create the .ssh directory and append the public key to authorized_keys
        $sshCommand = "mkdir -p ~/.ssh && echo '$typePubKey' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
        ssh "$($mghUser)@ml007.research.partners.org" $sshCommand
        Write-Host "✅  Public key successfully copied to ml007."
    }
} catch {
    Write-Host "❌  Failed to copy public key: $_" -ForegroundColor Red
    Write-Host "💡  You may need to manually copy your public key to the remote server." -ForegroundColor Yellow
    Write-Host "    Public key content: $typePubKey" -ForegroundColor Gray
}

# ──────────────────────────────────────────────────────────────
# 5. Populate ~/.ssh/config
# ──────────────────────────────────────────────────────────────
$sshConfigPath = "$HOME\.ssh\config"
if (-not (Test-Path $sshConfigPath)) { New-Item -ItemType File -Path $sshConfigPath | Out-Null }

function Add-HostConfig {
    param(
        [string]$HostName, [string]$FQDN, [string]$User
    )
    $sshConfig = "$HOME/.ssh/config"
    if (-not (Test-Path $sshConfig)) { New-Item -ItemType File -Path $sshConfig | Out-Null }
    $configContent = Get-Content $sshConfig -Raw
    
    # Check for the specific host entry, not just any HostName with that FQDN
    if ($configContent -notmatch "Host $HostName\s*\n\s*HostName $FQDN") {
        Add-Content $sshConfig "`nHost $HostName`n    HostName $FQDN`n    User $User"
        Write-Host "➕  Added $HostName to SSH config."
    } else {
        Write-Host "ℹ️  Host $HostName already in SSH config – skipping."
    }
}

Add-HostConfig -HostName 'ml003' -Fqdn 'ml003.research.partners.org' -User $mghUser
Add-HostConfig -HostName 'ml007' -Fqdn 'ml007.research.partners.org' -User $mghUser
Add-HostConfig -HostName 'ml008' -Fqdn 'ml008.research.partners.org' -User $mghUser

Write-Host "`n✅  Local onboarding complete!" -ForegroundColor Green
