#!/usr/bin/env bash
set -euo pipefail

# get the latest vscode-generated auth sock, if available
VSCODE_SSH_AUTH_SOCK=""
mapfile -t vscode_ssh_socks < <(compgen -G "/tmp/vscode-ssh*.sock" || true)
if [[ ${#vscode_ssh_socks[@]} -gt 0 ]]; then
  VSCODE_SSH_AUTH_SOCK=$(ls -1t "${vscode_ssh_socks[@]}" | head -n 1)
fi

if [ -n "${VSCODE_SSH_AUTH_SOCK}" ]; then
  export SSH_AUTH_SOCK=${VSCODE_SSH_AUTH_SOCK}
fi

if [ -n "${SSH_AUTH_SOCK:-}" ]; then
  echo "export SSH_AUTH_SOCK=\"${SSH_AUTH_SOCK}\"" >> ~/.profile
  echo "export SSH_AUTH_SOCK=\"${SSH_AUTH_SOCK}\"" >> ~/.bashrc
  echo "export SSH_AUTH_SOCK=\"${SSH_AUTH_SOCK}\"" >> ~/.zshenv  
fi

CRED_FILE="${CRED_FILE:-.sshcred}"
SSH_PORT="${SSH_PORT:-5001}"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -n "$@" 2>/dev/null || sudo "$@"
    return
  fi

  echo "ERROR: need root privileges (run as root or install/configure sudo)" >&2
  exit 1
}

as_root_bash() {
  local cmd="$1"

  if [[ "$(id -u)" -eq 0 ]]; then
    bash -lc "$cmd"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -n bash -lc "$cmd" 2>/dev/null || sudo bash -lc "$cmd"
    return
  fi

  echo "ERROR: need root privileges (run as root or install/configure sudo)" >&2
  exit 1
}

as_current_user_bash() {
  local cmd="$1"
  local quoted_home
  local quoted_cmd

  printf -v quoted_home "%q" "$CURRENT_USER_HOME"
  printf -v quoted_cmd "%q" "$cmd"

  if [[ "$(id -un)" == "$CURRENT_USER" ]]; then
    HOME="$CURRENT_USER_HOME" bash -lc "$cmd"
    return
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$CURRENT_USER" -- env HOME="$CURRENT_USER_HOME" bash -lc "$cmd"
      return
    fi

    if command -v su >/dev/null 2>&1; then
      su -s /bin/bash "$CURRENT_USER" -c "env HOME=$quoted_home bash -lc $quoted_cmd"
      return
    fi
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -n -u "$CURRENT_USER" HOME="$CURRENT_USER_HOME" bash -lc "$cmd" 2>/dev/null \
      || sudo -u "$CURRENT_USER" HOME="$CURRENT_USER_HOME" bash -lc "$cmd"
    return
  fi

  echo "ERROR: unable to run command as ${CURRENT_USER}" >&2
  exit 1
}

resolve_path() {
  local path="$1"
  local dir_path

  dir_path="$(cd "$(dirname "$path")" && pwd -P)"
  printf '%s/%s\n' "$dir_path" "$(basename "$path")"
}

# Prefer the non-root invoker when using sudo
CURRENT_USER="${SUDO_USER:-$(id -un)}"
CURRENT_USER_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"
if [[ -z "$CURRENT_USER_HOME" ]]; then
  echo "ERROR: unable to resolve home directory for ${CURRENT_USER}" >&2
  exit 1
fi

# Install deps and prep sshd dirs
as_root_bash '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

missing_packages=()
for package in openssh-server uuid-runtime dtach tmux git; do
  if ! dpkg-query -W -f="\${db:Status-Status}" "$package" 2>/dev/null | grep -qx installed; then
    missing_packages+=("$package")
  fi
done

if [[ ${#missing_packages[@]} -gt 0 ]]; then
  apt-get update
  apt-get install -y --no-install-recommends "${missing_packages[@]}"
  rm -rf /var/lib/apt/lists/*
else
  echo "All apt packages already installed; skipping apt-get install."
fi

mkdir -p /var/run/sshd
mkdir -p /etc/ssh/sshd_config.d
'

# install fresh editor
curl https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh | sh

# install GitHub CLI if missing
if command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI already installed; skipping."
else
  as_root_bash '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
if ! apt-get install -y --no-install-recommends gh; then
  echo "Default apt sources do not provide gh; configuring the official GitHub CLI repository."
  apt-get install -y --no-install-recommends ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y --no-install-recommends gh
fi
rm -rf /var/lib/apt/lists/*
'
fi

# install GitHub Copilot CLI
curl -fsSL https://gh.io/copilot-install | bash

# install opencode and ensure it is available on the user PATH
OPENCODE_INSTALL_DIR="${CURRENT_USER_HOME}/.opencode/bin"
if as_current_user_bash "command -v opencode >/dev/null 2>&1"; then
  echo "opencode already installed; skipping."
else
  as_current_user_bash "curl -fsSL https://opencode.ai/install | bash"
fi

if ! as_current_user_bash "command -v opencode >/dev/null 2>&1"; then
  OPENCODE_BIN="${OPENCODE_INSTALL_DIR}/opencode"
  if [[ ! -x "$OPENCODE_BIN" ]]; then
    echo "ERROR: opencode install completed but ${OPENCODE_BIN} is not executable" >&2
    exit 1
  fi

  as_root ln -sf "$OPENCODE_BIN" /usr/local/bin/opencode
fi

if ! as_current_user_bash "command -v opencode >/dev/null 2>&1"; then
  echo "ERROR: opencode is installed but not available on PATH for ${CURRENT_USER}" >&2
  exit 1
fi

# Use existing password if present, otherwise create it once
if [[ -f "$CRED_FILE" ]]; then
  PASS="$(cat "$CRED_FILE")"
  if [[ -z "${PASS}" ]]; then
    echo "ERROR: ${CRED_FILE} exists but is empty" >&2
    exit 1
  fi
else
  PASS="$(uuidgen | tr "[:upper:]" "[:lower:]")"
  umask 077
  printf '%s' "$PASS" > "$CRED_FILE"
fi

# If CURRENT_USER is root, allow root SSH. Otherwise, keep root SSH disabled.
if [[ "$CURRENT_USER" == "root" ]]; then
  PERMIT_ROOT_LOGIN="yes"
else
  PERMIT_ROOT_LOGIN="no"
fi

# Ensure user exists + set password + configure sshd
as_root_bash "
set -euo pipefail

if ! id -u '${CURRENT_USER}' >/dev/null 2>&1; then
  useradd -m -s /bin/bash '${CURRENT_USER}'
fi

echo '${CURRENT_USER}:${PASS}' | chpasswd

cat >/etc/ssh/sshd_config.d/99-local.conf <<EOF
Port ${SSH_PORT}
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
PermitRootLogin ${PERMIT_ROOT_LOGIN}
EOF
chmod 0644 /etc/ssh/sshd_config.d/99-local.conf

if ! grep -qE '^\\s*Include\\s+/etc/ssh/sshd_config\\.d/\\*\\.conf\\s*$' /etc/ssh/sshd_config; then
  echo 'Include /etc/ssh/sshd_config.d/*.conf' >> /etc/ssh/sshd_config
fi
"

# If git exists and this is a repo, ignore locally without touching .gitignore
if command -v git >/dev/null 2>&1; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REPO_ROOT="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
    CRED_FILE_ABS="$(resolve_path "$CRED_FILE")"

    if [[ "$CRED_FILE_ABS" == "$REPO_ROOT"/* ]]; then
      EXCLUDE_FILE="${REPO_ROOT}/.git/info/exclude"
      RELATIVE_CRED_PATH="${CRED_FILE_ABS#"$REPO_ROOT"/}"
      PATTERN="/${RELATIVE_CRED_PATH}"

      mkdir -p "${REPO_ROOT}/.git/info"
      touch "$EXCLUDE_FILE"
      if ! grep -qxF "$PATTERN" "$EXCLUDE_FILE"; then
        printf '\n%s\n' "$PATTERN" >> "$EXCLUDE_FILE"
      fi
    fi
  fi
fi

echo "SSH user: ${CURRENT_USER}"
echo "SSH pass: ${PASS}"
echo "SSH port: ${SSH_PORT}"
echo "PermitRootLogin: ${PERMIT_ROOT_LOGIN}"

# Start sshd in background (reads Port from config, but we also pass -p to be explicit)
as_root /usr/sbin/sshd -p "$SSH_PORT"

echo "To stop SSH server, run:"
echo "pkill -TERM -x sshd || true"
