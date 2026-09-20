-- Player courier job (server). Loaded after server/main.lua, which provides the shared `PP` table.
--
-- Life of a home order with couriers on duty:
--   ready (prep done) -> 'board'   posted on the depot board
--   courier claims it -> 'claimed' courier must carry it from the depot pile to their rental vehicle
--   loaded in vehicle -> 'loaded'  timer running; courier carries it to the door and places it
--   placed at door    -> PP.dropHome(...) : the normal doorstep parcel, order delivered, courier paid
-- At any point the order can drop back to the NPC van (PP.dropHome with no courier name): nobody
-- claimed it in time, all couriers clocked off, the courier abandoned / disconnected / lost the
-- vehicle / ran far too late. Progress lives on the order itself (order.courier), so it survives
-- restarts - the sweep below simply notices there is no live run for it and sends the NPC.

PPCourier = {}

local function cfg() return Config.courier or {} end
local function enabled() return cfg().enabled == true end

local SIZE_RANK = { s = 1, m = 2, l = 3, xl = 4 }

local Duty    = {} -- [cid] = source           clocked on
local Rentals = {} -- [cid] = { def, plate, deposit, src, pending, expires, entity, netId, missing, farSince }
local Carry   = {} -- [cid] = { orderId, stage = 'pile' | 'door' }

-- ─── helpers ─────────────────────────────────────────────────────────────────

local function notify(src, desc, kind)
    if not src then return end
    TriggerClientEvent('as-postalprime:toast', src, {
        title = T('courier.name'), description = desc, type = kind or 'inform',
    })
end

local function refreshClient(src)
    if src then TriggerClientEvent('as-postalprime:courier:refresh', src) end
end

local function nearPoint(src, p, radius)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(p.x, p.y, p.z)) <= radius
end

local function cData(pd)
    pd.courier = pd.courier or { xp = 0, deliveries = 0, earned = 0 }
    pd.courier.xp = pd.courier.xp or 0
    return pd.courier
end

local function levelFor(xp)
    local lv = 1
    for i, need in ipairs(cfg().levels or { 0 }) do
        if xp >= need then lv = i end
    end
    return lv
end

