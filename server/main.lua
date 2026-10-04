-- Core of the server side: the shared PP table, helpers and the app's state feed. The rest of the server code is split by
-- topic and loaded after this file (see fxmanifest.lua): shop.lua (checkout, cancel, returns, Plus), lockers.lua,
-- reviews.lua, delivery.lua, parcels.lua, market.lua, discovery.lua, tracking.lua, sweep.lua, admin.lua.
-- Anything shared between those files is exposed on PP.

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

-- Shared with every other server file loaded after this one.
PP = {}

local onlineSources = {}

-- ─── Money ───────────────────────────────────────────────────────────────────

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

-- Refunds owed to a player who was offline when the money became due (an uncollected order expiring, an admin
-- cancelling it). Saved on their row and paid out the next time they are online.
local function applyPendingRefund(source, cid)
    local pd = PPStore.players[cid]
    local owed = pd and tonumber(pd.pendingRefund)
    if not owed or owed <= 0 then return end
    pd.pendingRefund = nil
    PPStore.savePlayer(cid)
    refundPlayer(source, owed)
    PPLog.log('refund', source, ('paid out $%s refund owed from while offline'):format(owed), { citizen = cid })
    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.pendingRefund', owed), type = 'success',
    })
end

PP.applyPendingRefund = applyPendingRefund

function PP.owePlayer(cid, amount)
    if amount <= 0 then return end
    local pd = PPStore.getPlayer(cid)
    pd.pendingRefund = PPDeals.round2((pd.pendingRefund or 0) + amount)
    PPStore.savePlayer(cid)
end

-- Refunds to whoever is online, or queues it on their record when they are not.
function PP.refundCid(cid, amount)
    if amount <= 0 then return end
    local src = onlineSources[cid]
    if src then refundPlayer(src, amount) else PP.owePlayer(cid, amount) end
end

-- Phone notifications for someone who is offline are queued on their record and delivered the next time they are around.
local function deliverPendingNotifs(source, cid)
    local pd = PPStore.players[cid]
    local queue = pd and pd.pendingNotifs
    if not queue or #queue == 0 then return end
    pd.pendingNotifs = nil
    PPStore.markDirty(cid)
    for _, n in ipairs(queue) do
        if os.time() - (n.at or 0) < 172800 then pushPhoneNotification(source, n.title, n.body) end
    end
end

PP.deliverPendingNotifs = deliverPendingNotifs

