# Veredito técnico — GaloisLibrary

**Estado atual:** arquitetura KUAL-only a partir da v0.2.0.

## Decisão de produto

O plugin KOReader foi descontinuado após falhas no aparelho real. O produto agora
é uma única extensão KUAL dinâmica, com teclado por submenus, pesquisa,
resultados, download, toggle de fontes, health check e atualização.

O instalador remove automaticamente os dois caminhos usados pelas versões 0.1.x:

```text
/mnt/us/koreader/plugins/galoislibrary.koplugin
/mnt/us/plugins/galoislibrary.koplugin
```

Nenhum `koplugin/` é incluído no pacote da v0.2.0.

## Rede e fontes

- A busca do Anna's Archive pode ficar atrás de DDoS-Guard/FingerprintJS em IPs
  de datacenter; Wi-Fi residencial tende a funcionar melhor.
- A resolução de download usa espelhos LibGen (`ads.php → get.php → CDN`) e não
  depende da UI do site.
- O health check separa indisponibilidade da busca e indisponibilidade do caminho
  de download.
- Z-Library permanece desativada por padrão até a integração de login ser estável.

## Runtime

A UI é do próprio KUAL. O núcleo é Lua puro. O launcher procura Lua/LuaJIT e pode
usar `/mnt/us/koreader/luajit` apenas como runtime; não carrega plugin nem widgets
do KOReader. A compatibilidade com esse LuaJIT foi validada no desktop.

## Verificação

- 128 testes Lua verdes.
- Smoke test de instalação KUAL-only verde.
- Upgrade simulado remove plugins legados.
- Tarball auditado para proibir `koplugin/`.
- Menu JSON validado com parser JSON real.
- Pendente: validação final de interação e download no Kindle físico.
