#!/usr/bin/env bash
# Flash the LittleFS storage partition to the ESP32-P4.
# Must be run BEFORE flash.sh so the C6 firmware is present on first boot.

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

# Build the image if not already built.
if [ ! -f "$PROJECT_DIR/.pio/build/$TARGET/littlefs.bin" ]; then
    echo "littlefs.bin not found — building filesystem image first..."
    "$SCRIPT_DIR/buildfs.sh" "$TARGET"
fi

cd "$PROJECT_DIR"
exec platformio run -e "$TARGET" -t uploadfs "$@"
