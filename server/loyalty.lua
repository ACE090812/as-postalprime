-- Loyalty points (Config.loyalty): earned when an order is collected, redeemed at checkout, tiers from lifetime points.

PPLoyalty = {}

local round2 = PPDeals.round2

local function cfg() return Config.loyalty or {} end

function PPLoyalty.enabled() return Config.loyalty ~= nil and cfg().enabled ~= false end

local function data(pd)
    pd.loyalty = pd.loyalty or { points = 0, lifetime = 0 }
    return pd.loyalty
end

local function sortedTiers()
    local t = {}
    for _, tier in ipairs(cfg().tiers or {}) do t[#t + 1] = tier end
    table.sort(t, function(a, b) return (a.from or 0) < (b.from or 0) end)
    if #t == 0 then t[1] = { name = 'Member', from = 0, multiplier = 1 } end
    return t
end

-- Current tier and the next one (nil at the top) for a player.
function PPLoyalty.tierFor(pd)
    local lifetime = data(pd).lifetime or 0
    local tiers = sortedTiers()
    local current, nextTier = tiers[1], nil
    for i, tier in ipairs(tiers) do
        if lifetime >= (tier.from or 0) then current, nextTier = tier, tiers[i + 1] end
    end
    return current, nextTier
end

function PPLoyalty.stateFor(pd)
    if not PPLoyalty.enabled() then return { enabled = false } end
    local d = data(pd)
    local tier, nextTier = PPLoyalty.tierFor(pd)
    local r = cfg().redeem or {}
    return {
        enabled = true,
        points = d.points or 0,
        lifetime = d.lifetime or 0,
        tier = tier.name, multiplier = tier.multiplier or 1,
        nextTier = nextTier and nextTier.name or nil, nextAt = nextTier and nextTier.from or nil,
        pointsPerDollar = r.pointsPerDollar or 100, maxPct = r.maxPct or 50, minPoints = r.minPoints or 0,
    }
end

-- What redeeming would do for a payable amount: points used and the dollars they take off.
function PPLoyalty.quote(pd, payable)
    if not PPLoyalty.enabled() then return 0, 0 end
    local r = cfg().redeem or {}
    local rate = r.pointsPerDollar or 100
    local points = data(pd).points or 0
    if points < (r.minPoints or 0) or payable <= 0 then return 0, 0 end
    local maxDollars = round2(payable * (r.maxPct or 50) / 100)
    local dollars = math.min(maxDollars, math.floor(points / rate * 100) / 100)
    dollars = math.floor(dollars * 100) / 100
    if dollars <= 0 then return 0, 0 end
    return math.ceil(dollars * rate), dollars
end

function PPLoyalty.add(pd, points)
    local d = data(pd)
    d.points = math.max(0, (d.points or 0) + points)
    if points > 0 then d.lifetime = (d.lifetime or 0) + points end
end

-- Points a collected order earns its buyer (not parcels, not zero-value orders).
function PPLoyalty.earn(order)
    if not PPLoyalty.enabled() or order.parcel or order.pointsEarned or order.takenBy then return end
    local buyer = order.buyerCid
    if not buyer then return end
    local pd = PPStore.getPlayer(buyer)
    local paid = PP.itemsPaid(order)
    if paid <= 0 then return end
    local tier = PPLoyalty.tierFor(pd)
    local points = math.floor(paid * (cfg().pointsPerDollar or 1) * (tier.multiplier or 1))
    if points <= 0 then return end
    order.pointsEarned = points
    PPLoyalty.add(pd, points)
    PPStore.savePlayer(buyer)
    PP.notifyCid(buyer, T('notif.points.title'), T('notif.points.body', points))
end

-- A return takes back the points that money earned.
function PPLoyalty.clawback(cid, refund)
    if not PPLoyalty.enabled() then return end
    local pd = PPStore.getPlayer(cid)
    PPLoyalty.add(pd, -math.floor(refund * (cfg().pointsPerDollar or 1)))
end

return PPLoyalty
