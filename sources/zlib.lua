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

------------------------------------------------------------------------------
-- Mini parser JSON (Lua puro).
------------------------------------------------------------------------------

local function j_ws(s, i)
    local c = string.sub(s, i, i)
    while c == ' ' or c == '\n' or c == '\r' or c == '\t' do
        i = i + 1
        c = string.sub(s, i, i)
    end
    return i
end

local function j_str(s, i)
    -- i apunta a un `"`. Devolve (valor sin comillas, índice tras pechar).
    local acc, j = {}, i + 1
    while j <= #s do
        local ch = string.sub(s, j, j)
        if ch == '"' then
            return table.concat(acc), j + 1
        elseif ch == '\\' then
            local esc = string.sub(s, j + 1, j + 1)
            local map = { ['n'] = '\n', ['t'] = '\t', ['r'] = '\r',
                          ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
            acc[#acc + 1] = map[esc] or esc
            j = j + 2
        else
            acc[#acc + 1] = ch
            j = j + 1
        end
    end
    return table.concat(acc), i
end

local function j_num(s, i)
    local j = i
    while string.match(string.sub(s, j, j), '[0-9%.eE%+%-]') do j = j + 1 end
    return tonumber(string.sub(s, i, j - 1)), j
end

local function j_val(s, i)
    i = j_ws(s, i)
    local c = string.sub(s, i, i)
    if c == '"' then
        return j_str(s, i)
    elseif c == '{' then
        local obj, j = {}, j_ws(s, i + 1)
        if string.sub(s, j, j) == '}' then return obj, j + 1 end
        while true do
            local key, nk = j_str(s, j)
            j = j_ws(s, nk)
            j = j + 1 -- ':'
            local val, nv = j_val(s, j)
            j = nv
            obj[key] = val
            j = j_ws(s, j)
            local sep = string.sub(s, j, j)
            if sep == ',' then
                j = j_ws(s, j + 1)
            elseif sep == '}' then
                return obj, j + 1
            end
        end
    elseif c == '[' then
        local arr, j = {}, j_ws(s, i + 1)
        if string.sub(s, j, j) == ']' then return arr, j + 1 end
        while true do
            local val, nv = j_val(s, j)
            j = nv
            arr[#arr + 1] = val
            j = j_ws(s, j)
            local sep = string.sub(s, j, j)
            if sep == ',' then
                j = j_ws(s, j + 1)
            elseif sep == ']' then
                return arr, j + 1
            end
        end
    else
        return j_num(s, i)
    end
end

local function parse_json(s)
    if not s then return nil end
    local val = j_val(s, 1)
    return val
end

-----------------------------------------------------------------------------
-- Endpoint eapi devolve: { "books": [ {id, hash, title, author, extension} ], "total":N }
-----------------------------------------------------------------------------

local function parse_books_body(body)
    local data = parse_json(body)
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

function Z.resolve_download(net, book, opts)
    opts = opts or {}
    local base = opts.zlib_base or "https://z-lib.io"
    local redir, err = net.get(base .. "/md5/" .. book.md5, 20)
    if not redir then return nil, "zlib resolve (md5): " .. tostring(err) end

    local bid = string.match(redir, '/book/(%d+)/')
    local bhash = string.match(redir, '/book/%d+/([%w%+%-%.]+)')
    if not bid or not bhash then return nil, "zlib: non atopou id/hash en /md5/" end

    local json, jerr = net.get(base .. "/eapi/book/" .. bid .. "/" .. bhash .. "/file", 20)
    if not json then return nil, "zlib resolve (eapi): " .. tostring(jerr) end
    local data = parse_json(json)
    if type(data) ~= "table" or not data.downloadLink then
        return nil, "zlib: resposta eapi sen downloadLink"
    end
    return data.downloadLink
end

return Z