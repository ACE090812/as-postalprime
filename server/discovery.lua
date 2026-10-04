-- Discovery: "customers also bought", "bought before", and phone alerts when a saved (wishlist) item goes on sale or
-- comes back in stock.

PPDiscovery = {}

local REBUILD_SECONDS = 300
local cache = { at = 0, map = {} }

local function catalogOrder()
    local order = {}
    for i, e in ipairs(Config.catalog) do order[e.id] = i end
    return order
end

-- Counts how often each pair of catalog items was collected together in the same order, across every player.
local function rebuild()
    local pos = catalogOrder()
    local counts = {}
    for _, pd in pairs(PPStore.players) do
        for _, o in ipairs(pd.history or {}) do
            if o.collected and not o.parcel then
                local ids, seen = {}, {}
                for _, it in ipairs(o.items) do
                    if pos[it.id] and not seen[it.id] then
                        seen[it.id] = true
                        ids[#ids + 1] = it.id
                    end
                end
                for _, a in ipairs(ids) do
                    for _, b in ipairs(ids) do
                        if a ~= b then
                            counts[a] = counts[a] or {}
                            counts[a][b] = (counts[a][b] or 0) + 1
                        end
                    end
                end
            end
        end
    end
    local map = {}
    for a, others in pairs(counts) do
        local list = {}
        for b, n in pairs(others) do list[#list + 1] = { id = b, n = n } end
        table.sort(list, function(x, y)
            if x.n ~= y.n then return x.n > y.n end
            return pos[x.id] < pos[y.id]
        end)
        local top = {}
        for i = 1, math.min(3, #list) do top[i] = list[i].id end
        map[a] = top
    end
    cache = { at = os.time(), map = map }
end

-- Forces the next alsoBought() call to recount (used by tests / after bulk changes).
function PPDiscovery.invalidate() cache.at = 0 end

function PPDiscovery.alsoBought(itemId)
    if os.time() - cache.at > REBUILD_SECONDS then rebuild() end
    return cache.map[itemId]
end

-- Catalog item ids this player has collected before (any order, any time in their history).
function PPDiscovery.boughtBefore(pd)
    local out, seen = {}, {}
    for _, o in ipairs(pd.history or {}) do
        if o.collected and not o.parcel then
            for _, it in ipairs(o.items) do
                if not seen[it.id] and not it.listingId then
                    seen[it.id] = true
                    out[#out + 1] = it.id
                end
            end
        end
    end
    return out
end

-- ─── Wishlist alerts ─────────────────────────────────────────────────────────

local last = {}      -- [itemId] = { price, stock } from the previous check
local alerted = {}   -- [cid .. itemId] = os.time() of the last alert (one per hour at most)
local ALERT_COOLDOWN = 3600

local function alertWishlisters(entry, price, why)
    for cid, src in pairs(PP.onlineSources) do
        local pd = PPStore.players[cid]
        local key = cid .. entry.id
        if pd and pd.wishlist and pd.wishlist[entry.id] and (os.time() - (alerted[key] or 0)) > ALERT_COOLDOWN then
            alerted[key] = os.time()
            PP.notify(src, T('notif.wishlist.' .. why .. '.title'), T('notif.wishlist.' .. why .. '.body', entry.label, price))
        end
    end
end

CreateThread(function()
    Wait(20000)
    while true do
        local cfg = Config.notifications
        if cfg and cfg.wishlistAlerts ~= false then
            local deals = PPDeals.active()
            for _, entry in ipairs(Config.catalog) do
                local deal = deals[entry.id]
                local price = deal and PPDeals.round2(entry.price * (100 - deal.pct) / 100) or entry.price
                local stock = PPStore.getStock(entry.id)
                local prev = last[entry.id]
                if prev then
                    if price < prev.price - 0.001 then
                        alertWishlisters(entry, price, 'sale')
                    elseif prev.stock ~= nil and prev.stock <= 0 and (stock == nil or stock > 0) then
                        alertWishlisters(entry, price, 'stock')
                    end
                end
                last[entry.id] = { price = price, stock = stock }
            end
        end
        Wait(30000)
    end
end)

return PPDiscovery
