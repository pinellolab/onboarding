# Pinello Lab · Onboarding Automation Scripts

A cross-platform toolkit that turns a blank laptop **and** a brand-new Linux
cluster account into a fully-configured development environment in minutes.

| Script | Platform | What it does |
|--------|----------|--------------|
| `scripts/local/onboarding_local_mac.sh` | **macOS 12 +** | Installs VS Code + extensions, generates SSH keys, writes SSH config, then triggers the remote bootstrapper. |
| `scripts/local/onboarding_local_windows.ps1` | **Windows 10/11** | Same as mac, **plus** optional WSL 2 install & networking tweaks. |
| `scripts/remote/onboarding_remote.sh` | **Cluster (Debian/Ubuntu)** | Adds shared software to `PATH`, sets up Mamba/Conda, personal env folder, Jupyter password, VS Code server settings, and fixes SSH permissions. |

---

## Repository layout

```text
onboarding/
├── README.md
├── LICENSE
└── scripts/
    ├── local/
    │   ├── onboarding_local_mac.sh
    │   └── onboarding_local_windows.ps1
    └── remote/
        └── onboarding_remote.sh
````

*Everything runnable lives in `scripts/`.
Local scripts call the remote script via a relative path, so you can clone
anywhere and just run.*

---

## 1 · Prerequisites

| macOS                      | Windows                                 | Remote Linux                                  |
| -------------------------- | --------------------------------------- | --------------------------------------------- |
| Bash 3.x + (pre-installed) | PowerShell 5 + (or `pwsh`)              | SSH access to **ml007.research.partners.org** |
| Git                        | Git & **\[winget]**                     | Write access to `~/.bashrc`                   |
| —                          | (Optional) admin rights for WSL install | —                                             |

> **Mac note**  You may be prompted to install Apple’s Command-Line Tools
> (Git/SSH) on first use.

---

## 2 · Clone the repo

```bash
git clone https://github.com/pinellolab/onboarding.git
cd onboarding
```

---

## 3 · Run the local script

### macOS

```bash
chmod +x scripts/local/onboarding_local_mac.sh
./scripts/local/onboarding_local_mac.sh
```

### Windows (PowerShell)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\local\onboarding_local_windows.ps1
```

During execution you can choose to:

1. Install Microsoft Teams and VS Code (plus WSL 2 on Windows).
2. Install VS Code extensions **Remote-SSH**, **Python**, **Jupyter**, **Copilot**.
3. Generate an SSH key (if missing) and copy it to the cluster.
4. Provide your **MGH username** so the script can run the remote bootstrapper.

---

## 4 · What the remote script does

`onboarding_remote.sh` runs on the first cluster host you connect to and:

* Adds `/data/pinello/SHARED_SOFTWARE/bin` to `PATH`.
* Initialises **Mamba + Conda** and creates a personal `envs` directory.
* Optionally sets a **Jupyter Lab** password (v 2.16).
* Writes fresh VS Code *Machine* settings so the Python extension
  auto-selects the shared Miniforge interpreter.
* Ensures `~/.ssh/authorized_keys` exists and has the correct permissions.

> Re-running the script is safe & idempotent – no duplicate lines or conflicts.

---

## 5 · Troubleshooting

| Symptom                                | Fix                                                                                                                                                                        |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `code` CLI not found (mac)             | Launch VS Code once and run **“Shell Command: Install ‘code’ command in PATH”**, or `export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"`. |
| `winget` not recognised (Win)          | Install the Windows Package Manager from the Microsoft Store or upgrade to Windows 10 21H2 / Windows 11.                                                                   |
| `Permission denied (publickey)` on SSH | Re-run the local script; ensure the key was generated **and** `ssh-copy-id` succeeded.                                                                                     |
| VS Code on server shows no interpreter | Connect once, then *Python → Select Interpreter* and pick the **Miniforge3** entry ending in `/bin/python`.                                                                |

---

## 6 · Updating / contributing

1. Fork or branch off **`main`**.
2. Edit scripts inside `scripts/`.
3. Run `shellcheck` on `.sh` and `Invoke-ScriptAnalyzer` on `.ps1`.
4. Open a pull request — CI will run the linters automatically.

---

## 7 · License

Distributed under the **MIT License** — see [`LICENSE`](LICENSE) for details.

Happy on-boarding 🎉
