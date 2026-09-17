-- Target-system bridge: lets Config.target pick 'ox_target', 'qb-target', or 'auto' (detects
-- whichever is actually started - ox_target first if both are somehow present). Every other
-- client file goes through PPTarget instead of calling exports.ox_target/'qb-target' directly,
-- so this is the only place that needs to know the two APIs differ.

PPTarget = {}

local function detect()
    local wanted = Config.target or 'auto'
    if wanted == 'ox_target' or wanted == 'qb-target' then return wanted end

    if GetResourceState('ox_target') == 'started' then return 'ox_target' end
    if GetResourceState('qb-target') == 'started' then return 'qb-target' end

    print('[as-postalprime] Neither ox_target nor qb-target appears to be started - defaulting to ox_target. Locker interactions will not work until one of them is running.')
    return 'ox_target'
end

local system = detect()

-- Adds a target option to a specific entity (the locker wall prop). Returns nothing - removed
-- later by entity, not by an id, same as both underlying APIs expect for entity targets.
function PPTarget.addEntity(entity, name, icon, label, distance, onSelect)
    if system == 'qb-target' then
        exports['qb-target']:AddTargetEntity(entity, {
            options = {
                { icon = icon, label = label, action = onSelect },
            },
            distance = distance,
        })
    else
        exports.ox_target:addLocalEntity(entity, {
            { name = name, icon = icon, label = label, distance = distance, onSelect = onSelect },
        })
    end
end

function PPTarget.removeEntity(entity)
    if system == 'qb-target' then
        exports['qb-target']:RemoveTargetEntity(entity)
    else
        exports.ox_target:removeLocalEntity(entity)
    end
end

-- Adds a free-floating circular/sphere zone (the "Take Parcel" point). Returns a zone id/name
-- to pass back into PPTarget.removeZone later.
function PPTarget.addSphereZone(name, coords, radius, icon, label, distance, onSelect)
    if system == 'qb-target' then
        exports['qb-target']:AddCircleZone(name, coords, radius, {
            name = name,
            debugPoly = false,
            useZ = true,
        }, {
            options = {
                { icon = icon, label = label, action = onSelect },
            },
            distance = distance,
        })
        return name
    end

    return exports.ox_target:addSphereZone({
        coords = coords,
        radius = radius,
        options = {
            { name = name, icon = icon, label = label, distance = distance, onSelect = onSelect },
        },
    })
end

function PPTarget.removeZone(zoneId)
    if system == 'qb-target' then
        exports['qb-target']:RemoveZone(zoneId)
    else
        exports.ox_target:removeZone(zoneId)
    end
end
