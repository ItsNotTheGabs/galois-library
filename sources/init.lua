-- sources/init.lua
-- Registro de fontes pluggables para o catalogo de ebooks.
--
-- CONTRATO DE FONTE: qualquer fonte nova (anna, zlib, futuras...) deve exponer:
--   meta = { name="<id unico>", label="Nome legible", enabled_default=true|false }
--   search(net, query, page, settings) -> { books={...}, page, last_page } | nil, error
--   resolve_download(net, book, settings) -> url_string | nil
--
-- `net` é inyectado em runtime para poder stubear nas tests:
--   net.get(url, timeout_s) -> { status, body, url_effective } | nil, err_msg
--
-- `book` = { md5, title, author, format, description, source }
-- As fuentes fan **só** raspado/parse; nenhuma chama a rede directamente (via `net`).

local M = {}

-- fontes cargadas: { [name] = modulo }
local registry = {}
-- orden de presentación / resultado
local order = {}

local function load_source(name, mod)
    if not mod or type(mod) ~= "table" or not mod.META then
        return nil, "fuente '" .. tostring(name) .. "' sen contrato valido"
    end
    registry[name] = mod
    table.insert(order, name)
    return mod
end

function M.list()
    local out = {}
    for _, name in ipairs(order) do
        out[#out+1] = registry[name]
    end
    return out
end

-- Função para o app cargar todas las fuentes disponibles.
-- recibe um directorio impl de fuentes (ops):
--   { anna = require("sources.anna"), zlib = require("sources.zlib"), ... }
function M.register_all(impls)
    for name, mod in pairs(impls) do
        load_source(name, mod)
    end
end

-- busca a unha fonte polo nombre
function M.get(name)
    return registry[name]
end

-- valida implementação de unha fonte antes de usala
function M.validate(mod)
    if not mod.META then return false, "falta META" end
    if type(mod.META.name) ~= "string" or type(mod.META.label) ~= "string" then
        return false, "META.name/label han de ser strings"
    end
    if type(mod.search) ~= "function" then return false, "falta search()" end
    if type(mod.resolve_download) ~= "function" then return false, "falta resolve_download()" end
    return true
end

return M