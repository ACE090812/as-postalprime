-- Interaction-system bridge: lets Config.target pick 'as-interact', 'ox_target', 'qb-target', or
-- 'auto'. Every other client file goes through PPTarget instead of calling any of those exports
-- directly, so this is the only place that needs to know the three APIs differ.

PPTarget = {}

-- GetResourceState only says a resource is active, not that its scripts ran without error - a
-- resource can report 'started' while a script error (e.g. it started before one of ITS OWN
-- dependencies, like as-interact needing ox_lib) left its exports never registered, which then
-- hard-errors the caller with "No such export ...". Checking the export itself (indexing it
-- inside pcall, without calling it - CitizenFX's export proxy throws on the index, not just the
-- call) confirms it's actually ready to use, not just that the resource exists.
local function hasExport(resource, method)
    local ok, fn = pcall(function() return exports[resource][method] end)
    return ok and fn ~= nil
end

-- Returns the confirmed backend, or nil when nothing is confirmed ready YET but nothing is
-- confirmed missing either (still booting). Distinguishing "not yet" from "never" is what lets
-- system() below wait instead of guessing wrong on a server where the resource happens to start
-- after as-postalprime during a full restart, or where as-interact starts but its own exports
-- take a moment (or fail) to register. Preference order when more than one is installed:
-- as-interact, then ox_target, then qb-target.
local function detect()
    local wanted = Config.target or 'auto'
    if wanted == 'as-interact' or wanted == 'ox_target' or wanted == 'qb-target' then return wanted end

    if GetResourceState('as-interact') == 'started' and hasExport('as-interact', 'AddInteraction') then return 'as-interact' end
    if GetResourceState('ox_target') == 'started' and hasExport('ox_target', 'addLocalEntity') then return 'ox_target' end
    if GetResourceState('qb-target') == 'started' and hasExport('qb-target', 'AddTargetEntity') then return 'qb-target' end
    if GetResourceState('as-interact') == 'missing' and GetResourceState('ox_target') == 'missing'
        and GetResourceState('qb-target') == 'missing' then
        return 'as-interact' -- confirmed none is installed; fall back rather than wait forever
    end
    return nil
end

local resolved = nil

-- Resolves once, waiting up to 10s for one of the three to finish starting if this is called very
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
            -- Something is started but never passed the export check above (most likely
            -- as-interact hit a script error on its own end, e.g. it started before ox_lib) -
            -- fall back to whichever one is at least running, rather than blindly calling a
            -- broken export and hard-erroring every locker/van/take-point registration.
            if GetResourceState('as-interact') == 'started' then
                print('[as-postalprime] as-interact is started but its exports never came up (likely a script error in as-interact itself - check your F8 console and that ox_lib starts before it). Locker interactions will not work until that\'s fixed.')
                resolved = 'as-interact'
            elseif GetResourceState('ox_target') == 'started' then
                resolved = 'ox_target'
            elseif GetResourceState('qb-target') == 'started' then
                resolved = 'qb-target'
            else
                print('[as-postalprime] Neither as-interact, ox_target nor qb-target appears to be started after 10s - defaulting to as-interact. Locker interactions will not work until one of them is running.')
                resolved = 'as-interact'
            end
            return resolved
        end
        Wait(100)
    end
end

-- Belt-and-suspenders for the timeout fallback above: if the "resolved" backend's export still
-- isn't actually callable (system() gave up waiting), don't hard-error the caller - warn once and
-- return nil so addEntity/addSphereZone just skip registering that interaction instead of
-- breaking the whole resource.
local warnedBroken = {}
local function call(resource, method, ...)
    local ok, result = pcall(function(...) return exports[resource][method](exports[resource], ...) end, ...)
    if ok then return result end
    if not warnedBroken[resource] then
        warnedBroken[resource] = true
        print(('[as-postalprime] %s:%s failed (%s) - %s is started but not actually working, so its locker/van/take-point interactions will be missing until it\'s fixed.'):format(resource, method, tostring(result), resource))
    end
    return nil
