-- Pushes a real phone notification (banner + lockscreen) via sd-phone's own notification
-- center, not just the app's in-UI badge. Safe no-op if sd-phone's export isn't there for
-- whatever reason, so a bad build never hard-errors the rest of the resource.
local function pushPhoneNotification(source, title, body)
    local ok, err = pcall(function()
        exports['sd-phone']:notify(source, {
            app   = Config.app.identifier,
            appId = Config.app.identifier,
            title = title,
            body  = body,
            time  = 'now',
        })
    end)
    if not ok then
        print(('[as-postalprime] failed to push phone notification: %s'):format(tostring(err)))
    end
end

local onlineSources = {}

local function track(source)
    local cid = PPBridge.getIdentifier(source)
    if cid then onlineSources[cid] = source end
    return cid
end

AddEventHandler('playerDropped', function()
    local source = source
    for cid, src in pairs(onlineSources) do
        if src == source then onlineSources[cid] = nil end
    end
end)

local function findCatalogItem(id)
    for _, entry in ipairs(Config.catalog) do
        if entry.id == id then return entry end
    end
    return nil
end

local function findLocker(id)
    for _, l in ipairs(Config.lockers) do
        if l.id == id then return l end
    end
    return nil
end

local function newCode()
    return ('%06d'):format(math.random(0, 999999))
end

local function newOrderId()
    return ('ord_%08x_%04x'):format(os.time(), math.random(0, 0xffff))
end

-- Merge config-seeded rating/review-count with real submitted reviews for this item.
local function ratingFor(itemId, baseRating, baseReviews)
    local bucket = PPStore.reviews[itemId]
    if not bucket then return baseRating, baseReviews end
    local sum, count = 0, 0
    for _, r in pairs(bucket) do
        sum = sum + (tonumber(r.rating) or 0)
        count = count + 1
    end
    if count == 0 then return baseRating, baseReviews end
    return (sum / count), count
end

local function hasPurchased(playerData, itemId)
    for _, o in ipairs(playerData.history) do
        if o.collected then
            for _, it in ipairs(o.items) do
                if it.id == itemId then return true end
            end
        end
    end
    return false
end

local function hasReviewed(cid, itemId)
    return PPStore.reviews[itemId] and PPStore.reviews[itemId][cid] ~= nil
end

local function isPlusActive(pd)
    return pd.plus ~= nil and pd.plus.expiresAt ~= nil and pd.plus.expiresAt > os.time()
end

local function sanitizeOrder(order, cid)
    local items = {}
    for _, it in ipairs(order.items) do
        items[#items + 1] = {
            id = it.id, label = it.label, icon = it.icon, price = it.price, qty = it.qty,
            reviewed = order.collected and hasReviewed(cid, it.id) or false,
        }
    end
    return {
        id = order.id,
        items = items,
        lockerId = order.lockerId,
        lockerLabel = order.lockerLabel,
        itemsTotal = order.itemsTotal or order.total,
        deliveryFee = order.deliveryFee or 0,
        total = order.total,
        placedAt = order.placedAt * 1000,
        readyAt = order.readyAt * 1000,
        ready = order.ready,
        collected = order.collected,
        expired = order.expired or false,
        cancelled = order.cancelled or false,
        -- Only ever hand out the code while it's actually usable - never after collection/expiry.
        code = (order.ready and not order.collected and not order.expired) and order.code or nil,
        giftedBy = order.giftedBy,
    }
end

local function catalogPayload()
    local out = {}
    for _, entry in ipairs(Config.catalog) do
        local rating, reviews = ratingFor(entry.id, entry.baseRating, entry.baseReviews)
        out[#out + 1] = {
            id = entry.id, label = entry.label, price = entry.price, icon = entry.icon, cat = entry.cat,
            rating = rating, reviews = reviews,
            -- nil (omitted) means unlimited - the app only shows a stock note/blocks Add to Cart
            -- when this is an actual number.
            stock = PPStore.getStock(entry.id),
        }
    end
    return out
end

