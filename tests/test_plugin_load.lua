-- tests/test_plugin_load.lua
-- Verifica que o plugin carrega na forma do pluginloader.lua do KOReader:
-- ormWidgetContainer:extend, init() que registra no menu, addToMainMenu por chave.
-- (KOReader ausente -> stubs de ui/* para os require não estourar.)

package.path = "./?.lua;./sources/?.lua;./koplugin/galoislibrary.koplugin/?.lua;" .. package.path

local registered_entries = {}

-- stubs dos módulos KOReader
local function stub_tbl(...) return { new = function() return {} end, ... } end

local WidgetContainer_stub = {
    extend = function(self, def)
        local cls = {}
        for k, v in pairs(def) do cls[k] = v end
        cls.__index = cls
        function cls:new(o)
            local inst = setmetatable(o or {}, cls)
            if inst.init then inst:init() end
            return inst
        end
        return cls
    end,
}
-- ui.menu:registerToMainMenu grava no nosso table
local ui_stub = {
    menu = {
        registerToMainMenu = function(self, plugin) registered_entries.component = plugin end,
    },
}
local UIManager_stub = {
    show = function() end, close = function() end, scheduleIn = function() end,
}
local InfoMessage_stub = { new = function() return {} end }
local Notification_stub = { new = function() return {} end }

package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer_stub end
package.preload["ui/uimanager"] = function() return UIManager_stub end
package.preload["ui/widget/touchmenu"] = function() return { new = function() return {} end } end
package.preload["ui/widget/inputdialog"] = function() return { new = function() return {} end } end
package.preload["ui/widget/notification"] = function() return Notification_stub end
package.preload["ui/widget/infomessage"] = function() return InfoMessage_stub end
package.preload["ui/widget/buttondialog"] = function() return { new = function() return {} end } end

local ok, err = pcall(function()
    local GaloisLib = dofile("koplugin/galoislibrary.koplugin/main.lua")
    print("tipo do módulo:    ", type(GaloisLib))
    print("tem init:          ", type(GaloisLib.init))
    print("tem addToMainMenu: ", type(GaloisLib.addToMainMenu))
    -- createPluginInstance passa attr={ui=...} antes de init().
    local inst = GaloisLib:new{
        ui = ui_stub,
        net = { get = function() return nil, "stub" end, save = function() return nil end },
    }
    print("plugin registrado no menu:", registered_entries.component == inst)
    -- exercita addToMainMenu por chave nomeada
    local menu_items = {}
    inst:addToMainMenu(menu_items)
    print("menu_items tem chave 'galoislibrary':", menu_items.galoislibrary ~= nil)
    if menu_items.galoislibrary then
        print("sub itens:", #menu_items.galoislibrary.sub_item_table)
    end
end)
if not ok then
    print("FALHA AO CARREGAR:", err)
    os.exit(1)
end
print("LOAD OK")