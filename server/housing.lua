-- Housing bridge for home delivery.
-- PPHousing.list(cid)         -> every property this character can have a parcel delivered to
-- PPHousing.resolve(cid, key) -> one of those (or nil) - used at checkout so the client can never
--                                pick an address it has no access to.
--
-- A property is deliverable when the character OWNS it, RENTS it (nolag), or is a KEYHOLDER on it -
-- except brutal_housing, where only OWNERSHIP can be checked from the database (see the note above
-- listBrutal below for why). Supports nolag_properties, qbx_properties, brutal_housing (v2) and
-- rcore_housing; with Config.home.housing = 'auto' every supported script that is started is queried
-- and the results are merged (keys are prefixed "nolag:" / "qbx:" / "brutal:" / "rcore:"). All of them
-- read straight from the housing script's own database tables via oxmysql, so it works whether or not
-- the property is currently loaded/spawned.

PPHousing = {}
local warned = {}

local function pick(t, ...)
    for _, k in ipairs({ ... }) do
        if t[k] ~= nil then return t[k] end
    end
end

-- Accepts {x,y,z,w}, {1,2,3,4} or a stringified version of either; returns {x,y,z,w} or nil.
local function toPoint(v)
    if type(v) == 'string' then
        local ok, decoded = pcall(json.decode, v)
        if not ok then return nil end
        v = decoded
    end
    if type(v) ~= 'table' then return nil end
    -- pick() returns nothing (not nil) when no key matches, and tonumber() with no argument throws: wrap in ( )
    local x, y, z = tonumber((pick(v, 'x', 1))), tonumber((pick(v, 'y', 2))), tonumber((pick(v, 'z', 3)))
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, w = tonumber((pick(v, 'w', 'h', 4))) or 0.0 }
end

local function decode(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, out = pcall(json.decode, s)
    return ok and type(out) == 'table' and out or nil
end

-- ─── nolag_properties ────────────────────────────────────────────────────────

local function listNolag(cid)
    local rows
    local ok, err = pcall(function()
        rows = MySQL.query.await([[
            SELECT p.id, p.address, p.label, p.metadata AS pmeta, b.metadata AS bmeta
            FROM properties p
            LEFT JOIN buildings b ON b.id = p.buildingid
            LEFT JOIN properties_owners po ON po.id = p.ownerid
            LEFT JOIN properties_renters pr ON pr.id = p.renterid
            WHERE (po.type = 'user' AND po.identifier = ?)
               OR (pr.type = 'user' AND pr.identifier = ?)
               OR JSON_CONTAINS_PATH(p.keyholders, 'one', ?)
        ]], { cid, cid, ('$."%s"'):format(cid) })
    end)
    if not ok then
        if not warned.nolag then
            warned.nolag = true
            print(('[as-postalprime] nolag_properties lookup failed (shown once; is this really nolag_properties? set Config.home.housing to your housing script): %s'):format(tostring(err)))
        end
        return {}
    end

    local out = {}
    for _, r in ipairs(rows or {}) do
        local pmeta, bmeta = decode(r.pmeta), decode(r.bmeta)
        -- Same priority the script's own GetAllProperties export uses: building entrance, then the
        -- property's own entrance, then its manage point.
        local coords = (bmeta and toPoint(bmeta.enterData))
            or (pmeta and toPoint(pmeta.enterData))
            or (pmeta and toPoint(pmeta.managePoint))
        if coords then
            local label = (r.label and r.label ~= '') and r.label or r.address or T('housing.property', r.id)
            out[#out + 1] = {
                key = 'nolag:' .. r.id,
                label = label,
                address = r.address,
                coords = coords,
            }
        end
    end
    return out
end

-- ─── qbx_properties ──────────────────────────────────────────────────────────

local function listQbx(cid)
    local rows
    local ok, err = pcall(function()
        rows = MySQL.query.await([[
            SELECT id, property_name, coords
            FROM properties
            WHERE owner = ? OR JSON_CONTAINS(keyholders, JSON_QUOTE(?))
        ]], { cid, cid })
    end)
    if not ok then
        if not warned.qbx then
            warned.qbx = true
            print(('[as-postalprime] qbx_properties lookup failed (shown once): %s'):format(tostring(err)))
        end
        return {}
    end

    local out = {}
    for _, r in ipairs(rows or {}) do
        local coords = toPoint(r.coords)
        if coords then
            out[#out + 1] = {
                key = 'qbx:' .. r.id,
                label = r.property_name or T('housing.property', r.id),
                address = r.property_name,
                coords = coords,
            }
        end
    end
    return out
end

-- ─── brutal_housing (v2) ─────────────────────────────────────────────────────
-- Confirmed against a real export of this server's `brutal_housing` table: `owner` holds the same
-- ESX identifier format used everywhere else on this server (e.g. `owned_vehicles.owner`), so an
-- owner match works exactly like the nolag/qbx drivers above.
-- `keyid`, however, is NOT a list of holder identifiers - real rows show values like `Vjybl-9e^Zfp`
-- and `QdtaLl6RHqm5`, i.e. a random per-property lock/key code. Brutal Housing evidently tracks who
-- currently holds a key via a physical key item in inventory (matched against this code at the door),
-- not via a stored list of identifiers - so there is no SQL-only way to tell "this player is a
-- keyholder on this property" from this table alone. Practical effect: home delivery to a
-- brutal_housing address works for the OWNER, but not for a renter/keyholder who isn't the owner on
-- record. If Brutal ever adds a proper renter/keyholder identifier column, tell me the column name
-- and I'll wire it in.
local function listBrutal(cid)
    local rows
    local ok, err = pcall(function()
        rows = MySQL.query.await([[
            SELECT id, label, address, coords, owner
            FROM brutal_housing
            WHERE owner = ?
        ]], { cid })
    end)
    if not ok then
        if not warned.brutal then
            warned.brutal = true
            print(('[as-postalprime] brutal_housing lookup failed (shown once; is this really brutal_housing v2? set Config.home.housing to your housing script): %s'):format(tostring(err)))
        end
        return {}
    end

    local out = {}
    for _, r in ipairs(rows or {}) do
        local coords = toPoint(r.coords)
        if coords then
            local label = (r.label and r.label ~= '') and r.label or r.address or T('housing.property', r.id)
            out[#out + 1] = {
                key = 'brutal:' .. r.id,
                label = label,
                address = r.address,
                coords = coords,
            }
        end
    end
    return out
end

-- ─── rcore_housing ───────────────────────────────────────────────────────────
-- Confirmed straight from rcore_housing's own bridge source (modules/bridge/db/server.lua, which
-- ships unescrowed): `rcore_housing_properties` has `owner` and `tenant` as plain identifier columns,
-- and keyholders live in a separate, normal `rcore_housing_accesses` (property_id, identifier,
-- permissions) table - a real join, not a guessed blob format, so all three access types work.
-- `coords` is stored wrapped in a one-element JSON array (`db.RegisterProperty` does
-- `originModel.coords = { originModel.coords }` before insert), so it's unwrapped below before
-- being run through the normal {x,y,z,w} decoder. A unit that belongs to a building
-- (`parent_building_id` set) has its own `coords` cleared at creation and is meant to use the
-- building's entry point instead, so the query joins the parent row and falls back to its coords.
local function unwrapCoords(raw)
    local v = decode(raw) or (type(raw) == 'table' and raw or nil)
    if type(v) ~= 'table' then return nil end
    if type(v[1]) == 'table' then v = v[1] end
    return toPoint(v)
