-- On-model locker screen.
-- A DUI (off-screen browser rendering ui/screen.html) is swapped onto the locker prop's screen
-- texture at runtime. A DUI can't take mouse focus or fire NUI callbacks, so:
--   * Lua owns ALL state + button layout and just pushes it to the page with SendDuiMessage.
--   * Input is a virtual cursor (mouse movement) + left click, hit-tested here in Lua.
-- All coordinates below are fractions (0-1) of the SCREEN rect, not of the whole texture.

PPScreen = {}

local cfg = Config.screen or {}
local RES = GetCurrentResourceName()

local dui = nil
local duiReady = false
local session = nil

local rect = cfg.rect or { x = 0.0, y = 0.0, w = 0.775, h = 1.0 }
local ASPECT = rect.w / rect.h -- screen width/height in pixels (texture is square)

-- ─── Layouts ──────────────────────────────────────────────────────────────────

local function buildEntry()
    local b = {}
    local function add(id, label, x, y, w, h, kind)
        b[#b + 1] = { id = id, label = label, x = x, y = y, w = w, h = h, kind = kind }
    end

    add('close', '\u{2715}', 0.86, 0.025, 0.10, 0.06, 'close')

    local keys = { '1', '2', '3', '4', '5', '6', '7', '8', '9', 'clear', '0', 'back' }
    local cw, gx = 0.2733, 0.03
    for i, k in ipairs(keys) do
        local col = (i - 1) % 3
        local row = (i - 1) // 3
        local label = k
        local kind = 'key'
        if k == 'clear' then label, kind = 'Clear', 'keysmall' end
        if k == 'back' then label, kind = '\u{232B}', 'keysmall' end
        add(k, label, 0.06 + col * (cw + gx), 0.33 + row * 0.105, cw, 0.088, kind)
    end

    add('cancel', 'Cancel', 0.06, 0.775, 0.42, 0.09, 'cancel')
    add('submit', 'Open Locker', 0.52, 0.775, 0.42, 0.09, 'submit')
    return b
end

local function buildRetry()
    return { { id = 'retry', label = 'Try Again', x = 0.06, y = 0.70, w = 0.88, h = 0.09, kind = 'submit' } }
end

-- ─── DUI push ─────────────────────────────────────────────────────────────────

local function push()
    if not dui then return end
    local s = session
    if not s then
        SendDuiMessage(dui, json.encode({ view = 'idle' }))
        return
    end
    SendDuiMessage(dui, json.encode({
        view = s.view,
        label = s.label,
        code = s.code,
        cursor = { x = s.cx, y = s.cy },
        hover = s.hover,
        busy = s.busy,
        ok = s.ok,
        msg = s.msg,
        buttons = s.buttons,
    }))
end

-- ─── Session logic ────────────────────────────────────────────────────────────

local function hitTest(x, y)
    for _, btn in ipairs(session.buttons) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            return btn.id
        end
    end
end

function PPScreen.close()
    local s = session
    if not s then return end
    session = nil
    if s.cam then
        RenderScriptCams(false, true, 400, true, false)
        DestroyCam(s.cam, false)
    end
    push()
end

local function submit()
    local s = session
    if not s or s.busy or #s.code ~= 6 then return end
    s.busy = true
    s.dirty = true

    CreateThread(function()
        local res = lib.callback.await('as-postalprime:collect', false, { lockerId = s.lockerId, code = s.code })
        if session ~= s then return end

        s.busy = false
        s.view = 'result'
        s.ok = (res and res.ok) and true or false
        s.dirty = true

        if s.ok then
            s.msg = 'Locker door opened - grab your parcel!'
            s.buttons = {}
            SendNUIMessage({ action = 'as-postalprime:updated' }) -- refresh the phone app if it's open
            SetTimeout(1600, function()
                if session == s then PPScreen.close() end
            end)
        else
            s.msg = (res and res.error) or 'Failed to open locker'
            s.buttons = buildRetry()
        end
    end)
end

local function press(id)
    local s = session
    if not s or s.busy then return end

    if s.view == 'entry' then
        if id == 'cancel' or id == 'close' then PPScreen.close() return end
        if id == 'submit' then submit() return end
        if id == 'clear' then s.code = ''
        elseif id == 'back' then s.code = s.code:sub(1, -2)
        elseif id:match('^%d$') and #s.code < 6 then s.code = s.code .. id end
        s.dirty = true
    elseif s.view == 'result' and id == 'retry' then
        s.view, s.code, s.buttons, s.dirty = 'entry', '', buildEntry(), true
    end
end

local function startCam(s)
    local c = cfg.cam
    if not c then return end

    -- c.offset = LOCAL offset of the screen's centre on the prop (x = right, y = forward, z = up).
    -- The camera sits c.dist metres out from it on whichever side (local +Y or -Y) the player is on,
    -- so it works no matter which way the model's "front" points.
    local off = c.offset or vector3(0.0, 0.0, 1.45)
    local dist = c.dist or 0.9
    local ped = GetEntityCoords(PlayerPedId())
    local a = GetOffsetFromEntityInWorldCoords(s.prop, off.x, off.y + dist, off.z)
    local b = GetOffsetFromEntityInWorldCoords(s.prop, off.x, off.y - dist, off.z)
    local pos = (#(ped - a) < #(ped - b)) and a or b
    local tgt = GetOffsetFromEntityInWorldCoords(s.prop, off.x, off.y, off.z)

    s.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, c.fov or 40.0, false, 2)
    PointCamAtCoord(s.cam, tgt.x, tgt.y, tgt.z)
    SetCamActive(s.cam, true)
    RenderScriptCams(true, true, s.camInstant and 0 or 400, true, false)
end

-- Live camera tuning (only when Config.screen.debug = true):
--   /ppcam <x> <z> [dist] [fov]   e.g. /ppcam 0.0 1.5 0.9 40
-- Re-frames the camera on the fly and prints the line to paste into Config.screen.
RegisterCommand('ppcam', function(_, args)
    if not cfg.debug then return end
    local c = cfg.cam or {}
    local off = c.offset or vector3(0.0, 0.0, 1.45)
    cfg.cam = {
        offset = vector3(tonumber(args[1]) or off.x, off.y, tonumber(args[2]) or off.z),
        dist = tonumber(args[3]) or c.dist or 0.9,
        fov = tonumber(args[4]) or c.fov or 40.0,
    }
    print(('cam = { offset = vector3(%.2f, %.2f, %.2f), dist = %.2f, fov = %.1f },'):format(
        cfg.cam.offset.x, cfg.cam.offset.y, cfg.cam.offset.z, cfg.cam.dist, cfg.cam.fov))

    local s = session
    if s then
        if s.cam then DestroyCam(s.cam, false) s.cam = nil end
        s.camInstant = true
        startCam(s)
    end
end, false)

--- Returns true when the on-model screen handled the interaction (so main.lua skips the NUI overlay).
function PPScreen.open(lockerId, label, prop)
    if not cfg.enabled or not duiReady then
        print(('[as-postalprime] on-model screen not used: enabled=%s duiReady=%s (falling back to NUI overlay)'):format(tostring(cfg.enabled), tostring(duiReady)))
        return false
    end
    if session then return true end

    local s = {
        lockerId = lockerId, label = label or 'Locker', prop = prop,
        view = 'entry', code = '', buttons = buildEntry(),
        cx = 0.5, cy = 0.5, hover = nil, busy = false, ok = nil, msg = nil, dirty = true,
    }
    session = s
    startCam(s)
    SendDuiMessage(dui, json.encode({ action = 'init', rect = rect, debug = cfg.debug and true or false }))

    CreateThread(function()
        local sens = cfg.sensitivity or 0.6
        local maxDist = cfg.maxDistance or 3.5

        while session == s do
            Wait(0)
            DisableAllControlActions(0)

            -- Virtual cursor from mouse movement (controls are disabled, so read the disabled values).
            local dx = GetDisabledControlNormal(0, 1)
            local dy = GetDisabledControlNormal(0, 2)
            if dx ~= 0.0 or dy ~= 0.0 then
                s.cx = math.min(1.0, math.max(0.0, s.cx + dx * sens))
                s.cy = math.min(1.0, math.max(0.0, s.cy + dy * sens * ASPECT))
                local h = hitTest(s.cx, s.cy)
                if h ~= s.hover then s.hover = h end
                s.dirty = true
            end

            if IsDisabledControlJustPressed(0, 24) and s.hover then -- left mouse
                press(s.hover)
            end

            if IsDisabledControlJustPressed(0, 200) then -- ESC
                PPScreen.close()
                break
            end

            local ped = PlayerPedId()
            if IsEntityDead(ped) or not DoesEntityExist(s.prop)
                or #(GetEntityCoords(ped) - GetEntityCoords(s.prop)) > maxDist then
                PPScreen.close()
                break
            end

            if s.dirty and session == s then
                s.dirty = false
                push()
            end
        end
    end)

    return true
end

-- ─── Keyboard input ───────────────────────────────────────────────────────────
-- Digits (top row + numpad) type the code, Backspace deletes one digit, Enter submits (or retries).
-- These are FiveM key mappings, so they show up in Settings > Key Bindings > FiveM and can be
-- rebound. They only do anything while a locker screen session is open.

local function keyPress(id)
    if session then press(id) end
end

for d = 0, 9 do
    local n = tostring(d)
    RegisterCommand('pp_screen_' .. n, function() keyPress(n) end, false)
    RegisterKeyMapping('pp_screen_' .. n, 'Postal Prime screen: ' .. n, 'keyboard', n)
    RegisterCommand('pp_screen_np' .. n, function() keyPress(n) end, false)
    RegisterKeyMapping('pp_screen_np' .. n, 'Postal Prime screen: numpad ' .. n, 'keyboard', 'NUMPAD' .. n)
end

RegisterCommand('pp_screen_back', function() keyPress('back') end, false)
RegisterKeyMapping('pp_screen_back', 'Postal Prime screen: delete digit', 'keyboard', 'BACK')

RegisterCommand('pp_screen_enter', function()
    local s = session
    if not s then return end
    if s.view == 'entry' then press('submit') elseif s.view == 'result' then press('retry') end
end, false)
RegisterKeyMapping('pp_screen_enter', 'Postal Prime screen: confirm', 'keyboard', 'RETURN')

-- ─── DUI + texture swap ──────────────────────────────────────────────────────

CreateThread(function()
    print(('[as-postalprime] screen.lua loaded, Config.screen.enabled=%s'):format(tostring(cfg.enabled)))
    if not cfg.enabled then return end

    local size = cfg.size or 1024
    dui = CreateDui(('nui://%s/ui/screen.html'):format(RES), size, size)

    local deadline = GetGameTimer() + 10000
    while not IsDuiAvailable(dui) and GetGameTimer() < deadline do Wait(50) end
    if not IsDuiAvailable(dui) then
        print('[as-postalprime] locker screen DUI failed to load - falling back to the NUI keypad overlay')
        DestroyDui(dui)
        dui = nil
        return
    end
    Wait(300)

    local txdName = ('as_pp_screen_%d'):format(GetGameTimer())
    local txd = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txd, 'screen', GetDuiHandle(dui))
    AddReplaceTexture(cfg.txd or 'aslocker', cfg.txn or 'aslocker_diffuse_2', txdName, 'screen')

    SendDuiMessage(dui, json.encode({ action = 'init', rect = rect, debug = cfg.debug and true or false }))
    duiReady = true
    print(('[as-postalprime] locker screen ready: %s / %s -> DUI %dx%d'):format(cfg.txd or 'aslocker', cfg.txn or 'aslocker_diffuse_2', size, size))
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= RES then return end
    PPScreen.close()
    if duiReady then RemoveReplaceTexture(cfg.txd or 'aslocker', cfg.txn or 'aslocker_diffuse_2') end
    if dui then DestroyDui(dui) end
    dui, duiReady = nil, false
end)