local function batchFor(level)
    local b = cfg().batch or { 2 }
    return b[level] or b[#b] or 2
end

local function vehicleDef(key)
    for _, v in ipairs(cfg().vehicles or {}) do
        if v.key == key then return v end
    end
    return nil
end

local function unitsOf(size)
    return (cfg().units or {})[size] or 1
end

local function dutyCount()
    local n = 0
    for _ in pairs(Duty) do n = n + 1 end
    return n
end
PPCourier.dutyCount = dutyCount

local function isCourierJob(src)
    return PPBridge.getJob(src) == cfg().job
end

-- Resolves the calling player. Returns cid, or nil + an error string.
local function ctx(src, needDuty)
    if not enabled() then return nil, T('courier.err.off') end
    local cid = PP.track(src)
    if not cid then return nil, T('err.unavailable') end
    if not isCourierJob(src) then return nil, T('courier.err.notEmployed') end
    if needDuty and Duty[cid] ~= src then return nil, T('courier.err.clockOnFirst') end
    return cid
end

-- ─── orders ──────────────────────────────────────────────────────────────────

-- Where an order is going: a home door or a locker wall. nil = not something a courier can deliver.
local function destOf(order)
    if order.delivery == 'home' then
        local hp = order.homeProperty
        if not hp then return nil end
        return { kind = 'home', label = hp.label, coords = vector3(hp.coords.x, hp.coords.y, hp.coords.z) }
    end
    for _, l in ipairs(Config.lockers or {}) do
        if l.id == order.lockerId then
            return { kind = 'locker', label = order.lockerLabel or l.label, coords = vector3(l.coords.x, l.coords.y, l.coords.z) }
        end
    end
    return nil
end

local function findOrder(orderId)
    if type(orderId) ~= 'string' then return nil end
    for cid, pd in pairs(PPStore.players) do
        for _, o in ipairs(PP.eachOrder(pd)) do
            if o.id == orderId and destOf(o) then return cid, pd, o end
        end
    end
    return nil
end

-- Completes an order without a courier (NPC van for homes, plain "ready" for lockers) or with one (byName).
local function finishOrder(ownerCid, order, byName)
    if order.delivery == 'home' then
        PP.dropHome(ownerCid, order, byName)
    else
        PP.readyLocker(ownerCid, order, byName)
    end
end

local function sizeOf(order)
    return order.boxSize or PP.orderBoxSize(order)
end

local function doorPoint(order)
    return destOf(order).coords
end

local function depotDistance(order)
    local d = (Config.home and Config.home.depot) or cfg().depot.desk
    return #(doorPoint(order) - vector3(d.x, d.y, d.z))
end

-- Full pay for a delivery at this courier level (no lateness).
local function payFor(order, level)
    local p = cfg().pay or {}
    local km = depotDistance(order) / 1000.0
    local amt = (p.base or 0) + (p.perKm or 0) * km + ((p.size or {})[sizeOf(order)] or 0)
    amt = amt * (1 + ((p.levelBonusPct or 0) / 100.0) * (level - 1))
    return math.max(1, math.floor(amt + 0.5))
end

local function applyLate(full, lateSeconds)
    if lateSeconds <= 0 then return full end
    local p = cfg().pay or {}
    local steps = math.ceil(lateSeconds / math.max(1, p.lateStepSeconds or 30))
    local mult = math.max((p.minPct or 50) / 100.0, 1.0 - steps * (p.latePenaltyPct or 5) / 100.0)
    return math.max(1, math.floor(full * mult + 0.5))
end

local function limitSeconds(order, holding)
    local t = cfg().timer or {}
    return math.floor((t.baseSeconds or 120) + (t.perMeter or 0.12) * depotDistance(order)
        + (t.perExtraParcel or 90) * math.max(0, holding - 1))
end

-- Orders this courier has claimed (state claimed or loaded), oldest claim first.
local function claimsOf(courierCid)
    local out = {}
    for ownerCid, pd in pairs(PPStore.players) do
        for _, o in ipairs(PP.eachOrder(pd)) do
            if o.courier and o.courier.cid == courierCid and o.courier.state ~= 'board' then
                out[#out + 1] = { owner = ownerCid, order = o }
            end
        end
    end
    table.sort(out, function(a, b) return (a.order.courier.claimedAt or 0) < (b.order.courier.claimedAt or 0) end)
    return out
end

local function usedUnits(courierCid)
    local n = 0
    for _, c in ipairs(claimsOf(courierCid)) do n = n + unitsOf(sizeOf(c.order)) end
    return n
end

-- Sends an order back to the NPC van (also clears anything the courier was carrying for it).
local function toNpc(ownerCid, order, why)
    local c = order.courier
    local courierCid = c and c.cid
    local csrc = courierCid and Duty[courierCid] or nil
    if courierCid and Carry[courierCid] and Carry[courierCid].orderId == order.id then
        Carry[courierCid] = nil
        if csrc then TriggerClientEvent('as-postalprime:courier:carryClear', csrc) end
    end
    if csrc and why then notify(csrc, why, 'error') end
    finishOrder(ownerCid, order)
    refreshClient(csrc)
end

local function releaseClaims(courierCid, why)
    for _, c in ipairs(claimsOf(courierCid)) do toNpc(c.owner, c.order, why) end
end

-- ─── keys / rental vehicle ───────────────────────────────────────────────────

local function giveKey(src, r)
    if GetResourceState('acestudios_vehiclekeys') == 'started' then
        local ok, res = pcall(function() return exports.acestudios_vehiclekeys:GiveKey(src, r.plate, r.def.label) end)
        return ok and res ~= false
    end
    if GetResourceState('qbx_vehiclekeys') == 'started' and r.entity and DoesEntityExist(r.entity) then
        local ok = pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, r.entity) end)
        return ok
    end
    return true -- no key system: nothing to hand over
end

local function takeKey(src, r)
    if not src then return end
    if GetResourceState('acestudios_vehiclekeys') == 'started' then
        pcall(function() exports.acestudios_vehiclekeys:TakeKey(src, r.plate) end)
    end
end

