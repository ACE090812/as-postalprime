-- Startup self-check of config.lua and the locale files. Prints what is wrong in plain words instead of letting it fail
-- halfway through a player's order. Re-run any time from the server console with:  ppcheck

PPValidate = {}

local PREFIX = '[as-postalprime] '

local function itemExists(name)
    if GetResourceState('ox_inventory') == 'started' then
        local ok, def = pcall(function() return exports.ox_inventory:Items(name) end)
        if ok then return def ~= nil and def ~= false end
    end
    return nil -- can't tell (other inventory)
end

local function placeholders(s)
    local n = 0
    for _ in tostring(s):gmatch('%%[sd]') do n = n + 1 end
    return n
end

function PPValidate.locales(errors, warns)
    local en = Locales.en or {}
    for code, dict in pairs(Locales) do
        if code ~= 'en' then
            local missing, extra, badFmt = {}, {}, {}
            for k, v in pairs(en) do
                if dict[k] == nil then missing[#missing + 1] = k
                elseif placeholders(dict[k]) ~= placeholders(v) then badFmt[#badFmt + 1] = k end
            end
            for k in pairs(dict) do if en[k] == nil then extra[#extra + 1] = k end end
            table.sort(missing); table.sort(extra); table.sort(badFmt)
            if #missing > 0 then
                warns[#warns + 1] = ('locale "%s" is missing %d key(s) (they fall back to English): %s%s'):format(code, #missing,
                    table.concat(missing, ', ', 1, math.min(5, #missing)), #missing > 5 and ', ...' or '')
            end
            if #badFmt > 0 then
                errors[#errors + 1] = ('locale "%s": %%s/%%d placeholder count differs from English in: %s'):format(code, table.concat(badFmt, ', ', 1, math.min(5, #badFmt)))
            end
            if #extra > 0 then
                warns[#warns + 1] = ('locale "%s" has %d key(s) English does not: %s'):format(code, #extra, table.concat(extra, ', ', 1, math.min(5, #extra)))
            end
        end
    end
    if not Locales[Config.locale or 'en'] then
        errors[#errors + 1] = ('Config.locale = "%s" but there is no locales/%s.lua'):format(tostring(Config.locale), tostring(Config.locale))
    end
end

function PPValidate.run()
    local errors, warns = {}, {}
    local function err(fmt, ...) errors[#errors + 1] = fmt:format(...) end
    local function warn(fmt, ...) warns[#warns + 1] = fmt:format(...) end

    -- Dependencies
    for _, res in ipairs({ 'ox_lib', 'oxmysql', 'sd-phone' }) do
        if GetResourceState(res) ~= 'started' then err('required resource "%s" is not started', res) end
    end
    if GetResourceState('as-lockerprops') ~= 'started' then warn('"as-lockerprops" (the locker wall model) is not started') end

    -- Categories and catalog
    local cats = {}
    for _, c in ipairs(Config.categories or {}) do cats[c.id] = true end
    local ids, checkedItems = {}, {}
    local function checkItem(name, what)
        if type(name) ~= 'string' or name == '' then err('%s has no inventory item name', what) return end
        if checkedItems[name] then return end
        checkedItems[name] = true
        if itemExists(name) == false then err('%s: item "%s" does not exist in ox_inventory', what, name) end
    end
    for i, e in ipairs(Config.catalog or {}) do
        local w = ('catalog[%d] "%s"'):format(i, tostring(e.id))
        if type(e.id) ~= 'string' or e.id == '' then err('catalog[%d] has no id', i)
        elseif ids[e.id] then err('%s: duplicate id', w) else ids[e.id] = true end
        if e.id and e.id:sub(1, 3) == 'mp:' then err('%s: ids starting with "mp:" are reserved for marketplace listings', w) end
        if type(e.price) ~= 'number' or e.price <= 0 then err('%s: price must be a number above 0', w) end
        if not e.label or e.label == '' then err('%s: no label', w) end
        if e.cat and e.cat ~= 'all' and not cats[e.cat] then warn('%s: category "%s" is not in Config.categories, so it only shows under All', w, tostring(e.cat)) end
        if e.stock ~= nil and (type(e.stock) ~= 'number' or e.stock < 0) then err('%s: stock must be a number 0 or higher (or left out for unlimited)', w) end
        if e.baseRating and (e.baseRating < 0 or e.baseRating > 5) then warn('%s: baseRating should be 0-5', w) end
        checkItem(e.item, w)
    end
    if #(Config.catalog or {}) == 0 then err('Config.catalog is empty - there is nothing to sell') end

    -- Parcels / cash items
    if (Config.lockerWall or {}).giveBoxItem ~= false then
        for _, s in ipairs({ 's', 'm', 'l', 'xl' }) do checkItem('pp_parcel_' .. s, 'sealed parcel box') end
    end
    if Config.payment and Config.payment.mode == 'item' then checkItem(Config.payment.cashItem, 'Config.payment.cashItem') end

    -- Lockers
    local lockerIds = {}
    for i, l in ipairs(Config.lockers or {}) do
        local w = ('lockers[%d] "%s"'):format(i, tostring(l.id))
        if type(l.id) ~= 'string' or l.id == '' then err('lockers[%d] has no id', i)
        elseif lockerIds[l.id] then err('%s: duplicate id', w) else lockerIds[l.id] = true end
        if type(l.coords) ~= 'vector3' then err('%s: coords must be a vector3', w) end
        if type(l.heading) ~= 'number' then warn('%s: no heading', w) end
    end
    if #(Config.lockers or {}) == 0 then warn('Config.lockers is empty - players can only use home delivery') end

    -- Locker doors / box sizes
    local lw = Config.lockerWall or {}
    local sizes = {}
    for slot = 1, lw.totalDoors or 26 do
        local def = Config.lockerBoxOffsets and Config.lockerBoxOffsets[slot]
        local size = def and def.model and def.model:match('^asparcel_(%a+)$')
        if not size then err('lockerBoxOffsets[%d] is missing or has no asparcel_s/m/l/xl model', slot) else sizes[size] = true end
    end
    for _, s in ipairs({ 's', 'm', 'l', 'xl' }) do
        if not sizes[s] then warn('no locker door has an asparcel_%s box, so %s-sized orders will land in another size', s, s) end
    end
    local t = lw.boxSizeMaxUnits or {}
    if not (t.s and t.m and t.l and t.s < t.m and t.m < t.l) then err('lockerWall.boxSizeMaxUnits needs s < m < l') end

    -- Target system
    local target = Config.target
    if target and target ~= 'auto' and GetResourceState(target) ~= 'started' then
        err('Config.target = "%s" but that resource is not started', target)
    end

    -- Home delivery
    if Config.home and Config.home.enabled then
        if not Config.home.depot then err('Config.home.depot is missing') end
        if not PPHousing.available() then warn('home delivery is enabled but no supported housing script was detected') end
    end

    -- Sales
    local d = Config.deals
    if d and d.enabled ~= false then
        if d.daily and ((d.daily.pct or 0) <= 0 or d.daily.pct >= 100) then err('Config.deals.daily.pct must be between 1 and 99') end
        if d.lightning and d.lightning.enabled ~= false then
            if (d.lightning.pct or 0) <= 0 or d.lightning.pct >= 100 then err('Config.deals.lightning.pct must be between 1 and 99') end
            if (d.lightning.durationSeconds or 0) > (d.lightning.everySeconds or 0) then err('Config.deals.lightning.durationSeconds is longer than everySeconds') end
        end
    end
    for code, c in pairs(Config.coupons or {}) do
        if code ~= code:upper() then err('coupon "%s": codes must be UPPER CASE', code) end
        if (c.pct == nil) == (c.flat == nil) then err('coupon "%s": set exactly one of pct or flat', code) end
        if c.pct and (c.pct <= 0 or c.pct > 100) then err('coupon "%s": pct must be 1-100', code) end
    end

    -- Marketplace
    local m = Config.marketplace
    if m and m.enabled ~= false then
        if #(m.jobs or {}) == 0 then warn('Config.marketplace.jobs is empty - nobody can sell') end
        if #(m.allowedItems or {}) == 0 then warn('Config.marketplace.allowedItems is empty - there is nothing to list') end
        for i, def in ipairs(m.allowedItems or {}) do
            checkItem(def.item, ('marketplace.allowedItems[%d]'):format(i))
            if (def.minPrice or 1) > (def.maxPrice or 9999) then err('marketplace.allowedItems[%d]: minPrice is above maxPrice', i) end
        end
        if (m.commissionPct or 0) < 0 or (m.commissionPct or 0) >= 100 then err('Config.marketplace.commissionPct must be 0-99') end
    end

    -- Inventory capabilities
    local inv = PPBridge.inventoryName()
    if not PPBridge.supportsMetadata() then
        warn('inventory "%s" cannot store item metadata, so sealed parcel boxes are skipped and orders are handed over as plain items', inv)
    end

    -- Shipping / insurance / loyalty / subscriptions / rentals
    local ex = Config.shipping and Config.shipping.express
    if ex and ex.enabled ~= false and ((ex.prepSeconds or 0) < 0 or (ex.fee or 0) < 0) then err('Config.shipping.express needs prepSeconds and fee of 0 or more') end
    local ins = Config.insurance
    if ins and ins.enabled ~= false and ((ins.pct or 0) <= 0 or (ins.minFee or 0) > (ins.maxFee or 0)) then err('Config.insurance: pct must be above 0 and minFee not above maxFee') end
    local lo = Config.loyalty
    if lo and lo.enabled ~= false then
        if #(lo.tiers or {}) == 0 then warn('Config.loyalty.tiers is empty - everyone is in one tier') end
        if (lo.redeem or {}).pointsPerDollar == nil or lo.redeem.pointsPerDollar <= 0 then err('Config.loyalty.redeem.pointsPerDollar must be above 0') end
    end
    local sub = Config.subscriptions
    if sub and sub.enabled ~= false then
        if #(sub.intervals or {}) == 0 then err('Config.subscriptions.intervals is empty') end
        for i, iv in ipairs(sub.intervals or {}) do
            if not iv.id or not iv.hours or iv.hours <= 0 then err('Config.subscriptions.intervals[%d] needs an id and hours above 0', i) end
        end
    end
    local rent = Config.rentals
    if rent and rent.enabled ~= false and inv ~= 'ox_inventory' then
        warn('locker rentals need ox_inventory (they use a stash) - they are switched off with "%s"', inv)
    end

    PPValidate.locales(errors, warns)

    print(PREFIX .. ('config check: %d problem(s), %d warning(s)'):format(#errors, #warns))
    for _, e in ipairs(errors) do print(PREFIX .. '  [ERROR] ' .. e) end
    for _, w in ipairs(warns) do print(PREFIX .. '  [warn]  ' .. w) end
    return #errors, #warns
end

CreateThread(function()
    Wait(5000) -- let the other resources finish starting before judging them
    local ok, e = pcall(PPValidate.run)
    if not ok then print(PREFIX .. 'config check crashed: ' .. tostring(e)) end
end)

RegisterCommand('ppcheck', function(source)
    if source ~= 0 then return end
    PPValidate.run()
end, true)

return PPValidate
