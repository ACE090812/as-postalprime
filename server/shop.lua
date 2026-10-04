-- Shopping: wishlist, saved cart, coupons, checkout, cancelling, returns and Postal Prime Plus.

local track = PP.track
local findCatalogItem = PP.findCatalogItem
local findLocker = PP.findLocker
local cleanCart = PP.cleanCart
local isPlusActive = PP.isPlusActive
local orderList = PP.orderList
local homeTravelSeconds = PP.homeTravelSeconds
local newCode, newOrderId = PP.newCode, PP.newOrderId
local pushHistory = PP.pushHistory
local chargePlayer, refundPlayer = PP.charge, PP.pay
local round2 = PPDeals.round2

local MAX_QTY = 99

-- Wishlist is just a set of item ids saved on the player's own row - separate from the cart, and
-- never charges/reserves anything.
lib.callback.register('as-postalprime:toggleWishlist', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    if type(data) ~= 'table' or not data.itemId then return { ok = false, error = T('err.badRequest') } end
    if not findCatalogItem(data.itemId) then return { ok = false, error = T('err.unknownItem') } end

    local pd = PPStore.getPlayer(cid)
    pd.wishlist = pd.wishlist or {}
    if pd.wishlist[data.itemId] then
        pd.wishlist[data.itemId] = nil
    else
        pd.wishlist[data.itemId] = true
    end
    PPStore.markDirty(cid)

    local wishlist = {}
    for itemId in pairs(pd.wishlist) do wishlist[#wishlist + 1] = itemId end
    return { ok = true, wishlist = wishlist }
end)

lib.callback.register('as-postalprime:saveCart', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false } end
    local pd = PPStore.getPlayer(cid)
    pd.cart = cleanCart(data.cart)
    PPStore.markDirty(cid)
    return { ok = true }
end)

