-- Marketplace: players with an allowed job list items from their own inventory (Config.marketplace). Stock is held in
-- escrow on the listing. Buyers see listings in the shop as items with ids like 'mp:12' and check out as normal. The
-- seller is paid when the buyer COLLECTS the order (so cancels / expiries never need to touch seller money), minus
-- the commission, into a balance they withdraw in the app.

PPMarket = {}

local track = PP.track
local round2 = PPDeals.round2

local function cfg() return Config.marketplace or {} end

function PPMarket.enabled()
    return cfg().enabled ~= false and Config.marketplace ~= nil
end

local function allowedDef(item)
    for _, d in ipairs(cfg().allowedItems or {}) do
        if d.item == item then return d end
    end
end

local function canSell(source)
    if not PPMarket.enabled() then return false end
    local job = PPBridge.getJob(source)
    if not job then return false end
    for _, j in ipairs(cfg().jobs or {}) do
        if j == job then return true end
    end
    return false
end

local function listingId(key)
    local n = type(key) == 'string' and key:match('^mp:(%d+)$')
    return n and tonumber(n) or nil
end

local SHOP_ICONS = {}
for _, n in ipairs({ 'store', 'wrench', 'burger', 'car', 'shirt', 'coffee', 'leaf', 'gift', 'package', 'star' }) do SHOP_ICONS[n] = true end

-- A stable, opaque id for a seller that is safe to send to clients (never the citizen id).
local function sellerKey(cid)
    local h = 5381
    for i = 1, #cid do h = (h * 33 + cid:byte(i)) % 4294967296 end
    return ('s%08x'):format(h)
end

local function shopOf(cid)
    local pd = PPStore.players[cid]
    return pd and pd.market and pd.market.shop or nil
end

-- A listing in the shape of a catalog entry, so the rest of the server can treat both the same way.
local function asEntry(l)
    return {
        id = 'mp:' .. l.id, label = l.label, item = l.item, icon = l.icon, price = l.price, cat = 'market',
        listing = l.id, seller = l.sellerName, sellerCid = l.seller,
    }
end

function PPMarket.entry(key)
    local l = PPStore.listings[listingId(key) or -1]
    if not l or not PPMarket.enabled() then return nil end
    return asEntry(l)
end

function PPMarket.stock(key)
    local l = PPStore.listings[listingId(key) or -1]
    return l and l.qty or 0
end

function PPMarket.spend(key, qty)
    local l = PPStore.listings[listingId(key) or -1]
    if not l or l.qty < qty then return false end
    l.qty = l.qty - qty
    PPStore.saveListing(l.id)
    return true
end

function PPMarket.give(key, qty)
    local l = PPStore.listings[listingId(key) or -1]
    if not l then return end
    l.qty = l.qty + qty
    PPStore.saveListing(l.id)
end

-- Listings for the shop grid (in stock only).
function PPMarket.catalogRows()
    local out = {}
    if not PPMarket.enabled() then return out end
    local ids = {}
    for id, l in pairs(PPStore.listings) do
        if l.qty > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local l = PPStore.listings[id]
        local shop = shopOf(l.seller)
        out[#out + 1] = {
            id = 'mp:' .. id, label = l.label, price = l.price, icon = l.icon, cat = 'market',
            rating = 0, reviews = 0, stock = l.qty, seller = (shop and shop.name) or l.sellerName,
            sellerKey = sellerKey(l.seller),
        }
    end
    return out
end

local function sellerData(pd)
    pd.market = pd.market or { balance = 0, earned = 0, sold = 0 }
    return pd.market
end

