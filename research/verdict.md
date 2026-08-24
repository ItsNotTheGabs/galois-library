# Verdict — Viabilidade (Phase 0)

**Data:** 2026-08-24
**Projeto:** kindle-annas-dl — busca + download de ebooks no Kindle via KUAL

## Conclusões de viabilidade

| Pergunta | Resposta | Evidência |
|---|---|---|
| Dá para baixar no Kindle via KUAL sem computador? | **SIM** | KindleFetch (bash+curl puro) prova o fluxo; nosso `net_curl.lua` usa o mesmo curl do Kindle |
| Precisa de torrent? | **NÃO** (para o caso comum) | HTTP direto via mirrors lgli/zlib funciona; torrent = port pesado de libtorrent, mantido só como fallback futuro |
| Fontes pluggáveis com toggle? | **SIM (implementado)** | `sources/init.lua` contrato; `settings.lua` persistente; `catalog.lua` agrega só ativas; 31 testes verdes |
| UI com capas? | **Parcial (rota A)** | KOReader suporta o necessário (widgets+imagem+HTTP); plugin skeleton criado; falta completar `main.lua` no aparelho |
| Raspagem do AA ao vivo? | **Restrita** | `annas-archive.gl` → DDoS-Guard (JS); `annas-archive.li` → domínio parqueado; FingerprintJS bloqueia curl. A rota de descarga real passa por lgli/zlib (espelhos), não pelo AA |
| Z-Library ao vivo? | **Pendente** | z-lib.io sem resposta desta máquina; rota implementada segundo KindleFetch (eapi) |

## Decisões tomadas

- **Rota A (KOReader Lua plugin)** como alvo principal — reusa widget kit + HTTP + imagem já presentes.
- **Contrato de fonte mínimo**: `META {name,label,enabled}` + `search(net, q, page, opts)` + `resolve_download(net, book, opts)`.
- **net injetável**: `net_curl.lua` (curl real, desktop+Kindle) / stubs nos testes.
- **Parser isolado por fonte**: mudanças anti-scrape tocam só `sources/<fonte>.lua`.

## Próximo passo (0.6/0.7 do plano)

Validar as rotas de espelho (lgli/zlib) **no dispositivo do usuário** ou com um
mirror não-gated acessível — o fluxo `ads.php?md5=` / `eapi/book/.../file` está
implementado e testado contra fixtures; a captura viva de fixture real é o
único item aberto antes da UI de produção.