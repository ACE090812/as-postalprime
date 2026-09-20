-- Player courier job (client). All rules are enforced by server/courier.lua; this file is the depot
-- window (NUI, ui/courier.js), the rental vehicle spawn, carrying parcels (pile -> vehicle -> door), the
-- GPS route and the on-screen run list. Notifications, progress bars and menus are all the resource's own
-- NUI now - ox_lib is only used for callbacks, keybinds and model/anim loading.

local function cfg() return Config.courier or {} end

local SIZE_LABEL = { s = 'Small', m = 'Medium', l = 'Large', xl = 'X-Large' }
local CARRY_DICT, CARRY_ANIM = 'anim@heists@box_carry@', 'idle'

local S = {
    data = nil,        -- last state from the server
    timers = {},       -- [orderId] = GetGameTimer()/1000 when its time limit ends
    vehicle = nil,     -- local handle of the rental vehicle (re-resolved from its netId)
    carry = nil,       -- { orderId, stage = 'pile'|'door', obj, busy, since }
    doorZone = nil,
    blip = nil, blipKey = nil,
    pileObjs = {},
}

local function notify(desc, kind, title)
    SendNUIMessage({ action = 'as-postalprime:toast', title = title or 'Postal Prime Courier', description = desc, type = kind or 'inform' })
end

-- Server-side toasts (courier messages, order cancelled / collected...)
RegisterNetEvent('as-postalprime:toast')
AddEventHandler('as-postalprime:toast', function(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage({ action = 'as-postalprime:toast', title = data.title or 'Postal Prime', description = data.description or '', type = data.type or 'inform' })
end)

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return ('%d:%02d'):format(math.floor(sec / 60), sec % 60)
end

local function enabled()
    return cfg().enabled == true
end

local function onDuty() return S.data ~= nil and S.data.isCourier == true and S.data.onDuty == true end

-- ─── NUI helpers ─────────────────────────────────────────────────────────────

-- Sends the run list (with seconds left per loaded parcel) to the on-screen HUD. The page counts the timers down itself.
local function pushHud()
    local h = cfg().hud or {}
    local rows = {}
    local now = GetGameTimer() / 1000.0
    for _, c in ipairs(S.data and S.data.claims or {}) do
        rows[#rows + 1] = {
            label = c.label, size = c.size, state = c.state,
            left = S.timers[c.orderId] and (S.timers[c.orderId] - now) or nil,
        }
    end
    SendNUIMessage({
        action = 'as-postalprime:courier:hud',
        show = (h.enabled == true) and enabled() and onDuty(),
        rows = rows, carry = S.carry ~= nil, x = h.x, y = h.y,
    })
end

-- What the depot window renders: the server's state plus seconds-left for each parcel.
local function uiState()
    local d = S.data
    if not d or not d.ok then return { isCourier = false } end
    local now = GetGameTimer() / 1000.0
    local claims = {}
    for _, c in ipairs(d.claims or {}) do
        claims[#claims + 1] = {
            orderId = c.orderId, label = c.label, kind = c.kind, size = c.size, state = c.state, pay = c.pay,
            secondsLeft = S.timers[c.orderId] and (S.timers[c.orderId] - now) or nil,
        }
    end
    local dmg = cfg().damage or {}
    return {
        isCourier = d.isCourier == true, onDuty = d.onDuty == true,
        level = d.level, xp = d.xp, levelXp = d.levelXp, nextXp = d.nextXp,
        deliveries = d.deliveries, earned = d.earned, batch = d.batch, boardCount = d.boardCount,
        usedUnits = d.usedUnits, vehicles = d.vehicles or {}, rental = d.rental, claims = claims,
        info = {
            boardMinutes = math.floor((cfg().claimSeconds or 600) / 60 + 0.5),
            damageTolerance = dmg.enabled and dmg.tolerance or nil,
        },
    }
end

-- Custom progress bar (replaces lib.progressBar). Returns true when it finished, false when cancelled (X) or dead.
local function progress(o)
    local cancellable = o.canCancel ~= false
    local ped = PlayerPedId()
    SendNUIMessage({ action = 'as-postalprime:courier:progress', label = o.label, duration = o.duration, cancellable = cancellable })
    local anim = o.anim
    if anim and pcall(lib.requestAnimDict, anim.dict, 2000) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 1.0, -1, 49, 0.0, false, false, false)
    end
    local finish = GetGameTimer() + o.duration
    local cancelled = false
    while GetGameTimer() < finish do
        Wait(0)
        for _, ctl in ipairs({ 21, 22, 23, 24, 25, 30, 31, 36, 37, 44, 75, 140, 141, 142, 257, 263, 264 }) do
            DisableControlAction(0, ctl, true)
        end
        ped = PlayerPedId()
        if IsEntityDead(ped) or (cancellable and IsControlJustPressed(0, 73)) then
            cancelled = true
            break
        end
    end
    SendNUIMessage({ action = 'as-postalprime:courier:progressStop' })
    if anim then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
    return not cancelled
