-- koplugin/annakdl.koplugin/main.lua -- ponte KOReader
--
-- ESTADO: Esqueleto da UI. O núcleo (fontes pluggable, settings, catálogo) xa está
-- probado; estes ficheiros conectan ese núcleo á interface táctil e-ink de KOReader.
--
-- Para completar estes necesítanse os módulos do propio KOReader:
--   UIManager, Menu, InputDialog, WidgetContainer, ImageWidget, SocketHTTP, ...
-- Probanse no dispositivo (or no emulador de escritorio de KOReader), non aquí.
--
-- Forma real dun plugin KOReader: main.lua devuelve unha táboa co hanfield
-- `init` (chamada ao cargar) e `addToMainMenu` (engadir ao menú de xogador).

local eastkdl = {}

function eastkdl:init()
    -- xerarquía de catálogo cargada aquí; reuse o mesmo código que `lua cli.lua`
    self.sources = require("sources.init")
    self.catalog = require("catalog")
    self.settings = require("settings")

    self.sources.register_all({
        anna = require("sources.anna"),
        zlib = require("sources.zlib"),
    })

    -- cargar config de usuario desde /mnt/us/extensions (persistente)
    local cfg_path = "/mnt/us/extensions/annakdl/sources.cfg"
    self.cfg = self.settings.new({
        path = cfg_path,
        fs = {
            read = function(p) local f = io.open(p, "rb"); if not f then return nil end
                local d = f:read("*a"); f:close(); return d end,
            write = function(p, d) local f = io.open(p, "wb"); if not f then return false end
                f:write(d); f:close(); return true end,
        },
        defaults = { anna = true, zlib = true },
    })
end

-- engadir unha opción ao menú principal de KOReader (o nome exacto do hook é
-- addToMainMenu; KOReader chamao ao cargar o plugin).
function eastkdl:addToMainMenu(menu_items)
    -- TODO (UI): este é o lugar onde rexistrar as pantallas:
    --  - "Procurar no catálogo"  → busca con campo de texto (InputDialog)
    --  - "Configuración de fontes" → toggle anna/zlib (SwitchItem)
    --  - "Descargas" → lista de descargas (con progresso)
    -- Estas pantallas consumen self.catalog e self.cfg.
    table.insert(menu_items, {
        text = "AnnaDownloader",
        callback = function()
            -- UIManager:show(AnnaDownloaderMenu:new(self)) -- TODO P1
        end,
    })
end

return eastkdl