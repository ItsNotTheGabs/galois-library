#!/bin/sh
# Atualiza núcleo + extensão KUAL pelo instalador oficial.
set -u

DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
APP="${GALOIS_APP_ROOT:-}"
if [ -z "$APP" ] && [ -f "$DIR/app_path" ]; then
    APP="$(sed -n '1p' "$DIR/app_path")"
fi
APP="${APP:-/mnt/us/galois-library}"
STATE_DIR="$APP/data/kual"
LOG="$STATE_DIR/update.log"
URL="${GALOIS_INSTALLER_URL:-https://itsnotthegabs.github.io/galois-library/install.sh}"
CHECKSUM_URL="${GALOIS_CHECKSUM_URL:-https://itsnotthegabs.github.io/galois-library/dist/install.sh.sha256}"

message() {
    if command -v lipc-set-prop >/dev/null 2>&1; then
        lipc-set-prop com.lab126.system toasterMessage "$1" >/dev/null 2>&1 || true
    elif command -v eips >/dev/null 2>&1; then
        eips 2 2 "$1" >/dev/null 2>&1 || true
    fi
}

umask 077
mkdir -p "$STATE_DIR" || {
    message "GaloisLibrary: não foi possível preparar o update."
    exit 1
}
TMP_DIR=""
LOCK_DIR="$STATE_DIR/.action.lock"
LOCK_HELD=0
release_lock() {
    [ "$LOCK_HELD" -eq 1 ] || return 0
    owner="$(sed -n '1p' "$LOCK_DIR/owner" 2>/dev/null || true)"
    [ "$owner" = "$$" ] || {
        LOCK_HELD=0
        return 0
    }
    rm -f "$LOCK_DIR/owner"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=0
}
cleanup() {
    [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
    release_lock
}
trap 'cleanup' 0
trap 'cleanup; exit 1' 1 2 15

acquire_lock() {
    tries=0
    empty_tries=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        owner="$(sed -n '1p' "$LOCK_DIR/owner" 2>/dev/null || true)"
        case "$owner" in
            ''|*[!0-9]*)
                empty_tries=$((empty_tries + 1))
                if [ "$empty_tries" -ge 2 ]; then
                    if [ -z "$owner" ]; then
                        rmdir "$LOCK_DIR" 2>/dev/null && continue
                    else
                        current_owner="$(sed -n '1p' "$LOCK_DIR/owner" 2>/dev/null || true)"
                        if [ "$current_owner" = "$owner" ]; then
                            rm -f "$LOCK_DIR/owner"
                            rmdir "$LOCK_DIR" 2>/dev/null || true
                            continue
                        fi
                    fi
                fi
                ;;
            *)
                empty_tries=0
                if ! kill -0 "$owner" 2>/dev/null; then
                    rm -f "$LOCK_DIR/owner"
                    rmdir "$LOCK_DIR" 2>/dev/null || true
                    continue
                fi
                ;;
        esac
        tries=$((tries + 1))
        [ "$tries" -lt 180 ] || return 1
        sleep 1
    done
    if ! printf '%s\n' "$$" > "$LOCK_DIR/owner"; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
        return 1
    fi
    LOCK_HELD=1
    return 0
}

message "GaloisLibrary: aguardando ações em andamento..."
if ! acquire_lock; then
    message "GaloisLibrary: tempo esgotado aguardando o aplicativo."
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/galois-update.XXXXXX)" || {
    message "GaloisLibrary: falha ao criar diretório temporário."
    exit 1
}
INSTALLER="$TMP_DIR/install.sh"
CHECKSUM="$TMP_DIR/install.sh.sha256"

message "GaloisLibrary: baixando atualização..."
if ! curl -fsSL -m 60 -o "$INSTALLER" "$URL" >> "$LOG" 2>&1; then
    message "GaloisLibrary: falha ao baixar atualização."
    exit 1
fi
if ! curl -fsSL -m 30 -o "$CHECKSUM" "$CHECKSUM_URL" >> "$LOG" 2>&1; then
    message "GaloisLibrary: falha ao baixar checksum."
    exit 1
fi

EXPECTED="$(sed -n '1{s/[[:space:]].*//;p;}' "$CHECKSUM")"
case "$EXPECTED" in
    ''|*[!0-9A-Fa-f]*)
        message "GaloisLibrary: checksum publicado inválido."
        exit 1
        ;;
esac
[ "${#EXPECTED}" -eq 64 ] || {
    message "GaloisLibrary: checksum publicado inválido."
    exit 1
}

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "$INSTALLER" | sed 's/[[:space:]].*//')"
elif command -v openssl >/dev/null 2>&1; then
    ACTUAL="$(openssl dgst -sha256 "$INSTALLER" | sed 's/.*= //')"
else
    message "GaloisLibrary: SHA-256 indisponível no Kindle."
    exit 1
fi
if [ "$ACTUAL" != "$EXPECTED" ]; then
    printf '%s ERROR checksum esperado=%s obtido=%s\n' "$(date 2>/dev/null || true)" "$EXPECTED" "$ACTUAL" >> "$LOG"
    message "GaloisLibrary: checksum da atualização não confere."
    exit 1
fi

if ! sh -n "$INSTALLER" >> "$LOG" 2>&1; then
    message "GaloisLibrary: instalador baixado é inválido."
    exit 1
fi
INSTALL_LOG="$TMP_DIR/install.log"
if ! GALOIS_PREFIX="$APP" GALOIS_SKIP_INIT=1 sh "$INSTALLER" > "$INSTALL_LOG" 2>&1; then
    cat "$INSTALL_LOG" >> "$LOG" 2>/dev/null || true
    message "GaloisLibrary: falha ao instalar atualização."
    exit 1
fi
cat "$INSTALL_LOG" >> "$LOG" 2>/dev/null || {
    message "GaloisLibrary: atualização instalada, mas o log não foi preservado."
    exit 1
}
release_lock
if ! "$DIR/run.sh" init >> "$LOG" 2>&1; then
    message "GaloisLibrary atualizado, mas a inicialização falhou."
    exit 1
fi
message "GaloisLibrary atualizado. Reabra o KUAL."