end

-- "Take which parcel?" picker (several parcels loaded). Returns the chosen orderId, or nil if cancelled.
local pickPromise
local function pickParcel(items)
    if pickPromise then return nil end
    pickPromise = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'as-postalprime:courier:pick', title = 'Take which parcel?', items = items })
    local id = Citizen.Await(pickPromise)
    pickPromise = nil
    SetNuiFocus(false, false)
    return id
end

RegisterNUICallback('as-postalprime/courier:pick', function(data, cb)
    if pickPromise then pickPromise:resolve(data and data.orderId or nil) end
    cb({ ok = true })
end)

-- ─── carrying ────────────────────────────────────────────────────────────────

local function removeDoorZone()
    if S.doorZone then
        pcall(PPTarget.removeZone, S.doorZone)
        S.doorZone = nil
    end
end

-- Puts the parcel out of the courier's hands locally. tellServer = also clear the server's record.
local function clearCarry(tellServer)
    local c = S.carry
    S.carry = nil
    removeDoorZone()
    pushHud()
    if c and c.obj and DoesEntityExist(c.obj) then
        DetachEntity(c.obj, true, true)
        DeleteEntity(c.obj)
    end
    if c then
        local ped = PlayerPedId()
        StopAnimTask(ped, CARRY_DICT, CARRY_ANIM, 1.0)
    end
    if c and tellServer then TriggerServerEvent('as-postalprime:courier:dropCarry') end
end

local placeParcel -- forward: the door zone calls it

