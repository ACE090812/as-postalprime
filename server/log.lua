-- Audit log: console, ox_lib's logger and/or a Discord webhook (Config.logging). Safe to call from anywhere:
--   PPLog.log('purchase', source, 'bought 3 items for $120', { orderId = '...' })
-- `source` may be nil/0 for server-side events. Never errors back into the caller.

PPLog = {}

local queue = {}

local function cfg() return Config.logging or {} end

local COLORS = {
    purchase = 3066993, sale = 3066993, cancel = 15105570, ['return'] = 15105570, damaged = 15105570,
    lockout = 15158332, lowstock = 15844367, admin = 10181046, listing = 3447003, coupon = 3447003, restock = 3447003,
}

function PPLog.log(event, source, message, fields)
    local c = cfg()
    if c.enabled == false then return end
    local ok = pcall(function()
        message = tostring(message or '')
        if c.console then
            print(('[as-postalprime] [%s] %s%s'):format(event, source and source > 0 and ('(' .. source .. ') ') or '', message))
        end
        if c.oxLogger and lib and lib.logger then
            lib.logger(source or 0, 'postalprime:' .. event, message)
        end
        local url = c.webhook
        if type(url) == 'string' and url ~= '' and c.webhookEvents and c.webhookEvents[event] then
            local embedFields = {}
            for k, v in pairs(fields or {}) do
                embedFields[#embedFields + 1] = { name = tostring(k), value = tostring(v), inline = true }
            end
            if source and source > 0 then
                embedFields[#embedFields + 1] = { name = 'player', value = ('%s (id %d)'):format(GetPlayerName(source) or '?', source), inline = true }
            end
            queue[#queue + 1] = {
                username = c.webhookName or 'Postal Prime',
                embeds = { {
                    title = event, description = message, color = COLORS[event] or 8421504,
                    fields = embedFields, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                } },
            }
        end
    end)
    if not ok then print('[as-postalprime] logging failed for event ' .. tostring(event)) end
end

-- Discord allows ~5 requests per 2 seconds per webhook: send one every 1.2s, drop the oldest if it backs up.
CreateThread(function()
    while true do
        Wait(1200)
        local url = cfg().webhook
        if type(url) == 'string' and url ~= '' and #queue > 0 then
            while #queue > 25 do table.remove(queue, 1) end
            local payload = table.remove(queue, 1)
            PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
        elseif #queue > 0 then
            queue = {}
        end
    end
end)

return PPLog
