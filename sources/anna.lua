-- sources/anna.lua
-- Fonte: Anna's Archive (metadados + capas) com descarga via espelhos Libgen.
--
-- ARQUITECTURA: todo o parser está ILLADO neste ficheiro. Se o HTML do AA cambia
-- (anti-scrape), só se toca aquí; os tests con fixture garanten o contrato.
--
-- ✔ VALIDADO AO VIVO (2026-08-24):
--   * A busca do AA está tras DDoS-Guard JS-challenge em IPs de datacenter;
--     user-agents de bot (ClaudeBot/GPTBot/ChatGPT-User) NÃO a contornam.
--     IPs residenciais (o Wi-Fi do usuário) costuman passar sem challenge.
--   * O caminho de DESCARGA NÃO passa pelo DDoS-Guard: libgen.li/ads.php?md5=
--     -> get.php?md5=..&key=.. -> 200 -> CDN cdn*.booksdl.lc (testado live).
--   * health() separa: saúde da busca (pode estar bloqueada no datacenter) e
--     saúde do espelho de descarga (o caminho crítico).

local A = {}

A.META = {
    name = "anna",
    label = "Anna's Archive",
    enabled = true,
}

-- espellos de descarga (orde de tentativa); o primeiro que responda usa-se
A.MIRRORS = { "https://libgen.li", "https://libgen.is", "https://libgen.so" }

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

-- extrae a URL da capa: primeira <img ... src="..."> na tarxeta
local function grab_cover(slice)
    local im = string.find(slice, '<img', 1, true)
    if not im then return nil end
    -- procura src="..." (ou data-src="..." para lazy load) en texto plano
    local a = string.find(slice, 'src="', im, true)
    local start
    if a then start = a + 5 else
        a = string.find(slice, 'data-src="', im, true)
        if a then start = a + 9 end -- 'data-src="' ten 9 chars
    end
    if not a then return nil end
    local stop = string.find(slice, '"', start, true)
    if not stop then return nil end
    local src = string.sub(slice, start, stop - 1)
    if src == "" then return nil end
    -- ignorar glitter/spinner/pixel
    if string.find(src, 'spinner', 1, true) or string.find(src, 'pixel', 1, true)
       or string.find(src, 'blank', 1, true) or string.find(src, '.svg', 1, true) then
        return nil
    end
    return html_unescape(src)
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

        local cover_url = grab_cover(slice)

        if md5 and title then
            books[#books + 1] = {
                md5 = md5, title = title, author = author,
                format = format, description = description,
                cover_url = cover_url,
                source = A.META.name,
            }
        end
    end
    return books
end

-- search: descarga e parse da páxina de busca do AA.
function A.search(net, query, page, opts)
    page = page or 1
    local q = string.gsub(tostring(query), '%s+', '+')
    local url = "https://annas-archive.gl/search?page=" .. page .. "&q=" .. q .. "&content=book"
    local body, err = net.get(url, 20)
    if not body then return nil, "anna: " .. tostring(err) end
    return { results = A.parse_search(body), page = page, last_page = 1 }
end

-- health: DOBRA probe — estado da busca (no gate) e estado do espelho de
-- descarga (o camiño crítico). ok = a descarga pode funcionar.
function A.health(net, opts)
    opts = opts or {}

    -- (1) espelho de descarga: ads.php responde e contén get.php?
    local mirrors = opts.mirrors or A.MIRRORS
    local mirror_ok = false
    local notes = ""
    for _, m in ipairs(mirrors) do
        local body, err = net.get(m .. "/ads.php?md5=" .. string.rep("0", 32), 12)
        if body and string.find(body, "get.php", 1, true) then
            mirror_ok = true
            break
        elseif body then
            notes = "espelho " .. m .. " respondeu sen get.php"
        else
            notes = "espelho " .. m .. " sem resposta: " .. tostring(err)
        end
    end

    -- 2. busca AA (pode estar tras challenge no datacenter; residencial passa)
    local base = opts.anna_base or "https://annas-archive.gl"
    local sbody, serr = net.get(base .. "/search?q=galois+health&page=1&content=book", 12)
    local search_note = nil
    if not sbody then
        search_note = "busca sem resposta: " .. tostring(serr)
    elseif string.find(string.lower(sbody), "fingerprint", 1, true)
        or string.find(string.lower(sbody), "ddos-guard", 1, true) then
        search_note = "busca tras DDoS-Guard (espérase en IPs de datacenter; no residencial adoita pasar)"
    elseif not (string.find(sbody, "/md5/", 1, true) or string.find(sbody, "flex pt-3 pb-3", 1, true)) then
        search_note = "busca respondeu sen resultados/tarxetas"
    end

    if mirror_ok then
        local out = { ok = true }
        if search_note then out.note = search_note end
        return out
    end
    return { ok = false, error = "espelho de descarga indispoñible: " .. (notes or "?") }
end

-- __resolve_aux: de um corpo de ads.php devolve a URL do get.php (ou nil)
local function extract_get_url(body)
    -- procura o href CUJO valor contén get.php (robusto: ignora outros href da páxina)
    return string.match(body, 'href%s*=%s*"([^"]*get%.php[^"]*)"')
end

-- resolve_download: tenta en orde os espellos e devolve a URL directa (get.php).
function A.resolve_download(net, book, opts)
    opts = opts or {}
    local mirrors = opts.mirrors or A.MIRRORS
    local last_err = nil
    for _, lgli in ipairs(mirrors) do
        local ads = lgli .. "/ads.php?md5=" .. book.md5
        local body, err = net.get(ads, 30)
        if not body then
            last_err = lgli .. ": " .. tostring(err)
        else
            local url = extract_get_url(body)
            if not url then
                last_err = lgli .. ": sen get.php na resposta"
            else
                if string.match(url, '^http') then return url end
                return lgli .. "/" .. url:gsub("^/", "")
            end
        end
    end
    return nil, "anna resolve: " .. tostring(last_err or "sen espello dispoñible")
end

return A