local function startCarry(orderId, size, stage, doorCoords, kind)
    if S.carry then clearCarry(false) end
    local ped = PlayerPedId()

    local hash = joaat('asparcel_' .. (size or 'm'))
    if not IsModelValid(hash) then hash = joaat('prop_cs_cardbox_01') end
    if not pcall(lib.requestModel, hash, 5000) then
        notify('Couldn\'t load the parcel model.', 'error')
        TriggerServerEvent('as-postalprime:courier:dropCarry')
        return
    end
    pcall(lib.requestAnimDict, CARRY_DICT, 5000)

    local pc = GetEntityCoords(ped)
    local obj = CreateObject(hash, pc.x, pc.y, pc.z + 1.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    local cc = cfg().carry or {}
    local pos, rot = cc.pos or vector3(0.025, 0.08, 0.255), cc.rot or vector3(-145.0, 290.0, 0.0)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, cc.bone or 60309),
        pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    TaskPlayAnim(ped, CARRY_DICT, CARRY_ANIM, 8.0, -8.0, -1, 49, 0.0, false, false, false)

    local me = { orderId = orderId, stage = stage, obj = obj, since = GetGameTimer() }
    S.carry = me
    pushHud()

    if stage == 'door' and doorCoords then
        S.doorZone = PPTarget.addSphereZone(
            'as-postalprime:courier_door', vector3(doorCoords.x, doorCoords.y, doorCoords.z), 1.8,
            'fa-solid fa-box', 'Place Parcel', 3.5, function() placeParcel() end,
            function() return S.carry ~= nil and S.carry.stage == 'door' end
        )
    end

    notify(stage == 'pile' and 'Carry the parcel to your vehicle. Press X to put it down.'
        or (kind == 'locker' and 'Carry the parcel to the locker. Press X to put it down.'
            or 'Carry the parcel to the door. Press X to put it down.'))

    CreateThread(function()
        while S.carry == me do
            Wait(0)
            DisableControlAction(0, 21, true)  -- sprint
            DisableControlAction(0, 22, true)  -- jump
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            DisableControlAction(0, 140, true) -- melee
            local p = PlayerPedId()
            if IsEntityDead(p) or IsPedInAnyVehicle(p, true) or IsPedGettingIntoAVehicle(p) then
                clearCarry(true)
                notify('You put the parcel down.')
                break
            end
            if not me.busy and not IsEntityPlayingAnim(p, CARRY_DICT, CARRY_ANIM, 3) then
                TaskPlayAnim(p, CARRY_DICT, CARRY_ANIM, 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end
        end
    end)
end

lib.addKeybind({
    name = 'pp_courier_drop',
    description = 'Postal Prime: put the parcel down',
    defaultKey = 'X',
    onPressed = function()
        if S.carry and not S.carry.busy then
            clearCarry(true)
            notify('You put the parcel down.')
        end
    end,
})

-- ─── state ───────────────────────────────────────────────────────────────────

local function refresh()
    if not enabled() then return end
    local d = lib.callback.await('as-postalprime:courier:state', false)
    S.data = d
    S.timers = {}
    if d and d.claims then
        local now = GetGameTimer() / 1000.0
        for _, c in ipairs(d.claims) do
            if c.secondsLeft then S.timers[c.orderId] = now + c.secondsLeft end
        end
    end
    -- The server no longer thinks we hold a parcel (fallback / job change): drop ours.
    if d and d.ok and not d.carry and S.carry and (GetGameTimer() - S.carry.since) > 4000 then
        clearCarry(false)
    end
    pushHud()
    if S.uiOpen then SendNUIMessage({ action = 'as-postalprime:courier:state', state = uiState() }) end
end

RegisterNetEvent('as-postalprime:courier:refresh')
AddEventHandler('as-postalprime:courier:refresh', function()
    CreateThread(refresh)
end)

RegisterNetEvent('as-postalprime:courier:carryClear')
AddEventHandler('as-postalprime:courier:carryClear', function()
    if S.carry then
        clearCarry(false)
        notify('That parcel was taken off you.', 'error')
    end
end)

RegisterNetEvent('as-postalprime:courier:printCoords')
AddEventHandler('as-postalprime:courier:printCoords', function()
    local ped = PlayerPedId()
    local p, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local txt = ('vector4(%.2f, %.2f, %.2f, %.1f)'):format(p.x, p.y, p.z, h)
    print('[as-postalprime] ' .. txt)
    pcall(lib.setClipboard, txt)
    notify('Copied: ' .. txt, 'inform', 'Postal Prime')
end)

-- ─── delivering ──────────────────────────────────────────────────────────────

placeParcel = function()
    local c = S.carry
    if not c or c.stage ~= 'door' or c.busy then return end
    c.busy = true
    local ok = progress({
        duration = 1800, label = 'Placing parcel', canCancel = true, useWhileDead = false,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'pickup_object', clip = 'pickup_low' },
    })
    if not ok then c.busy = false return end

    local res = lib.callback.await('as-postalprime:courier:deliver', false, c.orderId)
    if not res or not res.ok then
        c.busy = false
        notify((res and res.error) or 'Couldn\'t deliver that parcel.', 'error')
        return
    end

    clearCarry(false)
    local msg = ('Paid $%d  ·  +%d XP'):format(res.pay, res.xp)
    if res.late and res.late > 0 then
        msg = ('%s\nLate by %s - pay cut from $%d'):format(msg, fmtTime(res.late), res.full)
    end
    notify(msg, 'success', 'Parcel delivered')
    if res.levelUp then notify(('You reached courier level %d!'):format(res.level), 'success', 'Level up') end
    refresh()
end

