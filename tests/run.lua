-- tests/run.lua
-- Micro test-runner (Lua 5.4 puro). Uso:
--   lua tests/run.lua
----------------------------------------------------------------------------

local os = require("os")
package.path = "./?.lua;./sources/?.lua;" .. package.path

local passed, failed = 0, 0

local T = {}

function T.eq(name, got, want)
    if tostring(got) == tostring(want) then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL %s\n     got:  %s\n     want: %s"):format(name, tostring(got), tostring(want)))
    end
end

function T.ok(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name) end
end

T.done = function()
    local failed_here, passed_here = failed, passed
    if _G.__GALOIS_SUITE__ then
        _G.__GALOIS_PASSED__ = (_G.__GALOIS_PASSED__ or 0) + passed_here
        _G.__GALOIS_FAILED__ = (_G.__GALOIS_FAILED__ or 0) + failed_here
    end
    print(("==== %d passed, %d failed ===="):format(passed_here, failed_here))
    if not _G.__GALOIS_SUITE__ then
        os.exit(failed_here == 0 and 0 or 1)
    end
    -- dentro da suite: non cortamos, permitimos continuar cos demais
    passed, failed = 0, 0
end

return T