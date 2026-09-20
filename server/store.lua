-- SQL-backed store (oxmysql). Each player's whole {active, history, plus} table and each
-- review are kept as a JSON blob in their own row - this keeps every call site in server/main.lua
-- unchanged (it still just reads/writes plain Lua tables in memory) while everything actually
-- persists to your database instead of a JSON file on disk, and survives independently of the
-- resource's own files.

PPStore = {}
PPStore.players = {}   -- [identifier] = { active = order|nil, history = { order, ... }, plus = {...}|nil }
PPStore.reviews = {}   -- [itemId] = { [identifier] = { rating, title, body, name, createdAt } }
PPStore.stock = {}     -- [itemId] = remaining count - only present for items with a configured stock cap
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

    -- If any table already got created (e.g. by an earlier, buggy version of this file) with
    -- the database's default charset instead of utf8mb4, force it over now rather than leaving
    -- every emoji-containing save broken.
    pcall(query, 'ALTER TABLE postalprime_players CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_reviews CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
    pcall(query, 'ALTER TABLE postalprime_stock CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci')
end

local normalize -- defined below, next to getPlayer

local function loadAll()
    local playerRows = query('SELECT identifier, data FROM postalprime_players', {})
    for _, row in ipairs(playerRows or {}) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then
            PPStore.players[row.identifier] = decoded
            normalize(decoded)
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

function PPStore.savePlayer(cid)
    local pd = PPStore.players[cid]
    if not pd then return end
    query(
        'INSERT INTO postalprime_players (identifier, data, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = VALUES(updated_at)',
        { cid, json.encode(pd), os.time() }
    )
end

-- Kept for anything that still wants to flush everything at once (e.g. on shutdown) - most call
-- sites should prefer PPStore.savePlayer(cid) for a single player's change.
function PPStore.savePlayers()
    for cid in pairs(PPStore.players) do
        PPStore.savePlayer(cid)
    end
end

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

-- Parcels sent by other resources live in pd.parcels so they never block shopping. Older saves kept
-- them in pd.active - move those over.
normalize = function(pd)
    if not pd.wishlist then pd.wishlist = {} end -- back-fills older saved rows from before wishlists existed
    if not pd.parcels then pd.parcels = {} end
    if pd.active and pd.active.parcel then
        pd.parcels[#pd.parcels + 1] = pd.active
        pd.active = nil
    end
end

function PPStore.getPlayer(cid)
    while not PPStore.ready do Wait(0) end -- guards against a request landing before the initial SQL load finishes
    if not PPStore.players[cid] then
        PPStore.players[cid] = { active = nil, history = {}, wishlist = {}, parcels = {} }
    end
    normalize(PPStore.players[cid])
    return PPStore.players[cid]
end

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    PPStore.savePlayers()
    PPStore.saveReviews()
end)

return PPStore
