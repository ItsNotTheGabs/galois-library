-- tests/run_all.lua
-- Executa a suite completa (run_tests + test_update) e reporta totais.
-- Uso: lua tests/run_all.lua

package.path = "./?.lua;./sources/?.lua;./tests/?.lua;" .. package.path
_G.__GALOIS_SUITE__ = true

dofile("./tests/run_tests.lua")
dofile("./tests/test_update.lua")
dofile("./tests/test_health.lua")
dofile("./tests/test_uimain.lua")

print(("======================================"))
print(("TOTAL: %d passed, %d failed")
    :format(_G.__GALOIS_PASSED__ or 0, _G.__GALOIS_FAILED__ or 0))
os.exit((_G.__GALOIS_FAILED__ or 0) == 0 and 0 or 1)