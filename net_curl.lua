-- net_curl.lua
-- Implementación real de `net` para o contrato de fonte, usando `curl`.
-- Funciona tanto no desktop Linux como no Kindle jailbreakeado (curl está en bin).
-- Cumpre o contrato: net.get(url, timeout_s) -> body (string) | nil, err

local C = {}

local function shell_quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- get(url, timeout) -> body (string) | nil, motivo
function C.get(url, timeout)
    timeout = timeout or 20
    local cmd = string.format("curl -s -m %d -A 'Mozilla/5.0 (galois-library)' %s",
        timeout, shell_quote(url))
    local f = io.popen(cmd, "r")
    if not f then return nil, "non podo executar curl" end
    local body = f:read("*a")
    local ok = f:close()
    if body == nil or body == "" then
        return nil, "curl resposta baleira (status " .. tostring(ok) .. ")"
    end
    return body
end

-- save(url, path, timeout) -> true | nil, motivo
-- Descarga e escribe directo a un arquivo (sen cargalo todo en memoria).
-- Inclúe retry (2) e resume (-C -) para redes paradas/kindle wifi caseiro.
function C.save(url, path, timeout)
    timeout = timeout or 30
    local cmd = string.format(
        "curl -s -m %d -L --retry 2 --retry-delay 2 -C - -A 'Mozilla/5.0 (galois)' -o %s %s",
        timeout, shell_quote(path), shell_quote(url))
    local f = io.popen(cmd, "r")
    if not f then return nil, "non podo executar curl save" end
    f:read("*a")
    f:close()
    -- comprobar que o arquivo existe e non está baleiro
    local h = io.open(path, "rb")
    if not h then return nil, "arquivo non gravado: " .. path end
    local size = h:seek("end")
    h:close()
    if size == 0 then return nil, "descarga baleira: " .. url end
    return true
end

return C