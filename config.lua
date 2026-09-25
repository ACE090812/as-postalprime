Config = {
    -- Language: any file in locales/ (locales/en.lua = English). Copy en.lua to add a language.
    locale = 'en',

    -- 'auto' detects qbx_core / qb-core / es_extended / falls back to 'standalone'.
    -- 'standalone' has no real money accounts - balance checks are skipped (always allowed).
    framework = 'auto',

    -- 'auto' detects ox_inventory / qb-inventory. Decides how catalog items are added/removed
    -- and (if payment.mode = 'item') how the cash item is read/removed.
    inventory = 'auto',

    -- Which targeting resource opens the locker wall's interactions. 'auto' detects whichever of
    -- ox_target / qb-target is actually started (ox_target wins if somehow both are). Set this
    -- explicitly only if you run both and auto-detect picks the wrong one.
    target = 'auto',

    app = {
        identifier  = 'as-postalprime',
        name        = 'Postal Prime',
        description = 'Shop, then collect from any Postal Prime locker.',
        icon = 'nui://as-postalprime/ui/icon.png',
    },

    -- Home-screen widgets (small and medium) that show your parcels: the most urgent one, its status and
    -- pickup code. Players add them from the phone's widget gallery. false = no widgets are registered.
    widget = {
        enabled = true,
        -- How often (seconds) an open widget asks the server for changes. Minimum 5.
        refreshSeconds = 10,
        -- Finished parcels (collected / expired / cancelled) stay in the medium widget for this many hours.
        historyHours = 72,
    },

    payment = {
        -- 'account' removes from a money account/balance (framework's cash account by default).
        -- 'item' removes a physical cash item from inventory instead. Charged at CHECKOUT, not
        -- collection - see "Payment timing" below.
        mode = 'account',
        account = 'bank',
        cashItem = 'money',
    },

    -- No hardcoded/fake items - whatever's listed here is what's actually sellable. `item` must
    -- already exist in your inventory's item config. `baseRating`/`baseReviews` are just flavour
    -- seed numbers shown until real player reviews exist for that product - once someone actually
    -- reviews it (see "How reviews work" in the README), the real average takes over.
    --
    -- `stock` is optional and off by default - leave it out entirely for unlimited stock (as
    -- below). Add `stock = N` to any item to cap how many can ever be sold before it shows
    -- "Out of stock" and blocks checkout; the remaining count lives in the `postalprime_stock`
    -- SQL table (not this file) so it survives restarts and actually depletes as people buy it.
    -- Restock a capped item live with the `pprestock <itemId> <amount>` server console command.
    catalog = {
        { id = 'earbuds',    label = 'Wireless Earbuds, Noise Cancelling', item = 'pp_earbuds',    price = 89,  icon = '🎧',  cat = 'tech',      baseRating = 4, baseReviews = 214 },
        { id = 'phonecase',  label = 'Shockproof Phone Case',              item = 'pp_phonecase',  price = 15,  icon = '📱',  cat = 'tech',      baseRating = 5, baseReviews = 84 },
        { id = 'charger',    label = 'Fast Charger 65W',                   item = 'pp_charger',    price = 22,  icon = '🔌',  cat = 'tech',      baseRating = 4, baseReviews = 140 },
        { id = 'watch',      label = 'Smart Watch Series X',               item = 'pp_watch',      price = 210, icon = '⌚',  cat = 'tech',      baseRating = 4, baseReviews = 53, stock = 15 },
        { id = 'hoodie',     label = 'Pullover Hoodie, Unisex',            item = 'pp_hoodie',     price = 48,  icon = '🧥',  cat = 'clothing',  baseRating = 5, baseReviews = 97 },
        { id = 'cap',        label = 'Snapback Cap, Adjustable',           item = 'pp_cap',        price = 25,  icon = '🧢',  cat = 'clothing',  baseRating = 4, baseReviews = 31 },
        { id = 'sneakers',   label = 'Running Sneakers, Lightweight',      item = 'pp_sneakers',   price = 95,  icon = '👟',  cat = 'clothing',  baseRating = 4, baseReviews = 280, stock = 25 },
        { id = 'sunglasses', label = 'Polarized Sunglasses',               item = 'pp_sunglasses', price = 60,  icon = '🕶️',  cat = 'clothing',  baseRating = 5, baseReviews = 60 },
        { id = 'coffee',     label = 'Coffee Beans, Dark Roast 1kg',       item = 'pp_coffee',     price = 18,  icon = '☕',  cat = 'home',      baseRating = 5, baseReviews = 330 },
        { id = 'toolkit',    label = 'Home Toolkit, 45-Piece',             item = 'pp_toolkit',    price = 55,  icon = '🧰',  cat = 'home',      baseRating = 4, baseReviews = 71 },
        { id = 'lamp',       label = 'LED Desk Lamp, Dimmable',            item = 'pp_lamp',       price = 32,  icon = '💡',  cat = 'home',      baseRating = 4, baseReviews = 45 },
        { id = 'plant',      label = 'Potted Plant, Faux',                 item = 'pp_plant',      price = 20,  icon = '🪴',  cat = 'home',      baseRating = 5, baseReviews = 22 },
    },

    categories = {
        { id = 'all',      label = 'All' },
        { id = 'tech',     label = 'Electronics' },
        { id = 'clothing', label = 'Fashion' },
        { id = 'home',     label = 'Home' },
    },

    -- Preset pickup lockers - these should match real postal-locker PROPS you've already placed
    -- around the map. This resource does not spawn or model the prop itself, only the ox_target
    -- interaction zone at its coordinates - point `coords`/`heading` at wherever you put each prop.
    -- The five below are your own actual locker placements (pulled from your locker prop setup).
    lockers = {
        { id = 'greenwich',    label = 'Greenwich Locker',     coords = vector3(170.9201, -1001.5137, 28.3388),  heading = 342.6835 },
        { id = 'bromley',      label = 'Bromley Locker',       coords = vector3(55.4414, -1739.2365, 28.3076),   heading = 233.9158 },
        { id = 'lewisham',     label = 'Lewisham Locker',      coords = vector3(-985.4567, -801.9762, 15.2739),  heading = 328.0291 },
        { id = 'towerhamlets', label = 'Tower Hamlets Locker', coords = vector3(-331.2124, 143.8541, 65.9996),   heading = 3.2400 },
        { id = 'bexley',       label = 'Bexley Locker',        coords = vector3(1110.4313, -352.7268, 66.0059),  heading = 35.3030 },
    },

    -- The physical locker wall prop spawned at each Config.lockers location, with per-door open
    -- animations. `stream/` ships the actual model/textures/anims - see fxmanifest.lua.
    lockerWall = {
        prop = 'aslocker',
        animDict = 'aslocker_animation',
        -- How many individual door slots the prop has (anim clips are named door_<1..totalDoors>_open/close).
        totalDoors = 26,
        interactDistance = 2.0,
        -- Box zone placed at each open door's parcel offset for the final "take it out" step.
        takeRadius = 0.5,
        -- If nobody takes the parcel out within this long, the door swings shut and the slot frees up.
        autoCloseMs = 45000,
        -- Parcel size by order size. Every unit in an order counts as 1 (or the catalog item's optional
        -- `weight = N`, e.g. weight = 3 on a bulky item), summed across the whole order:
        --   up to s units -> small box, up to m -> medium, up to l -> large, above that -> extra large.
        -- The order is given a free door whose fixed box (see lockerBoxOffsets) matches that size.
        boxSizeMaxUnits = { s = 2, m = 4, l = 7 },
        -- true (default): "Take Parcel" gives ONE pp_parcel_s/m/l/xl item (matching the order's box
        -- size) holding the order's contents in its metadata; using that item unpacks the real items
        -- into the inventory and removes the box. false: skip the box and give the order's items
        -- directly, like before this option existed.
        giveBoxItem = true,
    },

    -- Played on the player when they use "Take Parcel" - at the locker wall (the box comes off the
    -- open door) and on a home doorstep. The spawned box prop is attached to their hand for the
    -- animation's duration so it looks like it's actually being lifted out, not just vanishing.
    takeAnim = {
        dict = 'pickup_object',
        clip = 'pickup_low',
        duration = 1300, -- ms; the box is deleted and the item handed over once this ends
    },

    -- Home delivery: pick "Home" at checkout and a courier van drops the parcel at the front door of one
    -- of your properties (owned, rented or keyholder). Works with nolag_properties, qbx_properties,
    -- brutal_housing (v2), rcore_housing, qb-houses and ps-housing.
    home = {
        enabled = true,
        -- 'auto' = every supported housing script that's started, or force one:
        -- 'nolag_properties' / 'qbx_properties' / 'brutal_housing' / 'rcore_housing' / 'qb-houses' / 'ps-housing'.
        -- Set to 'auto' so whichever one you actually have running gets picked up; only force a single
        -- name if you run more than one housing script side by side and want just one of them used here.
        housing = 'qbx_properties',
        -- Delivery charge for home delivery - used INSTEAD of the normal delivery fee (plus.deliveryFee). Free with Postal Prime Plus.
        fee = 15,
        -- Travel time added to normal prep time, from this depot to the property's door.
        depot = vector3(-424.66, -2787.6, 6.0),
        secondsPer100m = 2.0,
        minTravelSeconds = 20,
        maxTravelSeconds = 300,
        -- Courier van (one picked at random per delivery) and driver ped.
        vans = { 'boxville2', 'speedo' },
        courierModel = 's_m_m_postal_01',
        -- Players within this many metres of the door when the parcel is dropped see the van arrive;
        -- everyone else simply sees the box when they walk up.
        animateRange = 250.0,
        spawnDistance = 160.0,     -- how far out along the road the van starts
        despawnAfterMs = 20000,    -- how long the van drives off before it's removed
        takeDistance = 2.5,        -- ox_target / qb-target distance to the box
        takeCheckDistance = 10.0,  -- server-side sanity check when taking it
    },

    -- Business delivery: another resource (the parts shop on as-browser) can send a parcel to a business. A courier
    -- (player, or the NPC van when nobody is on duty) takes it to the business's coordinates, and once dropped the
    -- items go straight into that business's ox_inventory stash and its employees get a notification.
    -- The business's coordinates and stash come from the sending resource, not from here.
    business = {
        enabled = true,
        playerDropSeconds = 3,     -- after a player courier places the box, wait this long before filling the stash
        vanDropSeconds = 25,       -- after an NPC van drop (lets the van sequence play out first)
    },

    -- Renders the pickup keypad ON the locker model's screen (DUI + texture swap) instead of a
    -- full-screen NUI overlay. Mouse moves a virtual cursor + left click presses; or type the code (0-9 / numpad), Backspace deletes, Enter confirms. ESC exits.
    -- NOTE: the swap is client-side and global to that model on YOUR client, so while you use one
    -- locker, every locker screen you can see shows your keypad. Other players still see idle.
    screen = {
        enabled = true,
        txd = 'aslocker',                 -- texture dictionary (embedded in aslocker.ydr = the model name)
        txn = 'aslocker_diffuse_2',       -- texture that holds the screen art
        size = 1024,                      -- DUI resolution (square). 2048 is sharper but heavier.
        -- Where the screen sits inside that texture, as fractions (0-1) of its width/height.
        -- Tune this until the keypad lines up with the glass. debug = true draws a magenta outline.
        rect = { x = 0.02, y = 0.0, w = 0.57, h = 1.0 },
        debug = false,
        sensitivity = 0.25,               -- virtual cursor speed
        maxDistance = 3.5,                -- auto-close if you walk this far from the locker
        -- Close-up camera while the screen is open (set cam = nil to disable).
        --   offset = where the screen's CENTRE sits on the prop, in LOCAL coords (x = right, y = forward, z = up)
        --   dist   = how far out from the screen the camera sits (metres) - smaller = more zoomed
        --   fov    = lens angle - smaller = more zoomed
        -- With debug = true you can tune it live in-game: /ppcam <x> <z> [dist] [fov]  (prints the line to paste here)
        cam = { offset = vector3(0.0, 0.0, 1.55), dist = 1.4, fov = 40.0 },
    },

    -- Local offset (relative to the locker wall prop's own position/rotation) of where each
    -- door's parcel actually sits, plus which parcel box model spawns there once that door is
    -- opened (asparcel_s/m/l/xl - shipped by pp_lockerprops alongside the wall).
    lockerBoxOffsets = {
        [1]  = { x = -0.9090, y = 0.0700, z = 0.1220, model = 'asparcel_m'  },
        [2]  = { x = -0.9090, y = 0.0700, z = 0.4390, model = 'asparcel_s'  },
        [3]  = { x = -0.9090, y = 0.0700, z = 0.6420, model = 'asparcel_l'  },
        [4]  = { x = -0.9090, y = 0.0700, z = 1.1170, model = 'asparcel_s'  },
        [5]  = { x = -0.9090, y = 0.0700, z = 1.3210, model = 'asparcel_m'  },
        [6]  = { x = -0.9090, y = 0.0700, z = 1.6380, model = 'asparcel_m'  },
        [7]  = { x = -0.9090, y = 0.0700, z = 1.9540, model = 'asparcel_s'  },
        [8]  = { x = -0.4480, y = 0.0700, z = 0.1220, model = 'asparcel_m'  },
        [9]  = { x = -0.4480, y = 0.0700, z = 0.4390, model = 'asparcel_s'  },
        [10] = { x = -0.4480, y = 0.0700, z = 0.6420, model = 'asparcel_m'  },
        [11] = { x = -0.4480, y = 0.0700, z = 0.9590, model = 'asparcel_s'  },
        [12] = { x = -0.4480, y = 0.0700, z = 1.1620, model = 'asparcel_s'  },
        [13] = { x = -0.4480, y = 0.0700, z = 1.3660, model = 'asparcel_m'  },
        [14] = { x = -0.4480, y = 0.0700, z = 1.6830, model = 'asparcel_l'  },
        [15] = { x =  0.4480, y = 0.0700, z = 0.1220, model = 'asparcel_s'  },
        [16] = { x =  0.4480, y = 0.0700, z = 0.3260, model = 'asparcel_m'  },
        [17] = { x =  0.4480, y = 0.0700, z = 0.6420, model = 'asparcel_l'  },
        [18] = { x =  0.4480, y = 0.0700, z = 1.1170, model = 'asparcel_xl' },
        [19] = { x =  0.4480, y = 0.0700, z = 1.7510, model = 'asparcel_m'  },
        [20] = { x =  0.4480, y = 0.0700, z = 2.0670, model = 'asparcel_s'  },
        [21] = { x =  0.9090, y = 0.0700, z = 0.1220, model = 'asparcel_xl' },
        [22] = { x =  0.9090, y = 0.0700, z = 0.7550, model = 'asparcel_s'  },
        [23] = { x =  0.9090, y = 0.0700, z = 0.9590, model = 'asparcel_l'  },
        [24] = { x =  0.9090, y = 0.0700, z = 1.4340, model = 'asparcel_m'  },
        [25] = { x =  0.9090, y = 0.0700, z = 1.7510, model = 'asparcel_s'  },
        [26] = { x =  0.9090, y = 0.0700, z = 1.9540, model = 'asparcel_s'  },
    },

    order = {
        -- One active (uncollected, unexpired) order per player at a time - they must collect or
        -- let it expire before placing another.
        -- How long from checkout until the order is "ready for pickup" at the locker.
        prepSeconds = 180,
        -- An uncollected order auto-cancels this long after becoming ready, and is fully refunded
        -- (money and/or items handed back) since it was already paid for at checkout.
        expireSecondsAfterReady = 1800,
        -- How close you need to be to a locker's coords for its ox_target option to appear.
        targetDistance = 2.0,
        -- Size of the ox_target box zone placed at each locker (width, length, height).
        zoneSize = vector3(1.0, 1.0, 2.0),
        -- How many past orders (collected/expired) to keep in a player's order history.
        historyLimit = 20,
        -- Parcels sent by other resources (passports etc.) waiting at once per player. They never block shop orders.
        maxParcels = 10,
    },

    -- Postal Prime Plus: a paid membership. Members get free delivery and faster prep; everyone
    -- else pays a delivery fee per order and waits the standard prep time.
    plus = {
        price = 500,
        durationDays = 7,
        -- Charged per order on top of the item total for non-members. Free for active members.
        deliveryFee = 15,
        -- How long "preparing" lasts for a member's order, instead of Config.order.prepSeconds.
        prepSeconds = 60,
    },
}

-- ─── Player courier job ──────────────────────────────────────────────────────
-- Home-delivery orders can be delivered by PLAYERS with the framework job below. While at least one
-- courier is clocked on, a ready home order is posted to the depot's order board instead of the NPC
-- van. If nobody claims it in time (Config.courier.claimSeconds), or every courier clocks off, or a
-- courier abandons / disconnects / runs out of time, the order automatically falls back to the NPC van.
--
-- Job to add in qbx_core/shared/jobs.lua:
--   ['postalprime'] = { label = 'Postal Prime', defaultDuty = true, offDutyPay = false,
--       grades = { [0] = { name = 'Collector', payment = 50 } } },
--
-- Every coordinate below is a STARTING GUESS at the GTA Post OP depot - stand where you want each one
-- and run /ppcoords (admin) to print + copy the exact vector4, then paste it here.
Config.courier = {
    enabled = true,
    job = 'postalprime',

    -- true  = couriers can claim and deliver their own orders (they still get paid + XP).
    -- false = a courier never sees / can't claim orders they placed themselves.
    allowOwnOrders = true,

    -- true  = ready LOCKER orders can also be delivered by couriers (carried to the locker wall and placed
    --         there; the customer then collects with their code as normal). If nobody takes it in time it
    --         simply becomes ready at the locker like before.
    -- false = couriers only ever handle home deliveries.
    lockerDeliveries = true,

    -- Parcels sent by other resources (as-passport passports, as-birthcert certificates, as-drivingschool replacement licences...)
    -- can be delivered by couriers too: when a courier is on duty they are posted to the depot board,
    -- and if nobody delivers them in time they simply become ready at the locker. Needs lockerDeliveries = true.
    -- Turn a line off for any resource you don't run, or don't want couriers handling.
    --   parcelDeliveries = true / false switches every sending resource at once, or use the table below.
    parcelDeliveries = {
        enabled = true,                 -- master switch: false = every such parcel goes straight to the locker
        ['as-passport'] = true,         -- passports (set false if you don't use as-passport)
        ['as-birthcert'] = true,        -- birth certificates (set false if you don't use as-birthcert)
        ['as-drivingschool'] = true,    -- replacement driving licences (set false if you don't use as-drivingschool)
        other = true,                   -- parcels from any other resource that calls createParcel
    },

    depot = {
        -- Menu point: clock on/off, rent a vehicle, order board, return vehicle.
        desk = vector3(-424.66, -2787.60, 6.0),
        -- Parcels are collected from here and carried to your vehicle.
        pile = vector3(-430.00, -2787.60, 6.0),
        -- Rental vehicles appear at the first FREE one of these (x, y, z, heading).
        spawns = {
            vector4(-445.57, -2789.71, 6.00, 45.17),
            vector4(-445.57, -2789.71, 6.00, 45.17),
            vector4(-445.57, -2789.71, 6.00, 45.17),
            vector4(-445.57, -2789.71, 6.00, 45.17),
        },
        -- Park the rental within returnRadius of this to hand it back (deposit refunded).
        returnPoint = vector3(-441.0, -2792.0, 6.0),
        returnRadius = 40.0,
        blip = { enabled = true, sprite = 478, colour = 5, scale = 0.8, label = 'Postal Prime Depot' },
        -- A few decorative parcel boxes stacked at the pile (local props, purely visual).
        pileProps = true,
    },

    -- Rentable company vehicles. deposit is charged up front and refunded when you return the vehicle;
    -- it is forfeited if the vehicle is destroyed, abandoned, or you disconnect while renting it.
    -- capacity is in box units (s=1, m=2, l=3, xl=4); maxBox is the biggest parcel it can carry.
    vehicles = {
        { key = 'scooter', label = 'Postal Scooter',  model = 'faggio',   level = 1, capacity = 2,  maxBox = 'm',  deposit = 150 },
        { key = 'van',     label = 'Prime Postal Van',      model = 'ppboxville', level = 2, capacity = 16, maxBox = 'xl', deposit = 750 },
    },
    units = { s = 1, m = 2, l = 3, xl = 4 },

    -- XP needed to reach each level (index = level). Max parcels you can hold at once per level (batch).
    levels = { 0, 150, 400, 800, 1500, 2500 },
    batch  = { 2, 2, 3, 3, 4, 5 },

    -- Pay per delivery, generated on the server from the straight-line distance depot -> door:
    --   (base + perKm * km + sizeBonus) * (1 + levelBonusPct% per level above 1) * lateMultiplier
    pay = {
        base = 50, perKm = 30,
        size = { s = 0, m = 10, l = 20, xl = 35 },
        levelBonusPct = 5,
        -- Late: lose latePenaltyPct of the pay for every lateStepSeconds over the limit, never below minPct.
        latePenaltyPct = 5, lateStepSeconds = 30, minPct = 50,
    },

    -- Time limit per parcel, starts when it is loaded into your vehicle:
    --   baseSeconds + perMeter * distance + perExtraParcel * (parcels you are holding - 1)
    timer = { baseSeconds = 120, perMeter = 0.12, perExtraParcel = 90 },

    -- XP per delivery: base + perSizeRank * (s=1..xl=4) + onTimeBonus if delivered within the limit.
    xp = { base = 20, perSizeRank = 5, onTimeBonus = 10 },

    -- Fallback timers (seconds).
    claimSeconds = 600,        -- unclaimed on the board this long -> NPC van
    holdSeconds = 900,         -- claimed but never loaded this long -> NPC van
    overdueSeconds = 600,      -- loaded and this far past its time limit -> NPC van (courier gets nothing)

    -- Damage cost, taken from the deposit when the vehicle is returned. Damage % is read on the SERVER from
    -- the vehicle's engine + body health (average). Under `tolerance` % is free; above it you lose
    -- deposit * damage% * maxDeductPct%  (so at maxDeductPct = 100 a fully wrecked return loses the whole deposit).
    damage = { enabled = true, tolerance = 5, maxDeductPct = 100 },

    -- Rental abandoned: the courier is further than this from their vehicle for this long -> forfeit.
    abandonDistance = 500.0,
    abandonSeconds = 300,

    -- Server-side sanity checks (metres).
    loadDistance = 9.0,        -- how close to the vehicle you must be to load / take a parcel
    deliverDistance = 12.0,    -- how close to the door you must be to place the parcel

    -- Carrying a parcel (attached to the right hand). Tweak if the box sits wrong on your asparcel_* models.
    carry = { bone = 60309, pos = vector3(0.025, 0.08, 0.255), rot = vector3(-145.0, 290.0, 0.0) },

    -- On-screen run list (left / top as fractions of the screen).
    hud = { enabled = true, x = 0.015, y = 0.60 },
}
