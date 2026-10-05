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

    local entered = (tostring(data.code or ''):gsub('%D', ''))
    local pd = PPStore.getPlayer(cid)

    -- Find the order this code is for: one of the caller's own orders that is ready at THIS locker. When there is
    -- none, `reason` says why (shown to the player).
    local order, reason
    local list = eachOrder(pd)
    if #list == 0 then
        reason = 'err.noOrderWaiting'
    else
        -- The player can have a shop order and parcels waiting at once: pick the one that is ready for a
        -- locker, is at THIS locker and matches the code.
        local ready, homeReady = {}, false
        for _, o in ipairs(list) do
            if o.ready and not o.collected and not o.expired then
                if o.delivery == 'home' then homeReady = true else ready[#ready + 1] = o end
            end
        end
        if #ready == 0 then
            reason = homeReady and 'err.homeDelivered' or 'err.stillPreparing'
        else
            local here = {}
            for _, o in ipairs(ready) do
                if o.lockerId == data.lockerId then here[#here + 1] = o end
            end
            if #here == 0 then
                reason = 'err.wrongLocker'
            elseif entered ~= '' then
                for _, o in ipairs(here) do
                    if entered == o.code then order = o break end
                end
            end
        end
    end

    if not order then
        -- A rented locker's code (anyone holding it can use it) opens that rental's storage instead.
        local rental = PPRentals and PPRentals.match(data.lockerId, entered)
        if rental then
            clearFails(cid)
            PPRentals.open(source, rental)
            return { ok = true, rental = true }
        end
        -- With rentals at this locker a code could belong to somebody else's rental, so EVERY failed attempt counts and
        -- the answer never says why (it would hint at what exists).
        local rentalsHere = PPRentals and PPRentals.hasAt(data.lockerId)
        if reason and not (rentalsHere and entered ~= '') then return { ok = false, error = T(reason) } end
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

function PP.cantCarry(source)
    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.cantCarry'), type = 'error',
    })
end

