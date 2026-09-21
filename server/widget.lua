-- Feed for the Postal Prime phone widgets (small + medium home-screen widgets, see ui/widget.html).
-- Loaded after server/main.lua: it reads the player's orders through PP.eachOrder / PP.track and the
-- PPStore player rows, and never changes anything. Turn the widgets off with Config.widget.enabled = false.

local function widgetEnabled()
    return Config.widget == nil or Config.widget.enabled ~= false
end

-- Most urgent first. Done states (collected / expired / cancelled) always sort after these.
local RANK = { ready = 1, delivered = 2, out = 3, collecting = 4, waiting = 5, preparing = 6 }
local DONE = { collected = true, expired = true, cancelled = true }

-- The same reading of an order the app's Orders tab uses.
local function statusOf(o)
    if o.cancelled then return 'cancelled' end
    if o.expired then return 'expired' end
    if o.collected then return 'collected' end
    if o.ready then return o.delivery == 'home' and 'delivered' or 'ready' end
    local c = o.courier and o.courier.state or nil
    if c == 'board' then return 'waiting' end
    if c == 'claimed' then return 'collecting' end
    if c == 'loaded' then return 'out' end
    return 'preparing'
end

-- 0-100 for the widget's bar: the preparing timer fills the first half, then each courier stage.
local function progressOf(o, status, now)
    if status == 'preparing' then
        local span = math.max(1, (tonumber(o.readyAt) or now) - (tonumber(o.placedAt) or now))
        local pct = math.max(0, math.min(1, (now - (tonumber(o.placedAt) or now)) / span))
        return math.floor(pct * 50)
    end
    if status == 'waiting' then return 55 end
    if status == 'collecting' then return 65 end
    if status == 'out' then return 80 end
    return 100
end

local function summarise(o, status, now)
    local items, count = {}, 0
    for _, it in ipairs(o.items or {}) do
        count = count + (tonumber(it.qty) or 1)
        if #items < 3 then items[#items + 1] = { label = it.label, qty = tonumber(it.qty) or 1 } end
    end
    return {
        id = o.id,
        status = status,
        delivery = o.delivery or 'locker',
        items = items,
        itemCount = count,
        extra = math.max(0, #(o.items or {}) - #items),
        lockerLabel = o.lockerLabel,
        -- Only ever while the code is usable, the same rule as the app.
        code = (status == 'ready' and o.code) or nil,
        progress = progressOf(o, status, now),
        placedAt = (tonumber(o.placedAt) or 0) * 1000,
    }
end

lib.callback.register('as-postalprime:getWidget', function(source)
    local refresh = math.max(5, math.floor(tonumber(Config.widget and Config.widget.refreshSeconds) or 10))
    if not widgetEnabled() then return { enabled = false, orders = {}, active = 0, refresh = refresh } end

    local cid = PP.track(source)
    if not cid then return { enabled = true, orders = {}, active = 0, refresh = refresh } end

    local now = os.time()
    local pd = PPStore.getPlayer(cid)
    local live, recent = {}, {}

    for _, o in ipairs(PP.eachOrder(pd)) do
        if not o.hidden then -- hidden orders (parts site) are tracked on their own website, not here
            local status = statusOf(o)
            if DONE[status] then recent[#recent + 1] = { o = o, status = status }
            else live[#live + 1] = { o = o, status = status } end
        end
    end
    table.sort(live, function(a, b)
        if RANK[a.status] ~= RANK[b.status] then return RANK[a.status] < RANK[b.status] end
        return (tonumber(a.o.placedAt) or 0) > (tonumber(b.o.placedAt) or 0)
    end)

    -- Finished orders (newest first in pd.history) stay visible for a while, so a parcel you just
    -- collected doesn't vanish from the widget the second you take it.
    local cutoff = now - math.floor((tonumber(Config.widget and Config.widget.historyHours) or 72) * 3600)
    for _, o in ipairs(pd.history or {}) do
        if not o.hidden and (tonumber(o.placedAt) or 0) >= cutoff then recent[#recent + 1] = { o = o, status = statusOf(o) } end
    end

    local out = {}
    for _, e in ipairs(live) do out[#out + 1] = summarise(e.o, e.status, now) end
    for _, e in ipairs(recent) do
        if #out >= 4 then break end
        out[#out + 1] = summarise(e.o, e.status, now)
    end
    while #out > 4 do out[#out] = nil end

    return { enabled = true, orders = out, active = #live, refresh = refresh }
end)
