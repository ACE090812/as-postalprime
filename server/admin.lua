-- Admin tools: /ppadmin <subcommand> (in game or from the server console) and the console-only pprestock command.
-- /ppadmin is restricted: give your admins the ACE   add_ace group.admin command.ppadmin allow   in server.cfg.

local findCatalogItem = PP.findCatalogItem
local round2 = PPDeals.round2

local function say(src, text)
    print(('[as-postalprime] %s'):format(text:gsub('\n', '\n[as-postalprime] ')))
    if src and src > 0 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Postal Prime', description = text, type = 'inform', duration = 9000 })
    end
end

-- A target is an online server id or a character identifier.
local function resolveCid(arg)
    if not arg then return nil end
    local id = tonumber(arg)
    if id and GetPlayerName(id) then return PPBridge.getIdentifier(id), id end
    if PPStore.players[arg] then return arg, PP.source(arg) end
    return nil
end

local function describe(o)
    local state = o.collected and 'collected' or o.expired and 'expired' or o.ready and 'ready' or 'preparing'
    return ('%s  %s  $%s  %s'):format(o.id, state, o.total, o.lockerLabel or '?')
end

local function findOrderAnywhere(orderId)
    for cid, pd in pairs(PPStore.players) do
        for _, o in ipairs(pd.orders or {}) do
            if o.id == orderId then return cid, pd, o end
        end
    end
end

local HELP = [[
ppadmin orders <id|citizenid>   in-flight orders for a player
ppadmin cancel <orderId>        cancel any uncollected shop order and refund the buyer
ppadmin refund <id|citizenid> <amount>   pay a refund (queued if they are offline)
ppadmin plus <id|citizenid> <days>       grant Postal Prime Plus
ppadmin stock <itemId> [amount]          show or SET stock for an item
ppadmin restock <itemId> <amount>        add stock
ppadmin coupon <CODE> [reset]            show (or reset) a coupon's server-wide uses
ppadmin market                           list marketplace listings
ppadmin market remove <listingId>        remove a listing (seller must be online to get the items back)
ppadmin loyalty <id|citizenid> [points]  show, or add (negative removes) loyalty points
ppadmin rentals [end <id>]               list locker rentals / end one
ppadmin subs <id|citizenid>              list a player's subscriptions
ppadmin stats [days]                     sales dashboard (default 7 days; 1 = today)
ppadmin repair [apply]                   scan for stuck orders etc. (add 'apply' to fix them)]]

local commands = {}

commands.help = function(src) say(src, HELP) end

