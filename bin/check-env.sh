#!/usr/bin/env bash
# Check if the local development environment is ready for this project.
#
# Validates:
# - Python 3
# - PlatformIO CLI (platformio or pio)
# - pioarduino platform installation
# - esptool (via python module or CLI)
#
# If PlatformIO is missing, this script can guide the user to install
# pioarduino core using the official installer project.

set -euo pipefail

PIOARDUINO_INSTALLER_URL="https://github.com/pioarduino/pioarduino-core-installer"

HAS_ERRORS=0
MISSING_PLATFORMIO=0
MISSING_PIP=0
MISSING_VENV=0
PLATFORMIO_OFF_PATH=0
MISSING_PIOARDUINO=0

print_ok() {
    echo "[OK]   $1"
}

print_err() {
    echo "[FAIL] $1"
    HAS_ERRORS=1
}

print_info() {
    echo "[INFO] $1"
}

find_platformio_cmd() {
    if command -v platformio >/dev/null 2>&1; then
        echo "platformio"
        return 0
    fi
    if command -v pio >/dev/null 2>&1; then
        echo "pio"
        return 0
    fi
    return 1
}

find_pioarduino_platforms() {
    local platform_dir="${PLATFORMIO_CORE_DIR:-$HOME/.platformio}/platforms"

    [[ -d "$platform_dir" ]] || return 1

    find "$platform_dir" -name platform.json -exec grep -l "https://github.com/pioarduino/" {} + 2>/dev/null
}

show_platformio_path_hint() {
    local known_platformio_bin="$HOME/.platformio/penv/bin/platformio"
    local known_activate_sh="$HOME/.platformio/penv/bin/activate"

    if [[ -x "$known_platformio_bin" ]]; then
        PLATFORMIO_OFF_PATH=1
        print_info "PlatformIO appears installed but is not on your current PATH."
        if [[ -f "$known_activate_sh" ]]; then
            print_info "Try: source $known_activate_sh"
        else
            print_info "Try running directly: $known_platformio_bin --version"
        fi
    fi
}

is_tty() {
    [[ -t 0 && -t 1 ]]
}

prompt_yes_no() {
    local prompt="$1"
    local answer
    while true; do
        read -rp "$prompt [y/N]: " answer
        case "$answer" in
            y|Y|yes|YES)
                return 0
                ;;
            n|N|no|NO|"")
                return 1
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
}

show_pioarduino_install_help() {
    cat <<EOF

pioarduino core does not appear to be installed.
The pioarduino installer requires 'uv'.

Recommended next step:
1. Open: $PIOARDUINO_INSTALLER_URL
2. Follow the installer instructions for your OS.

If 'uv' is missing, install it first (usually no sudo needed):
    curl -LsSf https://astral.sh/uv/install.sh | sh

If pip is missing from Python, bootstrap it first:
    python3 -m ensurepip --upgrade
    python3 -m pip install --user --upgrade pip

Note: On some systems, ensurepip may require admin rights (for example if
Python was installed system-wide). Prefer a user-level Python/venv when possible.

Then try this generic flow:
  git clone $PIOARDUINO_INSTALLER_URL
  cd pioarduino-core-installer
  uv run python get-platformio.py

Alternative uv install (if curl method is unavailable):
    python3 -m pip install --user uv

After installation, run this script again:
  bin/check-env.sh
EOF
}

echo "Checking development environment..."

# Check Python
if command -v python3 >/dev/null 2>&1; then
    PY_VER="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || true)"
    if [[ -n "$PY_VER" ]]; then
        print_ok "Python 3 detected ($PY_VER)"
    else
        print_err "Python 3 detected, but version check failed"
    fi
else
    print_err "Python 3 not found"
fi

# Check pip for Python 3 (needed for fallback uv installation)
if command -v python3 >/dev/null 2>&1; then
    if python3 -m pip --version >/dev/null 2>&1; then
        PIP_VER="$(python3 -m pip --version 2>/dev/null | head -1 || true)"
        if [[ -n "$PIP_VER" ]]; then
            print_ok "pip for Python 3 detected ($PIP_VER)"
        else
            print_ok "pip for Python 3 detected"
        fi
    else
        echo "[INFO] pip for Python 3 not found."
        echo "[INFO] To install pip: python3 -m ensurepip --upgrade"
        MISSING_PIP=1
    fi
fi

