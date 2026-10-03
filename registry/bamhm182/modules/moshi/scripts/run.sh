#!/usr/bin/env sh

# Convert templated variables to shell variables
export LOG_PATH=$${LOG_PATH:-/tmp/moshi.log}

# Set Moshi variables and helpers
export BOLD='\033[0;1m'
export TERM=dumb
export MOSHI_HOOK_SKIP_FIRST_RUN=1
export MOSHI_HOOK_SKIP_SERVICE=1
export INSTALL_DIR="$HOME/.local/bin"
export MOSHI_HOOK="$HOME/.local/bin/moshi-hook"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    printf 'WARNING: %s is not in your PATH.\n' "$INSTALL_DIR" >&2
    printf 'Add it with: export PATH="$PATH:%s"\n\n' "$INSTALL_DIR" >&2
    ;;
esac

export PATH="$PATH:$INSTALL_DIR"

install_package() {
  # Check if a command exists, if not, install the package.
  # $2 is the command provided if the package name is not a command.
  pkg="$1"
  cmd="$${2:-$pkg}"

  if [ -z "$pkg" ]; then
    printf 'usage: install_package <package>\n' >&2
    return 2
  fi

  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%s is already installed\n\n' "$pkg"
    return 0
  fi

  printf 'Installing %s\n\n' "$pkg"

  if command -v apt-get >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO apt-get update && SUDO apt-get install -y "$pkg"
  elif command -v dnf >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO dnf install -y "$pkg"
  elif command -v yum >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO yum install -y "$pkg"
  elif command -v zypper >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO zypper install -y "$pkg"
  elif command -v apk >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO apk add "$pkg"
  elif command -v brew >/dev/null 2>&1; then
    brew install "$pkg"
  else
    printf 'No usable package manager (or no sudo). Please install %s manually.\n' "$pkg" >&2
    return 1
  fi

  status=$?
  if [ "$status" -ne 0 ]; then
    printf 'Failed to install %s (exit code %s)\n' "$pkg" "$status" >&2
    return "$status"
  fi

  printf '%s installed successfully\n' "$pkg"
}

CAN_SUDO=0

if [ "$(id -u)" -eq 0 ]; then
  CAN_SUDO=1
  SUDO() { "$@"; }
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  CAN_SUDO=1
  SUDO() { sudo -n "$@"; }
else
  printf 'WARNING: not root and no passwordless sudo; privileged steps will be skipped.\n' >&2
  SUDO() { "$@"; }
fi

printf "👷 Starting Moshi Dependency install...\n\n"

install_package mosh
install_package procps pgrep

if command -v curl >/dev/null 2>&1; then
  printf "curl is already installed\n\n"
  fetch_to()    { curl -fsSL "$1" -o "$2"; }
  fetch_quiet() { curl -fsSL "$1" -o "$2" 2>/dev/null; }
  fetch_out()   { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  printf "wget is already installed\n\n"
  fetch_to()    { wget -qO "$2" "$1"; }
  fetch_quiet() { wget -qO "$2" "$1" 2>/dev/null; }
  fetch_out()   { wget -qO- "$1"; }
else
  install_package curl
  fetch_to()    { curl -fsSL "$1" -o "$2"; }
  fetch_quiet() { curl -fsSL "$1" -o "$2" 2>/dev/null; }
  fetch_out()   { curl -fsSL "$1"; }
fi

printf "👷 Starting Moshi install...\n\n"

fetch_out https://getmoshi.app/install.sh | sh

printf "🥳 Installation complete!\n\n"

printf "👷 Starting Moshi in background...\n\n"

if [ ! -f "$HOME/.config/moshi/config.toml" ]; then
  $MOSHI_HOOK set usage-collection off > /dev/null 2>&1
  $MOSHI_HOOK set scan-ports none > /dev/null 2>&1
  $MOSHI_HOOK set always-on-discovery off > /dev/null 2>&1
fi

# Don't start a second copy if one is already running
if ! pgrep -f "moshi-hook serve" >/dev/null; then
  setsid nohup $MOSHI_HOOK serve >> "$LOG_PATH" 2>&1 < /dev/null &
fi

printf "check logs at %s\n\n" "$LOG_PATH"