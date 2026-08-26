#!/bin/sh
# Smoke test do layout Kindle KUAL-only sem precisar de um Kindle físico.
set -eu

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT INT TERM
US="$ROOT/us"
PREFIX="$US/galois-library"
PACKAGE="${1:?use: tests/test_install_layout.sh dist/galois-library-VERSION.tar.gz}"
RELEASE_JSON="${GALOIS_RELEASE_JSON:-$(dirname "$PACKAGE")/release.json}"
INSTALLER="${GALOIS_INSTALLER:-./install.sh}"

# Simula resíduos das versões 0.1.x que o upgrade deve remover.
CUSTOM_KO="$ROOT/custom-koreader"
mkdir -p "$US/koreader/plugins/galoislibrary.koplugin" \
    "$US/plugins" \
    "$CUSTOM_KO/plugins/galoislibrary.koplugin"
printf old > "$US/koreader/plugins/galoislibrary.koplugin/main.lua"
ln -s /destino-legado-inexistente "$US/plugins/galoislibrary.koplugin"
printf old > "$CUSTOM_KO/plugins/galoislibrary.koplugin/main.lua"

GALOIS_MODE=kindle \
GALOIS_US_ROOT="$US" \
GALOIS_KOREADER_ROOT="$CUSTOM_KO" \
GALOIS_PREFIX="$PREFIX" \
GALOIS_ASSET_URL="file://$PACKAGE" \
sh "$INSTALLER" >"$ROOT/install.log" 2>&1

EXT="$US/extensions/galoislibrary"
test -f "$EXT/config.xml"
test -f "$EXT/menu.json"
test -x "$EXT/run.sh"
test -f "$EXT/app_path"
test -f "$PREFIX/kual/app.lua"
test -f "$PREFIX/kual/main.lua"

# KOReader foi descontinuado: upgrade remove resíduos e não reinstala plugin.
test ! -e "$US/koreader/plugins/galoislibrary.koplugin"
test ! -e "$US/plugins/galoislibrary.koplugin"
test ! -L "$US/plugins/galoislibrary.koplugin"
test ! -e "$CUSTOM_KO/plugins/galoislibrary.koplugin"
test ! -e "$PREFIX/koplugin"

python3 - "$EXT/menu.json" "$EXT/config.xml" "$EXT/app_path" "$PACKAGE" "$RELEASE_JSON" <<'PY'
import json
import pathlib
import sys
import tarfile
menu = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert menu["items"][0]["name"] == "GaloisLibrary"
assert "items" in menu["items"][0]
assert "action" not in menu["items"][0]
labels = [item["name"] for item in menu["items"][0]["items"]]
assert any(label.startswith("Consulta:") for label in labels)
assert "Pesquisar" in labels
xml = pathlib.Path(sys.argv[2]).read_text()
assert "<id>galoislibrary</id>" in xml
assert '<menu type="json" dynamic="true">menu.json</menu>' in xml
assert pathlib.Path(sys.argv[3]).read_text().strip().endswith("/galois-library")
release = json.loads(pathlib.Path(sys.argv[5]).read_text())
assert release["tag_name"].startswith("v")
assert release["tarball_url"].startswith("https://itsnotthegabs.github.io/galois-library/dist/")
with tarfile.open(sys.argv[4], "r:gz") as tf:
    names = {name.lstrip("./") for name in tf.getnames()}
    def member_text(path):
        member = next(m for m in tf.getmembers() if m.name.lstrip("./") == path)
        return tf.extractfile(member).read().decode()
    run_sh = member_text("kual/galoislibrary/run.sh")
    update_sh = member_text("kual/galoislibrary/update.sh")
assert not any(name == "koplugin" or name.startswith("koplugin/") for name in names)
assert "kual/galoislibrary/run.sh" in names
assert "kual/app.lua" in names
assert "cd --" not in run_sh and "dirname --" not in run_sh
assert "cd --" not in update_sh and "dirname --" not in update_sh
assert "/tmp/galois-install-$$.sh" not in update_sh
assert "mktemp -d" in update_sh
assert "umask 077" in update_sh
assert "trap 'cleanup'" in update_sh
assert 'STATE_DIR="$APP/data/kual"' in update_sh
assert 'LOG="$STATE_DIR/update.log"' in update_sh
assert "sha256sum" in update_sh
assert "GALOIS_INSTALLER_URL" in update_sh
assert "GALOIS_CHECKSUM_URL" in update_sh
assert ".action.lock" in update_sh
assert '"$LOCK/owner"' in run_sh and '"$LOCK/pid"' not in run_sh
assert 'GALOIS_PREFIX="$APP"' in update_sh
assert "GALOIS_SKIP_INIT=1" in update_sh
checksum_path = pathlib.Path(sys.argv[5]).parent / "install.sh.sha256"
assert checksum_path.is_file()
checksum_parts = checksum_path.read_text().split()
assert len(checksum_parts) >= 2 and checksum_parts[1] == "install.sh"
import hashlib
assert hashlib.sha256(pathlib.Path("install.sh").read_bytes()).hexdigest() == checksum_parts[0]
PY