end

local function listRcore(cid)
    local rows
    local ok, err = pcall(function()
        rows = MySQL.query.await([[
            SELECT p.id, p.name, p.address, p.coords AS pcoords, b.coords AS bcoords
            FROM rcore_housing_properties p
            LEFT JOIN rcore_housing_properties b ON b.id = p.parent_building_id
            WHERE (p.is_building = 0 OR p.is_building IS NULL)
              AND (p.is_hidden = 0 OR p.is_hidden IS NULL)
              AND (
                    p.owner = ?
                 OR p.tenant = ?
                 OR p.id IN (SELECT property_id FROM rcore_housing_accesses WHERE identifier = ?)
              )
        ]], { cid, cid, cid })
    end)
    if not ok then
        if not warned.rcore then
            warned.rcore = true
            print(('[as-postalprime] rcore_housing lookup failed (shown once; is this really rcore_housing? set Config.home.housing to your housing script): %s'):format(tostring(err)))
        end
        return {}
    end

    local out = {}
    for _, r in ipairs(rows or {}) do
        local coords = unwrapCoords(r.pcoords) or unwrapCoords(r.bcoords)
        if coords then
            local label = (r.name and r.name ~= '' and r.name ~= 'Unnamed') and r.name or r.address or T('housing.property', r.id)
            out[#out + 1] = {
                key = 'rcore:' .. r.id,
                label = label,
                address = r.address,
                coords = coords,
            }
        end
    end
    return out
end

-- ─── public API ──────────────────────────────────────────────────────────────

local function enabledScripts()
    local want = (Config.home and Config.home.housing) or 'auto'
    local out = {}
    if (want == 'auto' or want == 'nolag_properties') and GetResourceState('nolag_properties') == 'started' then
        out[#out + 1] = listNolag
    end
    if (want == 'auto' or want == 'qbx_properties') and GetResourceState('qbx_properties') == 'started' then
        out[#out + 1] = listQbx
    end
    if (want == 'auto' or want == 'brutal_housing') and GetResourceState('brutal_housing') == 'started' then
        out[#out + 1] = listBrutal
    end
    if (want == 'auto' or want == 'rcore_housing') and GetResourceState('rcore_housing') == 'started' then
        out[#out + 1] = listRcore
    end
    return out
end

-- cid is sanitised because it ends up inside a JSON path for the nolag keyholder lookup.
local function validCid(cid)
    return type(cid) == 'string' and cid ~= '' and cid:match('^[%w_%-%.:@]+$') ~= nil
end

function PPHousing.list(cid)
    if not validCid(cid) then return {} end
    local out = {}
    for _, fn in ipairs(enabledScripts()) do
        for _, p in ipairs(fn(cid)) do out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    return out
end

function PPHousing.resolve(cid, key)
    for _, p in ipairs(PPHousing.list(cid)) do
        if p.key == key then return p end
    end
    return nil
end

function PPHousing.available()
    return #enabledScripts() > 0
end

return PPHousing
