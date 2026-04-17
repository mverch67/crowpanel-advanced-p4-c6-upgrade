#!/usr/bin/env bash
# Download the latest ESP32-C6 network adapter firmware from the ESPHome
# esp-hosted-firmware GitHub Pages release and place it in data/ for LittleFS packaging.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$PROJECT_DIR/data"

TARGET="esp32c6"
FILENAME="network_adapter_${TARGET}.bin"
API_URL="https://api.github.com/repos/esphome/esp-hosted-firmware/releases/latest"

echo "Fetching latest esp-hosted-firmware release tag..."
LATEST_TAG=$(curl -fsSL "$API_URL" \
    | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])")
echo "Latest release: $LATEST_TAG"

DOWNLOAD_URL="https://esphome.github.io/esp-hosted-firmware/${LATEST_TAG}/${FILENAME}"
mkdir -p "$DATA_DIR"
OUTPUT="$DATA_DIR/$FILENAME"

echo "Downloading $DOWNLOAD_URL ..."
curl -fL --progress-bar -o "$OUTPUT" "$DOWNLOAD_URL"

# Optional SHA256 verification via a CHECKSUMS or SHA256SUMS file if available.
SHA_URL="https://esphome.github.io/esp-hosted-firmware/${LATEST_TAG}/SHA256SUMS"
if curl -fsSL "$SHA_URL" -o /tmp/esp_hosted_sha256sums 2>/dev/null; then
    EXPECTED=$(grep "$FILENAME" /tmp/esp_hosted_sha256sums | awk '{print $1}' | head -1)
    if [ -n "$EXPECTED" ]; then
        ACTUAL=$(sha256sum "$OUTPUT" | awk '{print $1}')
        if [ "$ACTUAL" = "$EXPECTED" ]; then
            echo "SHA256 verified: $ACTUAL"
        else
            echo "ERROR: SHA256 mismatch!"
            echo "  expected: $EXPECTED"
            echo "  actual:   $ACTUAL"
            rm -f "$OUTPUT"
            exit 1
        fi
    else
        echo "No checksum entry found for $FILENAME — skipping verification."
    fi
else
    echo "(No SHA256SUMS file found — skipping verification.)"
fi

echo ""
echo "Saved: $OUTPUT"
echo ""
echo "Next steps:"
echo "  bin/buildfs.sh          # package data/ into LittleFS image"
echo "  bin/upload_fs.sh        # flash the storage partition"
echo "  bin/flash.sh            # flash the app firmware"
