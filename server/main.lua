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

-- Shared with server/courier.lua (loaded after this file).
PP = {}

local onlineSources = {}
local pushHistory -- forward declaration: defined further down, but cancelOrder/checkout use it before that point

local function track(source)
    local cid = PPBridge.getIdentifier(source)
    if cid then onlineSources[cid] = source end
    return cid
end

PP.track = track
PP.notify = pushPhoneNotification
PP.source = function(cid) return onlineSources[cid] end

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

-- The saved cart: { [itemId] = qty }. Kept on the player's own row so it survives closing the app,
-- relogging and restarts. Anything no longer in the catalog is dropped, quantities are clamped.
local function cleanCart(cart)
    local out = {}
    if type(cart) ~= 'table' then return out end
    for itemId, qty in pairs(cart) do
        qty = math.floor(tonumber(qty) or 0)
        if qty > 0 and type(itemId) == 'string' and findCatalogItem(itemId) then
            out[itemId] = math.min(qty, 99)
        end
    end
    return out
end

local function findLocker(id)
    for _, l in ipairs(Config.lockers) do
        if l.id == id then return l end
    end
    return nil
end

-- Extra time a home delivery takes on top of normal prep, from the distance between the depot and the
-- property's front door (Config.home.depot / secondsPer100m / min+maxTravelSeconds).
local function homeTravelSeconds(coords)
    local h = Config.home or {}
    local depot = h.depot
    if not depot or not coords then return 0 end
    local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(depot.x, depot.y, depot.z))
    local secs = (dist / 100.0) * (h.secondsPer100m or 2.0)
    return math.floor(math.max(h.minTravelSeconds or 0, math.min(h.maxTravelSeconds or 300, secs)))
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