# Upgrade bem-sucedido preserva configuração e dados gerados pelo usuário.
mkdir -p "$PREFIX/config" "$PREFIX/data/user"
printf '%s\n' "anna=enabled" > "$PREFIX/config/sources.cfg"
printf '%s\n' "biblioteca-local" > "$PREFIX/data/user/sentinel"
GALOIS_MODE=kindle \
GALOIS_US_ROOT="$US" \
GALOIS_PREFIX="$PREFIX" \
GALOIS_ASSET_URL="file://$PACKAGE" \
GALOIS_VERSION=v0.2.0-preserve \
sh "$INSTALLER" >"$ROOT/preserve-install.log" 2>&1
test "$(cat "$PREFIX/config/sources.cfg")" = "anna=enabled"
test "$(cat "$PREFIX/data/user/sentinel")" = "biblioteca-local"

# E2E do updater seguro: download local, checksum, sh -n, execução e log persistente.
UPDATE_FIXTURE="$ROOT/update-fixture"
UPDATE_MARKER="$ROOT/update-ran"
mkdir -p "$UPDATE_FIXTURE"
printf '%s\n' '#!/bin/sh' 'set -eu' 'printf updated > "$GALOIS_UPDATE_MARKER"' > "$UPDATE_FIXTURE/install.sh"
(
    cd "$UPDATE_FIXTURE"
    sha256sum install.sh > install.sh.sha256
)
UPDATE_LOCK="$PREFIX/data/kual/.action.lock"
mkdir -p "$UPDATE_LOCK"
printf '%s\n' "$$" > "$UPDATE_LOCK/owner"
GALOIS_APP_ROOT="$PREFIX" \
GALOIS_INSTALLER_URL="file://$UPDATE_FIXTURE/install.sh" \
GALOIS_CHECKSUM_URL="file://$UPDATE_FIXTURE/install.sh.sha256" \
GALOIS_UPDATE_MARKER="$UPDATE_MARKER" \
"$EXT/update.sh" &
UPDATE_PID=$!
UPDATE_WAIT=0
while kill -0 "$UPDATE_PID" 2>/dev/null && [ "$UPDATE_WAIT" -lt 40 ]; do
    [ ! -e "$UPDATE_MARKER" ] || {
        printf '%s\n' "updater ignorou o lock das ações" >&2
        exit 1
    }
    UPDATE_WAIT=$((UPDATE_WAIT + 1))
    sleep 0.05
done
test ! -e "$UPDATE_MARKER"
rm -f "$UPDATE_LOCK/owner"
rmdir "$UPDATE_LOCK"
wait "$UPDATE_PID"
test "$(cat "$UPDATE_MARKER")" = "updated"
test -f "$PREFIX/data/kual/update.log"

# Diretório de lock sem owner (crash entre mkdir e write) deve ser recuperado.
rm -f "$UPDATE_MARKER"
mkdir -p "$PREFIX/data/kual/.action.lock"
GALOIS_APP_ROOT="$PREFIX" \
GALOIS_INSTALLER_URL="file://$UPDATE_FIXTURE/install.sh" \
GALOIS_CHECKSUM_URL="file://$UPDATE_FIXTURE/install.sh.sha256" \
GALOIS_UPDATE_MARKER="$UPDATE_MARKER" \
"$EXT/update.sh"
test "$(cat "$UPDATE_MARKER")" = "updated"

# run.sh reaproveita o mesmo protocolo e remove lock órfão criado pelo updater.
ORPHAN_LOCK="$PREFIX/data/kual/.action.lock"
mkdir -p "$ORPHAN_LOCK"
printf '%s\n' "999999" > "$ORPHAN_LOCK/owner"
"$EXT/run.sh" key Z &
ORPHAN_PID=$!
ORPHAN_WAIT=0
while kill -0 "$ORPHAN_PID" 2>/dev/null && [ "$ORPHAN_WAIT" -lt 40 ]; do
    ORPHAN_WAIT=$((ORPHAN_WAIT + 1))
    sleep 0.05