end

-- as-interact's Add* exports return an id used to remove/update later, but addEntity/removeEntity
-- are called by entity handle everywhere else in this resource (same shape ox_target/qb-target
-- expect), so we keep our own entity -> id map for that backend only.
local entityIds = {}

-- Adds a target option to a specific entity (the locker wall prop / courier van). Returns
-- nothing - removed later by entity, not by an id, same as all three underlying APIs expect for
-- entity targets (as-interact ids are tracked internally, see entityIds above).
-- canInteract (optional): function() -> boolean, checked every time the option would show.
function PPTarget.addEntity(entity, name, icon, label, distance, onSelect, canInteract)
    local sys = system()
    if sys == 'qb-target' then
        call('qb-target', 'AddTargetEntity', entity, {
            options = {
                { icon = icon, label = label, action = onSelect, canInteract = canInteract and function() return canInteract() end or nil },
            },
            distance = distance,
        })
    elseif sys == 'as-interact' then
        entityIds[entity] = call('as-interact', 'AddLocalEntityInteraction', {
            entity = entity,
            distance = distance,
            interactDst = distance,
            options = {
                { name = name, label = label, action = function() onSelect() end,
                  canInteract = canInteract and function() return canInteract() end or nil },
            },
        })
    else
        call('ox_target', 'addLocalEntity', entity, {
            { name = name, icon = icon, label = label, distance = distance, onSelect = onSelect,
              canInteract = canInteract and function() return canInteract() end or nil },
        })
    end
end

function PPTarget.removeEntity(entity)
    local sys = system()
    if sys == 'qb-target' then
        call('qb-target', 'RemoveTargetEntity', entity)
    elseif sys == 'as-interact' then
        local id = entityIds[entity]
        if id then
            call('as-interact', 'RemoveInteraction', id)
            entityIds[entity] = nil
        else
            -- Fallback in case addEntity was never tracked (e.g. called before this file loaded).
            call('as-interact', 'RemoveInteractionByEntity', entity)
        end
    else
        call('ox_target', 'removeLocalEntity', entity)
    end
end

-- Adds a free-floating circular/sphere zone (the "Take Parcel" point). Returns a zone id/name
-- to pass back into PPTarget.removeZone later. as-interact has no separate radius/zone concept -
-- its distance/interactDst already define how close the player must be, so radius maps onto
-- interactDst there (see the field mapping note below).
function PPTarget.addSphereZone(name, coords, radius, icon, label, distance, onSelect, canInteract)
    local sys = system()
    if sys == 'qb-target' then
        call('qb-target', 'AddCircleZone', name, coords, radius, {
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

    if sys == 'as-interact' then
        -- distance = how close for the point's dot to appear (matches ox_target/qb-target's outer
        -- "distance"); interactDst = how close for the prompt/E to work (matches the zone's radius).
        return call('as-interact', 'AddInteraction', {
            coords = coords,
            distance = distance,
            interactDst = radius,
            name = name,
            options = {
                { name = name, label = label, action = function() onSelect() end,
                  canInteract = canInteract and function() return canInteract() end or nil },
            },
        })
    end

    return call('ox_target', 'addSphereZone', {
        coords = coords,
        radius = radius,
        options = {
            { name = name, icon = icon, label = label, distance = distance, onSelect = onSelect,
              canInteract = canInteract and function() return canInteract() end or nil },
        },
    })
end

function PPTarget.removeZone(zoneId)
    if not zoneId then return end
    local sys = system()
    if sys == 'qb-target' then
        call('qb-target', 'RemoveZone', zoneId)
    elseif sys == 'as-interact' then
        call('as-interact', 'RemoveInteraction', zoneId)
    else
        call('ox_target', 'removeZone', zoneId)
    end
end