-- Every order a player has in flight: their shop order (pd.active) plus any parcels other resources
-- have sent them (pd.parcels). Parcels have their own list so they never stop the player shopping.
local function eachOrder(pd)
    local list = {}
    if pd.active then list[#list + 1] = pd.active end
    for _, o in ipairs(pd.parcels or {}) do list[#list + 1] = o end
    return list
end

PP.eachOrder = eachOrder -- server/courier.lua walks every in-flight order (shop order + parcels)

local function removeOrder(pd, order)
    if pd.active == order then pd.active = nil return end
    for i, o in ipairs(pd.parcels or {}) do
        if o == order then table.remove(pd.parcels, i) return end
    end
end

local function findOrderById(pd, id)
    for _, o in ipairs(eachOrder(pd)) do
        if o.id == id then return o end
    end
end

-- True when the player still has a ready, uncollected locker order (so the map blip should stay).
local function hasReadyLockerOrder(pd)
    for _, o in ipairs(eachOrder(pd)) do
        if o.ready and not o.collected and not o.expired and o.delivery ~= 'home' then return true end
    end
    return false
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
        delivery = order.delivery or 'locker',
        takenBy = order.takenBy,
        -- Player-courier progress while a home order is being handled: 'board' | 'claimed' | 'loaded'.
        courier = order.courier and order.courier.state or nil,
        deliveredBy = order.deliveredBy,
        parcel = order.parcel or nil,
        sender = order.sender,
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

-- The app's order list: the shop order, then parcels, then history.
local function orderList(pd, cid)
    local out = {}
    for _, o in ipairs(eachOrder(pd)) do out[#out + 1] = sanitizeOrder(o, cid) end
    for _, o in ipairs(pd.history) do out[#out + 1] = sanitizeOrder(o, cid) end
    return out
end

-- How many doors are currently occupied (ready, uncollected orders) at each locker, across every
-- player - used to show a rough "how busy is this locker" indicator before checkout.
local function lockerActiveCounts()
    local counts = {}
    for _, pd in pairs(PPStore.players) do
        for _, o in ipairs(eachOrder(pd)) do
            if o.ready and not o.collected and not o.expired and o.lockerId then
                counts[o.lockerId] = (counts[o.lockerId] or 0) + 1
            end
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
    if not cid then return { catalog = catalogPayload(), categories = Config.categories, lockers = lockerPayload(), orders = {}, home = { enabled = false, fee = 0 } } end

    local pd = PPStore.getPlayer(cid)
    local orders = orderList(pd, cid)

    local wishlist = {}
    for itemId in pairs(pd.wishlist or {}) do wishlist[#wishlist + 1] = itemId end

    return {
        catalog = catalogPayload(),
        categories = Config.categories,
        lockers = lockerPayload(),
        orders = orders,
        wishlist = wishlist,
        cart = cleanCart(pd.cart),
        playerName = PPBridge.getCharacterName(source),
        plus = {
            active = isPlusActive(pd),
            expiresAt = (pd.plus and pd.plus.expiresAt) and (pd.plus.expiresAt * 1000) or nil,
        },
        home = {
            enabled = (Config.home and Config.home.enabled and PPHousing.available()) and true or false,
            fee = (Config.home and Config.home.fee) or 0,
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

lib.callback.register('as-postalprime:saveCart', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false } end
    local pd = PPStore.getPlayer(cid)
    pd.cart = cleanCart(data.cart)
    PPStore.savePlayer(cid)
    return { ok = true }
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

-- Courier job uses the same money route as everything else (deposits, refunds, wages).
PP.charge = chargePlayer
PP.pay = refundPlayer

lib.callback.register('as-postalprime:checkout', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end
    local isHome = type(data) == 'table' and data.delivery == 'home'
    if type(data) ~= 'table' or type(data.items) ~= 'table' or (not isHome and not data.lockerId) then
        return { ok = false, error = 'Bad request' }
    end

    -- Home delivery: the property is re-resolved server-side from what THIS character owns/rents/has
    -- keys to, so a modified client can never send a parcel to an address it has no access to.
    local property = nil
    if isHome then
        if not (Config.home and Config.home.enabled) or not PPHousing.available() then
            return { ok = false, error = 'Home delivery isn\'t available right now' }
        end
        if type(data.giftTo) == 'string' and data.giftTo:gsub('%s+', '') ~= '' then
            return { ok = false, error = 'Gift orders can only go to a locker' }
        end
        if type(data.propertyKey) ~= 'string' then
            return { ok = false, error = 'Pick a property to deliver to' }
        end
        property = PPHousing.resolve(cid, data.propertyKey)
        if not property then
            return { ok = false, error = 'You don\'t have access to that property' }
        end
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

    local locker = nil
    if not isHome then
        locker = findLocker(data.lockerId)
        if not locker then return { ok = false, error = 'Pick a valid locker' } end
    end

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
    -- One delivery charge: home delivery uses its own fee INSTEAD of the normal locker delivery fee.
    local deliveryFee = plusActive and 0 or (isHome and (Config.home.fee or 0) or (Config.plus.deliveryFee or 0))
    local total = itemsTotal + deliveryFee
    local prepSeconds = plusActive and (Config.plus.prepSeconds or Config.order.prepSeconds) or (Config.order.prepSeconds or 180)
    if isHome then prepSeconds = prepSeconds + homeTravelSeconds(property.coords) end

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
        lockerId = isHome and ('home:' .. property.key) or locker.id,
        lockerLabel = isHome and ('Home - ' .. property.label) or locker.label,
        delivery = isHome and 'home' or 'locker',
        homeProperty = isHome and property or nil,
        itemsTotal = itemsTotal,
        deliveryFee = deliveryFee,
        total = total,
        placedAt = now,
        readyAt = now + prepSeconds,
        expiresAt = (not isHome) and (now + prepSeconds + (Config.order.expireSecondsAfterReady or 1800)) or nil,
        ready = false,
        collected = false,
        expired = false,
        code = newCode(),
        giftedBy = giftCid and PPBridge.getCharacterName(source) or nil,
    }
    recipientPd.active = order
    buyerPd.cart = nil -- the cart was just checked out
    PPStore.savePlayer(recipientCid)
    if cid ~= recipientCid then PPStore.savePlayer(cid) end

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
        return orderList(buyerPd, cid)
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
    if order.courier and order.courier.state ~= 'board' then
        return { ok = false, error = 'A courier is already handling this order and it can no longer be cancelled.' }
    end

    pd.active = nil
    order.courier = nil
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
    TriggerClientEvent('as-postalprime:toast', source, {
        title = 'Postal Prime', description = 'Order cancelled and refunded.', type = 'success',
    })

    return { ok = true, orders = orderList(pd, cid) }
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

function pushHistory(pd, order)
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

lib.callback.register('as-postalprime:collect', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = 'Not available' } end
    if type(data) ~= 'table' then return { ok = false, error = 'Bad request' } end

    local pd = PPStore.getPlayer(cid)
    local list = eachOrder(pd)
    if #list == 0 then return { ok = false, error = 'You have no order waiting' } end

    -- The player can have a shop order and parcels waiting at once: pick the one that is ready for a
    -- locker, is at THIS locker and matches the code.
    local ready, homeReady = {}, false
    for _, o in ipairs(list) do
        if o.ready and not o.collected and not o.expired then
            if o.delivery == 'home' then homeReady = true else ready[#ready + 1] = o end
        end
    end
    if #ready == 0 then
        if homeReady then return { ok = false, error = 'This order is being delivered to your home - look for the parcel at your front door' } end
        return { ok = false, error = 'Your order is still being prepared' }
    end
    local here = {}
    for _, o in ipairs(ready) do
        if o.lockerId == data.lockerId then here[#here + 1] = o end
    end
    if #here == 0 then return { ok = false, error = 'That locker doesn\'t have your order - check the app for the right one' } end

    local entered = tostring(data.code or ''):gsub('%D', '')
    local order
    if entered ~= '' then
        for _, o in ipairs(here) do
            if entered == o.code then order = o break end
        end
    end
    if not order then return { ok = false, error = 'Wrong code' } end

    if OpenDoors[data.lockerId] then
        return { ok = false, error = "Another locker door here is already open - wait a moment" }
    end

    if not order.doorSlot then
        order.boxSize = orderBoxSize(order)
        order.doorSlot = assignDoorSlot(order.lockerId, cid, order.boxSize)
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
    local order = findOrderById(pd, open.orderId)
    if not order or order.lockerId ~= lockerId or order.collected or order.expired then
        closeDoor(lockerId)
        return
    end

    for _, it in ipairs(order.items) do
        local entry = findCatalogItem(it.id)
        local itemName = entry and entry.item or it.item or it.id
        PPBridge.addItem(source, itemName, it.qty, it.metadata)
    end

    order.collected = true
    removeOrder(pd, order)
    pushHistory(pd, order)
    PPStore.savePlayer(cid)
    closeDoor(lockerId)

    if order.parcel then TriggerEvent('as-postalprime:parcelCollected', cid, order.parcelRef, source) end

    TriggerClientEvent('as-postalprime:client:updated', source)
    if not hasReadyLockerOrder(pd) then TriggerClientEvent('as-postalprime:client:orderReady:clear', source) end
    TriggerClientEvent('as-postalprime:toast', source, {
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

-- ─── Home delivery ────────────────────────────────────────────────────────────
-- A delivered home order is just an active order with delivery == 'home' and ready == true, so the
-- parcels are derived from the saved player data - nothing extra to persist, and they survive
-- restarts. They stay until somebody takes them (no expiry).

function homeParcelPayload(order)
    local hp = order.homeProperty
    return {
        orderId = order.id,
        model = 'asparcel_' .. (order.boxSize or 'm'),
        coords = hp.coords,
        label = hp.label,
    }
end

local function homeParcels()
    local out = {}
    for _, pd in pairs(PPStore.players) do
        local o = pd.active
        if o and o.delivery == 'home' and o.ready and not o.collected and not o.expired and o.homeProperty then
            out[#out + 1] = homeParcelPayload(o)
        end
    end
    return out
end

-- The dropdown of places this character can have a parcel delivered to.
lib.callback.register('as-postalprime:getProperties', function(source)
    local cid = track(source)
    if not cid or not (Config.home and Config.home.enabled) then return {} end
    local out = {}
    for _, p in ipairs(PPHousing.list(cid)) do
        out[#out + 1] = { key = p.key, label = p.label, address = p.address }
    end
    return out
end)

-- Puts the parcel at the front door: the order becomes ready/delivered, every client is told, and
-- the customer gets a notification. byName = a player courier delivered it (no van animation);
-- nil = the NPC courier van does it.
function PP.dropHome(cid, order, byName)
    order.ready = true
    order.courier = nil
    order.boxSize = order.boxSize or orderBoxSize(order)
    if byName then order.deliveredBy = byName end
    PPStore.savePlayer(cid)

    local payload = homeParcelPayload(order)
    if byName then payload.noAnim = true end
    TriggerClientEvent('as-postalprime:client:homeDrop', -1, payload)

    local src = onlineSources[cid]
    if src then
        TriggerClientEvent('as-postalprime:client:updated', src)
        pushPhoneNotification(src, 'Your parcel has arrived',
            byName and ('%s delivered your order to %s.'):format(byName, order.homeProperty.label)
                or ('Your Postal Prime courier is dropping your order at %s.'):format(order.homeProperty.label))
        TriggerClientEvent('as-postalprime:client:orderReady', src, order.homeProperty.coords, order.homeProperty.label)
    end
end

-- A locker order becomes ready for pickup: the customer gets their code and a waypoint. byName = a
-- player courier put it in the locker. If a courier was involved (delivered OR fell through) the
-- collection window starts now, not from checkout.
function PP.readyLocker(cid, order, byName)
    local hadCourier = order.courier ~= nil
    order.courier = nil
    order.ready = true
    if byName then order.deliveredBy = byName end
    if hadCourier then order.expiresAt = os.time() + (order.expireSeconds or Config.order.expireSecondsAfterReady or 1800) end
    PPStore.savePlayer(cid)

    local src = onlineSources[cid]
    if src then
        TriggerClientEvent('as-postalprime:client:updated', src)
        pushPhoneNotification(src, 'Order ready for pickup',
            byName and ('%s delivered your order to %s. Open the app for your pickup code.'):format(byName, order.lockerLabel)
                or ('Your order is ready at %s. Open the app for your pickup code.'):format(order.lockerLabel))
        local locker = findLocker(order.lockerId)
        if locker then
            TriggerClientEvent('as-postalprime:client:orderReady', src,
                { x = locker.coords.x, y = locker.coords.y, z = locker.coords.z }, order.lockerLabel)
        end
    end
end

lib.callback.register('as-postalprime:getHomeParcels', function()
    return homeParcels()
end)

-- Fired when someone uses "Take Parcel" on a box at a doorstep. Anyone standing at the box can take
-- it (by design) - the items go to whoever took it and the buyer's order is closed.
RegisterNetEvent('as-postalprime:takeHomeParcel')
AddEventHandler('as-postalprime:takeHomeParcel', function(orderId)
    local source = source
    local takerCid = track(source)
    if not takerCid or type(orderId) ~= 'string' then return end

    local ownerCid, ownerPd, order
    for cid, pd in pairs(PPStore.players) do
        local o = pd.active
        if o and o.id == orderId and o.delivery == 'home' then
            ownerCid, ownerPd, order = cid, pd, o
            break
        end
    end
    if not order or not order.ready or order.collected or order.expired or not order.homeProperty then return end

    local c = order.homeProperty.coords
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > (Config.home.takeCheckDistance or 10.0) then
        return -- too far from the doorstep
    end

    for _, it in ipairs(order.items) do
        local entry = findCatalogItem(it.id)
        PPBridge.addItem(source, entry and entry.item or it.item or it.id, it.qty, it.metadata)
    end

    order.collected = true
    if takerCid ~= ownerCid then order.takenBy = PPBridge.getCharacterName(source) end
    ownerPd.active = nil
    pushHistory(ownerPd, order)
    PPStore.savePlayer(ownerCid)

    TriggerClientEvent('as-postalprime:client:homeRemove', -1, order.id)

    TriggerClientEvent('as-postalprime:toast', source, {
        title = 'Postal Prime', description = 'Parcel collected!', type = 'success',
    })

    local ownerSrc = onlineSources[ownerCid]
    if ownerSrc then
        TriggerClientEvent('as-postalprime:client:updated', ownerSrc)
        TriggerClientEvent('as-postalprime:client:orderReady:clear', ownerSrc)
        if takerCid == ownerCid then
            pushPhoneNotification(ownerSrc, 'Parcel picked up',
                ('Your order at %s was picked up. Thanks for shopping with Postal Prime!'):format(order.homeProperty.label))
        else
            pushPhoneNotification(ownerSrc, 'Your parcel was taken',
                ('Your order at %s was picked up by someone else.'):format(order.homeProperty.label))
        end
    end
end)

-- ─── Parcels sent by other resources ──────────────────────────────────────────
-- Lets another resource (e.g. as-passport) put something in a player's locker without a catalog
-- purchase. The parcel is an ordinary order with nothing to pay and nothing to refund, and it goes
-- through the same prep time, pickup code, locker door and "Take Parcel" steps as any order.
--
--   local ok, err = exports['as-postalprime']:createParcel(citizenid, {
--       ref = 'PP123',                       -- your own reference, echoed back in the events below
--       sender = 'Los Santos Passport Office',
--       lockerId = 'some_locker_id',         -- one of exports['as-postalprime']:getLockers()
--       prepSeconds = 180, expireSeconds = 172800,   -- optional
--       items = { { item = 'passport', label = 'Passport', icon = '🛂', qty = 1, metadata = { ... } } },
--   })
--   err is 'busy' when the player already has a pile of uncollected parcels (try again later), 'bad_locker', 'bad_item' or 'bad_request'.
--   A parcel never blocks the player ordering from the shop, and a shop order never blocks a parcel.
--
-- Events (server side): 'as-postalprime:parcelCollected' (cid, ref, source) and
-- 'as-postalprime:parcelExpired' (cid, ref) when it sat uncollected until it expired.

exports('getLockers', function()
    local out = {}
    for _, l in ipairs(Config.lockers) do out[#out + 1] = { id = l.id, label = l.label } end
    return out
end)

exports('createParcel', function(cid, parcel)
    if type(cid) ~= 'string' or type(parcel) ~= 'table' or type(parcel.items) ~= 'table' or #parcel.items == 0 then
        return false, 'bad_request'
    end
    local locker = findLocker(parcel.lockerId)
    if not locker then return false, 'bad_locker' end

    local items = {}
    for _, it in ipairs(parcel.items) do
        if type(it) ~= 'table' or type(it.item) ~= 'string' or it.item == '' then return false, 'bad_item' end
        items[#items + 1] = {
            id = 'parcel:' .. it.item, item = it.item,
            label = tostring(it.label or it.item):sub(1, 60), icon = tostring(it.icon or '📦'):sub(1, 8),
            price = 0, qty = math.max(1, math.floor(tonumber(it.qty) or 1)), metadata = it.metadata,
        }
    end

    -- Parcels sit in their own list, so they never stop the player placing a shop order (and a shop
    -- order in progress never stops a parcel). Only an absurd pile-up is refused.
    local pd = PPStore.getPlayer(cid)
    pd.parcels = pd.parcels or {}
    if #pd.parcels >= (Config.order.maxParcels or 10) then return false, 'busy' end

    -- Which resource sent it (as-passport, as-birthcert, as-drivingschool...), so Config.courier.parcelDeliveries can be set per resource.
    local caller = GetInvokingResource and GetInvokingResource() or nil
    if type(caller) ~= 'string' or caller == '' then caller = nil end

    local now = os.time()
    local prep = tonumber(parcel.prepSeconds) or Config.order.prepSeconds or 180
    local expire = tonumber(parcel.expireSeconds) or Config.order.expireSecondsAfterReady or 1800
    pd.parcels[#pd.parcels + 1] = {
        id = newOrderId(), items = items,
        lockerId = locker.id, lockerLabel = locker.label, delivery = 'locker',
        itemsTotal = 0, deliveryFee = 0, total = 0,
        placedAt = now, readyAt = now + prep, expiresAt = now + prep + expire, expireSeconds = expire,
        ready = false, collected = false, expired = false, code = newCode(),
        parcel = true, parcelSource = caller, parcelRef = parcel.ref, sender = parcel.sender and tostring(parcel.sender):sub(1, 60) or nil,
    }
    PPStore.savePlayer(cid)

    local src = onlineSources[cid]
    if src then TriggerClientEvent('as-postalprime:client:updated', src) end
    return true
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
            for _, order in ipairs(eachOrder(pd)) do
            if not order.collected and not order.expired then
                if not order.ready and now >= order.readyAt and order.delivery == 'home' then
                    -- Home delivery, prep time is up. If player couriers are on duty the order goes to
                    -- the depot board (server/courier.lua then drives it from there, falling back to the
                    -- NPC van when needed); otherwise the NPC van drops it right now (client/home.lua).
                    if order.courier then
                        -- already with the courier system - it will call PP.dropHome when done
                    elseif not (PPCourier and PPCourier.tryBoard(cid, order)) then
                        PP.dropHome(cid, order)
                    end
                elseif not order.ready and now >= order.readyAt then
                    -- Locker order (or a parcel sent by another resource), prep time is up. With couriers on duty
                    -- (and Config.courier.lockerDeliveries / parcelDeliveries) it goes to the depot board first.
                    if order.courier then
                        -- already with the courier system - it will call PP.readyLocker when done
                    elseif not (PPCourier and PPCourier.tryBoard(cid, order)) then
                        PP.readyLocker(cid, order)
                    end
                elseif order.ready and order.expiresAt and now > order.expiresAt then
                    removeOrder(pd, order)
                    order.expired = true
                    pushHistory(pd, order)
                    PPStore.savePlayer(cid)

                    local src = onlineSources[cid]
                    if order.parcel then
                        -- A sent parcel has nothing to refund. The sender is told so it can send it again.
                        TriggerEvent('as-postalprime:parcelExpired', cid, order.parcelRef)
                        if src then
                            TriggerClientEvent('as-postalprime:client:updated', src)
                            if not hasReadyLockerOrder(pd) then TriggerClientEvent('as-postalprime:client:orderReady:clear', src) end
                            pushPhoneNotification(src, 'Parcel returned',
                                ('Your uncollected parcel at %s was returned to the sender.'):format(order.lockerLabel))
                        end
                    elseif src then
                        refundPlayer(src, order.total)
                        TriggerClientEvent('as-postalprime:client:updated', src)
                        if not hasReadyLockerOrder(pd) then TriggerClientEvent('as-postalprime:client:orderReady:clear', src) end
                        pushPhoneNotification(src, 'Order expired & refunded',
                            ('Your uncollected order at %s expired and was refunded in full.'):format(order.lockerLabel))
                    else
                        -- Player offline when their order expired - refund can't be applied to an
                        -- offline account/inventory for most frameworks. See README "Known limitation".
                        print(('[as-postalprime] order %s for %s expired while offline - could not refund %d automatically'):format(order.id, cid, order.total))
                    end
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
