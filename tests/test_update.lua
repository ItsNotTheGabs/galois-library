-- tests/test_update.lua
-- Tests do módulo update (check versión + auto-apply) con un mock local.

local T = require("run")
local update = require("update")

local function mock_net(routes)
    return {
        get = function(u, t)
            local b = routes[u]
            if b then return b end
            return nil, "mock 404: " .. tostring(u)
        end,
        save = function(u, path, t)
            -- gardamos un ficheiro real para que apply_zip poida extraed
            local body = routes[u]
            if body == nil then return nil, "mock save 404" end
            local f = io.open(path, "wb")
            if not f then return nil, "mock save non abre " .. path end
            f:write(body)
            f:close()
            return true
        end,
    }
end

-- ---- 1. check: versión igual e nova ----
local same = update.check(mock_net({ ["https://api.github.com/repos/o/galois/releases/latest"] =
    '{"tag_name":"v0.1.0"}' }), "0.1.0", "o/galois")
T.ok("check: mesmo versión -> has_update=false", same ~= nil and same.has_update == false)

local newer = update.check(mock_net({ ["https://api.github.com/repos/o/galois/releases/latest"] =
    '{"tag_name":"v0.2.0","assets":[{"browser_download_url":"https://x/galois.zip"}]}' }),
    "0.1.0", "o/galois")
T.ok("check: nova versión detectada", newer ~= nil)
T.eq("check: latest", newer and newer.latest or "", "0.2.0")
T.ok("check: has_update", newer and newer.has_update or false)

-- ---- 2. URL de release directa (non GitHub) ----
local viaurl = update.check(mock_net({ ["https://cdn.example.com/release.json"] =
    '{"tag_name":"v0.3.0"}' }), "0.2.0", "https://cdn.example.com/release.json")
T.ok("check: URL directa funciona", viaurl and viaurl.latest == "0.3.0")

-- ---- 3. apply_zip: falla con corpo baleiro ----
local ok, err = update.apply_zip(mock_net({ ["https://x/galois.zip"] = "" }),
    "https://x/galois.zip", "/tmp/galois_out_doesnotmatter")
T.ok("apply: falla (zip baleiro)", ok == nil and err ~= nil)

-- ---- 4. apply_zip real: tar.gz de fixture e extrae a unha carpeta ----
-- (construímos un tarball simple con version.txt)
os.execute("rm -rf /tmp/galois_pkg && mkdir -p /tmp/galois_pkg")
local wf = io.open("/tmp/galois_pkg/version.txt", "wb"); wf:write("fixture-lib-V1\n"); wf:close()
os.execute("tar -czf /tmp/galois_pkg.tar.gz -C /tmp/galois_pkg version.txt 2>/dev/null")
local tf = io.open("/tmp/galois_pkg.tar.gz", "rb")
local tarball = tf and tf:read("*a")
if tf then tf:close() end
local netr = mock_net({ ["https://x/latest.tar.gz"] = tarball })
local dest = "/tmp/galois_update_extract"
os.execute("rm -rf '" .. dest .. "'")
local okr, _ = update.apply_zip(netr, "https://x/latest.tar.gz", dest)
T.ok("apply real: descomprime", okr ~= nil)
local gh = io.open(dest .. "/version.txt", "rb")
local got = gh and gh:read("*a")
if gh then gh:close() end
T.eq("apply real: contido", got, "fixture-lib-V1\n")

-- ---- 5. semver ----
T.ok("semver 0.1.0 < 0.2.0", update.semver_lt("0.1.0", "0.2.0"))
T.ok("semver 1.0.0 > 0.9.9", (update.semver_lt("1.0.0", "0.9.9") == false))
T.ok("semver v-prefix ignorado", update.semver_lt("0.1.0", "v0.2.0"))
T.ok("semver iguais -> false", (update.semver_lt("0.2.0", "0.2.0") == false))

