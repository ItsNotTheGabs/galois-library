-- net_curl.lua
-- Implementación real de `net` para o contrato de fonte, usando `curl`.
-- Funciona tanto no desktop Linux como no Kindle jailbreakeado (curl está en bin).
-- Cumpre o contrato: net.get(url, timeout_s) -> body (string) | nil, err

local C = {}

local function shell_quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- get(url, timeout_s) -> { body } ou nil, motivo
function C.get(url, timeout)
    timeout = timeout or 20
    local cmd = string.format("curl -s -m %d -A 'Mozilla/5.0 (kindle-annas-dl)' %s",
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

return C