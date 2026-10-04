-- API for other resources: createParcel / getParcels / getDeliveryInfo / getLockers exports.

local findLocker = PP.findLocker
local eachOrder = PP.eachOrder
local homeTravelSeconds = PP.homeTravelSeconds
local newCode, newOrderId = PP.newCode, PP.newOrderId
local onlineSources = PP.onlineSources

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
--   delivery = 'business' + dropoff = { key, label, job, coords, stash } delivers to a business and fills its stash (see README).
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

local function createParcel(cid, parcel)
    if type(cid) ~= 'string' or type(parcel) ~= 'table' or type(parcel.items) ~= 'table' or #parcel.items == 0 then
        return false, 'bad_request'
    end
    -- delivery = 'home' + propertyKey (one of exports['as-postalprime']:getHomeProperties(cid)) puts the box at a
    -- front door instead of a locker. hidden = true keeps the order out of the phone app and widget and
    -- silences its phone notifications (used by the parts site, which shows its own tracking).
    local isBusiness = parcel.delivery == 'business'
    local isHome = parcel.delivery == 'home' or isBusiness
    local locker, property, business = nil, nil, nil
    if isBusiness then
        -- delivery = 'business' + dropoff = { key, label, job, coords = {x,y,z,w}, stash = { id, label, slots, weight, register } }:
        -- a courier (player or NPC van) takes it to those coords and the items then go into that stash. The caller
        -- supplies the destination, so only trusted server resources should ever call this.
        if not (Config.business and Config.business.enabled) then return false, 'business_unavailable' end
        local d = parcel.dropoff
        if type(d) ~= 'table' or type(d.coords) ~= 'table' or type(d.stash) ~= 'table' or type(d.stash.id) ~= 'string' or d.stash.id == '' then
            return false, 'bad_dropoff'
        end
        local x, y, z = tonumber(d.coords.x), tonumber(d.coords.y), tonumber(d.coords.z)
        if not (x and y and z) then return false, 'bad_dropoff' end
        local label = tostring(d.label or d.key or 'Business'):sub(1, 60)
        property = { key = 'biz:' .. tostring(d.key or d.job or label):sub(1, 40), label = label, address = label,
                     coords = { x = x, y = y, z = z, w = tonumber(d.coords.w) or 0.0 } }
        business = { job = d.job and tostring(d.job) or nil,
                     stash = { id = d.stash.id, label = d.stash.label, slots = d.stash.slots, weight = d.stash.weight,
                               owner = d.stash.owner, groups = d.stash.groups, register = d.stash.register == true } }
    elseif isHome then
        if not (Config.home and Config.home.enabled) or not PPHousing.available() then return false, 'home_unavailable' end
        property = PPHousing.resolve(cid, tostring(parcel.propertyKey or ''))
        if not property then return false, 'bad_property' end
    else
        locker = findLocker(parcel.lockerId)
        if not locker then return false, 'bad_locker' end
    end

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
    if isHome then prep = prep + homeTravelSeconds(property.coords) end
    local expire = tonumber(parcel.expireSeconds) or Config.order.expireSecondsAfterReady or 1800
    local order = {
        id = newOrderId(), items = items,
        lockerId = isHome and ('home:' .. property.key) or locker.id,
        lockerLabel = isHome and T('order.homeLabel', property.label) or locker.label,
        delivery = isHome and 'home' or 'locker',
        homeProperty = property, business = business,
        itemsTotal = 0, deliveryFee = 0, total = 0,
        placedAt = now, readyAt = now + prep,
        expiresAt = (not isHome) and (now + prep + expire) or nil, expireSeconds = expire,
        ready = false, collected = false, expired = false, code = newCode(),
        parcel = true, hidden = parcel.hidden == true or nil,
        parcelSource = caller, parcelRef = parcel.ref, sender = parcel.sender and tostring(parcel.sender):sub(1, 60) or nil,
    }
    pd.parcels[#pd.parcels + 1] = order
    PPStore.savePlayer(cid)

    local src = onlineSources[cid]
    if src then TriggerClientEvent('as-postalprime:client:updated', src) end
    return true, nil, order.id
end

exports('createParcel', createParcel)
PP.createParcel = createParcel

-- ─── Status for other resources (the parts site tracks its orders with these) ────────────────
-- getParcels(cid, refPrefix) -> list of parcels sent with createParcel (in flight and recent), newest first.
--   { id, ref, status, delivery, lockerId, lockerLabel, code, placedAt, readyAt, expiresAt, courier, deliveredBy }
--   status: preparing | waiting | collecting | out | ready | delivered | collected | expired
--   timestamps are unix seconds. code is only given while a locker order is ready to collect.
local function parcelStatus(o)
    if o.expired then return 'expired' end
    if o.collected then return 'collected' end
    if o.ready then return o.delivery == 'home' and 'delivered' or 'ready' end
    local c = o.courier and o.courier.state or nil
    if c == 'board' then return 'waiting' end
    if c == 'claimed' then return 'collecting' end
    if c == 'loaded' then return 'out' end
    return 'preparing'
end

local function describeParcel(o)
    local status = parcelStatus(o)
    local courierName = nil
    if o.courier and o.courier.cid and status ~= 'waiting' then
        local csrc = onlineSources[o.courier.cid]
        if csrc then
            local ok, n = pcall(PPBridge.getCharacterName, csrc)
            if ok then courierName = n end
        end
    end
    return {
        id = o.id, ref = o.parcelRef, status = status, delivery = o.delivery or 'locker',
        lockerId = o.lockerId, lockerLabel = o.lockerLabel,
        code = (status == 'ready') and o.code or nil,
        placedAt = o.placedAt, readyAt = o.readyAt, expiresAt = o.expiresAt,
        courier = courierName, deliveredBy = o.deliveredBy,
    }
end

exports('getParcels', function(cid, refPrefix)
    if type(cid) ~= 'string' then return {} end
    local pd = PPStore.getPlayer(cid)
    local out = {}
    local function add(o)
        if not o.parcel or o.parcelRef == nil then return end
        if refPrefix and tostring(o.parcelRef):sub(1, #refPrefix) ~= refPrefix then return end
        out[#out + 1] = describeParcel(o)
    end
    for _, o in ipairs(eachOrder(pd)) do add(o) end
    for _, o in ipairs(pd.history or {}) do add(o) end
    table.sort(out, function(a, b) return (a.placedAt or 0) > (b.placedAt or 0) end)
    return out
end)

-- Where a character can have a parcel sent: { lockers = { {id,label} }, home = { enabled, fee, properties = { {key,label,address} } } }
exports('getDeliveryInfo', function(cid)
    local lockers = {}
    for _, l in ipairs(Config.lockers) do lockers[#lockers + 1] = { id = l.id, label = l.label } end
    local homeOn = (Config.home and Config.home.enabled and PPHousing.available()) and true or false
    local props = {}
    if homeOn and type(cid) == 'string' then
        for _, p in ipairs(PPHousing.list(cid)) do props[#props + 1] = { key = p.key, label = p.label, address = p.address } end
    end
    return { lockers = lockers, home = { enabled = homeOn, fee = (Config.home and Config.home.fee) or 0, properties = props },
             business = { enabled = (Config.business and Config.business.enabled) and true or false } }
end)