# Check Python venv module (used by many installers/toolchains)
if command -v python3 >/dev/null 2>&1; then
    if python3 -m venv --help >/dev/null 2>&1; then
        print_ok "Python venv module detected"
    else
        print_info "Python venv module not found."
        print_info "If needed, install it (example Debian/Ubuntu): sudo apt install python3-venv"
        MISSING_VENV=1
    fi
fi

# Check PlatformIO / pioarduino CLI
PIO_CMD=""
if PIO_CMD="$(find_platformio_cmd)"; then
    PIO_VER="$($PIO_CMD --version 2>/dev/null | head -1 || true)"
    if [[ -n "$PIO_VER" ]]; then
        print_ok "PlatformIO CLI detected ($PIO_VER via '$PIO_CMD')"
    else
        print_ok "PlatformIO CLI detected (command: '$PIO_CMD')"
    fi
else
    print_err "PlatformIO CLI not found (platformio/pio)"
    show_platformio_path_hint
    MISSING_PLATFORMIO=1
fi

# Check for installed pioarduino platform metadata
PIOARDUINO_MATCHES="$(find_pioarduino_platforms || true)"
if [[ -n "$PIOARDUINO_MATCHES" ]]; then
    PIOARDUINO_COUNT="$(printf '%s\n' "$PIOARDUINO_MATCHES" | sed '/^$/d' | wc -l)"
    print_ok "pioarduino platform metadata detected ($PIOARDUINO_COUNT platform.json match(es))"
else
    print_err "pioarduino platform metadata not found under ${PLATFORMIO_CORE_DIR:-$HOME/.platformio}/platforms"
    MISSING_PIOARDUINO=1
fi

# Check uv (required by pioarduino core installer)
if command -v uv >/dev/null 2>&1; then
    UV_VER="$(uv --version 2>/dev/null | head -1 || true)"
    if [[ -n "$UV_VER" ]]; then
        print_ok "uv detected ($UV_VER)"
    else
        print_ok "uv detected"
    fi
else
    print_info "uv not found (required only if you need to install pioarduino core)."
fi

# Check esptool
if command -v python3 >/dev/null 2>&1 && python3 -m esptool version >/dev/null 2>&1; then
    ESPTOOL_VER="$(python3 -m esptool version 2>/dev/null | head -1 || true)"
    if [[ -n "$ESPTOOL_VER" ]]; then
        print_ok "esptool Python module detected ($ESPTOOL_VER)"
    else
        print_ok "esptool Python module detected"
    fi
elif command -v esptool >/dev/null 2>&1; then
    ESPTOOL_VER="$(esptool version 2>/dev/null | head -1 || true)"
    if [[ -n "$ESPTOOL_VER" ]]; then
        print_ok "esptool CLI detected ($ESPTOOL_VER)"
    else
        print_ok "esptool CLI detected"
    fi
else
    print_err "esptool not found (python module or CLI)"
fi

if [[ "$HAS_ERRORS" -eq 0 ]]; then
    echo "Checking development environment ... OK"
    exit 0
fi

echo "Checking development environment ... NOT OK"

if [[ "$MISSING_PLATFORMIO" -eq 1 ]]; then
    if [[ "$PLATFORMIO_OFF_PATH" -eq 1 ]]; then
        echo "PlatformIO seems to already be installed. Activate its environment and run this check again."
    else
        if is_tty; then
            if prompt_yes_no "Would you like to install pioarduino core now?"; then
                show_pioarduino_install_help
            else
                echo "Skipped pioarduino installation."
            fi
        else
            echo "Non-interactive shell detected; skipping install prompt."
            show_pioarduino_install_help
        fi
    fi
fi

if [[ "$MISSING_PIOARDUINO" -eq 1 && "$MISSING_PLATFORMIO" -eq 0 ]]; then
    if is_tty; then
        if prompt_yes_no "pioarduino platform files were not found. Would you like installation guidance now?"; then
            show_pioarduino_install_help
        else
            echo "Skipped pioarduino installation guidance."
        fi
    else
        echo "Non-interactive shell detected; skipping install prompt."
        show_pioarduino_install_help
    fi
fi

if [[ "$MISSING_PIP" -eq 1 && "$MISSING_PLATFORMIO" -eq 0 ]]; then
    echo "Hint: pip is optional for normal build/flash, but needed for some install flows."
fi

if [[ "$MISSING_VENV" -eq 1 && "$MISSING_PLATFORMIO" -eq 0 ]]; then
    echo "Hint: venv is optional once everything is installed, but useful for isolated Python tooling."
fi

exit 2