-- Loads the parcel in hand (from the pile) into the rental vehicle.
local function loadIntoVehicle()
    local c = S.carry
    if not c or c.stage ~= 'pile' or c.busy then return end
    c.busy = true
    local ok = progress({
        duration = 2200, label = 'Loading parcel', canCancel = true, useWhileDead = false,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'pickup_object', clip = 'pickup_low' },
    })
    if not ok then c.busy = false return end

    local res = lib.callback.await('as-postalprime:courier:load', false, c.orderId)
    if not res or not res.ok then
        c.busy = false
        notify((res and res.error) or 'Couldn\'t load that.', 'error')
        return
    end
    clearCarry(false)
    refresh()
    local d = S.data
    local left = 0
    for _, cl in ipairs(d and d.claims or {}) do if cl.state == 'claimed' then left = left + 1 end end
    notify(left > 0 and ('Loaded. %d more to collect from the pile.'):format(left)
        or 'All loaded - follow the GPS to the first stop.', 'success')
end

local function takeParcel(claim)
    local ok = progress({
        duration = 1500, label = 'Taking parcel out', canCancel = true, useWhileDead = false,
        disable = { move = true, car = true, combat = true },
    })
    if not ok then return end
    local res = lib.callback.await('as-postalprime:courier:takeFromVehicle', false, claim.orderId)
    if not res or not res.ok then
        notify((res and res.error) or 'Couldn\'t take that out.', 'error')
        return
    end
    startCarry(claim.orderId, res.size, 'door', res.coords, res.kind)
end

local function distTo(c)
    return #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z))
end