-- Turns the cart the app sends ({ [itemId] = qty }) into order lines, priced with today's deals. Returns the lines and
-- their total, or nil and an error message. `buyerCid` stops a seller buying their own marketplace listing.
local function buildLines(rawItems, buyerCid, checkStock)
    local lines, total = {}, 0
    for itemId, qty in pairs(rawItems) do
        qty = tonumber(qty) or 0
        if qty > 0 then
            local entry = findCatalogItem(itemId)
            if not entry then return nil, T('err.cartItemGone') end
            qty = math.min(MAX_QTY, math.floor(qty))
            if entry.listing and entry.sellerCid == buyerCid then return nil, T('err.market.own') end

            if checkStock then
                local stock = PP.getStock(entry.id)
                if stock ~= nil and stock < qty then
                    return nil, stock <= 0 and T('err.outOfStock', entry.label) or T('err.onlyLeft', stock, entry.label)
                end
            end

            local price = PP.unitPrice(entry)
            -- `item` is saved on the line so a later config change (or a removed catalog entry) can't break the hand-over.
            local line = { id = entry.id, label = entry.label, icon = entry.icon, price = price, qty = qty, item = entry.item }
            if not entry.listing and price < entry.price then line.origPrice = entry.price end
            if entry.listing then
                -- Marketplace line: remembers what to hand over and who gets paid when it is collected.
                line.item = entry.item
                line.listingId = entry.listing
                line.sellerCid = entry.sellerCid
                line.sellerName = entry.seller
            end
            lines[#lines + 1] = line
            total = total + price * qty
        end
    end
    return lines, round2(total)
end

-- Live coupon check for the app's checkout screen ("Apply" button).
lib.callback.register('as-postalprime:checkCoupon', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' or type(data.items) ~= 'table' then return { ok = false, error = T('err.badRequest') } end
    local pd = PPStore.getPlayer(cid)
    local lines, total = buildLines(data.items, cid, false)
    if not lines then return { ok = false, error = total } end
    local discount, code = PPDeals.checkCoupon(data.code, pd, total, isPlusActive(pd))
    if not discount then return { ok = false, error = code } end
    local c = Config.coupons[code]
    return { ok = true, code = code, discount = discount, label = c.label }
end)

lib.callback.register('as-postalprime:checkout', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    local isHome = type(data) == 'table' and data.delivery == 'home'
    if type(data) ~= 'table' or type(data.items) ~= 'table' or (not isHome and not data.lockerId) then
        return { ok = false, error = T('err.badRequest') }
    end

    -- Home delivery: the property is re-resolved server-side from what THIS character owns/rents/has
    -- keys to, so a modified client can never send a parcel to an address it has no access to.
    local property = nil
    if isHome then
        if not (Config.home and Config.home.enabled) or not PPHousing.available() then
            return { ok = false, error = T('err.homeUnavailable') }
        end
        if type(data.giftTo) == 'string' and data.giftTo:gsub('%s+', '') ~= '' then
            return { ok = false, error = T('err.giftLockerOnly') }
        end
        if type(data.propertyKey) ~= 'string' then
            return { ok = false, error = T('err.pickProperty') }
        end
        property = PPHousing.resolve(cid, data.propertyKey)
        if not property then
            return { ok = false, error = T('err.noPropertyAccess') }
        end
    end

    -- Gift orders: the order gets assigned to the RECIPIENT (they collect it, they get the ready/expiry
    -- notifications), but the buyer's card is the one charged. The recipient just needs to be an online player
    -- with that exact in-character name.
    local giftSrc, giftCid, giftName = nil, nil, nil
    if type(data.giftTo) == 'string' and data.giftTo:gsub('%s+', '') ~= '' then
        giftSrc = PP.findOnlinePlayerByName(data.giftTo, source)
        if not giftSrc then
            return { ok = false, error = T('err.giftNotFound', data.giftTo) }
        end
        giftCid = track(giftSrc)
        if not giftCid then return { ok = false, error = T('err.giftUnavailable') } end
        giftName = PPBridge.getCharacterName(giftSrc)
    end

    local recipientCid = giftCid or cid
    local buyerPd = PPStore.getPlayer(cid)
    local recipientPd = PPStore.getPlayer(recipientCid)

    if #recipientPd.orders >= (Config.order.maxActive or 3) then
        return { ok = false, error = giftCid
            and T('err.giftHasOrder', giftName)
            or T('err.hasOrder', Config.order.maxActive or 3) }
    end

    local locker = nil
    if not isHome then
        locker = findLocker(data.lockerId)
        if not locker then return { ok = false, error = T('err.pickLocker') } end
    end

    local items, itemsTotal = buildLines(data.items, cid, true)
    if not items then return { ok = false, error = itemsTotal } end
    if #items == 0 then return { ok = false, error = T('err.cartEmpty') } end

    -- Plus (free delivery / faster prep) is the RECIPIENT's benefit on a gift order, same as any
    -- other perk tied to who's actually receiving and collecting it.
    local plusActive = isPlusActive(recipientPd)

    local discount, couponCode = 0, nil
    if type(data.coupon) == 'string' and data.coupon:gsub('%s+', '') ~= '' then
        local d, codeOrErr = PPDeals.checkCoupon(data.coupon, buyerPd, itemsTotal, isPlusActive(buyerPd))
        if not d then return { ok = false, error = codeOrErr } end
        discount, couponCode = d, codeOrErr
    end

    -- One delivery charge: home delivery uses its own fee INSTEAD of the normal locker delivery fee.
    local deliveryFee = plusActive and 0 or (isHome and (Config.home.fee or 0) or (Config.plus.deliveryFee or 0))
    local prepSeconds = plusActive and (Config.plus.prepSeconds or Config.order.prepSeconds) or (Config.order.prepSeconds or 180)

    -- Express shipping: a fee for a (much) shorter prep time.
    local expressFee, express = 0, false
    local ex = Config.shipping and Config.shipping.express
    if data.speed == 'express' and ex and ex.enabled ~= false then
        express = true
        expressFee = plusActive and (ex.plusFee or ex.fee or 0) or (ex.fee or 0)
        prepSeconds = math.min(prepSeconds, ex.prepSeconds or prepSeconds)
    end
    if isHome then prepSeconds = prepSeconds + homeTravelSeconds(property.coords) end

    -- Delivery insurance (home delivery only): refunds the items if someone else takes the parcel from the doorstep.
    local insuranceFee, insured = 0, false
    local ins = Config.insurance
    if isHome and data.insured == true and ins and ins.enabled ~= false then
        insured = true
        insuranceFee = round2(math.max(ins.minFee or 0, math.min(ins.maxFee or 1e9, itemsTotal * (ins.pct or 5) / 100)))
    end

    -- Loyalty points as money off the items.
    local pointsUsed, pointsDiscount = 0, 0
    if data.points == true then
        pointsUsed, pointsDiscount = PPLoyalty.quote(buyerPd, round2(itemsTotal - discount))
    end

    local total = round2(itemsTotal - discount - pointsDiscount + deliveryFee + expressFee + insuranceFee)

    if not chargePlayer(source, total) then
        return { ok = false, error = T('err.noCash') }
    end

    -- Stock was only checked above, not spent yet - spend it now that payment succeeded. Checked
    -- again per-item in case something else sold the last unit between the check and here; on a miss
    -- everything already taken goes back and the player is refunded.
    local spent = {}
    for _, it in ipairs(items) do
        if not PP.spendStock(it.id, it.qty) then
            for _, s in ipairs(spent) do PP.giveStock(s.id, s.qty) end
            refundPlayer(source, total)
            return { ok = false, error = T('err.soldOut', it.label) }
        end
        spent[#spent + 1] = it
    end

    if couponCode then PPDeals.spendCoupon(buyerPd, couponCode) end
    if pointsUsed > 0 then PPLoyalty.add(buyerPd, -pointsUsed) end

    local dealSavings = 0
    for _, it in ipairs(items) do
        if it.origPrice then dealSavings = dealSavings + (it.origPrice - it.price) * it.qty end
    end

    local now = os.time()
    local order = {
        id = newOrderId(),
        items = items,
        lockerId = isHome and ('home:' .. property.key) or locker.id,
        lockerLabel = isHome and T('order.homeLabel', property.label) or locker.label,
        delivery = isHome and 'home' or 'locker',
        homeProperty = isHome and property or nil,
        itemsTotal = itemsTotal,
        discount = discount > 0 and discount or nil,
        coupon = couponCode,
        couponBy = couponCode and cid or nil,
        deliveryFee = deliveryFee,
        speed = express and 'express' or nil,
        expressFee = expressFee > 0 and expressFee or nil,
        insured = insured or nil,
        insuranceFee = insured and insuranceFee or nil,
        pointsUsed = pointsUsed > 0 and pointsUsed or nil,
        pointsDiscount = pointsDiscount > 0 and pointsDiscount or nil,
        dealSavings = dealSavings > 0 and round2(dealSavings) or nil,
        total = total,
        buyerCid = cid,
        placedAt = now,
        readyAt = now + prepSeconds,
        expiresAt = (not isHome) and (now + prepSeconds + (Config.order.expireSecondsAfterReady or 1800)) or nil,
        ready = false,
        collected = false,
        expired = false,
        code = newCode(),
        giftedBy = giftCid and PPBridge.getCharacterName(source) or nil,
    }
    recipientPd.orders[#recipientPd.orders + 1] = order
    buyerPd.cart = nil -- the cart was just checked out
    PPStore.savePlayer(recipientCid)
    if cid ~= recipientCid then PPStore.savePlayer(cid) end

    TriggerEvent('as-postalprime:orderPlaced', cid, order.id, total)
    PPLog.log('purchase', source, ('%d line(s), $%s%s%s'):format(#items, total,
        couponCode and (' with ' .. couponCode) or '', giftCid and (' (gift to ' .. giftName .. ')') or ''),
        { order = order.id, total = total, delivery = order.delivery })
    if couponCode then PPLog.log('coupon', source, couponCode .. ' used (-$' .. discount .. ')', { order = order.id }) end

    -- Readiness itself is flipped by the background sweep (server/sweep.lua), not a one-shot timer here -
    -- a timer scheduled only at checkout is lost forever if the resource/server restarts before
    -- it fires, leaving the order stuck on "Preparing". The sweep re-checks readyAt against the
    -- clock every few seconds regardless of restarts, so it always catches up.

    if giftCid then
        PP.notify(giftSrc, T('notif.gift.title'), T('notif.gift.body', order.lockerLabel))
        TriggerClientEvent('as-postalprime:client:updated', giftSrc)
    end

    -- The buyer's OWN order list is unaffected by a gift (it's not their order) - always
    -- return the buyer's real list, not the recipient's.
    return { ok = true, gifted = giftCid ~= nil, giftedTo = giftName, orders = orderList(buyerPd, cid) }
end)

-- Everything an uncollected order took is put back: stock, the coupon use and the money. The money goes to whoever paid
-- (an offline buyer is paid the next time they are online). reason: 'cancelled' | 'expired' | 'admin'.
function PP.unwindOrder(order, reason)
    for _, it in ipairs(order.items) do PP.giveStock(it.id, it.qty) end
    if order.coupon and order.couponBy then
        PPDeals.refundCoupon(PPStore.getPlayer(order.couponBy), order.coupon)
        PPStore.markDirty(order.couponBy)
    end
    if order.pointsUsed and order.buyerCid then
        PPLoyalty.add(PPStore.getPlayer(order.buyerCid), order.pointsUsed)
        PPStore.markDirty(order.buyerCid)
    end
    PP.refundCid(order.buyerCid or order.ownerCid, order.total)
    PPStats.bump(reason == 'expired' and 'expired' or 'cancelled', 1)
    PPStats.bump('refunded', order.total)
    PPLog.log('cancel', nil,
        ('order %s %s, $%s refunded'):format(order.id, reason, order.total), { order = order.id, reason = reason })
end

-- Lets a player back out of an order and get a full refund, but only while it's still
-- "Preparing" - once it's ready for pickup (code issued, door assignable) it has to be
-- collected or left to expire like before, same as a real courier already being en route.
lib.callback.register('as-postalprime:cancelOrder', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end

    local pd = PPStore.getPlayer(cid)
    local wanted = type(data) == 'table' and data.orderId or nil
    local order
    for _, o in ipairs(pd.orders) do
        if (wanted and o.id == wanted) or (not wanted and not o.ready) then order = o break end
    end
    if not order then return { ok = false, error = T('err.noActiveOrder') } end
    if order.ready then
        return { ok = false, error = T('err.alreadyReady') }
    end
    if order.courier and order.courier.state ~= 'board' then
        return { ok = false, error = T('err.courierHandling') }
    end

    PP.removeOrder(pd, order)
    order.courier = nil
    order.cancelled = true
    order.ownerCid = cid
    pushHistory(pd, order)
    PPStore.savePlayer(cid)
    PP.unwindOrder(order, 'cancelled')

    TriggerClientEvent('as-postalprime:client:updated', source)
    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.orderCancelled'), type = 'success',
    })

    return { ok = true, orders = orderList(pd, cid) }
end)