done
if kill -0 "$ORPHAN_PID" 2>/dev/null; then
    kill "$ORPHAN_PID" 2>/dev/null || true
    wait "$ORPHAN_PID" 2>/dev/null || true
    printf '%s\n' "run.sh não removeu lock owner órfão" >&2
    exit 1
fi
wait "$ORPHAN_PID"

mkdir -p "$ORPHAN_LOCK"
"$EXT/run.sh" key W &
OWNERLESS_RUN_PID=$!
OWNERLESS_RUN_WAIT=0
while kill -0 "$OWNERLESS_RUN_PID" 2>/dev/null && [ "$OWNERLESS_RUN_WAIT" -lt 40 ]; do
    OWNERLESS_RUN_WAIT=$((OWNERLESS_RUN_WAIT + 1))
    sleep 0.1
done
if kill -0 "$OWNERLESS_RUN_PID" 2>/dev/null; then
    kill "$OWNERLESS_RUN_PID" 2>/dev/null || true
    wait "$OWNERLESS_RUN_PID" 2>/dev/null || true
    printf '%s\n' "run.sh não removeu lock sem owner" >&2
    exit 1
fi
wait "$OWNERLESS_RUN_PID"

# Updater real: prefixo customizado, sem deadlock no init e log completo pós-swap.
REAL_WRAPPER="$ROOT/real-installer-wrapper.sh"
printf '%s\n' \
    '#!/bin/sh' \
    '[ "${GALOIS_PREFIX:-}" = "$EXPECTED_PREFIX" ] || exit 41' \
    'exec sh "$REAL_INSTALLER"' > "$REAL_WRAPPER"
REAL_CHECKSUM="$ROOT/real-installer-wrapper.sha256"
printf '%s  install.sh\n' "$(sha256sum "$REAL_WRAPPER" | sed 's/[[:space:]].*//')" > "$REAL_CHECKSUM"
GALOIS_APP_ROOT="$PREFIX" \
GALOIS_INSTALLER_URL="file://$REAL_WRAPPER" \
GALOIS_CHECKSUM_URL="file://$REAL_CHECKSUM" \
GALOIS_ASSET_URL="file://$PACKAGE" \
GALOIS_MODE=kindle \
GALOIS_US_ROOT="$US" \
EXPECTED_PREFIX="$PREFIX" \
REAL_INSTALLER="$INSTALLER" \
"$EXT/update.sh" &
REAL_UPDATE_PID=$!
REAL_UPDATE_WAIT=0
while kill -0 "$REAL_UPDATE_PID" 2>/dev/null && [ "$REAL_UPDATE_WAIT" -lt 60 ]; do
    REAL_UPDATE_WAIT=$((REAL_UPDATE_WAIT + 1))
    sleep 0.1
done
if kill -0 "$REAL_UPDATE_PID" 2>/dev/null; then
    kill "$REAL_UPDATE_PID" 2>/dev/null || true
    wait "$REAL_UPDATE_PID" 2>/dev/null || true
    printf '%s\n' "updater real travou aguardando o próprio lock" >&2
    exit 1
fi
if ! wait "$REAL_UPDATE_PID"; then
    printf '%s\n' "updater real falhou no prefixo customizado" >&2
    exit 1
fi
grep -q 'Concluído! Prefixo:' "$PREFIX/data/kual/update.log"
grep -q 'action=init' "$EXT/galois.log"

# Falha depois de ativar o novo núcleo deve restaurar núcleo e extensão anteriores.
GOOD_RUN_SUM="$(cksum "$EXT/run.sh")"
GOOD_CATALOG_SUM="$(cksum "$PREFIX/catalog.lua")"
GOOD_VERSION="$(cat "$PREFIX/version")"
ROLL_ROOT="$ROOT/rollback-package"
ROLL_TAR="$ROOT/rollback-package.tar.gz"
mkdir -p "$ROLL_ROOT"
tar -xzf "$PACKAGE" -C "$ROLL_ROOT"
printf '%s\n' '-- conteúdo novo que não pode sobreviver ao rollback' >> "$ROLL_ROOT/catalog.lua"
tar -czf "$ROLL_TAR" -C "$ROLL_ROOT" .
ROLL_LOG="$ROOT/rollback-install.log"
if GALOIS_MODE=kindle \
   GALOIS_US_ROOT="$US" \
   GALOIS_PREFIX="$PREFIX" \
   GALOIS_ASSET_URL="file://$ROLL_TAR" \
   GALOIS_VERSION=v0.2.0-rollback \
   GALOIS_TEST_FAIL_AFTER_CORE_SWAP=1 \
   sh "$INSTALLER" >"$ROLL_LOG" 2>&1; then
    printf '%s\n' "falha injetada não interrompeu o instalador" >&2
    exit 1