-- Random "arrived damaged" event (Config.returns.damagedChance): the items are fine, the customer gets a goodwill
-- refund of damagedRefundPct of what they paid for the items. Only ever on paid shop orders.
function PP.rollDamaged(source, order)
    local r = Config.returns
    if not r or (r.damagedChance or 0) <= 0 or order.parcel or order.takenBy then return end
    local paid = PP.itemsPaid(order)
    if paid <= 0 or math.random(100) > r.damagedChance then return end
    local refund = PPDeals.round2(paid * (r.damagedRefundPct or 25) / 100)
    if refund <= 0 then return end
    order.damaged = refund
    PP.pay(source, refund)
    PPStats.bump('damaged', 1)
    PPStats.bump('refunded', refund)
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

    -- A full inventory must never eat an order: check first, and leave the door open so they can try again.
    local useBox = Config.lockerWall.giveBoxItem ~= false and PPBridge.supportsMetadata()
    local boxItem = useBox and ('pp_parcel_' .. (order.boxSize or orderBoxSize(order))) or nil
    if useBox then
        if not PPBridge.canCarry(source, boxItem, 1) then return PP.cantCarry(source) end
    else
        for _, it in ipairs(order.items) do
            local entry = findCatalogItem(it.id)
            if not PPBridge.canCarry(source, entry and entry.item or it.item or it.id, it.qty) then return PP.cantCarry(source) end
        end
    end

    if useBox then
        -- One sealed box, matching whichever size door/box it was assigned. The box holds the real
        -- items in its own metadata; PPBridge.registerUsable('pp_parcel_' .. size, ...) below unpacks
        -- them the moment the player uses it.
        if not PPBridge.addItem(source, boxItem, 1, { orderId = order.id, items = order.items }) then return PP.cantCarry(source) end
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
-- Opens a sealed parcel as one all-or-nothing step so a parcel can never be lost. Two orders are tried:
--   A. (preferred) add every item while the box is still in its slot, then remove the box from that slot. If anything
--      fails the added items are taken back and the box was never touched.
--   B. (when A doesn't fit - a full inventory by weight or by slots, where the box's own slot/weight is what is in the
--      way) take the box out FIRST, then add every item; if that fails too, take the items back and put the box back
--      with its contents.
-- ox_inventory acts on the used slot right after the export returns (it consumes the box unless the item is defined with
-- consume = 0). After a plain success the box is already gone from that slot, so the handler just returns. After order B
-- that slot may hold one of the new items, and after a failure the box must stay - there the handler returns false, which
-- cancels the use, so the inventory consumes nothing.
-- Everything is reported to the player (toast) and to the server console (the item and the reason).
local function tryAdd(source, contents)
    local added, failed = {}, nil
    for _, c in ipairs(contents) do
        if not PPBridge.addItem(source, c.name, c.qty, c.metadata) then failed = c break end
        added[#added + 1] = c
    end
    return added, failed
end

local function takeBack(source, added)
    for _, c in ipairs(added) do PPBridge.removeItem(source, c.name, c.qty) end
end

local function openParcelBox(source, meta, boxItem, removeBox)
    if type(meta) ~= 'table' or type(meta.items) ~= 'table' or #meta.items == 0 then
        print(('[as-postalprime] a %s was used by source %s but has no contents in its metadata, so there is nothing to unpack (a box given out before giveBoxItem was turned on, or the inventory dropped its metadata).'):format(boxItem, tostring(source)))
        TriggerClientEvent('as-postalprime:toast', source, { title = T('app.name'), description = T('toast.parcelEmpty'), type = 'error' })
        return false
    end

    local contents = {}
    for _, it in ipairs(meta.items) do
        local entry = findCatalogItem(it.id)
        contents[#contents + 1] = { name = entry and entry.item or it.item or it.id, qty = tonumber(it.qty) or 1, metadata = it.metadata }
    end

    -- A: contents first, box still in place.
    local added, failed = tryAdd(source, contents)
    if not failed then
        if removeBox() then
            TriggerClientEvent('as-postalprime:toast', source, { title = T('app.name'), description = T('toast.parcelOpened'), type = 'success' })
            print(('[as-postalprime] opened %s for source %s (%d item(s))'):format(boxItem, tostring(source), #added))
            return true
        end
        takeBack(source, added) -- never hand over the contents and keep the box too
        print(('[as-postalprime] could not take the %s out of source %s\'s inventory, so it was not opened.'):format(boxItem, tostring(source)))
        return false
    end
    takeBack(source, added)

    -- B: the contents don't fit with the box in the way - take the box out first.
    if not removeBox() then
        print(('[as-postalprime] could not unpack %s for source %s: adding %dx "%s" failed and the box could not be removed to make room.'):format(boxItem, tostring(source), failed.qty, tostring(failed.name)))
        PP.cantCarry(source)
        return false
    end
    local added2, failed2 = tryAdd(source, contents)
    if not failed2 then
        print(('[as-postalprime] opened %s for source %s after freeing the box\'s own slot/weight (the inventory is nearly full)'):format(boxItem, tostring(source)))
        TriggerClientEvent('as-postalprime:toast', source, { title = T('app.name'), description = T('toast.parcelOpened'), type = 'success' })
        return 'freed'
    end

    -- Still doesn't fit: undo everything and give the player their box back.
    takeBack(source, added2)
    local restored = PPBridge.addItem(source, boxItem, 1, meta)
    print(('[as-postalprime] could not unpack %s for source %s: adding %dx "%s" failed (%s). %s'):format(
        boxItem, tostring(source), failed2.qty, tostring(failed2.name),
        PPBridge.canCarry(source, failed2.name, failed2.qty)
            and 'the inventory refused it - is that item defined in your inventory config?'
            or 'the inventory is too full or too heavy',
        restored and 'The parcel was put back in the inventory.' or 'WARNING: the parcel could not be put back - restore it for this player by hand.'))
    PP.cantCarry(source)
    return false
end

for _, size in ipairs({ 's', 'm', 'l', 'xl' }) do
    local boxItem = 'pp_parcel_' .. size
    PPBridge.registerUsable(boxItem, function(source, meta, removeSelf)
        -- Removes exactly the copy that was used, not just any pp_parcel_<size> the player is carrying - important if
        -- they're holding two boxes of the same size with different contents.
        local function removeBox()
            if removeSelf then return removeSelf() end
            return PPBridge.removeItem(source, boxItem, 1)
        end
        local ok, result = pcall(openParcelBox, source, meta, boxItem, removeBox)
        if not ok then
            print(('[as-postalprime] error while opening %s for source %s: %s'):format(boxItem, tostring(source), tostring(result)))
            PP.cantCarry(source)
            return false
        end
        if result == true then return end                                   -- plain success: same as always
        if result == 'freed' then
            -- the box's slot now holds a new item; stop the inventory consuming it (unless it never consumes: consume = 0)
            if PPBridge.itemConsumes(boxItem) then return false end
            return
        end
        return false                                                        -- could not open: leave the box alone
    end)
end
