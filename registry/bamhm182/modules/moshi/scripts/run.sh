#!/usr/bin/env sh

# Convert templated variables to shell variables
export LOG_PATH="${LOG_PATH}"
export INSTALL_DIR="${INSTALL_DIR}"

# Provide defaults for terraform vars if script run directly
[ -z "$LOG_PATH" ] && export LOG_PATH="/tmp/moshi.log"
[ -z "$INSTALL_DIR" ] && export INSTALL_DIR="$HOME/.local/bin"

# Set Moshi variables and helpers
export BOLD='\033[0;1m'
export TERM=dumb
export MOSHI_HOOK_SKIP_FIRST_RUN=1
export MOSHI_HOOK_SKIP_SERVICE=1
export MOSHI_HOOK="$INSTALL_DIR/moshi-hook"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    printf '🚧 WARNING: %s is not in your PATH.\n' "$INSTALL_DIR" >&2
    printf '\tAdd it with: export PATH="$PATH:%s"\n\n' "$INSTALL_DIR" >&2
    ;;
esac

export PATH="$PATH:$INSTALL_DIR"

printf "👷 Starting Moshi Dependency install...\n\n"

install_package() {
  # Check if a command exists, if not, install the package.
  # $2 is the command provided if the package name is not a command.
  pkg="$1"
  cmd="$${2:-$pkg}"

  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%s is already installed...\n\n' "$pkg"
    return 0
  fi

  printf 'Installing %s...\n' "$pkg"

  if command -v apt-get >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    { SUDO apt-get update && SUDO apt-get install -y "$pkg"; } >> "$LOG_PATH" 2>&1
  elif command -v dnf >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO dnf install -y "$pkg" >> "$LOG_PATH" 2>&1
  elif command -v yum >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO yum install -y "$pkg" >> "$LOG_PATH" 2>&1
  elif command -v zypper >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO zypper install -y "$pkg" >> "$LOG_PATH" 2>&1
  elif command -v apk >/dev/null 2>&1 && [ "$CAN_SUDO" -eq 1 ]; then
    SUDO apk add "$pkg" >> "$LOG_PATH" 2>&1
  elif command -v brew >/dev/null 2>&1; then
    brew install "$pkg" >> "$LOG_PATH" 2>&1
  else
    printf '🚨 No usable package manager (or no sudo). Please install %s manually.\n' "$pkg" >&2
    return 1
  fi

  status=$?
  if [ "$status" -ne 0 ]; then
    printf '🚨 Failed to install %s (exit code %s)\n' "$pkg" "$status" >&2
    return "$status"
  fi

  printf '\t🥳 %s installed successfully\n\n' "$pkg"
}

CAN_SUDO=0

if [ "$(id -u)" -eq 0 ]; then
  CAN_SUDO=1
  SUDO() { "$@"; }
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  CAN_SUDO=1
  SUDO() { sudo -n "$@"; }
else
  printf '🚧 WARNING: not root and no passwordless sudo; privileged steps will be skipped.\n' >&2
  SUDO() { "$@"; }
fi

install_package mosh
install_package procps pgrep
install_package python3

if command -v curl >/dev/null 2>&1; then
  printf "curl is already installed!\n\n"
  fetch_to()    { curl -fsSL "$1" -o "$2"; }
  fetch_quiet() { curl -fsSL "$1" -o "$2" 2>/dev/null; }
  fetch_out()   { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  printf "wget is already installed!\n\n"
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

mkdir -p "$INSTALL_DIR"
printf '%s' "${REDIRECTOR_B64}" | base64 -d > "$INSTALL_DIR/moshi-redirector.py"
chmod +x "$INSTALL_DIR/moshi-redirector.py"

printf "🥳 Installation complete!\n\n"

printf "👷 Starting Moshi in background...\n\n"

if [ ! -f "$HOME/.config/moshi/config.toml" ]; then
  $MOSHI_HOOK set usage-collection off >> "$LOG_PATH" 2>&1
  $MOSHI_HOOK set scan-ports none >> "$LOG_PATH" 2>&1
  $MOSHI_HOOK set always-on-discovery off >> "$LOG_PATH" 2>&1
fi

nohup "$MOSHI_HOOK" serve >> "$LOG_PATH" 2>&1 < /dev/null &
nohup "$INSTALL_DIR/moshi-redirector.py" >> "$LOG_PATH" 2>&1 < /dev/null &

printf "📝 Log File: %s\n\n" "$LOG_PATH"