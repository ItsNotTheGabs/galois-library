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
#   GALOIS_KOREADER_ROOT  raiz KOReader customizada para remover plugin legado
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
TRANSACTION_ACTIVE=0
CORE_ACTIVE=0
CORE_HAD_OLD=0
EXT_ACTIVE=0
EXT_HAD_OLD=0
LEGACY_1_MOVED=0
LEGACY_2_MOVED=0
LEGACY_3_MOVED=0
cleanup_install() {
    rc=$?
    trap - 0 1 2 15
    if [ "$TRANSACTION_ACTIVE" -eq 1 ]; then
        if ! rollback_transaction; then
            warn "rollback incompleto; backups foram preservados para recuperação manual"
            rc=1
        fi
    fi
    if [ -n "${CORE_NEW:-}" ]; then rm -rf "$CORE_NEW"; fi
    if [ -n "${EXT_NEW:-}" ]; then rm -rf "$EXT_NEW"; fi
    rm -rf "$TMP"
    exit "$rc"
}
trap 'cleanup_install' 0
trap 'exit 1' 1 2 15

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

# Valida o artefato extraído ORIGINAL antes de tocar na instalação existente.
for REQUIRED in \
    catalog.lua cli.lua health.lua install.sh json.lua net_curl.lua settings.lua update.lua \
    sources/anna.lua sources/init.lua sources/zlib.lua \
    kual/app.lua kual/main.lua \
    kual/galoislibrary/config.xml kual/galoislibrary/menu.json \
    kual/galoislibrary/run.sh kual/galoislibrary/update.sh
do
    [ -f "$SRC/$REQUIRED" ] || die "pacote incompleto: ausente $REQUIRED"
done

# --- preparar instalação transacional ---------------------------------------
PREFIX_PARENT="$(dirname "$PREFIX")"
CORE_NEW="$PREFIX_PARENT/.galois-library.new.$$"
CORE_OLD="$PREFIX_PARENT/.galois-library.old.$$"
CORE_ACTIVE=0
CORE_HAD_OLD=0

mkdir -p "$PREFIX_PARENT" || die "não consegui preparar o destino do núcleo"
rm -rf "$CORE_NEW" "$CORE_OLD"
mkdir -p "$CORE_NEW" || die "não consegui criar staging do núcleo"
if ! cp -R "$SRC"/. "$CORE_NEW"/; then
    rm -rf "$CORE_NEW"
    die "falha ao preparar o núcleo"
fi

# Dados do usuário não pertencem ao artefato e precisam sobreviver ao swap.
for KEEP in config data; do
    if [ -d "$PREFIX/$KEEP" ]; then
        mkdir -p "$CORE_NEW/$KEEP" || {
            rm -rf "$CORE_NEW"
            die "falha ao preservar $KEEP"
        }
        cp -R "$PREFIX/$KEEP"/. "$CORE_NEW/$KEEP"/ || {
            rm -rf "$CORE_NEW"
            die "falha ao preservar $KEEP"
        }
    fi
done

if [ -n "${TAG:-}" ]; then
    printf '%s\n' "$TAG" > "$CORE_NEW/version" || {
        rm -rf "$CORE_NEW"
        die "falha ao gravar versão"
    }
else
    printf '%s\n' "$VERSION_WANT" > "$CORE_NEW/version" || {
        rm -rf "$CORE_NEW"
        die "falha ao gravar versão"
    }
fi

rollback_core() {
    if [ "$CORE_HAD_OLD" -eq 1 ] && [ ! -e "$CORE_OLD" ] && [ ! -L "$CORE_OLD" ]; then
        if [ "$CORE_ACTIVE" -eq 0 ] && { [ -e "$PREFIX" ] || [ -L "$PREFIX" ]; }; then
            CORE_HAD_OLD=0
            return 0
        fi
        return 1
    fi
    if [ "$CORE_ACTIVE" -eq 1 ]; then
        rm -rf "$PREFIX" || return 1
        if [ -e "$PREFIX" ] || [ -L "$PREFIX" ]; then return 1; fi
    fi
    if [ "$CORE_HAD_OLD" -eq 1 ]; then
        mv "$CORE_OLD" "$PREFIX" || return 1
        if [ ! -e "$PREFIX" ] && [ ! -L "$PREFIX" ]; then return 1; fi
    fi
    CORE_ACTIVE=0
    CORE_HAD_OLD=0
    return 0
}

rollback_extension() {
    [ "$MODE" = "kindle" ] || return 0
    if [ "$EXT_HAD_OLD" -eq 1 ] && [ ! -e "$EXT_OLD" ] && [ ! -L "$EXT_OLD" ]; then
        if [ "$EXT_ACTIVE" -eq 0 ] && { [ -e "$EXT" ] || [ -L "$EXT" ]; }; then
            EXT_HAD_OLD=0
            return 0
        fi
        return 1
    fi
    if [ "$EXT_ACTIVE" -eq 1 ]; then
        rm -rf "$EXT" || return 1
        if [ -e "$EXT" ] || [ -L "$EXT" ]; then return 1; fi
    fi
    if [ "$EXT_HAD_OLD" -eq 1 ]; then
        mv "$EXT_OLD" "$EXT" || return 1
        if [ ! -e "$EXT" ] && [ ! -L "$EXT" ]; then return 1; fi
    fi
    EXT_ACTIVE=0
    EXT_HAD_OLD=0
    return 0
}

