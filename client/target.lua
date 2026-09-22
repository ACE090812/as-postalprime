-- Target-system bridge: lets Config.target pick 'ox_target', 'qb-target', or 'auto' (detects
-- whichever is actually started - ox_target first if both are somehow present). Every other
-- client file goes through PPTarget instead of calling exports.ox_target/'qb-target' directly,
-- so this is the only place that needs to know the two APIs differ.

PPTarget = {}

-- Returns the confirmed target system, or nil when neither is started YET but neither is confirmed
-- missing either (still booting). Distinguishing "not yet" from "never" is what lets system() below
-- wait instead of guessing wrong on a server where ox_target/qb-target happens to start after
-- as-postalprime during a full restart.
local function detect()
    local wanted = Config.target or 'auto'
    if wanted == 'ox_target' or wanted == 'qb-target' then return wanted end

    if GetResourceState('ox_target') == 'started' then return 'ox_target' end
    if GetResourceState('qb-target') == 'started' then return 'qb-target' end
    if GetResourceState('ox_target') == 'missing' and GetResourceState('qb-target') == 'missing' then
        return 'ox_target' -- confirmed neither is installed; fall back rather than wait forever
    end
    return nil
end

local resolved = nil

-- Resolves once, waiting up to 10s for ox_target/qb-target to finish starting if this is called very
-- early after as-postalprime's own start (the same startup-order race the browser resources hit with
-- framework detection - see as-browser/server/bridge.lua). Every PPTarget call below already runs
-- inside its own CreateThread (see client/main.lua), so blocking here is safe, and it means a locker's
-- target option is never registered against the wrong system in the first place.
local function system()
    if resolved then return resolved end
    local deadline = GetGameTimer() + 10000
    while true do
        local d = detect()
        if d then
            resolved = d
            return resolved
        end
        if GetGameTimer() > deadline then
            print('[as-postalprime] Neither ox_target nor qb-target appears to be started after 10s - defaulting to ox_target. Locker interactions will not work until one of them is running.')
            resolved = 'ox_target'
            return resolved
        end
        Wait(100)
    end
end

-- Adds a target option to a specific entity (the locker wall prop). Returns nothing - removed
-- later by entity, not by an id, same as both underlying APIs expect for entity targets.
-- canInteract (optional): function() -> boolean, checked every time the option would show.
function PPTarget.addEntity(entity, name, icon, label, distance, onSelect, canInteract)
    if system() == 'qb-target' then
        exports['qb-target']:AddTargetEntity(entity, {
            options = {
                { icon = icon, label = label, action = onSelect, canInteract = canInteract and function() return canInteract() end or nil },
            },
            distance = distance,
        })
    else
        exports.ox_target:addLocalEntity(entity, {
            { name = name, icon = icon, label = label, distance = distance, onSelect = onSelect,
              canInteract = canInteract and function() return canInteract() end or nil },
        })
    end
end

function PPTarget.removeEntity(entity)
    if system() == 'qb-target' then
        exports['qb-target']:RemoveTargetEntity(entity)
    else
        exports.ox_target:removeLocalEntity(entity)
    end
end

-- Adds a free-floating circular/sphere zone (the "Take Parcel" point). Returns a zone id/name
-- to pass back into PPTarget.removeZone later.
function PPTarget.addSphereZone(name, coords, radius, icon, label, distance, onSelect, canInteract)
    if system() == 'qb-target' then
        exports['qb-target']:AddCircleZone(name, coords, radius, {
            name = name,
            debugPoly = false,
            useZ = true,
        }, {
            options = {
                { icon = icon, label = label, action = onSelect, canInteract = canInteract and function() return canInteract() end or nil },
            },
            distance = distance,
        })
        return name
    end

    return exports.ox_target:addSphereZone({
        coords = coords,
        radius = radius,
        options = {
            { name = name, icon = icon, label = label, distance = distance, onSelect = onSelect,
              canInteract = canInteract and function() return canInteract() end or nil },
        },
    })
end

function PPTarget.removeZone(zoneId)
    if system() == 'qb-target' then
        exports['qb-target']:RemoveZone(zoneId)
    else
        exports.ox_target:removeZone(zoneId)
    end
end
