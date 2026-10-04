-- Background sweep, every few seconds: flips orders to "ready" once their prep time is up, expires/refunds ones that
-- sat ready too long uncollected, pays out refunds owed to players who were offline, and sends the timed phone
-- notifications. Driven entirely off the clock (readyAt/expiresAt, both saved at checkout) rather than one-shot
-- timers, so it keeps working correctly even if the resource or server restarts mid-order.

local eachOrder = PP.eachOrder
local removeOrder = PP.removeOrder
local hasReadyLockerOrder = PP.hasReadyLockerOrder
local pushHistory = PP.pushHistory
local onlineSources = PP.onlineSources
local pushPhoneNotification = PP.notify

local function expireOrder(cid, pd, order)
    removeOrder(pd, order)
    order.expired = true
    pushHistory(pd, order)
    PPStore.savePlayer(cid)

    local src = onlineSources[cid]
    if order.parcel then
        -- A sent parcel has nothing to refund. The sender is told so it can send it again.
        TriggerEvent('as-postalprime:parcelExpired', cid, order.parcelRef)
        if src then
            TriggerClientEvent('as-postalprime:client:updated', src)
            if not hasReadyLockerOrder(pd) then TriggerClientEvent('as-postalprime:client:orderReady:clear', src) end
            PP.notifyOrder(src, order, T('notif.parcelReturned.title'),
                T('notif.parcelReturned.body', order.lockerLabel))
        end
        return
    end

    -- Stock, coupon use and money all go back. An offline buyer is paid the next time they are online.
    order.ownerCid = cid
    PP.unwindOrder(order, 'expired')
    PP.notifyCid(cid, T('notif.expired.title'), T('notif.expired.body', order.lockerLabel))
    if src then
        TriggerClientEvent('as-postalprime:client:updated', src)
        if not hasReadyLockerOrder(pd) then TriggerClientEvent('as-postalprime:client:orderReady:clear', src) end
    end
end

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        local warnAt = (Config.notifications and Config.notifications.expiryWarnSeconds) or 0
        for cid, pd in pairs(PPStore.players) do
            for _, order in ipairs(eachOrder(pd)) do
                if not order.collected and not order.expired then
                    if not order.ready and now >= order.readyAt and order.delivery == 'home' then
                        -- Home delivery, prep time is up. If player couriers are on duty the order goes to
                        -- the depot board (server/courier.lua then drives it from there, falling back to the
                        -- NPC van when needed); otherwise the NPC van drops it right now (client/home.lua).
                        if order.courier then
                            -- already with the courier system - it will call PP.dropHome when done
                        elseif not (PPCourier and PPCourier.tryBoard(cid, order)) then
                            PP.dropHome(cid, order)
                        end
                    elseif not order.ready and now >= order.readyAt then
                        -- Locker order (or a parcel sent by another resource), prep time is up. With couriers on duty
                        -- (and Config.courier.lockerDeliveries / parcelDeliveries) it goes to the depot board first.
                        if order.courier then
                            -- already with the courier system - it will call PP.readyLocker when done
                        elseif not (PPCourier and PPCourier.tryBoard(cid, order)) then
                            PP.readyLocker(cid, order)
                        end
                    elseif order.ready and order.business and not order.business.failed and now >= (order.business.at or 0) then
                        PP.completeBusiness(cid, pd, order)
                    elseif order.ready and order.expiresAt and now > order.expiresAt then
                        expireOrder(cid, pd, order)
                    elseif order.ready and order.expiresAt and warnAt > 0 and not order.warned and order.delivery ~= 'home'
                        and order.expiresAt - now <= warnAt then
                        -- "Collect it soon" heads-up, once per order.
                        order.warned = true
                        PPStore.markDirty(cid)
                        local src = onlineSources[cid]
                        if src then
                            PP.notifyOrder(src, order, T('notif.expiring.title'),
                                T('notif.expiring.body', math.max(1, math.ceil((order.expiresAt - now) / 60)), order.lockerLabel))
                        end
                    end
                end
            end

            -- A refund that became due while the player was offline is paid as soon as they are back.
            if onlineSources[cid] then
                if pd.pendingRefund then PP.applyPendingRefund(onlineSources[cid], cid) end
                if pd.pendingNotifs then PP.deliverPendingNotifs(onlineSources[cid], cid) end
                if pd.subs and #pd.subs > 0 then PPSubs.process(cid, pd, onlineSources[cid], now) end
            end

            -- Plus expiring-soon heads-up: fires once per membership period, within 24h of
            -- expiry. pd.plus is a brand-new table on every subscribe/renew (see subscribePlus),
            -- so notifiedExpiry naturally resets whenever they renew - no separate reset needed.
            if pd.plus and pd.plus.expiresAt then
                local timeLeft = pd.plus.expiresAt - now
                if timeLeft > 0 and timeLeft <= 86400 and not pd.plus.notifiedExpiry then
                    pd.plus.notifiedExpiry = true
                    PPStore.markDirty(cid)
                    local src = onlineSources[cid]
                    if src then
                        pushPhoneNotification(src, T('notif.plusExpiring.title'),
                            T('notif.plusExpiring.body'))
                    end
                end
            end
        end
    end
end)
