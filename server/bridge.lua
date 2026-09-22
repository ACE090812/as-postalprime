PPBridge = {}

local function detectFramework()
    if Config.framework ~= 'auto' then return Config.framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

local function detectInventory()
    if Config.inventory ~= 'auto' then return Config.inventory end
    if GetResourceState('ox_inventory') == 'started' then return 'ox_inventory' end
    if GetResourceState('qb-inventory') == 'started' then return 'qb-inventory' end
    return 'ox_inventory'
end

local framework = detectFramework()
local inventory = detectInventory()

local QBCore, qbxExport, ESX

local function ensureCore()
    if framework == 'qb' and not QBCore then
        QBCore = exports['qb-core']:GetCoreObject()
    elseif framework == 'qbx' and not qbxExport then
        qbxExport = exports.qbx_core
    elseif framework == 'esx' and not ESX then
        ESX = exports['es_extended']:getSharedObject()
    end
end

function PPBridge.getIdentifier(source)
    ensureCore()
    if framework == 'qb' and QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        return Player and Player.PlayerData.citizenid or nil
    elseif framework == 'qbx' and qbxExport then
        local Player = qbxExport:GetPlayer(source)
        return Player and Player.PlayerData.citizenid or nil
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        return xPlayer and xPlayer.identifier or nil
    end

    return source and ('standalone:' .. tostring(source)) or nil
end