commands.orders = function(src, args)
    local cid = resolveCid(args[2])
    if not cid then return say(src, 'Player not found. Use an online server id or a citizenid.') end
    local pd = PPStore.getPlayer(cid)
    local lines = {}
    for _, o in ipairs(PP.eachOrder(pd)) do lines[#lines + 1] = describe(o) end
    say(src, #lines == 0 and 'No orders in flight.' or table.concat(lines, '\n'))
end

commands.cancel = function(src, args)
    local cid, pd, order = findOrderAnywhere(args[2])
    if not order then return say(src, 'No uncollected shop order with that id.') end
    if order.collected or order.expired then return say(src, 'That order is already finished.') end
    PP.removeOrder(pd, order)
    order.courier = nil
    order.cancelled = true
    order.ownerCid = cid
    PP.pushHistory(pd, order)
    PPStore.savePlayer(cid)
    PP.unwindOrder(order, 'admin')
    local osrc = PP.source(cid)
    if osrc then
        TriggerClientEvent('as-postalprime:client:updated', osrc)
        TriggerClientEvent('as-postalprime:client:orderReady:clear', osrc)
    end
    PPLog.log('admin', src, ('cancelled order %s and refunded $%s'):format(order.id, order.total), { order = order.id })
    say(src, ('Cancelled %s - $%s refunded%s.'):format(order.id, order.total, PP.source(order.buyerCid or cid) and '' or ' (queued, buyer is offline)'))
end

commands.refund = function(src, args)
    local cid = resolveCid(args[2])
    local amount = round2(tonumber(args[3]) or 0)
    if not cid or amount <= 0 then return say(src, 'Usage: ppadmin refund <id|citizenid> <amount>') end
    PP.refundCid(cid, amount)
    PPLog.log('admin', src, ('refunded $%s to %s'):format(amount, cid), { citizen = cid })
    say(src, ('Refunded $%s to %s.'):format(amount, cid))
end

commands.plus = function(src, args)
    local cid = resolveCid(args[2])
    local days = tonumber(args[3])
    if not cid or not days or days <= 0 then return say(src, 'Usage: ppadmin plus <id|citizenid> <days>') end
    local pd = PPStore.getPlayer(cid)
    local now = os.time()
    local base = (pd.plus and pd.plus.expiresAt and pd.plus.expiresAt > now) and pd.plus.expiresAt or now
    pd.plus = { expiresAt = base + math.floor(days * 86400) }
    PPStore.savePlayer(cid)
    local osrc = PP.source(cid)
    if osrc then TriggerClientEvent('as-postalprime:client:updated', osrc) end
    PPLog.log('admin', src, ('granted %s day(s) of Plus to %s'):format(days, cid), { citizen = cid })
    say(src, ('Granted %s day(s) of Plus to %s.'):format(days, cid))
end

commands.stock = function(src, args)
    local entry = findCatalogItem(args[2])
    if not entry or entry.listing then return say(src, 'Unknown item id.') end
    local current = PPStore.getStock(entry.id)
    local target = tonumber(args[3])
    if not target then
        return say(src, ('%s: %s'):format(entry.id, current == nil and 'unlimited' or (current .. ' in stock')))
    end
    target = math.max(0, math.floor(target))
    PPStore.restock(entry.id, target - (current or 0))
    PPLog.log('admin', src, ('set stock of %s to %d'):format(entry.id, target), { item = entry.id })
    say(src, ('%s stock set to %d.'):format(entry.id, target))
end

commands.restock = function(src, args)
    local entry = findCatalogItem(args[2])
    local amount = tonumber(args[3])
    if not entry or entry.listing or not amount or amount <= 0 then return say(src, 'Usage: ppadmin restock <itemId> <amount>') end
    local total = PPStore.restock(entry.id, math.floor(amount))
    PPLog.log('admin', src, ('restocked %s by %d (%d now)'):format(entry.id, math.floor(amount), total), { item = entry.id })
    say(src, ('%s restocked by %d - %d now remaining.'):format(entry.id, math.floor(amount), total))
end

commands.coupon = function(src, args)
    local code = PPDeals.normalizeCode(args[2])
    local c = Config.coupons and Config.coupons[code]
    if not c then return say(src, 'Unknown coupon code.') end
    if args[3] == 'reset' then
        PPStore.addCouponUse(code, -(PPStore.couponUses[code] or 0))
        PPLog.log('admin', src, ('reset uses of coupon %s'):format(code), {})
        return say(src, code .. ' uses reset to 0.')
    end
    say(src, ('%s: used %d%s time(s)'):format(code, PPStore.couponUses[code] or 0, c.uses and (' of ' .. c.uses) or ''))
end

commands.market = function(src, args)
    if args[2] == 'remove' then
        local id = tonumber(args[3])
        local l = id and PPStore.listings[id]
        if not l then return say(src, 'No such listing.') end
        local seller = PP.source(l.seller)
        if l.qty > 0 and not seller then return say(src, 'The seller must be online to get their items back.') end
        if l.qty > 0 and not PPBridge.addItem(seller, l.item, l.qty) then return say(src, 'The seller cannot carry the items right now.') end
        PPStore.deleteListing(id)
        PPLog.log('admin', src, ('removed listing %d (%dx %s)'):format(id, l.qty, l.label), { listing = id })
        return say(src, ('Removed listing %d.'):format(id))
    end
    local lines = {}
    for id, l in pairs(PPStore.listings) do
        lines[#lines + 1] = ('#%d  %dx %s @ $%s  by %s'):format(id, l.qty, l.label, l.price, l.sellerName or l.seller)
    end
    table.sort(lines)
    say(src, #lines == 0 and 'No listings.' or table.concat(lines, '\n'))
end

commands.loyalty = function(src, args)
    local cid = resolveCid(args[2])
    if not cid then return say(src, 'Usage: ppadmin loyalty <id|citizenid> [points]') end
    local pd = PPStore.getPlayer(cid)
    local delta = tonumber(args[3])
    if delta then
        PPLoyalty.add(pd, math.floor(delta))
        PPStore.savePlayer(cid)
        PPLog.log('admin', src, ('adjusted loyalty points of %s by %d'):format(cid, math.floor(delta)), { citizen = cid })
    end
    local st = PPLoyalty.stateFor(pd)
    say(src, ('%s: %d points (%d lifetime), tier %s'):format(cid, st.points or 0, st.lifetime or 0, st.tier or '-'))
end

commands.rentals = function(src, args)
    if args[2] == 'end' then
        local r = PPStore.rentals[tonumber(args[3]) or -1]
        if not r then return say(src, 'No such rental.') end
        PPRentals.finish(r, 'ended by admin')
        PPLog.log('admin', src, ('ended rental #%d'):format(r.id), { rental = r.id })
        return say(src, ('Ended rental #%d.'):format(r.id))
    end
    local lines = {}
    for id, r in pairs(PPStore.rentals) do
        lines[#lines + 1] = ('#%d  %s  %s  code %s  %s'):format(id, r.lockerId, r.ownerName or r.owner, r.code,
            r.expiresAt > os.time() and ('ends in ' .. math.ceil((r.expiresAt - os.time()) / 3600) .. 'h') or 'EXPIRED (grace)')
    end
    table.sort(lines)
    say(src, #lines == 0 and 'No rentals.' or table.concat(lines, '\n'))
end

commands.subs = function(src, args)
    local cid = resolveCid(args[2])
    if not cid then return say(src, 'Usage: ppadmin subs <id|citizenid>') end
    local lines = {}
    for _, s in ipairs(PPStore.getPlayer(cid).subs or {}) do
        lines[#lines + 1] = ('%dx %s %s  next %s%s'):format(s.qty, s.itemId, s.interval, os.date('%Y-%m-%d %H:%M', s.nextAt), s.paused and '  PAUSED' or '')
    end
    say(src, #lines == 0 and 'No subscriptions.' or table.concat(lines, '\n'))
end

commands.stats = function(src, args)
    local days = math.max(1, math.floor(tonumber(args[2]) or 7))
    local s, top = PPStats.summary(days)
    local function n(k) return s[k] or 0 end
    local orders = n('orders')
    local lines = {
        ('Last %d day(s)'):format(days),
        ('Orders collected: %d   Revenue: $%s   Average: $%s'):format(orders, round2(n('revenue')), orders > 0 and round2(n('revenue') / orders) or 0),
        ('Cancelled: %d   Expired: %d   Returns: %d   Damaged: %d   Refunded: $%s'):format(n('cancelled'), n('expired'), n('returns'), n('damaged'), round2(n('refunded'))),
        ('Coupon discounts: $%s   Points discounts: $%s'):format(round2(n('couponDiscount')), round2(n('pointsDiscount'))),
        ('Express fees: $%s   Insurance fees: $%s   Insurance payouts: $%s'):format(round2(n('expressFees')), round2(n('insuranceFees')), round2(n('insurancePayouts'))),
        ('Plus sold: %d ($%s)   Locker rentals: %d ($%s)'):format(n('plusSales'), round2(n('plusRevenue')), n('rentals'), round2(n('rentalRevenue'))),
        ('Marketplace volume: $%s   Commission kept: $%s'):format(round2(n('marketGross')), round2(n('marketCommission'))),
    }
    local topLines = {}
    for i = 1, math.min(5, #top) do topLines[#topLines + 1] = ('%s x%d'):format(top[i].id, top[i].qty) end
    lines[#lines + 1] = 'Top items: ' .. (#topLines > 0 and table.concat(topLines, ', ') or '-')
    say(src, table.concat(lines, '\n'))
end

commands.repair = function(src, args)
    local apply = args[2] == 'apply'
    local findings = PPRepair.run(apply)
    if apply and #findings > 0 then PPStore.flush() PPLog.log('admin', src, ('repair applied: %d finding(s)'):format(#findings), {}) end
    if #findings == 0 then return say(src, 'Nothing to repair.') end
    local lines = { ('%d finding(s)%s:'):format(#findings, apply and ' (fixes applied)' or ' (run "ppadmin repair apply" to fix)') }
    for i = 1, math.min(15, #findings) do lines[#lines + 1] = '- ' .. findings[i].text end
    if #findings > 15 then lines[#lines + 1] = ('...and %d more (see the server console)'):format(#findings - 15) end
    for i = 16, #findings do print('[as-postalprime] - ' .. findings[i].text) end
    say(src, table.concat(lines, '\n'))
end

RegisterCommand('ppadmin', function(source, args)
    local fn = commands[args[1] or 'help']
    if not fn then return say(source, 'Unknown subcommand.\n' .. HELP) end
    local ok, err = pcall(fn, source, args)
    if not ok then say(source, 'Command failed: ' .. tostring(err)) end
end, true)

-- Console-only restock command, kept from earlier versions: pprestock <itemId> <amount>
RegisterCommand('pprestock', function(source, args)
    if source ~= 0 then
        print('[as-postalprime] pprestock can only be run from the server console.')
        return
    end
    local itemId = args[1]
    local amount = tonumber(args[2])
    if not itemId or not amount or amount <= 0 then
        print('[as-postalprime] Usage: pprestock <itemId> <amount>')
        return
    end
    if not findCatalogItem(itemId) then
        print(('[as-postalprime] Unknown item id "%s" - check config.lua for the correct id.'):format(itemId))
        return
    end
    commands.restock(0, { 'restock', itemId, tostring(amount) })
end, true)
