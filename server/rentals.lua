-- Locker rentals (Config.rentals): rent a private storage door at a locker. The renter gets a 6-digit code; typing it into
-- that locker's keypad opens an ox_inventory stash. See PPRentals.match, used by the keypad in server/lockers.lua.

PPRentals = {}

local track = PP.track
local round2 = PPDeals.round2

local function cfg() return Config.rentals or {} end

function PPRentals.enabled()
    return Config.rentals ~= nil and cfg().enabled ~= false and PPBridge.inventoryName() == 'ox_inventory'
end

local function randomHex(n)
    local t = {}
    for i = 1, n do t[i] = ('%x'):format(math.random(0, 15)) end
    return table.concat(t)
end

local function registerStash(r)
    pcall(function()
        exports.ox_inventory:RegisterStash(r.stash, ('Rented locker #%d'):format(r.id), cfg().slots or 15, cfg().weight or 50000, false)
    end)
end

local function graceSeconds() return (cfg().graceHours or 24) * 3600 end

-- ─── lookups ─────────────────────────────────────────────────────────────────

function PPRentals.hasAt(lockerId)
    if not PPRentals.enabled() then return false end
    for _, r in pairs(PPStore.rentals) do
        if r.lockerId == lockerId then return true end
    end
    return false
end

-- The live (not expired) rental at a locker with this code, or nil.
function PPRentals.match(lockerId, code)
    if not PPRentals.enabled() or code == '' then return nil end
    local now = os.time()
    for _, r in pairs(PPStore.rentals) do
        if r.lockerId == lockerId and r.code == code and r.expiresAt > now then return r end
    end
    return nil
end

function PPRentals.open(source, rental)
    PPLog.log('rental', source, ('opened rented locker #%d at %s'):format(rental.id, rental.lockerId), { rental = rental.id })
    SetTimeout(1800, function() -- let the keypad's success message show first
        local ok, err = pcall(function() exports.ox_inventory:forceOpenInventory(source, 'stash', rental.stash) end)
        if not ok then print(('[as-postalprime] could not open rental stash %s: %s'):format(rental.stash, tostring(err))) end
    end)
end