rollback_legacy_plugins() {
    legacy_ok=0
    if [ "$LEGACY_1_MOVED" -eq 1 ]; then
        if [ -e "$LEGACY_1_OLD" ] || [ -L "$LEGACY_1_OLD" ]; then
            mv "$LEGACY_1_OLD" "$LEGACY_1" || legacy_ok=1
        elif [ ! -e "$LEGACY_1" ] && [ ! -L "$LEGACY_1" ]; then
            legacy_ok=1
        fi
        [ "$legacy_ok" -ne 0 ] || LEGACY_1_MOVED=0
    fi
    if [ "$LEGACY_2_MOVED" -eq 1 ]; then
        entry_ok=0
        if [ -e "$LEGACY_2_OLD" ] || [ -L "$LEGACY_2_OLD" ]; then
            mv "$LEGACY_2_OLD" "$LEGACY_2" || entry_ok=1
        elif [ ! -e "$LEGACY_2" ] && [ ! -L "$LEGACY_2" ]; then
            entry_ok=1
        fi
        [ "$entry_ok" -eq 0 ] && LEGACY_2_MOVED=0 || legacy_ok=1
    fi
    if [ "$LEGACY_3_MOVED" -eq 1 ]; then
        entry_ok=0
        if [ -e "$LEGACY_3_OLD" ] || [ -L "$LEGACY_3_OLD" ]; then
            mv "$LEGACY_3_OLD" "$LEGACY_3" || entry_ok=1
        elif [ ! -e "$LEGACY_3" ] && [ ! -L "$LEGACY_3" ]; then
            entry_ok=1
        fi
        [ "$entry_ok" -eq 0 ] && LEGACY_3_MOVED=0 || legacy_ok=1
    fi
    [ "$legacy_ok" -eq 0 ]
}

rollback_transaction() {
    rollback_ok=0
    rollback_extension || rollback_ok=1
    rollback_core || rollback_ok=1
    rollback_legacy_plugins || rollback_ok=1
    rm -rf "$CORE_NEW"
    [ "$MODE" != "kindle" ] || rm -rf "$EXT_NEW"
    [ "$rollback_ok" -eq 0 ] || return 1
    TRANSACTION_ACTIVE=0
    return 0
}

