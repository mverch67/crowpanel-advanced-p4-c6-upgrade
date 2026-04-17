#!/usr/bin/env bash
# Self-learning board target detector.
#
# Reads the board MAC address via esptool and looks it up in .board-target-map.
# If the MAC is unknown, it interactively asks the user which display model is
# connected and stores the answer for future runs.
#
# Map file format (project root):
#   AA:BB:CC:DD:EE:FF crowpanel-p4-50
#   11:22:33:44:55:66 crowpanel-p4-70-90-101

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAP_FILE="$PROJECT_DIR/.board-target-map"

find_port() {
    local ports=()
    for p in /dev/ttyUSB* /dev/ttyACM* \
              /dev/cu.usbserial-* /dev/cu.usbmodem* /dev/cu.wchusbserial*; do
        [[ -e "$p" ]] && ports+=("$p")
    done

    case "${#ports[@]}" in
        0)
            return 1
            ;;
        1)
            echo "${ports[0]}"
            ;;
        *)
            echo "" >&2
            echo "Multiple serial ports detected. Which device do you want to use?" >&2
            local i=1
            for p in "${ports[@]}"; do
                echo "  $i) $p" >&2
                ((i++))
            done
            echo "  q) Quit / cancel" >&2
            echo "" >&2
            while true; do
                read -rp "Enter choice [1-${#ports[@]} or q]: " SEL </dev/tty
                if [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 1 && SEL <= ${#ports[@]} )); then
                    echo "${ports[$((SEL-1))]}"
                    return 0
                elif [[ "$SEL" == q || "$SEL" == Q ]]; then
                    echo "Cancelled." >&2
                    exit 1
                else
                    echo "Invalid choice." >&2
                fi
            done
            ;;
    esac
}

get_mac() {
    local port="$1"
    python3 -m esptool --port "$port" chip_id 2>/dev/null \
        | awk '/MAC:/ {print toupper($2)}' \
        | tail -1 \
        | tr -d '\r'
}

echo "Detecting board — please make sure the device is connected via USB..." >&2

if ! PORT="$(find_port)"; then
    echo "ERROR: no serial port found (ttyUSB / ttyACM / cu.usbserial / cu.usbmodem / cu.wchusbserial)." >&2
    exit 2
fi

echo "Reading MAC from $PORT..." >&2
MAC="$(get_mac "$PORT" || true)"
if [[ -z "$MAC" ]]; then
    echo "ERROR: unable to read MAC from $PORT via esptool." >&2
    exit 2
fi
echo "MAC: $MAC" >&2

# Look up existing mapping
if [[ -f "$MAP_FILE" ]]; then
    TARGET="$(awk -v mac="$MAC" 'toupper($1)==mac {print $2}' "$MAP_FILE" | head -1)"
    case "$TARGET" in
        crowpanel-p4-50|crowpanel-p4-70-90-101)
            echo "Known device: $TARGET" >&2
            echo "$TARGET"
            exit 0
            ;;
    esac
fi

# Unknown MAC — ask the user
echo "" >&2
echo "Unknown device (MAC: $MAC)." >&2
echo "Which CrowPanel display model is connected?" >&2
echo "  1) 5\"    → crowpanel-p4-50" >&2
echo "  2) 7\"    → crowpanel-p4-70-90-101" >&2
echo "  3) 9\"    → crowpanel-p4-70-90-101" >&2
echo "  4) 10.1\" → crowpanel-p4-70-90-101" >&2
echo "  q) Quit / cancel" >&2
echo "" >&2

while true; do
    read -rp "Enter choice [1-4 or q]: " CHOICE </dev/tty
    case "$CHOICE" in
        1)
            TARGET="crowpanel-p4-50"
            break
            ;;
        2|3|4)
            TARGET="crowpanel-p4-70-90-101"
            break
            ;;
        q|Q)
            echo "Cancelled." >&2
            exit 1
            ;;
        *)
            echo "Invalid choice. Enter 1, 2, 3, 4, or q." >&2
            ;;
    esac
done

# Store the new mapping
echo "$MAC $TARGET" >> "$MAP_FILE"
echo "Saved: $MAC → $TARGET in $(basename "$MAP_FILE")" >&2

echo "$TARGET"