-- Send items from a collected order back for a refund (Config.returns). The items have to be in the player's
-- inventory (a sealed parcel has to be opened first); the refund is refundPct of what they paid for them.
lib.callback.register('as-postalprime:returnItem', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    if type(data) ~= 'table' or type(data.orderId) ~= 'string' or type(data.itemId) ~= 'string' then
        return { ok = false, error = T('err.badRequest') }
    end
    if not (Config.returns and Config.returns.enabled ~= false) then return { ok = false, error = T('err.returns.off') } end

    local pd = PPStore.getPlayer(cid)
    local order
    for _, o in ipairs(pd.history) do if o.id == data.orderId then order = o break end end
    if not order then return { ok = false, error = T('err.returns.noOrder') } end
    local line
    for _, it in ipairs(order.items) do if it.id == data.itemId then line = it break end end
    if not line then return { ok = false, error = T('err.unknownItem') } end

    local can = PP.returnableQty(order, line)
    if can <= 0 then return { ok = false, error = T('err.returns.closed') } end
    local qty = math.min(can, math.max(1, math.floor(tonumber(data.qty) or 1)))

    local entry = findCatalogItem(line.id)
    if not entry or not entry.item then return { ok = false, error = T('err.unknownItem') } end
    if PPBridge.getItemCount(source, entry.item) < qty then
        return { ok = false, error = T('err.returns.noItem', entry.label) }
    end
    if not PPBridge.removeItem(source, entry.item, qty) then
        return { ok = false, error = T('err.returns.noItem', entry.label) }
    end

    local refund = round2(PP.returnUnitRefund(order, line) * qty)
    line.returned = (line.returned or 0) + qty
    PPStore.savePlayer(cid)
    refundPlayer(source, refund)
    if Config.returns.restock ~= false then PP.giveStock(line.id, qty) end

    PPStats.recordReturn(cid, refund)
    PPStats.bump('returns', 1)
    PPStats.bump('refunded', refund)
    if order.buyerCid then PPLoyalty.clawback(order.buyerCid, refund) end
    PPLog.log('return', source, ('returned %dx %s for $%s'):format(qty, line.label, refund), { order = order.id })
    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.returned', refund), type = 'success',
    })
    return { ok = true, refund = refund, orders = orderList(pd, cid) }
