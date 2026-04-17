#!/usr/bin/env bash
# Compatibility wrapper for users expecting an explicit mklittlefs step.
# Delegates to PlatformIO buildfs target.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/buildfs.sh" "$@"
