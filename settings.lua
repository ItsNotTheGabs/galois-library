-- settings.lua
-- Estado activo/inactivo de cada fonte. PoC: arquivo texto simple key=value
-- inyectabel para tests (path e defaults recibense en new()).

local S = {}

-- Constants: valores de estado
S.ENABLED = "1"
S.DISABLED = "0"

-- new(opts) -> settings
--   opts.path      — donde garda o arquivo (nil => para non persistir)
--   opts.defaults  — tabela { name = bool, ... }
--   opts.fs        — módulo de arquivo inyectado (para tests): { read(path), write(path, data) }
function S.new(opts)
    opts = opts or {}
    local self = {
        path = opts.path,
        fs = opts.fs,
        state = {},   -- name -> "1"/"0"
        defaults = opts.defaults or {},
        _loaded = false,
    }
    setmetatable(self, { __index = S })
    -- cargar desde disco a primeira vez
    if self.path and self.fs then
        local data = self.fs.read(self.path)
        if data then
            for line in string.gmatch(data, "[^\n]+") do
                local eq = string.find(line, "=", 1, true)
                if eq then
                    local k = string.sub(line, 1, eq - 1)
                    local v = string.sub(line, eq + 1)
                    self.state[k] = v
                end
            end
        end
        self._loaded = true
    end
    return self
end

local function is_truthy(v)
    return v == true or v == S.ENABLED or v == "true" or v == 1
end

-- enabled(name) -> bool (usando default se nunca foi setiado)
function S:enabled(name)
    if self.state[name] ~= nil then
        return self.state[name] == S.ENABLED
    end
    return is_truthy(self.defaults[name])
end

function S:set(name, bool)
    self.state[name] = bool and S.ENABLED or S.DISABLED
    self:_persist()
end

-- set_raw: valor libre (non booleano) — p.ex. download_dir=/mnt/us/documents
function S:set_raw(k, v)
    self.state[k] = tostring(v)
    self:_persist()
end

-- get: valor cru (para configs non booleanas)
function S:get(k, default)
    local v = self.state[k]
    if v == nil then return default end
    return v
end

-- persist interna (extrae a escritura anterior)
function S:_persist()
    if self.path and self.fs then
        local lines = {}
        for k, v in pairs(self.state) do
            lines[#lines + 1] = k .. "=" .. v
        end
        table.sort(lines)
        self.fs.write(self.path, table.concat(lines, "\n") .. "\n")
    end
end

-- toggle convenience
function S:toggle(name, value_or_nil)
    local nxt = value_or_nil
    if nxt == nil then nxt = not self:enabled(name) end
    self:set(name, nxt)
    return nxt
end

return S