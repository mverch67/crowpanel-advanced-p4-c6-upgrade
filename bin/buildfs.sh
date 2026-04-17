#!/usr/bin/env bash
# Build the LittleFS filesystem image from the data/ directory.
# PlatformIO's mklittlefs tool is invoked automatically via `buildfs`.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "Usage: $0 <target> [platformio args...]"
    echo "Targets: crowpanel-p4-50 | crowpanel-p4-70-90-101"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

TARGET="$1"
shift

case "$TARGET" in
    crowpanel-p4-50|crowpanel-p4-70-90-101) ;;
    *)
        echo "ERROR: invalid target '$TARGET'"
        usage
        exit 1
        ;;
esac

# Sanity check: warn if data/ has no .bin payloads.
if ! ls "$PROJECT_DIR"/data/*.bin &>/dev/null; then
    echo "WARNING: no .bin files found in data/ — run bin/download_c6_fw.sh first."
    exit 1
fi

cd "$PROJECT_DIR"
exec platformio run -e "$TARGET" -t buildfs "$@"
