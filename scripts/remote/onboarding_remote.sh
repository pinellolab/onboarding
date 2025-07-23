#!/usr/bin/env bash
# -------------------------------------------------------------
#  Remote Linux onboarding script (fresh VS Code settings path)
# -------------------------------------------------------------
set -euo pipefail

shared_software_bin="/data/pinello/SHARED_SOFTWARE/bin"
miniforge_path="/data/pinello/SHARED_SOFTWARE/miniforge3"
user_folder="/data/pinello/SHARED_SOFTWARE/envs/${USER}_envs"
vscode_settings="$HOME/.vscode-server/data/Machine/settings.json"

# Check for required commands
command -v "$miniforge_path/bin/mamba" >/dev/null 2>&1 || { echo "ERROR: mamba not found at $miniforge_path/bin/mamba. Aborting."; exit 1; }
command -v "$miniforge_path/bin/jupyter" >/dev/null 2>&1 || { echo "ERROR: jupyter not found in $miniforge_path/bin/. Aborting."; exit 1; }

trap 'echo "ERROR: Error on line $LINENO."' ERR

echo "Starting remote onboarding process..."

# -- 1. ~/.bashrc additions -----------------------------------
if ! grep -Fq "$shared_software_bin" ~/.bashrc; then
    echo "export PATH=\"\$PATH:$shared_software_bin\"" >> ~/.bashrc
    echo "* Added SHARED_SOFTWARE bin to PATH"
fi

grep -Fq "umask g+w"              ~/.bashrc || echo "umask g+w" >> ~/.bashrc
grep -Fq "PIP_REQUIRE_VIRTUALENV" ~/.bashrc || echo "export PIP_REQUIRE_VIRTUALENV=true" >> ~/.bashrc

# mamba / conda init only once
if ! grep -Fq "mamba shell init" ~/.bashrc; then
    "$miniforge_path/bin/mamba" shell init --shell bash --root-prefix "$miniforge_path"
fi
if ! grep -Fq "conda initialize" ~/.bashrc; then
    "$miniforge_path/bin/conda" init bash
fi

# -- 2. personal envs folder ----------------------------------
mkdir -p "$user_folder"
"$miniforge_path/bin/mamba" config list envs_dirs | grep -Fq "$user_folder" ||
    "$miniforge_path/bin/mamba" config prepend envs_dirs "$user_folder"

# -- 3. optional Jupyter Lab password -------------------------
if [ -n "${JUPYTER_CHOICE:-}" ]; then
    jupyter_choice="$JUPYTER_CHOICE"
else
    read -r -p "Will you be using Jupyter Lab? (Y/n): " jupyter_choice
fi
if [[ "$jupyter_choice" =~ ^[Yy]$ ]]; then
    cfg="$HOME/.jupyter/jupyter_server_config.json"
    mkdir -p "$(dirname "$cfg")"
    if ! grep -q '"IdentityProvider":' "$cfg" 2>/dev/null; then
        if [ -n "${JUPYTER_CHOICE:-}" ] && [[ "$jupyter_choice" =~ ^[Yy]$ ]]; then
            echo "Setting Jupyter password (non-interactive)..."
            # Read password from stdin (first line)
            read -r jupyter_password
            source "$miniforge_path/bin/activate" base
            "$miniforge_path/bin/jupyter" lab password <<EOF
$jupyter_password
$jupyter_password
EOF
        else
            echo "* Jupyter password not set (no password provided)."
        fi
    else
        echo "* Jupyter password already set."
    fi
fi

# -- 4. optional VS Code Machine settings ---------------------
if [ -n "${VSCODE_CHOICE:-}" ]; then
    vscode_choice="$VSCODE_CHOICE"
else
    read -r -p "Will you be using Visual Studio Code? (Y/n): " vscode_choice
fi
if [[ "$vscode_choice" =~ ^[Yy]$ ]]; then
    mkdir -p "$(dirname "$vscode_settings")"
cat >"$vscode_settings" <<EOF
{
  "python.defaultInterpreterPath": "$miniforge_path/bin/python",
  "python.condaPath": "$miniforge_path/bin/conda"
}
EOF
    echo "* Wrote fresh VS Code Machine settings to $vscode_settings"
fi

echo "Remote onboarding complete!"
