-- Home delivery (client).
-- * Doorstep parcels: every parcel the server says exists is spawned as a local box object when you
--   walk within range of it, with a "Take Parcel" target. They stay until somebody takes them.
-- * Courier: when a parcel is dropped and you're within Config.home.animateRange of the door, a van
--   drives up the road, the courier walks the box to the door, then drives off. If any step can't
--   be done (no road nodes streamed in, model missing...) it's skipped and the box just appears.
-- All entities here are local (non-networked); each nearby client runs its own copy of the sequence.

local parcels = {}    -- [orderId] = { data = {orderId, model, coords, label}, entity = obj|nil }
local animating = {}  -- [orderId] = true while the courier sequence is playing (box held back until it ends)

local function cfg() return Config.home or {} end

-- ─── Doorstep boxes ──────────────────────────────────────────────────────────

local function despawnBox(p)
    if not p or not p.entity then return end
    if DoesEntityExist(p.entity) then
        PPTarget.removeEntity(p.entity)
        DeleteEntity(p.entity)
    end
    p.entity = nil
end

local function spawnBox(orderId, p)
    if p.entity and DoesEntityExist(p.entity) then return end

    local hash = joaat(p.data.model or 'asparcel_m')
    if not IsModelValid(hash) then hash = joaat('asparcel_m') end
    if not IsModelValid(hash) then return end
    if not pcall(lib.requestModel, hash, 5000) then return end

    local c = p.data.coords
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local obj = CreateObject(hash, c.x, c.y, c.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 or not DoesEntityExist(obj) then return end

    SetEntityHeading(obj, c.w or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    p.entity = obj

    PPTarget.addEntity(
        obj, 'as-postalprime:homeparcel_' .. orderId,
        'fa-solid fa-box', 'Take Parcel', cfg().takeDistance or 2.5,
        function() TriggerServerEvent('as-postalprime:takeHomeParcel', orderId) end
    )
end

CreateThread(function()
    while true do
        Wait(1500)
        local me = GetEntityCoords(PlayerPedId())
        for id, p in pairs(parcels) do
            if not animating[id] then
                local c = p.data.coords
                local dist = #(me - vector3(c.x, c.y, c.z))
                if dist < 60.0 then
                    if not (p.entity and DoesEntityExist(p.entity)) then spawnBox(id, p) end
                elseif dist > 100.0 and p.entity then
                    despawnBox(p)
                end
            end
        end
    end
end)

-- ─── Courier van sequence ────────────────────────────────────────────────────

local function waitUntil(fn, timeoutMs)
    local deadline = GetGameTimer() + timeoutMs
    while GetGameTimer() < deadline do
        if fn() then return true end
        Wait(250)
    end
    return false
end

local function loadModel(name)
    local hash = joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    if not pcall(lib.requestModel, hash, 5000) then return nil end
    return hash
end

-- A road node roughly spawnDistance out from the door, out of sight of the player if possible.
local function findSpawn(door)
    local dist = cfg().spawnDistance or 160.0
    local me = GetEntityCoords(PlayerPedId())
    for _ = 1, 15 do
        local ang = math.random() * math.pi * 2
        local tx, ty = door.x + math.cos(ang) * dist, door.y + math.sin(ang) * dist
        local found, pos, head = GetClosestVehicleNodeWithHeading(tx, ty, door.z, 1, 3.0, 0)
        if found and #(pos - door) > 80.0 and #(pos - me) > 50.0 then
            return pos, head
        end
    end
    return nil
end

local function runCourier(data, ents)
    local door = vector3(data.coords.x, data.coords.y, data.coords.z)

    local vans = cfg().vans or { 'boxville2' }
    local vanHash = loadModel(vans[math.random(#vans)])
    local pedHash = loadModel(cfg().courierModel or 's_m_m_postal_01')
    if not vanHash or not pedHash then return end

    local spawnPos, spawnHead = findSpawn(door)
    if not spawnPos then return end
    local foundStop, stop = GetClosestVehicleNodeWithHeading(door.x, door.y, door.z, 1, 3.0, 0)
    if not foundStop then return end

    local veh = CreateVehicle(vanHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHead, false, false)
    if not veh or veh == 0 then return end
    ents[#ents + 1] = veh
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)

    local ped = CreatePedInsideVehicle(veh, 26, pedHash, -1, false, false)
    if not ped or ped == 0 then return end
    ents[#ents + 1] = ped
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetDriverAbility(ped, 1.0)
    SetVehicleEngineOn(veh, true, true, false)

    -- Drive up to the road outside the door.
    TaskVehicleDriveToCoord(ped, veh, stop.x, stop.y, stop.z, 16.0, 0, vanHash, 786603, 5.0, true)
    waitUntil(function()
        return not DoesEntityExist(veh) or #(GetEntityCoords(veh) - stop) < 14.0
    end, 120000)
    if not DoesEntityExist(veh) then return end

    TaskVehicleTempAction(ped, veh, 27, 2500)
    Wait(1800)

    -- Courier gets out and walks the box to the door.
    TaskLeaveVehicle(ped, veh, 0)
    waitUntil(function() return not IsPedInAnyVehicle(ped, false) end, 6000)
    TaskGoStraightToCoord(ped, door.x, door.y, door.z, 1.0, 12000, data.coords.w or 0.0, 0.5)
    waitUntil(function() return #(GetEntityCoords(ped) - door) < 1.8 end, 15000)

    lib.requestAnimDict('pickup_object')
    TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1400, 0, 0.0, false, false, false)
    Wait(1200)

    -- The box appears on the doorstep now.
    animating[data.orderId] = nil
    local p = parcels[data.orderId]
    if p and not p.entity then spawnBox(data.orderId, p) end
    Wait(600)

    -- Back in the van and away.
    TaskEnterVehicle(ped, veh, 12000, -1, 1.0, 1, 0)
    waitUntil(function() return IsPedInVehicle(ped, veh, false) end, 14000)
    TaskVehicleDriveWander(ped, veh, 18.0, 786603)
    Wait(cfg().despawnAfterMs or 20000)
end

local function playDelivery(data)
    local ents = {}
    -- Anything that goes wrong just ends the sequence; cleanup below always runs.
    local ok, err = pcall(runCourier, data, ents)
    if not ok then
        print(('[as-postalprime] home delivery courier sequence failed: %s'):format(tostring(err)))
    end
    animating[data.orderId] = nil -- box shows up via the range manager if the sequence never got to place it
    for _, e in ipairs(ents) do
        if DoesEntityExist(e) then
            SetEntityAsMissionEntity(e, true, true)
            DeleteEntity(e)
        end
    end
end

-- ─── Server sync ─────────────────────────────────────────────────────────────

RegisterNetEvent('as-postalprime:client:homeDrop')
AddEventHandler('as-postalprime:client:homeDrop', function(data)
    if type(data) ~= 'table' or not data.orderId or not data.coords or parcels[data.orderId] then return end
    parcels[data.orderId] = { data = data }

    -- A player courier placed this one by hand (data.noAnim): no van, the box is simply there.
    if data.noAnim then return end

    local c = data.coords
    if #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z)) <= (cfg().animateRange or 250.0) then
        animating[data.orderId] = true
        CreateThread(function() playDelivery(data) end)
    end
end)

RegisterNetEvent('as-postalprime:client:homeRemove')
AddEventHandler('as-postalprime:client:homeRemove', function(orderId)
    local p = parcels[orderId]
    if p then despawnBox(p) end
    parcels[orderId] = nil
    animating[orderId] = nil
end)

-- Everything already sitting on doorsteps (server restarts, joining late).
CreateThread(function()
    Wait(2500)
    local list = lib.callback.await('as-postalprime:getHomeParcels', false)
    for _, d in ipairs(list or {}) do
        if d.orderId and not parcels[d.orderId] then parcels[d.orderId] = { data = d } end
    end
end)

-- Phone app: the dropdown of properties you can have delivered to.
RegisterNUICallback('as-postalprime/properties', function(_, cb)
    cb(lib.callback.await('as-postalprime:getProperties', false) or {})
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for _, p in pairs(parcels) do despawnBox(p) end
end)
