#!/usr/bin/env bash
set -euo pipefail

echo "🚀  Starting local onboarding process…"
REMOTE_SCRIPT="$(cd -- "$(dirname "$0")/../remote" && pwd)/onboarding_remote.sh"
LOGFILE="$PWD/onboarding_local.log"
exec > >(tee -a "$LOGFILE") 2> >(tee -a "$LOGFILE" >&2)
trap 'echo "❌ Error on line $LINENO. See $LOGFILE for details." | tee -a "$LOGFILE"' ERR

# Get MGH username first - required for remote operations
read -r -p "Enter your MGH username: " mgh_user
mgh_user="${mgh_user,,}"
if [[ -z "$mgh_user" ]]; then
  echo "❌ Username cannot be empty." | tee -a "$LOGFILE"
  exit 1
fi
echo "✅ Using MGH username: $mgh_user"

# ────────────────────────────────────────────────────────────────
# 1. Optional software downloads
# ────────────────────────────────────────────────────────────────
read -r -p "Do you want to download Microsoft Teams? (Y/n): " teams_choice
if [[ "$teams_choice" =~ ^[Yy]$ ]]; then
  echo "Opening Microsoft Teams download page…"
  open "https://www.microsoft.com/en-us/microsoft-teams/download-app"
else
  echo "Skipping Microsoft Teams."
fi

read -r -p "Do you want to download VS Code? (Y/n): " vscode_choice
if [[ "$vscode_choice" =~ ^[Yy]$ ]]; then
  echo "Opening VS Code download page…"
  open "https://code.visualstudio.com/Download"
  read -r -p $'Press Enter after you have installed Visual Studio Code.\n'

  # ── 1-a. Install desktop-side extensions
  echo "🔧 Installing VS Code extensions (Remote-SSH, Python, Jupyter, Copilot)…"
  export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
  if ! command -v code >/dev/null; then
    echo "❌  The VS Code CLI ('code') isn't on PATH. Run "Shell Command: Install 'code' command in PATH" from VS Code first." >&2
    exit 1
  fi

  # Install extensions with idempotency check
  extensions=("ms-vscode-remote.remote-ssh" "ms-python.python" "ms-toolsai.jupyter" "GitHub.copilot")
  for ext in "${extensions[@]}"; do
    if code --list-extensions | grep -q "^$ext$"; then
      echo "✅ Extension $ext already installed - skipping"
    else
      echo "📦 Installing extension: $ext"
      code --install-extension "$ext" --force
    fi
  done

  # ── 1-b. Seed User settings with remote default extensions
  SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
  mkdir -p "$SETTINGS_DIR"
  
  # Only write settings if they don't exist or don't contain our config
  SETTINGS_FILE="$SETTINGS_DIR/settings.json"
  if [[ ! -f "$SETTINGS_FILE" ]] || ! grep -q "remote.SSH.defaultExtensions" "$SETTINGS_FILE"; then
    cat >"$SETTINGS_FILE" <<'EOF'
{
  // Push these two server-side extensions to every new SSH host
  "remote.SSH.defaultExtensions": [
    "ms-python.python",
    "ms-toolsai.jupyter"
  ]
}
EOF
    echo "✔  VS Code settings written to $SETTINGS_DIR/settings.json"
  else
    echo "✅ VS Code settings already configured - skipping"
  fi
else
  echo "Skipping VS Code."
fi

# ────────────────────────────────────────────────────────────────
# 2. Generate SSH key and copy to ml007 (using password authentication)
# ────────────────────────────────────────────────────────────────
key_path="$HOME/.ssh/id_rsa"
if [ -f "$key_path" ]; then
  echo "🔑  Existing SSH key found at $key_path – reusing."
else
  echo "🔑  Generating a new 4096-bit RSA key…"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if ! ssh-keygen -t rsa -b 4096 -f "$key_path" -N ""; then
    echo "❌ Failed to generate SSH key"
    exit 1
  fi
  echo "✅ SSH key generated successfully"
fi

echo "🔐  Copying public key to ml007 (you may be prompted for your password)…"