# --- preparar integração Kindle: aplicação KUAL única -----------------------
if [ "$MODE" = "kindle" ]; then
    US="${GALOIS_US_ROOT:-/mnt/us}"
    EXT_PARENT="$US/extensions"
    EXT="$EXT_PARENT/galoislibrary"
    EXT_SRC="$SRC/kual/galoislibrary"
    EXT_NEW="$EXT_PARENT/.galoislibrary.new.$$"
    EXT_OLD="$EXT_PARENT/.galoislibrary.old.$$"
    EXT_HAD_OLD=0
    LEGACY_1="$US/koreader/plugins/galoislibrary.koplugin"
    LEGACY_2="$US/plugins/galoislibrary.koplugin"
    LEGACY_3=""
    if [ -n "${GALOIS_KOREADER_ROOT:-}" ]; then
        CUSTOM_KO_ROOT="${GALOIS_KOREADER_ROOT%/}"
        case "$CUSTOM_KO_ROOT" in
            /) die "GALOIS_KOREADER_ROOT=/ é inseguro" ;;
            /*) ;;
            *) die "GALOIS_KOREADER_ROOT deve ser absoluto" ;;
        esac
        LEGACY_3="$CUSTOM_KO_ROOT/plugins/galoislibrary.koplugin"
    fi
    LEGACY_1_OLD="$LEGACY_1.galois-old.$$"
    LEGACY_2_OLD="$LEGACY_2.galois-old.$$"
    LEGACY_3_OLD="${LEGACY_3:+$LEGACY_3.galois-old.$$}"

    mkdir -p "$EXT_PARENT" || {
        rm -rf "$CORE_NEW"
        die "não consegui preparar o destino KUAL"
    }
    rm -rf "$EXT_NEW" "$EXT_OLD"
    mkdir -p "$EXT_NEW" || {
        rm -rf "$CORE_NEW"
        die "não consegui criar staging KUAL"
    }
    cp -R "$EXT_SRC"/. "$EXT_NEW"/ || {
        rm -rf "$CORE_NEW" "$EXT_NEW"
        die "falha ao preparar extensão KUAL"
    }
    printf '%s\n' "$PREFIX" > "$EXT_NEW/app_path" || {
        rm -rf "$CORE_NEW" "$EXT_NEW"
        die "falha ao configurar extensão KUAL"
    }
    chmod +x "$EXT_NEW/run.sh" "$EXT_NEW/update.sh" || {
        rm -rf "$CORE_NEW" "$EXT_NEW"
        die "scripts KUAL ausentes ou inválidos"
    }
fi

# --- ativar núcleo -----------------------------------------------------------
TRANSACTION_ACTIVE=1
if [ "$MODE" = "kindle" ]; then
    if [ -e "$LEGACY_1" ] || [ -L "$LEGACY_1" ]; then
        LEGACY_1_MOVED=1
        mv "$LEGACY_1" "$LEGACY_1_OLD" || die "não consegui preservar plugin legado: $LEGACY_1"
    fi
    if [ -e "$LEGACY_2" ] || [ -L "$LEGACY_2" ]; then
        LEGACY_2_MOVED=1
        mv "$LEGACY_2" "$LEGACY_2_OLD" || die "não consegui preservar plugin legado: $LEGACY_2"
    fi
    if [ -n "$LEGACY_3" ] && { [ -e "$LEGACY_3" ] || [ -L "$LEGACY_3" ]; }; then
        LEGACY_3_MOVED=1
        mv "$LEGACY_3" "$LEGACY_3_OLD" || die "não consegui preservar plugin legado: $LEGACY_3"
    fi
fi
if [ -e "$PREFIX" ] || [ -L "$PREFIX" ]; then
    CORE_HAD_OLD=1
    mv "$PREFIX" "$CORE_OLD" || die "não consegui preservar o núcleo anterior"
    if [ "${GALOIS_TEST_SIGNAL_AFTER_CORE_OLD_MOVE:-0}" = "1" ]; then kill -TERM "$$"; fi
fi
CORE_ACTIVE=1
mv "$CORE_NEW" "$PREFIX" || die "falha ao ativar o núcleo"
if [ "${GALOIS_TEST_SIGNAL_AFTER_CORE_NEW_MOVE:-0}" = "1" ]; then kill -TERM "$$"; fi

# Hooks exclusivos dos testes para provar rollback explícito e por sinal.
if [ "${GALOIS_TEST_FAIL_AFTER_CORE_SWAP:-0}" = "1" ]; then
    die "falha de teste após ativar núcleo"
fi
if [ "${GALOIS_TEST_SIGNAL_AFTER_CORE_SWAP:-0}" = "1" ]; then
    kill -TERM "$$"
    die "TERM de teste não interrompeu o instalador"
fi

# --- ativar extensão e concluir a transação ---------------------------------
if [ "$MODE" = "kindle" ]; then
    if [ -e "$EXT" ] || [ -L "$EXT" ]; then
        EXT_HAD_OLD=1
        mv "$EXT" "$EXT_OLD" || die "não consegui preservar a extensão KUAL anterior"
    fi
    EXT_ACTIVE=1
    mv "$EXT_NEW" "$EXT" || die "falha ao ativar extensão KUAL"
fi

# A partir daqui núcleo, extensão e caminhos legados finais estão corretos.
TRANSACTION_ACTIVE=0
CORE_ACTIVE=0
CORE_HAD_OLD=0
EXT_ACTIVE=0
EXT_HAD_OLD=0
rm -rf "$CORE_OLD"
[ "$MODE" != "kindle" ] || rm -rf "$EXT_OLD"
log "Arquivo de versão: $(cat "$PREFIX/version" 2>/dev/null || echo '?')"

if [ "$MODE" = "kindle" ]; then
    if [ "$LEGACY_1_MOVED" -eq 1 ]; then
        rm -rf "$LEGACY_1_OLD" || warn "backup legado não pôde ser apagado: $LEGACY_1_OLD"
        log "Plugin KOReader legado desativado: $LEGACY_1"
    fi
    if [ "$LEGACY_2_MOVED" -eq 1 ]; then
        rm -rf "$LEGACY_2_OLD" || warn "backup legado não pôde ser apagado: $LEGACY_2_OLD"
        log "Plugin KOReader legado desativado: $LEGACY_2"
    fi
    if [ "$LEGACY_3_MOVED" -eq 1 ]; then
        rm -rf "$LEGACY_3_OLD" || warn "backup legado não pôde ser apagado: $LEGACY_3_OLD"
        log "Plugin KOReader legado desativado: $LEGACY_3"
    fi
    LEGACY_1_MOVED=0
    LEGACY_2_MOVED=0
    LEGACY_3_MOVED=0

    # Gera o menu inicial com o runtime disponível. O updater segura o lock e
    # adia este init até liberar o lock explicitamente.
    if [ "${GALOIS_SKIP_INIT:-0}" = "1" ]; then
        log "Inicialização KUAL adiada pelo updater"
    elif "$EXT/run.sh" init; then
        log "Aplicação KUAL instalada e inicializada em $EXT"
    else
        warn "KUAL instalado, mas runtime Lua não foi encontrado; veja $EXT/galois.log"
    fi
fi

log "Concluído! Prefixo: $PREFIX  (versão $(cat "$PREFIX/version" 2>/dev/null || echo '??'))"
exit 0