-- Housing bridge for home delivery.
-- PPHousing.list(cid)         -> every property this character can have a parcel delivered to
-- PPHousing.resolve(cid, key) -> one of those (or nil) - used at checkout so the client can never
--                                pick an address it has no access to.
--
-- A property is deliverable when the character OWNS it, RENTS it (nolag), or is a KEYHOLDER on it.
-- Supports nolag_properties and qbx_properties; with Config.home.housing = 'auto' every supported
-- script that is started is queried and the results are merged (keys are prefixed "nolag:" / "qbx:").
-- Both read straight from the housing script's own database tables via oxmysql, so it works whether
-- or not the property is currently loaded/spawned.

PPHousing = {}

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
    local x, y, z = tonumber(pick(v, 'x', 1)), tonumber(pick(v, 'y', 2)), tonumber(pick(v, 'z', 3))
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, w = tonumber(pick(v, 'w', 'h', 4)) or 0.0 }
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
        print(('[as-postalprime] nolag_properties lookup failed: %s'):format(tostring(err)))
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
        print(('[as-postalprime] qbx_properties lookup failed: %s'):format(tostring(err)))
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
