#!/bin/sh
# Smoke test do layout Kindle/KUAL sem precisar de um Kindle físico.
set -eu

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT INT TERM
US="$ROOT/us"
PREFIX="$US/galois-library"
KO_ROOT="$US/koreader"
PACKAGE="${1:?use: tests/test_install_layout.sh dist/galois-library-VERSION.tar.gz}"
INSTALLER="${GALOIS_INSTALLER:-./install.sh}"

mkdir -p "$US" "$KO_ROOT/plugins"
GALOIS_MODE=kindle \
GALOIS_US_ROOT="$US" \
GALOIS_KOREADER_ROOT="$KO_ROOT" \
GALOIS_PREFIX="$PREFIX" \
GALOIS_ASSET_URL="file://$PACKAGE" \
sh "$INSTALLER" >"$ROOT/install.log" 2>&1

EXT="$US/extensions/galoislibrary"
PLUGIN="$KO_ROOT/plugins/galoislibrary.koplugin"
test -f "$EXT/config.xml"
test -f "$EXT/menu.json"
test -x "$EXT/run.sh"
test -f "$PLUGIN/main.lua"
test -f "$PLUGIN/_meta.lua"

python3 - "$EXT/menu.json" "$EXT/config.xml" <<'PY'
import json
import pathlib
import sys
menu = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert menu["items"][0]["name"] == "GaloisLibrary"
assert menu["items"][0]["action"] == "./run.sh"
xml = pathlib.Path(sys.argv[2]).read_text()
assert '<menu type="json" dynamic="true">menu.json</menu>' in xml
PY

printf 'INSTALL_LAYOUT_OK\n'
printf 'plugin=%s\n' "$PLUGIN"
printf 'kual=%s\n' "$EXT"
