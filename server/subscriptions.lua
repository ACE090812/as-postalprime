-- Subscribe & save (Config.subscriptions): a catalog item that is ordered again on a schedule, delivered to a locker.
-- A subscription lives on the player's record (pd.subs). Every few seconds the sweep calls PPSubs.process for online
-- players; anything due is charged and placed as an ordinary shop order (so it shows in Orders, gets a pickup code,
-- is picked up like any other order, and can be cancelled while preparing).

PPSubs = {}

local track = PP.track
local round2 = PPDeals.round2

local function cfg() return Config.subscriptions or {} end

local function enabled() return Config.subscriptions ~= nil and cfg().enabled ~= false end

local function interval(id)
    for _, i in ipairs(cfg().intervals or {}) do
        if i.id == id then return i end
    end
end

local function discountFor(pd)
    return PP.isPlusActive(pd) and (cfg().plusDiscountPct or cfg().discountPct or 0) or (cfg().discountPct or 0)
end

function PPSubs.stateFor(pd)
    if not enabled() then return { enabled = false } end
    local list = {}
    for _, s in ipairs(pd.subs or {}) do
        local entry = PP.findCatalogItem(s.itemId)
        local lockerLabel = (PP.findLocker(s.lockerId) or {}).label
        list[#list + 1] = {
            id = s.id, itemId = s.itemId, label = entry and entry.label or s.itemId, icon = entry and entry.icon or '📦',
            qty = s.qty, intervalLabel = (interval(s.interval) or {}).label or s.interval, lockerLabel = lockerLabel,
            nextAt = s.nextAt * 1000, paused = s.paused or false, failures = s.failures or 0,
        }
    end
    local intervals = {}
    for _, i in ipairs(cfg().intervals or {}) do intervals[#intervals + 1] = { id = i.id, label = i.label } end
    return {
        enabled = true, list = list, max = cfg().maxPerPlayer or 3,
        discountPct = discountFor(pd), intervals = intervals,
    }
end

local function newId()
    return ('sub_%08x_%03x'):format(os.time(), math.random(0, 0xfff))
end

lib.callback.register('as-postalprime:subs:create', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    if not enabled() then return { ok = false, error = T('err.subs.off') } end
    if type(data) ~= 'table' then return { ok = false, error = T('err.badRequest') } end

    local pd = PPStore.getPlayer(cid)
    pd.subs = pd.subs or {}
    if #pd.subs >= (cfg().maxPerPlayer or 3) then return { ok = false, error = T('err.subs.max', cfg().maxPerPlayer or 3) } end

    local entry = PP.findCatalogItem(data.itemId)
    if not entry or entry.listing then return { ok = false, error = T('err.subs.item') } end
    local iv = interval(data.interval)
    if not iv then return { ok = false, error = T('err.badRequest') } end
    if not PP.findLocker(data.lockerId) then return { ok = false, error = T('err.pickLocker') } end
    local qty = math.max(1, math.min(10, math.floor(tonumber(data.qty) or 1)))
    for _, s in ipairs(pd.subs) do
        if s.itemId == entry.id then return { ok = false, error = T('err.subs.dup') } end
    end

    pd.subs[#pd.subs + 1] = {
        id = newId(), itemId = entry.id, qty = qty, interval = iv.id, hours = iv.hours, lockerId = data.lockerId,
        nextAt = os.time() + iv.hours * 3600, failures = 0,
    }
    PPStore.savePlayer(cid)
    PPLog.log('subscription', source, ('subscribed to %dx %s (%s)'):format(qty, entry.label, iv.label or iv.id), { item = entry.id })
    return { ok = true, subs = PPSubs.stateFor(pd) }
end)

local function findSub(pd, id)
    for i, s in ipairs(pd.subs or {}) do
        if s.id == id then return s, i end
    end
end

lib.callback.register('as-postalprime:subs:cancel', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false, error = T('err.unavailable') } end
    local pd = PPStore.getPlayer(cid)
    local s, i = findSub(pd, data.id)
    if not s then return { ok = false, error = T('err.subs.gone') } end
    table.remove(pd.subs, i)
    PPStore.savePlayer(cid)
    return { ok = true, subs = PPSubs.stateFor(pd) }
end)

