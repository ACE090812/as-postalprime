-- Locker walls: door assignment, the pickup keypad (collect), taking the box out and opening sealed parcels.

local track = PP.track
local findCatalogItem = PP.findCatalogItem
local eachOrder = PP.eachOrder
local removeOrder = PP.removeOrder
local findOrderById = PP.findOrderById
local hasReadyLockerOrder = PP.hasReadyLockerOrder
local pushHistory = PP.pushHistory

-- ─── Locker wall door assignment ──────────────────────────────────────────────
-- Each Config.lockers point is a physical wall prop with Config.lockerWall.totalDoors
-- individual door slots. An order gets assigned a free slot at its chosen locker the
-- moment it becomes ready, so two players' ready orders at the same locker never fight
-- over the same door.

local function usedDoorSlots(lockerId, excludeCid)
    local used = {}
    for cid, pd in pairs(PPStore.players) do
        if cid ~= excludeCid then
            for _, o in ipairs(eachOrder(pd)) do
                if o.ready and not o.collected and not o.expired and o.lockerId == lockerId and o.doorSlot then
                    used[o.doorSlot] = true
                end
            end
        end
    end
    -- the player's own other orders still occupy their doors too
    local own = excludeCid and PPStore.players[excludeCid]
    if own then
        for _, o in ipairs(eachOrder(own)) do
            if o.ready and not o.collected and not o.expired and o.lockerId == lockerId and o.doorSlot then
                used[o.doorSlot] = true
            end
        end
    end
    return used
end

