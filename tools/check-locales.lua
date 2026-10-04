-- Compares every locales/*.lua against locales/en.lua without starting the server:
--     lua tools/check-locales.lua          (run from the resource folder)
-- Reports keys missing from a translation, keys English doesn't have, and %s / %d placeholder mismatches.
-- Exit code 1 if anything is missing or mismatched, so it can be dropped into a git hook if you ever want that.

local dir = arg and arg[0] and arg[0]:match('^(.*)[/\\]tools[/\\][^/\\]+$') or '.'
local localesDir = dir .. '/locales'

Locales = {}
local p = io.popen('ls "' .. localesDir .. '"')
local files = {}
for name in p:lines() do if name:match('%.lua$') then files[#files + 1] = name end end
p:close()
table.sort(files)
for _, f in ipairs(files) do dofile(localesDir .. '/' .. f) end

local en = Locales.en
if not en then print('locales/en.lua not found') os.exit(2) end

local function placeholders(s)
    local n = 0
    for _ in tostring(s):gmatch('%%[sd]') do n = n + 1 end
    return n
end

local bad = false
local codes = {}
for code in pairs(Locales) do if code ~= 'en' then codes[#codes + 1] = code end end
table.sort(codes)
for _, code in ipairs(codes) do
    local dict = Locales[code]
    local missing, extra, fmt = {}, {}, {}
    for k, v in pairs(en) do
        if dict[k] == nil then missing[#missing + 1] = k
        elseif placeholders(dict[k]) ~= placeholders(v) then fmt[#fmt + 1] = k end
    end
    for k in pairs(dict) do if en[k] == nil then extra[#extra + 1] = k end end
    table.sort(missing); table.sort(extra); table.sort(fmt)
    print(('%-6s missing %-3d extra %-3d placeholder-mismatch %d'):format(code, #missing, #extra, #fmt))
    for _, k in ipairs(missing) do print('   missing  ' .. k) end
    for _, k in ipairs(extra) do print('   extra    ' .. k) end
    for _, k in ipairs(fmt) do print('   format   ' .. k) end
    if #missing > 0 or #fmt > 0 then bad = true end
end
os.exit(bad and 1 or 0)