-- Ends a rental. refund = give the deposit back. The vehicle is deleted either way.
local function endRental(cid, refund, message, kind)
    local r = Rentals[cid]
    if not r then return end
    Rentals[cid] = nil

    local pd = PPStore.getPlayer(cid)
    cData(pd).rental = nil
    PPStore.savePlayer(cid)

    if r.entity and DoesEntityExist(r.entity) then DeleteEntity(r.entity) end

    local src = r.src
    if src and GetPlayerName(src) then
        takeKey(src, r)
        if refund then PP.pay(src, type(refund) == 'number' and refund or (r.deposit or 0)) end
        if message then notify(src, message, kind) end
        refreshClient(src)
    end
    if Carry[cid] then Carry[cid] = nil end
end

local function forfeit(cid, message)
    releaseClaims(cid, T('courier.toast.rentalGone'))
    endRental(cid, false, message, 'error')
end

-- ─── state for the client ────────────────────────────────────────────────────

local function claimPayload(c, level)
    local o = c.order
    local st = o.courier
    local secondsLeft = (st.state == 'loaded' and st.deadline) and (st.deadline - os.time()) or nil
    local dest = destOf(o)
    return {
        orderId = o.id, label = dest.label, kind = dest.kind, size = sizeOf(o), state = st.state,
        secondsLeft = secondsLeft,
        coords = { x = dest.coords.x, y = dest.coords.y, z = dest.coords.z },
        pay = payFor(o, level),
    }
end

