#!/usr/bin/env bash
# =============================================================
#  git-multi-account  (Bash/Zsh: macOS, Linux, WSL, Git Bash)
#  Interactive multi-GitHub-account manager.
#
#  FIRST-TIME SETUP (run once per environment):
#    bash git-setup.sh
#
#  It will: walk you through adding accounts (unlimited), guide
#  SSH key creation/reuse per account, write ~/.ssh/config,
#  save ~/.git-accounts, install helper functions into ~/.zshrc
#  (if your login shell is zsh) or ~/.bashrc.
#
#  After setup, reload:  source ~/.zshrc   (or ~/.bashrc)
#  Then type:  githelp
# =============================================================
set -uo pipefail

ACCOUNTS_FILE="$HOME/.git-accounts"
SSH_CONFIG="$HOME/.ssh/config"
# Install helpers into the rc file of the user's login shell (zsh on macOS, bash elsewhere)
case "$(basename "${SHELL:-bash}")" in
  zsh) RCFILE="$HOME/.zshrc" ;;
  *)   RCFILE="$HOME/.bashrc" ;;
esac
RCNAME="~/$(basename "$RCFILE")"
MARK_START="# >>> git-multi-account >>>"
MARK_END="# <<< git-multi-account <<<"

c_cyan='\033[0;36m'; c_grn='\033[0;32m'; c_yel='\033[0;33m'; c_red='\033[0;31m'; c_off='\033[0m'
say(){ echo -e "${c_cyan}==>${c_off} $1"; }
ok(){  echo -e "  ${c_grn}OK${c_off} $1"; }
warn(){ echo -e "  ${c_yel}!${c_off} $1"; }
lower(){ echo "$1" | tr '[:upper:]' '[:lower:]'; }  # bash 3.2 (macOS) has no ${var,,}

mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh" 2>/dev/null

ask(){ # ask "prompt" "default" -> echoes answer
  local p="$1" d="${2:-}" a
  if [ -n "$d" ]; then read -r -p "$p [$d]: " a; echo "${a:-$d}"
  else read -r -p "$p: " a; echo "$a"; fi
}

add_one_account(){
  echo
  say "New account"
  local label user email keypath genkey
  while :; do
    label="$(ask "  Short label (letters/numbers, e.g. bibek)")"
    label="$(echo "$label" | tr -cd '[:alnum:]_-')"
    [ -n "$label" ] && break
    warn "Label can't be empty."
  done
  user="$(ask "  GitHub username (e.g. questbibek)")"
  email="$(ask "  Email for commits")"

  # SSH key: reuse or generate
  local default_key="$HOME/.ssh/id_ed25519_${label}"
  if [ -f "$default_key" ]; then
    ok "Found existing key: $default_key"
    keypath="$default_key"
  else
    echo
    warn "No key found at $default_key"
    genkey="$(ask "  Generate a new SSH key for '$label'? (y/n)" "y")"
    if [ "$(lower "$genkey")" = "y" ]; then
      ssh-keygen -t ed25519 -C "${label}-github" -f "$default_key" -N ""
      keypath="$default_key"
      ok "Key created: $default_key"
    else
      keypath="$(ask "  Path to an existing private key" "$default_key")"
    fi
  fi
  chmod 600 "$keypath" 2>/dev/null

  # Show public key and wait for the user to add it to GitHub
  if [ -f "${keypath}.pub" ]; then
    echo
    say "Add THIS public key to GitHub for '$user':"
    echo "  https://github.com/settings/ssh/new"
    echo "  ----------------------------------------------------------------"
    echo "  $(cat "${keypath}.pub")"
    echo "  ----------------------------------------------------------------"
    read -r -p "  Press Enter AFTER you've added it to GitHub..." _
  fi

  # Write SSH config host alias
  local host="github.com-${label}"
  if ! grep -q "Host ${host}\b" "$SSH_CONFIG" 2>/dev/null; then
    {
      echo ""
      echo "Host ${host}"
      echo "    HostName github.com"
      echo "    User git"
      echo "    IdentityFile ${keypath}"
      echo "    IdentitiesOnly yes"
    } >> "$SSH_CONFIG"
    ok "Added SSH alias: ${host}"
  else
    ok "SSH alias ${host} already present"
  fi
  chmod 600 "$SSH_CONFIG" 2>/dev/null

  # Test connection
  echo
  say "Testing connection (you should see: Hi ${user}!)..."
  ssh -o StrictHostKeyChecking=accept-new -T "git@${host}" 2>&1 | sed 's/^/    /'

  # Save to accounts file: label|user|email|keypath|host
  echo "${label}|${user}|${email}|${keypath}|${host}" >> "$ACCOUNTS_FILE"
  ok "Saved account '${label}'"
}

