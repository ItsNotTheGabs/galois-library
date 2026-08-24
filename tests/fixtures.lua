-- tests/fixtures.lua
-- Fixtures sinvainéticas (estruturas documentadas; non capturadas en vivo,
-- porque AA está detrás de DDoS-Guard desde esta máquina). Proban o CONTRATO
-- de cada fonte, non o rendering real.

local F = {}

-- Tarxeta de resultado estilo Anna's Archive (estrutura que descobre KindleFetch):
--   card:  <div class="flex pt-3 pb-3 border-b border-gray-200">
--   md5:   href="/md5/<32 hex>"
--   título:  div ... text-violet-900 ... data-content="..."
--   autor:   div ... text-amber-800 ... data-content="..."
--   descri:  div ... font-semibold text-sm leading-[1.2] mt-2 [data-content]
--   extensão: no nome do arquivo en a tarxeta (".epub", ".pdf", ...)
local MD5_A = string.rep('a', 32)
local MD5_B = string.rep('b', 32)

local function card(md5, title, author, ext, desc)
    return '<div class="flex pt-3 pb-3 border-b border-gray-200">'
        .. '<div class="w-16 h-24 bg-gray-200"></div>'
        .. '<div class="grow px-4 py-2">'
        .. '<div class="font-bold text-violet-900 line-clamp-[5]" data-content="' .. title .. '">' .. title .. '</div>'
        .. '<div class="font-bold text-amber-800 line-clamp-[2]" data-content="' .. author .. '">' .. author .. '</div>'
        .. '<div class="text-gray-800 font-semibold text-sm leading-[1.2] mt-2" data-content="'
        .. (desc or '') .. '">' .. (desc or '') .. '</div>'
        .. '<div class="flex items-center gap-1">'
        .. '<div class="category-card text-product-title"> file-name.' .. ext .. '</div>'
        .. '<a href="/md5/' .. md5 .. '" class="text-blue-600">Download</a>'
        .. '</div></div></div>'
end

F.HTML_TWO_RESULTS =
      '<html><body>(header)</body>'
    .. card(MD5_A, 'Pride and Prejudice', 'Jane Austen', 'epub', 'A classic novel')
    .. card(MD5_B, 'Second Book', 'Another', 'pdf', '')
    .. '</html>'

F.HTML_EMPTY = '<html><body>no results at all</body></html>'
F.MD5_A = MD5_A
F.MD5_B = MD5_B

-- Respostas de Z-Library (eapi)
F.ZLIB_SEARCH_JSON = [[
{"time":1730000000,"books":[
  {"id":1001,"hash":"abc123","title":"Dune","author":"Frank Herbert","extension":"epub"},
  {"id":1002,"hash":"def456","title":"Neuromancer","author":"William Gibson","extension":"mobi"}
],"total":2}
]]

F.ZLIB_MD5_REDIRECT = '<html><body>Redirecting to <a href="/book/1001/abc123">go</a></body></html>'
F.ZLIB_FILE_JSON = '{"downloadLink":"https://dl.zlib.example/book/1001.epub","description":"Dune"}'
F.ZLIB_SEARCH_EMPTY = '{"time":1730000000,"books":[],"total":0}'

return F