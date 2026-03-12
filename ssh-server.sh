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

# Prefer the non-root invoker when using sudo
CURRENT_USER="${SUDO_USER:-$(id -un)}"

# Install deps and prep sshd dirs
as_root_bash '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends openssh-server uuid-runtime tmux
rm -rf /var/lib/apt/lists/*
mkdir -p /var/run/sshd
mkdir -p /etc/ssh/sshd_config.d
'

# install fresh editor
curl https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh | sh

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
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    EXCLUDE_FILE="${REPO_ROOT}/.git/info/exclude"
    PATTERN="/$(basename "$CRED_FILE")"

    mkdir -p "${REPO_ROOT}/.git/info"
    touch "$EXCLUDE_FILE"
    if ! grep -qxF "$PATTERN" "$EXCLUDE_FILE"; then
      printf '\n%s\n' "$PATTERN" >> "$EXCLUDE_FILE"
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
