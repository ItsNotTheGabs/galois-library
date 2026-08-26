# GaloisLibrary 📚 — KUAL

Aplicação para **Kindle jailbroken**, executada inteiramente como extensão do
**KUAL**. Permite montar uma consulta, pesquisar livros, conferir metadados e
baixar arquivos para `/mnt/us/documents` sem instalar um plugin no KOReader.

> ⚖️ Ferramenta neutra: use apenas para obras em domínio público, licenciadas
> livremente ou que você tenha direito de acessar.

## Mudança da v0.2.0

A integração com o KOReader foi **descontinuada**. O instalador da v0.2.0:

- não contém nem instala `galoislibrary.koplugin`;
- remove resíduos antigos de:
  - `/mnt/us/koreader/plugins/galoislibrary.koplugin`;
  - `/mnt/us/plugins/galoislibrary.koplugin`;
- instala somente a aplicação KUAL em
  `/mnt/us/extensions/galoislibrary`;
- mantém o núcleo e os dados em `/mnt/us/galois-library`.

## Instalação

No Kindle, por SSH ou terminal:

```sh
curl -sSL https://itsnotthegabs.github.io/galois-library/install.sh | sh
```

Depois feche e reabra o KUAL. Entre em **GaloisLibrary**.

## Como usar no KUAL

O KUAL não possui uma caixa de texto livre. Por isso, o GaloisLibrary usa menus
dinâmicos como teclado:

1. Abra **GaloisLibrary**.
2. Use **Teclado A-I**, **Teclado J-R**, **Teclado S-Z**, **Números** e
   **Espaço** para montar a consulta.
3. Use **Apagar** ou **Limpar** para corrigir.
4. Toque em **Pesquisar**.
5. Aguarde a mensagem de conclusão e toque em **Atualizar tela**.
6. Abra **Resultados** e escolha um livro.
7. Toque em **Baixar para documents**.
8. Aguarde a conclusão; o arquivo será salvo em `/mnt/us/documents`.

As ações de rede rodam em segundo plano. **Atualizar tela** existe porque o KUAL
recarrega o menu antes de pesquisas/downloads longos terminarem.

## Fontes e diagnóstico

No submenu **Fontes e diagnóstico**:

- `[ON]` / `[OFF]` mostra o estado de cada fonte;
- tocar em uma fonte alterna seu estado;
- **Testar saúde das fontes** executa os probes e mostra o resultado em
  `Status:` no menu principal.

Anna's Archive começa ativa; Z-Library começa desativada até sua integração de
login ficar estável.

## Runtime

O app é Lua puro e o launcher procura o runtime nesta ordem:

1. `GALOIS_LUA`;
2. runtime futuro empacotado em `/mnt/us/galois-library/bin/`;
3. LuaJIT existente em `/mnt/us/koreader/luajit`;
4. `lua` ou `luajit` no `PATH`.

O KOReader pode fornecer apenas o **runtime LuaJIT**; nenhum plugin do KOReader é
instalado ou carregado. Se nenhum runtime existir, o launcher mostra uma mensagem
na tela e grava o motivo em:

```text
/mnt/us/extensions/galoislibrary/galois.log
```

O updater mantém seu log fora da extensão substituída:

```text
/mnt/us/galois-library/data/kual/update.log
```

## Atualização

No menu GaloisLibrary, toque em **Atualizar GaloisLibrary**. O script espera as
ações em andamento, valida o instalador oficial por SHA-256, atualiza o núcleo e
substitui a extensão KUAL por completo.

Também é possível repetir manualmente:

```sh
curl -sSL https://itsnotthegabs.github.io/galois-library/install.sh | sh
```

## Arquitetura

```text
/mnt/us/galois-library/
├── kual/
│   ├── app.lua          # estado, menu dinâmico, busca e download
│   ├── main.lua         # entrypoint Lua
│   └── galoislibrary/   # template da extensão
├── sources/             # Anna's Archive e Z-Library
├── catalog.lua
├── health.lua
├── net_curl.lua
└── data/kual/           # consulta, resultados e configuração persistentes

/mnt/us/extensions/galoislibrary/
├── config.xml
├── menu.json
├── run.sh
├── update.sh
├── app_path
└── galois.log
```

## DDoS-Guard

A busca do Anna's Archive pode apresentar challenge em alguns endereços IP. Em
Wi-Fi residencial costuma funcionar melhor. A resolução de download usa espelhos
LibGen independentes e o health check diferencia falha de busca de falha do
caminho de download.

## Desenvolvimento e testes

```sh
lua tests/run_all.lua
./create_release.sh
sh tests/test_install_layout.sh "$PWD/dist/galois-library-$(cat VERSION).tar.gz"
```

Os testes (**128 passed, 0 failed**) cobrem fontes, catálogo, configurações,
health, atualização, teclado KUAL, persistência, pesquisa, download e upgrade
sobre instalações 0.1.x. O núcleo KUAL também é executado com o LuaJIT real do
KOReader somente como runtime. O smoke test valida que o pacote não contém
`koplugin/` e que o instalador remove plugins legados.

## Estado atual

- [x] UI dinâmica KUAL sem KTerm
- [x] Teclado por submenus
- [x] Pesquisa e resultados no KUAL
- [x] Download para `/mnt/us/documents`
- [x] Toggle e health check por fonte
- [x] Auto-update da extensão e do núcleo
- [x] Remoção automática do plugin KOReader legado
- [ ] Validação final no Kindle físico
- [ ] Login estável da Z-Library