-- The rental vehicle's single target option: load / take out / put back, depending on what you're doing.
local function onVehicleParcels()
    if S.carry then
        if S.carry.busy then return end
        if S.carry.stage == 'pile' then return loadIntoVehicle() end
        clearCarry(true)
        notify('You put the parcel back in the vehicle.')
        return
    end

    refresh()
    local loaded = {}
    for _, c in ipairs(S.data and S.data.claims or {}) do
        if c.state == 'loaded' then loaded[#loaded + 1] = c end
    end
    if #loaded == 0 then
        notify('Nothing is loaded. Collect parcels from the pile at the depot first.')
        return
    end
    table.sort(loaded, function(a, b) return distTo(a.coords) < distTo(b.coords) end)
    if #loaded == 1 then return takeParcel(loaded[1]) end

    local items = {}
    local now = GetGameTimer() / 1000.0
    for _, c in ipairs(loaded) do
        items[#items + 1] = {
            orderId = c.orderId, label = c.label, size = c.size, kind = c.kind,
            km = distTo(c.coords) / 1000.0,
            left = S.timers[c.orderId] and (S.timers[c.orderId] - now) or nil,
        }
    end
    local id = pickParcel(items)
    if not id then return end
    for _, c in ipairs(loaded) do
        if c.orderId == id then return takeParcel(c) end
    end
end

-- ─── rental vehicle ──────────────────────────────────────────────────────────

local function registerVehicleTarget(veh)
    if S.vehicle and S.vehicle ~= veh then pcall(PPTarget.removeEntity, S.vehicle) end
    S.vehicle = veh
    PPTarget.addEntity(veh, 'as-postalprime:courier_veh', 'fa-solid fa-box-open', 'Parcels', 4.0, onVehicleParcels)
end

local function pickSpawn()
    for _, sp in ipairs(cfg().depot.spawns or {}) do
        if GetClosestVehicle(sp.x, sp.y, sp.z, 3.0, 0, 71) == 0 then return sp end
    end
    return nil
end

-- Full tank on whatever fuel system is running (state bag + native + the common fuel resources' exports).
local function setFuelFull(veh)
    SetVehicleFuelLevel(veh, 100.0)
    pcall(function() Entity(veh).state:set('fuel', 100.0, true) end)
    for _, res in ipairs({ 'LegacyFuel', 'cdn-fuel', 'ps-fuel', 'lc_fuel', 'x-fuel', 'okokGasStation' }) do
        if GetResourceState(res) == 'started' then
            pcall(function() exports[res]:SetFuel(veh, 100.0) end)
        end
    end
    if GetResourceState('ox_fuel') == 'started' then
        pcall(function() Entity(veh).state.fuel = 100.0 end)
    end
end

-- Returns true when the vehicle is out and registered.
local function rentVehicle(v)
    local res = lib.callback.await('as-postalprime:courier:rent', false, v.key)
    if not res or not res.ok then
        notify((res and res.error) or 'Couldn\'t rent that.', 'error')
        return false
    end

    local function fail(msg)
        lib.callback.await('as-postalprime:courier:cancelRent', false)
        notify(msg, 'error')
        refresh()
        return false
    end

    local sp = pickSpawn()
    if not sp then return fail('Every bay is busy - deposit refunded. Try again in a moment.') end

    local hash = joaat(res.model)
    if not IsModelInCdimage(hash) or not pcall(lib.requestModel, hash, 8000) then
        return fail('That vehicle model isn\'t available - deposit refunded.')
    end

    local veh = CreateVehicle(hash, sp.x, sp.y, sp.z, sp.w, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 then return fail('The vehicle wouldn\'t spawn - deposit refunded.') end

    local deadline = GetGameTimer() + 5000
    while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < deadline do Wait(50) end
    local netId = NetworkGetNetworkIdFromEntity(veh)

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, res.plate)
    SetVehicleDoorsLocked(veh, 1)
    setFuelFull(veh)

    local reg = lib.callback.await('as-postalprime:courier:registerVehicle', false, netId)
    if not reg or not reg.ok then
        if DoesEntityExist(veh) then DeleteEntity(veh) end
        notify((reg and reg.error) or 'Couldn\'t register the vehicle.', 'error')
        refresh()
        return false
    end

    refresh()
    registerVehicleTarget(veh)
    -- Fuel scripts often initialise a fresh vehicle a moment after it spawns - top it up again.
    CreateThread(function() Wait(1500) if DoesEntityExist(veh) then setFuelFull(veh) end end)
    notify(('%s ready in the bay - plate %s. Your key is in your inventory.'):format(v.label, res.plate), 'success')
    return true
end

-- Re-attach the target when the vehicle re-streams; report it if it's destroyed.
CreateThread(function()
    while true do
        Wait(2000)
        local r = S.data and S.data.rental
        if r and r.netId and NetworkDoesNetworkIdExist(r.netId) then
            local ent = NetworkGetEntityFromNetworkId(r.netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                if ent ~= S.vehicle then registerVehicleTarget(ent) end
                if IsEntityDead(ent) then
                    TriggerServerEvent('as-postalprime:courier:vehicleLost')
                    S.data.rental = nil
                    S.vehicle = nil
                    CreateThread(function() Wait(1500) refresh() end)
                end
            end
        end
    end
end)

-- ─── depot window ────────────────────────────────────────────────────────────
-- The window itself is ui/courier.js. It asks for everything through the callbacks below, and each
-- reply carries the fresh state so the page never shows stale numbers.

local function toggleDuty(on)
    local res = lib.callback.await('as-postalprime:courier:duty', false, on)
    if not res or not res.ok then notify((res and res.error) or 'Couldn\'t do that.', 'error') end
    refresh()
end

local function nui(name, fn)
    RegisterNUICallback('as-postalprime/courier:' .. name, function(data, cb)
        local ok, res = pcall(fn, data or {})
        if not ok then
            print(('[as-postalprime] courier:%s failed: %s'):format(name, tostring(res)))
            notify('Something went wrong - try again.', 'error')
            res = { ok = false }
            pcall(refresh)
        end
        if type(res) ~= 'table' then res = { ok = true } end
        if S.uiOpen and res.orders == nil then res.state = uiState() end
        cb(res)
    end)
end

nui('close', function()
    S.uiOpen = false
    SetNuiFocus(false, false)
    return { ok = true }
end)

nui('state', function()
    refresh()
    return { ok = true }
end)

nui('board', function()
    return lib.callback.await('as-postalprime:courier:board', false) or { ok = false }
end)

nui('duty', function(d)
    toggleDuty(d.on == true)
    return { ok = true }
end)

nui('rent', function(d)
    local pick
    for _, v in ipairs(S.data and S.data.vehicles or {}) do
        if v.key == d.key then pick = v end
    end
    if not pick then return { ok = false } end
    return { ok = rentVehicle(pick) }
end)

nui('return', function()
    local r = lib.callback.await('as-postalprime:courier:return', false)
    if not (r and r.ok) then notify((r and r.error) or 'Couldn\'t return it.', 'error') end
    if S.vehicle then pcall(PPTarget.removeEntity, S.vehicle) S.vehicle = nil end
    refresh()
    return { ok = r and r.ok == true }
end)

nui('claim', function(d)
    local r = lib.callback.await('as-postalprime:courier:claim', false, d.orderId)
    if r and r.ok then
        notify('Claimed. Collect the parcel from the pile, load it, then deliver.', 'success')
    else
        notify((r and r.error) or 'Couldn\'t claim that.', 'error')
    end
    refresh()
    return { ok = r and r.ok == true }
end)

nui('unclaim', function(d)
    local r = lib.callback.await('as-postalprime:courier:unclaim', false, d.orderId)
    if not (r and r.ok) then notify((r and r.error) or 'Couldn\'t put that back.', 'error') end
    refresh()
    return { ok = r and r.ok == true }
end)

nui('abandon', function()
    lib.callback.await('as-postalprime:courier:abandon', false)
    if S.carry then clearCarry(false) end
    refresh()
    return { ok = true }
end)

local function openDepot()
    if S.uiOpen then return end
    refresh()
    local d = S.data
    if not d or not d.ok then notify('The courier job isn\'t available right now.', 'error', 'Postal Prime Depot') return end
    if not d.isCourier then
        notify('You need the Postal Prime job to work from the depot.', 'error', 'Postal Prime Depot')
        return
    end
    S.uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'as-postalprime:courier:open', state = uiState() })
end

-- ─── pile ────────────────────────────────────────────────────────────────────

local function onPile()
    if S.carry then notify('You\'re already carrying a parcel.') return end
    local res = lib.callback.await('as-postalprime:courier:pickPile', false)
    if not res or not res.ok then notify((res and res.error) or 'Nothing to collect.', 'error') return end

    local ok = progress({
        duration = 1200, label = 'Picking up parcel', canCancel = true, useWhileDead = false,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'pickup_object', clip = 'pickup_low' },
    })
    if not ok then
        TriggerServerEvent('as-postalprime:courier:dropCarry')
        return
    end
    startCarry(res.orderId, res.size, 'pile')
