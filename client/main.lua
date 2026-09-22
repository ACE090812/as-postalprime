CreateThread(function()
    -- Small + medium home-screen widgets (ui/widget.html). Interactive so a tap opens the app.
    local widgets = nil
    if Config.widget == nil or Config.widget.enabled ~= false then
        widgets = {
            {
                id = 'parcels',
                name = T('widget.name'),
                ui = GetCurrentResourceName() .. '/ui/widget.html',
                interactive = true,
                sizes = { 'sm', 'md' },
            },
        }
    end

    local ok, err = exports['sd-phone']:addCustomApp({
        identifier  = Config.app.identifier,
        name        = Config.app.name,
        description = Config.app.description,
        icon        = Config.app.icon,

        ui = GetCurrentResourceName() .. '/ui/index.html',
        widgets = widgets,
    })
    if not ok then
        print(('[as-postalprime] failed to register the Postal Prime app with sd-phone: %s'):format(tostring(err)))
    end
end)

-- Language dictionary for the NUI pages (see ui/i18n.js). Config.locale picks the language.
RegisterNUICallback('as-postalprime/locale', function(_, cb)
    cb(LocaleDict())
end)

RegisterNUICallback('as-postalprime/state', function(_, cb)
    local result = lib.callback.await('as-postalprime:getState', false)
    if result and result.lockers then
        local coords = GetEntityCoords(PlayerPedId())
        for _, l in ipairs(result.lockers) do
            if l.coords then
                l.distanceKm = #(coords - vector3(l.coords.x, l.coords.y, l.coords.z)) / 1000.0
            end
        end
        table.sort(result.lockers, function(a, b) return (a.distanceKm or 0) < (b.distanceKm or 0) end)
    end
    cb(result)
end)

-- Light feed for the home-screen widgets (ui/widget.html polls it while the phone shows the widget).
RegisterNUICallback('as-postalprime/widget', function(_, cb)
    cb(lib.callback.await('as-postalprime:getWidget', false))
end)

RegisterNUICallback('as-postalprime/checkout', function(data, cb)
    cb(lib.callback.await('as-postalprime:checkout', false, data))
end)

RegisterNUICallback('as-postalprime/reviews', function(data, cb)
    cb(lib.callback.await('as-postalprime:getReviews', false, data))
end)

RegisterNUICallback('as-postalprime/submitReview', function(data, cb)
    cb(lib.callback.await('as-postalprime:submitReview', false, data))
end)

RegisterNUICallback('as-postalprime/subscribePlus', function(_, cb)
    cb(lib.callback.await('as-postalprime:subscribePlus', false))
end)

RegisterNUICallback('as-postalprime/toggleWishlist', function(data, cb)
    cb(lib.callback.await('as-postalprime:toggleWishlist', false, data))
end)

RegisterNUICallback('as-postalprime/saveCart', function(data, cb)
    cb(lib.callback.await('as-postalprime:saveCart', false, data))
end)

RegisterNUICallback('as-postalprime/cancelOrder', function(_, cb)
    cb(lib.callback.await('as-postalprime:cancelOrder', false))
end)

RegisterNetEvent('as-postalprime:client:updated', function()
    SendNUIMessage({ action = 'as-postalprime:updated' })
end)

-- Short flavour animation when a sealed parcel (Config.parcelItems) is used - the server has
-- already decided to give the real items by the time this fires, so this is cosmetic only and
-- doesn't gate anything (reuses PPTakeAnim.play with no box to attach, just the anim itself).
RegisterNetEvent('as-postalprime:client:openParcel', function()
    local cfg = Config.parcelOpenAnim or {}
    if PPTakeAnim then
        PPTakeAnim.play(nil, nil, cfg.dict, cfg.clip, cfg.duration)
    end
end)

-- ─── Order-ready map ping ─────────────────────────────────────────────────────
-- A blip + waypoint dropped on the assigned locker the moment an order flips to "ready", so
-- players don't have to remember which of the (possibly several) lockers it's sitting at.
-- Cleared on collection/expiry by the server (see server/main.lua).

