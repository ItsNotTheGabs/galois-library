-- update.lua
-- Auto-update de GaloisLibrary.
--
-- check(net, current_version, repo) -> (nil) | { latest, has_update, url }
--   - consulta o release "latest" de GitHub (repo "owner/name")
--   - compara semver; devolve info se hai nova
-- apply_zip(net, asset_url, dest_dir) -> ok, err
--   - baixa o zip da release e descomprime en dest_dir
--   - (o chamador decide onde: /mnt/us/extensions/... ou equivalentes)
--
-- As funcións son puras (reciben `net` injectado) => testeable en desktop.
-- Tamén funcionan para calquera "URL de release" (non só github) con Manifest.

local U = {}

-- executa un comando e devolve true se o exit code foi 0 (Lua 5.4 devolve
-- 'true' en éxito, Lua 5.1-5.3 devolve 0)
local function exec_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

-- semver comparador simple (0.1.0)
function U.parse_version(v)
    local a, b, c = string.match(tostring(v), '^v?([%d]+)%.([%d]+)%.([%d]+)')
    if not a then return 0, 0, 0 end
    return tonumber(a), tonumber(b), tonumber(c)
end

function U.semver_lt(x, y)
    local x1, x2, x3 = U.parse_version(x)
    local y1, y2, y3 = U.parse_version(y)
    if x1 ~= y1 then return x1 < y1 end
    if x2 ~= y2 then return x2 < y2 end
    return x3 < y3
end

-- extrae o tag de versión dunha release: "v0.2.0" -> "0.2.0"
local function tag_to_version(tag)
    return (tostring(tag or ""):gsub("^v", ""))
end

-- check(net, current_version, repo_url_or_owner) -> info | nil, err
-- `repo_url_or_owner` pode ser "owner/repo" (GitHub API) ou unha URL completa
-- que responda { "tag_name": "vX.Y.Z" }.
function U.check(net, current_version, repo)
    local url
    if string.find(repo, "://") then
        url = repo
    else
        url = "https://api.github.com/repos/" .. repo .. "/releases/latest"
    end
    local body, err = net.get(url, 15)
    if not body then return nil, "update: " .. tostring(err) end

    -- parse JSON mínimo (reutiliza json.lua compartido)
    local j = require("json")
    local data = j.parse(body)
    if not data or not data.tag_name then return nil, "update: resposta sen tag_name" end

    local latest = tag_to_version(data.tag_name)
    local out = { latest = latest, has_update = U.semver_lt(current_version, latest) }
    -- queremos unha URL de descarga (asset, zipball ou tarball)
    if data.assets and data.assets[1] then
        out.url = data.assets[1].browser_download_url
    elseif data.tarball_url then
        out.url = data.tarball_url
    elseif data.zipball_url then
        out.url = data.zipball_url
    end
    return out
end

-- apply_zip(net, url, dest) -> ok, err
-- Baixa o ficheiro (zip) e descomprime en dest. Shells-out a `unzip` (presente
-- no Kindle; tamén en desktop), fallback a `tar -xf` se unzip non existe.
function U.apply_zip(net, url, dest)
    local tmp = "/tmp/galois_update_" .. os.time() .. ".zip"
    local ok_save = net.save(url, tmp, 30)
    if not ok_save then return nil, "update: descarga fallou (" .. tostring(ok_save) .. ")" end

    local f = io.open(tmp, "rb")
    if not f then return nil, "update: non puiden abrir descarga" end
    local size = f:seek("end"); f:close()
    if size == 0 then os.remove(tmp); return nil, "update: zip baleiro" end

    -- descomprimir: proba zip (unzip), senón tar.gz (tar -xzf)
    os.execute("mkdir -p '" .. dest .. "'")
    local code = exec_ok("unzip -o -q '" .. tmp .. "' -d '" .. dest .. "' 2>/dev/null")
    if not code then
        code = exec_ok("tar -xzf '" .. tmp .. "' -C '" .. dest .. "' 2>/dev/null")
    end
    if not code then
        os.remove(tmp)
        return nil, "update: fallo ao descomprimir"
    end
    os.remove(tmp)
    return true
end

-- self_update(net, repo, prefix, current_version) -> true | nil, err
-- Núcleo do auto-update:
--   1. consulta a release (GIThub URL ou URL directa)
--   2. se hai nova versión, baixa o tarball e extrae sobre o prefijo
--   3. conserva `config/` (settings do usuario) — o tarball de release non a contén
--   4. escribe o novo `version`
function U.self_update(net, repo, prefix, current_version)
    local info, err = U.check(net, current_version, repo)
    if not info then return nil, err or "update: sen info" end
    if not info.has_update then return nil, "ja está atualizado (" .. current_version .. ")" end
    if not info.url then return nil, "release sen URL de descarga" end

    -- extrae a un dir temporal dentro do prefijo
    local tmp = prefix .. "/.galois_update_tmp"
    os.execute("rm -rf '" .. tmp .. "'")
    local ok, aerr = U.apply_zip(net, info.url, tmp)
    if not ok then return nil, aerr or "fallo apply" end

    -- tarball do GitHub ten un top-level dir (repo-tag-hash/); normaliza
    local f = io.popen("ls -1 '" .. tmp .. "' 2>/dev/null")
    local names = f and f:read("*a") or ""
    if f then f:close() end
    local count, single = 0, nil
    for name in string.gmatch(names, "[^\n]+") do count = count + 1; single = name end
    if count == 1 and single then
        -- confirma que é um DIRECTÓRIO (io.open em dir retorna non-nil no Linux)
        local p = io.popen("test -d '" .. tmp .. "/" .. single .. "' && echo yes")
        local isdir = p and p:read("*l") == "yes"
        if p then p:close() end
        if isdir then
            tmp = tmp .. "/" .. single   -- top-level dir → usa-o como raíz
        end
    end

    -- copiar sobre as fontes, preservando config/
    os.execute("mkdir -p '" .. prefix .. "'")
    local f2 = io.popen("ls -1 '" .. tmp .. "' 2>/dev/null")
    local names2 = f2 and f2:read("*a") or ""
    if f2 then f2:close() end
    for name in string.gmatch(names2, "[^\n]+") do
        if name ~= "config" then
            os.execute("cp -r '" .. tmp .. "/" .. name .. "' '" .. prefix .. "/' ")
        end
    end
    os.execute("rm -rf '" .. prefix .. "/.galois_update_tmp'")

    -- escribe versión nova
    local vf = io.open(prefix .. "/version", "wb")
    if vf then vf:write(info.latest .. "\n"); vf:close() end
    return true
end

return U