local function mine(cid)
    local out = {}
    for _, r in pairs(PPStore.rentals) do
        if r.owner == cid then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function PPRentals.stateFor(cid)
    if not PPRentals.enabled() then return { enabled = false } end
    local now = os.time()
    local counts = {}
    for _, r in pairs(PPStore.rentals) do counts[r.lockerId] = (counts[r.lockerId] or 0) + 1 end
    local lockers = {}
    for _, l in ipairs(Config.lockers) do
        lockers[#lockers + 1] = { id = l.id, label = l.label, free = math.max(0, (cfg().maxPerLocker or 10) - (counts[l.id] or 0)) }
    end
    local list = {}
    for _, r in ipairs(mine(cid)) do
        list[#list + 1] = {
            id = r.id, lockerId = r.lockerId, lockerLabel = (PP.findLocker(r.lockerId) or {}).label or r.lockerId,
            code = r.code, expiresAt = r.expiresAt * 1000, expired = r.expiresAt <= now,
            graceEndsAt = (r.expiresAt + graceSeconds()) * 1000,
        }
    end
    return {
        enabled = true, pricePerDay = cfg().pricePerDay or 50, maxDays = cfg().maxDays or 7,
        maxPerPlayer = cfg().maxPerPlayer or 2, lockers = lockers, mine = list,
    }
end

-- ─── actions ─────────────────────────────────────────────────────────────────

local function clampDays(v)
    local d = math.floor(tonumber(v) or 0)
    if d < 1 or d > (cfg().maxDays or 7) then return nil end
    return d
end

local function freshCode(lockerId)
    for _ = 1, 50 do
        local code = PP.newCode()
        local clash = false
        for _, r in pairs(PPStore.rentals) do
            if r.lockerId == lockerId and r.code == code then clash = true break end
        end
        if not clash then return code end
    end
    return PP.newCode()
end

lib.callback.register('as-postalprime:rentals:rent', function(source, data)
    local cid = track(source)
    if not cid then return { ok = false, error = T('err.unavailable') } end
    if not PPRentals.enabled() then return { ok = false, error = T('err.rent.off') } end
    if type(data) ~= 'table' then return { ok = false, error = T('err.badRequest') } end

    local days = clampDays(data.days)
    if not days then return { ok = false, error = T('err.rent.days', cfg().maxDays or 7) } end
    if not PP.findLocker(data.lockerId) then return { ok = false, error = T('err.pickLocker') } end
    if #mine(cid) >= (cfg().maxPerPlayer or 2) then return { ok = false, error = T('err.rent.max', cfg().maxPerPlayer or 2) } end
    local atLocker = 0
    for _, r in pairs(PPStore.rentals) do if r.lockerId == data.lockerId then atLocker = atLocker + 1 end end
    if atLocker >= (cfg().maxPerLocker or 10) then return { ok = false, error = T('err.rent.full') } end

    local price = round2((cfg().pricePerDay or 50) * days)
    if not PP.charge(source, price) then return { ok = false, error = T('err.noCash') } end

    local id = PPStore.nextRentalId()
    local r = {
        id = id, owner = cid, ownerName = PPBridge.getCharacterName(source), lockerId = data.lockerId,
        code = freshCode(data.lockerId), stash = ('pp_rental_%d_%s'):format(id, randomHex(10)),
        startedAt = os.time(), expiresAt = os.time() + days * 86400,
    }
    PPStore.rentals[id] = r
    registerStash(r)
    PPStore.saveRental(id)
    PPStats.bump('rentals', 1)
    PPStats.bump('rentalRevenue', price)
    PPLog.log('rental', source, ('rented locker #%d at %s for %d day(s), $%s'):format(id, r.lockerId, days, price), { rental = id })
    return { ok = true, rentals = PPRentals.stateFor(cid) }
end)

local function ownRental(cid, id)
    local r = PPStore.rentals[tonumber(id) or -1]
    if r and r.owner == cid then return r end
end

lib.callback.register('as-postalprime:rentals:extend', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false, error = T('err.unavailable') } end
    local r = ownRental(cid, data.id)
    if not r then return { ok = false, error = T('err.rent.gone') } end
    local days = clampDays(data.days)
    if not days then return { ok = false, error = T('err.rent.days', cfg().maxDays or 7) } end

    local now = os.time()
    local base = math.max(r.expiresAt, now)
    if base + days * 86400 - now > 30 * 86400 then return { ok = false, error = T('err.rent.tooLong') } end
    local price = round2((cfg().pricePerDay or 50) * days)
    if not PP.charge(source, price) then return { ok = false, error = T('err.noCash') } end

    r.expiresAt = base + days * 86400
    r.warned, r.expiredNotified = nil, nil
    PPStore.saveRental(r.id)
    PPStats.bump('rentalRevenue', price)
    PPLog.log('rental', source, ('extended locker #%d by %d day(s), $%s'):format(r.id, days, price), { rental = r.id })
    return { ok = true, rentals = PPRentals.stateFor(cid) }
end)

lib.callback.register('as-postalprime:rentals:newCode', function(source, data)
    local cid = track(source)
    if not cid or type(data) ~= 'table' then return { ok = false, error = T('err.unavailable') } end
    local r = ownRental(cid, data.id)
    if not r then return { ok = false, error = T('err.rent.gone') } end
    r.code = freshCode(r.lockerId)
    PPStore.saveRental(r.id)
    return { ok = true, rentals = PPRentals.stateFor(cid) }
end)

-- ─── upkeep ──────────────────────────────────────────────────────────────────

function PPRentals.finish(r, reason)
    if cfg().clearOnExpire then
        pcall(function() exports.ox_inventory:ClearInventory(r.stash) end)
    end
    PPStore.deleteRental(r.id)
    PPLog.log('rental', nil, ('rental #%d at %s ended (%s)'):format(r.id, r.lockerId, reason), { rental = r.id })
end

CreateThread(function()
    Wait(4000)
    for _, r in pairs(PPStore.rentals) do registerStash(r) end -- stashes are not remembered across restarts
    while true do
        Wait(60000)
        if PPRentals.enabled() then
            local now = os.time()
            local ended = {}
            for _, r in pairs(PPStore.rentals) do
                if now > r.expiresAt + graceSeconds() then
                    ended[#ended + 1] = r
                elseif now > r.expiresAt and not r.expiredNotified then
                    r.expiredNotified = true
                    PPStore.saveRental(r.id)
                    PP.notifyCid(r.owner, T('notif.rent.expired.title'), T('notif.rent.expired.body', cfg().graceHours or 24))
                elseif r.expiresAt - now < 3600 and now <= r.expiresAt and not r.warned then
                    r.warned = true
                    PPStore.saveRental(r.id)
                    PP.notifyCid(r.owner, T('notif.rent.soon.title'), T('notif.rent.soon.body'))
                end
            end
            for _, r in ipairs(ended) do
                PP.notifyCid(r.owner, T('notif.rent.ended.title'), T('notif.rent.ended.body'))
                PPRentals.finish(r, 'grace period over')
            end
        end
    end
end)

return PPRentals