-- Finds an ONLINE player by their in-character name (case-insensitive) for gift orders. Not
-- purchase history or anything identity-sensitive - just a live name match among connected
-- players, same as calling out someone's name in-game.
local function findOnlinePlayerByName(name, excludeSource)
    local wanted = name:lower()
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src and src ~= excludeSource then
            local ok, charName = pcall(PPBridge.getCharacterName, src)
            if ok and charName and charName:lower() == wanted then
                return src
            end
        end
    end
    return nil
end

-- How many doors are currently occupied (ready, uncollected orders) at each locker, across every
-- player - used to show a rough "how busy is this locker" indicator before checkout.
local function lockerActiveCounts()
    local counts = {}
    for _, pd in pairs(PPStore.players) do
        local o = pd.active
        if o and o.ready and not o.collected and not o.expired and o.lockerId then
            counts[o.lockerId] = (counts[o.lockerId] or 0) + 1
        end
    end
    return counts
end

local function lockerPayload()
    local counts = lockerActiveCounts()
    local total = Config.lockerWall.totalDoors or 26
    local out = {}
    for _, l in ipairs(Config.lockers) do
        out[#out + 1] = {
            id = l.id, label = l.label,
            coords = { x = l.coords.x, y = l.coords.y, z = l.coords.z },
            doorsUsed = counts[l.id] or 0,
            doorsTotal = total,
        }
    end
    return out
end

