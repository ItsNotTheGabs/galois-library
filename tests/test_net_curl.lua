-- tests/test_net_curl.lua
-- net.save só pode confirmar sucesso quando curl termina com exit 0.

local T = require("run")
local net = require("net_curl")

local ROOT = "/tmp/galois_net_curl_test"
os.execute("rm -rf '" .. ROOT .. "' && mkdir -p '" .. ROOT .. "'")

local real_popen = io.popen
local captured_get_cmd
io.popen = function(cmd)
    captured_get_cmd = cmd
    return {
        read = function() return "PAGINA-DE-ERRO" end,
        close = function() return nil, "exit", 22 end,
    }
end
local body, get_err = net.get("https://example.invalid/404", 2)
io.popen = real_popen
T.ok("get rejeita body quando curl falha", body == nil)
T.ok("get devolve erro de curl", type(get_err) == "string" and get_err ~= "")
T.ok("get usa curl -f", captured_get_cmd:find(" -f ", 1, true) ~= nil)
T.ok("get segue redirect com -L", captured_get_cmd:find(" -L ", 1, true) ~= nil)

local target = ROOT .. "/book.epub"
local f = assert(io.open(target, "wb"))
f:write("ARQUIVO-ANTIGO")
f:close()

local ok, err = net.save("file:///tmp/galois-arquivo-que-nao-existe", target, 2)
T.ok("curl com erro não aceita arquivo final antigo", not ok)
T.ok("curl com erro devolve motivo", type(err) == "string" and err ~= "")

f = assert(io.open(target, "rb"))
local old = f:read("*a")
f:close()
T.eq("falha preserva arquivo final anterior", old, "ARQUIVO-ANTIGO")

local source = ROOT .. "/source.epub"
f = assert(io.open(source, "wb"))
f:write("CONTEUDO-NOVO")
f:close()

f = assert(io.open(target .. ".part", "wb"))
f:write("LIXO")
f:close()
f = assert(io.open(target .. ".part.url", "wb"))
f:write("file:///outra-origem")
f:close()

ok, err = net.save("file://" .. source, target, 5)
T.ok("curl bem-sucedido retorna true", ok == true)
f = assert(io.open(target, "rb"))
local downloaded = f:read("*a")
f:close()
T.eq("sucesso substitui arquivo final", downloaded, "CONTEUDO-NOVO")
T.ok("sucesso remove proveniência do parcial", io.open(target .. ".part.url", "rb") == nil)

os.execute("rm -rf '" .. ROOT .. "'")
T.done()
