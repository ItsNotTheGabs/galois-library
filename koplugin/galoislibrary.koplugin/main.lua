-- koplugin/galoislibrary.koplugin/main.lua
-- GaloisLibrary — UI KOReader (e-ink).
--
-- Screens:
--   * Menu principal         (buscar, fontes, health, atualização)
--   * Busca por título/autor  (InputDialog) -> resultados em lista
--   * Detalhe do livro        (título/autor/formato/descrição + Baixar)
--   * Configurações de fontes  (toggle + STATUS de saúde por fonte)
--   * Atualizações            (check manual + auto com throttle 24h)
--
-- O núcleo (sources/catalog/health/update) é 100% Lua independente de KOReader
-- e roda também via `lua cli.lua ...` no desktop. Este ficheiro é só a camada UI.
--
-- NOTA de API KOReader: os nomes dos widgets abaixo seguem o master do KOReader
-- (WidgetContainer, UIManager, InputDialog, TouchMenu, Notification, InfoMessage,
-- ButtonDialog). Requer verificação on-device; o fallback defensivo evita crash.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local InputDialog     = require("ui/widget/inputdialog")
local TouchMenu       = require("ui/widget/touchmenu")

local ok_note, Notification = pcall(require, "ui/widget/notification")
local ok_info, InfoMessage = pcall(require, "ui/widget/infomessage")
local ok_btn, ButtonDialog = pcall(require, "ui/widget/buttondialog")

-- dir do núcleo (instalado por install.sh)
local GALOIS_DIR = "/mnt/us/galois-library"
if not io.open(GALOIS_DIR, "r") then
    GALOIS_DIR = "/mnt/us/extensions/galoislibrary"
end
package.path = GALOIS_DIR .. "/?.lua;" .. GALOIS_DIR .. "/sources/?.lua;" .. package.path

local GaloisLib = WidgetContainer:extend("GaloisLibrary")

function GaloisLib:init()
    self.name = "galoislibrary"
    self.net = require("net_curl")
    self.sources = require("sources.init")
    self.catalog = require("catalog")
    self.health = require("health")
    self.update = require("update")

    self.sources.register_all({
        anna = require("anna"),
        zlib = require("zlib"),
    })

    -- config do usuario: fica FORA da pasta de update (persiste entre versões)
    local cfg_path = GALOIS_DIR .. "/config/sources.cfg"
    self.cfg = require("settings").new({
        path = cfg_path,
        fs = {
            read = function(p) local f = io.open(p, "rb"); if not f then return nil end
                local d = f:read("*a"); f:close(); return d end,
            write = function(p, d) local f = io.open(p, "wb"); if not f then return false end
                f:write(d); f:close(); return true end,
        },
        defaults = {
            anna = true, zlib = true,
            download_dir = GALOIS_DIR .. "/documents",
            repo = "galois-library/galois-library",
        },
    })

    self.last_query = ""
    UIManager:scheduleIn(0, function() self:autoCheckUpdate() end)
end

local function notify(text)
    if ok_note and Notification then
        UIManager:show(Notification:new{ text = text })
    else
        print("[GaloisLibrary] " .. text)
    end
end

local function info(text)
    if ok_info and InfoMessage then
        UIManager:show(InfoMessage:new{ text = text })
    else
        notify(text)
    end
end

---------------------------------------------------------------------------
-- Atualizações
---------------------------------------------------------------------------

function GaloisLib:autoCheckUpdate()
    -- throttling: 1x por dia
    local last = tonumber(self.cfg:get("last_update_check", "0")) or 0
    if os.time() - last < 86400 then return end
    self.cfg:set_raw("last_update_check", tostring(os.time()))
    self:checkUpdate(true)
end

function GaloisLib:currentVersion()
    local vf = io.open(GALOIS_DIR .. "/version", "rb")
    if not vf then return "0.0.0" end
    local v = vf:read("*a"):gsub("%s+$", "")
    vf:close()
    return v
end

