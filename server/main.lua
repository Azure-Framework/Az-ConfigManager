local RESOURCE = GetCurrentResourceName()

local Scan = {
    resources = {},
    filesById = {},
    lastRun = 0,
    totals = { resources = 0, files = 0, fields = 0 },
}

local BackupIndex = nil
local PendingRestart = {}

local function debugPrint(...)
    if not Config.Debug then return end
    local out = {}
    for i = 1, select('#', ...) do out[#out + 1] = tostring(select(i, ...)) end
    print(('^4[%s]^7 %s'):format(RESOURCE, table.concat(out, ' ')))
end

local function trim(value)
    
    
    
    local out = tostring(value or '')
    out = out:gsub('^%s+', '')
    out = out:gsub('%s+$', '')
    return out
end

local function lower(value)
    return string.lower(tostring(value or ''))
end

local function shallowCopy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function nowStamp()
    return os.date('!%Y%m%d_%H%M%S')
end

local function nowIso()
    return os.date('!%Y-%m-%d %H:%M:%S UTC')
end

local function safeJsonDecode(raw, fallback)
    if not raw or raw == '' then return fallback end
    local ok, data = pcall(json.decode, raw)
    if ok and data ~= nil then return data end
    return fallback
end

local function safeJsonEncode(data)
    local ok, encoded = pcall(json.encode, data)
    if ok and encoded then return encoded end
    return '{}'
end

local function sanitizeFileName(value)
    value = tostring(value or '')
    value = value:gsub('[\\/:%*%?"<>|%s%[%]]+', '_')
    value = value:gsub('_+', '_')
    if #value > 140 then value = value:sub(1, 140) end
    return value
end

local function splitLines(content)
    content = tostring(content or '')
    local lines = {}
    content = content:gsub('\r\n', '\n'):gsub('\r', '\n')
    if content == '' then return { '' } end
    for line in (content .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end
    if #lines > 1 and lines[#lines] == '' then table.remove(lines, #lines) end
    return lines
end

local function joinLines(lines)
    return table.concat(lines or {}, '\n')
end

local function getExtension(path)
    local ext = tostring(path or ''):match('%.([%w_%-]+)$')
    return ext and lower(ext) or ''
end

local function isEditablePath(path)
    local ext = getExtension(path)
    if not Config.EditableExtensions[ext] then return false end
    local p = lower(path)
    if p:find('%.bak', 1, true) then return false end
    if p:find('/node_modules/', 1, true) then return false end
    if p:find('/stream/', 1, true) then return false end
    if p:find('/html/', 1, true) or p:find('/ui/', 1, true) then
        
        return p:find('config', 1, true) ~= nil or p:find('settings', 1, true) ~= nil
    end
    return true
end

local function looksLikeConfigPath(path)
    local p = lower(path):gsub('\\', '/')
    if not isEditablePath(p) then return false end
    for _, word in ipairs(Config.ConfigNameKeywords or {}) do
        if p:find(lower(word), 1, true) then return true end
    end

    if Config.AllowScriptFilesWithLocalConfig == true and getExtension(p) == 'lua' then
        local fileName = p:match('([^/]+)$') or p
        if fileName == 'client.lua' or fileName == 'server.lua' or fileName == 'main.lua' or fileName == 'shared.lua' then
            return true
        end
    end

    return false
end

local function makeFileId(resourceName, path)
    return resourceName .. '::' .. path
end

local function stripAtResourcePrefix(value)
    value = tostring(value or '')
    if value:sub(1, 1) ~= '@' then return value end
    local firstSlash = value:find('/', 2, true)
    if not firstSlash then return value end
    return value:sub(firstSlash + 1)
end

local function normalizePath(value)
    value = stripAtResourcePrefix(value)
    value = value:gsub('\\', '/')
    value = value:gsub('^%./', '')
    value = value:gsub('/+', '/')
    return value
end

local function pathHasSkippedPart(path)
    local p = lower(tostring(path or ''):gsub('\\', '/'))
    for _, part in ipairs(Config.RecursiveSkipPathParts or {}) do
        local needle = lower(tostring(part or ''))
        if needle ~= '' and p:find(needle, 1, true) then return true end
    end
    return false
end

local function isWindowsPath(path)
    path = tostring(path or '')

    
    
    if path:match('^%a:[/\\]') then return true end
    if path:find('\\', 1, true) then return true end

    local okOs, osName = pcall(function()
        return os and os.getenv and os.getenv('OS') or nil
    end)
    if okOs and type(osName) == 'string' and osName:lower():find('windows', 1, true) then
        return true
    end

    return false
end

local function shellQuote(path)
    path = tostring(path or '')
    if isWindowsPath(path) then
        return '"' .. path:gsub('"', '\\"') .. '"'
    end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function directReadText(absPath, maxBytes)
    maxBytes = tonumber(maxBytes) or 250000
    local ok, fh = pcall(io.open, absPath, 'rb')
    if not ok or not fh then return nil end
    local data = fh:read(maxBytes + 1)
    fh:close()
    if not data or #data > maxBytes then return nil end
    return tostring(data)
end

local function contentLooksLikeConfig(path, content)
    local ext = getExtension(path)
    local p = lower(tostring(path or ''))

    if ext == 'cfg' or ext == 'ini' or ext == 'callout' then return true end
    if ext == 'json' then
        if p:find('package%.json') or p:find('package%-lock%.json') or p:find('tsconfig%.json') or p:find('vite%.config') then return false end
        return true
    end
    if ext ~= 'lua' then return false end

    local s = tostring(content or '')
    
    if s:find('local%s+Config%s*=', 1, false) then return true end
    if s:find('Config%s*=%s*Config%s+or%s+{}', 1, false) then return true end
    if s:find('Config%s*=%s*{', 1, false) then return true end
    if s:find('Config%.[%w_]+%s*=', 1, false) then return true end
    if s:find('Settings%.[%w_]+%s*=', 1, false) then return true end
    if s:find('Shared%.[%w_]+%s*=', 1, false) then return true end
    if s:find('Jobs%.[%w_]+%s*=', 1, false) then return true end
    if s:find('Locations%.[%w_]+%s*=', 1, false) then return true end
    if s:find('return%s*{', 1, false) and (p:find('callout', 1, true) or p:find('config', 1, true) or p:find('settings', 1, true)) then return true end
    return false
end

local function addKnownCandidate(candidates, path)
    path = normalizePath(path)
    if path == '' then return end
    if path:find('%*') then return end
    if pathHasSkippedPart(path) then return end
    if not isEditablePath(path) then return end
    candidates[path] = true
end

local function recursiveResourceCandidates(resourceName)
    local out = {}
    if Config.EnableRecursiveFileScan ~= true then return out end

    local okPath, resourcePath = pcall(GetResourcePath, resourceName)
    if not okPath or type(resourcePath) ~= 'string' or resourcePath == '' then return out end

    local base = resourcePath:gsub('\\', '/')
    local baseLower = lower(base)
    local command
    if isWindowsPath(resourcePath) then
        command = 'dir /b /s ' .. shellQuote(resourcePath)
    else
        command = 'find ' .. shellQuote(resourcePath) .. ' -type f'
    end

    local okPopen, pipe = pcall(io.popen, command)
    if not okPopen or not pipe then return out end

    local maxFiles = tonumber(Config.MaxRecursiveFilesPerResource) or 900
    local checked = 0
    for line in pipe:lines() do
        if checked >= maxFiles then break end
        local full = tostring(line or ''):gsub('\\', '/')
        local fullLower = lower(full)
        if fullLower:sub(1, #baseLower) == baseLower then
            local rel = full:sub(#base + 1):gsub('^/+', '')
            rel = normalizePath(rel)
            if rel ~= '' and not pathHasSkippedPart(rel) and isEditablePath(rel) then
                local ext = getExtension(rel)
                local nameLooksConfig = looksLikeConfigPath(rel)
                local include = false

                if nameLooksConfig or ext == 'cfg' or ext == 'ini' or ext == 'callout' then
                    include = true
                elseif ext == 'json' then
                    include = contentLooksLikeConfig(rel, '')
                elseif ext == 'lua' then
                    local raw = directReadText(full, Config.MaxContentProbeBytes or 220000)
                    include = contentLooksLikeConfig(rel, raw or '')
                end

                if include then
                    out[#out + 1] = rel
                    checked = checked + 1
                end
            end
        end
    end
    pipe:close()

    return out
end

local function addCandidate(candidates, path)
    path = normalizePath(path)
    if path == '' then return end
    if path:find('%*') then return end
    if path:find('^@') then return end
    if not looksLikeConfigPath(path) then return end
    candidates[path] = true
end

local function getResourceCandidates(resourceName)
    local candidates = {}

    for _, path in ipairs(Config.CommonConfigFiles or {}) do
        addCandidate(candidates, path)
    end

    for _, key in ipairs(Config.ManifestMetadataKeys or {}) do
        local count = 0
        local okCount, valueCount = pcall(GetNumResourceMetadata, resourceName, key)
        if okCount then count = tonumber(valueCount) or 0 end

        for i = 0, count - 1 do
            local ok, value = pcall(GetResourceMetadata, resourceName, key, i)
            if ok and value and value ~= '' then
                addCandidate(candidates, value)
            end
        end
    end

    for _, path in ipairs(recursiveResourceCandidates(resourceName)) do
        addKnownCandidate(candidates, path)
    end

    return candidates
end

local function loadResourceText(resourceName, path)
    local ok, data = pcall(LoadResourceFile, resourceName, path)
    if not ok then return nil, tostring(data) end
    if data == nil then return nil, 'missing' end
    return tostring(data), nil
end

local function braceDelta(line)
    local delta = 0
    local inString = false
    local quote = nil
    local escape = false
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if inString then
            if escape then
                escape = false
            elseif c == '\\' then
                escape = true
            elseif c == quote then
                inString = false
                quote = nil
            end
        else
            if c == '-' and line:sub(i, i + 1) == '--' then
                break
            elseif c == '"' or c == "'" then
                inString = true
                quote = c
            elseif c == '{' then
                delta = delta + 1
            elseif c == '}' then
                delta = delta - 1
            end
        end
        i = i + 1
    end
    return delta
end

local function stripInlineComment(value)
    value = tostring(value or '')
    local inString = false
    local quote = nil
    local escape = false
    local i = 1
    while i <= #value do
        local c = value:sub(i, i)
        if inString then
            if escape then
                escape = false
            elseif c == '\\' then
                escape = true
            elseif c == quote then
                inString = false
                quote = nil
            end
        else
            if c == '"' or c == "'" then
                inString = true
                quote = c
            elseif c == '-' and value:sub(i, i + 1) == '--' then
                return trim(value:sub(1, i - 1))
            end
        end
        i = i + 1
    end
    return trim(value)
end

local function unquoteLuaString(value)
    value = trim(value)
    local q = value:sub(1, 1)
    if (q == '"' or q == "'") and value:sub(-1) == q then
        local inner = value:sub(2, -2)
        inner = inner:gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t')
        inner = inner:gsub('\\"', '"'):gsub("\\'", "'"):gsub('\\\\', '\\')
        return inner
    end
    return value
end


local function looksLikeColorKey(key)
    local k = lower(key or '')
    return k:find('color', 1, true) ~= nil
        or k:find('colour', 1, true) ~= nil
        or k:find('rgba', 1, true) ~= nil
        or k:find('hex', 1, true) ~= nil
end

local function looksLikeColorValue(value)
    value = trim(value or '')
    if value:match('^#%x%x%x$') then return true end
    if value:match('^#%x%x%x%x$') then return true end
    if value:match('^#%x%x%x%x%x%x$') then return true end
    if value:match('^#%x%x%x%x%x%x%x%x$') then return true end
    if lower(value):match('^rgba?%s*%(') then return true end
    return false
end

local function isArrayTable(t)
    if type(t) ~= 'table' then return false, 0 end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then return false, 0 end
        if k > n then n = k end
    end
    for i = 1, n do
        if t[i] == nil then return false, 0 end
    end
    return true, n
end

local function detectJsonVectorTable(value)
    if type(value) ~= 'table' then return nil end

    local function pick(t, names)
        for _, name in ipairs(names) do
            if t[name] ~= nil then return name, tonumber(t[name]) end
        end
        return nil, nil
    end

    local xKey, x = pick(value, { 'x', 'X' })
    local yKey, y = pick(value, { 'y', 'Y' })
    if xKey and yKey then
        local zKey, z = pick(value, { 'z', 'Z' })
        local wKey, w = pick(value, { 'w', 'W', 'heading', 'Heading', 'h', 'H' })
        local keys = { xKey, yKey }
        local coords = { x or 0, y or 0 }
        local count = 2
        if zKey then
            count = 3
            keys[3] = zKey
            coords[3] = z or 0
        end
        if wKey then
            count = 4
            keys[4] = wKey
            coords[4] = w or 0
        end
        return 'vector' .. tostring(count), coords, 'object', keys
    end

    local isArray, n = isArrayTable(value)
    if isArray and n >= 2 and n <= 4 then
        local coords = {}
        for i = 1, n do
            if tonumber(value[i]) == nil then return nil end
            coords[i] = tonumber(value[i]) or 0
        end
        return 'vector' .. tostring(n), coords, 'array', nil
    end

    return nil
end

local function detectLuaValue(raw)
    raw = stripInlineComment(raw)
    local lowerRaw = lower(raw)

    if lowerRaw == 'true' then return 'boolean', true end
    if lowerRaw == 'false' then return 'boolean', false end

    local numberValue = tonumber(raw)
    if numberValue ~= nil then return 'number', numberValue end

    local q = raw:sub(1, 1)
    if (q == '"' or q == "'") and raw:sub(-1) == q then
        return 'string', unquoteLuaString(raw)
    end

    local vecName, inside = raw:match('^(vector[234])%s*%((.-)%)$')
    if not vecName then vecName, inside = raw:match('^(vec[234])%s*%((.-)%)$') end
    if vecName and inside then
        local coords = {}
        for part in inside:gmatch('[^,]+') do
            local cleaned = trim(part)
            coords[#coords + 1] = tonumber(cleaned) or 0.0
        end
        local detectedType = vecName:gsub('^vec', 'vector')
        return detectedType, coords, { constructor = vecName }
    end

    if raw:sub(1, 1) == '{' then
        return 'table', raw
    end


    return 'raw', raw
end

local function stripTrailingComma(value)
    value = trim(stripInlineComment(value or ''))
    if value:sub(-1) == ',' then value = trim(value:sub(1, -2)) end
    return value
end

local function luaPatternEscape(value)
    return (tostring(value or ''):gsub('([^%w])', '%%%1'))
end

local function makeLocalFieldId(lineNumber, key)
    return tostring(lineNumber) .. ':local:' .. tostring(key or '')
end

local function pathJoin(base, key)
    base = tostring(base or '')
    key = tostring(key or '')
    if base == '' then return key end
    return base .. '.' .. key
end

local function detectRgbaTable(raw)
    raw = stripTrailingComma(raw)
    local body = raw:match('^%s*{%s*(.-)%s*}%s*$')
    if not body then return nil end
    local r = body:match('[%s,{]r%s*=%s*([%-%.%d]+)') or body:match('^r%s*=%s*([%-%.%d]+)')
    local g = body:match('[%s,{]g%s*=%s*([%-%.%d]+)') or body:match('^g%s*=%s*([%-%.%d]+)')
    local b = body:match('[%s,{]b%s*=%s*([%-%.%d]+)') or body:match('^b%s*=%s*([%-%.%d]+)')
    local a = body:match('[%s,{]a%s*=%s*([%-%.%d]+)') or body:match('^a%s*=%s*([%-%.%d]+)')
    if r and g and b then
        return {
            r = tonumber(r) or 0,
            g = tonumber(g) or 0,
            b = tonumber(b) or 0,
            a = tonumber(a) or 255,
        }
    end
    return nil
end

local function findValueEnd(text, startIndex)
    local paren, brace, bracket = 0, 0, 0
    local inString = false
    local quote = nil
    local escape = false
    local i = startIndex
    while i <= #text do
        local c = text:sub(i, i)
        if inString then
            if escape then
                escape = false
            elseif c == '\\' then
                escape = true
            elseif c == quote then
                inString = false
                quote = nil
            end
        else
            if c == '"' or c == "'" then
                inString = true
                quote = c
            elseif c == '(' then
                paren = paren + 1
            elseif c == ')' then
                paren = math.max(0, paren - 1)
            elseif c == '{' then
                brace = brace + 1
            elseif c == '}' then
                if brace == 0 and paren == 0 and bracket == 0 then return i - 1 end
                brace = math.max(0, brace - 1)
            elseif c == '[' then
                bracket = bracket + 1
            elseif c == ']' then
                bracket = math.max(0, bracket - 1)
            elseif c == ',' and paren == 0 and brace == 0 and bracket == 0 then
                return i - 1
            end
        end
        i = i + 1
    end
    return #text
end

local function addParsedLuaTableField(fields, lineNumber, fullKey, rawValue, rawLine, mode, inlineKey, valueTypeOverride, valueOverride, valueMeta)
    if #fields >= (Config.MaxParsedFieldsPerFile or 500) then return end
    local cleanValue = stripTrailingComma(rawValue or '')
    local valueType, value, meta = detectLuaValue(cleanValue)
    if valueTypeOverride then
        valueType = valueTypeOverride
        value = valueOverride
        meta = valueMeta or meta
    end
    if valueType == 'string' and (looksLikeColorKey(fullKey) or looksLikeColorValue(value)) then
        valueType = 'color'
    end
    fields[#fields + 1] = {
        id = makeLocalFieldId(lineNumber, fullKey),
        key = fullKey,
        type = valueType,
        value = value,
        raw = rawLine or cleanValue,
        startLine = lineNumber,
        endLine = lineNumber,
        editable = true,
        localTableMode = mode or 'line-key',
        inlineKey = inlineKey,
        valueConstructor = meta and meta.constructor or nil,
    }
end

local function parseInlineLuaPairs(line, basePath, lineNumber, fields)
    local body = line:match('{(.*)}')
    if not body then return end
    local pos = 1
    while pos <= #body and #fields < (Config.MaxParsedFieldsPerFile or 500) do
        local s, e, key = body:find('([%w_]+)%s*=', pos)
        if not s then break end
        local valueStart = e + 1
        local valueEnd = findValueEnd(body, valueStart)
        local rawValue = trim(body:sub(valueStart, valueEnd))
        if rawValue ~= '' then
            addParsedLuaTableField(fields, lineNumber, pathJoin(basePath, key), rawValue, line, 'inline-key', key)
        end
        pos = math.max(valueEnd + 2, e + 1)
    end
end

local function findLuaTableBlockEnd(lines, startLine)
    local delta = 0
    for i = startLine, #lines do
        delta = delta + braceDelta(lines[i])
        if delta <= 0 then return i end
    end
    return #lines
end

local function parseLocalConfigTables(content, fields)
    local lines = splitLines(content)
    fields = fields or {}
    local startLine = nil

    for i, line in ipairs(lines) do
        if line:match('^%s*local%s+Config%s*=%s*{') or line:match('^%s*Config%s*=%s*{') then
            startLine = i
            break
        end
    end
    if not startLine then return fields end

    local endLine = findLuaTableBlockEnd(lines, startLine)
    local stack = { { path = 'Config', arrayIndex = 0 } }
    local i = startLine + 1

    while i < endLine and #fields < (Config.MaxParsedFieldsPerFile or 500) do
        local line = lines[i]
        local clean = trim(stripInlineComment(line))

        if clean ~= '' then
            if clean:sub(1, 1) == '}' then
                if #stack > 1 then table.remove(stack) end
            else
                local ctx = stack[#stack]

                if clean:sub(1, 1) == '{' then
                    ctx.arrayIndex = (tonumber(ctx.arrayIndex) or 0) + 1
                    local rowPath = tostring(ctx.path) .. '[' .. tostring(ctx.arrayIndex) .. ']'
                    parseInlineLuaPairs(line, rowPath, i, fields)
                else
                    local key, rhs = clean:match('^([%w_]+)%s*=%s*(.-)%s*$')
                    if key and rhs then
                        local cleanRhs = stripTrailingComma(rhs)
                        local fullKey = pathJoin(ctx.path, key)
                        local delta = braceDelta(line)
                        local rgba = detectRgbaTable(cleanRhs)

                        if rgba then
                            addParsedLuaTableField(fields, i, fullKey, cleanRhs, line, 'line-key', key, 'rgba_table', rgba)
                            parseInlineLuaPairs(line, fullKey, i, fields)
                        elseif cleanRhs:sub(1, 1) == '{' and delta > 0 then
                            table.insert(stack, { path = fullKey, arrayIndex = 0 })
                        elseif cleanRhs:sub(1, 1) == '{' then
                            parseInlineLuaPairs(line, fullKey, i, fields)
                        else
                            addParsedLuaTableField(fields, i, fullKey, cleanRhs, line, 'line-key', key)
                        end
                    end
                end
            end
        end

        i = i + 1
    end

    return fields
end

local function replaceInlineLuaValue(line, inlineKey, replacementValue)
    inlineKey = tostring(inlineKey or '')
    if inlineKey == '' then return nil end
    local pattern = '([%s,{]' .. luaPatternEscape(inlineKey) .. '%s*=%s*)'
    local s, e, prefix = line:find(pattern)
    if not s then
        pattern = '^(' .. luaPatternEscape(inlineKey) .. '%s*=%s*)'
        s, e, prefix = line:find(pattern)
    end
    if not s then return nil end
    local valueStart = e + 1
    local valueEnd = findValueEnd(line, valueStart)
    return line:sub(1, valueStart - 1) .. tostring(replacementValue or '') .. line:sub(valueEnd + 1)
end

local function replaceLineKeyValue(line, inlineKey, replacementValue)
    local key = luaPatternEscape(inlineKey or '')
    local prefix = line:match('^(%s*' .. key .. '%s*=%s*)')
    if not prefix then return nil end
    local comment = line:match('(%s*%-%-.*)$') or ''
    local beforeComment = line:gsub('%s*%-%-.*$', '')
    local comma = beforeComment:match(',%s*$') and ',' or ''
    return prefix .. tostring(replacementValue or '') .. comma .. comment
end

local function keyFromLine(line)
    local lhs, rhs = line:match('^%s*([%w_%.:%[%]"\']+)%s*=%s*(.-)%s*$')
    if not lhs or not rhs then return nil, nil end

    if not lhs:match('^Config') and not lhs:match('^Settings') and not lhs:match('^Shared') and not lhs:match('^Jobs') and not lhs:match('^Locations') then
        return nil, nil
    end

    return lhs, rhs
end

local function splitDefaultOrExpression(key, rhs)
    
    
    local clean = trim(stripInlineComment(rhs or ''))
    local left, expr = clean:match('^([%w_%.:%[%]\"\']+)%s+or%s+(.+)$')
    if left and trim(left) == trim(key or '') and expr and expr ~= '' then
        return trim(expr), left .. ' or '
    end
    return clean, nil
end

local function parseLuaFields(content)
    local lines = splitLines(content)
    local fields = {}
    local i = 1

    while i <= #lines and #fields < (Config.MaxParsedFieldsPerFile or 500) do
        local line = lines[i]
        local key, rhs = keyFromLine(line)
        if key and rhs then
            local cleanRhs, rhsPrefix = splitDefaultOrExpression(key, rhs)
            local startLine = i
            local endLine = i
            local rawBlock = line
            local delta = braceDelta(line)

            if cleanRhs:sub(1, 1) == '{' and delta > 0 then
                local j = i + 1
                while j <= #lines and delta > 0 do
                    delta = delta + braceDelta(lines[j])
                    rawBlock = rawBlock .. '\n' .. lines[j]
                    endLine = j
                    j = j + 1
                    if #rawBlock > (Config.MaxTableFieldBytes or 80000) then break end
                end
            end

            local valueType, value, valueMeta = detectLuaValue(cleanRhs)
            if valueType == 'string' and (looksLikeColorKey(key) or looksLikeColorValue(value)) then
                valueType = 'color'
            end
            if endLine > startLine then
                valueType = 'table'
                value = rawBlock
            end

            fields[#fields + 1] = {
                id = tostring(startLine) .. ':' .. key,
                key = key,
                type = valueType,
                value = value,
                raw = rawBlock,
                startLine = startLine,
                endLine = endLine,
                editable = true,
                rhsPrefix = rhsPrefix,
                valueConstructor = valueMeta and valueMeta.constructor or nil,
            }
            i = endLine
        end
        i = i + 1
    end

    return parseLocalConfigTables(content, fields)
end

local function flattenJson(value, prefix, fields, depth)
    fields = fields or {}
    depth = depth or 0
    if #fields >= (Config.MaxParsedFieldsPerFile or 500) then return fields end
    if depth > 7 then return fields end

    local valueType = type(value)
    if valueType == 'table' then
        local vectorType, vectorValue, vectorShape, vectorKeys = detectJsonVectorTable(value)
        if vectorType then
            fields[#fields + 1] = {
                id = prefix,
                key = prefix,
                type = vectorType,
                value = vectorValue,
                raw = safeJsonEncode(value),
                editable = true,
                vectorShape = vectorShape,
                vectorKeys = vectorKeys,
            }
            return fields
        end

        local count = 0
        for _ in pairs(value) do count = count + 1 end
        if count == 0 then return fields end

        if prefix ~= '' then
            fields[#fields + 1] = {
                id = prefix,
                key = prefix,
                type = 'json-table',
                value = safeJsonEncode(value),
                raw = safeJsonEncode(value),
                editable = false,
            }
        end

        for k, v in pairs(value) do
            local child = prefix == '' and tostring(k) or (prefix .. '.' .. tostring(k))
            if type(v) == 'table' then
                flattenJson(v, child, fields, depth + 1)
            elseif type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then
                local fieldType = type(v)
                if fieldType == 'string' and (looksLikeColorKey(child) or looksLikeColorValue(v)) then
                    fieldType = 'color'
                end
                fields[#fields + 1] = {
                    id = child,
                    key = child,
                    type = fieldType,
                    value = v,
                    raw = tostring(v),
                    editable = true,
                }
            end
            if #fields >= (Config.MaxParsedFieldsPerFile or 500) then break end
        end
    end
    return fields
end

local function parseFields(path, content)
    local ext = getExtension(path)
    if ext == 'lua' or ext == 'callout' then
        return parseLuaFields(content)
    elseif ext == 'json' then
        local data = safeJsonDecode(content, nil)
        if type(data) == 'table' then return flattenJson(data, '', {}) end
    end
    return {}
end

local function getKind(path)
    local p = lower(path)
    if p:find('job', 1, true) then return 'Jobs' end
    if p:find('location', 1, true) or p:find('coord', 1, true) or p:find('spawn', 1, true) or p:find('route', 1, true) then return 'Locations' end
    if p:find('item', 1, true) or p:find('shop', 1, true) or p:find('price', 1, true) then return 'Items/Values' end
    if p:find('callout', 1, true) then return 'Callouts' end
    if p:find('vehicle', 1, true) or p:find('weapon', 1, true) then return 'Vehicles/Weapons' end
    return 'Config'
end

local function shouldIgnoreResource(resourceName)
    if not resourceName or resourceName == '' then return true end
    if resourceName == RESOURCE then return true end
    if Config.IgnoreResources and Config.IgnoreResources[resourceName] then return true end
    return false
end

local function scanResources(force)
    local now = os.time()
    if not force and Scan.lastRun > 0 and (now - Scan.lastRun) < 5 then
        return Scan
    end

    local resources = {}
    local filesById = {}
    local totals = { resources = 0, files = 0, fields = 0 }

    local count = GetNumResources()
    for i = 0, count - 1 do
        local resourceName = GetResourceByFindIndex(i)
        if resourceName and not shouldIgnoreResource(resourceName) then
            local candidates = getResourceCandidates(resourceName)
            local files = {}

            for path in pairs(candidates) do
                local raw = loadResourceText(resourceName, path)
                if raw and #raw <= (Config.MaxFileBytes or 750000) then
                    local fields = parseFields(path, raw)
                    local id = makeFileId(resourceName, path)
                    local info = {
                        id = id,
                        resource = resourceName,
                        path = path,
                        name = path:match('([^/]+)$') or path,
                        ext = getExtension(path),
                        kind = getKind(path),
                        size = #raw,
                        fields = #fields,
                    }
                    files[#files + 1] = info
                    filesById[id] = info
                    totals.files = totals.files + 1
                    totals.fields = totals.fields + #fields
                end
            end

            table.sort(files, function(a, b)
                if a.kind == b.kind then return a.path < b.path end
                return a.kind < b.kind
            end)

            if #files > 0 or Config.ShowResourcesWithoutConfig == true then
                local state = GetResourceState(resourceName) or 'unknown'
                resources[#resources + 1] = {
                    name = resourceName,
                    state = state,
                    files = files,
                    fileCount = #files,
                }
                totals.resources = totals.resources + 1
            end
        end
    end

    table.sort(resources, function(a, b) return lower(a.name) < lower(b.name) end)

    Scan.resources = resources
    Scan.filesById = filesById
    Scan.lastRun = now
    Scan.totals = totals

    debugPrint(('Scanned %s resources, %s files, %s fields'):format(totals.resources, totals.files, totals.fields))
    return Scan
end

local function isAdmin(src)
    src = tonumber(src or 0) or 0
    if src == 0 then return true end

    if Config.UseAzFrameworkAdmin and Config.FrameworkResource and GetResourceState(Config.FrameworkResource) == 'started' then
        local ok, res = pcall(function()
            return exports[Config.FrameworkResource]:isAdmin(src)
        end)
        if ok and res == true then return true end
    end

    if Config.AcePermission and Config.AcePermission ~= '' and IsPlayerAceAllowed(src, Config.AcePermission) then
        return true
    end

    if IsPlayerAceAllowed(src, 'adminmenu.use') then return true end
    if IsPlayerAceAllowed(src, 'command') then return true end

    return false
end

local function notify(src, message, msgType)
    TriggerClientEvent('az-configmanager:client:notify', src, {
        message = tostring(message or ''),
        type = msgType or 'info'
    })
end

local function readBackupIndex()
    if BackupIndex ~= nil then return BackupIndex end
    local raw = LoadResourceFile(RESOURCE, 'backups/index.json')
    BackupIndex = safeJsonDecode(raw, { entries = {} })
    if type(BackupIndex) ~= 'table' then BackupIndex = { entries = {} } end
    if type(BackupIndex.entries) ~= 'table' then BackupIndex.entries = {} end
    return BackupIndex
end

local function saveBackupIndex()
    local encoded = safeJsonEncode(BackupIndex or { entries = {} })
    SaveResourceFile(RESOURCE, 'backups/index.json', encoded, #encoded)
end

local function backupFile(resourceName, path, content, src)
    local index = readBackupIndex()
    local fileName = ('%s__%s__%s.bak'):format(sanitizeFileName(resourceName), sanitizeFileName(path), nowStamp())
    local backupPath = 'backups/' .. fileName
    local ok = SaveResourceFile(RESOURCE, backupPath, content or '', #(content or ''))
    if not ok then return false, 'backup_save_failed' end

    index.entries[#index.entries + 1] = {
        backupPath = backupPath,
        resource = resourceName,
        path = path,
        createdAt = nowIso(),
        source = tonumber(src or 0) or 0,
        sourceName = (tonumber(src or 0) or 0) > 0 and GetPlayerName(src) or 'console',
        size = #(content or ''),
    }

    while #index.entries > 300 do table.remove(index.entries, 1) end
    saveBackupIndex()
    return true, backupPath
end

local function saveTargetFile(resourceName, path, newContent, src)
    if Config.BlockedSaveResources and Config.BlockedSaveResources[resourceName] then
        return false, 'This resource is blocked from UI saves in Config.BlockedSaveResources.'
    end

    if type(newContent) ~= 'string' then return false, 'Invalid content.' end
    if #newContent > (Config.MaxRawSaveBytes or 1000000) then return false, 'File is larger than Config.MaxRawSaveBytes.' end

    local oldContent, err = loadResourceText(resourceName, path)
    if not oldContent then return false, 'Could not read original file: ' .. tostring(err) end

    local backedUp, backupErr = backupFile(resourceName, path, oldContent, src)
    if not backedUp then return false, 'Backup failed, save stopped: ' .. tostring(backupErr) end

    local ok, result = pcall(SaveResourceFile, resourceName, path, newContent, #newContent)
    if not ok or not result then
        return false, 'SaveResourceFile failed. Check file permissions/resource escrow/path.'
    end

    PendingRestart[resourceName] = true
    scanResources(true)
    return true, 'Saved. A backup was created first.'
end

local function luaEscapeString(value)
    value = tostring(value or '')
    value = value:gsub('\\', '\\\\')
    value = value:gsub('\n', '\\n')
    value = value:gsub('\r', '\\r')
    value = value:gsub('\t', '\\t')
    value = value:gsub('"', '\\"')
    return '"' .. value .. '"'
end

local function formatLuaValue(valueType, value, raw)
    valueType = tostring(valueType or 'raw')
    if valueType == 'boolean' then
        return (value == true or value == 'true' or value == 1 or value == '1') and 'true' or 'false'
    elseif valueType == 'number' then
        local n = tonumber(value)
        if n == nil then return nil, 'Invalid number.' end
        return tostring(n)
    elseif valueType == 'string' or valueType == 'color' then
        return luaEscapeString(value)
    elseif valueType == 'rgba_table' then
        local rgba = value
        if type(rgba) ~= 'table' then rgba = safeJsonDecode(rgba, {}) end
        local r = tonumber(rgba.r or rgba.R or rgba[1] or rgba['1'] or 0) or 0
        local g = tonumber(rgba.g or rgba.G or rgba[2] or rgba['2'] or 0) or 0
        local b = tonumber(rgba.b or rgba.B or rgba[3] or rgba['3'] or 0) or 0
        local a = tonumber(rgba.a or rgba.A or rgba[4] or rgba['4'] or 255) or 255
        return ('{ r = %d, g = %d, b = %d, a = %d }'):format(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5), math.floor(a + 0.5))
    elseif valueType == 'vector2' or valueType == 'vector3' or valueType == 'vector4' then
        local coords = value
        if type(coords) ~= 'table' then coords = safeJsonDecode(coords, {}) end
        local need = tonumber(valueType:sub(-1)) or 3
        local out = {}
        for i = 1, need do out[#out + 1] = tostring(tonumber(coords[i] or coords[tostring(i)] or 0) or 0) end
        return ('%s(%s)'):format(valueType, table.concat(out, ', '))
    elseif valueType == 'table' then
        raw = tostring(raw or value or '')
        if raw == '' then return nil, 'Empty table/raw value.' end
        return raw
    elseif valueType == 'raw' then
        raw = tostring(raw or value or '')
        if raw == '' then return nil, 'Empty raw value.' end
        return raw
    end
    return nil, 'This value type must be edited in Raw mode.'
end

local function saveLuaField(fileId, fieldId, valueType, value, raw, src)
    local info = Scan.filesById[fileId]
    if not info then
        scanResources(true)
        info = Scan.filesById[fileId]
    end
    if not info then return false, 'Unknown file. Rescan and try again.' end
    if getExtension(info.path) ~= 'lua' and getExtension(info.path) ~= 'callout' then
        return false, 'Typed field saving only supports Lua/callout files. Use Raw mode for this file.'
    end

    local content, err = loadResourceText(info.resource, info.path)
    if not content then return false, 'Could not read file: ' .. tostring(err) end

    local fields = parseFields(info.path, content)
    local field
    for _, f in ipairs(fields) do
        if tostring(f.id) == tostring(fieldId) then field = f break end
    end
    if not field then return false, 'Could not find that field. The file may have changed; reload it.' end

    local replacementValue, formatErr = formatLuaValue(valueType or field.type, value, raw)
    if not replacementValue then return false, formatErr end
    local effectiveType = tostring(valueType or field.type or '')
    if (effectiveType == 'vector2' or effectiveType == 'vector3' or effectiveType == 'vector4') and field.valueConstructor then
        replacementValue = replacementValue:gsub('^vector[234]', tostring(field.valueConstructor)):gsub('^vec[234]', tostring(field.valueConstructor))
    end

    local lines = splitLines(content)
    local originalLine = lines[field.startLine]
    if not originalLine then return false, 'Invalid line index.' end

    if field.localTableMode == 'line-key' then
        local replaced = replaceLineKeyValue(originalLine, field.inlineKey, replacementValue)
        if not replaced then return false, 'Could not update that local Config value. Use Raw mode for this field.' end
        lines[field.startLine] = replaced
        return saveTargetFile(info.resource, info.path, joinLines(lines), src)
    elseif field.localTableMode == 'inline-key' then
        local replaced = replaceInlineLuaValue(originalLine, field.inlineKey, replacementValue)
        if not replaced then return false, 'Could not update that inline Config value. Use Raw mode for this field.' end
        lines[field.startLine] = replaced
        return saveTargetFile(info.resource, info.path, joinLines(lines), src)
    end

    if (valueType or field.type) == 'table' or (valueType or field.type) == 'raw' then
        local rawReplacement = tostring(replacementValue or '')
        local replacementLines = splitLines(rawReplacement)
        local newLines = {}
        for i = 1, field.startLine - 1 do newLines[#newLines + 1] = lines[i] end
        for _, line in ipairs(replacementLines) do newLines[#newLines + 1] = line end
        for i = field.endLine + 1, #lines do newLines[#newLines + 1] = lines[i] end
        return saveTargetFile(info.resource, info.path, joinLines(newLines), src)
    end

    local prefix = originalLine:match('^(%s*[%w_%.:%[%]"\']+%s*=%s*)')
    if not prefix then return false, 'Could not preserve assignment prefix.' end

    local comment = originalLine:match('%s*(%-%-.*)$') or ''
    local rhsPrefix = tostring(field.rhsPrefix or '')
    lines[field.startLine] = prefix .. rhsPrefix .. replacementValue .. (comment ~= '' and (' ' .. comment) or '')
    return saveTargetFile(info.resource, info.path, joinLines(lines), src)
end


local function jsonPathSegments(path)
    local out = {}
    for part in tostring(path or ''):gmatch('[^%.]+') do
        local n = tonumber(part)
        if n and tostring(n) == part then
            out[#out + 1] = n
        else
            out[#out + 1] = part
        end
    end
    return out
end

local function setJsonPath(root, path, newValue)
    local parts = jsonPathSegments(path)
    if #parts == 0 then return false, 'Invalid JSON path.' end
    local cursor = root
    for i = 1, #parts - 1 do
        cursor = cursor[parts[i]]
        if type(cursor) ~= 'table' then return false, 'JSON path no longer exists.' end
    end
    cursor[parts[#parts]] = newValue
    return true
end

local function formatJsonFieldValue(field, valueType, value, raw)
    valueType = tostring(valueType or field.type or 'raw')
    if valueType == 'boolean' then
        return (value == true or value == 'true' or value == 1 or value == '1') and true or false
    elseif valueType == 'number' then
        local n = tonumber(value)
        if n == nil then return nil, 'Invalid number.' end
        return n
    elseif valueType == 'string' or valueType == 'color' then
        return tostring(value or '')
    elseif valueType == 'vector2' or valueType == 'vector3' or valueType == 'vector4' then
        local coords = value
        if type(coords) ~= 'table' then coords = safeJsonDecode(coords, {}) end
        local need = tonumber(valueType:sub(-1)) or 3
        local numbers = {}
        for i = 1, need do numbers[i] = tonumber(coords[i] or coords[tostring(i)] or 0) or 0 end
        if field.vectorShape == 'object' then
            local keys = field.vectorKeys or { 'x', 'y', 'z', 'w' }
            local out = {}
            for i = 1, need do out[keys[i] or ({ 'x', 'y', 'z', 'w' })[i]] = numbers[i] end
            return out
        end
        return numbers
    elseif valueType == 'json-table' then
        return nil, 'JSON tables are view-only in Fields mode. Use Raw mode for full table edits.'
    end
    return nil, 'This JSON field type must be edited in Raw mode.'
end

local function jsonPretty(value, indent)
    indent = indent or 0
    local t = type(value)
    if t ~= 'table' then return safeJsonEncode(value) end

    local isArray, n = isArrayTable(value)
    local pad = string.rep('  ', indent)
    local childPad = string.rep('  ', indent + 1)
    local parts = {}

    if isArray then
        if n == 0 then return '[]' end
        for i = 1, n do
            parts[#parts + 1] = childPad .. jsonPretty(value[i], indent + 1)
        end
        return '[\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. ']'
    end

    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    if #keys == 0 then return '{}' end
    for _, k in ipairs(keys) do
        parts[#parts + 1] = childPad .. safeJsonEncode(tostring(k)) .. ': ' .. jsonPretty(value[k], indent + 1)
    end
    return '{\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. '}'
end

local function saveJsonField(fileId, fieldId, valueType, value, raw, src)
    local info = Scan.filesById[fileId]
    if not info then
        scanResources(true)
        info = Scan.filesById[fileId]
    end
    if not info then return false, 'Unknown file. Rescan and try again.' end
    if getExtension(info.path) ~= 'json' then return false, 'JSON field saving only supports .json files.' end

    local content, err = loadResourceText(info.resource, info.path)
    if not content then return false, 'Could not read file: ' .. tostring(err) end

    local data = safeJsonDecode(content, nil)
    if type(data) ~= 'table' then return false, 'Could not parse this JSON file.' end

    local fields = parseFields(info.path, content)
    local field
    for _, f in ipairs(fields) do
        if tostring(f.id) == tostring(fieldId) then field = f break end
    end
    if not field then return false, 'Could not find that JSON field. Reload the file and try again.' end
    if field.editable == false then return false, 'That JSON field is view-only. Edit it in Raw mode.' end

    local replacementValue, formatErr = formatJsonFieldValue(field, valueType or field.type, value, raw)
    if replacementValue == nil and formatErr then return false, formatErr end

    local ok, setErr = setJsonPath(data, field.id, replacementValue)
    if not ok then return false, setErr end

    return saveTargetFile(info.resource, info.path, jsonPretty(data), src)
end

local function saveTypedField(fileId, fieldId, valueType, value, raw, src)
    local info = Scan.filesById[fileId]
    if not info then
        scanResources(true)
        info = Scan.filesById[fileId]
    end
    if not info then return false, 'Unknown file. Rescan and try again.' end

    local ext = getExtension(info.path)
    if ext == 'lua' or ext == 'callout' then
        return saveLuaField(fileId, fieldId, valueType, value, raw, src)
    elseif ext == 'json' then
        return saveJsonField(fileId, fieldId, valueType, value, raw, src)
    end

    return false, 'Typed field saving only supports Lua/callout/JSON files. Use Raw mode for this file.'
end

local function getPublicScanData()
    scanResources(false)
    return {
        resources = Scan.resources,
        totals = Scan.totals,
        lastRun = Scan.lastRun,
        allowRestart = Config.AllowRestartButton == true,
        pendingRestart = PendingRestart,
    }
end

local function getFilePayload(fileId)
    scanResources(false)
    local info = Scan.filesById[fileId]
    if not info then return nil, 'Unknown file. Run rescan.' end

    local content, err = loadResourceText(info.resource, info.path)
    if not content then return nil, 'Could not read file: ' .. tostring(err) end

    local fields = parseFields(info.path, content)
    return {
        info = info,
        content = content,
        fields = fields,
        fieldCount = #fields,
        pendingRestart = PendingRestart[info.resource] == true,
    }
end

local function listBackups(resourceName, path)
    local index = readBackupIndex()
    local out = {}
    for i = #index.entries, 1, -1 do
        local entry = index.entries[i]
        if (not resourceName or entry.resource == resourceName) and (not path or entry.path == path) then
            out[#out + 1] = entry
            if #out >= 50 then break end
        end
    end
    return out
end

local function restoreBackup(backupPath, src)
    local index = readBackupIndex()
    local chosen
    for _, entry in ipairs(index.entries) do
        if entry.backupPath == backupPath then chosen = entry break end
    end
    if not chosen then return false, 'Backup not found in index.' end

    local backupContent = LoadResourceFile(RESOURCE, chosen.backupPath)
    if not backupContent then return false, 'Backup file missing.' end

    return saveTargetFile(chosen.resource, chosen.path, backupContent, src)
end

local function restartTargetResource(resourceName)
    if Config.AllowRestartButton ~= true then return false, 'Restart button disabled in config.' end
    if shouldIgnoreResource(resourceName) then return false, 'Cannot restart that resource from the manager.' end
    ExecuteCommand(('restart %s'):format(resourceName))
    PendingRestart[resourceName] = nil
    SetTimeout(2500, function() scanResources(true) end)
    return true, 'Restart command sent.'
end

RegisterNetEvent('az-configmanager:server:open', function()
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission to open Azure Config Manager.', 'error')
        return
    end

    TriggerClientEvent('az-configmanager:client:open', src, getPublicScanData())
end)

RegisterNetEvent('az-configmanager:server:request', function(requestId, action, payload)
    local src = source
    if not isAdmin(src) then
        TriggerClientEvent('az-configmanager:client:response', src, requestId, false, 'No permission.')
        return
    end

    payload = type(payload) == 'table' and payload or {}

    if action == 'getResources' then
        TriggerClientEvent('az-configmanager:client:response', src, requestId, true, getPublicScanData())

    elseif action == 'rescan' then
        scanResources(true)
        TriggerClientEvent('az-configmanager:client:response', src, requestId, true, getPublicScanData())

    elseif action == 'getFile' then
        local data, err = getFilePayload(payload.fileId)
        TriggerClientEvent('az-configmanager:client:response', src, requestId, data ~= nil, data or err)

    elseif action == 'saveRaw' then
        local info = Scan.filesById[payload.fileId]
        if not info then
            scanResources(true)
            info = Scan.filesById[payload.fileId]
        end
        local ok, msg
        if not info then
            ok, msg = false, 'Unknown file. Rescan and try again.'
        else
            ok, msg = saveTargetFile(info.resource, info.path, tostring(payload.content or ''), src)
        end
        TriggerClientEvent('az-configmanager:client:response', src, requestId, ok, msg)

    elseif action == 'saveField' then
        local ok, msg = saveTypedField(payload.fileId, payload.fieldId, payload.type, payload.value, payload.raw, src)
        TriggerClientEvent('az-configmanager:client:response', src, requestId, ok, msg)

    elseif action == 'getBackups' then
        local info = Scan.filesById[payload.fileId]
        local backups = info and listBackups(info.resource, info.path) or listBackups(nil, nil)
        TriggerClientEvent('az-configmanager:client:response', src, requestId, true, backups)

    elseif action == 'restoreBackup' then
        local ok, msg = restoreBackup(payload.backupPath, src)
        TriggerClientEvent('az-configmanager:client:response', src, requestId, ok, msg)

    elseif action == 'restartResource' then
        local ok, msg = restartTargetResource(tostring(payload.resource or ''))
        TriggerClientEvent('az-configmanager:client:response', src, requestId, ok, msg)

    else
        TriggerClientEvent('az-configmanager:client:response', src, requestId, false, 'Unknown action: ' .. tostring(action))
    end
end)

CreateThread(function()
    Wait(tonumber(Config.InitialScanDelayMs) or 8000)
    scanResources(true)
    print(('^4[%s]^7 Ready. /%s opens the in-game config manager. Scanned %s resources with %s editable files.'):format(
        RESOURCE,
        Config.Command or 'azmanager',
        tostring(Scan.totals.resources),
        tostring(Scan.totals.files)
    ))
end)

exports('Rescan', function()
    scanResources(true)
    return Scan.totals
end)

exports('GetScanTotals', function()
    scanResources(false)
    return shallowCopy(Scan.totals)
end)