# First ensure proper SSH directory structure on remote server
echo "   Setting up remote SSH directory structure..."
if ssh -o StrictHostKeyChecking=no "$mgh_user"@ml007.research.partners.org \
  "mkdir -p \$HOME/.ssh && [ -f \$HOME/.ssh/authorized_keys ] && mv \$HOME/.ssh/authorized_keys \$HOME/.ssh/authorized_keys.old || true && touch \$HOME/.ssh/authorized_keys && [ -f \$HOME/.ssh/authorized_keys.old ] && cat \$HOME/.ssh/authorized_keys.old >> \$HOME/.ssh/authorized_keys || true && chmod 700 \$HOME/.ssh && chmod 600 \$HOME/.ssh/authorized_keys" 2>/dev/null; then
  echo "✅ Remote SSH directory structure confirmed"
else
  echo "⚠️  Warning: Could not setup SSH directory structure - continuing anyway"
fi

# Now copy the SSH key
if ! ssh-copy-id -o StrictHostKeyChecking=no "$mgh_user"@ml007.research.partners.org; then
  echo "❌ Failed to copy SSH key to ml007. Please check connectivity and credentials."
  echo "   Manual installation required:"
  echo "   1. Copy this public key: $(cat "$key_path.pub")"
  echo "   2. Add it to ~/.ssh/authorized_keys on ml007"
  exit 1
fi
echo "✅ SSH key copied successfully - future connections will be passwordless"

# ────────────────────────────────────────────────────────────────
# 3. Run remote onboarding script on ml007 (using SSH key)
# ────────────────────────────────────────────────────────────────
read -r -p "Will you be using Jupyter Lab? (Y/n): " jupyter_choice
jupyter_password=""
if [[ "$jupyter_choice" =~ ^[Yy]$ ]]; then
  read -s -p "Enter a password for Jupyter Lab: " jupyter_password
  echo
  if [[ -z "$jupyter_password" ]]; then
    echo "❌ Jupyter password cannot be empty if Jupyter Lab is selected." | tee -a "$LOGFILE"
    exit 1
  fi
fi
read -r -p "Will you be using Visual Studio Code? (Y/n): " vscode_choice

# Test SSH connectivity with key-based authentication
echo "🔍 Testing SSH connectivity with key-based authentication..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "$mgh_user"@ml007.research.partners.org exit 2>/dev/null; then
  echo "❌ Cannot connect to ml007.research.partners.org with SSH key"
  echo "   SSH key authentication may have failed. Check the key setup above."
  exit 1
fi
echo "✅ SSH key-based connectivity confirmed"

echo "📡  Running remote onboarding on ml007 (passwordless)…"
if [[ "$jupyter_choice" =~ ^[Yy]$ ]]; then
  # Pass password via environment variable and suppress warnings
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$mgh_user"@ml007.research.partners.org \
    "JUPYTER_CHOICE='$jupyter_choice' JUPYTER_PASSWORD='$jupyter_password' VSCODE_CHOICE='$vscode_choice' bash -s" < "$REMOTE_SCRIPT" 2>/dev/null | tee ./onboarding_remote.log; then
    echo "❌ Remote onboarding failed. Check onboarding_remote.log for details."
    exit 1
  fi
else
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$mgh_user"@ml007.research.partners.org \
    "JUPYTER_CHOICE='$jupyter_choice' VSCODE_CHOICE='$vscode_choice' bash -s" < "$REMOTE_SCRIPT" | tee ./onboarding_remote.log; then
    echo "❌ Remote onboarding failed. Check onboarding_remote.log for details."
    exit 1
  fi
fi

# ────────────────────────────────────────────────────────────────
# 4. Populate ~/.ssh/config for lab machines
# ────────────────────────────────────────────────────────────────
ssh_config="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh"
touch "$ssh_config"
chmod 600 "$ssh_config"

add_host () {
  local host=$1 fqdn=$2 user=$3
  if ! grep -Fq "HostName $fqdn" "$ssh_config"; then
    printf "\nHost %s\n\tHostName %s\n\tUser %s\n" \
          "$host" "$fqdn" "$user" >>"$ssh_config"
    echo "➕  Added $host to SSH config."
  else
    echo "✅  HostName $fqdn already in SSH config – skipping."
  fi
}

echo "🔧 Configuring SSH hosts..."
add_host ml003 ml003.research.partners.org "$mgh_user"
add_host ml007 ml007.research.partners.org "$mgh_user"
add_host ml008 ml008.research.partners.org "$mgh_user"

echo "✅  Onboarding complete!"