function GaloisLib:checkUpdate(silent)
    local repo = self.cfg:get("repo", "galibre-archive/galois-archive")
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
                      UIManager:close(dlg)
                      UIManager:show(Notification:new{ text = "Baixando atualização..." })
                      local ok, err = self.update.self_update(self.net, repo, GALOIS_DIR, cur)
                      if ok then
                          info("Atualizado para v" .. info.latest .. " ✓")
                      else
                          info("Falha na atualização: " .. tostring(err))
                      end
                  end },
                  { text = "Agora não", callback = function() UIManager:close(dlg) end } },
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
function GaloisLib:searchDialog()
    local dialog = InputDialog:new{
        title = "Buscar livros",
        input = self.last_query,
        type = "text",
        buttons = {
            { { text = "Buscar", callback = function()
                  local q = dialog.getInputText and dialog:getInputText() or dialog.input or ""
                  UIManager:close(dialog)
                  self.last_query = q
                  self:doSearch(q)
              end },
              { text = "Cancelar", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function GaloisLib:doSearch(q)
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
            -- cover_url (se a fonte tiver) viaja no item; a UI real mostra a capa
            -- via ImageWidget (cache em /tmp/galois-covers/<md5>.jpg)
            cover_url = b.cover_url,
            book = b,
            callback = function() self:bookDetailMenu(b) end,
        }
    end
    items[#items + 1] = { text = "✕ Fechar", callback = function() end }
    self._results_menu = TouchMenu:new{
        title = string.format("Resultados (%d)", #res.results),
        item_table = items,
    }
    UIManager:show(self._results_menu)
end

---------------------------------------------------------------------------
-- Detalhe do livro + download
---------------------------------------------------------------------------
function GaloisLib:bookDetailMenu(b)
    local src = self.sources.get(b.source)
    local items = {
        { text = ("%s"):format(b.title), bold = true },
        { text = ("Autor: %s"):format(b.author or "desconhecido") },
        { text = ("Formato: %s · Fonte: %s"):format(b.format or "?", b.source) },
    }
    if b.description and b.description ~= "" then
        items[#items + 1] = { text = ("Descrição: %s"):format(b.description) }
    end
    items[#items + 1] = { text = "⬇ Baixar para a biblioteca", callback = function()
        UIManager:close(self._book_menu)
        self:downloadBook(b)
    end }
    items[#items + 1] = { text = "◀ Voltar" }
    self._book_menu = TouchMenu:new{ title = b.title, item_table = items }
    UIManager:show(self._book_menu)
end

function GaloisLib:downloadBook(b)
    -- resolve a URL e baixa para documents/
    local src_mod = self.sources.get(b.source)
    if not src_mod then info("Fonte desconhecida: " .. tostring(b.source)); return end
    UIManager:show(Notification:new{ text = "Resolvendo link de download..." })
    local url, err = src_mod.resolve_download(self.net, b, self.cfg)
    if not url then info("Não foi possível baixar: " .. tostring(err)); return end

    local dir = self.cfg:get("download_dir", "/mnt/us/documents")
    os.execute("mkdir -p '" .. dir .. "'")
    local fname = (b.title or "livro"):gsub("[^%w%p%s]", ""):gsub("%s+", "_"):gsub("%.%.?", ".") .. "." .. (b.format or "epub")
    local dest = dir .. "/" .. fname

    UIManager:show(Notification:new{ text = "Baixando..." })
    local ok, err2 = self.net.save(url, dest, 120)
    if ok then
        info("Baixado!\n" .. dest)
    else
        info("Falha no download: " .. tostring(err2))
    end
end

---------------------------------------------------------------------------
-- Configurações de fontes (com status de saúde)
---------------------------------------------------------------------------
function GaloisLib:sourcesConfigMenu(with_health)
    if with_health == nil then with_health = true end
    local items = {}

    if with_health then
        -- Estado de saúde ao abrir a tela
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
                    self:sourcesConfigMenu(true)
                end,
            }
        end
    end

    items[#items + 1] = { text = "🔄 Testar fontes agora", callback = function()
        UIManager:close(self._cfg_menu)
        UIManager:show(Notification:new{ text = "Testando fontes..." })
        local res = self.health.run(self.net, self.sources, self.cfg, { only_enabled = false })
        local lines = {}
        for _, r in ipairs(res.report) do
            lines[#lines + 1] = string.format("%s%s", r.ok and "✓" or "✗", r.label)
                .. (r.ok and "" or (" — " .. (r.error or "")))
        end
        info(table.concat(lines, "\n") .. string.format("\n\n%d saudáveis · %d com problema", res.healthy, res.unhealthy))
    end }

    items[#items + 1] = { text = "Baixar livros para: " .. (self.cfg:get("download_dir", "/mnt/us/documents")), callback = function()
        UIManager:close(self._cfg_menu)
        local dlg = InputDialog:new{ title = "Pasta de download", input = self.cfg:get("download_dir", ""),
            buttons = { { { text = "OK", callback = function()
                              local p = dlg.getInputText and dlg:getInputText() or dlg.input or ""
                              self.cfg:set_raw("download_dir", p)
                              UIManager:close(dlg)
                              info("Destino: " .. p)
                          end } } } }
        UIManager:show(dlg)
    end }

    items[#items + 1] = { text = "◀ Voltar" }

    self._cfg_menu = TouchMenu:new{ title = "Configurações de fontes", item_table = items }
    UIManager:show(self._cfg_menu)
end

---------------------------------------------------------------------------
-- Menu principal
---------------------------------------------------------------------------
function GaloisLib:mainMenuItems()
    local items = {
        { text = "🔍 Buscar livros", callback = function() self:searchDialog() end },
        { text = "⚙ Fontes (ativar/desativar + saúde)", callback = function() self:sourcesConfigMenu(true) end },
        { text = "⬆ Verificar atualização", callback = function() self:checkUpdate(false) end },
        { text = "ℹ Sobre", callback = function()
            info(string.format("GaloisLibrary v%s\nFontes plugáveis com health check.", self:currentVersion()))
        end },
    }
    return items
end

function GaloisLib:addToMainMenu(menu_items)
    table.insert(menu_items, {
        text = "GaloisLibrary",
        sub_item_table = self:mainMenuItems(),
    })
end

return GaloisLib