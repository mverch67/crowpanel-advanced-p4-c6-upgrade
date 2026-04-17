#!/usr/bin/env bash
# One-shot C6 upgrade flow:
#   1) download latest C6 firmware
#   2) build app
#   3) build LittleFS
#   4) upload LittleFS first
#   5) flash app
# Stops on first failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 <target>"
    echo "       $0 --auto"
    echo "Targets: crowpanel-p4-50 | crowpanel-p4-70-90-101"
}

resolve_target() {
    local arg="${1:-}"

    if [[ "$arg" == "--auto" || -z "$arg" ]]; then
        if detected="$($SCRIPT_DIR/detect_target.sh)"; then
            echo "$detected"
            return 0
        fi
        echo "ERROR: automatic detection failed. Pass target explicitly." >&2
        usage >&2
        return 1
    fi

    case "$arg" in
        crowpanel-p4-50|crowpanel-p4-70-90-101)
            echo "$arg"
            ;;
        *)
            echo "ERROR: invalid target '$arg'" >&2
            usage >&2
            return 1
            ;;
    esac
}

TARGET="$(resolve_target "${1:-}")"

echo "Using target: $TARGET"

"$SCRIPT_DIR/download_c6_fw.sh"
"$SCRIPT_DIR/build.sh" "$TARGET"
"$SCRIPT_DIR/buildfs.sh" "$TARGET"
"$SCRIPT_DIR/upload_fs.sh" "$TARGET"
"$SCRIPT_DIR/flash.sh" "$TARGET"

echo "C6 upgrade flow completed for target $TARGET"