local orderBlip = nil

RegisterNetEvent('as-postalprime:client:orderReady')
AddEventHandler('as-postalprime:client:orderReady', function(coords, lockerLabel)
    if orderBlip and DoesBlipExist(orderBlip) then RemoveBlip(orderBlip) end
    orderBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(orderBlip, 478)
    SetBlipColour(orderBlip, 5)
    SetBlipScale(orderBlip, 0.9)
    SetBlipAsShortRange(orderBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(T('blip.order', lockerLabel))
    EndTextCommandSetBlipName(orderBlip)
    SetNewWaypoint(coords.x, coords.y)
end)

RegisterNetEvent('as-postalprime:client:orderReady:clear')
AddEventHandler('as-postalprime:client:orderReady:clear', function()
    if orderBlip and DoesBlipExist(orderBlip) then RemoveBlip(orderBlip) end
    orderBlip = nil
end)

-- ─── Locker wall props ───────────────────────────────────────────────────────
-- Spawns the actual mdx_cap_lockers wall prop at each Config.lockers location (coords/heading
-- from config.lua - point these at your own placed locker props). Entering the pickup code on
-- the wall opens that order's assigned door with the real per-door animation and drops the
-- parcel at its offset; walking up and taking it hands the items over server-side.

local lockerProps = {}     -- [lockerId] = spawned wall entity
local takeZones = {}       -- [lockerId] = ox_target zone id for the currently-open door's parcel
local spawnedBoxes = {}    -- [lockerId] = spawned parcel box entity, attached to the wall prop

local function playDoorAnim(lockerId, doorSlot, open)
    local prop = lockerProps[lockerId]
    if not prop or not DoesEntityExist(prop) then return end

    local dict = Config.lockerWall.animDict
    lib.requestAnimDict(dict)

    local clip = (open and 'door_%d_open' or 'door_%d_close'):format(doorSlot)
    PlayEntityAnim(prop, clip, dict, 1000.0, false, true, false, 0.0, 0)
end

local function removeTakeZone(lockerId)
    local zoneId = takeZones[lockerId]
    if zoneId then
        PPTarget.removeZone(zoneId)
        takeZones[lockerId] = nil
    end
end

local function removeBox(lockerId)
    local box = spawnedBoxes[lockerId]
    if box then
        if DoesEntityExist(box) then DeleteEntity(box) end
        spawnedBoxes[lockerId] = nil
    end
end

-- Spawns the parcel box for this door, attached to the wall prop at its configured offset, and
-- drops a "Take Parcel" interaction point there. The take zone is always created off the
-- prop's own offset (not the box's own coords) and doesn't depend on the box actually spawning
-- successfully - a bad/missing model would otherwise leave an open door with no way to collect
-- from it at all, which is worse than a door with no visible box in it.
local function spawnBox(lockerId, doorSlot)
    local prop = lockerProps[lockerId]
    local def = Config.lockerBoxOffsets[doorSlot]
    if not prop or not def or not DoesEntityExist(prop) then return end

    removeBox(lockerId)

    local modelName = def.model or 'mdx_parcel_m'
    local hash = joaat(modelName)

    if IsModelValid(hash) then
        lib.requestModel(hash)
        local box = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
        if DoesEntityExist(box) then
            AttachEntityToEntity(
                box, prop, 0,
                def.x, def.y, def.z,
                0.0, 0.0, 0.0,
                false, false, false, false, 2, true
            )
            spawnedBoxes[lockerId] = box
        end
        SetModelAsNoLongerNeeded(hash)
    end

    if not spawnedBoxes[lockerId] then
        print(('[as-postalprime] parcel box model "%s" failed to spawn for locker %s door %d - the door will still open with a "Take Parcel" point at the right spot, just without a visible box'):format(modelName, lockerId, doorSlot))
    end

    local coords = GetOffsetFromEntityInWorldCoords(prop, def.x, def.y, def.z)
    takeZones[lockerId] = PPTarget.addSphereZone(
        'as-postalprime:takebox_' .. lockerId, coords, Config.lockerWall.takeRadius or 0.5,
        'fa-solid fa-box', T('target.takeParcel'), 2.5,
        function()
            removeTakeZone(lockerId) -- stop repeat clicks while the take animation plays
            PPTakeAnim.play(spawnedBoxes[lockerId], function()
                TriggerServerEvent('as-postalprime:takeBox', lockerId, doorSlot)
            end)
        end
    )
