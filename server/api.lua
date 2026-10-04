-- Exports for other resources (besides createParcel / getParcels / getDeliveryInfo / getLockers in server/parcels.lua).
-- Everything here is server-side and trusted: only call it from your own server scripts.
--
--   addCatalogItem(entry)            -> ok, err      add a product at runtime (same fields as a Config.catalog entry:
--                                                    id, label, item, price, icon, cat, stock, ...). It is NOT saved - call it
--                                                    again each time your resource starts. 'exists' / 'bad_entry' on failure.
--   removeCatalogItem(id)            -> ok           take a product off sale (orders already placed still get their items)
--   addCoupon(code, def)             -> ok, err      def like a Config.coupons entry ({ pct = 10 } or { flat = 5 }, ...)
--   removeCoupon(code)               -> ok
--   giftItems(cid, items, opts)      -> ok, err, id  put catalog items in someone's locker as a free parcel:
--                                                    items = { phonecase = 2, hoodie = 1 }, opts = { lockerId, sender, ref, prepSeconds }
--   getOrders(cid)                   -> table        the character's in-flight orders (what the app shows)
--   getStock(itemId) / setStock(itemId, amount)
--   addLoyaltyPoints(cid, points)    -> new total    (negative takes points away)
--   getLoyalty(cid)                  -> { points, lifetime, tier, nextTier, nextAt }
--   grantPlus(cid, days)             -> expiresAt    unix seconds
--
-- Server events: 'as-postalprime:orderPlaced' (cid, orderId, total), 'as-postalprime:orderCollected' (cid, orderId, total),
-- 'as-postalprime:parcelCollected' / 'parcelExpired' (see parcels), 'as-postalprime:suspiciousCollect' (source, cid, lockerId, lockCount),
-- 'as-postalprime:businessDelivered'.

local findCatalogItem = PP.findCatalogItem

exports('addCatalogItem', function(entry)
    if type(entry) ~= 'table' or type(entry.id) ~= 'string' or entry.id == '' or entry.id:sub(1, 3) == 'mp:'
        or type(entry.label) ~= 'string' or type(entry.item) ~= 'string' or type(entry.price) ~= 'number' or entry.price <= 0 then
        return false, 'bad_entry'
    end
    for _, e in ipairs(Config.catalog) do
        if e.id == entry.id then return false, 'exists' end
    end
    local copy = {}
    for k, v in pairs(entry) do copy[k] = v end
    copy.icon = copy.icon or 'box'
    copy.cat = copy.cat or 'all'
    copy.baseRating = copy.baseRating or 4
    copy.baseReviews = copy.baseReviews or 0
    copy.runtime = true
    Config.catalog[#Config.catalog + 1] = copy
    if copy.stock ~= nil and PPStore.getStock(copy.id) == nil then PPStore.restock(copy.id, copy.stock) end
    return true
end)

exports('removeCatalogItem', function(id)
    for i, e in ipairs(Config.catalog) do
        if e.id == id then
            table.remove(Config.catalog, i)
            return true
        end
    end
    return false
end)

exports('addCoupon', function(code, def)
    code = PPDeals.normalizeCode(code)
    if code == '' or type(def) ~= 'table' or (def.pct == nil) == (def.flat == nil) then return false, 'bad_coupon' end
    Config.coupons = Config.coupons or {}
    Config.coupons[code] = def
    return true
end)

exports('removeCoupon', function(code)
    code = PPDeals.normalizeCode(code)
    if Config.coupons and Config.coupons[code] then Config.coupons[code] = nil return true end
    return false
end)

exports('giftItems', function(cid, items, opts)
    if type(cid) ~= 'string' or type(items) ~= 'table' then return false, 'bad_request' end
    opts = opts or {}
    local lines = {}
    for id, qty in pairs(items) do
        local entry = findCatalogItem(id)
        if not entry or entry.listing then return false, 'bad_item' end
        lines[#lines + 1] = { item = entry.item, label = entry.label, icon = entry.icon, qty = math.max(1, math.floor(tonumber(qty) or 1)) }
    end
    if #lines == 0 then return false, 'bad_request' end
    return PP.createParcel(cid, {
        ref = opts.ref, sender = opts.sender or 'Postal Prime', lockerId = opts.lockerId or (Config.lockers[1] and Config.lockers[1].id),
        prepSeconds = opts.prepSeconds, items = lines,
    })
end)

exports('getOrders', function(cid)
    if type(cid) ~= 'string' then return {} end
    return PP.orderList(PPStore.getPlayer(cid), cid)
end)

exports('getStock', function(itemId) return PPStore.getStock(itemId) end)

exports('setStock', function(itemId, amount)
    if not findCatalogItem(itemId) or type(amount) ~= 'number' or amount < 0 then return false end
    PPStore.restock(itemId, math.floor(amount) - (PPStore.getStock(itemId) or 0))
    return true
end)

exports('addLoyaltyPoints', function(cid, points)
    if type(cid) ~= 'string' or type(points) ~= 'number' then return false end
    local pd = PPStore.getPlayer(cid)
    PPLoyalty.add(pd, math.floor(points))
    PPStore.savePlayer(cid)
    return pd.loyalty.points
end)

exports('getLoyalty', function(cid)
    if type(cid) ~= 'string' then return nil end
    return PPLoyalty.stateFor(PPStore.getPlayer(cid))
end)

exports('grantPlus', function(cid, days)
    if type(cid) ~= 'string' or type(days) ~= 'number' or days <= 0 then return false end
    local pd = PPStore.getPlayer(cid)
    local now = os.time()
    local base = (pd.plus and pd.plus.expiresAt and pd.plus.expiresAt > now) and pd.plus.expiresAt or now
    pd.plus = { expiresAt = base + math.floor(days * 86400) }
    PPStore.savePlayer(cid)
    return pd.plus.expiresAt
end)