local function buildState(src, cid)
    local pd = PPStore.getPlayer(cid)
    local cd = cData(pd)

    -- A rental left over from a server/resource restart (the vehicle is gone): give the deposit back.
    if cd.rental and not Rentals[cid] then
        local dep = cd.rental.deposit or 0
        cd.rental = nil
        PPStore.savePlayer(cid)
        if dep > 0 then
            PP.pay(src, dep)
            notify(src, T('courier.toast.rentalClosed', dep), 'success')
        end
    end

    local level = levelFor(cd.xp)
    local levels = cfg().levels or { 0 }
    local vehicles = {}
    for _, v in ipairs(cfg().vehicles or {}) do
        vehicles[#vehicles + 1] = {
            key = v.key, label = v.label, model = v.model, level = v.level, capacity = v.capacity,
            maxBox = v.maxBox, deposit = v.deposit, unlocked = level >= v.level,
        }
    end

    local claims = {}
    for _, c in ipairs(claimsOf(cid)) do claims[#claims + 1] = claimPayload(c, level) end

    local r = Rentals[cid]
    local rental = nil
    if r and not r.pending then
        rental = {
            key = r.def.key, label = r.def.label, plate = r.plate, netId = r.netId,
            capacity = r.def.capacity, maxBox = r.def.maxBox, deposit = r.deposit,
        }
    end

    local boardCount = 0
    for _, opd in pairs(PPStore.players) do
        for _, o in ipairs(PP.eachOrder(opd)) do
            if o.courier and o.courier.state == 'board' then boardCount = boardCount + 1 end
        end
    end

    local carry = Carry[cid]
    return {
        ok = true, isCourier = true, onDuty = Duty[cid] == src,
        level = level, xp = cd.xp, levelXp = levels[level] or 0, nextXp = levels[level + 1],
        deliveries = cd.deliveries or 0, earned = cd.earned or 0,
        batch = batchFor(level), boardCount = boardCount,
        vehicles = vehicles, rental = rental, claims = claims,
        usedUnits = usedUnits(cid),
        carry = carry and { orderId = carry.orderId, stage = carry.stage } or nil,
    }
end

lib.callback.register('as-postalprime:courier:state', function(source)
    if not enabled() then return { ok = false, enabled = false } end
    local cid = PP.track(source)
    if not cid then return { ok = false } end
    if not isCourierJob(source) then
        -- Not (or no longer) a courier: make sure nothing stays half-open.
        if Duty[cid] then Duty[cid] = nil end
        return { ok = true, isCourier = false }
    end
    return buildState(source, cid)
end)

-- ─── clock on / off ──────────────────────────────────────────────────────────

lib.callback.register('as-postalprime:courier:duty', function(source, on)
    local cid, err = ctx(source)
    if not cid then return { ok = false, error = err } end
    if not nearPoint(source, cfg().depot.desk, 15.0) then
        return { ok = false, error = T('courier.err.atDesk') }
    end

    if on then
        Duty[cid] = source
        notify(source, T('courier.toast.clockedOn'), 'success')
    else
        if Rentals[cid] then
            return { ok = false, error = T('courier.err.clockOffVehicle') }
        end
        releaseClaims(cid, nil)
        Carry[cid] = nil
        Duty[cid] = nil
        notify(source, T('courier.toast.clockedOff'), 'inform')
    end
    return { ok = true }
end)

-- ─── vehicle rental ──────────────────────────────────────────────────────────

lib.callback.register('as-postalprime:courier:rent', function(source, key)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    if not nearPoint(source, cfg().depot.desk, 15.0) then
        return { ok = false, error = T('courier.err.atDesk') }
    end
    if Rentals[cid] then return { ok = false, error = T('courier.err.haveVehicle') } end

    local def = vehicleDef(key)
    if not def then return { ok = false, error = T('courier.err.unknownVehicle') } end

    local pd = PPStore.getPlayer(cid)
    local level = levelFor(cData(pd).xp)
    if level < def.level then
        return { ok = false, error = T('courier.err.needLevel', def.level, def.label) }
    end

    if not PP.charge(source, def.deposit) then
        return { ok = false, error = T('courier.err.noCashDeposit', def.deposit) }
    end

    local plate = ('PP%05d'):format(math.random(0, 99999))
    Rentals[cid] = { def = def, plate = plate, deposit = def.deposit, src = source, pending = true, expires = os.time() + 45 }
    cData(pd).rental = { deposit = def.deposit, key = def.key, at = os.time() }
    PPStore.savePlayer(cid)

    return { ok = true, model = def.model, label = def.label, plate = plate, deposit = def.deposit }
end)

-- Called by the client once it has spawned the rental (a networked vehicle at the depot).
lib.callback.register('as-postalprime:courier:registerVehicle', function(source, netId)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    local r = Rentals[cid]
    if not r or not r.pending then return { ok = false, error = T('courier.err.noPendingRental') } end
    netId = tonumber(netId)
    if not netId then return { ok = false, error = T('courier.err.badVehicle') } end

    -- The entity can take a moment to exist server-side after the client creates it.
    local ent = 0
    for _ = 1, 15 do
        ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then break end
        ent = 0
        Wait(200)
    end
    if ent == 0 then return { ok = false, error = T('courier.err.noSpawn') } end
    if GetEntityModel(ent) ~= joaat(r.def.model) then return { ok = false, error = T('courier.err.wrongVehicle') } end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(ent)) > 80.0 then
        return { ok = false, error = T('courier.err.vehicleFar') }
    end

    r.entity, r.netId, r.pending = ent, netId, false
    pcall(SetVehicleNumberPlateText, ent, r.plate)

    if not giveKey(source, r) then
        -- Couldn't hand over the key (inventory full?) - undo the rental cleanly.
        endRental(cid, true, T('courier.toast.keyFailed'), 'error')
        return { ok = false, error = T('courier.err.noKey') }
    end
    return { ok = true, plate = r.plate }
end)

-- Client couldn't spawn the vehicle (all bays busy / model failed): refund the pending rental.
lib.callback.register('as-postalprime:courier:cancelRent', function(source)
    local cid = PP.track(source)
    local r = cid and Rentals[cid]
    if not r or not r.pending then return { ok = false } end
    endRental(cid, true, T('courier.toast.rentCancelled'), 'inform')
    return { ok = true }
end)

-- Damage on a rental as a percentage 0-100 (engine + body health averaged), read server-side.
local function damagePercent(ent)
    local ok, engine, body = pcall(function() return GetVehicleEngineHealth(ent), GetVehicleBodyHealth(ent) end)
    if not ok or not engine or not body then return 0 end
    engine = math.max(0.0, math.min(1000.0, engine))
    body = math.max(0.0, math.min(1000.0, body))
    return math.floor((1.0 - (engine + body) / 2000.0) * 100.0 + 0.5)
end

