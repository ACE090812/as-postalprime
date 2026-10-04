-- Repair tool: /ppadmin repair        (report only)
--              /ppadmin repair apply  (fix what it can)
-- Finds orders, door slots, courier assignments, stock, listings, rentals and subscriptions that are in a state the rest
-- of the resource can't cope with (a crash mid-order, a config change, a courier who vanished) and puts them right.

PPRepair = {}

function PPRepair.run(apply)
    local findings = {}
    local now = os.time()
    local function note(fixed, text)
        findings[#findings + 1] = { fixed = fixed and apply, text = text .. ((fixed and apply) and ' - fixed' or (fixed and ' - can be fixed' or ' - needs a manual look')) }
    end

    local seenIds, doorUse = {}, {}

    for cid, pd in pairs(PPStore.players) do
        PPStore.getPlayer(cid) -- normalises old saves (single `active` order)

        if type(pd.pendingRefund) == 'number' and pd.pendingRefund <= 0 then
            note(true, ('%s has a pendingRefund of %s'):format(cid, pd.pendingRefund))
            if apply then pd.pendingRefund = nil end
        end

        for _, listName in ipairs({ 'orders', 'parcels' }) do
            local list = pd[listName]
            for i = #list, 1, -1 do
                local o = list[i]
                local tag = ('%s order %s'):format(cid, tostring(o.id))
                if type(o) ~= 'table' or type(o.items) ~= 'table' then
                    note(true, tag .. ' is malformed')
                    if apply then table.remove(list, i) end
                else
                    if not o.id then
                        note(true, cid .. ' has an order with no id')
                        if apply then o.id = PP.newOrderId() end
                    elseif seenIds[o.id] then
                        note(false, tag .. ' has a duplicate id')
                    else
                        seenIds[o.id] = true
                    end
                    if o.collected or o.expired then
                        note(true, tag .. ' is finished but still listed as in flight')
                        if apply then
                            table.remove(list, i)
                            PP.pushHistory(pd, o)
                        end
                    else
                        if not o.readyAt then
                            note(true, tag .. ' has no ready time')
                            if apply then o.readyAt = o.placedAt or now end
                        end
                        if o.ready and not o.code and o.delivery ~= 'home' then
                            note(true, tag .. ' is ready but has no pickup code')
                            if apply then o.code = PP.newCode() end
                        end
                        if #o.items == 0 then note(false, tag .. ' has no items') end
                        local c = o.courier
                        if c and c.state ~= 'board' then
                            local gone = not c.cid or (not PP.source(c.cid) and c.deadline and now > c.deadline + 300)
                            if gone then
                                note(true, tag .. ' is assigned to a courier who is gone')
                                if apply then o.courier = nil end
                            end
                        end
                        if o.ready and o.doorSlot and o.lockerId and o.delivery ~= 'home' then
                            local key = o.lockerId .. ':' .. o.doorSlot
                            if doorUse[key] then
                                note(true, tag .. (' shares door %d at %s with another order'):format(o.doorSlot, o.lockerId))
                                if apply then o.doorSlot = nil end
                            else
                                doorUse[key] = true
                            end
                        end
                    end
                end
            end
        end

        for i = #(pd.subs or {}), 1, -1 do
            local s = pd.subs[i]
            if not PP.findCatalogItem(s.itemId) or not PP.findLocker(s.lockerId) then
                note(true, ('%s has a subscription to a removed item or locker (%s)'):format(cid, tostring(s.itemId)))
                if apply then table.remove(pd.subs, i) end
            end
        end

        if apply then PPStore.markDirty(cid) end
    end

    for itemId, qty in pairs(PPStore.stock) do
        if qty < 0 then
            note(true, ('stock of %s is negative (%d)'):format(itemId, qty))
            if apply then PPStore.restock(itemId, -qty) end
        end
    end

    for id, l in pairs(PPStore.listings) do
        if l.qty < 0 then
            note(true, ('marketplace listing #%d has a negative quantity'):format(id))
            if apply then l.qty = 0 PPStore.saveListing(id) end
        end
        if (l.price or 0) <= 0 then note(false, ('marketplace listing #%d has a price of %s'):format(id, tostring(l.price))) end
    end

    local codes = {}
    for id, r in pairs(PPStore.rentals) do
        local graceEnd = r.expiresAt + (((Config.rentals or {}).graceHours or 24) * 3600)
        if now > graceEnd then
            note(true, ('rental #%d is past its grace period'):format(id))
            if apply then PPRentals.finish(r, 'repair') end
        else
            local key = r.lockerId .. ':' .. r.code
            if codes[key] then
                note(true, ('rental #%d has the same code as another rental at %s'):format(id, r.lockerId))
                if apply then r.code = PP.newCode() PPStore.saveRental(id) end
            else
                codes[key] = true
            end
        end
    end

    return findings
end

return PPRepair
