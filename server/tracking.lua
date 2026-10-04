-- Live order tracking: where an order is in its journey, an ETA, and (while a player courier has it loaded in their
-- van) the courier's position so the app can drop a moving blip on the map.

local track = PP.track

local COURIER_METRES_PER_SECOND = 11.0   -- ~40 km/h average once the van is moving

local function destOf(order)
    if order.delivery == 'home' then
        local hp = order.homeProperty
        if not hp then return nil end
        return { x = hp.coords.x, y = hp.coords.y, z = hp.coords.z, label = hp.label }
    end
    local l = PP.findLocker(order.lockerId)
    if not l then return nil end
    return { x = l.coords.x, y = l.coords.y, z = l.coords.z, label = order.lockerLabel or l.label }
end

lib.callback.register('as-postalprime:trackOrder', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' or type(data.orderId) ~= 'string' then return { ok = false } end
    local pd = PPStore.getPlayer(cid)
    local order = PP.findOrderById(pd, data.orderId)
    if not order or order.collected or order.expired then return { ok = true, stage = 'done' } end

    local now = os.time()
    local dest = destOf(order)
    if order.ready then return { ok = true, stage = 'ready', dest = dest } end

    local c = order.courier
    if not c then
        return { ok = true, stage = 'preparing', eta = math.max(0, order.readyAt - now), dest = dest }
    end
    if c.state ~= 'loaded' then
        return { ok = true, stage = c.state == 'board' and 'waiting' or 'collecting', dest = dest }
    end

    -- Loaded: the courier is driving it over.
    local out = { ok = true, stage = 'out', dest = dest }
    local csrc = c.cid and PP.source(c.cid)
    local ped = csrc and GetPlayerPed(csrc)
    if ped and ped ~= 0 and dest then
        local p = GetEntityCoords(ped)
        out.courier = { x = p.x, y = p.y, z = p.z }
        out.distance = #(p - vector3(dest.x, dest.y, dest.z))
        out.eta = math.ceil(out.distance / COURIER_METRES_PER_SECOND) + 5
    elseif c.deadline then
        out.eta = math.max(0, c.deadline - now)
    end
    return out
end)