-- The player's in-character name (charinfo/getName), not their FiveM/Steam display name.
-- Falls back to GetPlayerName only if the framework can't provide a character name at all.
function PPBridge.getCharacterName(source)
    ensureCore()
    if framework == 'qb' and QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        local ci = Player and Player.PlayerData.charinfo
        if ci and (ci.firstname or ci.lastname) then
            return (('%s %s'):format(ci.firstname or '', ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        end
    elseif framework == 'qbx' and qbxExport then
        local Player = qbxExport:GetPlayer(source)
        local ci = Player and Player.PlayerData.charinfo
        if ci and (ci.firstname or ci.lastname) then
            return (('%s %s'):format(ci.firstname or '', ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        end
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local ok, name = pcall(function() return xPlayer.getName() end)
            if ok and name and name ~= '' then return name end
        end
    end

    return GetPlayerName(source) or T('name.customer')
end

function PPBridge.getBalance(source, account)
    ensureCore()
    if framework == 'qb' and QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        return Player and Player.PlayerData.money[account] or 0
    elseif framework == 'qbx' and qbxExport then
        local Player = qbxExport:GetPlayer(source)
        return Player and Player.PlayerData.money[account] or 0
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        local acc = xPlayer and xPlayer.getAccount(account)
        return acc and acc.money or 0
    end
    return nil
end

function PPBridge.removeMoney(source, account, amount)
    ensureCore()
    if amount <= 0 then return true end
    if framework == 'qb' and QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        return Player ~= nil and Player.Functions.RemoveMoney(account, amount, 'postalprime') == true
    elseif framework == 'qbx' and qbxExport then
        local Player = qbxExport:GetPlayer(source)
        return Player ~= nil and Player.Functions.RemoveMoney(account, amount, 'postalprime') == true
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        local acc = xPlayer.getAccount(account)
        if not acc or acc.money < amount then return false end
        xPlayer.removeAccountMoney(account, amount)
        return true
    end

    return true
end

function PPBridge.addMoney(source, account, amount)
    ensureCore()
    if amount <= 0 then return true end
    if framework == 'qb' and QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        Player.Functions.AddMoney(account, amount, 'postalprime-refund')
        return true
    elseif framework == 'qbx' and qbxExport then
        local Player = qbxExport:GetPlayer(source)
        if not Player then return false end
        Player.Functions.AddMoney(account, amount, 'postalprime-refund')
        return true
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        xPlayer.addAccountMoney(account, amount)
        return true
    end
    return true
end

function PPBridge.getItemCount(source, item)
    if inventory == 'ox_inventory' then
        local ok, count = pcall(function() return exports.ox_inventory:Search(source, 'count', item) end)
        return ok and (count or 0) or 0
    elseif inventory == 'qb-inventory' then
        local ok, it = pcall(function() return exports['qb-inventory']:GetItemByName(source, item) end)
        return ok and it and (it.amount or it.count or 0) or 0
    end
    return 0
end

function PPBridge.addItem(source, item, count, metadata)
    count = count or 1
    if inventory == 'ox_inventory' then
        local ok, result = pcall(function() return exports.ox_inventory:AddItem(source, item, count, metadata) end)
        return ok and result and true or false
    elseif inventory == 'qb-inventory' then
        local ok = pcall(function() exports['qb-inventory']:AddItem(source, item, count, false, metadata) end)
        return ok
    end
    return false
end

function PPBridge.removeItem(source, item, count)
    count = count or 1
    if inventory == 'ox_inventory' then
        local ok, result = pcall(function() return exports.ox_inventory:RemoveItem(source, item, count) end)
        return ok and result and true or false
    elseif inventory == 'qb-inventory' then
        local ok = pcall(function() exports['qb-inventory']:RemoveItem(source, item, count) end)
        return ok
    end
    return false
end

-- Registers a "use this item" handler that works the same regardless of inventory.
-- handler(source, metadata, removeSelf) is called with whatever plain table was stored on the item
-- when it was given out, plus a removeSelf() that removes exactly the slot/copy that was used - never
-- "any item with this name", which matters for a non-stacking item where the player might be holding
-- several copies with different metadata at once (e.g. two parcels with different contents).
-- ox_inventory: matches the pattern already proven working in as-printer's own 'printed_document'
-- item (server/api.lua) - items.lua must point the item at `server = { export = 'as-postalprime.<itemName>' }`.
-- qb-inventory (and qbx, which also commonly runs qb-inventory): goes through the FRAMEWORK core's
-- CreateUseableItem, not the inventory resource itself, so this needs ensureCore() first.
function PPBridge.registerUsable(itemName, handler)
    if inventory == 'ox_inventory' then
        exports(itemName, function(event, item, inv, slot)
            if event ~= 'usingItem' then return end
            local src = inv and inv.id
            if type(src) ~= 'number' then return end
            local s = exports.ox_inventory:GetSlot(src, slot)
            local function removeSelf()
                pcall(function() exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot) end)
            end
            handler(src, (s and s.metadata) or {}, removeSelf)
        end)
        return
    end

    ensureCore()
    local function qbHandler(source, item)
        local function removeSelf()
            pcall(function() exports['qb-inventory']:RemoveItem(source, itemName, 1, item and item.slot) end)
        end
        handler(source, (item and item.info) or {}, removeSelf)
    end
    if framework == 'qb' and QBCore then
        QBCore.Functions.CreateUseableItem(itemName, qbHandler)
    elseif framework == 'qbx' and qbxExport then
        local ok = pcall(function() qbxExport:CreateUseableItem(itemName, qbHandler) end)
        if not ok then
            print(('[as-postalprime] could not register usable item "%s" on qbx_core - if you run ox_inventory with qbx, set Config.inventory to "ox_inventory" instead of leaving it on qb-inventory\'s path.'):format(itemName))
        end
    else
        print(('[as-postalprime] could not register usable item "%s": no supported framework/inventory combination detected (framework=%s, inventory=%s).'):format(itemName, tostring(framework), tostring(inventory)))
    end
end

-- The player's framework job name (e.g. 'postalprime') or nil. Used by the courier job.
function PPBridge.getJob(source)
    ensureCore()
    if framework == 'qb' and QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        local job = Player and Player.PlayerData.job
        return job and job.name or nil
    elseif framework == 'qbx' and qbxExport then
        local Player = qbxExport:GetPlayer(source)
        local job = Player and Player.PlayerData.job
        return job and job.name or nil
    elseif framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        local job = xPlayer and (xPlayer.job or (xPlayer.getJob and xPlayer.getJob()))
        return job and job.name or nil
    end
    return nil
end

return PPBridge
