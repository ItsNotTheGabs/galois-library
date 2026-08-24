-- tests/koreader_pluginloader_smoke.lua
-- Executar com o luajit do KOReader, a partir da pasta instalada:
--   KO_HOME=/tmp/ko-home GALOIS_DIR=/path/galois-library ./luajit \
--     /path/galois-library/tests/koreader_pluginloader_smoke.lua
-- O script usa o pluginloader real do KOReader para testar descoberta/carga.

local function fail(msg)
    io.stderr:write("PLUGINLOADER_FAIL: " .. msg .. "\n")
    os.exit(1)
end

local plugin_root = os.getenv("KO_HOME")
if not plugin_root or plugin_root == "" then fail("KO_HOME não definido") end

-- reader.lua faz exatamente estas inicializações antes do pluginloader.
dofile("setupkoenv.lua")
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("extra_plugin_paths", { DataStorage:getDataDir() .. "/plugins" })
G_reader_settings:saveSetting("plugins_disabled", {})
G_reader_settings:saveSetting("plugins_disable_external", false)

-- Setup device/canvas exatamente como reader.lua antes de carregar UI/pluginloader.
local Device = require("device")
local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)
local Bidi = require("ui/bidi")
Bidi.setup(G_reader_settings:readSetting("language"))

local PluginLoader = require("pluginloader")
PluginLoader.enabled_plugins = nil
PluginLoader.disabled_plugins = nil
PluginLoader.loaded_plugins = nil
PluginLoader.all_plugins = nil

local enabled, disabled = PluginLoader:loadPlugins()
local found
for _, plugin in ipairs(enabled) do
    if plugin.name == "galoislibrary" then
        found = plugin
        break
    end
end
if not found then
    local names = {}
    for _, plugin in ipairs(enabled) do names[#names + 1] = plugin.name end
    fail("plugin não foi descoberto/carregado; enabled=" .. table.concat(names, ","))
end
if type(found.addToMainMenu) ~= "function" then fail("addToMainMenu ausente") end

-- A instância real do filemanager recebe { ui = self }.
local menu_items = {}
local fake_menu = {
    registerToMainMenu = function(self, module) module.__registered = true end,
}
local fake_ui = { menu = fake_menu }
local ok, instance = PluginLoader:createPluginInstance(found, { ui = fake_ui })
if not ok or not instance then fail("createPluginInstance falhou: " .. tostring(instance)) end
instance:addToMainMenu(menu_items)
if not menu_items.galoislibrary then fail("addToMainMenu não criou menu_items.galoislibrary") end

print("PLUGINLOADER_OK")
print("path=" .. tostring(found.path))
print("name=" .. tostring(found.name))
print("menu=GaloisLibrary")