run_wizard(){
  echo
  say "Git Multi-Account Setup"
  touch "$ACCOUNTS_FILE"
  local more="y"
  while [ "$(lower "$more")" = "y" ]; do
    add_one_account
    echo
    more="$(ask "Add another account? (y/n)" "n")"
  done

  echo
  say "Set the GLOBAL default identity (used for new repos)"
  if [ -s "$ACCOUNTS_FILE" ]; then
    echo "  Accounts:"; nl -w4 -s'. ' <(cut -d'|' -f1 "$ACCOUNTS_FILE")
    local pick; pick="$(ask "  Which label is the default?" "$(head -1 "$ACCOUNTS_FILE" | cut -d'|' -f1)")"
    local line; line="$(grep "^${pick}|" "$ACCOUNTS_FILE" | head -1)"
    if [ -n "$line" ]; then
      git config --global user.name  "$(echo "$line" | cut -d'|' -f2)"
      git config --global user.email "$(echo "$line" | cut -d'|' -f3)"
      ok "Global default = ${pick}"
    fi
  fi

  # WSL / Git Bash: repos on the Windows filesystem trip git's ownership check.
  # Skip on macOS/Linux, where it would only switch that safety check off globally.
  case "$(uname -s) $(uname -r)" in
    *[Mm]icrosoft*|MINGW*|MSYS*|CYGWIN*)
      git config --global --get-all safe.directory 2>/dev/null | grep -qxF '*' \
        || git config --global --add safe.directory '*' ;;
  esac

  install_helpers
  echo
  ok "Done! Run:  source ${RCNAME}   then:  githelp"
}

install_helpers(){
  # remove old block if present, then append fresh (awk instead of sed -i: BSD/GNU differ)
  if grep -qF "$MARK_START" "$RCFILE" 2>/dev/null; then
    local tmp; tmp="$(mktemp)"
    awk -v s="$MARK_START" -v e="$MARK_END" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$RCFILE" > "$tmp" \
      && cat "$tmp" > "$RCFILE"
    rm -f "$tmp"
  fi
  cat >> "$RCFILE" <<'HELPERS'
# >>> git-multi-account >>>
GIT_ACCOUNTS_FILE="$HOME/.git-accounts"

_ga_line(){ grep "^$1|" "$GIT_ACCOUNTS_FILE" 2>/dev/null | head -1; }

gitwho(){
  echo "user.name : $(git config user.name 2>/dev/null)"
  echo "user.email: $(git config user.email 2>/dev/null)"
  echo "origin    : $(git remote get-url origin 2>/dev/null)"
}

gitaccounts(){
  [ -s "$GIT_ACCOUNTS_FILE" ] || { echo "No accounts. Run gitsetup."; return; }
  printf "%-12s %-18s %s\n" "LABEL" "GITHUB USER" "EMAIL"
  while IFS='|' read -r l u e k h; do printf "%-12s %-18s %s\n" "$l" "$u" "$e"; done < "$GIT_ACCOUNTS_FILE"
}

gituse(){
  local label="$1"; local line; line="$(_ga_line "$label")"
  [ -z "$line" ] && { echo "Unknown account: $label (try: gitaccounts)"; return 1; }
  IFS='|' read -r l u e k h <<< "$line"
  git config user.name  "$u"
  git config user.email "$e"
  local url; url="$(git remote get-url origin 2>/dev/null)"
  if [ -n "$url" ]; then
    # rewrite host portion to the alias ("rpath", not "path": zsh ties $path to $PATH)
    local rpath="${url#*github.com*:}"; rpath="${rpath#*github.com*/}"
    git remote set-url origin "git@${h}:${rpath}"
  fi
  echo "Switched to '$l' ($u <$e>)"
  gitwho
}

gitclone(){
  local label="$1" url="$2"; local line; line="$(_ga_line "$label")"
  [ -z "$line" ] && { echo "Unknown account: $label (try: gitaccounts)"; return 1; }
  IFS='|' read -r l u e k h <<< "$line"
  # normalize url to owner/repo
  local or="$url"
  or="${or#https://github.com/}"; or="${or#git@github.com:}"; or="${or#github.com/}"
  or="${or%.git}"
  case "$(echo "$or" | tr -cd '/' )" in
    "/") ;; *) echo "Use owner/repo or a full GitHub URL"; return 1;;
  esac
  git clone "git@${h}:${or}.git" || return 1
  cd "$(basename "$or")" || return 1
  git config user.name "$u"; git config user.email "$e"
  echo "Cloned as '$l' -> $(pwd)"
}

