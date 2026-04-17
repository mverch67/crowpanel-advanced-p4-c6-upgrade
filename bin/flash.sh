#!/usr/bin/env bash
# Flash the app firmware to the ESP32-P4.
# Run bin/upload_fs.sh first so the LittleFS storage partition is ready.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

find_tio_port() {
	local port
	for port in /dev/ttyUSB*; do
		[[ -e "$port" ]] && {
			echo "$port"
			return 0
		}
	done
	return 1
}

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

cd "$PROJECT_DIR"
platformio run -e "$TARGET" -t upload "$@"

if [[ -x /usr/bin/tio ]] && PORT="$(find_tio_port)"; then
	echo "Opening serial console on $PORT..."
	exec /usr/bin/tio "$PORT"
fi
