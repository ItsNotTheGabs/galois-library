-- tests/test_uimain.lua
-- Exercita a LÓGICA da UI do plugin (sem KOReader real) usando stubs preloadados.
-- Cobre: menu principal, tela de fontes com STATUS de saúde, e fluxo de busca.
--
-- Executar: lua tests/run_all.lua

local T = require("run")
local F = require("fixtures")

---------------------------------------------------------------------------
-- stubs minimalistas da API KOReader (só o que o main.lua usa)
---------------------------------------------------------------------------
local shown, closed = {}, {}

local UIManager = {
    show = function(self, w) shown[#shown + 1] = w end,
    close = function() end,
    scheduleIn = function() end,          -- autoCheckUpdate fica desligado offline
}

local WidgetContainer = {
    extend = function(self, name)
        local cls = { name = name }
        cls.__index = cls
        function cls:new(o)
            local inst = setmetatable(o or {}, cls)
            if inst.init then inst:init() end
            return inst
        end
        return cls
    end,
}

local InputDialog = {}
function InputDialog.new(_, opts)
    local self = { opts = opts, input = (opts and opts.input) or "" }
    function self:getInputText() return self.input end
    function self:onShowKeyboard() end
    return self
end

local TouchMenu = {}
function TouchMenu.new(_, opts)
    return { opts = opts, item_table = (opts and opts.item_table) or {}, title = (opts and opts.title) or "" }
end

local Notification = { new = function(_, opts) return opts end }
local InfoMessage = { new = function(_, opts) return opts end }
local ButtonDialog = { new = function(_, opts) return opts end }

-- registra no package.preload para que require("ui/...") funcione
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["ui/uimanager"] = function() return UIManager end
package.preload["ui/widget/inputdialog"] = function() return InputDialog end
package.preload["ui/widget/touchmenu"] = function() return TouchMenu end
package.preload["ui/widget/notification"] = function() return Notification end
package.preload["ui/widget/infomessage"] = function() return InfoMessage end
package.preload["ui/widget/buttondialog"] = function() return ButtonDialog end

-- carrega o plugin (core via package.path do repo root)
package.path = "./?.lua;./sources/?.lua;" .. package.path
local plugin = dofile("koplugin/galoislibrary.koplugin/main.lua")

-- aplica override do núcleo com rede fake (fixtures)
local net_fake = {
    get = function(url, t)
        if string.find(url, "annas-archive", 1, true) then return F.HTML_TWO_RESULTS end
        if string.find(url, "z-lib", 1, true) then return F.ZLIB_SEARCH_JSON end
        if string.find(url, "galois-library", 1, true) then return F.GALOIS_HEALTH_OK end
        return nil, "404 stub: " .. url
    end,
    save = function(u, p, t) local f = io.open(p, "wb"); f:write("x"); f:close(); return true end,
}

-- injeta os módulos do núcleo no plugin estático (sem chamar init real)
plugin.net = net_fake
local sources_root = require("sources.init")
plugin.sources = sources_root
plugin.catalog = require("catalog")
plugin.health = require("health")
plugin.update = require("update")
plugin.cfg = require("settings").new({ defaults = { anna = true, zlib = true,
    download_dir = "/tmp/gl_dl", repo = "tests/repo" } })
-- registra as fontes reais no registry (anna+zlib; pode já ter fakes da suite)
sources_root.register_all({ anna = require("anna"), zlib = require("zlib") })

-- ---- 1. menu principal ----
local menu_arr = {}
plugin:addToMainMenu(menu_arr)
T.eq("main menu: 1 item", #menu_arr, 1)
T.eq("main menu: título", menu_arr[1].text, "GaloisLibrary")
local sub = menu_arr[1].sub_item_table
T.ok("main menu: submenu presente", type(sub) == "table" and #sub >= 4)

-- ---- 2. config de fontes com status de saúde ----
shown = {}
plugin:sourcesConfigMenu(true)
T.ok("cfg screen aberta", #shown >= 1)
local cfg_menu = shown[#shown]
local texts = {}
for _, it in ipairs(cfg_menu.item_table) do
    texts[#texts + 1] = it.text or ""
end
local joined = table.concat(texts, "\n")
T.ok("cfg: mostra anna (label)", string.find(joined, "Archive", 1, true) ~= nil)
T.ok("cfg: mostra zlib (label)", string.find(joined, "Z-Library", 1, true) ~= nil)
T.ok("cfg: toggle presente (checked)", cfg_menu.item_table[1].checked ~= nil)
T.ok("cfg: ação testar fontes", string.find(joined, "Testar fontes", 1, true) ~= nil)

-- ---- 3. fluxo de busca -> resultados ----
shown = {}
plugin:doSearch("dune")
local res_menu
for _, w in ipairs(shown) do
    if w.item_table then res_menu = w end
end
T.ok("busca: menu de resultados aberto", res_menu ~= nil)
T.ok("busca: >=5 linhas (resultados + fechar)", res_menu and #res_menu.item_table >= 5)
local all_texts = {}
for _, it in ipairs(res_menu and res_menu.item_table or {}) do
    if it.text then all_texts[#all_texts + 1] = it.text end
end
local res_joined = table.concat(all_texts, "\n")
T.ok("busca: contém resultado Anna (Pride)", string.find(res_joined, "Pride", 1, true) ~= nil)
T.ok("busca: contém resultado zlib (Dune)", string.find(res_joined, "Dune", 1, true) ~= nil)
-- cover_url viaja no item (para render futuro) — pelo menos um item com capa
-- (a ordem é determinística; o zlib não expõe cover_url, o anna sim)
local any_cover = false
for _, it in ipairs(res_menu.item_table) do
    if type(it.cover_url) == "string" and string.find(it.cover_url, "covers.example", 1, true) then
        any_cover = true
    end
end
T.ok("busca: algum item carrega cover_url", any_cover)

-- ---- 4. health: teste de fontes gera resumo ----
-- rede que não responde nada => busca sem resultados (não é crash; info())
local plugin2 = plugin
local net_mudo = { get = function() return nil, "offline" end, save = function() return true end }
plugin2.net = net_mudo
shown = {}
plugin2:doSearch("nada")
local lyn = 0
for _, w in ipairs(shown) do if w.item_table then lyn = lyn + 1 end end
T.eq("busca offline: sem menu de resultados", lyn, 0)

T.done()