gitnew(){
  local label="$1" repo="${2:-}"; local line; line="$(_ga_line "$label")"
  [ -z "$line" ] && { echo "Unknown account: $label (try: gitaccounts)"; return 1; }
  IFS='|' read -r l u e k h <<< "$line"
  git init -b main 2>/dev/null || git init
  git config user.name "$u"; git config user.email "$e"
  if [ -n "$repo" ]; then
    git remote add origin "git@${h}:${u}/${repo}.git" 2>/dev/null \
      || git remote set-url origin "git@${h}:${u}/${repo}.git"
    echo "Remote: git@${h}:${u}/${repo}.git"
  fi
  echo "Initialized here as '$l' ($u <$e>)"
}

gitsetup(){ bash "$HOME/.git-setup.sh"; }
gitadd-account(){ bash "$HOME/.git-setup.sh"; }

gitremove(){
  local label="${1:-}"
  [ -f "$GIT_ACCOUNTS_FILE" ] || { echo "No accounts configured."; return; }
  if [ -z "$label" ]; then
    gitaccounts
    printf "  Which label to remove? "; read -r label   # no read -p: zsh treats -p as coprocess
  fi
  [ -z "$label" ] && return
  local line; line="$(_ga_line "$label")"
  [ -z "$line" ] && { echo "Unknown account: $label (try: gitaccounts)"; return 1; }
  IFS='|' read -r _l _u _e keypath host <<< "$line"

  local tmp; tmp="$(mktemp)"
  # grep -v exits 1 when no lines remain (removing the last account), so don't gate mv on it
  { grep -v "^${label}|" "$GIT_ACCOUNTS_FILE" || true; } > "$tmp" && mv "$tmp" "$GIT_ACCOUNTS_FILE"
  echo "  Removed '$label' from accounts."

  local ssh_cfg="$HOME/.ssh/config"
  if [ -f "$ssh_cfg" ]; then
    local tmp2; tmp2="$(mktemp)"
    awk -v h="$host" '/^Host /{skip=($2==h?1:0)} !skip{print}' "$ssh_cfg" > "$tmp2" && mv "$tmp2" "$ssh_cfg"
    echo "  Removed SSH config entry for '$host'."
  fi

  if [ -f "$keypath" ]; then
    local del; printf "  Delete SSH key '%s'? (y/n) [n]: " "$keypath"; read -r del
    case "$del" in
      [yY]*) rm -f "$keypath" "${keypath}.pub"; echo "  Deleted SSH key files." ;;
    esac
  fi
  echo "Account '$label' removed. Open a new terminal to reload shortcuts."
}

githelp(){
  cat <<EOF

  Git Multi-Account - commands
  ----------------------------------------------------------
  gitaccounts            list configured accounts
  gitwho                 show current repo identity + remote
  gituse <label>         switch current repo to an account
  gitclone <label> <url> clone a repo as an account (owner/repo or full URL)
  gitnew <label> [repo]  init a NEW repo here as an account (+remote if repo given)
  gitremove [label]      remove a configured account
  gitsetup               re-run the wizard (add accounts, fix keys)
  gitadd-account         same as gitsetup

  Per-account shortcuts (auto-generated):
EOF
  while IFS='|' read -r l u e k h; do
    echo "  git-$l                 switch current repo to '$l'"
    echo "  $l-clone <url>          clone as '$l'"
    echo "  $l-init [repo]          init a new repo here as '$l'"
  done < "$GIT_ACCOUNTS_FILE" 2>/dev/null
  cat <<EOF

  Plain git shortcuts:
  gs=status  ga=add .  gcm "msg"=commit  gp=push  gl=pull  gco=checkout
  ----------------------------------------------------------
EOF
}

# plain shortcuts
alias gs='git status'
alias ga='git add .'
gcm(){ git commit -m "$*"; }
alias gp='git push'
alias gl='git pull'
alias gco='git checkout'

# generate per-account shortcuts: git-<label> and <label>-clone
if [ -s "$GIT_ACCOUNTS_FILE" ]; then
  while IFS='|' read -r _l _u _e _k _h; do
    eval "git-${_l}(){ gituse '${_l}'; }"
    eval "${_l}-clone(){ gitclone '${_l}' \"\$1\"; }"
    eval "${_l}-init(){ gitnew '${_l}' \"\$1\"; }"
  done < "$GIT_ACCOUNTS_FILE"
fi
# <<< git-multi-account <<<
HELPERS
  ok "Helpers installed into ${RCNAME}"
}

# Keep a copy of this script where gitsetup expects it
cp "$0" "$HOME/.git-setup.sh" 2>/dev/null || true

run_wizard
