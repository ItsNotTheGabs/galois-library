-- koplugin/galoislibrary.koplugin/main.lua
-- GaloisLibrary — UI KOReader (e-ink). PLUGIN ROBUSTO:
--
--  * Estado vive no MÓDULO (tabela S), NÃO em instância de WidgetContainer —
--    assim funciona independente de como o loadér do KOReader chama os hooks
--    (com ':' ou com '.', versões antigas/nova).
--  * addToMainMenu detecta as duas convenções de chamada.
--  * Telas: menu principal, busca, resultados, detalhe/baixar, configurações
--    de fontes (com health), atualização.
--
-- O núcleo (sources/catalog/health/update) é Lua puro testável em desktop.

local S = { name = "galoislibrary" }

-- ---- detecção da raiz do núcleo (instalado por install.sh) ----------------
local function find_core()
    for _, cand in ipairs({ "/mnt/us/galois-library", "/mnt/us/extensions/galoislibrary" }) do
        local f = io.open(cand .. "/sources/init.lua", "r")
        if f then f:close(); return cand end
    end
    return nil -- (modo dev: roda na raiz do repo)
end
local GALOIS_DIR = find_core()
if GALOIS_DIR then
    package.path = GALOIS_DIR .. "/?.lua;" .. GALOIS_DIR .. "/sources/?.lua;" .. package.path
end

-- widgets KOReader (com fallback defensivo)
local ok_ui, UIManager = pcall(require, "ui/uimanager")
local ok_inp, InputDialog = pcall(require, "ui/widget/inputdialog")
local ok_menu, TouchMenu = pcall(require, "ui/widget/touchmenu")
local ok_note, Notification = pcall(require, "ui/widget/notification")
local ok_info, InfoMessage = pcall(require, "ui/widget/infomessage")
local ok_btn, ButtonDialog = pcall(require, "ui/widget/buttondialog")

local function notify(text)
    if ok_note and Notification then UIManager:show(Notification:new{ text = text }) else print("[GaloisLibrary] " .. text) end
end
local function info(text)
    if ok_info and InfoMessage then UIManager:show(InfoMessage:new{ text = text }) else notify(text) end
end

local function real_fs()
    return {
        read = function(p) local f = io.open(p, "rb"); if not f then return nil end
            local d = f:read("*a"); f:close(); return d end,
        write = function(p, d)
            local dir = string.match(p, '^(.*)/[^/]+$')
            if dir then os.execute("mkdir -p '" .. dir .. "' 2>/dev/null") end
            local f = io.open(p, "wb"); if not f then return false end
            f:write(d); f:close(); return true
        end,
    }
end

-- fecha um widget sem erro se o arg faltar (KOReader pede o widget; protege)
local function close_ui(w)
    if UIManager and UIManager.close then
        pcall(UIManager.close, UIManager, w)
    end
end

---------------------------------------------------------------------------
-- init (chamado pelo KOReader; tolera : ou .)
---------------------------------------------------------------------------
function S.init(self)
    S.last_query = ""
    S.net = require("net_curl")
    S.sources = require("sources.init")
    S.catalog = require("catalog")
    S.health = require("health")
    S.update = require("update")

    S.sources.register_all({
        anna = require("anna"),
        zlib = require("zlib"),
    })

    local base = GALOIS_DIR or "."
    S.cfg = require("settings").new({
        path = base .. "/config/sources.cfg",
        fs = real_fs(),
        defaults = {
            anna = true, zlib = true,
            download_dir = "/mnt/us/documents",
            repo = "ItsNotTheGabs/galois-library",
        },
    })

    if ok_ui then
        UIManager:scheduleIn(0, function() S:autoCheckUpdate() end)
    end
    return S
end

---------------------------------------------------------------------------
-- Atualizações
---------------------------------------------------------------------------
function S:autoCheckUpdate()
    local last = tonumber(self.cfg:get("last_update_check", "0")) or 0
    if os.time() - last < 86400 then return end
    self.cfg:set_raw("last_update_check", tostring(os.time()))
    self:checkUpdate(true)
