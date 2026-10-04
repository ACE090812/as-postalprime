-- Home and business delivery: doorstep parcels, the courier-van drop, taking a parcel from a door.

local track = PP.track
local findCatalogItem = PP.findCatalogItem
local findLocker = PP.findLocker
local eachOrder = PP.eachOrder
local removeOrder = PP.removeOrder
local orderBoxSize = PP.orderBoxSize
local pushHistory = PP.pushHistory
local onlineSources = PP.onlineSources

-- ─── Home delivery ────────────────────────────────────────────────────────────
-- A delivered home order is just an active order with delivery == 'home' and ready == true, so the
-- parcels are derived from the saved player data - nothing extra to persist, and they survive
-- restarts. They stay until somebody takes them (no expiry).

local function homeParcelPayload(order)
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
        for _, o in ipairs(eachOrder(pd)) do
            if o.delivery == 'home' and o.ready and not o.collected and not o.expired and o.homeProperty then
                out[#out + 1] = homeParcelPayload(o)
            end
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
PP.homeParcelPayload = homeParcelPayload

function PP.dropHome(cid, order, byName)
    order.ready = true
    order.courier = nil
    if order.business then
        -- Business delivery: the box is dropped like a home one, then PP.completeBusiness (5s loop) moves the
        -- items into the job stash once the drop has had time to play out.
        local bc = Config.business or {}
        order.business.at = os.time() + (byName and (tonumber(bc.playerDropSeconds) or 3) or (tonumber(bc.vanDropSeconds) or 25))
    end
    order.boxSize = order.boxSize or orderBoxSize(order)
    if byName then order.deliveredBy = byName end
    if byName then PPStore.savePlayer(cid) else PPStore.markDirty(cid) end

    local payload = homeParcelPayload(order)
    if byName then payload.noAnim = true end
    TriggerClientEvent('as-postalprime:client:homeDrop', -1, payload)

    local src = onlineSources[cid]
    if src then
        TriggerClientEvent('as-postalprime:client:updated', src)
        PP.notifyOrder(src, order, T('notif.arrived.title'),
            byName and T('notif.arrived.byCourier', byName, order.homeProperty.label)
                or T('notif.arrived.byVan', order.homeProperty.label))
        if not order.business then
            TriggerClientEvent('as-postalprime:client:orderReady', src, order.homeProperty.coords, order.homeProperty.label)
        end
    end
end

-- ─── Business delivery ────────────────────────────────────────────────────────
-- A parcel sent with delivery = 'business' goes through the normal home-delivery machinery (courier board,
-- NPC van, waypoint at the door) but is not left for anyone to take: when the drop is done the items are put
-- into the business's ox_inventory stash and the employees are told.

local function stashDeposit(b, items)
    if GetResourceState('ox_inventory') ~= 'started' then return false, 'no_inventory' end
    local ox, st = exports.ox_inventory, b.stash or {}
    if type(st.id) ~= 'string' or st.id == '' then return false, 'no_stash' end
    if st.register then
        pcall(function()
            ox:RegisterStash(st.id, st.label or st.id, tonumber(st.slots) or 50, tonumber(st.weight) or 100000, st.owner or false, st.groups)
        end)
    end
    local added = {}
    local function rollback()
        for _, a in ipairs(added) do pcall(function() ox:RemoveItem(st.id, a.name, a.qty, a.metadata) end) end
    end
    for _, it in ipairs(items) do
        local entry = findCatalogItem(it.id)
        local name = entry and entry.item or it.item or it.id
        local can, ok = false, false
        pcall(function() can = ox:CanCarryItem(st.id, name, it.qty, it.metadata) end)
        if can then pcall(function() ok = ox:AddItem(st.id, name, it.qty, it.metadata) end) end
        if not ok then rollback() return false, can and 'error' or 'full' end
        added[#added + 1] = { name = name, qty = it.qty, metadata = it.metadata }
    end
    return true
end

local function toastJob(job, description, kind)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and PPBridge.getJob(src) == job then
            TriggerClientEvent('as-postalprime:toast', src, { title = T('app.name'), description = description, type = kind or 'success' })
        end
    end
end

function PP.completeBusiness(cid, pd, order)
    local b = order.business
    if not b or order.collected then return end
    local ok, why = stashDeposit(b, order.items)
    local label = order.homeProperty and order.homeProperty.label or 'business'
    if not ok then
        -- Nothing was added. Leave the box at the door so the staff can take it by hand, and say why.
        b.failed = true
        PPStore.savePlayer(cid)
        print(('[as-postalprime] business delivery %s: could not fill stash %s (%s); the box stays at the door'):format(tostring(order.parcelRef or order.id), tostring(b.stash and b.stash.id), tostring(why)))
        if b.job then toastJob(b.job, T('toast.businessFailed', label), 'error') end
        return
    end
    order.collected = true
    removeOrder(pd, order)
    pushHistory(pd, order)
    PPStore.savePlayer(cid)
    TriggerClientEvent('as-postalprime:client:homeRemove', -1, order.id)
    if order.parcel then TriggerEvent('as-postalprime:parcelCollected', cid, order.parcelRef, nil) end
    TriggerEvent('as-postalprime:businessDelivered', cid, order.parcelRef, b.job, b.stash and b.stash.id)
    if b.job then toastJob(b.job, T('toast.businessDelivered', label), 'success') end
    local src = onlineSources[cid]
    if src then TriggerClientEvent('as-postalprime:client:updated', src) end
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
    if byName or hadCourier then PPStore.savePlayer(cid) else PPStore.markDirty(cid) end

    local src = onlineSources[cid]
    if src then
        TriggerClientEvent('as-postalprime:client:updated', src)
        PP.notifyOrder(src, order, T('notif.ready.title'),
            byName and T('notif.ready.byCourier', byName, order.lockerLabel)
                or T('notif.ready.default', order.lockerLabel))
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
        for _, o in ipairs(eachOrder(pd)) do
            if o.id == orderId and o.delivery == 'home' then
                ownerCid, ownerPd, order = cid, pd, o
                break
            end
        end
        if order then break end
    end
    if not order or not order.ready or order.collected or order.expired or not order.homeProperty then return end
    if order.business and not order.business.failed then return end   -- goes straight to the stash, not for taking

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
    order.collectedAt = os.time()
    if takerCid ~= ownerCid then order.takenBy = PPBridge.getCharacterName(source) end
    removeOrder(ownerPd, order)
    pushHistory(ownerPd, order)
    PPStore.savePlayer(ownerCid)
    if takerCid == ownerCid then PP.rollDamaged(source, order) end
    PP.onCollected(ownerCid, order)

    if order.parcel then TriggerEvent('as-postalprime:parcelCollected', ownerCid, order.parcelRef, source) end

    TriggerClientEvent('as-postalprime:client:homeRemove', -1, order.id)

    TriggerClientEvent('as-postalprime:toast', source, {
        title = T('app.name'), description = T('toast.parcelCollected'), type = 'success',
    })

    local ownerSrc = onlineSources[ownerCid]
    if ownerSrc then
        TriggerClientEvent('as-postalprime:client:updated', ownerSrc)
        TriggerClientEvent('as-postalprime:client:orderReady:clear', ownerSrc)
        if takerCid == ownerCid then
            PP.notifyOrder(ownerSrc, order, T('notif.collected.title'),
                T('notif.homePickedUp.body', order.homeProperty.label))
        else
            PP.notifyOrder(ownerSrc, order, T('notif.homeTaken.title'),
                T('notif.homeTaken.body', order.homeProperty.label))
        end
    end
end)
