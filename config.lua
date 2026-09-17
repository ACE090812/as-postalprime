Config = {
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
        { id = 'sunglasses', label = 'Polarized Sunglasses',               item = 'pp_sunglasses', price = 60,  icon = '🕶️', cat = 'clothing',  baseRating = 5, baseReviews = 60 },
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
        { id = 'legionsquare',  label = 'Legion Square Locker',     coords = vector3(170.9201, -1001.5137, 28.3388),  heading = 342.6835 },
        { id = 'bromley',       label = 'Bromley Locker',           coords = vector3(55.4414, -1739.2365, 28.3076),   heading = 233.9158 },
        { id = 'vespucci',      label = 'Vespucci Locker',          coords = vector3(-985.4567, -801.9762, 15.2739),  heading = 328.0291 },
        { id = 'towerhamlets',  label = 'Tower Hamlets Locker',     coords = vector3(-331.2124, 143.8541, 65.9996),   heading = 3.2400 },
        { id = 'bexley',        label = 'Bexley Locker',            coords = vector3(1110.4313, -352.7268, 66.0059),  heading = 35.3030 },
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
