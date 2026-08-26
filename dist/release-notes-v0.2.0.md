## GaloisLibrary v0.2.0 — KUAL-only

Esta versão descontinua o plugin do KOReader. O GaloisLibrary passa a ser uma única aplicação KUAL dinâmica.

### O que mudou

- remove `galoislibrary.koplugin` dos pacotes;
- remove automaticamente plugins legados nos caminhos padrão e em `GALOIS_KOREADER_ROOT` customizado;
- teclado por submenus KUAL para montar consultas;
- resultados, metadados, toggle de fontes e health check dentro do KUAL;
- download para `/mnt/us/documents` com `.part`, resume e validação real do exit status do curl;
- ações KUAL e o updater compartilham um lock para impedir perda de teclas/estado e troca concorrente;
- JSON com controles escapados, UTF-8 sanitizado e truncamento seguro;
- erros de pesquisa, resolução, persistência e download ficam visíveis no status;
- instalação com preflight e troca transacional (núcleo + extensão + limpeza legada), preservando `config/` e `data/` e restaurando tudo em caso de falha ou sinal;
- updater com `mktemp`, `umask 077`, cleanup por trap, SHA-256, lock compartilhado e log persistente em `/mnt/us/galois-library/data/kual/update.log`.

### Instalação/upgrade

```sh
curl -fsSL https://itsnotthegabs.github.io/galois-library/install.sh | sh
```

Depois feche e reabra o KUAL.

### Runtime

A interface é 100% KUAL. O launcher pode usar `/mnt/us/koreader/luajit` somente como runtime Lua; nenhum plugin do KOReader é instalado ou carregado.

### Verificação

- 128 testes Lua, 0 falhas;
- 40 testes do app KUAL e 10 de rede/download verdes no LuaJIT real;
- instalação/upgrade KUAL-only, pacote incompleto, caminho KOReader customizado e concorrência validados;
- rollback transacional provado sob falha injetada e sob TERM em múltiplos pontos;
- updater E2E validado com checksum e log persistente;
- tarball sem `koplugin/` e menu JSON validado.

### Limitações conhecidas

- a interação final no Kindle físico depende da confirmação do usuário;
- Anna's Archive pode apresentar challenge dependendo do IP;
- Z-Library permanece desativada por padrão até o login ficar estável.