lib.callback.register('as-postalprime:getState', function(source)
    local cid = track(source)
    if not cid then return { catalog = catalogPayload(), categories = Config.categories, lockers = lockerPayload(), orders = {} } end

    local pd = PPStore.getPlayer(cid)
    local orders = {}
    if pd.active then orders[#orders + 1] = sanitizeOrder(pd.active, cid) end
    for _, o in ipairs(pd.history) do
        orders[#orders + 1] = sanitizeOrder(o, cid)
    end

    local wishlist = {}
    for itemId in pairs(pd.wishlist or {}) do wishlist[#wishlist + 1] = itemId end

    return {
        catalog = catalogPayload(),
        categories = Config.categories,
        lockers = lockerPayload(),
        orders = orders,
        wishlist = wishlist,
        playerName = PPBridge.getCharacterName(source),
        plus = {
            active = isPlusActive(pd),
            expiresAt = (pd.plus and pd.plus.expiresAt) and (pd.plus.expiresAt * 1000) or nil,
        },
        plusConfig = {
            price = Config.plus.price,
            durationDays = Config.plus.durationDays,
            deliveryFee = Config.plus.deliveryFee,
        },
    }
end)

-- Wishlist is just a set of item ids saved on the player's own row - separate from the cart, and
-- never charges/reserves anything.
lib.callback.register('as-postalprime:toggleWishlist', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end
    if type(data) ~= 'table' or not data.itemId then return { ok = false, error = 'Bad request' } end
    if not findCatalogItem(data.itemId) then return { ok = false, error = 'Unknown item' } end

    local pd = PPStore.getPlayer(cid)
    pd.wishlist = pd.wishlist or {}
    if pd.wishlist[data.itemId] then
        pd.wishlist[data.itemId] = nil
    else
        pd.wishlist[data.itemId] = true
    end
    PPStore.savePlayer(cid)

    local wishlist = {}
    for itemId in pairs(pd.wishlist) do wishlist[#wishlist + 1] = itemId end
    return { ok = true, wishlist = wishlist }
end)

local function chargePlayer(source, price)
    if price <= 0 then return true end
    if Config.payment.mode == 'item' then
        if PPBridge.getItemCount(source, Config.payment.cashItem) < price then return false end
        return PPBridge.removeItem(source, Config.payment.cashItem, price)
    end
    local balance = PPBridge.getBalance(source, Config.payment.account)
    if balance ~= nil and balance < price then return false end
    return PPBridge.removeMoney(source, Config.payment.account, price)
end

local function refundPlayer(source, price)
    if price <= 0 then return end
    if Config.payment.mode == 'item' then
        PPBridge.addItem(source, Config.payment.cashItem, price)
    else
        PPBridge.addMoney(source, Config.payment.account, price)
    end
end

lib.callback.register('as-postalprime:checkout', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end
    if type(data) ~= 'table' or type(data.items) ~= 'table' or not data.lockerId then
        return { ok = false, error = 'Bad request' }
    end

    -- Gift orders: the order gets assigned to the RECIPIENT's active slot (they collect it,
    -- they get the ready/expiry notifications), but the buyer's card is the one charged. The
    -- recipient just needs to be an online player with that exact in-character name.
    local giftSrc, giftCid, giftName = nil, nil, nil
    if type(data.giftTo) == 'string' and data.giftTo:gsub('%s+', '') ~= '' then
        giftSrc = findOnlinePlayerByName(data.giftTo, source)
        if not giftSrc then
            return { ok = false, error = ('Couldn\'t find an online player named "%s"'):format(data.giftTo) }
        end
        giftCid = track(giftSrc)
        if not giftCid then return { ok = false, error = 'That player isn\'t available right now' } end
        giftName = PPBridge.getCharacterName(giftSrc)
    end

    local recipientCid = giftCid or cid
    local buyerPd = PPStore.getPlayer(cid)
    local recipientPd = PPStore.getPlayer(recipientCid)

    if recipientPd.active then
        return { ok = false, error = giftCid
            and (giftName .. ' already has an order on the way - they need to collect or wait for it to expire first.')
            or 'You already have an order on the way. Collect or wait for it to expire first.' }
    end

    local locker = findLocker(data.lockerId)
    if not locker then return { ok = false, error = 'Pick a valid locker' } end

    local items, itemsTotal = {}, 0
    for itemId, qty in pairs(data.items) do
        qty = tonumber(qty) or 0
        if qty > 0 then
            local entry = findCatalogItem(itemId)
            if not entry then return { ok = false, error = 'Cart contains an item that no longer exists' } end
            qty = math.floor(qty)

            local stock = PPStore.getStock(entry.id)
            if stock ~= nil and stock < qty then
                return { ok = false, error = stock <= 0
                    and (entry.label .. ' is out of stock')
                    or ('Only ' .. stock .. ' left of ' .. entry.label) }
            end

            items[#items + 1] = { id = entry.id, label = entry.label, icon = entry.icon, price = entry.price, qty = qty }
            itemsTotal = itemsTotal + entry.price * qty
        end
    end

    if #items == 0 then return { ok = false, error = 'Your cart is empty' } end

    -- Plus (free delivery / faster prep) is the RECIPIENT's benefit on a gift order, same as any
    -- other perk tied to who's actually receiving and collecting it.
    local plusActive = isPlusActive(recipientPd)
    local deliveryFee = plusActive and 0 or (Config.plus.deliveryFee or 0)
    local total = itemsTotal + deliveryFee
    local prepSeconds = plusActive and (Config.plus.prepSeconds or Config.order.prepSeconds) or (Config.order.prepSeconds or 180)

    if not chargePlayer(source, total) then
        return { ok = false, error = 'Not enough cash' }
    end

    -- Stock was only checked above, not spent yet - spend it now that payment succeeded. Checked
    -- again per-item in case something else sold the last unit between the check and here.
    for _, it in ipairs(items) do
        if not PPStore.trySpendStock(it.id, it.qty) then
            refundPlayer(source, total)
            return { ok = false, error = it.label .. ' just sold out - you have not been charged.' }
        end
    end

    local now = os.time()
    local order = {
        id = newOrderId(),
        items = items,
        lockerId = locker.id,
        lockerLabel = locker.label,
        itemsTotal = itemsTotal,
        deliveryFee = deliveryFee,
        total = total,
        placedAt = now,
        readyAt = now + prepSeconds,
        expiresAt = now + prepSeconds + (Config.order.expireSecondsAfterReady or 1800),
        ready = false,
        collected = false,
        expired = false,
        code = newCode(),
        giftedBy = giftCid and PPBridge.getCharacterName(source) or nil,
    }
    recipientPd.active = order
    PPStore.savePlayer(recipientCid)

    -- Readiness itself is flipped by the background sweep below, not a one-shot timer here -
    -- a timer scheduled only at checkout is lost forever if the resource/server restarts before
    -- it fires, leaving the order stuck on "Preparing". The sweep re-checks readyAt against the
    -- clock every few seconds regardless of restarts, so it always catches up.

    if giftCid then
        pushPhoneNotification(giftSrc, 'You got a gift order!',
            ('Someone sent you an order - it\'ll be ready at %s.'):format(locker.label))
        TriggerClientEvent('as-postalprime:client:updated', giftSrc)
    end

    return { ok = true, gifted = giftCid ~= nil, giftedTo = giftName, orders = (function()
        -- The buyer's OWN order list is unaffected by a gift (it's not their order) - always
        -- return the buyer's real list, not the recipient's.
        local orders = {}
        if buyerPd.active then orders[#orders + 1] = sanitizeOrder(buyerPd.active, cid) end
        for _, o in ipairs(buyerPd.history) do orders[#orders + 1] = sanitizeOrder(o, cid) end
        return orders
    end)() }
end)

-- Lets a player back out of an order and get a full refund, but only while it's still
-- "Preparing" - once it's ready for pickup (code issued, door assignable) it has to be
-- collected or left to expire like before, same as a real courier already being en route.
lib.callback.register('as-postalprime:cancelOrder', function(source)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end

    local pd = PPStore.getPlayer(cid)
    local order = pd.active
    if not order then return { ok = false, error = 'You have no active order' } end
    if order.ready then
        return { ok = false, error = 'This order is already ready for pickup and can no longer be cancelled - collect it or let it expire.' }
    end

    pd.active = nil
    order.cancelled = true
    pushHistory(pd, order)
    PPStore.savePlayer(cid)

    refundPlayer(source, order.total)

    -- Hand the stock back for anything that was actually spending from a real cap - never for
    -- unlimited items, which would otherwise accidentally start capping them.
    for _, it in ipairs(order.items) do
        if PPStore.getStock(it.id) ~= nil then
            PPStore.restock(it.id, it.qty)
        end
    end

    TriggerClientEvent('as-postalprime:client:updated', source)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Postal Prime', description = 'Order cancelled and refunded.', type = 'success',
    })

    local orders = {}
    if pd.active then orders[#orders + 1] = sanitizeOrder(pd.active, cid) end
    for _, o in ipairs(pd.history) do orders[#orders + 1] = sanitizeOrder(o, cid) end
    return { ok = true, orders = orders }
end)

lib.callback.register('as-postalprime:subscribePlus', function(source)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end

    local pd = PPStore.getPlayer(cid)
    local price = Config.plus.price or 0

    if not chargePlayer(source, price) then
        return { ok = false, error = 'Not enough cash' }
    end

    local now = os.time()
    local durationSeconds = (Config.plus.durationDays or 7) * 86400
    local base = (pd.plus and pd.plus.expiresAt and pd.plus.expiresAt > now) and pd.plus.expiresAt or now
    pd.plus = { expiresAt = base + durationSeconds }
    PPStore.savePlayer(cid)

    return {
        ok = true,
        plus = { active = true, expiresAt = pd.plus.expiresAt * 1000 },
    }
end)

local function pushHistory(pd, order)
    table.insert(pd.history, 1, order)
    local limit = Config.order.historyLimit or 20
    while #pd.history > limit do table.remove(pd.history) end
end

-- ─── Locker wall door assignment ──────────────────────────────────────────────
-- Each Config.lockers point is a physical wall prop with Config.lockerWall.totalDoors
-- individual door slots. An order gets assigned a free slot at its chosen locker the
-- moment it becomes ready, so two players' ready orders at the same locker never fight
-- over the same door.

local function usedDoorSlots(lockerId, excludeCid)
    local used = {}
    for cid, pd in pairs(PPStore.players) do
        local o = pd.active
        if cid ~= excludeCid and o and o.ready and not o.collected and not o.expired
            and o.lockerId == lockerId and o.doorSlot then
            used[o.doorSlot] = true
        end
    end
    return used
end

local function assignDoorSlot(lockerId, excludeCid)
    local used = usedDoorSlots(lockerId, excludeCid)
    local total = Config.lockerWall.totalDoors or 26
    for i = 1, total do
        if not used[i] then return i end
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

lib.callback.register('as-postalprime:collect', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end
    if type(data) ~= 'table' then return { ok = false, error = 'Bad request' } end

    local pd = PPStore.getPlayer(cid)
    local order = pd.active
    if not order then return { ok = false, error = 'You have no order waiting' } end
    if not order.ready then return { ok = false, error = 'Your order is still being prepared' } end
    if order.lockerId ~= data.lockerId then return { ok = false, error = 'That locker doesn\'t have your order - check the app for the right one' } end
    if order.collected or order.expired then return { ok = false, error = 'That order is no longer active' } end

    local entered = tostring(data.code or ''):gsub('%D', '')
    if entered == '' or entered ~= order.code then
        return { ok = false, error = 'Wrong code' }
    end

    if OpenDoors[data.lockerId] then
        return { ok = false, error = "Another locker door here is already open - wait a moment" }
    end

    if not order.doorSlot then
        order.doorSlot = assignDoorSlot(order.lockerId, cid)
        PPStore.savePlayer(cid)
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
    local order = pd.active
    if not order or order.lockerId ~= lockerId or order.collected or order.expired then
        closeDoor(lockerId)
        return
    end

    for _, it in ipairs(order.items) do
        local entry = findCatalogItem(it.id)
        local itemName = entry and entry.item or it.id
        PPBridge.addItem(source, itemName, it.qty)
    end

    order.collected = true
    pd.active = nil
    pushHistory(pd, order)
    PPStore.savePlayer(cid)
    closeDoor(lockerId)

    TriggerClientEvent('as-postalprime:client:updated', source)
    TriggerClientEvent('as-postalprime:client:orderReady:clear', source)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Postal Prime', description = 'Order collected!', type = 'success',
    })
    pushPhoneNotification(source, 'Parcel picked up',
        ('Your order from %s was collected. Thanks for shopping with Postal Prime!'):format(order.lockerLabel))
end)

lib.callback.register('as-postalprime:getReviews', function(source, data)
    local cid = track(source)
    if type(data) ~= 'table' or not data.itemId then return { ok = false, error = 'Bad request' } end
    local entry = findCatalogItem(data.itemId)
    if not entry then return { ok = false, error = 'Unknown item' } end

    local rating, count = ratingFor(entry.id, entry.baseRating, entry.baseReviews)
    local list, mine = {}, nil
    local bucket = PPStore.reviews[entry.id]
    if bucket then
        for reviewCid, r in pairs(bucket) do
            local review = {
                name = r.name, rating = r.rating, title = r.title, body = r.body, createdAt = r.createdAt * 1000,
            }
            if cid and reviewCid == cid then
                mine = review
            else
                list[#list + 1] = review
            end
        end
        table.sort(list, function(a, b) return a.createdAt > b.createdAt end)
    end

    local pd = cid and PPStore.getPlayer(cid) or nil
    local canReview = pd and hasPurchased(pd, entry.id) and not mine or false

    return {
        ok = true,
        rating = rating,
        reviewCount = count,
        mine = mine,
        reviews = list,
        canReview = canReview and true or false,
    }
end)

lib.callback.register('as-postalprime:submitReview', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end
    if type(data) ~= 'table' or not data.itemId then return { ok = false, error = 'Bad request' } end

    local entry = findCatalogItem(data.itemId)
    if not entry then return { ok = false, error = 'Unknown item' } end

    local pd = PPStore.getPlayer(cid)
    if not hasPurchased(pd, entry.id) then
        return { ok = false, error = 'You can only review something you\'ve collected from a locker' }
    end

    local rating = tonumber(data.rating) or 5
    rating = math.max(1, math.min(5, math.floor(rating)))
    local title = tostring(data.title or ''):sub(1, 80)
    local body = tostring(data.body or ''):sub(1, 500)
    if title == '' then title = 'No title' end
    if body == '' then body = '(no written comment)' end

    PPStore.reviews[entry.id] = PPStore.reviews[entry.id] or {}
    PPStore.reviews[entry.id][cid] = {
        name = PPBridge.getCharacterName(source),
        rating = rating, title = title, body = body, createdAt = os.time(),
    }
    PPStore.saveReview(entry.id, cid)

    return { ok = true }
end)

-- Background sweep, every few seconds: flips orders to "ready" once their prep time is up, and
-- expires/refunds ones that sat ready too long uncollected. Driven entirely off the clock
-- (readyAt/expiresAt, both saved to disk at checkout) rather than one-shot timers, so it keeps
-- working correctly even if the resource or server restarts mid-order.
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for cid, pd in pairs(PPStore.players) do
            local order = pd.active
            if order and not order.collected and not order.expired then
                if not order.ready and now >= order.readyAt then
                    order.ready = true
                    PPStore.savePlayer(cid)
                    local src = onlineSources[cid]
                    if src then
                        TriggerClientEvent('as-postalprime:client:updated', src)
                        pushPhoneNotification(src, 'Order ready for pickup',
                            ('Your order is ready at %s. Open the app for your pickup code.'):format(order.lockerLabel))
                        local locker = findLocker(order.lockerId)
                        if locker then
                            TriggerClientEvent('as-postalprime:client:orderReady', src,
                                { x = locker.coords.x, y = locker.coords.y, z = locker.coords.z }, order.lockerLabel)
                        end
                    end
                elseif order.ready and now > order.expiresAt then
                    pd.active = nil
                    order.expired = true
                    pushHistory(pd, order)
                    PPStore.savePlayer(cid)

                    local src = onlineSources[cid]
                    if src then
                        refundPlayer(src, order.total)
                        TriggerClientEvent('as-postalprime:client:updated', src)
                        TriggerClientEvent('as-postalprime:client:orderReady:clear', src)
                        pushPhoneNotification(src, 'Order expired & refunded',
                            ('Your uncollected order at %s expired and was refunded in full.'):format(order.lockerLabel))
                    else
                        -- Player offline when their order expired - refund can't be applied to an
                        -- offline account/inventory for most frameworks. See README "Known limitation".
                        print(('[as-postalprime] order %s for %s expired while offline - could not refund %d automatically'):format(order.id, cid, order.total))
                    end
                end
            end

            -- Plus expiring-soon heads-up: fires once per membership period, within 24h of
            -- expiry. pd.plus is a brand-new table on every subscribe/renew (see subscribePlus),
            -- so notifiedExpiry naturally resets whenever they renew - no separate reset needed.
            if pd.plus and pd.plus.expiresAt then
                local timeLeft = pd.plus.expiresAt - now
                if timeLeft > 0 and timeLeft <= 86400 and not pd.plus.notifiedExpiry then
                    pd.plus.notifiedExpiry = true
                    PPStore.savePlayer(cid)
                    local src = onlineSources[cid]
                    if src then
                        pushPhoneNotification(src, 'Postal Prime Plus expiring soon',
                            'Your membership expires in less than 24 hours. Renew from the You tab to keep free delivery.')
                    end
                end
            end
        end
    end
end)

-- Console-only restock command for items with a Config.catalog `stock` cap: pprestock <itemId> <amount>
RegisterCommand('pprestock', function(source, args)
    if source ~= 0 then
        print('[as-postalprime] pprestock can only be run from the server console.')
        return
    end

    local itemId = args[1]
    local amount = tonumber(args[2])
    if not itemId or not amount or amount <= 0 then
        print('[as-postalprime] Usage: pprestock <itemId> <amount>')
        return
    end

    if not findCatalogItem(itemId) then
        print(('[as-postalprime] Unknown item id "%s" - check config.lua for the correct id.'):format(itemId))
        return
    end

    local total = PPStore.restock(itemId, math.floor(amount))
    print(('[as-postalprime] %s restocked by %d - %d now remaining.'):format(itemId, math.floor(amount), total))
end, true)
