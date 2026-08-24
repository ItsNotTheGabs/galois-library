# GaloisLibrary 📚

App para **Kindle jailbreakeado** (KUAL/KOReader) que busca livros com **capas e metadados**
no **Anna's Archive** e **Z-Library**, baixa direto para a biblioteca do Kindle
(`/mnt/us/documents`), com UI clicável, **fontes plugáveis com health check** e
**auto-update** (o usuário nunca fica em versão antiga).

> ⚖️ O app é uma ferramenta neutra. Respeite direitos autorais: prefira obras de
> domínio público / licenças livres. O responsável pelo uso é o usuário.

## Instalação (uma linha)

```sh
curl -sSL https://itsnotthegabs.github.io/galois-library/install.sh | sh
```

O instalador detecta o ambiente:

- **Kindle** (`/mnt/us` presente) → instala o núcleo em `/mnt/us/galois-library`,
  registra a extensão KUAL completa (`extensions/galoislibrary/config.xml + menu.json`)
  e instala o plugin KOReader em **`/mnt/us/koreader/plugins/galoislibrary.koplugin`**.
- **Desktop Linux** → `~/.local/share/galois-library` (para testar o núcleo).

Depois da instalação, feche e abra o KOReader e reabra o KUAL. Se o seu KOReader
estiver em outro caminho, use `GALOIS_KOREADER_ROOT=/caminho/koreader`.

Variáveis de ambiente:

```bash
GALOIS_REPO=ItsNotTheGabs/galois-library  # ou URL direta de release.json
GALOIS_ASSET_URL=https://...   # tarball direto (dispensa GitHub API)
GALOIS_PREFIX=/caminho/destino
GALOIS_KOREADER_ROOT=/mnt/us/koreader
```

## DDoS-Guard — achado medido (importante!)

O site do Anna's está atrás do **DDoS-Guard** em IPs de datacenter; **user-agents de
bot (ClaudeBot/GPTBot/ChatGPT) NÃO contornam** (medido: todos → 403 captcha). O que
funciona de verdade:

- A **busca** do AA pode dar challenge em IP de datacenter, mas **IP residencial
  (Wi-Fi do usuário) tende a passar**;
- O **download NÃO passa pelo gate**: `libgen.li/ads.php?md5=… → get.php?md5=…&key=… →
  CDN booksdl.lc` — **validado ao vivo** (resolve de um md5 real de domínio público
  devolveu a URL limpa e o CDN respondeu).
- O `health` da fonte anna **separa** os dois estados: se a busca estiver atrás do
  gate mas o espelho responder, a fonte aparece `SAUDÁVEL` (com nota) — porque o
  download continua funcionando.

## Auto-update 🔄

- Ao abrir no KOReader, verifica 1×/dia e oferece atualizar (preservando `config/`).
- CLI: `lua cli.lua update [--apply]`.
- `create_release.sh` gera o pacote (`galois-library-<ver>.tar.gz` + `release.json`).

## Health check por fonte 🩺

```bash
$ lua cli.lua health --all
[!!]  anna  Anna's Archive — espelho de descarga indisponível: ...
[OK]  zlib  Z-Library
Saudáveis: 1 · Com problema: 1
$ echo $?    # 1 = algo caído (monitorável por cron)
```

Na UI (KOReader): Config → cada fonte mostra `[SAUDÁVEL]`/`[PROBLEMA: motivo]` +
toggle + botão **"Testar fontes agora"**.

## Fontes plugáveis

Busca roda só nas fontes ativas. Para adicionar fonte futura, crie `sources/nova.lua`:

```lua
META = { name="nova", label="Nova", enabled_default=true }
search(net, q, page, opts) -> { results={{md5,title,author,format,cover_url,...}}, page }
resolve_download(net, book, opts) -> url
health(net, opts) -> { ok=true } | { ok=false, error="motivo" }
```

Registre em `sources.register_all({ ..., nova = require("nova") })` — nada mais muda.

## Stack & testes

- Lua 5.x / LuaJIT (KOReader) + `curl` (já no Kindle), núcleo Lua puro testável.
- `lua tests/run_all.lua` → **87 testes verdes** (sources, catalog, settings,
  update, health, lógica da UI com stubs KOReader).
- `tests/test_plugin_load.lua` verifica o contrato do plugin; `tests/test_install_layout.sh`
  verifica o layout real de KUAL/KOReader e diferencia o instalador antigo do atual.
- O emulador desktop do KOReader é usado no smoke test `tests/koreader_pluginloader_smoke.lua`.
- Download com **resume** (`-C -`) e **retry** (`--retry 2`).

## Roteiro

- [x] Fontes plugáveis (anna + zlib) com toggle persistente e health
- [x] Instalação `curl|sh` + auto-update (instala plugin KOReader em `koreader/plugins` e KUAL com `config.xml`)
- [x] DDoS-Guard contornado: download via espelhos libgen (validado ao vivo)
- [x] `cover_url` no contrato/parser/UI (render ImageWidget: pending device)
- [x] CLI: search / toggle / health / update / resolve (E2E real validado)
- [x] PluginLoader real do KOReader: descoberta, carga, instanciação e registro do menu validados no emulador
- [ ] Validação on-device (visual, ImageWidget real, download no Wi-Fi real)
- [ ] Login zlib + fila de downloads com gestão de falhas
- [x] Repo + release GitHub + GitHub Pages publicados para o `curl|sh`