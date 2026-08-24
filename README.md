# GaloisLibrary 📚

App para **Kindle jailbreakeado** (KUAL) que busca livros com **capas e metadados**
no **Anna's Archive** e **Z-Library**, baixa direto para a biblioteca do Kindle
(`/mnt/us/documents`), com UI clicável e **fontes pluggáveis** com **health check**.

> ⚖️ O app é uma ferramenta neutra. Respeite direitos autorais: prefira obras de
> domínio público / licenças livres. O responsável pelo uso é o usuário.

## Instalação (uma linha)

```sh
curl -sSL https://SEU_HOST/galois-library/install.sh | sh
```

O instalador detecta o ambiente:

- **Kindle** (`/mnt/us` presente) → instala em `/mnt/us/galois-library` + registra
  extensão KUAL (`extensions/galoislibrary`).
- **Desktop Linux** → `~/.local/share/galois-library`.

Variáveis de ambiente (para mirror/repo próprio):

```sh
GALOIS_REPO=owner/repo        # ou URL direta de release.json
GALOIS_ASSET_URL=https://...  # tarball direto (dispensa GitHub API)
GALOIS_PREFIX=/caminho/destino
```

Validação, se quiser: servi um tarball local e rode o instalador com `GALOIS_ASSET_URL=file://...` (testado em `tests/`).

## Atualizações automáticas 🔄

O usuário nunca precisa ficar com versão antiga:

- **Auto-check**: ao abrir o GaloisLibrary no KOReader, verifica uma vez por dia se
  há release nova (`update.lua` → semver) e oferece aplicar na hora.
- **CLI**: `lua cli.lua update` (verifica) / `lua cli.lua update --apply` (aplica).
- Ao atualizar, **`config/` do usuário é preservado** (settings das fontes ficam fora
  da árvore de update).
- `update.lua` lê o `version` instalado e consome o padrão GitHub (tag → tarball) ou
  URL direta de release.

## Health check por fonte (o problema do KindleFetch resolvido) 🩺

Cada fonte tem `health(net, opts)` — um **probe mínimo de busca** que diz se a fonte
está **SAUDÁVEL** ou **COM PROBLEMA** e por quê:

```sh
$ lua cli.lua health --all
[!!]  anna   Anna's Archive — bloqueado por challenge anti-bot (fingerprint)
[!!]  zlib   Z-Library — sem resposta: curl resposta baleira
Saudáveis: 0 · Com problema: 2
$ echo $?   # 1 → dá para monitorar com cron
```

- Diagnósticos claros: **challenge anti-bot**, domínio parqueado, rede fora do ar,
  login requerido — para você saber se é problema SEU ou da FONTE.
- Na UI (KOReader): Config → cada fonte mostra `[SAUDÁVEL]`/`[PROBLEMA: ...]` +
  toggle ativar/desativar + botão **"Testar fontes agora"**.
- Na CLI: exit code 1 se algo caído (dá para fazer o health viver no cron).

## Fontes pluggables

`busca` roda só nas fontes **ativas** nas configs (toggle por fonte). Para adicionar
uma fonte futura, crie `sources/nova.lua` com o contrato mínimo:

```lua
META = { name="nova", label="Nova Fonte", enabled_default=true }
search(net, q, page, opts) -> { results={{md5,title,author,format,...}}, page }
resolve_download(net, book, opts) -> url
health(net, opts) -> { ok=true } | { ok=false, error="motivo" }
```

E registre em `sources.register_all({ ... nova = require("nova") })` — nada mais muda.

## Stack

- **Lua 5.x / LuaJIT** (a stack do KOReader) + `curl` (já presente no Kindle).
- Core 100% testado em desktop (`lua tests/run_all.lua` → ainda verde).
- UI KOReader (plugin `annakdl.koplugin`) — menu, busca, resultados, config com
  health — lógica testada com stubs; camada visual requer verificação on-device.

## Testes

```sh
lua tests/run_all.lua   # 75 pass (sources, catalog, settings, update, health, UI logic)
```

## Roteiro

- [x] Fontes plugáveis (anna + zlib) com toggle persistente
- [x] Health check por fonte (CLI + UI) com diagnóstico claro
- [x] Instalação `curl|sh` (Kindle/desktop) + auto-update com semver
- [x] CLI: search / source toggle / health / update / resolve
- [x] Esqueleto UI KOReader (menu, busca, resultados, config, download)
- [ ] Captura/verifica funcional
- [ ] Capas dos livros na listagem (ImageWidget) e grade visual
- [ ] Download manager com fila/retomada
- [ ] Release real (repositório + instalador: definir owner/repo)