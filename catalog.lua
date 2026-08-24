-- catalog.lua
-- Coordina a busca entre todas as fuentes ativas (respeitando settings.enabled).
-- Entrega os resultados plurados, cada libro marcado co nome da sua fonte.

local C = {}

-- search(net, registry, settings, query, page) ->
--   { results = { book, ... }, page, last_page }     on success
--   nil, msg  on total failure (sem fuentes ativas, etc.)
function C.search(net, registry, query, page, settings)
    local sources = registry.list()
    local out = {}
    local have = false
    local last_page = 1

    for _, mod in ipairs(sources) do
        if not settings or settings:enabled(mod.META.name) then
            local ok, res = pcall(mod.search, net, query, page, {})
            if ok and res and res.results then
                have = true
                for _, b in ipairs(res.results) do
                    b.source = mod.META.name
                    out[#out+1] = b
                end
                if res.last_page and res.last_page > last_page then
                    last_page = res.last_page
                end
            end
        end
    end

    if not have then
        return nil, "ninguna fonte ativa devolviu resultados"
    end

    return { results = out, page = page, last_page = last_page }
end

-- C.resolve(net, registry, book, settings) -> url (string) or nil, err
-- Intentaa resolver download coa fonte que devolveu o libro.
-- (repassa as settings como opts, para mirrors etc. configurables no usuario)
function C.resolve(net, registry, book, settings)
    local mod = registry.get(book.source)
    if not mod then return nil, "fonte desconocida: " .. tostring(book.source) end
    return mod.resolve_download(net, book, settings or {})
end

return C