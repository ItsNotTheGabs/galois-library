-- sources/anna.lua
-- Fonte: Anna's Archive. Parsing HTML simple (lista de resultados).
--
-- ARQUITECTURA: todo o parser está ILLADO neste ficheiro. Se o HTML do AA cambia
-- (anti-scrape), só se toca aquí; os tests con fixture garanten o contrato.
--
-- Dado o id (md5) dun libro, resolve_download() usa a rota de espello 'lgli'
-- (proxy Libgen) como KindleFetch, evitando o challenge do AA cando sexa posible.
-- Esta rota require VERIFICACIÓN live (neste entorno está tras DDoS-Guard).

local A = {}

A.META = {
    name = "anna",
    label = "Anna's Archive",
    enabled = true,
}

-- ---- helpers ----

-- acha todas as ocurrrencias dun substring simple; devolve lista de offsets
local function find_all(s, anchor)
    local pos, acc = 1, {}
    while true do
        local a, b = string.find(s, anchor, pos, true)
        if not a then break end
        acc[#acc + 1] = a
        pos = b + 1
    end
    return acc
end

-- le `attr="..."` a partir de `from`; nil se non o hacha
local function read_attr(s, from, attr)
    local a = string.find(s, attr, from, true)
    if not a then return nil end
    local q1 = string.find(s, '"', a + #attr + 1, true)
    if not q1 then return nil end
    local q2 = string.find(s, '"', q1 + 1, true)
    if not q2 then return nil end
    return string.sub(s, q1 + 1, q2 - 1)
end

local function html_unescape(s)
    s = string.gsub(s, '&amp;', '&')
    s = string.gsub(s, '&quot;', '"')
    s = string.gsub(s, '&lt;', '<')
    s = string.gsub(s, '&gt;', '>')
    s = string.gsub(s, '&#39;', "'")
    return s
end

-- cada tarxeta de resultado comeza por este div
local CARD_OPEN = '<div class="flex pt-3 pb-3 border-b border-gray-200">'

-- extrae 32 caracteres hex despois dun prefix "/md5/"
local function grab_md5(slice)
    local h = string.find(slice, '/md5/', 1, true)
    if not h then return nil end
    return string.match(string.sub(slice, h + 5), '^' .. string.rep('[0-9a-fA-F]', 32))
end

-- parse_search(html) -> array de books presentes na proxía
function A.parse_search(html)
    local books = {}
    local cards = find_all(html, CARD_OPEN)
    for i = 1, #cards do
        local next = (i < #cards) and cards[i + 1] or (#html + 1)
        local slice = string.sub(html, cards[i], next - 1)

        local md5 = grab_md5(slice)

        local vt = string.find(slice, 'text-violet-900', 1, true)
        local title = vt and html_unescape(read_attr(slice, vt, 'data-content') or '') or nil

        local am = string.find(slice, 'text-amber-800', 1, true)
        local author = am and html_unescape(read_attr(slice, am, 'data-content') or '') or nil

        local ds = string.find(slice, 'font-semibold text-sm leading-[1.2] mt-2', 1, true)
        local description = ds and html_unescape(read_attr(slice, ds, 'data-content') or '') or nil

        -- formato: extensión do arquivo na tarjeta (.epub, .mobi, .pdf...)
        local format = nil
        for _, ext in ipairs({ 'epub', 'mobi', 'pdf', 'azw3', 'fb2' }) do
            local p = string.find(slice, '.' .. ext, 1, true)
            if p then format = ext break end
        end

        if md5 and title then
            books[#books + 1] = {
                md5 = md5, title = title, author = author,
                format = format, description = description,
                source = A.META.name,
            }
        end
    end
    return books
end

-- search: descarga e parse da págoaa de busca do AA.
function A.search(net, query, page, opts)
    page = page or 1
    local q = string.gsub(tostring(query), '%s+', '+')
    local url = "https://annas-archive.gl/search?page=" .. page .. "&q=" .. q .. "&content=book"
    local body, err = net.get(url, 20)
    if not body then return nil, "anna: " .. tostring(err) end
    return { results = A.parse_search(body), page = page, last_page = 1 }
end

-- health: probe mínimo — unha busca básica e determinada se a fonte responde
-- ou está tras un challenge/erro. Devolve { ok=true } ou { ok=false, error=... }.
function A.health(net, opts)
    opts = opts or {}
    local base = opts.anna_base or "https://annas-archive.gl"
    local url = base .. "/search?q=galois+health&page=1&content=book"
    local body, err = net.get(url, 15)
    if not body then
        return { ok = false, error = "sem resposta: " .. tostring(err) }
    end
    -- detectar challenges/capchas típicos
    local low = string.lower(body)
    if string.find(low, "fingerprint", 1, true) then
        return { ok = false, error = "bloqueado por challenge anti-bot (fingerprint)" }
    end
    if string.find(low, "redirecting", 1, true) and not string.find(low, "/md5/", 1, true) then
        return { ok = false, error = "redirección de protección (DDoS-Guard/anti-bot)" }
    end
    if string.find(low, "forsale", 1, true) then
        return { ok = false, error = "dominio parqueado/á venda (mirror caído)" }
    end
    -- páxina de resultados: aínda que non haya libros, a estrutura de card está
    if string.find(body, "flex pt-3 pb-3", 1, true) or string.find(body, "/md5/", 1, true) then
        return { ok = true }
    end
    -- resposta 200 pero sen marca recoñecible: consideramos "saudábel" (pode ser
    -- a páxina de "0 resultados"), pero informamos no error opcional
    return { ok = true, note = "respondeu sen tarxetas — probablemente 0 resultados" }
end

-- resolve_download: resolve unha URL directa vía proxy lgli.
function A.resolve_download(net, book, opts)
    opts = opts or {}
    local lgli = opts.lgli_base or "https://libgen.so"
    local ads = lgli .. "/ads.php?md5=" .. book.md5
    local body, err = net.get(ads, 30)
    if not body then return nil, "anna resolve: " .. tostring(err) end

    local g = string.find(body, 'get.php', 1, true)
    if not g then return nil, "anna: sen get.php na resposta lgli" end
    local gend = string.find(body, '"', g, true)
    local q = string.find(body, 'href="', 1, true)
    if not q then return nil, "anna: sen href antes de get.php" end
    -- URL = desde despois de href=" ate o peche "
    local url = string.sub(body, q + 6, gend - 1)
    if string.match(url, '^http') then return url end
    url = url:gsub('^/', '')
    return lgli .. "/" .. url
end

return A