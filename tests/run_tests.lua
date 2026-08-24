-- tests/run.lua
-- Executa todos os tests. Uso:
--   lua tests/run.lua
----------------------------------------------------------------------------

package.path = "./?.lua;./sources/?.lua;./tests/?.lua;" .. package.path

local os = require("os")
local T = require("run")      -- test-runner
local F = require("fixtures") -- fixtures sintéticas

-- ---- stubs de rede (contrato da fonte) ----
-- cada fonte recibe `net` vía inxección; aquí simulamos respostas.
local function fake_net(routes)
    return {
        get = function(url, timeout)
            local body = routes[url]
            if body == nil then return nil, "404 stub: " .. url end
            return body
        end,
        _routes = routes,
    }
end

-- ---- 1. Fonte Anna: parse_search ----
local anna = require("anna")
local books = anna.parse_search(F.HTML_TWO_RESULTS)
T.eq("anna: 2 resultados", #books, 2)
T.eq("anna md5 primer", books[1].md5, F.MD5_A)
T.eq("anna md5 segundo", books[2].md5, F.MD5_B)
T.eq("anna título", books[1].title, "Pride and Prejudice")
T.eq("anna autor", books[1].author, "Jane Austen")
T.eq("anna formato epub", books[1].format, "epub")
T.eq("anna formato pdf segundo", books[2].format, "pdf")
T.eq("anna descrición", books[1].description, "A classic novel")
T.eq("anna source", books[1].source, "anna")
T.ok("anna cover_url presente", type(books[1].cover_url) == "string"
    and string.find(books[1].cover_url, "covers.example", 1, true) ~= nil)
T.ok("anna cover_url do 2º diferente", books[2].cover_url ~= books[1].cover_url)
T.eq("anna baleiro", #anna.parse_search(F.HTML_EMPTY), 0)

-- ---- 1b. Anna search() vía rede ----
local netA = fake_net({ ["https://annas-archive.gl/search?page=1&q=pride&content=book"] = F.HTML_TWO_RESULTS })
local res, err = anna.search(netA, "pride", 1, {})
T.ok("anna search ok", res ~= nil)
T.eq("anna search 2 libros", res and #res.results or -1, 2)

-- ---- health: DOBRA probe (espelho) ----
-- mirror ok + search ok
local nhm = fake_net({
    ["https://libgen.li/ads.php?md5=" .. string.rep("0", 32)] =
        '<a href="get.php?md5=0000&key=x">download</a>',
    ["https://annas-archive.gl/search?q=galois+health&page=1&content=book"] =
        '<div class="flex pt-3 pb-3 border-b border-gray-200">' ..
        '<a href="/md5/' .. string.rep('c', 32) .. '">x</a></div>',
})
local hbio = anna.health(nhm, {})
T.eq("anna.health: mirror ok -> ok", hbio.ok, true)

-- mirror ok + busca bloqueada (DDoS) -> AINDA ok com nota (download funciona)
local nhm2 = fake_net({
    ["https://libgen.li/ads.php?md5=" .. string.rep("0", 32)] =
        '<div><a href="get.php?md5=0&key=y">d</a></div>',
    ["https://annas-archive.gl/search?q=galois+health&page=1&content=book"] =
        '<script src="/.well-known/ddos-guard/js-challenge/index.js"></script>',
})
local hb2 = anna.health(nhm2, { mirrors = { "https://libgen.li" } })
T.eq("anna.health: mirror ok + busca bloqueada -> ok", hb2.ok, true)
T.ok("anna.health: nota menciona DDoS-Guard", string.find(hb2.note or "", "DDoS", 1, true) ~= nil)

-- mirror morto -> caído
local nhm3 = fake_net({})
local hb3 = anna.health(nhm3, { mirrors = { "https://libgen.li" } })
T.eq("anna.health: mirror morto -> caído", hb3.ok, false)

-- resolve_download: fallback entre espelhos
local netfb = fake_net({
    ["https://libgen.is/ads.php?md5=" .. F.MD5_A] = "sem get.php",
    ["https://libgen.li/ads.php?md5=" .. F.MD5_A] = '<a href="get.php?md5=' .. F.MD5_A .. '&key=2">d</a>',
})
local ufb = anna.resolve_download(netfb, { md5 = F.MD5_A }, { mirrors = { "https://libgen.is", "https://libgen.li" } })
T.eq("resolve: segunda mirror usada", ufb, "https://libgen.li/get.php?md5=" .. F.MD5_A .. "&key=2")

-- ---- 1c. Anna resolve_download() via 'lgli' ----
local lgli_html = '<html><a href="/get.php?md5=' .. F.MD5_A .. '&key=1">download</a></html>'
local netR = fake_net({ ["https://libgen.so/ads.php?md5=" .. F.MD5_A] = lgli_html })
local url = anna.resolve_download(netR, { md5 = F.MD5_A }, {})
T.eq("AD let ok", url, "https://libgen.so/get.php?md5=" .. F.MD5_A .. "&key=1")

-- ========= 3. Test Z-Library search ----
local zlib = require("zlib")
local nz = fake_net({
    ["https://z-lib.io/eapi/search?query=dune&page=1"] = F.ZLIB_SEARCH_JSON,
})
local zr, zerr = zlib.search(nz, "dune", 1, {})
T.ok("zlib search ok", zr ~= nil)
T.eq("zlib 2 books", zr and #zr.results or -1, 2)
T.eq("zlib titulo", zr and zr.results[1].title or "", "Dune")
T.eq("zlib source", zr and zr.results[1].source or "", "zlib")

-- ---- 3b. ZLib resolve via /md5 -> /eapi/book ----
local nzr = fake_net({
    ["https://z-lib.io/md5/1001"] = F.ZLIB_MD5_REDIRECT,
    ["https://z-lib.io/eapi/book/1001/abc123/file"] = F.ZLIB_FILE_JSON,
})
local zurl, zerr2 = zlib.resolve_download(nzr, { md5 = "1001" }, {})
T.eq("zlib url", zurl, "https://dl.zlib.example/book/1001.epub")
T.ok("zlib erro eapi ausente", (function()
    local n2 = fake_net({ ["https://z-lib.io/md5/x"] = F.ZLIB_MD5_REDIRECT })
    local u, e = zlib.resolve_download(n2, { md5 = "x" }, {})
    return e ~= nil
end)())

-- ========= 4. Test Settings (toggle persistencia) ----
local settings = require("settings")
local fs_mem = { data = nil }
local fake_fs = {
    read = function(_) return fs_mem.data end,
    write = function(_, d) fs_mem.data = d end,
}
local s = settings.new({ path = "/tmp/x", fs = fake_fs, defaults = { anna = true, zlib = true } })
T.eq("set default anna on", s:enabled("anna"), true)
T.eq("set zlib default on", s:enabled("zlib"), true)
s:set("zlib", false)
T.eq("set zlib off", s:enabled("zlib"), false)
T.eq("set persisted", fs_mem.data and fs_mem.data:find("zlib=0") ~= nil, true)

-- ========= 5. Test Catalog (toggle affect) ----
local reg = require("sources.init")
reg.register_all({ anna = anna, zlib = zlib })
local catalog = require("catalog")

-- ambas activas
local cs = settings.new({ defaults = { anna = true, zlib = true } })
local nboth = fake_net({
    ["https://annas-archive.gl/search?page=1&q=x&content=book"] = F.HTML_TWO_RESULTS,
    ["https://z-lib.io/eapi/search?query=x&page=1"] = F.ZLIB_SEARCH_JSON,
})
local cr, cerr = catalog.search(nboth, reg, "x", 1, cs)
T.ok("catalog ambas activas ok", cr ~= nil)
T.eq("catalog 2+2=4", cr and #cr.results or -1, 4)

-- so Anna
local cs_a = settings.new({ defaults = { anna = true, zlib = false } })
local na = fake_net({ ["https://annas-archive.gl/search?page=1&q=x&content=book"] = F.HTML_TWO_RESULTS })
local cr_a = catalog.search(na, reg, "x", 1, cs_a)
T.eq("catalog só anna (2)", cr_a and #cr_a.results or -1, 2)

-- so zlib
local cs_z = settings.new({ defaults = { zlib = true } })
local nz2 = fake_net({ ["https://z-lib.io/eapi/search?query=x&page=1"] = F.ZLIB_SEARCH_JSON })
local cz = catalog.search(nz2, reg, "x", 1, cs_z)
T.eq("catalog só zlib (2)", cz and #cz.results or -1, 2)

-- ningún activo -> erro
local nada = settings.new({ defaults = { anna = false, zlib = false } })
local ce, cerr2 = catalog.search(fake_net({}), reg, "x", 1, nada)
T.ok("catalog sen fontes -> nil", ce == nil and cerr2 ~= nil)

-- ========= 6. Test: validación do contrato ----
local sources_mod = require("sources.init")
T.ok("validate anna", sources_mod.validate(anna))
T.ok("validate zlib", sources_mod.validate(zlib))
T.ok("validate fake-broken", (function()
    local _, e = sources_mod.validate({ META = { name = "x" } })
    return e ~= nil
end)())

T.done()