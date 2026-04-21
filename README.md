# ssh-server-runner

A script that starts an SSH server inside a devcontainer (or any Debian/Ubuntu environment), installs a small set of developer tools, and wires up SSH agent forwarding from VS Code — so your local SSH keys work transparently inside the container.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Connecting to the server](#connecting-to-the-server)
- [Stopping the server](#stopping-the-server)
- [Persistent terminal sessions with dtach and tmux](#persistent-terminal-sessions-with-dtach-and-tmux)
- [What the script installs and configures](#what-the-script-installs-and-configures)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- **OS:** Debian or Ubuntu (including devcontainer images built on either).
- **Tools available in PATH:** `curl`, `bash`.
- **Privileges:** `sudo` access or a root shell (the script uses `sudo` automatically when it is available).
- **Open port:** The chosen port (default `5001`) must not already be in use and must be reachable from your SSH client.

---

## Quick Start

Run this one-liner inside your devcontainer terminal:

```bash
# Start the server on the default port (5001)
curl -fsSL https://raw.githubusercontent.com/PabloZaiden/ssh-server-runner/main/ssh-server.sh | bash
```

To use a custom port or a custom credential file location, set the relevant environment variables inline:

```bash
# Custom port and credential file
curl -fsSL https://raw.githubusercontent.com/PabloZaiden/ssh-server-runner/main/ssh-server.sh \
  | SSH_PORT=2222 CRED_FILE=~/.mysshcred bash
```

When the script finishes it prints the SSH user, password, and port:

```
SSH user: vscode
SSH pass: a1b2c3d4-...
SSH port: 5001
PermitRootLogin: no
To stop SSH server, run:
pkill -TERM -x sshd || true
```

Use those credentials to connect immediately (see [Connecting to the server](#connecting-to-the-server)).

If VS Code does not automatically expose the port, open the **Ports** panel (`Ctrl+Shift+P` → "Focus on Ports View") and forward it manually.

---

## Configuration

All options are set via environment variables passed to the script. No config file is required.

| Variable | Default | Description |
|---|---|---|
| `SSH_PORT` | `5001` | Port the SSH daemon listens on. |
| `CRED_FILE` | `.sshcred` | Path where the generated password is stored. Relative paths are resolved against the current working directory. |

---

## Connecting to the server

Once the script exits, the SSH daemon is running. Connect with:

```bash
ssh -p 5001 <user>@localhost
```

Replace `5001` with your `SSH_PORT` and `<user>` with the username printed by the script.

### Forward your local SSH agent

```bash
ssh -A -p 5001 <user>@localhost
```

The `-A` flag forwards your local SSH agent into the remote session, giving the server access to your local SSH keys without copying private key files.

> **Note:** The script already persists the VS Code SSH agent socket (`SSH_AUTH_SOCK`) into `~/.profile`, `~/.bashrc`, and `~/.zshenv` inside the container. Reconnecting to an existing session will therefore have agent forwarding re-applied automatically on login, as long as the socket path is still valid.

### Connect with VS Code Remote – SSH

Add an entry to your local `~/.ssh/config`:

```
Host my-devcontainer
    HostName localhost
    Port 5001
    User <user>
    ForwardAgent yes
```

Then open VS Code, run **Remote-SSH: Connect to Host…**, and select `my-devcontainer`.

---

## Stopping the server

The script starts `sshd` and exits — it does **not** keep a foreground process running. To stop the SSH daemon:

```bash
pkill -TERM -x sshd || true
```

If you need to restart it, simply re-run the original `curl | bash` one-liner. The script reuses the existing credential file and does not rotate the password.

---

## Persistent terminal sessions with dtach and tmux

Both `dtach` and `tmux` are installed by the script so you can keep terminal sessions alive across SSH disconnects.

If you want the lightest possible detached session tool, use `dtach`:

Start a detached session:

```bash
dtach -c /tmp/mysession bash
```

Detach from a running session (without killing it) with `Ctrl+\`.

Re-attach to an existing session:

```bash
dtach -a /tmp/mysession
```

This is especially useful inside SSH sessions where network interruptions would otherwise terminate any running processes.

If you prefer a full terminal multiplexer, start `tmux` instead:

```bash
tmux
```

`tmux` gives you windows, panes, session management, and more advanced workflows than `dtach`.

---

## What the script installs and configures

`ssh-server.sh` does more than just start `sshd`. It installs software, writes configuration, and creates local state so later runs can reuse it.

### Apt packages

The script checks whether these Debian packages are already installed and only installs the ones that are missing:

- `openssh-server` — the SSH daemon.
- `uuid-runtime` — provides `uuidgen` for generating a random password.
- `dtach` — lightweight terminal session manager (see [above](#persistent-terminal-sessions-with-dtach-and-tmux)).
- `tmux` — full-featured terminal multiplexer for persistent sessions and pane/window management.

It also creates these runtime/configuration directories if they do not already exist:

- `/var/run/sshd`
- `/etc/ssh/sshd_config.d`

### Bootstrapped tools

- **`fresh` editor** — installed by piping the upstream install script from `https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh` into `sh`. Run on every execution.
- **GitHub CLI (`gh`)** — installed only when `gh` is not already on `PATH`. If the default apt repositories do not provide it, the script adds GitHub's official apt repository and retries.
- **GitHub Copilot CLI** — installed on every run by piping `https://gh.io/copilot-install` into `bash`.

When adding the GitHub CLI apt repository the script writes:
- `/etc/apt/keyrings/githubcli-archive-keyring.gpg`
- `/etc/apt/sources.list.d/github-cli.list`

### SSH authentication and generated files

On first run the script generates a random password using `uuidgen` and stores it in `CRED_FILE` (default: `./.sshcred`, mode `0600`).

On later runs it reuses the same credential file. If the file exists but is empty, the script exits with an error.

If the credential file lives inside the current git repository, the script appends its repo-relative path to `.git/info/exclude` so the password file is never accidentally committed — without modifying `.gitignore`.

### SSH daemon configuration

The script configures SSH for the current user (preferring `SUDO_USER` when invoked through `sudo`) and ensures that user exists before setting the password.

It writes `/etc/ssh/sshd_config.d/99-local.conf` with:

| Directive | Value |
|---|---|
| `Port` | `${SSH_PORT}` (default `5001`) |
| `PasswordAuthentication` | `yes` |
| `KbdInteractiveAuthentication` | `yes` |
| `UsePAM` | `yes` |
| `PermitRootLogin` | `yes` if running as root, `no` otherwise |

If `/etc/ssh/sshd_config` does not already include `/etc/ssh/sshd_config.d/*.conf`, the script appends that include directive once.

### SSH agent forwarding persistence

If `SSH_AUTH_SOCK` is set (or a VS Code-generated socket matching `/tmp/vscode-ssh*.sock` is found), the script appends an `export SSH_AUTH_SOCK="..."` line to:

- `~/.profile`
- `~/.bashrc`
- `~/.zshenv`

This ensures the agent socket is available in new login shells and interactive shells opened over SSH, even after the original VS Code process has rotated the socket path.

### What happens every run vs only when needed

| Action | Frequency |
|---|---|
| Install missing apt packages | Only when packages are absent |
| Install `gh` | Only when `gh` is not on `PATH` |
| Add GitHub CLI apt repository | Only if the default apt install for `gh` fails |
| Create credential file | Only on first run |
| Add `.git/info/exclude` entry | Only when pattern is not already present |
| Bootstrap `fresh` editor | Every run |
| Install GitHub Copilot CLI | Every run |
| Write SSH daemon config | Every run |
| Start `sshd` | Every run |

---

## Troubleshooting

### Port already in use

```
Error: bind: Address already in use
```

Another process is listening on `SSH_PORT`. Either stop that process or choose a different port:

```bash
curl -fsSL https://raw.githubusercontent.com/PabloZaiden/ssh-server-runner/main/ssh-server.sh \
  | SSH_PORT=2222 bash
```

### `sudo` not available and not running as root

```
ERROR: need root privileges (run as root or install/configure sudo)
```

Run the script as root, or install and configure `sudo` for your user before running it.

### Credential file is empty

```
ERROR: .sshcred exists but is empty
```

The credential file was created but never populated (e.g. a previous interrupted run). Delete it and re-run:

```bash
rm .sshcred
curl -fsSL https://raw.githubusercontent.com/PabloZaiden/ssh-server-runner/main/ssh-server.sh | bash
```

### `fresh` or Copilot CLI install fails

These tools are fetched from the internet on every run. If the container has no outbound internet access, those steps will fail but the SSH server will still start. The errors are non-fatal — scroll past them and check that the final `SSH user / SSH pass / SSH port` block was printed.

### SSH agent socket not forwarded after reconnect

The `SSH_AUTH_SOCK` value written to shell startup files captures the socket path at the time the script ran. VS Code periodically rotates this path. Re-run the script to capture the latest socket:

```bash
curl -fsSL https://raw.githubusercontent.com/PabloZaiden/ssh-server-runner/main/ssh-server.sh | bash
```

### Permission denied when connecting

- Verify the username and password match what was printed by the script.
- Confirm the port is forwarded and reachable (`ssh -v` is helpful).
- Check that `sshd` is still running: `pgrep -x sshd`.
- If you changed `SSH_PORT` between runs, make sure you are connecting to the new port.
