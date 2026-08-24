-- sources/init.lua
-- Registro de fontes pluggables para o catalogo de ebooks.
--
-- CONTRATO DE FONTE: cualquier fonte nova (anna, zlib, futuras...) debe exponer:
--   meta = { name="<id unico>", label="Nome legible", enabled_default=true|false }
--   search(net, query, page, settings) -> { books={...}, page, last_page } | nil, error
--   resolve_download(net, book, settings) -> url_string | nil
--   health(net, settings) -> { ok=true } | { ok=false, error="motivo" }
--       Probe mínimo (busca básica) para detectar se a fonte está SAUDÁVEL.
--       É o que alimenta o status nas configs e o monitor ("fonte morreu?").
--
-- `net` é inyectado en runtime para poder stubear nas tests:
--   net.get(url, timeout_s) -> body (string) | nil, err_msg
--   net.save(url, path, timeout_s) -> true | nil, err_msg   (para downloads)
--
-- `book` = { md5, title, author, format, description, source, cover_url? }
--   cover_url (opcional): URL da capa, preenchida pela fonte no parse de busca.
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
-- recibe unha táboa { name = module, ... }; garda en orde alfabética
-- (determinista — a UI non quere resultados en orde aleatoria).
function M.register_all(impls)
    local names = {}
    for name in pairs(impls) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        load_source(name, impls[name])
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
    if type(mod.health) ~= "function" then return false, "falta health() (status da fonte)" end
    return true
end

return M