lib.callback.register('as-postalprime:courier:return', function(source)
    local cid = PP.track(source)
    local r = cid and Rentals[cid]
    if not r or r.pending then return { ok = false, error = T('courier.err.noVehicleOut') } end

    local dep = cfg().depot
    if not r.entity or not DoesEntityExist(r.entity) then
        return { ok = false, error = T('courier.err.vehicleMissing') }
    end
    if #(GetEntityCoords(r.entity) - dep.returnPoint) > (dep.returnRadius or 40.0) then
        return { ok = false, error = T('courier.err.bringBack') }
    end
    if not nearPoint(source, dep.desk, 60.0) then
        return { ok = false, error = T('courier.err.atDepot') }
    end

    local had = #claimsOf(cid)
    releaseClaims(cid, nil)

    local deposit = r.deposit or 0
    local dmg = damagePercent(r.entity)
    local dc = cfg().damage or {}
    local deduct = 0
    if dc.enabled and dmg > (dc.tolerance or 0) then
        deduct = math.min(deposit, math.floor(deposit * (dmg / 100.0) * ((dc.maxDeductPct or 100) / 100.0) + 0.5))
    end
    local back = deposit - deduct
    if deduct > 0 then
        endRental(cid, back, T('courier.toast.returnedDamaged', dmg, deduct, back), 'inform')
    else
        endRental(cid, back, T('courier.toast.returned', back), 'success')
    end
    if had > 0 then
        notify(source, T('courier.toast.parcelsToNpc'), 'inform')
    end
    return { ok = true }
end)

-- The client saw the rental blow up.
RegisterNetEvent('as-postalprime:courier:vehicleLost')
AddEventHandler('as-postalprime:courier:vehicleLost', function()
    local src = source
    local cid = PP.track(src)
    local r = cid and Rentals[cid]
    if not r or r.pending or r.src ~= src then return end
    forfeit(cid, T('courier.toast.vehicleDestroyed'))
end)

-- ─── board / claiming ────────────────────────────────────────────────────────

-- Why this courier can't take an order right now (nil = they can).
local function claimBlocker(cid, order)
    local r = Rentals[cid]
    if not r or r.pending then return T('courier.block.rentFirst') end
    local level = levelFor(cData(PPStore.getPlayer(cid)).xp)
    local size = sizeOf(order)
    if (SIZE_RANK[size] or 1) > (SIZE_RANK[r.def.maxBox] or 1) then return T('courier.block.tooBig') end
    if usedUnits(cid) + unitsOf(size) > r.def.capacity then return T('courier.block.noRoom') end
    if #claimsOf(cid) >= batchFor(level) then return T('courier.block.batch', batchFor(level)) end
    return nil
end

lib.callback.register('as-postalprime:courier:board', function(source)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    local level = levelFor(cData(PPStore.getPlayer(cid)).xp)

    local list = {}
    for ownerCid, pd in pairs(PPStore.players) do
        for _, o in ipairs(PP.eachOrder(pd)) do
            if o.courier and o.courier.state == 'board' and destOf(o) and (ownerCid ~= cid or cfg().allowOwnOrders == true) then
                local size = sizeOf(o)
                list[#list + 1] = {
                    orderId = o.id, label = destOf(o).label, kind = destOf(o).kind, size = size,
                    km = math.floor(depotDistance(o) / 100.0 + 0.5) / 10.0,
                    pay = payFor(o, level), boardedAt = o.courier.boardedAt or 0,
                    blocked = claimBlocker(cid, o),
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.boardedAt < b.boardedAt end)
    return { ok = true, orders = list }
end)

lib.callback.register('as-postalprime:courier:claim', function(source, orderId)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    if not nearPoint(source, cfg().depot.desk, 15.0) then
        return { ok = false, error = T('courier.err.atDesk') }
    end

    local ownerCid, _, o = findOrder(orderId)
    if not o or not o.courier or o.courier.state ~= 'board' then
        return { ok = false, error = T('courier.err.noLongerAvailable') }
    end
    if ownerCid == cid and cfg().allowOwnOrders ~= true then
        return { ok = false, error = T('courier.err.ownOrder') }
    end
    local blocker = claimBlocker(cid, o)
    if blocker then return { ok = false, error = blocker } end

    o.courier.state = 'claimed'
    o.courier.cid = cid
    o.courier.claimedAt = os.time()
    PPStore.savePlayer(ownerCid)

    local osrc = PP.source(ownerCid)
    if osrc then
        TriggerClientEvent('as-postalprime:client:updated', osrc)
        PP.notify(osrc, T('courier.notif.claimed.title'), T('courier.notif.claimed.body'))
    end
    return { ok = true }
end)