end

-- ─── setup: depot blip, targets, decorative pile ─────────────────────────────

local zones = {}
local depotBlip

CreateThread(function()
    if not enabled() then return end
    local dep = cfg().depot
    local desk, pile = dep.desk, dep.pile

    if dep.blip and dep.blip.enabled then
        depotBlip = AddBlipForCoord(desk.x, desk.y, desk.z)
        SetBlipSprite(depotBlip, dep.blip.sprite or 478)
        SetBlipColour(depotBlip, dep.blip.colour or 5)
        SetBlipScale(depotBlip, dep.blip.scale or 0.8)
        SetBlipAsShortRange(depotBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(dep.blip.label or 'Postal Prime Depot')
        EndTextCommandSetBlipName(depotBlip)
    end

    zones[#zones + 1] = PPTarget.addSphereZone(
        'as-postalprime:courier_desk', vector3(desk.x, desk.y, desk.z), 1.5,
        'fa-solid fa-truck-fast', 'Postal Prime Depot', 3.0, openDepot)

    zones[#zones + 1] = PPTarget.addSphereZone(
        'as-postalprime:courier_pile', vector3(pile.x, pile.y, pile.z), 1.8,
        'fa-solid fa-box', 'Collect Parcel', 3.0, onPile,
        function() return onDuty() and S.data.rental ~= nil and S.carry == nil end)

    Wait(2500)
    refresh()
end)

-- Decorative parcels at the pile (local props, spawned when you're near).
CreateThread(function()
    if not enabled() or not cfg().depot.pileProps then return end
    local pile = cfg().depot.pile
    local center = vector3(pile.x, pile.y, pile.z)
    local layout = {
        { 'asparcel_l',  0.0,  0.0, 0.0 }, { 'asparcel_m', 0.8, 0.3, 40.0 }, { 'asparcel_m', -0.7, 0.4, 100.0 },
        { 'asparcel_s',  0.3, -0.7, 15.0 }, { 'asparcel_xl', -0.3, -1.3, 70.0 }, { 'asparcel_s', 1.1, -0.6, 200.0 },
    }
    while true do
        Wait(3000)
        local dist = #(GetEntityCoords(PlayerPedId()) - center)
        if dist < 80.0 and #S.pileObjs == 0 then
            for _, def in ipairs(layout) do
                local hash = joaat(def[1])
                if IsModelValid(hash) and pcall(lib.requestModel, hash, 3000) then
                    local o = CreateObject(hash, center.x + def[2], center.y + def[3], center.z, false, false, false)
                    SetEntityHeading(o, def[4])
                    PlaceObjectOnGroundProperly(o)
                    FreezeEntityPosition(o, true)
                    SetModelAsNoLongerNeeded(hash)
                    S.pileObjs[#S.pileObjs + 1] = o
                end
            end
        elseif dist > 140.0 and #S.pileObjs > 0 then
            for _, o in ipairs(S.pileObjs) do if DoesEntityExist(o) then DeleteEntity(o) end end
            S.pileObjs = {}
        end
    end
end)

-- Keep job/duty fresh (job changes, a shift ended by the server).
CreateThread(function()
    Wait(6000)
    while true do
        Wait(30000)
        refresh()
    end
end)

-- ─── GPS route to the next stop ──────────────────────────────────────────────

local function setRoute(coords, label)
    local key = coords and ('%.1f:%.1f'):format(coords.x, coords.y) or nil
    if key == S.blipKey then return end
    if S.blip and DoesBlipExist(S.blip) then RemoveBlip(S.blip) end
    S.blip, S.blipKey = nil, key
    if not coords then return end
    S.blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(S.blip, 1)
    SetBlipColour(S.blip, 5)
    SetBlipRoute(S.blip, true)
    SetBlipRouteColour(S.blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or 'Delivery')
    EndTextCommandSetBlipName(S.blip)
end

CreateThread(function()
    while true do
        Wait(1500)
        local d = S.data
        local target, label
        if enabled() and onDuty() and d.claims and #d.claims > 0 then
            if S.carry and S.carry.stage == 'door' then
                for _, c in ipairs(d.claims) do
                    if c.orderId == S.carry.orderId then target, label = c.coords, c.label end
                end
            elseif S.carry and S.carry.stage == 'pile' then
                if S.vehicle and DoesEntityExist(S.vehicle) then
                    local vc = GetEntityCoords(S.vehicle)
                    target, label = { x = vc.x, y = vc.y, z = vc.z }, 'Your vehicle'
                end
            else
                local best, bestD
                local hasClaimed = false
                for _, c in ipairs(d.claims) do
                    if c.state == 'loaded' then
                        local dist = distTo(c.coords)
                        if not bestD or dist < bestD then best, bestD = c, dist end
                    else
                        hasClaimed = true
                    end
                end
                if best then
                    target, label = best.coords, best.label
                elseif hasClaimed then
                    local p = cfg().depot.pile
                    target, label = { x = p.x, y = p.y, z = p.z }, 'Parcel pile'
                end
            end
        end
        setRoute(target, label)
    end
end)

-- ─── on-screen run list ──────────────────────────────────────────────────────
-- Drawn by ui/courier.js (see pushHud above) - nothing to do per frame here.

-- ─── cleanup ─────────────────────────────────────────────────────────────────

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    if S.uiOpen or pickPromise then
        S.uiOpen = false
        SetNuiFocus(false, false)
        if pickPromise then pickPromise:resolve(nil) end
    end
    clearCarry(false)
    setRoute(nil)
    for _, z in ipairs(zones) do pcall(PPTarget.removeZone, z) end
    if S.vehicle then pcall(PPTarget.removeEntity, S.vehicle) end
    if depotBlip and DoesBlipExist(depotBlip) then RemoveBlip(depotBlip) end
    for _, o in ipairs(S.pileObjs) do if DoesEntityExist(o) then DeleteEntity(o) end end
end)