end

function S:currentVersion()
    local vf = io.open((GALOIS_DIR or ".") .. "/version", "rb")
    if not vf then return "0.0.0" end
    local v = vf:read("*a"):gsub("%s+$", "")
    vf:close()
    return v
end

function S:checkUpdate(silent)
    local repo = self.cfg:get("repo", "ItsNotTheGabs/galois-library")
    local cur = self:currentVersion()
    local info, err = self.update.check(self.net, cur, repo)
    if not info then
        if not silent then info("Falha ao verificar atualização: " .. tostring(err)) end
        return
    end
    if not info.has_update then
        if not silent then notify("GaloisLibrary já está atualizado (v" .. cur .. ")") end
        return
    end
    if ok_btn and ButtonDialog then
        local dlg = ButtonDialog:new{
            title = string.format("Nova versão %s disponível", info.latest),
            info_text = string.format("Atual: v%s\nBaixar e aplicar agora?", cur),
            buttons = {
                { { text = "Atualizar", callback = function()
                      close_ui(dlg)
                      notify("Baixando atualização...")
                      local ok, err = self.update.self_update(self.net, repo, (GALOIS_DIR or "."), cur)
                      if ok then info("Atualizado para v" .. info.latest .. " ✓")
                      else info("Falha na atualização: " .. tostring(err)) end
                  end },
                  { text = "Agora não", callback = function() close_ui(dlg) end } },
            },
        }
        UIManager:show(dlg)
    else
        notify("Nova versão " .. info.latest .. " disponível. Rode: lua cli.lua update --apply")
    end
end

