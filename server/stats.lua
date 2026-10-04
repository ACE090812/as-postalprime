-- Statistics: a player's own spending stats (the You tab) and server-wide daily sales counters (/ppadmin stats).

PPStats = {}

local round2 = PPDeals.round2

-- ─── Personal stats ──────────────────────────────────────────────────────────
-- pd.stats keeps lifetime totals (the order history only keeps the last few orders). The first time it is needed it
-- is built from whatever history exists, then updated as orders are collected.

local function monthKey(ts) return os.date('%Y-%m', ts) end

local function addOrderTo(st, order)
    st.orders = (st.orders or 0) + 1
    st.spent = round2((st.spent or 0) + (order.total or 0))
    st.saved = round2((st.saved or 0) + (order.discount or 0) + (order.pointsDiscount or 0) + (order.dealSavings or 0))
    local mk = monthKey(order.collectedAt or order.placedAt or os.time())
    st.byMonth[mk] = round2((st.byMonth[mk] or 0) + (order.total or 0))
    for _, it in ipairs(order.items) do
        local entry = PP.findCatalogItem(it.id)
        local cat = it.listingId and 'market' or (entry and entry.cat) or 'other'
        st.byCat[cat] = round2((st.byCat[cat] or 0) + (it.price or 0) * (it.qty or 0))
        st.items[it.id] = (st.items[it.id] or 0) + (it.qty or 0)
    end
end

local function ensure(pd)
    if pd.stats then return pd.stats end
    local st = { orders = 0, spent = 0, saved = 0, returned = 0, byMonth = {}, byCat = {}, items = {} }
    for _, o in ipairs(pd.history or {}) do
        if o.collected and not o.parcel and not o.takenBy then addOrderTo(st, o) end
        for _, it in ipairs(o.items or {}) do
            if (it.returned or 0) > 0 then
                st.returned = round2(st.returned + (it.returned or 0) * (it.price or 0) * 0.8)
            end
        end
    end
    pd.stats = st
    return st
end

-- Called for every collected order (see PP.onCollected). Stats belong to whoever collected it.
function PPStats.recordCollected(cid, order)
    if order.parcel or order.takenBy then return end
    local pd = PPStore.getPlayer(cid)
    local st = ensure(pd)
    addOrderTo(st, order)
    PPStore.markDirty(cid)
end

function PPStats.recordReturn(cid, refund)
    local st = ensure(PPStore.getPlayer(cid))
    st.returned = round2((st.returned or 0) + refund)
    PPStore.markDirty(cid)
end

function PPStats.personal(pd, reviewsWritten)
    local st = ensure(pd)
    local months = {}
    local now = os.time()
    local t = os.date('*t', now)
    for i = 5, 0, -1 do
        local ts = os.time({ year = t.year, month = t.month - i, day = 1, hour = 12 })
        local key = monthKey(ts)
        months[#months + 1] = { key = key, label = os.date('%b', ts), total = st.byMonth[key] or 0 }
    end
    local cats = {}
    local labels = {}
    for _, c in ipairs(Config.categories or {}) do labels[c.id] = c.label end
    labels.market = T('app.cat.market')
    for id, total in pairs(st.byCat) do cats[#cats + 1] = { id = id, label = labels[id] or id, total = total } end
    table.sort(cats, function(a, b) return a.total > b.total end)
    local top = {}
    for id, qty in pairs(st.items) do
        local entry = PP.findCatalogItem(id)
        if entry then top[#top + 1] = { id = id, label = entry.label, icon = entry.icon, qty = qty } end
    end
    table.sort(top, function(a, b) if a.qty ~= b.qty then return a.qty > b.qty end return a.id < b.id end)
    while #top > 5 do table.remove(top) end
    return {
        orders = st.orders, spent = st.spent, saved = st.saved, returned = st.returned or 0,
        months = months, cats = cats, top = top, reviews = reviewsWritten or 0,
    }
end

lib.callback.register('as-postalprime:stats', function(source)
    local cid = PP.track(source)
    if not cid then return { ok = false } end
    local reviews = 0
    for _, bucket in pairs(PPStore.reviews) do
        if bucket[cid] then reviews = reviews + 1 end
    end
    return { ok = true, stats = PPStats.personal(PPStore.getPlayer(cid), reviews) }
end)

-- ─── Server-wide daily counters ──────────────────────────────────────────────

local dirtyDays = {}

local function today() return os.date('%Y-%m-%d') end

local function dayRow(day)
    day = day or today()
    local d = PPStore.daily[day]
    if not d then d = { items = {} } PPStore.daily[day] = d end
    d.items = d.items or {}
    return d, day
end

-- PPStats.bump('revenue', 12.5) / PPStats.bump('orders')
function PPStats.bump(field, amount)
    local d, day = dayRow()
    d[field] = round2((d[field] or 0) + (amount or 1))
    dirtyDays[day] = true
end

function PPStats.bumpItems(order)
    local d, day = dayRow()
    for _, it in ipairs(order.items) do
        local key = it.listingId and ('market:' .. it.item) or it.id
        d.items[key] = (d.items[key] or 0) + (it.qty or 0)
    end
    dirtyDays[day] = true
end

CreateThread(function()
    while true do
        Wait(30000)
        for day in pairs(dirtyDays) do
            dirtyDays[day] = nil
            PPStore.saveDaily(day)
        end
    end
end)

-- Totals for the last `days` days (1 = today only).
function PPStats.summary(days)
    days = math.max(1, math.floor(days or 1))
    local sum, items = {}, {}
    local now = os.time()
    for i = 0, days - 1 do
        local d = PPStore.daily[os.date('%Y-%m-%d', now - i * 86400)]
        if d then
            for k, v in pairs(d) do
                if k == 'items' then
                    for id, qty in pairs(v) do items[id] = (items[id] or 0) + qty end
                else
                    sum[k] = (sum[k] or 0) + v
                end
            end
        end
    end
    local top = {}
    for id, qty in pairs(items) do top[#top + 1] = { id = id, qty = qty } end
    table.sort(top, function(a, b) if a.qty ~= b.qty then return a.qty > b.qty end return a.id < b.id end)
    return sum, top
end

return PPStats
