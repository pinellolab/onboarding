#!/usr/bin/env bash
echo "🚀  Starting local onboarding process…"
REMOTE_SCRIPT="$(cd -- "$(dirname "$0")/../remote" && pwd)/onboarding_remote.sh"
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
  echo "Installing VS Code extensions (Remote-SSH, Python, Jupyter, Copilot)…"
  export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
  if ! command -v code >/dev/null; then
    echo "❌  The VS Code CLI (‘code’) isn’t on PATH. Run “Shell Command: Install ‘code’ command in PATH” from VS Code first." >&2
    exit 1
  fi

  code --install-extension ms-vscode-remote.remote-ssh   --force
  code --install-extension ms-python.python              --force
  code --install-extension ms-toolsai.jupyter            --force
  code --install-extension GitHub.copilot                --force

  # ── 1-b. Seed User settings with remote default extensions
  SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
  mkdir -p "$SETTINGS_DIR"
  cat >"$SETTINGS_DIR/settings.json" <<'EOF'
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
  echo "Skipping VS Code."
fi

# ────────────────────────────────────────────────────────────────
# 2. Trigger remote onboarding script
# ────────────────────────────────────────────────────────────────
read -r -p "Enter your MGH username to start remote onboarding: " mgh_user
echo "📡  Running remote onboarding on ml007…"
ssh "$mgh_user"@ml007.research.partners.org "bash -s" < "$REMOTE_SCRIPT"
# ────────────────────────────────────────────────────────────────
# 3. Generate or reuse local SSH key
# ────────────────────────────────────────────────────────────────
key_path="$HOME/.ssh/id_rsa"
if [ -f "$key_path" ]; then
  echo "🔑  Existing SSH key found at $key_path – reusing."
else
  echo "🔑  Generating a new 4096-bit RSA key…"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t rsa -b 4096 -f "$key_path" -N ""
fi

echo "🔐  Copying public key to ml007…"
ssh-copy-id "$mgh_user"@ml007.research.partners.org

# ────────────────────────────────────────────────────────────────
# 4. Populate ~/.ssh/config for lab machines
# ────────────────────────────────────────────────────────────────
ssh_config="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh"
touch "$ssh_config"
chmod 600 "$ssh_config"

add_host () {
  local host=$1 fqdn=$2 user=$3
  if ! grep -Fq "Host $host" "$ssh_config"; then
    printf "\nHost %s\n\tHostName %s\n\tUser %s\n\tIdentityFile %s\n" \
           "$host" "$fqdn" "$user" "$key_path" >>"$ssh_config"
    echo "➕  Added $host to SSH config."
  else
    echo "ℹ️  $host already in SSH config – skipping."
  fi
}

add_host ml003 ml003.research.partners.org "$mgh_user"
add_host ml007 ml007.research.partners.org "$mgh_user"
add_host ml008 ml008.research.partners.org "$mgh_user"

echo "✅  Onboarding complete!"