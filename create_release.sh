#!/bin/sh
# ============================================================================
# create_release.sh — empacota a release do GaloisLibrary para o instalador curl|sh
#
# Uso:
#   ./create_release.sh [versão]        # default: lê VERSION (ou 0.1.0)
#
# Gera:
#   dist/galois-library-<ver>.tar.gz   (raiz = núcleo Lua + app KUAL)
#   dist/release.json                  (tag_name + tarball_url, formato do update.lua)
#
# Publicar: suba o .tar.gz e o release.json para o seu host (ex.: páginas de
# release do GitHub) e use GALOIS_REPO/GALOIS_ASSET_URL no instalador.
# ============================================================================
set -eu

VER="${1:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
[ -n "$VER" ] || VER="0.1.0"
PAGES_BASE="${GALOIS_PAGES_BASE:-https://itsnotthegabs.github.io/galois-library}"
PAGES_BASE="${PAGES_BASE%/}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

OUT="galois-library-$VER.tar.gz"
STAGE=".release-stage-$$"
mkdir -p "$STAGE" dist

log(){ printf '\033[1;32m[release]\033[0m %s\n' "$*"; }

# monta a árvore (raíz sem o dir envolvente)
cp -r sources settings.lua catalog.lua health.lua json.lua net_curl.lua \
      update.lua cli.lua install.sh kual README.md "$STAGE/" 2>/dev/null
printf '%s\n' "$VER" > "$STAGE/version"

tar -czf "dist/$OUT" -C "$STAGE" .
rm -rf "$STAGE"
sha256sum install.sh > dist/install.sh.sha256

# release.json no formato que update.lua consome
printf '{"tag_name":"v%s","tarball_url":"%s/dist/%s"}\n' "$VER" "$PAGES_BASE" "$OUT" > dist/release.json

log "Release: dist/$OUT"
log "  release.json: v$VER -> dist/$OUT"
log "Host: publique dist/* e use:"
log "  curl -sSL <host>/install.sh | GALOIS_ASSET_URL=<host>/dist/$OUT sh"