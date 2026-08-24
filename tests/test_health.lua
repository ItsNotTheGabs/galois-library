-- tests/test_health.lua
-- Tests do orquestrador de saúde (health.lua) e dos probes de cada fonte.

local T = require("run")
local health = require("health")

local function mock_net(routes)
    return { get = function(u, t)
        local b = routes[u]
        if b == nil then return nil, "404 stub: " .. tostring(u) end
        return b
    end }
end

-- registo mínimo de fontes (falsas, só META+health para isolar o orquestrador)
local registry = require("sources.init")
local function fake_source(name, health_ret)
    return {
        META = { name = name, label = name, enabled = true },
        search = function() return { results = {} } end,
        resolve_download = function() return nil end,
        health = function() return health_ret end,
    }
end

-- helper: acha a entrada dunha fonte polo nome no relatório
local function report_of(res, name)
    for _, r in ipairs(res.report) do
        if r.name == name then return r end
    end
    return nil
end

-- ---- 1. orquestrador: todas saudáveis ----
registry.register_all({
    alpha = fake_source("alpha", { ok = true }),
    beta  = fake_source("beta",  { ok = true }),
})
local res = health.run(mock_net({}), registry, nil, {})
T.eq("health: alpha saudável", report_of(res, "alpha") and report_of(res, "alpha").ok, true)
T.eq("health: beta saudável", report_of(res, "beta") and report_of(res, "beta").ok, true)

-- ---- 2. una caída ----
registry.register_all({
    bom = fake_source("bom", { ok = true }),
    mau = fake_source("mau", { ok = false, error = "DNS fail" }),
})
local res2 = health.run(mock_net({}), registry, nil, {})
T.eq("health: bom saudável", (report_of(res2, "bom") or {}).ok, true)
T.eq("health: mau caída", (report_of(res2, "mau") or {}).ok, false)
T.eq("health: motivo propagado", (report_of(res2, "mau") or {}).error, "DNS fail")

-- ---- 3. fonte que lança exceção no probe ----
registry.register_all({
    boom = { META = { name = "boom", label = "boom" },
             search = function() end, resolve_download = function() end,
             health = function() error("boom!") end },
})
local res3 = health.run(mock_net({}), registry, nil, {})
T.eq("health: exceção -> caída", (report_of(res3, "boom") or {}).ok, false)

-- ---- 4. probes reais das fontes ----
local anna = require("anna")
-- saudável: mirror responde com get.php
local MIRROR_OK = '<a href="get.php?md5=0000&key=x">download</a>'
local net_ok = mock_net({
    ["https://annas-archive.gl/search?q=galois+health&page=1&content=book"] =
        '<div class="flex pt-3 pb-3 border-b border-gray-200">' ..
        '<a href="/md5/' .. string.rep('c', 32) .. '">x</a></div>',
    ["https://libgen.li/ads.php?md5=" .. string.rep("0", 32)] = MIRROR_OK,
    ["https://libgen.is/ads.php?md5=" .. string.rep("0", 32)] = MIRROR_OK,
    ["https://libgen.so/ads.php?md5=" .. string.rep("0", 32)] = MIRROR_OK,
})
local hok = anna.health(net_ok, {})
T.eq("anna.health: ok (busca+mirror)", hok.ok, true)

-- busca com challenge (DDoS) mas mirror OK -> fonte SAUDÁVEL para download (nota)
local net_ch = mock_net({
    ["https://annas-archive.gl/search?q=galois+health&page=1&content=book"] =
        '<script src="/js/fingerprint/iife.min.js"></script>',
    ["https://libgen.li/ads.php?md5=" .. string.rep("0", 32)] = MIRROR_OK,
    ["https://libgen.is/ads.php?md5=" .. string.rep("0", 32)] = MIRROR_OK,
    ["https://libgen.so/ads.php?md5=" .. string.rep("0", 32)] = MIRROR_OK,
})
local hch = anna.health(net_ch, {})
T.eq("anna.health: mirror ok, busca bloqueada -> ok", hch.ok, true)
T.ok("anna.health: nota fala do bloqueio", string.find(hch.note or "", "DDoS", 1, true) ~= nil)

-- mirror inacessível -> caído (mesmo que a busca pareça ok)
local net_nil = mock_net({
    ["https://annas-archive.gl/search?q=galois+health&page=1&content=book"] =
        '<div class="flex pt-3 pb-3 border-b border-gray-200">' ..
        '<a href="/md5/' .. string.rep('c', 32) .. '">x</a></div>',
    -- sem rotas de espelho
})
local hn = anna.health(net_nil, {})
T.eq("anna.health: espelho morto -> caído", hn.ok, false)

-- zlib saudável
local zlib = require("zlib")
local nz = mock_net({ ["https://z-lib.io/eapi/search?query=galois+health&page=1"] =
    '{"books":[],"total":0}' })
T.eq("zlib.health: ok (0 resultados)", zlib.health(nz, {}).ok, true)
-- zlib caído (JSON inválido)
local nzb = mock_net({ ["https://z-lib.io/eapi/search?query=galois+health&page=1"] =
    '<html>login</html>' })
T.eq("zlib.health: non-JSON -> caído", zlib.health(nzb, {}).ok, false)

-- ---- 5. format amigable ----
local fmt = health.format({ report = {
    { name = "anna", label = "Anna's Archive", ok = true, took_ms = 120 },
    { name = "zlib", label = "Z-Library", ok = false, error = "DNS fail" },
}, healthy = 1, unhealthy = 1 })
T.ok("format: inclúe nomes", string.find(fmt, "anna", 1, true) ~= nil)
T.ok("format: inclúe estado caído", string.find(fmt, "!!", 1, true) ~= nil)

T.done()