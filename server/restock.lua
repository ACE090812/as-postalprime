-- Automatic restocking (Config.restock) and low-stock alerts. A catalog `stock` number is the item's maximum.

local function cfg() return Config.restock or {} end

local function tick()
    local c = cfg()
    if c.enabled == false then return end
    for _, entry in ipairs(Config.catalog) do
        if entry.stock ~= nil then
            local amount = entry.restockAmount
            if amount == nil then amount = c.amount or 5 end
            local current = PPStore.getStock(entry.id) or 0
            if amount > 0 and current < entry.stock then
                local add = math.min(amount, entry.stock - current)
                local total = PPStore.restock(entry.id, add)
                PPLog.log('restock', nil, ('%s restocked +%d (%d/%d)'):format(entry.id, add, total, entry.stock), { item = entry.id })
            end
        end
    end
end

CreateThread(function()
    local interval = math.max(1, cfg().intervalMinutes or 60) * 60000
    while true do
        Wait(interval)
        local ok, err = pcall(tick)
        if not ok then print('[as-postalprime] automatic restock failed: ' .. tostring(err)) end
    end
end)

-- One alert each time an item drops to the threshold; re-arms once it is back above it.
local alerted = {}
CreateThread(function()
    Wait(15000)
    while true do
        local threshold = cfg().lowStockThreshold or 0
        if threshold > 0 then
            for _, entry in ipairs(Config.catalog) do
                local stock = entry.stock ~= nil and PPStore.getStock(entry.id) or nil
                if stock ~= nil then
                    if stock <= threshold and not alerted[entry.id] then
                        alerted[entry.id] = true
                        PPLog.log('lowstock', nil, ('%s is low on stock: %d left'):format(entry.label, stock), { item = entry.id })
                    elseif stock > threshold then
                        alerted[entry.id] = nil
                    end
                end
            end
        end
        Wait(60000)
    end
end)
