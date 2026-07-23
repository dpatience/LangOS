#!/usr/bin/env bash
# Install LangOS (patience) system-wide after building a release.
# Usage:
#   MIX_ENV=prod mix release patience
#   sudo ./scripts/install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE="$ROOT/_build/prod/rel/patience"
BIN="$RELEASE/bin/patience"

if [[ ! -x "$BIN" ]]; then
  echo "error: release not found. Run: MIX_ENV=prod mix release patience" >&2
  exit 1
fi

PREFIX="${PREFIX:-/usr/local}"
INSTALL_BIN="$PREFIX/bin/patience"
INSTALL_SHARE="$PREFIX/share/langos"

echo "Installing patience to $INSTALL_BIN ..."
install -d "$PREFIX/bin" "$INSTALL_SHARE/packs" "$INSTALL_SHARE/models" "$INSTALL_SHARE/config"
install -m 755 "$BIN" "$INSTALL_BIN"
cp -r "$ROOT/packs/"* "$INSTALL_SHARE/packs/" 2>/dev/null || true
cp -r "$ROOT/models/"* "$INSTALL_SHARE/models/" 2>/dev/null || true
cp "$ROOT/config/langos.json" "$INSTALL_SHARE/config/" 2>/dev/null || true

echo "Installed. Run first-time setup:"
echo "  patience setup"
echo "  patience serve"
