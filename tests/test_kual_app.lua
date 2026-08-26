-- tests/test_kual_app.lua
-- Contrato do app KUAL autônomo: teclado, pesquisa, resultados e download.

local T = require("run")
local App = require("kual.app")

local function valid_utf8(value)
    local i = 1
    while i <= #value do
        local b = value:byte(i)
        local width
        if b < 0x80 then width = 1
        elseif b >= 0xC2 and b <= 0xDF then width = 2
        elseif b >= 0xE0 and b <= 0xEF then width = 3
        elseif b >= 0xF0 and b <= 0xF4 then width = 4
        else return false end
        for j = 2, width do
            local c = value:byte(i + j - 1)
            if not c or c < 0x80 or c > 0xBF then return false end
        end
        i = i + width
    end
    return true
end

T.ok("nome longo preserva UTF-8", valid_utf8(App.safe_filename(string.rep("é", 100))))
local control_json = App.json_encode({ name = "bad" .. string.char(1) })
T.ok("JSON escapa controle arbitrário", control_json:find("\\u0001", 1, true) ~= nil)
T.ok("JSON não contém controle cru", control_json:find(string.char(1), 1, true) == nil)
local invalid_utf8_json = App.json_encode({ name = "bad" .. string.char(0xFF) })
T.ok("JSON sanitiza UTF-8 inválido", valid_utf8(invalid_utf8_json))
T.ok("JSON usa caractere de substituição", invalid_utf8_json:find("\239\191\189", 1, true) ~= nil)

local ROOT = "/tmp/galois_kual_app_test"
os.execute("rm -rf '" .. ROOT .. "' && mkdir -p '" .. ROOT .. "/documents'")

local enabled_state = { anna = true, zlib = false }
local fake_settings = {
    enabled = function(_, name) return enabled_state[name] == true end,
    set = function(_, name, value) enabled_state[name] = value == true; return true end,
}
local fake_registry = {
    list = function()
        return {
            { META = { name = "anna", label = "Anna's Archive" } },
            { META = { name = "zlib", label = "Z-Library" } },
        }
    end,
    get = function(_, name) return name == "anna" and {} or nil end,
}
local fake_catalog = {
    search = function(net, registry, query, page, settings)
        if query ~= "DUNE" then return nil, "consulta inesperada" end
        return { results = {
            { source="anna", md5=string.rep("a", 32), title="Dune", author="Frank Herbert", format="epub" },
            { source="anna", md5=string.rep("b", 32), title="Dune Messiah", author="Frank Herbert", format="mobi" },
        }, page=1, last_page=1 }
    end,
    resolve = function(net, registry, book, settings)
        return "https://files.example/" .. book.md5 .. "." .. book.format
    end,
}
local saved_url, saved_path
local fake_net = {
    save = function(url, path)
        saved_url, saved_path = url, path
        local f = assert(io.open(path, "wb")); f:write("ebook"); f:close()
        return true
    end,
}

local fake_health = {
    run = function(net, registry, settings)
        return {
            healthy = 1,
            unhealthy = 1,
            report = {
                { name="anna", label="Anna's Archive", ok=true },
                { name="zlib", label="Z-Library", ok=false, error="login indisponível" },
            },
        }
    end,
}

local app = App.new{
    state_dir = ROOT .. "/state",
    menu_path = ROOT .. "/menu.json",
    documents_dir = ROOT .. "/documents",
    settings = fake_settings,
    registry = fake_registry,
    catalog = fake_catalog,
    health = fake_health,
    net = fake_net,
}

local ok, err = app:dispatch("init")
T.ok("kual init gera menu", ok == true and err == nil)
local mf = io.open(ROOT .. "/menu.json", "rb")
local initial = mf and mf:read("*a") or ""
if mf then mf:close() end
T.ok("menu tem submenu GaloisLibrary", initial:find('"name":"GaloisLibrary"', 1, true) ~= nil)
T.ok("menu tem teclado", initial:find('"name":"Teclado A-I"', 1, true) ~= nil)
T.ok("menu não menciona KOReader", initial:find("KOReader", 1, true) == nil)
T.ok("menu oferece atualização KUAL-only", initial:find("./update.sh", 1, true) ~= nil)