-- Put a claimed (not yet loaded) order back on the board.
lib.callback.register('as-postalprime:courier:unclaim', function(source, orderId)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    local ownerCid, _, o = findOrder(orderId)
    local c = o and o.courier
    if not c or c.cid ~= cid or c.state ~= 'claimed' then
        return { ok = false, error = T('courier.err.putBackLoaded') }
    end
    if Carry[cid] and Carry[cid].orderId == orderId then
        return { ok = false, error = T('courier.err.putDownFirst') }
    end
    c.state, c.cid, c.claimedAt = 'board', nil, nil
    PPStore.savePlayer(ownerCid)
    return { ok = true }
end)

-- Hand every parcel on this run back to the NPC courier (keeps the vehicle + shift).
lib.callback.register('as-postalprime:courier:abandon', function(source)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    local n = #claimsOf(cid)
    releaseClaims(cid, nil)
    Carry[cid] = nil
    TriggerClientEvent('as-postalprime:courier:carryClear', source)
    if n > 0 then notify(source, T('courier.toast.runAbandoned'), 'inform') end
    return { ok = true }
end)

-- ─── carrying: pile -> vehicle -> door ───────────────────────────────────────

lib.callback.register('as-postalprime:courier:pickPile', function(source)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    if not nearPoint(source, cfg().depot.pile, 15.0) then
        return { ok = false, error = T('courier.err.atPile') }
    end
    if Carry[cid] then return { ok = false, error = T('courier.err.alreadyCarrying') } end

    for _, c in ipairs(claimsOf(cid)) do
        if c.order.courier.state == 'claimed' then
            Carry[cid] = { orderId = c.order.id, stage = 'pile' }
            return { ok = true, orderId = c.order.id, size = sizeOf(c.order), label = destOf(c.order).label }
        end
    end
    return { ok = false, error = T('courier.err.noParcelsLeft') }
end)

local function nearRentalVehicle(src, cid)
    local r = Rentals[cid]
    if not r or r.pending or not r.entity or not DoesEntityExist(r.entity) then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(r.entity)) <= (cfg().loadDistance or 9.0)
end