lib.callback.register('as-postalprime:subs:toggle', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false, error = T('err.unavailable') } end
    local pd = PPStore.getPlayer(cid)
    local s = findSub(pd, data.id)
    if not s then return { ok = false, error = T('err.subs.gone') } end
    s.paused = not s.paused or nil
    if not s.paused then
        s.failures = 0
        if s.nextAt < os.time() then s.nextAt = os.time() + 60 end -- resumed: next order shortly, not instantly
    end
    PPStore.savePlayer(cid)
    return { ok = true, subs = PPSubs.stateFor(pd) }
end)

-- Called by the sweep for an ONLINE player. Places any due subscription orders.
function PPSubs.process(cid, pd, source, now)
    if not enabled() then return end
    for i = #pd.subs, 1, -1 do
        local s = pd.subs[i]
        if not s.paused and s.nextAt <= now then
            local entry = PP.findCatalogItem(s.itemId)
            local locker = PP.findLocker(s.lockerId)
            if not entry or entry.listing or not locker then
                table.remove(pd.subs, i)
                PP.notifyCid(cid, T('notif.sub.gone.title'), T('notif.sub.gone.body'))
                PPStore.savePlayer(cid)
            elseif #pd.orders >= (Config.order.maxActive or 3) then
                s.nextAt = now + 600 -- too many orders in flight right now: look again in 10 minutes
            else
                local stock = PP.getStock(entry.id)
                if stock ~= nil and stock < s.qty then
                    s.nextAt = now + (cfg().retryMinutes or 30) * 60
                    PPStore.markDirty(cid)
                else
                    PPSubs.place(cid, pd, source, s, entry, locker, now)
                end
            end
        end
    end
end

function PPSubs.place(cid, pd, source, s, entry, locker, now)
    local plus = PP.isPlusActive(pd)
    local base = PP.unitPrice(entry)
    local price = round2(base * (100 - discountFor(pd)) / 100)
    local itemsTotal = round2(price * s.qty)
    local fee = plus and 0 or (Config.plus.deliveryFee or 0)
    local total = round2(itemsTotal + fee)

    if not PP.charge(source, total) then
        s.failures = (s.failures or 0) + 1
        s.nextAt = now + (cfg().retryMinutes or 30) * 60
        if s.failures >= (cfg().maxFailures or 3) then
            s.paused = true
            PP.notifyCid(cid, T('notif.sub.paused.title'), T('notif.sub.paused.body', entry.label))
        elseif s.failures == 1 then
            PP.notifyCid(cid, T('notif.sub.failed.title'), T('notif.sub.failed.body', entry.label, total))
        end
        PPStore.savePlayer(cid)
        return
    end
    if not PP.spendStock(entry.id, s.qty) then
        PP.pay(source, total)
        s.nextAt = now + (cfg().retryMinutes or 30) * 60
        PPStore.markDirty(cid)
        return
    end

    local prep = plus and (Config.plus.prepSeconds or Config.order.prepSeconds) or (Config.order.prepSeconds or 180)
    local order = {
        id = PP.newOrderId(),
        items = { { id = entry.id, label = entry.label, icon = entry.icon, price = price, qty = s.qty,
                    origPrice = price < entry.price and entry.price or nil } },
        lockerId = locker.id, lockerLabel = locker.label, delivery = 'locker',
        itemsTotal = itemsTotal, deliveryFee = fee, total = total, buyerCid = cid,
        placedAt = now, readyAt = now + prep, expiresAt = now + prep + (Config.order.expireSecondsAfterReady or 1800),
        ready = false, collected = false, expired = false, code = PP.newCode(), subscription = s.id,
        dealSavings = (entry.price > price) and round2((entry.price - price) * s.qty) or nil,
    }
    pd.orders[#pd.orders + 1] = order
    s.failures = 0
    s.nextAt = now + s.hours * 3600
    PPStore.savePlayer(cid)

    PPLog.log('purchase', source, ('subscription order: %dx %s for $%s'):format(s.qty, entry.label, total), { order = order.id, subscription = s.id })
    PP.notify(source, T('notif.sub.ordered.title'), T('notif.sub.ordered.body', s.qty, entry.label, total))
    TriggerClientEvent('as-postalprime:client:updated', source)
end

return PPSubs
