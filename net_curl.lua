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
    local cmd = string.format("curl -sS -f -L -m %d -A 'Mozilla/5.0 (galois-library)' %s 2>&1",
        timeout, shell_quote(url))
    local f = io.popen(cmd, "r")
    if not f then return nil, "non podo executar curl" end
    local body = f:read("*a") or ""
    local closed, _, exit_code = f:close()
    if not closed then
        return nil, "curl falhou (status " .. tostring(exit_code) .. "): " .. body
    end
    if body == "" then
        return nil, "curl resposta baleira"
    end
    return body
end

-- save(url, path, timeout) -> true | nil, motivo
-- Descarga e escribe directo a un arquivo (sen cargalo todo en memoria).
-- Inclúe retry (2) e resume (-C -) para redes paradas/kindle wifi caseiro.
function C.save(url, path, timeout)
    timeout = timeout or 30
    local partial = path .. ".part"
    local provenance = partial .. ".url"

    local previous_url
    local meta = io.open(provenance, "rb")
    if meta then
        previous_url = meta:read("*l")
        meta:close()
    end
    local existing = io.open(partial, "rb")
    if existing then existing:close() end
    if existing and previous_url ~= url then
        if not os.remove(partial) then
            return nil, "non podo descartar parcial de outra origem: " .. partial
        end
    end
    if previous_url ~= url then os.remove(provenance) end

    meta = io.open(provenance, "wb")
    if not meta then return nil, "non podo gravar proveniência: " .. provenance end
    local wrote, write_err = meta:write(url, "\n")
    local closed, close_err = meta:close()
    if not wrote or not closed then
        os.remove(provenance)
        return nil, "falha ao gravar proveniência: " .. tostring(write_err or close_err)
    end

    local cmd = string.format(
        "curl -sS -f -m %d -L --retry 2 --retry-delay 2 -C - -A 'Mozilla/5.0 (galois)' -o %s %s 2>&1",
        timeout, shell_quote(partial), shell_quote(url))
    local f = io.popen(cmd, "r")
    if not f then return nil, "non podo executar curl save" end
    local output = f:read("*a") or ""
    local closed, _, exit_code = f:close()
    if not closed then
        return nil, "curl falhou (status " .. tostring(exit_code) .. "): " .. output
    end

    local h = io.open(partial, "rb")
    if not h then return nil, "arquivo parcial non gravado: " .. partial end
    local size = h:seek("end")
    h:close()
    if not size or size == 0 then return nil, "descarga baleira: " .. url end

    if not os.rename(partial, path) then
        return nil, "non podo finalizar descarga: " .. path
    end
    os.remove(provenance)
    return true
end

return C