-- kual/app.lua
-- UI dinâmica do GaloisLibrary inteiramente dentro do KUAL.
-- Não depende de widgets nem do plugin KOReader.

local M = {}
local App = {}
App.__index = App

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function ensure_dir(path)
    return command_ok("mkdir -p " .. shell_quote(path) .. " 2>/dev/null")
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local value = f:read("*a")
    f:close()
    return value
end

local function write_file(path, value)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return nil, "não consegui escrever " .. path end
    local wrote, write_err = f:write(value or "")
    if not wrote then
        f:close()
        os.remove(tmp)
        return nil, "falha ao escrever " .. path .. ": " .. tostring(write_err)
    end
    local closed, close_err = f:close()
    if not closed then
        os.remove(tmp)
        return nil, "falha ao fechar " .. path .. ": " .. tostring(close_err)
    end
    if not os.rename(tmp, path) then
        os.remove(tmp)
        return nil, "não consegui substituir " .. path
    end
    return true
end

local function pct_encode(value)
    return tostring(value or ""):gsub("([^%w%._ %-])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end)
end

local function pct_decode(value)
    return tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local BOOK_FIELDS = { "source", "md5", "title", "author", "format", "description" }

local function serialize_books(books)
    local lines = {}
    for _, book in ipairs(books or {}) do
        local fields = {}
        for _, key in ipairs(BOOK_FIELDS) do
            fields[#fields + 1] = pct_encode(book[key])
        end
        lines[#lines + 1] = table.concat(fields, "\t")
    end
    return (#lines > 0 and table.concat(lines, "\n") .. "\n" or "")
end

local function deserialize_books(raw)
    local books = {}
    for line in tostring(raw or ""):gmatch("[^\n]+") do
        local values = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do
            values[#values + 1] = pct_decode(field)
        end
        if values[3] and values[3] ~= "" then
            local book = {}
            for i, key in ipairs(BOOK_FIELDS) do book[key] = values[i] or "" end
            books[#books + 1] = book
        end
    end
    return books
end

local function sanitize_utf8(value)
    local out, i, length = {}, 1, #value
    local function continuation(pos)
        local b = value:byte(pos)
        return b and b >= 0x80 and b <= 0xBF
    end
    while i <= length do
        local b1, size = value:byte(i), 0
        if b1 <= 0x7F then
            size = 1
        elseif b1 >= 0xC2 and b1 <= 0xDF and continuation(i + 1) then
            size = 2
        elseif b1 == 0xE0 then
            local b2 = value:byte(i + 1)
            if b2 and b2 >= 0xA0 and b2 <= 0xBF and continuation(i + 2) then size = 3 end
        elseif (b1 >= 0xE1 and b1 <= 0xEC) or (b1 >= 0xEE and b1 <= 0xEF) then
            if continuation(i + 1) and continuation(i + 2) then size = 3 end
        elseif b1 == 0xED then
            local b2 = value:byte(i + 1)
            if b2 and b2 >= 0x80 and b2 <= 0x9F and continuation(i + 2) then size = 3 end
        elseif b1 == 0xF0 then
            local b2 = value:byte(i + 1)
            if b2 and b2 >= 0x90 and b2 <= 0xBF and continuation(i + 2) and continuation(i + 3) then size = 4 end
        elseif b1 >= 0xF1 and b1 <= 0xF3 then
            if continuation(i + 1) and continuation(i + 2) and continuation(i + 3) then size = 4 end
        elseif b1 == 0xF4 then
            local b2 = value:byte(i + 1)
            if b2 and b2 >= 0x80 and b2 <= 0x8F and continuation(i + 2) and continuation(i + 3) then size = 4 end
        end
        if size > 0 then
            out[#out + 1] = value:sub(i, i + size - 1)
            i = i + size
        else
            out[#out + 1] = "\239\191\189"
            i = i + 1
        end
    end
    return table.concat(out)
end

local function json_string(value)
    value = sanitize_utf8(tostring(value or ""))
    value = value:gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
        :gsub("[%z\1-\31]", function(ch)
            return string.format("\\u%04X", string.byte(ch))
        end)
    return '"' .. value .. '"'
end

local function is_array(value)
    if type(value) ~= "table" then return false end
    local max, count = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        if key > max then max = key end
        count = count + 1
    end
    return max == count
end

local function json_encode(value)
    local kind = type(value)
    if kind == "string" then return json_string(value) end
    if kind == "number" then return tostring(value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "nil" then return "null" end
    if kind ~= "table" then return json_string(tostring(value)) end

    local out = {}
    if is_array(value) then
        for i = 1, #value do out[#out + 1] = json_encode(value[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        out[#out + 1] = json_string(key) .. ":" .. json_encode(value[key])
    end
    return "{" .. table.concat(out, ",") .. "}"
end

local function action(name, command, priority)
    return {
        name = name,
        action = command,
        priority = priority or 0,
        exitmenu = false,
        refresh = command ~= ":",
        status = false,
    }
end

local function submenu(name, items, priority)
    return { name = name, items = items, priority = priority or 0 }
end

local function truncate(value, max)
    value = tostring(value or "")
    if #value <= max then return value end
    local limit = math.max(0, max - 3)
    while limit > 0 do
        local next_byte = value:byte(limit + 1)
        if next_byte and next_byte >= 0x80 and next_byte <= 0xBF then
            limit = limit - 1
        else
            break
        end
    end
    return value:sub(1, limit) .. "..."
end

local function safe_filename(value)
    value = tostring(value or "ebook")
    value = value:gsub("[%z\1-\31/\\:*?\"<>|]", "-")
    value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then value = "ebook" end
    return truncate(value, 100)
end

function M.new(opts)
    opts = opts or {}
    assert(opts.state_dir, "state_dir obrigatório")
    assert(opts.menu_path, "menu_path obrigatório")
    local self = setmetatable({
        state_dir = opts.state_dir,
        menu_path = opts.menu_path,
        documents_dir = opts.documents_dir or "/mnt/us/documents",
        settings = assert(opts.settings, "settings obrigatório"),
        registry = assert(opts.registry, "registry obrigatório"),
        catalog = assert(opts.catalog, "catalog obrigatório"),
        health = opts.health,
        net = assert(opts.net, "net obrigatório"),
    }, App)
    ensure_dir(self.state_dir)
    ensure_dir(self.documents_dir)
    return self
end

function App:load_state()
    local query = read_file(self.state_dir .. "/query.txt") or ""
    local status = read_file(self.state_dir .. "/status.txt") or "Pronto"
    query = query:gsub("[\r\n]+", "")
    status = status:gsub("[\r\n]+", " ")
    return {
        query = query,
        status = status,
        results = deserialize_books(read_file(self.state_dir .. "/results.tsv")),
    }
end

function App:save_state(state)
    ensure_dir(self.state_dir)
    local ok, err = write_file(self.state_dir .. "/query.txt", state.query or "")
    if not ok then return nil, err end
    ok, err = write_file(self.state_dir .. "/status.txt", state.status or "")
    if not ok then return nil, err end
    return write_file(self.state_dir .. "/results.tsv", serialize_books(state.results))
end

local function keyboard_group(label, chars, priority)
    local items = {}
    for i = 1, #chars do
        local key = chars:sub(i, i)
        items[#items + 1] = action(key, "./run.sh key " .. key, i)
    end
    return submenu(label, items, priority)
end

function App:menu_table(state)
    local query_label = state.query ~= "" and state.query or "(vazia)"
    local app_items = {
        action("Status: " .. truncate(state.status, 70), ":", 1),
        action("Consulta: " .. truncate(query_label, 60), ":", 2),
        keyboard_group("Teclado A-I", "ABCDEFGHI", 10),
        keyboard_group("Teclado J-R", "JKLMNOPQR", 11),
        keyboard_group("Teclado S-Z", "STUVWXYZ", 12),
        keyboard_group("Números", "0123456789", 13),
        action("Espaço", "./run.sh space", 20),
        action("Apagar", "./run.sh backspace", 21),
        action("Limpar", "./run.sh clear", 22),
        action("Pesquisar", "./run.sh search", 30),
        action("Atualizar tela", "./run.sh refresh", 31),
    }

    if #state.results > 0 then
        local result_items = {}
        for i, book in ipairs(state.results) do
            local details = {
                action("Autor: " .. truncate(book.author ~= "" and book.author or "desconhecido", 65), ":", 1),
                action("Formato: " .. (book.format ~= "" and book.format or "desconhecido"), ":", 2),
                action("Baixar para documents", "./run.sh download " .. i, 10),
            }
            result_items[#result_items + 1] = submenu(
                tostring(i) .. ". " .. truncate(book.title, 58), details, i)
        end
        app_items[#app_items + 1] = submenu("Resultados (" .. #state.results .. ")", result_items, 40)
    end

    local source_items = {}
    for i, source in ipairs(self.registry.list()) do
        local name = source.META.name
        local enabled = self.settings:enabled(name)
        source_items[#source_items + 1] = action(
            (enabled and "[ON] " or "[OFF] ") .. source.META.label,
            "./run.sh toggle " .. name, i)
    end
    source_items[#source_items + 1] = action("Testar saúde das fontes", "./run.sh health", 20)
    app_items[#app_items + 1] = submenu("Fontes e diagnóstico", source_items, 50)
    app_items[#app_items + 1] = action("Atualizar GaloisLibrary", "./update.sh", 90)

    return { items = { submenu("GaloisLibrary", app_items, -100) } }
end

function App:render(state)
    state = state or self:load_state()
    return write_file(self.menu_path, json_encode(self:menu_table(state)) .. "\n")
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function App:dispatch(command, arg)
    local state = self:load_state()

    if command == "init" or command == "refresh" then
        return self:render(state)
    elseif command == "key" then
        local key = tostring(arg or ""):sub(1, 1):upper()
        if key:match("^[A-Z0-9]$") and #state.query < 60 then
            state.query = state.query .. key
            state.status = "Consulta atualizada"
        end
    elseif command == "space" then
        if #state.query < 60 and state.query ~= "" and state.query:sub(-1) ~= " " then
            state.query = state.query .. " "
        end
        state.status = "Consulta atualizada"
    elseif command == "backspace" then
        state.query = state.query:sub(1, math.max(0, #state.query - 1))
        state.status = "Consulta atualizada"
    elseif command == "clear" then
        state.query, state.results = "", {}
        state.status = "Consulta limpa"
    elseif command == "search" then
        state.query = trim(state.query)
        if state.query == "" then
            state.status = "Digite uma consulta antes de pesquisar"
        else
            state.status = "Pesquisando: " .. state.query
            state.results = {}
            self:save_state(state)
            self:render(state)
            local ok, result, err = pcall(self.catalog.search,
                self.net, self.registry, state.query, 1, self.settings)
            if ok and result and result.results then
                state.results = result.results
                state.status = #state.results .. " resultado(s) para " .. state.query
            else
                state.status = "Falha na pesquisa: " .. tostring(ok and err or result)
            end
        end
    elseif command == "toggle" then
        local found = false
        for _, source in ipairs(self.registry.list()) do
            if source.META.name == tostring(arg) then found = true break end
        end
        if not found then
            state.status = "Fonte desconhecida: " .. tostring(arg)
        else
            local enabled = not self.settings:enabled(arg)
            local called, saved, save_err = pcall(self.settings.set, self.settings, arg, enabled)
            if not called then
                state.status = "Falha ao salvar fonte: " .. tostring(saved)
            elseif not saved then
                state.status = "Falha ao salvar fonte: " .. tostring(save_err)
            else
                state.status = tostring(arg) .. (enabled and " ativada" or " desativada")
            end
        end
    elseif command == "health" then
        if not self.health or type(self.health.run) ~= "function" then
            state.status = "Health check indisponível"
        else
            state.status = "Testando saúde das fontes..."
            self:save_state(state)
            self:render(state)
            local ok, report = pcall(self.health.run,
                self.net, self.registry, self.settings, { only_enabled = false })
            if not ok or not report then
                state.status = "Falha no health check: " .. tostring(report)
            else
                local parts = { tostring(report.healthy or 0) .. " OK", tostring(report.unhealthy or 0) .. " com problema" }
                for _, item in ipairs(report.report or {}) do
                    if not item.ok and not item.skipped then
                        parts[#parts + 1] = tostring(item.label or item.name) .. ": " .. tostring(item.error or "falha")
                    end
                end
                state.status = "Saúde: " .. table.concat(parts, " · ")
            end
        end
    elseif command == "download" then
        local index = tonumber(arg)
        local book = index and state.results[index]
        if not book then
            state.status = "Resultado inválido"
        else
            state.status = "Baixando: " .. book.title
            self:save_state(state)
            self:render(state)
            local resolved, url, err = pcall(self.catalog.resolve,
                self.net, self.registry, book, self.settings)
            if not resolved then
                state.status = "Falha ao resolver: " .. tostring(url)
            elseif not url then
                state.status = "Falha ao resolver: " .. tostring(err)
            else
                local extension = book.format ~= "" and book.format:lower() or "epub"
                extension = extension:match("^[a-z0-9]+$") and extension or "epub"
                local filename = safe_filename(book.title .. " - " .. (book.author ~= "" and book.author or "autor desconhecido"))
                    .. "." .. extension
                local path = self.documents_dir .. "/" .. filename
                local downloaded, saved, save_err = pcall(self.net.save, url, path, 180)
                if not downloaded then
                    state.status = "Falha no download: " .. tostring(saved)
                elseif saved then
                    state.status = "Baixado: " .. filename
                else
                    state.status = "Falha no download: " .. tostring(save_err)
                end
            end
        end
    else
        state.status = "Comando desconhecido: " .. tostring(command)
    end

    local ok, err = self:save_state(state)
    if not ok then return nil, err end
    return self:render(state)
end

M.json_encode = json_encode
M.safe_filename = safe_filename
M.write_file = write_file
return M
