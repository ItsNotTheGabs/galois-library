# Kindle Anna's Archive / Z-Library Downloader

App para Kindle jailbreakeado (KUAL) que busca metadados **com capas** e baixa ebooks
**diretamente na biblioteca do Kindle** (`/mnt/us/documents`), com interface clicável.

Arquitetura de **fontes pluggables**: cada fonte (anna-archive, z-library e futuras)
é um módulo Lua isolado que implementa um contrato comum. O usuário **habilita ou
desabilita** qualquer fonte nas configurações de resultado de busca, sem tocar código.

## Estado atual (PoC funcional)

- ✅ Contrato de fonte (`sources/init.lua`) — validação + registro de fontes
- ✅ Settings com toggle persistente (`settings.lua`) — fonte ativada/desativada
- ✅ Catálogo coordenador (`catalog.lua`) — busca só nas fontes ativas
- ✅ Fonte `anna.lua` — parsing HTML (estrutura que usa KindleFetch) + rota lgli
- ✅ Fonte `zlib.lua` — eapi JSON + rota /md5 → /eapi/book → downloadLink
- ✅ 31 testes unitários verdes (`lua tests/run_tests.lua`), stubs de rede (sem deps)
- ✅ CLI demo (`lua cli.lua ...`) — toggle por fonte nas buscas
- ⏳ Plugin KOReader (`koplugin/annakdl.koplugin/`) — esqueleto UI a completar
- ⏳ Download real: verificação live pendente (esta máquina está atrás do DDoS-Guard
  do AA; o fluxo lgli/zlib está implementado segundo o que o KindleFetch usa)

## Stack

- **Lua 5.x** (o mesmo que usa KOReader) — núcleo testado no desktop, roda no Kindle
- **curl** — backend de rede real (`net_curl.lua`); disponível no Kindle também
- **KOReader** — camada UI (rota A), a conversar na fase P1

## Uso da CLI (desktop / também roda em kterm no Kindle)

```sh
lua cli.lua sources                       # lista fontes e estado
lua cli.lua toggle zlib off               # desativa zlib (persiste no config)
lua cli.lua search "dune"                 # busca com fontes ativas (rede real)
lua cli.lua search "dune" --sources anna  # só anna (filtro transitório)
lua cli.lua search "dune" --fixtures      # demo offline com dados sintéticos
lua cli.lua resolve <md5> --source anna   # resolve link direto de um book
```

## Testes

```sh
lua tests/run_tests.lua   # 31 verde
```

## Próximos passos

1. **UI KOReader (P1)**: telas de busca com capas, toggle nas config (SwitchItem),
   lista de resultados clicável — no stock (require KOReader no aparelho).
2. **Download real**: rodar `cli resolve` com um md5 real de um livro de domínio
   público (p.ex. de Project Gutenberg) para validar a rota lgli/zlib ao vivo.
3. **Mirror selection**: fallback múltiplos mirrors (SLUM/futuro).
4. Empacotar como extensão KUAL/MRPI (`extensions/` + `menu.json`).

## Aviso legal

O utilitário em si é neutro; respeite os direitos autorais. Prefira obras de domínio
público / licenças livres. O responsável pelo uso é o usuário.