-- Notify a character by id: straight away if online, otherwise queued (max 8, dropped after 48h).
function PP.notifyCid(cid, title, body)
    local src = onlineSources[cid]
    if src then return pushPhoneNotification(src, title, body) end
    local pd = PPStore.players[cid]
    if not pd then return end
    pd.pendingNotifs = pd.pendingNotifs or {}
    pd.pendingNotifs[#pd.pendingNotifs + 1] = { title = title, body = body, at = os.time() }
    while #pd.pendingNotifs > 8 do table.remove(pd.pendingNotifs, 1) end
    PPStore.markDirty(cid)
end

function PP.notifyOrderCid(cid, order, title, body)
    if order and order.hidden then return end
    PP.notifyCid(cid, title, body)
end

local function track(source)
    local cid = PPBridge.getIdentifier(source)
    if cid then
        onlineSources[cid] = source
        applyPendingRefund(source, cid)
        deliverPendingNotifs(source, cid)
    end
    return cid
end

PP.track = track
PP.notify = pushPhoneNotification
-- Orders sent with hidden = true (e.g. from the parts site) never push phone notifications.
PP.notifyOrder = function(src, order, title, body)
    if order and order.hidden then return end
    pushPhoneNotification(src, title, body)
end
PP.source = function(cid) return onlineSources[cid] end
PP.onlineSources = onlineSources
PP.round2 = function(n) return PPDeals.round2(n) end

AddEventHandler('playerDropped', function()
    local source = source
    for cid, src in pairs(onlineSources) do
        if src == source then onlineSources[cid] = nil end
    end
end)

-- ─── Catalog / lookups ───────────────────────────────────────────────────────

-- A catalog entry, or a marketplace listing as a catalog-shaped entry (ids like 'mp:12').
local function findCatalogItem(id)
    for _, entry in ipairs(Config.catalog) do
        if entry.id == id then return entry end
    end
    if type(id) == 'string' and PPMarket then return PPMarket.entry(id) end
    return nil
end

local function isMarketId(id)
    return type(id) == 'string' and id:sub(1, 3) == 'mp:'
end

-- Stock for a catalog item (nil = unlimited) or marketplace listing, behind one set of calls.
function PP.getStock(id)
    if isMarketId(id) then return PPMarket.stock(id) end
    return PPStore.getStock(id)
end

function PP.spendStock(id, qty)
    if isMarketId(id) then return PPMarket.spend(id, qty) end
    return PPStore.trySpendStock(id, qty)
end

-- Hands units back (a cancelled / expired / returned order). Never turns an unlimited item into a capped one.
function PP.giveStock(id, qty)
    if isMarketId(id) then return PPMarket.give(id, qty) end
    local current = PPStore.getStock(id)
    if current == nil then return end
    -- Returned units never push a capped item above its configured maximum (automatic restocking may already have refilled it).
    local entry = findCatalogItem(id)
    local add = qty
    if entry and entry.stock then add = math.max(0, math.min(qty, entry.stock - current)) end
    if add > 0 then PPStore.restock(id, add) end
end

-- What one unit costs right now: the catalog price with any active deal, or the seller's price for a listing.
function PP.unitPrice(entry)
    if entry.listing then return entry.price, nil end
    return PPDeals.price(entry)
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

-- Every order a player has in flight: their shop orders (pd.orders, up to Config.order.maxActive) plus any parcels
-- other resources have sent them (pd.parcels). Parcels have their own list so they never stop the player shopping.
local function eachOrder(pd)
    local list = {}
    for _, o in ipairs(pd.orders or {}) do list[#list + 1] = o end
    for _, o in ipairs(pd.parcels or {}) do list[#list + 1] = o end
    return list
end

local function removeOrder(pd, order)
    for _, list in ipairs({ pd.orders or {}, pd.parcels or {} }) do
        for i, o in ipairs(list) do
            if o == order then table.remove(list, i) return end
        end
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

local function pushHistory(pd, order)
    table.insert(pd.history, 1, order)
    local limit = Config.order.historyLimit or 20
    while #pd.history > limit do table.remove(pd.history) end
end

PP.findCatalogItem = findCatalogItem
PP.findLocker = findLocker
PP.homeTravelSeconds = homeTravelSeconds
PP.newCode = newCode
PP.newOrderId = newOrderId
PP.ratingFor = ratingFor
PP.hasPurchased = hasPurchased
PP.hasReviewed = hasReviewed
PP.isPlusActive = isPlusActive
PP.eachOrder = eachOrder -- server/courier.lua walks every in-flight order (shop orders + parcels)
PP.removeOrder = removeOrder
PP.findOrderById = findOrderById
PP.hasReadyLockerOrder = hasReadyLockerOrder
PP.pushHistory = pushHistory
PP.cleanCart = cleanCart

-- ─── Returns ─────────────────────────────────────────────────────────────────

-- Units of an order item that can still be sent back (0 = none), and what each unit refunds.
local function returnableQty(order, it, now)
    local r = Config.returns
    if not r or r.enabled == false or not order.collected or order.parcel or order.takenBy then return 0 end
    if it.listingId or (it.price or 0) <= 0 then return 0 end
    if not order.collectedAt or (now or os.time()) - order.collectedAt > (r.windowSeconds or 86400) then return 0 end
    return math.max(0, (tonumber(it.qty) or 0) - (tonumber(it.returned) or 0))
end

-- What was paid for the ITEMS of an order (after coupon and points discounts; fees excluded).
local function itemsPaid(order)
    local total = tonumber(order.itemsTotal) or 0
    return math.max(0, total - (tonumber(order.discount) or 0) - (tonumber(order.pointsDiscount) or 0))
end
PP.itemsPaid = itemsPaid

-- Share of an item's price actually paid (a discount is spread over the whole items total).
local function paidRatio(order)
    local total = tonumber(order.itemsTotal) or 0
    if total <= 0 then return 1 end
    return itemsPaid(order) / total
end

local function returnUnitRefund(order, it)
    local pct = (Config.returns and Config.returns.refundPct) or 80
    return PPDeals.round2(it.price * paidRatio(order) * pct / 100)
end

PP.returnableQty = returnableQty
PP.returnUnitRefund = returnUnitRefund

local function sanitizeOrder(order, cid)
    local now = os.time()
    local items = {}
    for _, it in ipairs(order.items) do
        items[#items + 1] = {
            id = it.id, label = it.label, icon = it.icon, price = it.price, qty = it.qty,
            reviewed = order.collected and hasReviewed(cid, it.id) or false,
            returned = it.returned or 0,
            returnable = returnableQty(order, it, now),
            returnRefund = returnableQty(order, it, now) > 0 and returnUnitRefund(order, it) or nil,
        }
    end
    local live = order.ready and not order.collected and not order.expired
    return {
        id = order.id,
        items = items,
        lockerId = order.lockerId,
        lockerLabel = order.lockerLabel,
        itemsTotal = order.itemsTotal or order.total,
        discount = order.discount or 0,
        coupon = order.coupon,
        deliveryFee = order.deliveryFee or 0,
        expressFee = order.expressFee,
        insured = order.insured or nil,
        insuranceFee = order.insuranceFee,
        insurancePaid = order.insurancePaid,
        pointsUsed = order.pointsUsed,
        pointsDiscount = order.pointsDiscount,
        pointsEarned = order.pointsEarned,
        subscription = order.subscription and true or nil,
        total = order.total,
        placedAt = order.placedAt * 1000,
        readyAt = order.readyAt * 1000,
        -- Locker orders: when an uncollected order is cancelled and refunded (the app shows a countdown).
        expiresAt = (live and order.expiresAt) and (order.expiresAt * 1000) or nil,
        ready = order.ready,
        collected = order.collected,
        expired = order.expired or false,
        cancelled = order.cancelled or false,
        -- Only ever hand out the code while it's actually usable - never after collection/expiry.
        code = live and order.code or nil,
        giftedBy = order.giftedBy,
        delivery = order.delivery or 'locker',
        takenBy = order.takenBy,
        -- Player-courier progress while a home order is being handled: 'board' | 'claimed' | 'loaded'.
        courier = order.courier and order.courier.state or nil,
        deliveredBy = order.deliveredBy,
        parcel = order.parcel or nil,
        sender = order.sender,
        damaged = order.damaged or nil,
    }
end

PP.sanitizeOrder = sanitizeOrder

local function catalogPayload(cid)
    local out = {}
    local now = os.time()
    local deals = PPDeals.active(now)
    for _, entry in ipairs(Config.catalog) do
        local rating, reviews = ratingFor(entry.id, entry.baseRating, entry.baseReviews)
        local deal = deals[entry.id]
        local price = deal and PPDeals.round2(entry.price * (100 - deal.pct) / 100) or entry.price
        out[#out + 1] = {
            id = entry.id, label = entry.label, price = price, icon = entry.icon, cat = entry.cat,
            rating = rating, reviews = reviews,
            -- nil (omitted) means unlimited - the app only shows a stock note/blocks Add to Cart
            -- when this is an actual number.
            stock = PPStore.getStock(entry.id),
            origPrice = deal and entry.price or nil,
            deal = deal and { pct = deal.pct, kind = deal.kind, endsAt = deal.endsAt * 1000 } or nil,
            alsoBought = PPDiscovery and PPDiscovery.alsoBought(entry.id) or nil,
        }
    end
    if PPMarket then
        for _, row in ipairs(PPMarket.catalogRows()) do out[#out + 1] = row end
    end
    return out
end

PP.catalogPayload = catalogPayload

-- Finds an ONLINE player by their in-character name (case-insensitive) for gift orders. Not
-- purchase history or anything identity-sensitive - just a live name match among connected
-- players, same as calling out someone's name in-game.
function PP.findOnlinePlayerByName(name, excludeSource)
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

-- The app's order list: shop orders, then parcels, then history.
local function orderList(pd, cid)
    local out = {}
    for _, o in ipairs(eachOrder(pd)) do if not o.hidden then out[#out + 1] = sanitizeOrder(o, cid) end end
    for _, o in ipairs(pd.history) do if not o.hidden then out[#out + 1] = sanitizeOrder(o, cid) end end
    return out
end

PP.orderList = orderList

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

    local categories = {}
    for _, c in ipairs(Config.categories) do categories[#categories + 1] = c end
    if PPMarket and PPMarket.enabled() then
        categories[#categories + 1] = { id = 'market', label = T('app.cat.market') }
    end

    return {
        catalog = catalogPayload(cid),
        categories = categories,
        lockers = lockerPayload(),
        orders = orders,
        wishlist = wishlist,
        boughtBefore = PPDiscovery and PPDiscovery.boughtBefore(pd) or {},
        cart = cleanCart(pd.cart),
        playerName = PPBridge.getCharacterName(source),
        maxActive = Config.order.maxActive or 3,
        market = PPMarket and PPMarket.stateFor(source, cid, pd) or nil,
        shops = PPMarket and PPMarket.enabled() and PPMarket.shops() or {},
        loyalty = PPLoyalty and PPLoyalty.stateFor(pd) or { enabled = false },
        subs = PPSubs and PPSubs.stateFor(pd) or { enabled = false },
        rentals = PPRentals and PPRentals.stateFor(cid) or { enabled = false },
        shipping = {
            express = (Config.shipping and Config.shipping.express and Config.shipping.express.enabled ~= false) and {
                fee = Config.shipping.express.fee, plusFee = Config.shipping.express.plusFee or Config.shipping.express.fee,
                prepSeconds = Config.shipping.express.prepSeconds,
            } or nil,
        },
        insurance = (Config.insurance and Config.insurance.enabled ~= false) and {
            pct = Config.insurance.pct, minFee = Config.insurance.minFee, maxFee = Config.insurance.maxFee,
        } or nil,
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
