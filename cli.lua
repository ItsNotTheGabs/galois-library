-- cli.lua
-- Demo CLI do catálogo pluggable. Uso:
--
--   lua cli.lua search "dune"                        # fuentes activas por config
--   lua cli.lua search "dune" --sources anna         # só anna
--   lua cli.lua search "dune" --sources anna,zlib    # ambas (default)
--   lua cli.lua sources                              # lista fuentes + estado
--   lua cli.lua toggle zlib off                      # activar/desactivar fonte
--   lua cli.lua resolve <md5> --source anna          # proba resolve_download
--
-- MODE FIXTURE: lua cli.lua search "dune" --fixtures  (sen rede real)
----------------------------------------------------------------------------

package.path = "./?.lua;./sources/?.lua;" .. package.path

local settings = require("settings")
local sources  = require("sources.init")
local catalog  = require("catalog")
local anna = require("anna")
local zlib = require("zlib")

local CFG_PATH = os.getenv("HOME") .. "/.config/kindle-annas-dl/sources.cfg"
local fs_real = {
    read = function(p) local f = io.open(p, "r"); if not f then return nil end
        local d = f:read("*a"); f:close(); return d end,
    write = function(p, d)
        local dir = string.match(p, '^(.*)/[^/]+$')
        if dir then os.execute("mkdir -p '" .. dir .. "' 2>/dev/null") end
        local f = io.open(p, "w"); if not f then return false end
        f:write(d); f:close(); return true
    end,
}

local cfg = settings.new({ path = CFG_PATH, fs = fs_real, defaults = {
    anna = true, zlib = true,
} })

sources.register_all({ anna = anna, zlib = zlib })

-- ---- net: real (curl) ou fixture (stub) ----
local function make_net(fixtures)
    if not fixtures then return require("net_curl") end
    return {
        get = function(url, t)
            if not fixtures[url] then return nil, "stub sen ruta: " .. url end
            return fixtures[url]
        end,
    }
end

-- ---- comandos ----

local function cmd_sources()
    print("Fontes registradas:")
    for _, m in ipairs(sources.list()) do
        local state = cfg:enabled(m.META.name) and "ATIVADA" or "desativada"
        print(string.format("  %-8s %-20s [%s]", m.META.name, m.META.label, state))
    end
    print("config: " .. CFG_PATH)
end

local function cmd_toggle(name, val)
    local m = sources.get(name)
    if not m then print("fonte desconhecida: " .. name); return end
    local nv = val ~= "off"
    cfg:set(name, nv)
    print(string.format("%s -> %s", name, nv and "ATIVADA" or "desativada"))
end

local function cmd_search(args)
    -- args = { "search", <query>, ... } — saltamos o comando
    local query, only, fixtures = args[2], nil, false
    local i = 3
    while args[i] do
        if args[i] == "--sources" then
            only = args[i + 1]; i = i + 2
        elseif args[i] == "--fixtures" then
            fixtures = true; i = i + 1
        else i = i + 1 end
    end
    query = query or "test"

    -- construír net-fixture se pedir
    local fixtures_net
    if fixtures then
        local F = require("tests/fixtures")
        fixtures_net = {
            ["https://annas-archive.gl/search?page=1&q=" .. string.gsub(query, "%s+", "+") .. "&content=book"] = F.HTML_TWO_RESULTS,
            ["https://z-lib.io/eapi/search?query=" .. query .. "&page=1"] = F.ZLIB_SEARCH_JSON,
        }
    end
    local net = make_net(fixtures and fixtures_net or nil)

    -- filtro --sources: sen efecto persistente; só vale nesta execución
    local run_cfg = cfg
    if only then
        local overrides = {}
        for _, m in ipairs(sources.list()) do
            local want = false
            for token in string.gmatch(only, "[^,]+") do
                if token == m.META.name then want = true end
            end
            overrides[m.META.name] = want
        end
        run_cfg = settings.new({ defaults = overrides })
    end

    local res, err = catalog.search(net, sources, query, 1, run_cfg)
    if not res then print("erro: " .. tostring(err)); return end
    print(string.format("== %d resultado(s) (query='%s') ==", #res.results, query))
    for idx, b in ipairs(res.results) do
        print(string.format("  %2d. [%s] %s — %s (%s)",
            idx, b.source, b.title, b.author or "s/a", b.format or "?"))
    end
end

local function cmd_resolve_md5(md5, source)
    local m = sources.get(source)
    if not m then print("fonte desconhecida: " .. source); return end
    local url, err = m.resolve_download(require("net_curl"), { md5 = md5 }, {})
    if url then print(url) else print("erro: " .. tostring(err)) end
end

-- ---- main ----

local cmd = arg[1]
if cmd == "sources" then
    cmd_sources()
elseif cmd == "toggle" then
    cmd_toggle(arg[2], arg[3])
elseif cmd == "search" then
    cmd_search(arg)
elseif cmd == "resolve" then
    local md5 = arg[2]
    local src = "anna"
    for i = 3, #arg do
        if arg[i] == "--source" then src = arg[i + 1] end
    end
    if md5 then cmd_resolve_md5(md5, src) else print("uso: cli resolve <md5> [--source anna|zlib]") end
else
    print([[uso:
  lua cli.lua sources
  lua cli.lua toggle <nome> [off]
  lua cli.lua search <query> [--sources anna,zlib] [--fixtures]
  lua cli.lua resolve <md5> [--source anna|zlib]])
end