-- What the app's Sell screen needs.
function PPMarket.stateFor(source, cid, pd)
    if not PPMarket.enabled() then return { enabled = false } end
    local mine = {}
    for id, l in pairs(PPStore.listings) do
        if l.seller == cid then
            mine[#mine + 1] = { id = id, label = l.label, icon = l.icon, price = l.price, qty = l.qty }
        end
    end
    table.sort(mine, function(a, b) return a.id < b.id end)
    local allowed = {}
    for _, d in ipairs(cfg().allowedItems or {}) do
        allowed[#allowed + 1] = { item = d.item, label = d.label, icon = d.icon, minPrice = d.minPrice or 1, maxPrice = d.maxPrice or 9999 }
    end
    local md = pd.market or {}
    return {
        enabled = true,
        canSell = canSell(source),
        commissionPct = cfg().commissionPct or 10,
        maxListings = cfg().maxListings or 8,
        maxQty = cfg().maxQtyPerListing or 50,
        allowed = allowed,
        mine = mine,
        balance = md.balance or 0,
        earned = md.earned or 0,
        sold = md.sold or 0,
        shop = md.shop and { name = md.shop.name, tagline = md.shop.tagline, icon = SHOP_ICONS[md.shop.icon] and md.shop.icon or 'store' } or { name = '', tagline = '', icon = 'store' },
    }
end

-- Storefront cards for the Marketplace page: one per seller that has something in stock.
function PPMarket.shops()
    local by, order = {}, {}
    for _, l in pairs(PPStore.listings) do
        if l.qty > 0 then
            local key = sellerKey(l.seller)
            if not by[key] then
                local shop = shopOf(l.seller)
                by[key] = { key = key, name = (shop and shop.name ~= '' and shop.name) or l.sellerName, tagline = shop and shop.tagline or '',
                            icon = (shop and SHOP_ICONS[shop.icon] and shop.icon) or 'store', items = 0 }
                order[#order + 1] = key
            end
            by[key].items = by[key].items + 1
        end
    end
    table.sort(order, function(a, b) return by[a].name < by[b].name end)
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = by[k] end
    return out
end

-- Units of a listing still tied up in uncollected orders (they can come back if the order is cancelled or expires).
local function pendingUnits(id)
    local n = 0
    for _, pd in pairs(PPStore.players) do
        for _, o in ipairs(PP.eachOrder(pd)) do
            if not o.collected and not o.expired then
                for _, it in ipairs(o.items) do
                    if it.listingId == id then n = n + (tonumber(it.qty) or 0) end
                end
            end
        end
    end
    return n
end

lib.callback.register('as-postalprime:market:list', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    if type(data) ~= 'table' then return { ok = false, error = T('err.badRequest') } end
    if not PPMarket.enabled() then return { ok = false, error = T('err.market.off') } end
    if not canSell(source) then return { ok = false, error = T('err.market.job') } end

    local def = allowedDef(data.item)
    if not def then return { ok = false, error = T('err.market.item') } end

    local qty = math.floor(tonumber(data.qty) or 0)
    if qty < 1 or qty > (cfg().maxQtyPerListing or 50) then
        return { ok = false, error = T('err.market.qty', cfg().maxQtyPerListing or 50) }
    end
    local price = round2(tonumber(data.price) or 0)
    local minP, maxP = def.minPrice or 1, def.maxPrice or 9999
    if price < minP or price > maxP then return { ok = false, error = T('err.market.price', minP, maxP) } end

    local count = 0
    for _, l in pairs(PPStore.listings) do if l.seller == cid then count = count + 1 end end
    if count >= (cfg().maxListings or 8) then return { ok = false, error = T('err.market.full') } end

    if PPBridge.getItemCount(source, def.item) < qty then return { ok = false, error = T('err.market.noStock', def.label) } end
    if not PPBridge.removeItem(source, def.item, qty) then return { ok = false, error = T('err.market.noStock', def.label) } end

    local id = PPStore.nextListingId()
    PPStore.listings[id] = {
        id = id, seller = cid, sellerName = PPBridge.getCharacterName(source), item = def.item, label = def.label,
        icon = def.icon or 'box', price = price, qty = qty, createdAt = os.time(),
    }
    PPStore.saveListing(id)
    PPLog.log('listing', source, ('listed %dx %s at $%s'):format(qty, def.label, price), { listing = id })
    return { ok = true, market = PPMarket.stateFor(source, cid, PPStore.getPlayer(cid)) }
end)

lib.callback.register('as-postalprime:market:remove', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false, error = T('err.unavailable') } end
    local id = tonumber(data.id)
    local l = id and PPStore.listings[id]
    if not l or l.seller ~= cid then return { ok = false, error = T('err.market.gone') } end
    if pendingUnits(id) > 0 then return { ok = false, error = T('err.market.pending') } end

    if l.qty > 0 and not PPBridge.addItem(source, l.item, l.qty) then
        return { ok = false, error = T('err.market.cantCarry') }
    end
    PPStore.deleteListing(id)
    PPLog.log('listing', source, ('removed listing %d (%dx %s returned)'):format(id, l.qty, l.label), { listing = id })
    return { ok = true, market = PPMarket.stateFor(source, cid, PPStore.getPlayer(cid)) }
end)

-- A seller's storefront: a shop name, tagline and icon shown on their listings and on the Marketplace page.
lib.callback.register('as-postalprime:market:setShop', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false, error = T('err.unavailable') } end
    if not PPMarket.enabled() then return { ok = false, error = T('err.market.off') } end
    if not canSell(source) then return { ok = false, error = T('err.market.job') } end
    -- Trim, drop control characters / angle brackets, and cut to n CHARACTERS (not bytes, so an emoji is never split).
    local clean = function(v, n)
        local str = tostring(v or ''):gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
        if not utf8.len(str) then return '' end
        local cut = utf8.offset(str, n + 1)
        return cut and str:sub(1, cut - 1) or str
    end
    local pd = PPStore.getPlayer(cid)
    local md = sellerData(pd)
    -- The storefront icon is picked from a fixed list of built-in icons (the app shows them as vector art).
    local icon = tostring(data.icon or '')
    if not SHOP_ICONS[icon] then icon = 'store' end
    md.shop = { name = clean(data.name, 30), tagline = clean(data.tagline, 60), icon = icon }
    PPStore.savePlayer(cid)
    PPLog.log('listing', source, ('set storefront "%s"'):format(md.shop.name), { citizen = cid })
    return { ok = true, market = PPMarket.stateFor(source, cid, pd) }
end)

lib.callback.register('as-postalprime:market:withdraw', function(source)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    local pd = PPStore.getPlayer(cid)
    local md = sellerData(pd)
    local amount = round2(md.balance or 0)
    if amount <= 0 then return { ok = false, error = T('err.market.noBalance') } end
    md.balance = 0
    PPStore.savePlayer(cid)
    PP.pay(source, amount)
    PPLog.log('sale', source, ('withdrew $%s of marketplace earnings'):format(amount), { citizen = cid })
    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.withdrawn', amount), type = 'success',
    })
    return { ok = true, market = PPMarket.stateFor(source, cid, pd) }
