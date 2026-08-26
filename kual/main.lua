-- kual/main.lua
-- Entrypoint chamado por /mnt/us/extensions/galoislibrary/run.sh.

local app_root = os.getenv("GALOIS_APP_ROOT") or "."
package.path = app_root .. "/?.lua;" .. app_root .. "/sources/?.lua;" .. package.path

local App = require("kual.app")
local settings = require("settings")
local registry = require("sources.init")
local catalog = require("catalog")
local health = require("health")
local net = require("net_curl")
local anna = require("anna")
local zlib = require("zlib")

local state_dir = os.getenv("GALOIS_STATE_DIR") or (app_root .. "/data/kual")
local menu_path = os.getenv("GALOIS_MENU_PATH") or "/mnt/us/extensions/galoislibrary/menu.json"
local documents_dir = os.getenv("GALOIS_DOCUMENTS_DIR") or "/mnt/us/documents"

local fs_real = {
    read = function(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local value = f:read("*a")
        f:close()
        return value
    end,
    write = function(path, value)
        local dir = path:match("^(.*)/[^/]+$")
        if dir then os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null") end
        return App.write_file(path, value)
    end,
}

registry.register_all({ anna = anna, zlib = zlib })
local source_settings = settings.new{
    path = state_dir .. "/sources.cfg",
    fs = fs_real,
    defaults = { anna = true, zlib = false },
}

local app = App.new{
    state_dir = state_dir,
    menu_path = menu_path,
    documents_dir = documents_dir,
    settings = source_settings,
    registry = registry,
    catalog = catalog,
    health = health,
    net = net,
}

local command = arg[1] or "init"
local ok, err = app:dispatch(command, arg[2])
if not ok then
    io.stderr:write("GaloisLibrary KUAL: ", tostring(err), "\n")
    os.exit(1)
end