---------------------------------------------------------------------------
-- Busca
---------------------------------------------------------------------------
function S:searchDialog()
    local dialog = InputDialog:new{
        title = "Buscar livros",
        input = self.last_query or "",
        buttons = {
            { { text = "Buscar", callback = function()
                      local q = dialog.getInputText and dialog:getInputText() or dialog.input or ""
                      close_ui(dialog)
                      self.last_query = q
                      self:doSearch(q)
                  end },
                  { text = "Cancelar", callback = function() close_ui(dialog) end } },
        },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function S:doSearch(q)
    if not q or q == "" then notify("Busca vazia"); return end
    UIManager:show(Notification:new{ text = "Buscando em fontes ativas..." })
    local res, err = self.catalog.search(self.net, self.sources, q, 1, self.cfg)
    if not res then
        info("Nenhum resultado: " .. tostring(err))
        return
    end
    local items = {}
    for _, b in ipairs(res.results) do
        local label = string.format("%s  [%s] %s", b.title, b.source, b.format or "?")
        items[#items + 1] = {
            text = label,
            cover_url = b.cover_url,
            book = b,
            callback = function() self:bookDetailMenu(b) end,
        }
    end
    items[#items + 1] = { text = "✕ Fechar" }
    UIManager:show(TouchMenu:new{
        title = string.format("Resultados (%d)", #res.results),
        item_table = items,
    })
end

function S:bookDetailMenu(b)
    local items = {
        { text = ("%s"):format(b.title), bold = true },
        { text = ("Autor: %s"):format(b.author or "desconhecido") },
        { text = ("Formato: %s · Fonte: %s"):format(b.format or "?", b.source) },
    }
    if b.description and b.description ~= "" then
        items[#items + 1] = { text = ("Descrição: %s"):format(b.description) }
    end
    items[#items + 1] = { text = "⬇ Baixar para a biblioteca", callback = function()
        close_ui()
        self:downloadBook(b)
    end }
    items[#items + 1] = { text = "◀ Voltar" }
    UIManager:show(TouchMenu:new{ title = b.title, item_table = items })
end

function S:downloadBook(b)
    local src_mod = self.sources.get(b.source)
    if not src_mod then info("Fonte desconhecida: " .. tostring(b.source)); return end
    UIManager:show(Notification:new{ text = "Resolvendo link de download..." })
    local url, err = src_mod.resolve_download(self.net, b, self.cfg)
    if not url then info("Não foi possível baixar: " .. tostring(err)); return end

    local dir = self.cfg:get("download_dir", "/mnt/us/documents")
    os.execute("mkdir -p '" .. dir .. "'")
    local fname = (b.title or "livro"):gsub("[^%w%p%s]", ""):gsub("%s+", "_") .. "." .. (b.format or "epub")
    local dest = dir .. "/" .. fname

    UIManager:show(Notification:new{ text = "Baixando..." })
    local ok, derr = self.net.save(url, dest, 120)
    if ok then info("Baixado!\n" .. dest) else info("Falha no download: " .. tostring(derr)) end
end

---------------------------------------------------------------------------
-- Configurações de fontes (com status de saúde)
---------------------------------------------------------------------------
function S:sourcesConfigMenu()
    local items = {}
    local res = self.health.run(self.net, self.sources, self.cfg, {})
    local status = {}
    for _, r in ipairs(res.report) do
        if r.ok then status[r.name] = "SAUDÁVEL" .. (r.note and " (" .. r.note .. ")" or "")
        else status[r.name] = "PROBLEMA: " .. (r.error or "") end
    end
    for _, m in ipairs(self.sources.list()) do
        local st = status[m.META.name] or "?"
        items[#items + 1] = {
            text = string.format("%s — [%s]", m.META.label, st),
            checked = self.cfg:enabled(m.META.name),
            callback = function()
                self.cfg:toggle(m.META.name)
                self:sourcesConfigMenu()
            end,
        }
    end
    items[#items + 1] = { text = "🔄 Testar fontes agora", callback = function()
        close_ui()
        UIManager:show(Notification:new{ text = "Testando fontes..." })
        local r2 = self.health.run(self.net, self.sources, self.cfg, { only_enabled = false })
        local lines = {}
        for _, r in ipairs(r2.report) do
            lines[#lines + 1] = string.format("%s%s", r.ok and "✓" or "✗", r.label)
                .. (r.ok and "" or (" — " .. (r.error or "")))
        end
        info(table.concat(lines, "\n") .. string.format("\n\n%d saudáveis · %d com problema", r2.healthy, r2.unhealthy))
    end }

    items[#items + 1] = { text = "Pasta de download: " .. (self.cfg:get("download_dir", "/mnt/us/documents")), callback = function()
        close_ui()
        local dlg = InputDialog:new{ title = "Pasta de download",
            input = self.cfg:get("download_dir", ""),
            buttons = { { { text = "OK", callback = function()
                local p = dlg.getInputText and dlg:getInputText() or dlg.input or ""
                self.cfg:set_raw("download_dir", p)
                UIManager:close(dlg)
                info("Destino: " .. p)
            end } } } }
        UIManager:show(dlg)
    end }

    items[#items + 1] = { text = "◀ Voltar" }
    UIManager:show(TouchMenu:new{ title = "Configurações de fontes", item_table = items })
end

---------------------------------------------------------------------------
-- Menu principal
---------------------------------------------------------------------------
function S:addToMainMenu(menu_items, _maybe)
    -- tolera as duas convenções do loadér:
    --   plugin:addToMainMenu(items)  -> self=plugin, menu_items=items
    --   plugin.addToMainMenu(items)  -> self=items,    menu_items=nil
    if type(menu_items) ~= "table" then
        menu_items = self
    end
    table.insert(menu_items, {
        text = "GaloisLibrary",
        sub_item_table = {
            { text = "🔍 Buscar livros", callback = function() self:searchDialog() end },
            { text = "⚙ Fontes (ativar/desativar + saúde)", callback = function() self:sourcesConfigMenu() end },
            { text = "⬆ Verificar atualização", callback = function() self:checkUpdate(false) end },
            { text = "ℹ Sobre", callback = function()
                info(string.format("GaloisLibrary v%s\nFontes plugáveis com health check.",
                    self:currentVersion()))
            end },
        },
    })
end

return S