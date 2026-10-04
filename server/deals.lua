-- Pricing rules: deal of the day, lightning deals and coupon codes (Config.deals / Config.coupons).
-- Deals are a pure function of the clock - nothing is saved and every player (and every restart) agrees.

PPDeals = {}

local function round2(n) return math.floor(n * 100 + 0.5) / 100 end
PPDeals.round2 = round2

-- Small seeded generator so a given day / time window always picks the same items. (math.random is left alone:
-- reseeding it here would change randomness for every other part of the resource.)
local function rng(seed)
    local s = math.floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 48271) % 2147483647
        return s
    end
end

local function eligible(exclude)
    local out = {}
    for _, e in ipairs(Config.catalog) do
        if not e.noDeals and not (exclude and exclude[e.id]) then out[#out + 1] = e.id end
    end
    return out
end

local function pick(list, count, seed)
    local next = rng(seed)
    local pool, out = {}, {}
    for i, v in ipairs(list) do pool[i] = v end
    for _ = 1, math.min(count, #pool) do
        local i = (next() % #pool) + 1
        out[#out + 1] = table.remove(pool, i)
    end
    return out
end

-- { [itemId] = { pct, kind = 'daily'|'lightning', endsAt = unix seconds } } for the given time.
function PPDeals.active(now)
    now = now or os.time()
    local out = {}
    local cfg = Config.deals
    if not cfg or cfg.enabled == false then return out end

    local daily = {}
    if cfg.daily and (cfg.daily.count or 0) > 0 and (cfg.daily.pct or 0) > 0 then
        local t = os.date('*t', now)
        local dayKey = t.year * 1000 + t.yday
        local endsAt = os.time({ year = t.year, month = t.month, day = t.day + 1, hour = 0, min = 0, sec = 0 })
        for _, id in ipairs(pick(eligible(), cfg.daily.count, dayKey * 31 + 7)) do
            out[id] = { pct = cfg.daily.pct, kind = 'daily', endsAt = endsAt }
            daily[id] = true
        end
    end

    local l = cfg.lightning
    if l and l.enabled ~= false and (l.pct or 0) > 0 and (l.everySeconds or 0) > 0 then
        local slot = math.floor(now / l.everySeconds)
        local into = now - slot * l.everySeconds
        if into < (l.durationSeconds or 0) then
            local list = eligible(daily)
            if #list == 0 then list = eligible() end
            local id = pick(list, 1, slot * 7919 + 13)[1]
            if id and (not out[id] or out[id].pct < l.pct) then
                out[id] = { pct = l.pct, kind = 'lightning', endsAt = slot * l.everySeconds + l.durationSeconds }
            end
        end
    end
    return out
end

-- Effective unit price for a catalog entry right now: price, deal (or nil).
function PPDeals.price(entry, now)
    local deal = PPDeals.active(now)[entry.id]
    if not deal then return entry.price, nil end
    return round2(entry.price * (100 - deal.pct) / 100), deal
end

-- ─── Coupons ─────────────────────────────────────────────────────────────────

function PPDeals.normalizeCode(code)
    local code = tostring(code or ''):upper():gsub('%s+', '')
    return code
end

-- Checks a coupon for a player and works out the discount on `itemsTotal`.
-- Returns discount, code on success; nil, errorText on failure.
function PPDeals.checkCoupon(rawCode, pd, itemsTotal, plusActive, now)
    now = now or os.time()
    local code = PPDeals.normalizeCode(rawCode)
    local c = Config.coupons and Config.coupons[code]
    if code == '' or not c then return nil, T('err.coupon.unknown') end
    if c.expiresAt and now >= c.expiresAt then return nil, T('err.coupon.expired') end
    if c.plusOnly and not plusActive then return nil, T('err.coupon.plus') end
    if c.minTotal and itemsTotal < c.minTotal then return nil, T('err.coupon.min', c.minTotal) end
    if c.uses and (PPStore.couponUses[code] or 0) >= c.uses then return nil, T('err.coupon.soldOut') end
    local mine = pd.coupons and pd.coupons[code] or 0
    if mine >= (c.perPlayer or 1) then return nil, T('err.coupon.used') end

    local discount
    if c.pct then
        discount = round2(itemsTotal * c.pct / 100)
        if c.maxDiscount then discount = math.min(discount, c.maxDiscount) end
    else
        discount = tonumber(c.flat) or 0
    end
    discount = math.max(0, math.min(discount, itemsTotal))
    if discount <= 0 then return nil, T('err.coupon.unknown') end
    return discount, code
end

-- Counts the use against the character and the server-wide total (call once the order is paid for).
function PPDeals.spendCoupon(pd, code)
    pd.coupons = pd.coupons or {}
    pd.coupons[code] = (pd.coupons[code] or 0) + 1
    PPStore.addCouponUse(code, 1)
end

-- Gives the use back (the order was cancelled / expired / refunded).
function PPDeals.refundCoupon(pd, code)
    if not code then return end
    if pd.coupons and pd.coupons[code] then
        pd.coupons[code] = pd.coupons[code] - 1
        if pd.coupons[code] <= 0 then pd.coupons[code] = nil end
    end
    PPStore.addCouponUse(code, -1)
end

return PPDeals
