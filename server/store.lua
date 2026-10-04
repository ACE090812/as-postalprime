-- SQL-backed store (oxmysql). Each player's whole {active, history, plus} table and each
-- review are kept as a JSON blob in their own row - this keeps every call site in server/main.lua
-- unchanged (it still just reads/writes plain Lua tables in memory) while everything actually
-- persists to your database instead of a JSON file on disk, and survives independently of the
-- resource's own files.

PPStore = {}
PPStore.players = {}   -- [identifier] = { orders = { order, ... }, parcels = { order, ... }, history = { order, ... }, plus = {...}|nil, ... }
PPStore.reviews = {}   -- [itemId] = { [identifier] = { rating, title, body, name, createdAt } }
PPStore.stock = {}     -- [itemId] = remaining count - only present for items with a configured stock cap
PPStore.listings = {}  -- [id (number)] = marketplace listing (see server/market.lua)
PPStore.couponUses = {} -- [CODE] = how many times the coupon has been used server-wide
PPStore.rentals = {}   -- [id (number)] = locker rental (see server/rentals.lua)
PPStore.daily = {}     -- ['YYYY-MM-DD'] = { revenue = n, orders = n, ... } sales counters (see server/stats.lua)
PPStore.ready = false

-- Wraps oxmysql's callback API in an explicit promise/await so this genuinely blocks the calling
-- thread until the query finishes - relying on oxmysql's own implicit promise-return behaviour
-- caused CREATE TABLE and the very first SELECT/INSERT to race each other (the table sometimes
-- didn't exist yet when the first query ran). This works the same regardless of oxmysql version.
local function query(sql, params)
    local p = promise.new()
    exports.oxmysql:execute(sql, params or {}, function(result)
        p:resolve(result)
    end)
    return Citizen.Await(p)
end

local function ensureTables()
    -- utf8mb4 is required, not just nice-to-have: catalog icons and pasted review text can
    -- contain emoji (4-byte UTF-8), and MySQL's default 'utf8' charset only supports up to 3
    -- bytes per character - inserting an emoji into a plain 'utf8' column fails outright.
    query([[
        CREATE TABLE IF NOT EXISTS postalprime_players (
            identifier VARCHAR(64) NOT NULL PRIMARY KEY,
            data LONGTEXT NOT NULL,
            updated_at INT UNSIGNED NOT NULL
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ]])
    query([[
        CREATE TABLE IF NOT EXISTS postalprime_reviews (
            item_id VARCHAR(64) NOT NULL,
            identifier VARCHAR(64) NOT NULL,
            data LONGTEXT NOT NULL,
            updated_at INT UNSIGNED NOT NULL,
            PRIMARY KEY (item_id, identifier)
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ]])
    query([[
        CREATE TABLE IF NOT EXISTS postalprime_stock (
            item_id VARCHAR(64) NOT NULL PRIMARY KEY,
            remaining INT NOT NULL
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ]])

    query([[
        CREATE TABLE IF NOT EXISTS postalprime_listings (
            id INT NOT NULL PRIMARY KEY,
            data LONGTEXT NOT NULL,
            updated_at INT UNSIGNED NOT NULL
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ]])
    query([[
        CREATE TABLE IF NOT EXISTS postalprime_rentals (
            id INT NOT NULL PRIMARY KEY,
            data LONGTEXT NOT NULL,
            updated_at INT UNSIGNED NOT NULL
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ]])
    query([[
        CREATE TABLE IF NOT EXISTS postalprime_daily (
            day VARCHAR(10) NOT NULL PRIMARY KEY,
            data LONGTEXT NOT NULL
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ]])
    query([[
        CREATE TABLE IF NOT EXISTS postalprime_coupons (
            code VARCHAR(64) NOT NULL PRIMARY KEY,
            uses INT NOT NULL
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ]])

    -- If any table already got created (e.g. by an earlier, buggy version of this file) with
    -- the database's default charset instead of utf8mb4, force it over now rather than leaving
    -- every emoji-containing save broken.
    pcall(query, 'ALTER TABLE postalprime_players CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_reviews CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_stock CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_listings CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_rentals CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_daily CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_coupons CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
end

local normalize -- defined below, next to getPlayer
local lastSaved = {}   -- [cid] = the JSON last written, so an unchanged player is never written again
local dirty = {}       -- [cid] = true for players waiting for the next batched flush

local function loadAll()
    local playerRows = query('SELECT identifier, data FROM postalprime_players', {})
    for _, row in ipairs(playerRows or {}) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then
            PPStore.players[row.identifier] = decoded
            normalize(decoded)
            lastSaved[row.identifier] = json.encode(decoded)
        end
    end

    local reviewRows = query('SELECT item_id, identifier, data FROM postalprime_reviews', {})
    for _, row in ipairs(reviewRows or {}) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then
            PPStore.reviews[row.item_id] = PPStore.reviews[row.item_id] or {}
            PPStore.reviews[row.item_id][row.identifier] = decoded
        end
    end

    local stockRows = query('SELECT item_id, remaining FROM postalprime_stock', {})
    for _, row in ipairs(stockRows or {}) do
        PPStore.stock[row.item_id] = tonumber(row.remaining)
    end

    local listingRows = query('SELECT id, data FROM postalprime_listings', {})
    for _, row in ipairs(listingRows or {}) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then
            decoded.id = tonumber(row.id)
            PPStore.listings[decoded.id] = decoded
        end
    end

    local rentalRows = query('SELECT id, data FROM postalprime_rentals', {})
    for _, row in ipairs(rentalRows or {}) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then
            decoded.id = tonumber(row.id)
            PPStore.rentals[decoded.id] = decoded
        end
    end

    -- Only the last 120 days of sales counters are kept in memory (older rows stay in the table).
    local dailyRows = query("SELECT day, data FROM postalprime_daily WHERE day >= DATE_FORMAT(DATE_SUB(NOW(), INTERVAL 120 DAY), '%Y-%m-%d')", {})
    for _, row in ipairs(dailyRows or {}) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then PPStore.daily[row.day] = decoded end
    end

    local couponRows = query('SELECT code, uses FROM postalprime_coupons', {})
    for _, row in ipairs(couponRows or {}) do
        PPStore.couponUses[row.code] = tonumber(row.uses) or 0
    end

    -- Seed a starting row for any catalog item that has a configured stock cap but no row yet
    -- (first boot, or a stock cap just added to config.lua). Items with no `stock` field at all
    -- stay unlimited forever - they never get a row.
    for _, entry in ipairs(Config.catalog) do
        if entry.stock ~= nil and PPStore.stock[entry.id] == nil then
            PPStore.stock[entry.id] = entry.stock
            query('INSERT IGNORE INTO postalprime_stock (item_id, remaining) VALUES (?, ?)', { entry.id, entry.stock })
        end
    end
end

CreateThread(function()
    local ok, err = pcall(function()
        ensureTables()
        loadAll()
    end)
    if not ok then
        print(('[as-postalprime] SQL setup failed: %s'):format(tostring(err)))
    end
    PPStore.ready = true -- unblock getPlayer() either way rather than hang the resource forever
    print(('[as-postalprime] loaded %d player record(s) and reviews from SQL'):format((function()
        local n = 0
        for _ in pairs(PPStore.players) do n = n + 1 end
        return n
    end)()))
end)

-- Writes one player right now, unless nothing about them changed since the last write. Use this for anything
-- involving money or items (checkout, refunds, collecting).
function PPStore.savePlayer(cid)
    dirty[cid] = nil
    local pd = PPStore.players[cid]
    if not pd then return end
    local encoded = json.encode(pd)
    if lastSaved[cid] == encoded then return end
    query(
        'INSERT INTO postalprime_players (identifier, data, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = VALUES(updated_at)',
        { cid, encoded, os.time() }
    )
    lastSaved[cid] = encoded
end

-- Queues a minor change (cart, wishlist, flags, things the sweep can re-derive) for the next batched flush.
function PPStore.markDirty(cid)
    if PPStore.players[cid] then dirty[cid] = true end
end

function PPStore.flush()
    local list = {}
    for cid in pairs(dirty) do list[#list + 1] = cid end
    for _, cid in ipairs(list) do PPStore.savePlayer(cid) end
end

-- Flush everything that changed (shutdown). Unchanged players are skipped by savePlayer itself.
function PPStore.savePlayers()
    for cid in pairs(PPStore.players) do
        PPStore.savePlayer(cid)
    end
end

CreateThread(function()
    while true do
        Wait(math.max(1, (Config.storage and Config.storage.flushSeconds) or 5) * 1000)
        if next(dirty) then PPStore.flush() end
    end
end)

AddEventHandler('playerDropped', function()
    -- A leaving player's pending minor changes go to the database now rather than waiting for the batch.
    PPStore.flush()
end)

function PPStore.saveReview(itemId, cid)
    local review = PPStore.reviews[itemId] and PPStore.reviews[itemId][cid]
    if not review then return end
    query(
        'INSERT INTO postalprime_reviews (item_id, identifier, data, updated_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = VALUES(updated_at)',
        { itemId, cid, json.encode(review), os.time() }
    )
end

function PPStore.saveReviews()
    for itemId, bucket in pairs(PPStore.reviews) do
        for cid in pairs(bucket) do
            PPStore.saveReview(itemId, cid)
        end
    end
end

-- nil = unlimited (no stock cap configured for this item at all).
function PPStore.getStock(itemId)
    return PPStore.stock[itemId]
end

-- Returns false without changing anything if there isn't enough left; only actually spends
-- when the full requested quantity is available.
function PPStore.trySpendStock(itemId, qty)
    local remaining = PPStore.stock[itemId]
    if remaining == nil then return true end -- unlimited
    if remaining < qty then return false end
    PPStore.stock[itemId] = remaining - qty
    query('UPDATE postalprime_stock SET remaining = ? WHERE item_id = ?', { PPStore.stock[itemId], itemId })
    return true
end

-- Used by the pprestock console command. Also works for an item with no cap yet (starts one).
function PPStore.restock(itemId, amount)
    local newTotal = (PPStore.stock[itemId] or 0) + amount
    PPStore.stock[itemId] = newTotal
    query(
        'INSERT INTO postalprime_stock (item_id, remaining) VALUES (?, ?) ON DUPLICATE KEY UPDATE remaining = VALUES(remaining)',
        { itemId, newTotal }
    )
    return newTotal
end

-- Marketplace listings (server/market.lua owns the rules; this is just persistence).
function PPStore.saveListing(id)
    local l = PPStore.listings[id]
    if not l then return end
    query(
        'INSERT INTO postalprime_listings (id, data, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = VALUES(updated_at)',
        { id, json.encode(l), os.time() }
    )
end

function PPStore.saveRental(id)
    local r = PPStore.rentals[id]
    if not r then return end
    query(
        'INSERT INTO postalprime_rentals (id, data, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = VALUES(updated_at)',
        { id, json.encode(r), os.time() }
    )
end

function PPStore.deleteRental(id)
    PPStore.rentals[id] = nil
    query('DELETE FROM postalprime_rentals WHERE id = ?', { id })
end

function PPStore.nextRentalId()
    local max = 0
    for id in pairs(PPStore.rentals) do if id > max then max = id end end
    return max + 1
end

function PPStore.saveDaily(day)
    local d = PPStore.daily[day]
    if not d then return end
    query(
        'INSERT INTO postalprime_daily (day, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { day, json.encode(d) }
    )
end

function PPStore.deleteListing(id)
    PPStore.listings[id] = nil
    query('DELETE FROM postalprime_listings WHERE id = ?', { id })
end

function PPStore.nextListingId()
    local max = 0
    for id in pairs(PPStore.listings) do if id > max then max = id end end
    return max + 1
end

-- Server-wide coupon use counter (per-character counts live on the player row).
function PPStore.addCouponUse(code, delta)
    local n = math.max(0, (PPStore.couponUses[code] or 0) + delta)
    PPStore.couponUses[code] = n
    query(
        'INSERT INTO postalprime_coupons (code, uses) VALUES (?, ?) ON DUPLICATE KEY UPDATE uses = VALUES(uses)',
        { code, n }
    )
end

-- Shop orders live in pd.orders (several can be in flight - Config.order.maxActive). Parcels sent by other
-- resources live in pd.parcels so they never block shopping. Older saves kept a single pd.active - move it over.
normalize = function(pd)
    if not pd.wishlist then pd.wishlist = {} end -- back-fills older saved rows from before wishlists existed
    if not pd.parcels then pd.parcels = {} end
    if not pd.orders then pd.orders = {} end
    if pd.active then
        local list = pd.active.parcel and pd.parcels or pd.orders
        list[#list + 1] = pd.active
        pd.active = nil
    end
end

function PPStore.getPlayer(cid)
    while not PPStore.ready do Wait(0) end -- guards against a request landing before the initial SQL load finishes
    if not PPStore.players[cid] then
        PPStore.players[cid] = { orders = {}, history = {}, wishlist = {}, parcels = {} }
    end
    normalize(PPStore.players[cid])
    return PPStore.players[cid]
end

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    PPStore.savePlayers()
    PPStore.saveReviews()
    for id in pairs(PPStore.listings) do PPStore.saveListing(id) end
    for id in pairs(PPStore.rentals) do PPStore.saveRental(id) end
    for day in pairs(PPStore.daily) do PPStore.saveDaily(day) end
end)

return PPStore