for c in ("DUNE"):gmatch(".") do assert(app:dispatch("key", c)) end
local state = app:load_state()
T.eq("teclado monta consulta", state.query, "DUNE")

assert(app:dispatch("backspace"))
assert(app:dispatch("key", "E"))
state = app:load_state()
T.eq("backspace atualiza consulta", state.query, "DUNE")

assert(app:dispatch("search"))
state = app:load_state()
T.eq("pesquisa persiste dois resultados", #state.results, 2)
T.eq("pesquisa mantém título", state.results[1].title, "Dune")

mf = io.open(ROOT .. "/menu.json", "rb")
local searched = mf and mf:read("*a") or ""
if mf then mf:close() end
T.ok("menu mostra resultados", searched:find("Dune Messiah", 1, true) ~= nil)
T.ok("resultado oferece download", searched:find("./run.sh download 1", 1, true) ~= nil)

assert(app:dispatch("download", "1"))
state = app:load_state()
T.ok("download atualiza status", state.status:find("Baixado:", 1, true) == 1)
T.ok("download usa URL resolvida", saved_url and saved_url:find(string.rep("a", 32), 1, true) ~= nil)
T.eq("download salva em documents", saved_path, ROOT .. "/documents/Dune - Frank Herbert.epub")
local df = io.open(saved_path, "rb")
T.ok("arquivo baixado existe", df ~= nil)
if df then df:close() end

assert(app:dispatch("toggle", "zlib"))
T.ok("toggle ativa fonte", enabled_state.zlib == true)
mf = io.open(ROOT .. "/menu.json", "rb")
local toggled_menu = mf and mf:read("*a") or ""
if mf then mf:close() end
T.ok("menu mostra estado da fonte", toggled_menu:find("[ON] Z-Library", 1, true) ~= nil)

assert(app:dispatch("health"))
state = app:load_state()
T.ok("health fica visível no status", state.status:find("1 OK", 1, true) ~= nil)
T.ok("health mostra fonte com problema", state.status:find("Z-Library", 1, true) ~= nil)

-- Nova instância deve recuperar consulta/resultados do disco.
local app2 = App.new{
    state_dir = ROOT .. "/state",
    menu_path = ROOT .. "/menu.json",
    documents_dir = ROOT .. "/documents",
    settings = fake_settings,
    registry = fake_registry,
    catalog = fake_catalog,
    health = fake_health,
    net = fake_net,
}
local restored = app2:load_state()
T.eq("estado persiste consulta", restored.query, "DUNE")
T.eq("estado persiste resultados", #restored.results, 2)

local throwing_catalog = {
    search = fake_catalog.search,
    resolve = function() error("resolver explodiu") end,
}
local error_app = App.new{
    state_dir = ROOT .. "/state",
    menu_path = ROOT .. "/menu.json",
    documents_dir = ROOT .. "/documents",
    settings = fake_settings,
    registry = fake_registry,
    catalog = throwing_catalog,
    health = fake_health,
    net = fake_net,
}
local survived, dispatched = pcall(function()
    return error_app:dispatch("download", "1")
end)
T.ok("exceção do resolver não derruba o app", survived and dispatched == true)
local error_state = error_app:load_state()
T.ok("erro do resolver fica visível", error_state.status:find("Falha ao resolver", 1, true) ~= nil)

local throwing_net = {
    save = function() error("download explodiu") end,
}
local save_error_app = App.new{
    state_dir = ROOT .. "/state",
    menu_path = ROOT .. "/menu.json",
    documents_dir = ROOT .. "/documents",
    settings = fake_settings,
    registry = fake_registry,
    catalog = fake_catalog,
    health = fake_health,
    net = throwing_net,
}
survived, dispatched = pcall(function()
    return save_error_app:dispatch("download", "1")
end)
T.ok("exceção do download não derruba o app", survived and dispatched == true)
error_state = save_error_app:load_state()
T.ok("erro do download fica visível", error_state.status:find("Falha no download", 1, true) ~= nil)

local failing_enabled = false
local failing_settings = {
    enabled = function() return failing_enabled end,
    set = function() return nil, "armazenamento somente leitura" end,
}
local settings_error_app = App.new{
    state_dir = ROOT .. "/state",
    menu_path = ROOT .. "/menu.json",
    documents_dir = ROOT .. "/documents",
    settings = failing_settings,
    registry = fake_registry,
    catalog = fake_catalog,
    health = fake_health,
    net = fake_net,
}
assert(settings_error_app:dispatch("toggle", "zlib"))
error_state = settings_error_app:load_state()
T.ok("falha de persistência fica visível", error_state.status:find("Falha ao salvar fonte", 1, true) ~= nil)
T.ok("falha não anuncia fonte ativada", error_state.status:find("ativada", 1, true) == nil)

local throwing_settings = {
    enabled = function() return false end,
    set = function() error("filesystem explodiu") end,
}
local settings_throw_app = App.new{
    state_dir = ROOT .. "/state",
    menu_path = ROOT .. "/menu.json",
    documents_dir = ROOT .. "/documents",
    settings = throwing_settings,
    registry = fake_registry,
    catalog = fake_catalog,
    health = fake_health,
    net = fake_net,
}
survived, dispatched = pcall(function()
    return settings_throw_app:dispatch("toggle", "zlib")
end)
T.ok("exceção de persistência não derruba app", survived and dispatched == true)
error_state = settings_throw_app:load_state()
T.ok("exceção de persistência fica visível", error_state.status:find("Falha ao salvar fonte", 1, true) ~= nil)

local query_path = ROOT .. "/state/query.txt"
local query_before_handle = assert(io.open(query_path, "rb"))
local query_before = query_before_handle:read("*a")
query_before_handle:close()
local real_open = io.open
io.open = function(path, mode)
    local handle, open_err = real_open(path, mode)
    if handle and mode == "wb" and path:sub(-4) == ".tmp" then
        return {
            write = function() return nil, "disk full" end,
            close = function() return handle:close() end,
        }
    end
    return handle, open_err
end
survived, dispatched, dispatch_err = pcall(function()
    local ok, err = app:dispatch("key", "X")
    return ok, err
end)
io.open = real_open
T.ok("falha de write não derruba app", survived)
T.ok("falha de write faz dispatch falhar", dispatched == nil and type(dispatch_err) == "string")
local query_after_handle = assert(io.open(query_path, "rb"))
local query_after = query_after_handle:read("*a")
query_after_handle:close()
T.eq("falha de write preserva estado anterior", query_after, query_before)

io.open = function(path, mode)
    local handle, open_err = real_open(path, mode)
    if handle and mode == "wb" and path:sub(-4) == ".tmp" then
        return {
            write = function(_, value) return handle:write(value) end,
            close = function()
                handle:close()
                return nil, "delayed I/O error"
            end,
        }
    end
    return handle, open_err
end
survived, dispatched, dispatch_err = pcall(function()
    local ok, err = app:dispatch("key", "Y")
    return ok, err
end)
io.open = real_open
T.ok("falha de close não derruba app", survived)
T.ok("falha de close faz dispatch falhar", dispatched == nil and type(dispatch_err) == "string")
query_after_handle = assert(io.open(query_path, "rb"))
query_after = query_after_handle:read("*a")
query_after_handle:close()
T.eq("falha de close preserva estado anterior", query_after, query_before)

T.done()
