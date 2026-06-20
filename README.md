# Git Multi-Account Manager

Interactive setup + helper commands for using **multiple GitHub accounts** on one
machine. Works in **WSL, Git Bash, and PowerShell**. Add as many accounts as you
like, anytime. Per-account SSH keys are created/reused with guidance, and the
public key is shown so you can paste it into GitHub before the connection is tested.

## Setup (run once per environment)

**WSL or Git Bash:**
```bash
bash git-setup.sh
source ~/.bashrc
githelp
```

**PowerShell:**
```powershell
powershell -ExecutionPolicy Bypass -File .\git-setup.ps1
. $PROFILE
githelp
```

The wizard will, for each account: ask a short label, your GitHub username and
email; create or reuse an SSH key; show the public key and wait while you add it
to https://github.com/settings/ssh/new; write the `~/.ssh/config` alias; test the
connection; and save the account. Loop to add more. Finally it sets a global
default identity and installs the helper commands.

> Each environment is separate (WSL / Git Bash / PowerShell each have their own
> config). Run the setup once in each environment you use.

## Commands (after setup)

| Command | What it does |
|---|---|
| `githelp` | List all commands |
| `gitaccounts` | List configured accounts |
| `gitwho` | Current repo identity + remote |
| `gituse <label>` | Switch current repo to an account |
| `gitclone <label> <url>` | Clone a repo as an account (`owner/repo` or full URL) |
| `gitnew <label> [repo]` | Init a NEW repo in the current folder as an account (adds remote if you give a repo name) |
| `gitsetup` | Re-run the wizard to add accounts or fix keys |
| `git-<label>` | Auto shortcut: switch to that account (e.g. `git-bibek`) |
| `<label>-clone <url>` | Auto shortcut: clone as that account (e.g. `bibek-clone ...`) |
| `<label>-init [repo]` | Auto shortcut: init a new repo as that account (e.g. `bibek-init my-app`) |
| `gs` `gcm "msg"` `gp` `gl` | status / commit / push / pull |

## Files it creates

| File | Purpose |
|---|---|
| `~/.git-accounts` | Your accounts (label, user, email, key path, host alias) |
| `~/.ssh/config` | Host aliases (`github.com-<label>`) |
| `~/.bashrc` / `$PROFILE` | Helper commands (in a marked block) |
| `~/.git-setup.sh` / `~/.git-setup.ps1` | Copy of the wizard, used by `gitsetup` |

## Add another account later
Just run `gitsetup` (or `gitadd-account`) in that environment and add it. The
helpers and per-account shortcuts regenerate automatically on next shell reload.

## Notes
- SSH keys are NOT shared between WSL, Git Bash, and PowerShell unless you copy
  them. To reuse Windows keys in WSL:
  `cp /mnt/c/Users/<you>/.ssh/id_ed25519_* ~/.ssh/ && chmod 600 ~/.ssh/id_ed25519_*`
- If a push fails with `Permission denied (publickey)`, run `gituse <label>` (or
  `git-<label>`) in the repo to fix the remote alias.
- Never commit private keys. Only the `.pub` files go to GitHub.
