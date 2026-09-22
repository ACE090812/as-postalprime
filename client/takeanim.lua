-- Shared "take the parcel out" animation, played wherever a spawned box prop is taken - the locker
-- wall's open-door box (client/main.lua) and a home doorstep box (client/home.lua). The box is
-- attached to the player's hand for the animation's duration so it looks like it's actually being
-- lifted out, not just vanishing the instant the target option is used; the caller still owns the
-- box entity and deletes it as normal once the server confirms the hand-off.

PPTakeAnim = {}

--- Plays Config.takeAnim on the local ped, attaching `box` (an existing entity, or nil) to their
--- hand for its duration, then calls `done()`. `done` is a plain callback, not a promise - callers
--- kick off the actual TriggerServerEvent from inside it so nothing is handed over until the
--- animation has actually finished.
--- dict/clip/duration are optional overrides (falls back to Config.takeAnim) - used to play a
--- different anim from the same helper, e.g. Config.parcelOpenAnim when opening a sealed parcel.
function PPTakeAnim.play(box, done, dict, clip, duration)
    local cfg = Config.takeAnim or {}
    dict = dict or cfg.dict or 'pickup_object'
    clip = clip or cfg.clip or 'pickup_low'
    duration = duration or cfg.duration or 1300

    local ped = PlayerPedId()
    lib.requestAnimDict(dict)

    if box and DoesEntityExist(box) then
        local bone = GetPedBoneIndex(ped, 28422) -- SKEL_R_Hand
        AttachEntityToEntity(box, ped, bone, 0.12, 0.02, 0.0, -90.0, 0.0, 0.0, true, true, false, true, 1, true)
    end

    -- Flags: 16 (upper body only) + 32 (cancellable) - the player can still walk off mid-anim
    -- instead of being rooted, and it doesn't look silly with the box already in-hand.
    TaskPlayAnim(ped, dict, clip, 3.0, -3.0, duration, 48, 0.0, false, false, false)

    SetTimeout(duration, function()
        if done then done() end
    end)
end