fi
test "$(cksum "$EXT/run.sh")" = "$GOOD_RUN_SUM"
test "$(cksum "$PREFIX/catalog.lua")" = "$GOOD_CATALOG_SUM"
test "$(cat "$PREFIX/version")" = "$GOOD_VERSION"

SIGNAL_LOG="$ROOT/signal-install.log"
if GALOIS_MODE=kindle \
   GALOIS_US_ROOT="$US" \
   GALOIS_PREFIX="$PREFIX" \
   GALOIS_ASSET_URL="file://$ROLL_TAR" \
   GALOIS_VERSION=v0.2.0-signal \
   GALOIS_TEST_SIGNAL_AFTER_CORE_SWAP=1 \
   sh "$INSTALLER" >"$SIGNAL_LOG" 2>&1; then
    printf '%s\n' "TERM injetado não interrompeu o instalador" >&2
    exit 1
fi
test "$(cksum "$EXT/run.sh")" = "$GOOD_RUN_SUM"
test "$(cksum "$PREFIX/catalog.lua")" = "$GOOD_CATALOG_SUM"
test "$(cat "$PREFIX/version")" = "$GOOD_VERSION"

for SIGNAL_HOOK in GALOIS_TEST_SIGNAL_AFTER_CORE_OLD_MOVE GALOIS_TEST_SIGNAL_AFTER_CORE_NEW_MOVE; do
    WINDOW_LOG="$ROOT/$SIGNAL_HOOK.log"
    if env \
       GALOIS_MODE=kindle \
       GALOIS_US_ROOT="$US" \
       GALOIS_PREFIX="$PREFIX" \
       GALOIS_ASSET_URL="file://$ROLL_TAR" \
       GALOIS_VERSION=v0.2.0-window \
       "$SIGNAL_HOOK=1" \
       sh "$INSTALLER" >"$WINDOW_LOG" 2>&1; then
        printf '%s\n' "$SIGNAL_HOOK não interrompeu o instalador" >&2
        exit 1
    fi
    test "$(cksum "$EXT/run.sh")" = "$GOOD_RUN_SUM"
    test "$(cksum "$PREFIX/catalog.lua")" = "$GOOD_CATALOG_SUM"
    test "$(cat "$PREFIX/version")" = "$GOOD_VERSION"
done

INVALID_ROOT_LOG="$ROOT/invalid-root-install.log"
if GALOIS_MODE=kindle \
   GALOIS_US_ROOT="$US" \
   GALOIS_PREFIX="$PREFIX" \
   GALOIS_KOREADER_ROOT="raiz-relativa" \
   GALOIS_ASSET_URL="file://$ROLL_TAR" \
   sh "$INSTALLER" >"$INVALID_ROOT_LOG" 2>&1; then
    printf '%s\n' "raiz KOReader relativa foi aceita" >&2
    exit 1
fi
test "$(cksum "$EXT/run.sh")" = "$GOOD_RUN_SUM"
test "$(cksum "$PREFIX/catalog.lua")" = "$GOOD_CATALOG_SUM"
for INVALID_LEFTOVER in "$US"/.galois-library.new.* "$US/extensions"/.galoislibrary.new.*; do
    if [ -e "$INVALID_LEFTOVER" ] || [ -L "$INVALID_LEFTOVER" ]; then
        printf '%s\n' "preflight inválido deixou staging: $INVALID_LEFTOVER" >&2
        exit 1
    fi
done

LEGACY_FAIL_PARENT="$US/koreader/plugins"
LEGACY_FAIL_PATH="$LEGACY_FAIL_PARENT/galoislibrary.koplugin"
mkdir -p "$LEGACY_FAIL_PATH"
printf '%s\n' "legado" > "$LEGACY_FAIL_PATH/main.lua"
chmod 500 "$LEGACY_FAIL_PARENT"
LEGACY_FAIL_LOG="$ROOT/legacy-fail-install.log"
if GALOIS_MODE=kindle \
   GALOIS_US_ROOT="$US" \
   GALOIS_PREFIX="$PREFIX" \
   GALOIS_ASSET_URL="file://$ROLL_TAR" \
   sh "$INSTALLER" >"$LEGACY_FAIL_LOG" 2>&1; then
    chmod 700 "$LEGACY_FAIL_PARENT"
    printf '%s\n' "falha de migração legada foi ignorada" >&2
    exit 1
