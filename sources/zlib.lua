-- sources/zlib.lua
-- Fonte: Z-Library.
--
-- Busca vía eapi JSON de Z-Library; resolve_download() reutiliza a ruta que usa
-- KindleFetch: /md5/<md5> -> /book/<id>/<hash> -> /eapi/book/.../file -> downloadLink.
-- (Pendiente de verificación live; este entorno está tras DDoS-Guard.)
--
-- Z-Library a menudo exige login. O toggle en settings decide se esta fonte
-- participa na busca; cando falle por falta de login, search() devolve
-- nil + motivo para que o app poida notificalo ao user.

local Z = {}

Z.META = {
    name = "zlib",
    label = "Z-Library",
    enabled = true,
}

-- Reutiliza o parser JSON compartido (json.lua)
local json = require("json")

-----------------------------------------------------------------------------
-- Endpoint eapi devolve: { "books": [ {id, hash, title, author, extension} ], "total":N }
-----------------------------------------------------------------------------

local function parse_books_body(body)
    local data = json.parse(body)
    if type(data) ~= "table" or type(data.books) ~= "table" then return {} end
    local books = {}
    for _, row in ipairs(data.books) do
        local id = row.id
        if id then
            books[#books + 1] = {
                md5 = tostring(id),
                title = row.title,
                author = row.author,
                format = row.extension,
                description = nil,
                source = Z.META.name,
            }
        end
    end
    return books
end

local function urlencode(s)
    s = tostring(s)
    s = string.gsub(s, '([^%w%s])', function(c) return string.format('%%%02X', string.byte(c)) end)
    s = string.gsub(s, ' ', '+')
    return s
end

function Z.search(net, query, page, opts)
    opts = opts or {}
    local base = opts.zlib_base or "https://z-lib.io"
    local url = base .. "/eapi/search?query=" .. urlencode(query) .. "&page=" .. tostring(page or 1)
    local resp, err = net.get(url, 20)
    if not resp then return nil, "zlib: " .. tostring(err) end
    return { results = parse_books_body(resp), page = page or 1, last_page = 1 }
end

-- health: probe — busca básica no eapi. Saúde = o JSON parsea (aínda que haxa 0
-- resultados); se falla a rede ou parse, a fonte está com problema.
function Z.health(net, opts)
    opts = opts or {}
    local base = opts.zlib_base or "https://z-lib.io"
    local url = base .. "/eapi/search?query=galois+health&page=1"
    local body, err = net.get(url, 15)
    if not body then
        return { ok = false, error = "sem resposta: " .. tostring(err) }
    end
    local data = json.parse(body)
    if type(data) ~= "table" then
        return { ok = false, error = "resposta non-JSON (pode ser bloqueio/login)" }
    end
    if data.books == nil then
        return { ok = false, error = "eapi sen campo 'books'" }
    end
    return { ok = true }
end

function Z.resolve_download(net, book, opts)
    opts = opts or {}
    local base = opts.zlib_base or "https://z-lib.io"
    local redir, err = net.get(base .. "/md5/" .. book.md5, 20)
    if not redir then return nil, "zlib resolve (md5): " .. tostring(err) end

    local bid = string.match(redir, '/book/(%d+)/')
    local bhash = string.match(redir, '/book/%d+/([%w%+%-%.]+)')
    if not bid or not bhash then return nil, "zlib: non atopou id/hash en /md5/" end

    local json2, jerr = net.get(base .. "/eapi/book/" .. bid .. "/" .. bhash .. "/file", 20)
    if not json2 then return nil, "zlib resolve (eapi): " .. tostring(jerr) end
    local data = json.parse(json2)
    if type(data) ~= "table" or not data.downloadLink then
        return nil, "zlib: resposta eapi sen downloadLink"
    end
    return data.downloadLink
end

return Z