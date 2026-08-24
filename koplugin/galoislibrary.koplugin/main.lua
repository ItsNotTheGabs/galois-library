-- koplugin/galoislibrary.koplugin/main.lua
-- GaloisLibrary — UI KOReader (e-ink). PLUGIN NO FORMATO OFICIAL.
--
-- Convenções do pluginloader.lua + Widget (validadas contra plugins/hello
-- do próprio KOReader):
--   * o módulo retornado é WidgetContainer:extend{ name=..., is_doc_only=false }
--   * init() chama self.ui.menu:registerToMainMenu(self)  -> cria instância real
--   * addToMainMenu(menu_items) POPULA menu_items por CHAVE nomeada (não insert)
--   * cores (sources/...) vivem em /mnt/us/galois-library (instalador); o plugin
--     REGISTRA o package.path para achar os módulos.
--
-- O núcleo é 100% Lua puro testável em desktop (lua tests/run_all.lua).

local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- ---- raiz do núcleo (cópia instalada pelo install.sh) --------------------
local GALOIS_DIR
local candidates = {}
local configured_dir = os.getenv("GALOIS_DIR")
if configured_dir and configured_dir ~= "" then candidates[#candidates + 1] = configured_dir end
candidates[#candidates + 1] = "/mnt/us/galois-library"
candidates[#candidates + 1] = "/mnt/us/extensions/galoislibrary"
for _, cand in ipairs(candidates) do
    local f = io.open(cand .. "/sources/init.lua", "r")
    if f then
        f:close()
        GALOIS_DIR = cand
        break
    end
end

local GaloisLibrary = WidgetContainer:extend{
    name = "galoislibrary",
    is_doc_only = false,
}

function GaloisLibrary:init()
    -- Fallback ao repetir o load (KOReader pode chamar init de novo)
    if self._initialized then return end
    self._initialized = true

    -- garantir que o núcleo esteja no path
    if GALOIS_DIR then
        package.path = GALOIS_DIR .. "/?.lua;" .. GALOIS_DIR .. "/sources/?.lua;" .. package.path
    end

    -- carrega o núcleo (net persistente, catálogo, health, update)
    -- (se o host/teste já injetou net/net real, respeita; senão, usa o real)
    self.net = self.net or require("net_curl")
    self.sources = require("sources.init")
    self.catalog = require("catalog")
    self.health = require("health")
    self.update = require("update")

    self.sources.register_all({
        anna = require("anna"),
        zlib = require("zlib"),
    })

    local base = GALOIS_DIR or "."
    self.cfg = require("settings").new({
        path = base .. "/config/sources.cfg",
        fs = {
            read = function(p) local f = io.open(p, "rb"); if not f then return nil end
                local d = f:read("*a"); f:close(); return d end,
            write = function(p, d)
                local dir = string.match(p, '^(.*)/[^/]+$')
                if dir then os.execute("mkdir -p '" .. dir .. "' 2>/dev/null") end
                local f = io.open(p, "wb"); if not f then return false end
                f:write(d); f:close(); return true
            end,
        },
        defaults = {
            anna = true, zlib = true,
            download_dir = "/mnt/us/documents",
            repo = "ItsNotTheGabs/galois-library",
        },
    })

    -- REGISTRA no menu principal: forma canónica
    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function GaloisLibrary:addToMainMenu(menu_items)
    menu_items.galoislibrary = {
        text = "GaloisLibrary",
        sub_item_table = {
            { text = "🔍 Buscar livros", callback = function() self:searchDialog() end },
            { text = "⚙ Fontes (ativar/desativar + saúde)", callback = function() self:sourcesConfigMenu() end },
            { text = "⬆ Verificar atualização", callback = function() self:checkUpdate() end },
            { text = "ℹ Sobre", callback = function() self:showAbout() end },
        },
    }
end

-- ---- helpers de UI defensivos ----
local UIManager = require("ui/uimanager")
local function notify(text)
    local Notification = require("ui/widget/notification")
    UIManager:show(Notification:new{ text = text, timeout = 3 })
end
local function info(text)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text })
end
local function close_dialog(dlg)
    if dlg then UIManager:close(dlg) end
end

-- ---- atualizações ----
function GaloisLibrary:checkUpdate()
    local cur = self:currentVersion()
    local res, err = self.update.check(self.net, cur, self.cfg:get("repo", "ItsNotTheGabs/galois-library"))
    if not res then
        info("Falha ao verificar atualização: " .. tostring(err))
        return
    end
    if not res.has_update then
        notify("GaloisLibrary já está atualizado (v" .. cur .. ")")
        return
    end
    local UpdateDialog = require("ui/widget/buttondialog")
    local dlg = UpdateDialog:new{
        title = string.format("Nova versão %s disponível", res.latest),
        info_text = string.format("Atual: v%s\nBaixar e aplicar agora?", cur),
        buttons = {
            { { text = "Atualizar", callback = function()
                    close_dialog(dlg)
                    notify("Baixando atualização...")
                    local ok, err = self.update.self_update(self.net, self.cfg:get("repo", "ItsNotTheGabs/galois-library"), (GALOIS_DIR or "."), cur)
                    if ok then info("Atualizado para v" .. res.latest .. " ✓") else info("Falha na atualização: " .. tostring(err)) end
                end } },
            { { text = "Agora não", callback = function() close_dialog(dlg) end } },
        },
    }
    UIManager:show(dlg)
end

function GaloisLibrary:currentVersion()
    local vf = io.open((GALOIS_DIR or ".") .. "/version", "rb")
    if not vf then return "0.0.0" end
    local v = vf:read("*a"):gsub("%s+$", "")
    vf:close()
    return v
end

function GaloisLibrary:showAbout()
    info(string.format("GaloisLibrary v%s\nFontes plugáveis com health check.", self:currentVersion()))
end

-- ---- busca ----
function GaloisLibrary:searchDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local dialog = InputDialog:new{
        title = "Buscar livros",
        input = "",
        buttons = {
            { { text = "Buscar", callback = function()
                    local q = dialog:getInputText() or ""
                    close_dialog(dialog)
                    self:doSearch(q)
                end } },
            { { text = "Cancelar", callback = function() close_dialog(dialog) end } },
        },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function GaloisLibrary:doSearch(q)
    if not q or q == "" then notify("Busca vazia"); return end
    notify("Buscando em fontes ativas...")
    local res, err = self.catalog.search(self.net, self.sources, q, 1, self.cfg)
    if not res then
        info("Nenhum resultado: " .. tostring(err))
        return
    end
    local TouchMenu = require("ui/widget/touchmenu")
    local items = {}
    for _, b in ipairs(res.results) do
        local label = string.format("%s  [%s] %s", b.title, b.source, b.format or "?")
        items[#items + 1] = {
            text = label,
            cover_url = b.cover_url,
            callback = function() self:bookDetailMenu(b) end,
        }
    end
    items[#items + 1] = { text = "✕ Fechar" }
    UIManager:show(TouchMenu:new{ title = string.format("Resultados (%d)", #res.results), item_table = items })
end

function GaloisLibrary:bookDetailMenu(b)
    local TouchMenu = require("ui/widget/touchmenu")
    local items = {
        { text = ("%s"):format(b.title), bold = true },
        { text = ("Autor: %s"):format(b.author or "desconhecido") },
        { text = ("Formato: %s · Fonte: %s"):format(b.format or "?", b.source) },
    }
    if b.description and b.description ~= "" then
        items[#items + 1] = { text = ("Descrição: %s"):format(b.description) }
    end
    items[#items + 1] = { text = "⬇ Baixar para a biblioteca", callback = function()
        self:downloadBook(b)
    end }
    items[#items + 1] = { text = "◀ Voltar" }
    UIManager:show(TouchMenu:new{ title = b.title, item_table = items })
end

function GaloisLibrary:downloadBook(b)
    local src_mod = self.sources.get(b.source)
    if not src_mod then notify("Fonte desconhecida: " .. tostring(b.source)); return end
    notify("Resolvendo link de download...")
    local url, err = src_mod.resolve_download(self.net, b, self.cfg)
    if not url then notify("Não foi possível baixar: " .. tostring(err)); return end
    local dir = self.cfg:get("download_dir", "/mnt/us/documents")
    os.execute("mkdir -p '" .. dir .. "'")
    local fname = (b.title or "livro"):gsub("[^%w%p%s]", ""):gsub("%s+", "_") .. "." .. (b.format or "epub")
    local dest = dir .. "/" .. fname
    notify("Baixando...")
    local ok, derr = self.net:save(url, dest, 120)
    if ok then notify("Baixado!\n" .. dest) else notify("Falha no download: " .. tostring(derr)) end
end

-- ---- configurações de fontes ----
function GaloisLibrary:sourcesConfigMenu()
    local TouchMenu = require("ui/widget/touchmenu")
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
                UIManager:show(TouchMenu:new{ title = "Configurações de fontes", item_table = items }) -- refresh
            end,
        }
    end
    items[#items + 1] = { text = "🔄 Testar fontes agora", callback = function()
        local r2 = self.health.run(self.net, self.sources, self.cfg, { only_enabled = false })
        local lines = {}
        for _, r in ipairs(r2.report) do
            lines[#lines + 1] = string.format("%s%s", r.ok and "✓" or "✗", r.label)
                .. (r.ok and "" or (" — " .. (r.error or "")))
        end
        notify(table.concat(lines, "\n") .. string.format("\n%d saudáveis · %d com problema", r2.healthy, r2.unhealthy))
    end }
    items[#items + 1] = { text = "◀ Voltar" }
    UIManager:show(TouchMenu:new{ title = "Configurações de fontes", item_table = items })
end

return GaloisLibrary