end

RegisterNetEvent('as-postalprime:client:syncDoor')
AddEventHandler('as-postalprime:client:syncDoor', function(lockerId, doorSlot, open)
    playDoorAnim(lockerId, doorSlot, open)
    removeTakeZone(lockerId)

    if open then
        spawnBox(lockerId, doorSlot)
    else
        removeBox(lockerId)
    end
end)

--- ─── Locker pickup keypad (custom UI, replaces ox_lib) ─────────────────────────
-- The keypad lives as an always-loaded overlay on this resource's own ui_page (see
-- ui/index.html's #lockerKeypad) and is shown/hidden directly on THIS root NUI instance via
-- SendNUIMessage - completely separate from the copy sd-phone embeds in its own iframe when the
-- app is opened on the phone, so this works at the locker whether or not the phone is out.
-- pendingLockerId correlates the keypad's submit/cancel callbacks (which don't otherwise know
-- which of the (possibly several) lockers triggered them) back to the right one.
local pendingLockerId = nil

local function closeLockerKeypad()
    SetNuiFocus(false, false)
    pendingLockerId = nil
end

RegisterNUICallback('as-postalprime/locker:submit', function(data, cb)
    if not pendingLockerId then cb({ ok = false, error = T('err.noLocker') }) return end
    local code = data and data.code
    local result = lib.callback.await('as-postalprime:collect', false, { lockerId = pendingLockerId, code = code })
    if result and result.ok then
        SendNUIMessage({ action = 'as-postalprime:updated' })
    end
    cb(result or { ok = false, error = T('err.noResponse') })
end)

RegisterNUICallback('as-postalprime/locker:close', function(_, cb)
    closeLockerKeypad()
    cb({ ok = true })
end)

CreateThread(function()
    for _, locker in ipairs(Config.lockers) do
        local model = joaat(Config.lockerWall.prop)
        lib.requestModel(model)
        local obj = CreateObject(model, locker.coords.x, locker.coords.y, locker.coords.z, false, false, false)
        FreezeEntityPosition(obj, true)
        SetEntityHeading(obj, locker.heading or 0.0)
        SetModelAsNoLongerNeeded(model)
        lockerProps[locker.id] = obj

        PPTarget.addEntity(
            obj, 'as-postalprime:collect_' .. locker.id,
            'fa-solid fa-box-open', T('target.openLocker'), Config.lockerWall.interactDistance or 2.0,
            function()
                -- On-model screen (client/screen.lua) when enabled + ready; otherwise fall back to the NUI overlay.
                if PPScreen and PPScreen.open(locker.id, locker.label, obj) then return end
                pendingLockerId = locker.id
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'as-postalprime:keypad:show', label = locker.label })
            end
        )
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for lockerId in pairs(takeZones) do removeTakeZone(lockerId) end
    for lockerId in pairs(spawnedBoxes) do removeBox(lockerId) end
    for _, obj in pairs(lockerProps) do
        if DoesEntityExist(obj) then
            PPTarget.removeEntity(obj)
            DeleteEntity(obj)
        end
    end
    if orderBlip and DoesBlipExist(orderBlip) then RemoveBlip(orderBlip) end
    -- Belt-and-suspenders: don't leave the player's controls locked to NUI if the resource
    -- stops while the locker keypad happens to be open.
    if pendingLockerId then SetNuiFocus(false, false) end
end)