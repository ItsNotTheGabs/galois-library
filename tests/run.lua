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
    print(("==== %d passed, %d failed ===="):format(passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

return T