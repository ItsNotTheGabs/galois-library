#!/bin/sh
# ============================================================================
# GaloisLibrary — instalador / atualizador via curl|sh
#
#   curl -sSL https://HOST/galois-library/install.sh | sh
#
# Detecta o ambiente:
#   - Kindle jailbreakeado  -> instala em /mnt/us/... (extensão KUAL + núcleo)
#   - Desktop Linux         -> ~/.local/share/galois-library
#
# Configuração por env (para mirrors/repo próprios):
#   GALOIS_REPO       "owner/repo" (GitHub) ou URL direta de release.json
#                     (default: ItsNotTheGabs/galois-library)
#   GALOIS_ASSET_URL  URL direta do tarball (dispensa a consulta à API)
#   GALOIS_PREFIX     destino alternativo (testes)
#   GALOIS_VERSION    versão a instalar (default: latest)
# ============================================================================
set -u

log()  { printf '\033[1;32m[Galois]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[Galois]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[Galois] ERRO:\033[0m %s\n' "$*" >&2; exit 1; }

REPO="${GALOIS_REPO:-ItsNotTheGabs/galois-library}"
ASSET_URL="${GALOIS_ASSET_URL:-}"
VERSION_WANT="${GALOIS_VERSION:-latest}"

# ---- destino --------------------------------------------------------------
MODE="${GALOIS_MODE:-auto}"
if [ "$MODE" = "auto" ]; then
    if [ -d /mnt/us ] && [ -w /mnt/us ]; then
        MODE="kindle"
    else
        MODE="desktop"
    fi
fi
if [ "$MODE" = "kindle" ]; then
    PREFIX="${GALOIS_PREFIX:-/mnt/us/galois-library}"
else
    PREFIX="${GALOIS_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/galois-library}"
fi
log "Ambiente: $MODE  ->  $PREFIX"

command -v curl >/dev/null 2>&1 || die "curl é necessário"
command -v tar  >/dev/null 2>&1 || die "tar é necessário"

TMP="$(mktemp -d)" || die "non conseguín crear tmp"
trap 'rm -rf "$TMP"' EXIT INT TERM

# --- descobrir release ------------------------------------------------
if [ -z "$ASSET_URL" ]; then
    log "Consultando release latest de $REPO ..."
    if printf '%s' "$REPO" | grep -q '://'; then
        RELEASE_URL="$REPO"
    else
        RELEASE_URL="https://api.github.com/repos/$REPO/releases/latest"
    fi
    RELEASE_JSON="$(curl -sfL -m 30 -A 'galois-library-installer' "$RELEASE_URL")" \
        || die "não consegui consultar a release ($RELEASE_URL)"
    TAG="$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [ -z "$TAG" ]; then
        # fallback: parse simples da primeira linha com tag_name
        TAG="$(printf '%s' "$RELEASE_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    fi
    [ -n "$TAG" ] || die "release sem tag_name"
    log "Release encontrada: $TAG"

    # asset .tar.gz na release, se houver; senão, tarball de source do GitHub
    ASSET_URL="$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"tarball_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [ -z "$ASSET_URL" ]; then
        ASSET_URL="$(printf '%s' "$RELEASE_JSON" | grep -o '"tarball_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    fi
    [ -n "$ASSET_URL" ] || ASSET_URL="https://api.github.com/repos/$REPO/tarball/$TAG"
else
    TAG="${VERSION_WANT:-manual}"
    log "Asset direto configurado (tag=$TAG)"
fi

# --- baixar e extrair --------------------------------------------------
log "Baixando $ASSET_URL ..."
curl -sfL -m 120 -o "$TMP/release.tar.gz" "$ASSET_URL" || die "falha no download do artefato"
[ -s "$TMP/release.tar.gz" ] || die "artefato vazio"

mkdir -p "$TMP/x"
tar -xzf "$TMP/release.tar.gz" -C "$TMP/x" || die "falha ao extrair tarball"

# O tarball do GitHub tem um top-level dir (repo-tag-hash/); normalizamos.
SRC="$TMP/x"
if [ "$(ls -1 "$TMP/x" | wc -l)" -eq 1 ] && [ -d "$TMP/x"/* ]; then
    SRC="$TMP/x/$(ls -1 "$TMP/x" | head -1)"
fi

# --- instalar ---------------------------------------------------------
mkdir -p "$PREFIX"
cp -a "$SRC"/. "$PREFIX"/ 2>/dev/null || { cp -r "$SRC"/* "$PREFIX"/ 2>/dev/null || {
    # último recurso: copiar arquivo a arquivo
    (cd "$SRC" && for f in *; do [ -e "$f" ] && cp -r "$f" "$PREFIX/"; done)
}; }

# arquivo de versão
if [ -n "${TAG:-}" ]; then
    printf '%s\n' "$TAG" > "$PREFIX/version"
else
    printf '%s\n' "$VERSION_WANT" > "$PREFIX/version"
fi
log "Arquivo de versão: $(cat "$PREFIX/version" 2>/dev/null || echo '?')"

# --- integração Kindle (KUAL + plugin KOReader) ---------------------------
if [ "$MODE" = "kindle" ]; then
    US="${GALOIS_US_ROOT:-/mnt/us}"   # raiz da partição de usuário (testável)
    EXT="$US/extensions/galoislibrary"
    mkdir -p "$EXT"
    cat > "$EXT/menu.json" <<EOF
{
  "items": [
    {"name": "GaloisLibrary", "action": "sh run.sh"}
  ]
}
EOF
    cat > "$EXT/run.sh" <<'EOF'
#!/bin/sh
# Abre o app (via kterm se existir; senão mostra instruções).
if [ -x /mnt/us/kterm/bin/kterm.sh ]; then
    cd /mnt/us/galois-library && /mnt/us/kterm/bin/kterm.sh -e sh -c 'echo "GaloisLibrary: use KOReader > menu > GaloisLibrary"; echo "ou: lua cli.lua search <query>"; read x' 2>/dev/null
else
    echo "Abra o KOReader -> menu -> GaloisLibrary" > /tmp/galois_hint
fi
EOF
    chmod +x "$EXT/run.sh"
    log "Extensão KUAL registrada em $EXT"

    # plugin KOReader -> plugins/galoislibrary.koplugin
    # (é o que faz o GaloisLibrary aparecer no menu do KOReader)
    if [ -d "$PREFIX/koplugin/galoislibrary.koplugin" ]; then
        KOPLUG="$US/plugins/galoislibrary.koplugin"
        rm -rf "$KOPLUG"
        mkdir -p "$(dirname "$KOPLUG")"
        cp -r "$PREFIX/koplugin/galoislibrary.koplugin" "$KOPLUG"
        log "Plugin KOReader instalado em $KOPLUG (reinicie o KOReader)"
    else
        warn "aviso: $PREFIX/koplugin/galoislibrary.koplugin não encontrado (está no release?)"
    fi
fi

# --- auto-verificação de versão (health/update) --------------------------
if [ -x "$PREFIX/cli.lua" ] && command -v lua >/dev/null 2>&1; then
    cd "$PREFIX" && lua cli.lua health --all >/tmp/galois_health.msg 2>&1 || true
fi

log "Concluído! Prefixo: $PREFIX  (versão $(cat "$PREFIX/version" 2>/dev/null || echo '??'))"
exit 0