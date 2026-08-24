-- json.lua
-- Mini parser JSON (Lua puro, sen deps). Suficiente para obxetos/arrays, números
-- e strings; non manexa null/unicode escapes avanzados (=> nil).

local M = {}

local function ws(s, i)
    local c = string.sub(s, i, i)
    while c == ' ' or c == '\n' or c == '\r' or c == '\t' do
        i = i + 1
        c = string.sub(s, i, i)
    end
    return i
end

local function str(s, i)
    local acc, j = {}, i + 1
    while j <= #s do
        local ch = string.sub(s, j, j)
        if ch == '"' then
            return table.concat(acc), j + 1
        elseif ch == '\\' then
            local esc = string.sub(s, j + 1, j + 1)
            local map = { ['n'] = '\n', ['t'] = '\t', ['r'] = '\r',
                          ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
            acc[#acc + 1] = map[esc] or esc
            j = j + 2
        else
            acc[#acc + 1] = ch
            j = j + 1
        end
    end
    return table.concat(acc), i
end

local function num(s, i)
    local j = i
    while string.match(string.sub(s, j, j), '[0-9%.eE%+%-]') do j = j + 1 end
    return tonumber(string.sub(s, i, j - 1)), j
end

local function val(s, i)
    i = ws(s, i)
    local c = string.sub(s, i, i)
    if c == '"' then
        return str(s, i)
    elseif c == '{' then
        local obj, j = {}, ws(s, i + 1)
        if string.sub(s, j, j) == '}' then return obj, j + 1 end
        while true do
            local key, nk = str(s, j)
            j = ws(s, nk)
            j = j + 1 -- ':'
            local v, nv = val(s, j)
            j = nv
            obj[key] = v
            j = ws(s, j)
            local sep = string.sub(s, j, j)
            if sep == ',' then
                j = ws(s, j + 1)
            elseif sep == '}' then
                return obj, j + 1
            end
        end
    elseif c == '[' then
        local arr, j = {}, ws(s, i + 1)
        if string.sub(s, j, j) == ']' then return arr, j + 1 end
        while true do
            local v, nv = val(s, j)
            j = nv
            arr[#arr + 1] = v
            j = ws(s, j)
            local sep = string.sub(s, j, j)
            if sep == ',' then
                j = ws(s, j + 1)
            elseif sep == ']' then
                return arr, j + 1
            end
        end
    else
        return num(s, i)
    end
end

-- parse(s) -> table | nil
function M.parse(s)
    if not s or s == "" then return nil end
    local v = val(s, 1)
    return v
end

return M