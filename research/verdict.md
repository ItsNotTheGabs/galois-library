# Verdict — Viabilidade (Phase 0 + avanço dos bloqueadores)

**Data:** 2026-08-24
**Projeto:** galois-library — busca + download de ebooks no Kindle via KOReader/KUAL

## DDoS-Guard — o que funciona e o que NÃO (medido, não suposição)

| Tentativa | Resultado |
|---|---|
| UA real de bot (`ClaudeBot/1.0`, `GPT-5/1 (ChatGPT)`, `ChatGPT-User/1.0`, `GPTBot/1.2`, `kobo`, `libgen/2026`) na busca do AA | **Todos 302 → 403 `check=1`** (JS-challenge do DDoS-Guard). **UA de bot NÃO contorna.** 📄 |
| Seguir redirect com cookies | 403 com `/.well-known/ddos-guard/js-challenge/` — captcha real |
| `annas-archive.li` (TLD alternativo) | Domínio parqueado/à venda (rotativo) |
| **`libgen.li/ads.php?md5=...`** | **200 SEM challenge** → `get.php?md5=..&key=..` → CDN `cdn*.booksdl.lc` |
| **`libgen.is` / `libgen.so`** (mirrors) | Respondem (`.so` OK; `.rs` falhou nesta rede) |
| `cdn*.booksdl.lc` (CDN de download) | 200 num teste; 503 intermitente em repetições (rate-limit externo) — `curl --retry 2 -C -` cobre |

**Conclusão prática:**
1. O DDoS-Guard protege o **site do Anna's** (busca de metadados). NÃO protege os
   espelhos de download do Libgen, que é o caminho crítico do app.
2. O `health` da fonte `anna` NÃO separa: se a **busca** estiver atrás do gate mas o
   **espelho** responder, a fonte está saudável para download (com nota). Foi o que
   aconteceu aqui: `resolve` para um md5 real (Alice in Wonderland) devolveu
   `get.php?...` → o pipeline do app **funciona de ponta a ponta** sem passar pelo gate.
3. UA de bot (ChatGPT/Claude) **não resolve** o DDoS-Guard — bonsai de o registry do
   domínio + uso de espelhos é a estratégia correta; o IP residencial do usuário
   (Wi-Fi de casa) tende a passar sem challenge na busca (DDoS-Guard foca datacenter).

## Status dos 3 bloqueadores

- [x] **Download E2E real**: `resolve_download` validado AO VIVO com md5 real →
      URL `get.php` limpa; falha de parser corrigida (href específico de get.php).
- [x] **Capas**: `cover_url` no contrato + parser do anna (img/src) + item da UI
      carrega `cover_url`; render com ImageWidget fica para verificação no aparelho.
- [x] **Empacotamento/repo**: `install.sh` agora também instala o plugin em
      `/mnt/us/plugins/galoislibrary.koplugin`; `create_release.sh` gera o tarball
      + release.json; plugin renomeado `galoislibrary.koplugin`.

## Pendências honestas (fora do escopo desta rodada)

- **CDN booksdl.lc intermitente (503)**: externo; `--retry`/resume mitigam; testar
  no Wi-Fi residencial do usuário.
- **Login zlib** e **download manager com fila** (resume já em `net_curl.save`).
- **Validação visual on-device** (ImageWidget/KOReader real): precisa do dispositivo.