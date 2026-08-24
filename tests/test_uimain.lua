-- tests/test_uimain.lua
-- Exercita a LÓGICA da UI do plugin (com stubs KOReader + núcleo real).
-- Usa o plugin instanciado como o KOReader faz: ui injetado + init().
--
-- Executar: lua tests/run_all.lua

local T = require("run")
local F = require("fixtures")

---------------------------------------------------------------------------
-- stubs minimalistas da API KOReader (só o que o main.lua usa)
---------------------------------------------------------------------------
local shown, closed = {}, {}

local UIManager_stub = {
    show = function(_, w) shown[#shown + 1] = w end,
    close = function() end,
    scheduleIn = function() end,
}

local WidgetContainer_stub = {
    extend = function(_, def)
        local cls = {}
        for k, v in pairs(def) do cls[k] = v end
        cls.__index = cls
        function cls:new(o)
            local inst = setmetatable(o or {}, cls)
            return inst  -- NÃO chama init aqui (o pluginloader chama depois)
        end
        return cls
    end,
}

local registered = {}
local ui_stub = {
    menu = { registerToMainMenu = function(_, plugin) registered.plugin = plugin end },
}

local InputDialog = {}
function InputDialog.new(_, opts)
    local self = { opts = opts, input = (opts and opts.input) or "" }
    function self:getInputText() return self.input end
    function self:onShowKeyboard() end
    return self
end

local TouchMenu_stub = {}
function TouchMenu_stub.new(_, opts)
    return { item_table = (opts and opts.item_table) or {}, title = (opts and opts.title) or "" }
end

local Notification = { new = function(_, opts) return opts end }
local InfoMessage = { new = function(_, opts) return opts end }
local ButtonDialog = { new = function(_, opts) return opts end }

package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer_stub end
package.preload["ui/uimanager"] = function() return UIManager_stub end
package.preload["ui/widget/inputdialog"] = function() return InputDialog end
package.preload["ui/widget/touchmenu"] = function() return TouchMenu_stub end
package.preload["ui/widget/notification"] = function() return Notification end
package.preload["ui/widget/infomessage"] = function() return InfoMessage end
package.preload["ui/widget/buttondialog"] = function() return ButtonDialog end

-- carrega o plugin
package.path = "./?.lua;./sources/?.lua;" .. package.path
local GaloisLib = dofile("koplugin/galoislibrary.koplugin/main.lua")

-- injeta o núcleo + rede fake (como o KOReader no device: instância real)
local plugin = GaloisLib:new()
plugin.ui = ui_stub
local net_fake = {
    get = function(url)
        if string.find(url, "annas-archive", 1, true) then return F.HTML_TWO_RESULTS end
        if string.find(url, "z-lib", 1, true) then return F.ZLIB_SEARCH_JSON end
        if string.find(url, "galois-library", 1, true) then return F.GALOIS_HEALTH_OK end
        return nil, "404 stub: " .. url
    end,
    save = function(_, u, p) local f = io.open(p, "wb"); f:write("x"); f:close(); return true end,
}
plugin.net = net_fake
plugin.sources = require("sources.init")
plugin.catalog = require("catalog")
plugin.health = require("health")
plugin.update = require("update")
plugin.cfg = require("settings").new({ defaults = { anna = true, zlib = true,
    download_dir = "/tmp/gl_dl", repo = "tests/repo" } })
plugin.sources.register_all({ anna = require("anna"), zlib = require("zlib") })

-- ---- 1. init registra no menu ----
plugin:init()
T.ok("init: plugin registrado no menu", registered.plugin == plugin)

-- ---- 2. menu principal (addToMainMenu por chave) ----
local menu_items = {}
plugin:addToMainMenu(menu_items)
T.ok("main menu: chave 'galoislibrary'", menu_items.galoislibrary ~= nil)
T.ok("main menu: submenu >=4", type(menu_items.galoislibrary) == "table"
    and #menu_items.galoislibrary.sub_item_table >= 4)
T.eq("main menu: título", menu_items.galoislibrary.text, "GaloisLibrary")

-- ---- 3. config de fontes com status de saúde ----
shown = {}
plugin:sourcesConfigMenu()
T.ok("cfg screen aberta", #shown >= 1)
local cfg_menu = shown[#shown]
local texts = {}
for _, it in ipairs(cfg_menu.item_table) do texts[#texts + 1] = it.text or "" end
local joined = table.concat(texts, "\n")
T.ok("cfg: mostra label Anna", string.find(joined, "Archive", 1, true) ~= nil)
T.ok("cfg: mostra label Z-Library", string.find(joined, "Z-Library", 1, true) ~= nil)
T.ok("cfg: toggle presente", cfg_menu.item_table[1].checked ~= nil)
T.ok("cfg: ação testar fontes", string.find(joined, "Testar fontes", 1, true) ~= nil)

-- ---- 4. fluxo de busca -> resultados ----
shown = {}
plugin:doSearch("dune")
local res_menu
for _, w in ipairs(shown) do if w.item_table then res_menu = w end end
T.ok("busca: menu de resultados aberto", res_menu ~= nil)
T.ok("busca: >=5 linhas", res_menu and #res_menu.item_table >= 5)
local all_texts = {}
for _, it in ipairs(res_menu and res_menu.item_table or {}) do
    if it.text then all_texts[#all_texts + 1] = it.text end
end
local res_joined = table.concat(all_texts, "\n")
T.ok("busca: contém Anna (Pride)", string.find(res_joined, "Pride", 1, true) ~= nil)
T.ok("busca: contém zlib (Dune)", string.find(res_joined, "Dune", 1, true) ~= nil)
-- cover_url viaja no item
local any_cover = false
for _, it in ipairs(res_menu.item_table) do
    if type(it.cover_url) == "string" and string.find(it.cover_url, "covers.example", 1, true) then
        any_cover = true
    end
end
T.ok("busca: algum item com cover_url", any_cover)

-- ---- 5. busca offline não quebra ----
local net_mudo = { get = function() return nil, "offline" end, save = function() return true end }
plugin.net = net_mudo
shown = {}
plugin:doSearch("nada")
local lyn = 0
for _, w in ipairs(shown) do if w.item_table then lyn = lyn + 1 end end
T.eq("busca offline: sem menu de resultados", lyn, 0)

T.done()