-- ---- 6. self_update E2E: baixa release e aplica no prefixo ----
os.execute("rm -rf /tmp/galois_prefix_v1 /tmp/galois_pkg_v2")
os.execute("mkdir -p /tmp/galois_prefix_v1 /tmp/galois_pkg_v2")
-- prefixo "instalado" na v1
local v1f = io.open("/tmp/galois_prefix_v1/version", "wb"); v1f:write("0.1.0\n"); v1f:close()
local c1 = io.open("/tmp/galois_prefix_v1/app.lua", "wb"); c1:write("-- v1\n"); c1:close()
-- config do usuario (debe preservarse)
os.execute("mkdir -p /tmp/galois_prefix_v1/config")
local cf = io.open("/tmp/galois_prefix_v1/config/sources.cfg", "wb"); cf:write("anna=1\n"); cf:close()
-- release v0.2.0 con tarball que contén app.lua novo
local w2 = io.open("/tmp/galois_pkg_v2/version", "wb"); w2:write("0.2.0\n"); w2:close()
local a2 = io.open("/tmp/galois_pkg_v2/app.lua", "wb"); a2:write("-- v2\n"); a2:close()
os.execute("tar -czf /tmp/galois_pkg_v2.tar.gz -C /tmp/galois_pkg_v2 . 2>/dev/null")
local tf2 = io.open("/tmp/galois_pkg_v2.tar.gz", "rb")
local ball2 = tf2 and tf2:read("*a")
if tf2 then tf2:close() end

local n_up = mock_net({
    ["https://api.github.com/repos/o/galois/releases/latest"] =
        '{"tag_name":"v0.2.0","tarball_url":"https://x/pkg.tar.gz"}',
    ["https://x/pkg.tar.gz"] = ball2,
})
local up_ok, up_err = update.self_update(n_up, "o/galois", "/tmp/galois_prefix_v1", "0.1.0")
T.ok("self_update: aplica", up_ok ~= nil, up_err or "")
local ver_after = io.open("/tmp/galois_prefix_v1/version", "rb") and io.open("/tmp/galois_prefix_v1/version", "rb"):read("*a") or ""
T.eq("self_update: version bumped", ver_after, "0.2.0\n")
local app_after = io.open("/tmp/galois_prefix_v1/app.lua", "rb") and io.open("/tmp/galois_prefix_v1/app.lua", "rb"):read("*a") or ""
T.eq("self_update: arquivo substituído", app_after, "-- v2\n")
local cfg_after = io.open("/tmp/galois_prefix_v1/config/sources.cfg", "rb") and io.open("/tmp/galois_prefix_v1/config/sources.cfg", "rb"):read("*a") or ""
T.eq("self_update: config preservado", cfg_after, "anna=1\n")

-- já atualizado -> nil
local up2, up2err = update.self_update(n_up, "o/galois", "/tmp/galois_prefix_v1", "0.2.0")
T.ok("self_update: já atual -> nil", up2 == nil and up2err ~= nil)

-- ---- 7. self_update com tarball de top-level dir (como o do GitHub) ----
os.execute("rm -rf /tmp/galois_prefix_g /tmp/galois_pkg_gh")
os.execute("mkdir -p /tmp/galois_prefix_g /tmp/galois_pkg_gh/repo-tag-hash")
local wg = io.open("/tmp/galois_pkg_gh/repo-tag-hash/version", "wb"); wg:write("0.3.0\n"); wg:close()
local ag = io.open("/tmp/galois_pkg_gh/repo-tag-hash/app.lua", "wb"); ag:write("-- v3\n"); ag:close()
os.execute("tar -czf /tmp/galois_pkg_gh.tar.gz -C /tmp/galois_pkg_gh . 2>/dev/null")
local tg = io.open("/tmp/galois_pkg_gh.tar.gz", "rb")
local ball_g = tg and tg:read("*a")
if tg then tg:close() end
local n_g = mock_net({
    ["https://api.github.com/repos/o/galois/releases/latest"] =
        '{"tag_name":"v0.3.0","tarball_url":"https://x/pkg3.tar.gz"}',
    ["https://x/pkg3.tar.gz"] = ball_g,
})
local ok_g, err_g = update.self_update(n_g, "o/galois", "/tmp/galois_prefix_g", "0.2.0")
T.ok("self_update: github-style tarball aplica", ok_g ~= nil, tostring(err_g))
local app3 = io.open("/tmp/galois_prefix_g/app.lua", "rb") and io.open("/tmp/galois_prefix_g/app.lua", "rb"):read("*a") or ""
T.eq("self_update: github-style arquivo na raiz", app3, "-- v3\n")
local ver3 = io.open("/tmp/galois_prefix_g/version", "rb") and io.open("/tmp/galois_prefix_g/version", "rb"):read("*a") or ""
T.eq("self_update: github-style version", ver3, "0.3.0\n")

T.done()