end)

-- Pays the sellers behind any marketplace lines of a collected order (called from PP.onCollected in shop.lua).
function PPMarket.payout(order)
    local credited = {}
    for _, it in ipairs(order.items) do
        if it.listingId and it.sellerCid then
            local gross = round2((it.price or 0) * (it.qty or 0))
            local net = round2(gross * (100 - (cfg().commissionPct or 10)) / 100)
            local pd = PPStore.getPlayer(it.sellerCid)
            local md = sellerData(pd)
            md.balance = round2((md.balance or 0) + net)
            md.earned = round2((md.earned or 0) + net)
            md.sold = (md.sold or 0) + (it.qty or 0)
            credited[it.sellerCid] = (credited[it.sellerCid] or 0) + net
            PPStats.bump('marketGross', gross)
            PPStats.bump('marketCommission', round2(gross - net))
            PPLog.log('sale', nil, ('%dx %s sold by %s for $%s ($%s after commission)'):format(it.qty, it.label, it.sellerName or '?', gross, net),
                { order = order.id, seller = it.sellerCid })
        end
    end
    for sellerCid, net in pairs(credited) do
        PPStore.savePlayer(sellerCid)
        PP.notifyCid(sellerCid, T('notif.sale.title'), T('notif.sale.body', round2(net)))
        local src = PP.source(sellerCid)
        if src then TriggerClientEvent('as-postalprime:client:updated', src) end
    end
end

return PPMarket