fi
chmod 700 "$LEGACY_FAIL_PARENT"
test -f "$LEGACY_FAIL_PATH/main.lua"
test "$(cksum "$EXT/run.sh")" = "$GOOD_RUN_SUM"
test "$(cksum "$PREFIX/catalog.lua")" = "$GOOD_CATALOG_SUM"
rm -rf "$LEGACY_FAIL_PATH"

# CLI não pode anunciar toggle quando sources.cfg não pôde ser persistido.
CLI_BAD_HOME="$ROOT/home-nao-diretorio"
printf '%s\n' "arquivo" > "$CLI_BAD_HOME"
CLI_LOG="$ROOT/cli-toggle.log"
if HOME="$CLI_BAD_HOME" lua cli.lua toggle zlib off > "$CLI_LOG" 2>&1; then
    printf '%s\n' "CLI anunciou toggle apesar da falha de persistência" >&2
    exit 1
fi
grep -q 'falha' "$CLI_LOG"

# Um pacote incompleto deve ser rejeitado antes de alterar a instalação válida.
BAD_ROOT="$ROOT/bad-package"
BAD_TAR="$ROOT/bad-package.tar.gz"
mkdir -p "$BAD_ROOT/kual/galoislibrary"
printf '%s\n' '-- pacote propositalmente incompleto' > "$BAD_ROOT/catalog.lua"
cp "$EXT/config.xml" "$BAD_ROOT/kual/galoislibrary/config.xml"
tar -czf "$BAD_TAR" -C "$BAD_ROOT" .
BAD_LOG="$ROOT/bad-install.log"
if GALOIS_MODE=kindle \
   GALOIS_US_ROOT="$US" \
   GALOIS_PREFIX="$PREFIX" \
   GALOIS_ASSET_URL="file://$BAD_TAR" \
   GALOIS_VERSION=v0.2.0-bad \
   sh "$INSTALLER" >"$BAD_LOG" 2>&1; then
    printf 'pacote incompleto foi aceito\n' >&2
    exit 1
fi
case "$(cat "$BAD_LOG")" in
    *"pacote incompleto:"*) ;;
    *) printf 'falha não ocorreu no preflight do pacote\n' >&2; exit 1 ;;
esac
test "$(cksum "$EXT/run.sh")" = "$GOOD_RUN_SUM"
test "$(cksum "$PREFIX/catalog.lua")" = "$GOOD_CATALOG_SUM"
test "$(cat "$PREFIX/version")" = "$GOOD_VERSION"

# Executa o launcher real contra o Lua desktop e confirma regeneração dinâmica.
GALOIS_LUA="$(command -v lua)" GALOIS_STATE_DIR="$ROOT/state" "$EXT/run.sh" init
for key in D U N E; do
    GALOIS_LUA="$(command -v lua)" GALOIS_STATE_DIR="$ROOT/state" "$EXT/run.sh" key "$key"
done
python3 -m json.tool "$EXT/menu.json" >/dev/null
python3 - "$EXT/menu.json" <<'PY'
import json, pathlib, sys
menu = json.loads(pathlib.Path(sys.argv[1]).read_text())
labels = [item["name"] for item in menu["items"][0]["items"]]
assert "Consulta: DUNE" in labels
PY

# KUAL executa ações em background. Vários toques não podem perder estado nem
# colidir nos arquivos .tmp usados pela persistência/menu.
GALOIS_LUA="$(command -v lua)" GALOIS_STATE_DIR="$ROOT/state" "$EXT/run.sh" clear
PIDS=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    GALOIS_LUA="$(command -v lua)" GALOIS_STATE_DIR="$ROOT/state" "$EXT/run.sh" key A &
    PIDS="$PIDS $!"
done
FAILED=0
for PID in $PIDS; do
    wait "$PID" || FAILED=1
done
test "$FAILED" -eq 0
test "$(cat "$ROOT/state/query.txt")" = "AAAAAAAAAAAAAAAAAAAA"

printf 'INSTALL_LAYOUT_KUAL_ONLY_OK\n'
printf 'kual=%s\n' "$EXT"
