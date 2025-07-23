#!/usr/bin/env pwsh
<#
  Windows onboarding script
  • Optional WSL install + config
  • Installs Teams and VS Code via winget
  • Seeds VS Code extensions & settings
  • Generates SSH key and populates ~/.ssh/config
  • Compatible with PowerShell 5.1 and 7+
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# PowerShell version compatibility helper function
function ConvertFrom-SecureStringCompat {
    param(
        [System.Security.SecureString]$SecureString
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # PowerShell 7+ method
        return $SecureString | ConvertFrom-SecureString -AsPlainText
    } else {
        # PowerShell 5.1 method
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }
}

# PowerShell 5.1-compatible SSH execution helper
function Invoke-SSHCommand {
    param(
        [string]$Arguments,
        [switch]$SuppressOutput
    )
    
    $sshProcess = New-Object System.Diagnostics.Process
    $sshProcess.StartInfo.FileName = "ssh"
    $sshProcess.StartInfo.Arguments = $Arguments
    $sshProcess.StartInfo.UseShellExecute = $false
    $sshProcess.StartInfo.RedirectStandardOutput = $true
    $sshProcess.StartInfo.RedirectStandardError = $true
    $sshProcess.StartInfo.CreateNoWindow = $true
    
    try {
        $sshProcess.Start() | Out-Null
        $output = $sshProcess.StandardOutput.ReadToEnd()
        $error = $sshProcess.StandardError.ReadToEnd()
        $sshProcess.WaitForExit()
        $exitCode = $sshProcess.ExitCode
        
        # Combine output and error
        if ($error) {
            $output += "`n" + $error
        }
        
        return @{
            Output = $output
            ExitCode = $exitCode
        }
    } catch {
        if (-not $SuppressOutput) {
            Write-Host "[ERROR] SSH process error: $_" -ForegroundColor Red
        }
        return @{
            Output = "Process execution failed: $_"
            ExitCode = 1
        }
    } finally {
        if ($sshProcess) {
            $sshProcess.Dispose()
        }
    }
}

Write-Host "`n[Starting] Starting local onboarding process..." -ForegroundColor Cyan
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray

# Get MGH username early since it's needed for remote operations
$mghUser = Read-Host -Prompt "Enter your MGH username for remote onboarding"
$mghUser = $mghUser.ToLower()
if ([string]::IsNullOrWhiteSpace($mghUser)) {
    Write-Host "[ERROR] Username cannot be empty." -ForegroundColor Red
    exit 1
}
Write-Host "[SUCCESS] MGH username set to: $mghUser" -ForegroundColor Green

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
        Write-Host "[OK] WSL already installed (`"$distroList`"). Skipping install."
    } else {
        Write-Host "[INSTALL] Installing WSL (this may reboot)..."
        wsl --install
    }

    # --- Ensure .wslconfig settings ---
    $wslConfigPath = "$HOME\.wslconfig"
    Write-Host "[CONFIG] Configuring $wslConfigPath..."

    if (-not (Test-Path $wslConfigPath)) { New-Item -ItemType File -Path $wslConfigPath -Force | Out-Null }

    $config = if (Test-Path $wslConfigPath) { Get-Content $wslConfigPath -Raw } else { "" }
    if ([string]::IsNullOrEmpty($config)) { $config = "" }
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
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # PowerShell 7+ method
            Set-Content -Path $wslConfigPath -Value $config -Encoding UTF8
        } else {
            # PowerShell 5.1 method
            $config | Out-File -FilePath $wslConfigPath -Encoding UTF8
        }
        Write-Host "[OK] WSL configuration updated."
    } else {
        Write-Host "[OK] WSL configuration already up-to-date."
    }
} else {
    Write-Host "Skipping WSL installation."
}

# ──────────────────────────────────────────────────────────────
# 2. Optional desktop software via winget
# ──────────────────────────────────────────────────────────────
$teamsChoice = Read-Host -Prompt "Do you want to install Microsoft Teams? (Y/n)"
if ($teamsChoice -match '^[Yy]$') {
    Write-Host "[INSTALL] Installing Microsoft Teams..."
    winget install --id Microsoft.Teams -e --silent
} else { 
    Write-Host "Skipping Teams." 
}

$vscodeChoice = Read-Host -Prompt "Do you want to install VS Code? (Y/n)"
if ($vscodeChoice -match '^[Yy]$') {
    Write-Host "[INSTALL] Installing Visual Studio Code..."
    winget install --id Microsoft.VisualStudioCode -e --silent
    Read-Host -Prompt "Press Enter after VS Code has finished installing"

    # Locate code.cmd
    $codeCmd = "$Env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    if (-not (Test-Path $codeCmd)) {
        Write-Host "[ERROR] 'code' CLI not found. Launch VS Code once and run *Shell Command: Install 'code' command in PATH*." -ForegroundColor Red
        exit 1
    }

    Write-Host "[EXTENSIONS] Installing VS Code extensions..."
    
    # Check and install extensions with idempotency
    $extensions = @(
        "ms-vscode-remote.remote-ssh",
        "ms-python.python", 
        "ms-toolsai.jupyter",
        "GitHub.copilot"
    )
    
    # Get list of installed extensions
    $installedExtensions = & $codeCmd --list-extensions 2>$null
    
    foreach ($ext in $extensions) {
        if ($installedExtensions -contains $ext) {
            Write-Host "[SKIP] Extension $ext already installed - skipping"
        } else {
            Write-Host "[INSTALL] Installing extension: $ext"
            & $codeCmd --install-extension $ext "--force"
        }
    }

    # Seed User settings
    $settingsDir  = Join-Path $Env:APPDATA "Code\User"
    $settingsFile = Join-Path $settingsDir  "settings.json"
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir | Out-Null }

    # Check if settings already exist and contain our configuration
    $settingsContent = if (Test-Path $settingsFile) { Get-Content $settingsFile -Raw } else { "" }
    if ($settingsContent -notmatch "remote\.SSH\.defaultExtensions") {
        $settingsJson = @'
{
  // Extensions that will be copied to every *remote* host
  "remote.SSH.defaultExtensions": [
    "ms-python.python",
    "ms-toolsai.jupyter"
  ]
}
'@
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # PowerShell 7+ method
            $settingsJson | Set-Content -Path $settingsFile -Encoding UTF8
        } else {
            # PowerShell 5.1 method
            $settingsJson | Out-File -FilePath $settingsFile -Encoding UTF8
        }
        Write-Host "[OK] VS Code settings written to $settingsFile"
    } else {
        Write-Host "[SKIP] VS Code settings already configured - skipping"
    }
} else {
    Write-Host "Skipping VS Code."
}

# ──────────────────────────────────────────────────────────────
# 3. Generate SSH key and copy to ml007 (using password authentication)
# ──────────────────────────────────────────────────────────────
$keyPath = "$HOME\.ssh\id_rsa"
if (-not (Test-Path $HOME\.ssh)) { New-Item -ItemType Directory -Path $HOME\.ssh | Out-Null }

if (Test-Path $keyPath) {
    Write-Host "[KEY] Existing SSH key found - reusing."
} else {
    Write-Host "[KEY] Generating a new 4096-bit RSA key..."
    ssh-keygen -t rsa -b 4096 -f $keyPath -N ""
}

Write-Host "[COPY] Copying public key to ml007..."
$typePubKey = Get-Content "$keyPath.pub"

# Use standard SSH to copy the public key with password authentication
try {
    # First test SSH connectivity
    Write-Host "   Testing SSH connection to ml007..." -ForegroundColor Gray
    Write-Host "   (You may be prompted for your password)" -ForegroundColor Yellow
    
    $sshResult = Invoke-SSHCommand -Arguments "-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o LogLevel=ERROR `"$($mghUser)@ml007.research.partners.org`" `"echo 'connected'`""

    if ($sshResult.ExitCode -ne 0) {
        $errorMessage = $sshResult.Output
        if ($errorMessage -like "*Could not resolve hostname*") {
            Write-Host "[ERROR] Cannot resolve hostname 'ml007.research.partners.org'" -ForegroundColor Red
            Write-Host "[TIP] Please check your network connection and DNS settings." -ForegroundColor Yellow
            Write-Host "      You may need to be connected to the organization VPN." -ForegroundColor Yellow
        }
        elseif ($errorMessage -like "*Connection refused*" -or $errorMessage -like "*Connection timed out*") {
            Write-Host "[ERROR] Cannot connect to ml007.research.partners.org" -ForegroundColor Red
            Write-Host "[TIP] The server may be down or SSH access may be restricted." -ForegroundColor Yellow
        }
        elseif ($errorMessage -like "*Permission denied*" -or $errorMessage -like "*Authentication failed*") {
            Write-Host "[ERROR] Authentication failed for user '$mghUser'" -ForegroundColor Red
            Write-Host "[TIP] Please check your username and ensure you have SSH access." -ForegroundColor Yellow
        }
        else {
            Write-Host "[ERROR] SSH connection failed: $errorMessage" -ForegroundColor Red
        }
        
        Write-Host "[MANUAL] Manual key installation required:" -ForegroundColor Yellow
        Write-Host "         1. Copy this public key: $typePubKey" -ForegroundColor Gray
        Write-Host "         2. Add it to ~/.ssh/authorized_keys on the remote server" -ForegroundColor Gray
        Write-Host "[ERROR] Cannot proceed without SSH key setup." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    
    Write-Host "   SSH connection successful, preparing remote SSH directory..." -ForegroundColor Gray
    
    # Ensure proper SSH directory structure exists on remote server
    $sshSetupCommand = "mkdir -p `$HOME/.ssh && [ -f `$HOME/.ssh/authorized_keys ] && mv `$HOME/.ssh/authorized_keys `$HOME/.ssh/authorized_keys.old || true && touch `$HOME/.ssh/authorized_keys && [ -f `$HOME/.ssh/authorized_keys.old ] && cat `$HOME/.ssh/authorized_keys.old >> `$HOME/.ssh/authorized_keys || true && chmod 700 `$HOME/.ssh && chmod 600 `$HOME/.ssh/authorized_keys"
    
    $setupResult = Invoke-SSHCommand -Arguments "-o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o LogLevel=ERROR `"$($mghUser)@ml007.research.partners.org`" `"$sshSetupCommand`"" -SuppressOutput
    
    if ($setupResult.ExitCode -ne 0) {
        Write-Host "[WARNING] Failed to setup SSH directory structure" -ForegroundColor Yellow
        Write-Host "          Continuing anyway - this may be a permissions issue that resolves itself" -ForegroundColor Gray
    } else {
        Write-Host "   Remote SSH directory structure confirmed" -ForegroundColor Gray
    }
    
    # Check if key already exists in authorized_keys before adding
    # Use fgrep (fixed string search) instead of grep to handle special characters in SSH keys
    $keyCheckResult = Invoke-SSHCommand -Arguments "-o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o LogLevel=ERROR `"$($mghUser)@ml007.research.partners.org`" `"fgrep -q '$typePubKey' ~/.ssh/authorized_keys 2>/dev/null && echo 'exists' || echo 'missing'`"" -SuppressOutput
    $keyCheck = $keyCheckResult.Output.Trim()
    
    # Default to missing if check fails
    if ($keyCheckResult.ExitCode -ne 0) {
        $keyCheck = "missing"
    }
    
    if ($keyCheck -eq "exists") {
        Write-Host "[SKIP] Public key already exists in ml007 authorized_keys."
    } else {
        # Use a safer method to add the key that prevents duplicates
        # This command adds the key only if it doesn't already exist (double-check protection)
        $sshCommand = "grep -Fxq '$typePubKey' ~/.ssh/authorized_keys 2>/dev/null || echo '$typePubKey' >> ~/.ssh/authorized_keys"
        
        $keyInstallResult = Invoke-SSHCommand -Arguments "-o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o LogLevel=ERROR `"$($mghUser)@ml007.research.partners.org`" `"$sshCommand`""
        
        if ($keyInstallResult.ExitCode -eq 0) {
            Write-Host "[SUCCESS] Public key successfully copied to ml007."
        } else {
            Write-Host "[ERROR] Failed to copy public key" -ForegroundColor Red
            Write-Host "[MANUAL] Manual installation: Add this key to ~/.ssh/authorized_keys on ml007:" -ForegroundColor Yellow
            Write-Host "         $typePubKey" -ForegroundColor Gray
            Write-Host "[ERROR] Cannot proceed without SSH key setup." -ForegroundColor Red
            Stop-Transcript
            exit 1
        }
    }
} catch {
    Write-Host "[ERROR] Unexpected error during public key setup: $_" -ForegroundColor Red
    Write-Host "[MANUAL] Manual installation: Add this key to ~/.ssh/authorized_keys on ml007:" -ForegroundColor Yellow
    Write-Host "         $typePubKey" -ForegroundColor Gray
    Write-Host "[ERROR] Cannot proceed without SSH key setup." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# ──────────────────────────────────────────────────────────────
# 4. Run remote onboarding script on ml007 (using SSH key)
# ──────────────────────────────────────────────────────────────
try {
    $jupyterChoice = Read-Host -Prompt "Will you be using Jupyter Lab? (Y/n)"
    $jupyterPassword = ""
    if ($jupyterChoice -match '^[Yy]$') {
        $securePassword = Read-Host -Prompt "Enter a password for Jupyter Lab" -AsSecureString
        $jupyterPassword = ConvertFrom-SecureStringCompat -SecureString $securePassword
        if ([string]::IsNullOrWhiteSpace($jupyterPassword)) {
            Write-Host "[ERROR] Jupyter password cannot be empty if Jupyter Lab is selected." | Tee-Object -FilePath $LOGFILE -Append
            Stop-Transcript
            exit 1
        }
    }

    $vscodeChoice = Read-Host -Prompt "Will you be using Visual Studio Code? (Y/n)"
    Write-Host "Executing remote onboarding on ml007..."
    
    # Test SSH connectivity first (now using SSH key)
    Write-Host "   Testing SSH connection with key-based authentication..." -ForegroundColor Gray
    
    $keyTestResult = Invoke-SSHCommand -Arguments "-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR `"$($mghUser)@ml007.research.partners.org`" `"echo 'connected'`""
    
    if ($keyTestResult.ExitCode -ne 0) {
        $errorMessage = $keyTestResult.Output
        if ($errorMessage -like "*Could not resolve hostname*") {
            Write-Host "[ERROR] Cannot resolve hostname 'ml007.research.partners.org'" -ForegroundColor Red
            Write-Host "[TIP] Please check your network connection and DNS settings." -ForegroundColor Yellow
            Write-Host "      You may need to be connected to the organization VPN." -ForegroundColor Yellow
        }
        elseif ($errorMessage -like "*Connection refused*" -or $errorMessage -like "*Connection timed out*") {
            Write-Host "[ERROR] Cannot connect to ml007.research.partners.org" -ForegroundColor Red
            Write-Host "[TIP] The server may be down or SSH access may be restricted." -ForegroundColor Yellow
        }
        elseif ($errorMessage -like "*Permission denied*" -or $errorMessage -like "*Authentication failed*") {
            Write-Host "[ERROR] Authentication failed for user '$mghUser'" -ForegroundColor Red
            Write-Host "[TIP] Please check your username and ensure you have SSH access." -ForegroundColor Yellow
        }
        else {
            Write-Host "[ERROR] SSH connection failed: $errorMessage" -ForegroundColor Red
        }
        throw "SSH connection to ml007 failed"
    }
    
    Write-Host "   SSH connection successful, executing remote script..." -ForegroundColor Gray
    
    # Read the remote script content
    $scriptContent = Get-Content -Path $RemoteScript -Raw
    
    # Execute remote script by piping content directly via SSH
    if ($jupyterChoice -match '^[Yy]$') {
        $envVars = "JUPYTER_CHOICE='$jupyterChoice' JUPYTER_PASSWORD='$jupyterPassword' VSCODE_CHOICE='$vscodeChoice'"
        $sshArgs = "-o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR `"$($mghUser)@ml007.research.partners.org`" `"$envVars bash -s`""
    } else {
        $envVars = "JUPYTER_CHOICE='$jupyterChoice' VSCODE_CHOICE='$vscodeChoice'"
        $sshArgs = "-o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR `"$($mghUser)@ml007.research.partners.org`" `"$envVars bash -s`""
    }
    
    # Create process to pipe script content to SSH
    $sshProcess = New-Object System.Diagnostics.Process
    $sshProcess.StartInfo.FileName = "ssh"
    $sshProcess.StartInfo.Arguments = $sshArgs
    $sshProcess.StartInfo.UseShellExecute = $false
    $sshProcess.StartInfo.RedirectStandardInput = $true
    $sshProcess.StartInfo.RedirectStandardOutput = $true
    $sshProcess.StartInfo.RedirectStandardError = $true
    $sshProcess.StartInfo.CreateNoWindow = $true
    
    try {
        $sshProcess.Start() | Out-Null
        
        # Write script content to SSH stdin
        $sshProcess.StandardInput.Write($scriptContent)
        $sshProcess.StandardInput.Close()
        
        # Read output
        $output = $sshProcess.StandardOutput.ReadToEnd()
        $error = $sshProcess.StandardError.ReadToEnd()
        $sshProcess.WaitForExit()
        $exitCode = $sshProcess.ExitCode
        
        # Combine output and error
        if ($error) {
            $output += "`n" + $error
        }
        
        # Display and log output
        if ($output) {
            Write-Host $output
            $output | Out-File -FilePath "./onboarding_remote.log" -Encoding UTF8
        }
        
        if ($exitCode -ne 0) {
            Write-Host "[ERROR] Remote script execution failed with exit code: $exitCode" -ForegroundColor Red
            throw "Remote script execution failed"
        }
    } catch {
        Write-Host "[ERROR] SSH execution error: $_" -ForegroundColor Red
        throw "SSH execution failed: $_"
    } finally {
        if ($sshProcess) {
            $sshProcess.Dispose()
        }
    }
} catch {
    Write-Host "[ERROR] Error: $_" | Tee-Object -FilePath $LOGFILE -Append
    Stop-Transcript
    exit 1
}

Stop-Transcript

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
    $configContent = if (Test-Path $sshConfig) { Get-Content $sshConfig -Raw } else { "" }
    
    # Check for the specific host entry, not just any HostName with that FQDN
    if ($configContent -notmatch "Host $HostName\s*\n\s*HostName $FQDN") {
        Add-Content $sshConfig "`nHost $HostName`n    HostName $FQDN`n    User $User"
        Write-Host "[ADD] Added $HostName to SSH config."
    } else {
        Write-Host "[SKIP] Host $HostName already in SSH config - skipping."
    }
}

Add-HostConfig -HostName 'ml003' -FQDN 'ml003.research.partners.org' -User $mghUser
Add-HostConfig -HostName 'ml007' -FQDN 'ml007.research.partners.org' -User $mghUser
Add-HostConfig -HostName 'ml008' -FQDN 'ml008.research.partners.org' -User $mghUser

Write-Host "`n[COMPLETE] Local onboarding complete!" -ForegroundColor Green
