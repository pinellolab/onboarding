#!/usr/bin/env bash
# -------------------------------------------------------------
#  Remote Linux onboarding script (fresh VS Code settings path)
# -------------------------------------------------------------
set -euo pipefail

shared_software_bin="/data/pinello/SHARED_SOFTWARE/bin"
miniforge_path="/data/pinello/SHARED_SOFTWARE/miniforge3"
user_folder="/data/pinello/SHARED_SOFTWARE/envs/${USER}_envs"
vscode_settings="$HOME/.vscode-server/data/Machine/settings.json"

echo "🚀  Starting remote onboarding process…"

# ── 1. ~/.bashrc additions ───────────────────────────────────
if ! grep -Fq "$shared_software_bin" ~/.bashrc; then
    echo "export PATH=\"\$PATH:$shared_software_bin\"" >> ~/.bashrc
    echo "• Added SHARED_SOFTWARE bin to PATH"
fi

grep -Fq "umask g+w"              ~/.bashrc || echo "umask g+w" >> ~/.bashrc
grep -Fq "PIP_REQUIRE_VIRTUALENV" ~/.bashrc || echo "export PIP_REQUIRE_VIRTUALENV=true" >> ~/.bashrc

# mamba / conda init only once
grep -Fq "mamba shell init" ~/.bashrc || "$miniforge_path/bin/mamba" shell init --shell bash --root-prefix "$miniforge_path"
grep -Fq "conda initialize" ~/.bashrc || "$miniforge_path/bin/conda" init bash

# ── 2. personal envs folder ──────────────────────────────────
mkdir -p "$user_folder"
"$miniforge_path/bin/mamba" config --show envs_dirs | grep -Fq "$user_folder" ||
    "$miniforge_path/bin/mamba" config prepend envs_dirs "$user_folder"

# ── 3. authorised_keys perms fix ─────────────────────────────
mkdir -p "$HOME/.ssh"
touch    "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
chown "$USER:$USER" "$HOME/.ssh/authorized_keys"

# ── 4. optional Jupyter Lab password ─────────────────────────
read -r -p "Will you be using Jupyter Lab? (Y/n): " jupyter_choice
if [[ "$jupyter_choice" =~ ^[Yy]$ ]]; then
    cfg="$HOME/.jupyter/jupyter_server_config.json"
    mkdir -p "$(dirname "$cfg")"
    if ! grep -q '"IdentityProvider":' "$cfg" 2>/dev/null; then
        echo "🔑  Setting Jupyter password…"; jupyter lab password
    else
        echo "• Jupyter password already set."
    fi
fi

# ── 5. optional VS Code Machine settings ─────────────────────
read -r -p "Will you be using Visual Studio Code? (Y/n): " vscode_choice
if [[ "$vscode_choice" =~ ^[Yy]$ ]]; then
    mkdir -p "$(dirname "$vscode_settings")"
cat >"$vscode_settings" <<EOF
{
  "python.defaultInterpreterPath": "$miniforge_path/bin/python",
  "python.condaPath": "$miniforge_path/bin/conda"
}
EOF
    echo "• Wrote fresh VS Code Machine settings to $vscode_settings"
fi

echo "✅  Remote onboarding complete!"
