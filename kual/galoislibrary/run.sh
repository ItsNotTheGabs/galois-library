#!/bin/sh
# Launcher KUAL do GaloisLibrary. Nunca falha silenciosamente.
set -u

DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
APP="${GALOIS_APP_ROOT:-}"
if [ -z "$APP" ] && [ -f "$DIR/app_path" ]; then
    APP="$(sed -n '1p' "$DIR/app_path")"
fi
APP="${APP:-/mnt/us/galois-library}"
LOG="$DIR/galois.log"

message() {
    text="$1"
    if command -v lipc-set-prop >/dev/null 2>&1; then
        lipc-set-prop com.lab126.system toasterMessage "$text" >/dev/null 2>&1 || true
    elif command -v eips >/dev/null 2>&1; then
        eips 2 2 "$text" >/dev/null 2>&1 || true
    fi
}

find_lua() {
    for candidate in \
        "${GALOIS_LUA:-}" \
        "$APP/bin/lua" \
        "$APP/bin/luajit" \
        "/mnt/us/koreader/luajit" \
        "/mnt/us/koreader/koreader/luajit"
    do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v lua >/dev/null 2>&1; then command -v lua; return 0; fi
    if command -v luajit >/dev/null 2>&1; then command -v luajit; return 0; fi
    return 1
}

mkdir -p "$DIR" "$APP/data/home" "$APP/data/kual" 2>/dev/null || true
LUA_BIN="$(find_lua || true)"
if [ -z "$LUA_BIN" ]; then
    printf '%s ERROR nenhum Lua encontrado (app=%s)\n' "$(date 2>/dev/null || true)" "$APP" >> "$LOG"
    message "GaloisLibrary: runtime Lua não encontrado. Veja galois.log."
    exit 1
fi

# KUAL dispara ações em background. Serializa leitura+escrita do estado/menu para
# impedir perda de teclas e colisões em arquivos .tmp.
LOCK="$APP/data/kual/.action.lock"
TRIES=0
EMPTY_TRIES=0
while ! mkdir "$LOCK" 2>/dev/null; do
    OWNER="$(cat "$LOCK/owner" 2>/dev/null || true)"
    case "$OWNER" in
        ''|*[!0-9]*)
            EMPTY_TRIES=$((EMPTY_TRIES + 1))
            if [ "$EMPTY_TRIES" -ge 2 ]; then
                if [ -z "$OWNER" ]; then
                    rmdir "$LOCK" 2>/dev/null && continue
                else
                    CURRENT_OWNER="$(cat "$LOCK/owner" 2>/dev/null || true)"
                    if [ "$CURRENT_OWNER" = "$OWNER" ]; then
                        rm -f "$LOCK/owner"
                        rmdir "$LOCK" 2>/dev/null || true
                        continue
                    fi
                fi
            fi
            ;;
        *)
            EMPTY_TRIES=0
            if ! kill -0 "$OWNER" 2>/dev/null; then
                rm -f "$LOCK/owner"
                rmdir "$LOCK" 2>/dev/null || true
                continue
            fi
            ;;
    esac
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -ge 60 ]; then
        printf '%s ERROR timeout aguardando lock\n' "$(date 2>/dev/null || true)" >> "$LOG"
        message "GaloisLibrary ocupado. Tente novamente."
        exit 1
    fi
    sleep 1
done
if ! printf '%s\n' "$$" > "$LOCK/owner"; then
    rmdir "$LOCK" 2>/dev/null || true
    exit 1
fi
release_lock() {
    OWNER="$(cat "$LOCK/owner" 2>/dev/null || true)"
    [ "$OWNER" = "$$" ] || return 0
    rm -f "$LOCK/owner"
    rmdir "$LOCK" 2>/dev/null || true
}
trap 'release_lock' 0
trap 'release_lock; exit 1' 1 2 15

export HOME="$APP/data/home"
export GALOIS_APP_ROOT="$APP"
export GALOIS_STATE_DIR="${GALOIS_STATE_DIR:-$APP/data/kual}"
export GALOIS_MENU_PATH="${GALOIS_MENU_PATH:-$DIR/menu.json}"
export GALOIS_DOCUMENTS_DIR="${GALOIS_DOCUMENTS_DIR:-/mnt/us/documents}"

cd "$APP" || {
    message "GaloisLibrary: pasta do app não encontrada."
    exit 1
}

printf '%s action=%s lua=%s\n' "$(date 2>/dev/null || true)" "${1:-init}" "$LUA_BIN" >> "$LOG"
"$LUA_BIN" "$APP/kual/main.lua" "$@" >> "$LOG" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    message "GaloisLibrary falhou. Veja extensions/galoislibrary/galois.log."
    exit "$rc"
fi

case "${1:-init}" in
    search|download|health)
        message "GaloisLibrary concluiu. Toque em Atualizar tela."
        ;;
esac
exit 0