-- ─── Box size ─────────────────────────────────────────────────────────────────
-- The parcel size an order needs comes from how much is in it: every unit counts as 1 (or the
-- catalog entry's optional `weight`), summed across the whole order, then bucketed by
-- Config.lockerWall.boxSizeMaxUnits into s / m / l / xl. Each door slot has a fixed box model
-- (Config.lockerBoxOffsets[slot].model = asparcel_s/m/l/xl), so the order gets a door whose box
-- matches - a bigger order lands in a bigger door AND spawns a bigger box.

local SIZE_RANK = { s = 1, m = 2, l = 3, xl = 4 }

local function orderBoxSize(order)
    local units = 0
    for _, it in ipairs(order.items) do
        local entry = findCatalogItem(it.id)
        units = units + (tonumber(it.qty) or 1) * ((entry and tonumber(entry.weight)) or 1)
    end
    local t = Config.lockerWall.boxSizeMaxUnits or { s = 2, m = 4, l = 7 }
    if units <= (t.s or 2) then return 's' end
    if units <= (t.m or 4) then return 'm' end
    if units <= (t.l or 7) then return 'l' end
    return 'xl'
end

PP.orderBoxSize = orderBoxSize

local function slotSizeRank(slot)
    local def = Config.lockerBoxOffsets and Config.lockerBoxOffsets[slot]
    local size = def and def.model and def.model:match('asparcel_(%a+)$')
    return SIZE_RANK[size or 'm'] or 2
end

-- Picks a random free door whose box fits the order: exact size first, then the next size up
-- (closest first), and only if nothing bigger is free, smaller ones (closest first).
local function assignDoorSlot(lockerId, excludeCid, needSize)
    local used = usedDoorSlots(lockerId, excludeCid)
    local total = Config.lockerWall.totalDoors or 26
    local need = SIZE_RANK[needSize or 's'] or 1

    local free = { {}, {}, {}, {} }
    for i = 1, total do
        if not used[i] then
            local r = slotSizeRank(i)
            free[r][#free[r] + 1] = i
        end
    end

    local prefer = { need }
    for r = need + 1, 4 do prefer[#prefer + 1] = r end
    for r = need - 1, 1, -1 do prefer[#prefer + 1] = r end
    for _, r in ipairs(prefer) do
        local list = free[r]
        if list and #list > 0 then return list[math.random(1, #list)] end
    end

    -- Every slot is taken (shouldn't happen at normal order volume) - reuse one rather
    -- than fail the order outright.
    return math.random(1, total)
end

-- OpenDoors[lockerId] = { cid, orderId, doorSlot } - only one door open per locker point
-- at a time, matching the wall prop's single door-open animation state.
local OpenDoors = {}

local function closeDoor(lockerId)
    local open = OpenDoors[lockerId]
    if not open then return end
    OpenDoors[lockerId] = nil
    TriggerClientEvent('as-postalprime:client:syncDoor', -1, lockerId, open.doorSlot, false)
end

-- ─── Keypad lockout ───────────────────────────────────────────────────────────
-- Wrong codes are counted per player and per locker (Config.security.collect). Hitting the limit locks the keypad for
-- that player - doubling each time they trip it again - or for the whole locker, and fires
-- 'as-postalprime:suspiciousCollect' (source, citizenid, lockerId, fails) for police alerts and the like.

local PlayerFails = {}   -- [cid] = { count, locks, lockedUntil }
local LockerFails = {}   -- [lockerId] = { count, windowStart, lockedUntil }

local function secLeft(untilTs) return math.max(1, math.ceil(untilTs - os.time())) end

local function lockoutSeconds(cid, lockerId)
    local now = os.time()
    local p = PlayerFails[cid]
    if p and p.lockedUntil and p.lockedUntil > now then return secLeft(p.lockedUntil) end
    local l = LockerFails[lockerId]
    if l and l.lockedUntil and l.lockedUntil > now then return secLeft(l.lockedUntil) end
    return nil
end

-- Returns the lockout length in seconds if this wrong code tripped one, otherwise nil.
local function recordWrongCode(source, cid, lockerId)
    local c = (Config.security and Config.security.collect) or {}
    local now = os.time()
    local tripped

    local p = PlayerFails[cid] or { count = 0, locks = 0 }
    PlayerFails[cid] = p
    p.count = p.count + 1
    if p.count >= (c.maxAttempts or 5) then
        p.locks = p.locks + 1
        local secs = math.floor(math.min(c.maxLockSeconds or 900, (c.lockSeconds or 60) * (2 ^ (p.locks - 1))))
        p.lockedUntil = now + secs
        p.count = 0
        tripped = secs
        PPLog.log('lockout', source, ('keypad locked for %ds after repeated wrong codes at %s'):format(secs, lockerId), { locker = lockerId, citizen = cid })
        TriggerEvent('as-postalprime:suspiciousCollect', source, cid, lockerId, p.locks)
    end

    local l = LockerFails[lockerId] or { count = 0, windowStart = now }
    LockerFails[lockerId] = l
    if now - l.windowStart > (c.lockerWindowSeconds or 60) then l.count, l.windowStart = 0, now end
    l.count = l.count + 1
    if l.count >= (c.lockerMaxAttempts or 20) then
        l.lockedUntil = now + (c.lockerLockSeconds or 120)
        l.count, l.windowStart = 0, now
        tripped = tripped or (c.lockerLockSeconds or 120)
        PPLog.log('lockout', source, ('locker %s keypad locked for %ds (too many wrong codes)'):format(lockerId, c.lockerLockSeconds or 120), { locker = lockerId })
    end
    return tripped
end

local function clearFails(cid)
    PlayerFails[cid] = nil
end

lib.callback.register('as-postalprime:collect', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    if type(data) ~= 'table' then return { ok = false, error = T('err.badRequest') } end

    local locked = lockoutSeconds(cid, tostring(data.lockerId))
    if locked then return { ok = false, error = T('err.lockedOut', locked) } end

    local pd = PPStore.getPlayer(cid)
    local list = eachOrder(pd)
    if #list == 0 then return { ok = false, error = T('err.noOrderWaiting') } end

    -- The player can have a shop order and parcels waiting at once: pick the one that is ready for a
    -- locker, is at THIS locker and matches the code.
    local ready, homeReady = {}, false
    for _, o in ipairs(list) do
        if o.ready and not o.collected and not o.expired then
            if o.delivery == 'home' then homeReady = true else ready[#ready + 1] = o end
        end
    end
    if #ready == 0 then
        if homeReady then return { ok = false, error = T('err.homeDelivered') } end
        return { ok = false, error = T('err.stillPreparing') }
    end
    local here = {}
    for _, o in ipairs(ready) do
        if o.lockerId == data.lockerId then here[#here + 1] = o end
    end
    if #here == 0 then return { ok = false, error = T('err.wrongLocker') } end

    local entered = tostring(data.code or ''):gsub('%D', '')
    local order
    if entered ~= '' then
        for _, o in ipairs(here) do
            if entered == o.code then order = o break end
        end
    end
    if not order then
        local tripped = recordWrongCode(source, cid, data.lockerId)
        if tripped then return { ok = false, error = T('err.lockedOut', tripped) } end
        return { ok = false, error = T('err.wrongCode') }
    end
    clearFails(cid)

    if OpenDoors[data.lockerId] then
        return { ok = false, error = T('err.doorOpen') }
    end

    if not order.doorSlot then
        order.boxSize = orderBoxSize(order)
        order.doorSlot = assignDoorSlot(order.lockerId, cid, order.boxSize)
        PPStore.markDirty(cid)
    end

    OpenDoors[data.lockerId] = { cid = cid, orderId = order.id, doorSlot = order.doorSlot }
    TriggerClientEvent('as-postalprime:client:syncDoor', -1, data.lockerId, order.doorSlot, true)

    SetTimeout(Config.lockerWall.autoCloseMs or 45000, function()
        local open = OpenDoors[data.lockerId]
        if open and open.orderId == order.id then
            closeDoor(data.lockerId)
        end
    end)

    return { ok = true, doorSlot = order.doorSlot }
end)

-- Random "arrived damaged" event (Config.returns.damagedChance): the items are fine, the customer gets a goodwill
-- refund of damagedRefundPct of what they paid for the items. Only ever on paid shop orders.
function PP.rollDamaged(source, order)
    local r = Config.returns
    if not r or (r.damagedChance or 0) <= 0 or order.parcel or order.takenBy then return end
    local paid = PPDeals.round2((order.itemsTotal or 0) - (order.discount or 0))
    if paid <= 0 or math.random(100) > r.damagedChance then return end
    local refund = PPDeals.round2(paid * (r.damagedRefundPct or 25) / 100)
    if refund <= 0 then return end
    order.damaged = refund
    PP.pay(source, refund)
    PPLog.log('damaged', source, ('parcel %s arrived damaged, $%s goodwill refund'):format(order.id, refund), { order = order.id })
    PP.notify(source, T('notif.damaged.title'), T('notif.damaged.body', refund))
end

-- Final hand-off: fired once the player walks up to the open door's parcel offset and
-- interacts with the "Take Parcel" zone client-side.
RegisterNetEvent('as-postalprime:takeBox')
AddEventHandler('as-postalprime:takeBox', function(lockerId, doorSlot)
    local source = source
    local cid = track(source)
    if not cid then return end

    local open = OpenDoors[lockerId]
    if not open or open.cid ~= cid or open.doorSlot ~= doorSlot then
        return -- stale click, door already closed/reassigned
    end

    local pd = PPStore.getPlayer(cid)
    local order = findOrderById(pd, open.orderId)
    if not order or order.lockerId ~= lockerId or order.collected or order.expired then
        closeDoor(lockerId)
        return
    end

    if (Config.lockerWall.giveBoxItem ~= false) then
        -- One sealed box, matching whichever size door/box it was assigned. The box holds the real
        -- items in its own metadata; PPBridge.registerUsable('pp_parcel_' .. size, ...) below unpacks
        -- them the moment the player uses it.
        local boxItem = 'pp_parcel_' .. (order.boxSize or orderBoxSize(order))
        PPBridge.addItem(source, boxItem, 1, { orderId = order.id, items = order.items })
    else
        for _, it in ipairs(order.items) do
            local entry = findCatalogItem(it.id)
            local itemName = entry and entry.item or it.item or it.id
            PPBridge.addItem(source, itemName, it.qty, it.metadata)
        end
    end

    order.collected = true
    order.collectedAt = os.time()
    removeOrder(pd, order)
    pushHistory(pd, order)
    PPStore.savePlayer(cid)
    closeDoor(lockerId)
    PP.rollDamaged(source, order)
    PP.onCollected(cid, order)

    if order.parcel then TriggerEvent('as-postalprime:parcelCollected', cid, order.parcelRef, source) end

    TriggerClientEvent('as-postalprime:client:updated', source)
    if not hasReadyLockerOrder(pd) then TriggerClientEvent('as-postalprime:client:orderReady:clear', source) end
    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.orderCollected'), type = 'success',
    })
    PP.notifyOrder(source, order, T('notif.collected.title'),
        T('notif.collected.body', order.lockerLabel))
end)

-- Opening a pp_parcel_s/m/l/xl box: unpack the real items from its metadata, remove the (one) box
-- item itself, then let the player know. Registered for all four sizes since they all behave the
-- same way - only the box's own weight/label differs.
local function openParcelBox(source, meta)
    if type(meta) ~= 'table' or type(meta.items) ~= 'table' then
        print(('[as-postalprime] a pp_parcel box was used by source %s with no/garbled metadata - nothing to unpack (were older boxes given out before giveBoxItem was turned on?).'):format(tostring(source)))
        return
    end
    for _, it in ipairs(meta.items) do
        local entry = findCatalogItem(it.id)
        local itemName = entry and entry.item or it.item or it.id
        PPBridge.addItem(source, itemName, it.qty, it.metadata)
    end
    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.parcelOpened'), type = 'success',
    })
end

for _, size in ipairs({ 's', 'm', 'l', 'xl' }) do
    PPBridge.registerUsable('pp_parcel_' .. size, function(source, meta, removeSelf)
        openParcelBox(source, meta)
        -- Removes exactly the copy that was used, not just any pp_parcel_<size> the player is
        -- carrying - important if they're holding two boxes of the same size with different contents.
        if removeSelf then removeSelf() else PPBridge.removeItem(source, 'pp_parcel_' .. size, 1) end
    end)
end
