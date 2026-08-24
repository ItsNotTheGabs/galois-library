-- health.lua
-- Orquestrador de saúde das fontes.
--
-- Corre un probe mínimo (health()) en cada fonte registrada e devolve un
-- relatório: { name, label, ok, error, took_ms }.
--
-- Serve tanto para a UI (status nas configs) como para monitor:
--   lua cli.lua health         (saída amigable + exit code)
--   uso em cron/script: health.lua devolve exit 1 se algo estiver caído.

local H = {}

-- run(net, registry, settings, opts) -> { report = {...}, healthy = n, unhealthy = n }
--  opts.only_enabled  — evalua só fontes ativas (default: todas)
--  opts.timeout       — segundos para cada probe (default 15)
function H.run(net, registry, settings, opts)
    opts = opts or {}
    local report = {}
    local healthy, unhealthy = 0, 0

    for _, mod in ipairs(registry.list()) do
        local name = mod.META.name
        local skipped = settings and opts.only_enabled and not settings:enabled(name)

        if skipped then
            report[#report + 1] = {
                name = name,
                label = mod.META.label,
                ok = false,
                error = "inativa (desativada nas configs)",
                skipped = true,
            }
        else
            local t0 = os.clock()
            local ok, res = pcall(mod.health, net, opts.probe_opts or {})
            local took = math.floor((os.clock() - t0) * 1000)

            if not ok then
                unhealthy = unhealthy + 1
                report[#report + 1] = {
                    name = name, label = mod.META.label,
                    ok = false, error = "erro no probe: " .. tostring(res), took_ms = took,
                }
            elseif res and res.ok then
                healthy = healthy + 1
                report[#report + 1] = {
                    name = name, label = mod.META.label,
                    ok = true, note = res.note, took_ms = took,
                }
            else
                unhealthy = unhealthy + 1
                report[#report + 1] = {
                    name = name, label = mod.META.label,
                    ok = false, error = res and res.error or "sem motivo", took_ms = took,
                }
            end
        end
    end

    return { report = report, healthy = healthy, unhealthy = unhealthy }
end

-- format(net, registry, settings, opts) -> string amigable (para CLI/UI texto)
function H.format(res)
    local lines = {}
    for _, r in ipairs(res.report) do
        local mark = r.ok and "[OK] " or (r.skipped and "[--] " or "[!!] ")
        local extra = r.ok
            and (r.took_ms and string.format(" (%dms)%s", r.took_ms, r.error and " — " .. r.error or "") or "")
            or (r.error or r.reason or "")
        lines[#lines + 1] = string.format("%s %-6s %s%s", mark, r.name, r.label, extra)
    end
    lines[#lines + 1] = string.format("Saudáveis: %d · Com problema: %d", res.healthy, res.unhealthy)
    return table.concat(lines, "\n")
end

return H