lib.callback.register('as-postalprime:courier:load', function(source, orderId)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    local carry = Carry[cid]
    if not carry or carry.stage ~= 'pile' or carry.orderId ~= orderId then
        return { ok = false, error = T('courier.err.notCarrying') }
    end
    if not nearRentalVehicle(source, cid) then return { ok = false, error = T('courier.err.closerVehicle') } end

    local ownerCid, _, o = findOrder(orderId)
    local c = o and o.courier
    if not c or c.cid ~= cid or c.state ~= 'claimed' then
        Carry[cid] = nil
        return { ok = false, error = T('courier.err.notYours') }
    end

    c.state = 'loaded'
    c.loadedAt = os.time()
    c.deadline = c.loadedAt + limitSeconds(o, #claimsOf(cid))
    Carry[cid] = nil
    PPStore.savePlayer(ownerCid)

    local osrc = PP.source(ownerCid)
    if osrc then
        TriggerClientEvent('as-postalprime:client:updated', osrc)
        PP.notify(osrc, T('courier.notif.out.title'), destOf(o).kind == 'locker'
            and T('courier.notif.out.locker')
            or T('courier.notif.out.home'))
    end
    return { ok = true }
end)

-- Take a loaded parcel back out of the vehicle to carry to the door.
lib.callback.register('as-postalprime:courier:takeFromVehicle', function(source, orderId)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    if Carry[cid] and Carry[cid].stage == 'pile' then return { ok = false, error = T('courier.err.loadFirst') } end
    if not nearRentalVehicle(source, cid) then return { ok = false, error = T('courier.err.closerVehicle') } end

    local _, _, o = findOrder(orderId)
    local c = o and o.courier
    if not c or c.cid ~= cid or c.state ~= 'loaded' then return { ok = false, error = T('courier.err.notLoaded') } end

    Carry[cid] = { orderId = orderId, stage = 'door' }
    local dest = destOf(o)
    return { ok = true, size = sizeOf(o), label = dest.label, kind = dest.kind,
        coords = { x = dest.coords.x, y = dest.coords.y, z = dest.coords.z } }
end)

-- The client put the parcel down / it got dropped (entered a vehicle, died, etc.).
RegisterNetEvent('as-postalprime:courier:dropCarry')
AddEventHandler('as-postalprime:courier:dropCarry', function()
    local cid = PP.track(source)
    if cid then Carry[cid] = nil end
end)

lib.callback.register('as-postalprime:courier:deliver', function(source, orderId)
    local cid, err = ctx(source, true)
    if not cid then return { ok = false, error = err } end
    local carry = Carry[cid]
    if not carry or carry.stage ~= 'door' or carry.orderId ~= orderId then
        return { ok = false, error = T('courier.err.notCarrying') }
    end

    local ownerCid, _, o = findOrder(orderId)
    local c = o and o.courier
    if not c or c.cid ~= cid or c.state ~= 'loaded' then
        Carry[cid] = nil
        return { ok = false, error = T('courier.err.notYours') }
    end
    if not nearPoint(source, doorPoint(o), cfg().deliverDistance or 12.0) then
        return { ok = false, error = destOf(o).kind == 'locker' and T('courier.err.farLocker') or T('courier.err.farDoor') }
    end

    local pd = PPStore.getPlayer(cid)
    local cd = cData(pd)
    local levelBefore = levelFor(cd.xp)

    local late = math.max(0, os.time() - (c.deadline or os.time()))
    local full = payFor(o, levelBefore)
    local amount = applyLate(full, late)

    local xpc = cfg().xp or {}
    local gain = (xpc.base or 20) + (xpc.perSizeRank or 5) * (SIZE_RANK[sizeOf(o)] or 1)
        + (late == 0 and (xpc.onTimeBonus or 10) or 0)

    local name = PPBridge.getCharacterName(source)
    finishOrder(ownerCid, o, name) -- home: box appears at the door; locker: order becomes ready. Customer notified.
    PP.pay(source, amount)

    cd.xp = cd.xp + gain
    cd.deliveries = (cd.deliveries or 0) + 1
    cd.earned = (cd.earned or 0) + amount
    PPStore.savePlayer(cid)
    Carry[cid] = nil

    local levelAfter = levelFor(cd.xp)
    return { ok = true, pay = amount, full = full, late = late, xp = gain, level = levelAfter, levelUp = levelAfter > levelBefore }
end)

-- ─── sweep: fallbacks, abandonment, job changes ──────────────────────────────

local function sweep()
    local now = os.time()
    local job = cfg().job

    -- Couriers who left / lost the job.
    for cid, src in pairs(Duty) do
        if not GetPlayerName(src) then
            Duty[cid] = nil
        elseif PPBridge.getJob(src) ~= job then
            Duty[cid] = nil
            releaseClaims(cid, nil)
            Carry[cid] = nil
            notify(src, T('courier.toast.noLongerCourier'), 'error')
            refreshClient(src)
        end
    end

    -- Rentals: unregistered ones time out; vehicles that vanished or got left behind forfeit.
    for cid, r in pairs(Rentals) do
        if r.pending then
            if now > r.expires then endRental(cid, true, T('courier.toast.rentalTimedOut'), 'inform') end
        else
            if not r.entity or not DoesEntityExist(r.entity) then
                r.missing = (r.missing or 0) + 1
                if r.missing >= 3 then forfeit(cid, T('courier.toast.vehicleLost')) end
            else
                r.missing = 0
                local src = r.src
                local ped = src and GetPlayerPed(src) or nil
                if ped and ped ~= 0 then
                    if #(GetEntityCoords(ped) - GetEntityCoords(r.entity)) > (cfg().abandonDistance or 500.0) then
                        r.farSince = r.farSince or now
                        if now - r.farSince > (cfg().abandonSeconds or 300) then
                            forfeit(cid, T('courier.toast.vehicleAbandoned'))
                        end
                    else
                        r.farSince = nil
                    end
                end
            end
        end
    end

    -- Orders: anything with no live courier behind it (or out of time) goes to the NPC van.
    local couriers = dutyCount()
    for ownerCid, pd in pairs(PPStore.players) do
        for _, o in ipairs(PP.eachOrder(pd)) do
        local c = o.courier
        if c and not o.ready and not o.collected and not o.expired then
            if c.state == 'board' then
                if couriers == 0 then
                    toNpc(ownerCid, o)
                elseif now - (c.boardedAt or now) > (cfg().claimSeconds or 600) then
                    toNpc(ownerCid, o)
                end
            else
                if not c.cid or not Duty[c.cid] or not Rentals[c.cid] then
                    toNpc(ownerCid, o, T('courier.toast.runCancelled'))
                elseif c.state == 'claimed' and now - (c.claimedAt or now) > (cfg().holdSeconds or 900) then
                    toNpc(ownerCid, o, T('courier.toast.tooSlowLoad'))
                elseif c.state == 'loaded' and c.deadline and now > c.deadline + (cfg().overdueSeconds or 600) then
                    toNpc(ownerCid, o, T('courier.toast.tooLate'))
                end
            end
        end
        end
    end
end

CreateThread(function()
    while true do
        Wait(5000)
        if enabled() then
            local ok, err = pcall(sweep)
            if not ok then print(('[as-postalprime] courier sweep error: %s'):format(tostring(err))) end
        end
    end
end)

-- Config.courier.parcelDeliveries: true / false, or { enabled, ['resource-name'] = bool, other = bool } to
-- choose per sending resource (order.parcelSource, e.g. 'as-passport', 'as-drivingschool').
local function parcelAllowed(order)
    local pd = cfg().parcelDeliveries
    if pd == true then return true end
    if type(pd) ~= 'table' or pd.enabled == false then return false end
    local v = pd[order.parcelSource or '']
    if v ~= nil then return v == true end
    return pd.other ~= false
end

-- Called from server/main.lua when a home order's prep time is up. true = the order is now on the
-- board (main.lua then leaves it alone); false = no couriers on duty, NPC van goes.
function PPCourier.tryBoard(cid, order)
    if not enabled() or dutyCount() == 0 then return false end
    local dest = destOf(order)
    if not dest then return false end
    if dest.kind == 'locker' and cfg().lockerDeliveries ~= true then return false end
    -- Parcels sent by other resources (passport, licence replacement...) only board when Config.courier.parcelDeliveries allows it.
    if order.parcel and not parcelAllowed(order) then return false end
    order.boxSize = PP.orderBoxSize(order)
    order.courier = { state = 'board', boardedAt = os.time() }
    PPStore.savePlayer(cid)

    local src = PP.source(cid)
    if src then
        TriggerClientEvent('as-postalprime:client:updated', src)
        PP.notify(src, T('courier.notif.waiting.title'),
            (order.parcel and T('courier.notif.waiting.parcel', dest.label) or T('courier.notif.waiting.order', dest.label)))
    end
    for _, csrc in pairs(Duty) do
        notify(csrc, T('courier.toast.newOrder'), 'inform')
        refreshClient(csrc)
    end
    return true
end

-- ─── lifecycle ───────────────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    for cid, dsrc in pairs(Duty) do
        if dsrc == src then
            Duty[cid] = nil
            Carry[cid] = nil
            releaseClaims(cid, nil)
        end
    end
    -- Disconnecting with a rental = the deposit is forfeited.
    for cid, r in pairs(Rentals) do
        if r.src == src then endRental(cid, false) end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for cid in pairs(Rentals) do
        local r = Rentals[cid]
        -- Stopping the resource isn't the courier's fault: give the deposit back.
        if r then endRental(cid, true, T('courier.toast.restarted'), 'inform') end
    end
end)

-- Admin helper for placing the depot points: /ppcoords prints + copies your exact vector4.
lib.addCommand('ppcoords', { help = T('cmd.ppcoords'), restricted = 'group.admin' }, function(source)
    TriggerClientEvent('as-postalprime:courier:printCoords', source)
end)

return PPCourier