end)

lib.callback.register('as-postalprime:subscribePlus', function(source)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end

    local pd = PPStore.getPlayer(cid)
    local price = Config.plus.price or 0

    if not chargePlayer(source, price) then
        return { ok = false, error = T('err.noCash') }
    end

    local now = os.time()
    local durationSeconds = (Config.plus.durationDays or 7) * 86400
    local base = (pd.plus and pd.plus.expiresAt and pd.plus.expiresAt > now) and pd.plus.expiresAt or now
    pd.plus = { expiresAt = base + durationSeconds }
    PPStore.savePlayer(cid)
    PPStats.bump('plusSales', 1)
    PPStats.bump('plusRevenue', price)
    PPLog.log('purchase', source, ('Postal Prime Plus for $%s'):format(price), { plus = true })

    return {
        ok = true,
        plus = { active = true, expiresAt = pd.plus.expiresAt * 1000 },
    }
end)

-- Everything that happens when any order is collected (locker or doorstep): sellers are paid, the buyer earns loyalty
-- points, the collector's stats and the server's daily counters are updated.
function PP.onCollected(cid, order)
    if order.parcel then return end
    PPMarket.payout(order)
    PPLoyalty.earn(order)
    PPStats.recordCollected(cid, order)
    PPStats.bump('orders', 1)
    PPStats.bump('revenue', order.total or 0)
    if (order.discount or 0) > 0 then PPStats.bump('couponDiscount', order.discount) end
    if (order.pointsDiscount or 0) > 0 then PPStats.bump('pointsDiscount', order.pointsDiscount) end
    if (order.expressFee or 0) > 0 then PPStats.bump('expressFees', order.expressFee) end
    if (order.insuranceFee or 0) > 0 then PPStats.bump('insuranceFees', order.insuranceFee) end
    PPStats.bumpItems(order)
    TriggerEvent('as-postalprime:orderCollected', cid, order.id, order.total or 0)
end
