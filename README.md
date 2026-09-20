# as-postalprime

Postal Prime: a standalone Amazon-style shopping app for sd-phone. Registers itself into the
real phone through `exports['sd-phone']:addCustomApp` - no sd-phone core files touched. Players
browse a general goods catalog, check out and pick a pickup locker, then physically collect the
order from that locker with `ox_target` or `qb-target` and a pickup code shown in the app.
Orders can also be delivered to a property's front door (home delivery), and optionally by real
players working the Postal Prime courier job.

## Before you start it

1. **Ensure order**: this resource must start *after* `ox_lib`, `oxmysql`, `sd-phone`,
   **`pp_lockerprops`**, and whichever of **`ox_target`/`qb-target`** you use (and after your
   inventory/framework) in `server.cfg`. Whichever target system you use isn't listed in this
   resource's own `dependencies` (FiveM can't express "either one of these"), so make sure it's
   actually started yourself.
2. **Create the catalog items** in your inventory's own item config - this resource does not
   create item definitions, only sells and hands them out. See "Item definitions" below for the
   full shipped set (`pp_earbuds`, `pp_phonecase`, etc, plus `money` if you use item-based payment).
3. **Fill in `Config.lockers`** with the coordinates/heading for each locker wall you want. This
   resource spawns the locker wall prop (`Config.lockerWall.prop`) at each of these points -
   `heading` is the prop's rotation. The actual model/textures/animations live in the separate
   `pp_lockerprops` resource (see "Locker wall prop" below) - it just needs to be started.
4. **Check `Config.framework` / `Config.inventory`** - `'auto'` detects qbx_core/qb-core/es_extended
   and ox_inventory/qb-inventory. Set explicitly if you run something auto-detect might get wrong.
   **Check `Config.target`** the same way - `'auto'` detects ox_target/qb-target (whichever is
   actually started; ox_target wins if somehow both are), or set it explicitly.
5. **Check `Config.payment.mode`** - `'account'` (cash balance) or `'item'` (physical cash item).
6. **Tune `Config.order`** - `prepSeconds` (how long "preparing" lasts before it's ready to
   collect), `expireSecondsAfterReady` (how long an uncollected order waits before it's cancelled
   and refunded), `targetDistance`/`zoneSize` for the locker interaction zones.
7. **Home delivery (optional)** - `Config.home`. Needs `nolag_properties` and/or `qbx_properties`
   started. Set `Config.home.enabled = false` to turn it off. See "Home delivery" below.
8. **Courier job (optional)** - `Config.courier`. Add the job to your framework, then set the depot
   coordinates with `/ppcoords`. See "Player courier job" below. `Config.courier.enabled = false`
   turns the whole thing off and every order falls back to the NPC van / locker as before.
9. **Edit `Config.catalog`** to whatever you actually want to sell - prices, icons, categories,
   and `baseRating`/`baseReviews` (flavour numbers shown until real player reviews take over -
   see "How reviews work" below).

## Item definitions

Every item name below is whatever you set in `config.lua` - these examples use the shipped
defaults. Add whichever your setup actually needs.

### ox_inventory (`data/items.lua`)

```lua
['pp_earbuds']    = { label = 'Wireless Earbuds, Noise Cancelling', weight = 200, stack = true, close = true },
['pp_phonecase']  = { label = 'Shockproof Phone Case',              weight = 100, stack = true, close = true },
['pp_charger']    = { label = 'Fast Charger 65W',                   weight = 150, stack = true, close = true },
['pp_watch']      = { label = 'Smart Watch Series X',               weight = 150, stack = true, close = true },
['pp_hoodie']     = { label = 'Pullover Hoodie, Unisex',            weight = 400, stack = true, close = true },
['pp_cap']        = { label = 'Snapback Cap, Adjustable',           weight = 100, stack = true, close = true },
['pp_sneakers']   = { label = 'Running Sneakers, Lightweight',      weight = 400, stack = true, close = true },
['pp_sunglasses'] = { label = 'Polarized Sunglasses',               weight = 100, stack = true, close = true },
['pp_coffee']     = { label = 'Coffee Beans, Dark Roast 1kg',       weight = 1000, stack = true, close = true },
['pp_toolkit']    = { label = 'Home Toolkit, 45-Piece',             weight = 2000, stack = true, close = true },
['pp_lamp']       = { label = 'LED Desk Lamp, Dimmable',            weight = 600, stack = true, close = true },
['pp_plant']      = { label = 'Potted Plant, Faux',                 weight = 500, stack = true, close = true },

-- Only needed if Config.payment.mode = 'item'. Most ox_inventory setups already ship a 'money'
-- item for exactly this purpose - check before adding a duplicate.
['money'] = { label = 'Cash', weight = 0, stack = true, close = true },
```

### qb-inventory (`qb-core`'s shared items)

Same idea - add each `pp_*` id as a normal, non-useable item with `useable = false`, plus `money`
if you're on item-based payment and don't already have one. Every `image` needs a matching png in
your inventory's own image folder - this resource only registers behaviour, it doesn't ship item
art.

## How it works

1. **Browse & add to cart** - the catalog is entirely config-driven (`Config.catalog`), rendered in
   an Amazon-styled home screen with categories, search, and a product detail sheet.
2. **Checkout** - the player picks exactly one pickup locker from the config list (sorted by real
   in-game distance), then places the order. **Payment happens immediately at checkout** (cash
   account or cash item, per `Config.payment.mode`) - not at collection.
3. **One shop order at a time** - a player can't place a new order while they already have one
   outstanding (preparing, or ready and uncollected). They have to collect it or let it expire
   first. Parcels sent by other resources (passports, licences) don't count towards this - see
   "Parcels from other resources".
4. **Preparing → Ready** - after `Config.order.prepSeconds`, the order flips to "ready for pickup"
   and a 6-digit pickup code appears in the Orders tab.
5. **Collect physically** - at the chosen locker wall, the player uses the target option
   ("Open Postal Prime Locker") and enters the code shown in the app. Entering it at the *wrong*
   locker, or the wrong code, fails - it has to be the same locker they picked at checkout. A
   correct code assigns the order a free door slot on that wall (`Config.lockerWall.totalDoors`),
   plays that door's real open animation, and drops a "Take Parcel" interaction point at the
   door's parcel offset (`Config.lockerBoxOffsets`) - only one door per wall can be open at a
   time, and it swings shut on its own (`Config.lockerWall.autoCloseMs`) if nobody takes the
   parcel out.
6. **Expiry & refund** - an uncollected order auto-cancels `Config.order.expireSecondsAfterReady`
   after becoming ready, and is refunded in full (it was already paid for at checkout).

## Target system (ox_target / qb-target)

`Config.target` picks how the locker wall's interactions ("Open Postal Prime Locker", "Take
Parcel") are shown - `'ox_target'`, `'qb-target'`, or `'auto'` (default) to detect whichever one
is actually started. All of `client/main.lua` goes through a small bridge in `client/target.lua`
(`PPTarget.addEntity`/`addSphereZone`/`removeEntity`/`removeZone`) instead of calling either
resource's export directly, so the rest of the code doesn't care which one is running. Whichever
one you use has to actually be started before `as-postalprime` in `server.cfg` - it isn't (and
can't be) listed in this resource's own `dependencies`, since FiveM has no way to express "either
one of these two."

## Locker wall prop

The actual locker wall model, texture dictionary and door-open/close animations ship in their
**own resource, `as-lockerprops`** (started as a dependency, no scripts, just streamed assets and
a `data_file 'DLC_ITYP_REQUEST'` registration in its own `fxmanifest.lua`) - keeping the prop
files out of the app's own code. `as-postalprime` just references the archetype by name
(`Config.lockerWall.prop`), and spawns one wall at each `Config.lockers` entry's `coords`/
`heading`. `Config.lockerBoxOffsets` are local offsets (relative to the wall prop) for where each
numbered door's parcel sits - used to place the "Take Parcel" point once that door is open, no
extra prop model needed for the parcel itself.

The `as_parcel_s/m/l/xl` box props ship in `as-lockerprops` too - `Config.lockerBoxOffsets`
gives each door slot both its attach offset and which size spawns there. When a door opens, the
matching box is attached to the wall at that offset and gets its own "Take Parcel" target point;
it's deleted the moment it's taken (or the door auto-closes unclaimed).

## Postal Prime Plus

A paid membership, config-driven via `Config.plus`:

- **Members** (`Config.plus.durationDays` from time of purchase/renewal) get **free delivery** and
  a faster prep time (`Config.plus.prepSeconds` instead of `Config.order.prepSeconds`).
- **Non-members** pay `Config.plus.deliveryFee` on top of the item total at checkout, and wait the
  standard prep time.
- Subscribing/renewing costs `Config.plus.price`, charged the same way as everything else
  (`Config.payment.mode`). Renewing while already a member extends from the current expiry, it
  doesn't reset it.
- Subscribe/renew from the **You** tab. The home screen shows a banner (join prompt for
  non-members, active-member confirmation for members), and checkout shows a nudge toward Plus
  whenever the player isn't subscribed.
- Membership is stored per player, alongside orders, in the `postalprime_players` SQL table.

## How reviews work

Reviews are gated on actually having collected the item, not just ordered it:

- Once an order is marked **Collected**, each item in it gets a "Rate & review" button in the
  Orders tab.
- Submitting a review (1-5 stars, a title, a comment) stores it server-side keyed by the player's
  identifier and that item - one review per player per item (submitting again overwrites their
  existing one, it doesn't stack).
- A product's displayed star rating and review count blend in real submitted reviews once any
  exist; until then it shows the config-seeded `baseRating`/`baseReviews` flavour numbers, so a
  brand new product doesn't look empty on day one.
- Reviews persist in the `postalprime_reviews` SQL table, independent of order history.

## Data storage (SQL, via oxmysql)

Everything persists to your database, not a JSON file - created automatically on first start:

- **`postalprime_players`** - one row per player identifier. `data` is a JSON blob of that
  player's `{ active order, order history, plus membership }`, matching the same shape the app
  and server logic have always used internally - only *where* it's saved changed.
- **`postalprime_reviews`** - one row per `(item_id, identifier)` pair. `data` is a JSON blob of
  that single review (`rating`, `title`, `body`, author name, timestamp).

Saves are targeted (only the player/review that actually changed is written), not a full-table
dump on every event. `oxmysql` must be started before this resource - it's listed in
`dependencies` in `fxmanifest.lua`.

## Known limitation - refunds while offline

If a player's order expires while they're offline, this resource can't credit most frameworks'
money/inventory for an offline player, so the order is still cleared but the refund is skipped (a
warning is printed server-side naming the player and amount). If you want guaranteed offline
refunds, the cleanest fix is queuing the refund and applying it via your framework's own
player-loaded/spawn event - left out here to avoid guessing at your specific framework's offline
API.

## Phone notifications

A real notification (banner + lockscreen, via sd-phone's own `exports['sd-phone']:notify`) fires
for the player, on top of the in-app "ready" badge, when:

- their order becomes ready for pickup,
- an uncollected order expires and is refunded,
- they physically collect a parcel from a locker, and
- their Postal Prime Plus membership is within 24 hours of expiring (fires once per membership
  period - resets automatically on renewal).

Sent server-side, so it reaches the player even if they're not currently in the app. If they're
offline when it happens, they simply see it (and the updated order state) next time they log in -
sd-phone's notify export only reaches connected players. This uses `Config.app.identifier` as the
notification's `app`/`appId`, so it shows with Postal Prime's own name/icon in the notification
center.

## Reorder

Any **Collected** order in the Orders tab gets a "🔁 Reorder" button alongside its review
prompts - it adds every item from that order back into the cart (skipping any that have since
been removed from `Config.catalog`) and jumps straight to Cart, so a repeat purchase doesn't mean
re-browsing Home from scratch. Parcels created by other resources (the passport, for example) show
no review or reorder buttons.

## Stock limits

Off by default. Add `stock = N` to any `Config.catalog` entry to cap how many can ever be sold at
once - the remaining count lives in the `postalprime_stock` SQL table (seeded from that config
value the first time the item is seen), not in `config.lua` itself, so it actually depletes as
people buy it and survives restarts. An item with no `stock` field is unlimited, same as before.

- The app shows "Only N left" once stock drops to 5 or below, and "Out of stock" (Add to Cart
  disabled) at 0.
- Checkout re-checks stock right before charging and again right before confirming the order, so
  two players can't both buy the last unit - whoever's charge finishes first gets it, the other is
  refunded automatically and told it just sold out.
- **Restock from the server console**: `asrestock <itemId> <amount>` (console/RCON only, not a
  player-usable in-game command). Works even on an item that currently has no cap yet.

## Gift orders

Checkout has a "🎁 Send as a gift" toggle. Turn it on, type the recipient's exact in-character
name (they need to be online), and the order goes to **their** locker/Orders tab instead of
yours - they get the "gift from <you>" note on it, and their own notifications (ready, expiry,
pickup) fire for them, not you. You're the one charged at checkout, though: the recipient's own
Postal Prime Plus status decides their delivery fee and prep speed, not yours, so what you're
shown at checkout is an estimate if your Plus status differs from theirs. A recipient who already
has an order on the way can't receive a gift until they collect or it expires, same one-order-at-
a-time rule as normal.

## Wishlist

Every catalog card and the item detail sheet have a heart button that saves/unsaves the item -
separate from the cart, and doesn't reserve or charge anything. A "❤️ Saved" chip next to the
category chips on Home filters down to just the saved items. Stored per player alongside orders
in the same SQL row, so it survives restarts.

## Cancelling an order

While an order is still **Preparing** (not yet ready for pickup), the Orders tab shows a "Cancel &
refund" button - it fully refunds the order and hands any spent stock back, then drops the order
into history marked "Cancelled & refunded". Once an order flips to **Ready for pickup** it can no
longer be cancelled from the app - at that point it has to be collected or left to expire like
before. If a courier has already started collecting a home or locker order (see "Player
courier job"), it can't be cancelled either.

## Locker capacity indicator

The locker list at checkout shows how busy each locker currently is - "Quiet", "Some activity", or
"Busy" - based on how many of that locker's doors currently have a ready, uncollected order sitting
in them (out of `Config.lockerWall.totalDoors`). This is just an indicator to help players spread
out, not a hard cap - a locker will still accept more orders even at "Busy".

## Order-ready map ping

The moment an order becomes ready, the player gets a blip + waypoint dropped on their assigned
locker (in addition to the phone notification), so they don't have to remember which of the
configured lockers it's sitting at. It clears automatically once the order is collected or expires.

## Parcels from other resources

Another resource can put a parcel in a player's locker. Three do at the moment: **as-passport**
(passports and replacement IDs), **as-birthcert** (birth certificates) and **as-drivingschool**
(replacement driving licences). Postal Prime doesn't need any of them to run - it only exposes the exports below, and they call it when they are
installed. The parcel goes through the normal prep time, pickup code and locker door, but there is
nothing to pay and nothing to refund, and the player can't cancel it.

### Start order

```
ensure oxmysql
ensure as-postalprime     # before the resources that send parcels
ensure as-passport        # optional
ensure as-birthcert       # optional
ensure as-drivingschool   # optional
```

If `as-postalprime` isn't started when they send a parcel, they fall back to putting the item straight
in the inventory (as-passport and as-birthcert via `Config.delivery.mode`, as-drivingschool via
`Config.Replace.mode`), so start Postal Prime first.

### Shopping is never blocked by a parcel

Parcels are kept in their own list (`parcels` in the player's saved data), separate from their shop
order. A waiting passport, birth certificate or licence never stops the player ordering from Postal Prime, and a shop order
in progress never stops a parcel arriving. Only a second *shop* order is blocked ("one shop order at a
time"). A player can have several parcels waiting at once, up to `Config.order.maxParcels` (default 10).
Each has its own pickup code; entering a code at the locker opens the door for the order it belongs to,
and the Orders tab shows them all. The app shows no cancel, review or reorder buttons on a parcel.

Parcels sent while an older version of this resource was running (stored in the shop order slot) are
moved to the new list automatically the first time the player's data loads.

### Courier deliveries

With `Config.courier.parcelDeliveries` on (and `Config.courier.lockerDeliveries`), a parcel that is ready
goes to the depot board while a courier is clocked on. A player courier carries it to the locker and
places it there for the same pay and XP as a locker order, and the customer is told who delivered it. If
nobody delivers it in time (or the courier abandons, loses the job or disconnects) it simply becomes
ready at the locker as before. It keeps the `expireSeconds` it was sent with either way.

`parcelDeliveries` can be a single `true` / `false`, or a table to choose per sending resource:

```lua
parcelDeliveries = {
    enabled = true,                 -- master switch: false = every such parcel goes straight to the locker
    ['as-passport'] = true,         -- passports (set false if you don't use as-passport)
    ['as-birthcert'] = true,        -- birth certificates (set false if you don't use as-birthcert)
    ['as-drivingschool'] = true,    -- replacement driving licences (set false if you don't use as-drivingschool)
    other = true,                   -- parcels from any other resource that calls createParcel
},
```

- Set a resource to `false` and its parcels skip the depot board and go straight to the locker.
- The sending resource is read from the call itself (`GetInvokingResource`), so the keys are the
  resource folder names. If you rename `as-passport`, `as-birthcert` or `as-drivingschool`, use the new name here.
- A parcel with no known sender (or one saved before this was added) counts as `other`.
- Set the line for any of them you don't run to `false`. A `false` resource is skipped entirely by the
  courier code: its parcels are never posted to the depot board, never offered to couriers, and go
  straight to the locker. (If the resource isn't installed nothing is ever sent, so leaving it `true` is
  harmless, but `false` keeps it out of the courier code completely.)
- This only controls the *courier* side. Whether a resource puts its item in a locker at all is set in
  that resource (`Config.delivery.mode`).

### For developers: `createParcel`

```lua
local ok, err = exports['as-postalprime']:createParcel(citizenid, {
    ref         = 'PP123',                        -- your own reference, sent back in the events below
    sender      = 'Los Santos Passport Office',
    lockerId    = 'some_locker_id',               -- one of the ids from getLockers()
    prepSeconds = 180,                            -- optional
    expireSeconds = 172800,                       -- optional, how long it waits once ready
    items = {
        { item = 'passport', label = 'Passport', icon = '🛂', qty = 1, metadata = { number = '123456789' } },
    },
})
-- ok is true, or false with err = 'busy' (the player already has Config.order.maxParcels parcels
-- waiting, try again later), 'bad_locker', 'bad_item' or 'bad_request'

local lockers = exports['as-postalprime']:getLockers()   -- { { id, label }, ... }
```

Server events: `as-postalprime:parcelCollected` (citizenid, ref, source) and
`as-postalprime:parcelExpired` (citizenid, ref) when it sat uncollected until it expired.
`metadata` is given to the item when the parcel is taken (ox_inventory metadata, or `info` for
qb-inventory). A courier delivery doesn't change either event: `parcelCollected` still fires when the
customer takes the parcel from the locker.

The changes that make this work are in `server/main.lua`, `server/store.lua` and `server/bridge.lua`: the
`createParcel` and `getLockers` exports, the separate `parcels` list, items carrying `item` and
`metadata` on collection, `PPBridge.addItem(source, item, count, metadata)`, and parcel orders skipping
cancel and refund.

## Home delivery

Pick "Home" at checkout and the parcel is dropped at the front door of one of your properties:
owned, rented (nolag) or keyholder. Properties are read straight from `nolag_properties` /
`qbx_properties` through `server/housing.lua`, so it works whether or not the property is currently
loaded. The server re-checks the address at checkout, so a client can't pick a property it has no
access to.

- Delivery is charged `Config.home.fee` instead of the normal locker delivery fee (free with Postal
  Prime Plus).
- Travel time is added on top of the prep time, based on the distance from `Config.home.depot` to
  the door (`secondsPer100m`, clamped by `minTravelSeconds` / `maxTravelSeconds`).
- With no player courier taking it, a courier van and driver ped (`Config.home.vans`,
  `courierModel`) drive up and drop the box at the door. Anyone within `animateRange` sees this;
  everyone else just sees the box when they walk up. Take it with the target option on the box.
- `Config.home.housing = 'auto'` queries every supported housing script that's started. Force one
  with `'nolag_properties'` or `'qbx_properties'`.

## Player courier job

Players with the `Config.courier.job` job (default `postalprime`) can deliver ready orders instead
of the NPC van. Turn it off with `Config.courier.enabled = false`.

### Setup

1. Add the job to your framework, for example in `qbx_core/shared/jobs.lua`:

   ```lua
   ['postalprime'] = { label = 'Postal Prime', defaultDuty = true, offDutyPay = false,
       grades = { [0] = { name = 'Collector', payment = 50 } } },
   ```

   Nothing in this resource hands the job out - give it through your job centre or admin menu.
2. Stand at each depot point and run `/ppcoords` (needs `group.admin`). It prints and copies a
   `vector4`. Paste them into `Config.courier.depot`: `desk` (menu), `pile` (where parcels are
   collected), `spawns` (rental bays), `returnPoint` / `returnRadius`. The shipped values are only
   a starting guess near the depot.
3. Vehicle keys: if `acestudios_vehiclekeys` is started, the courier is given a key for the rental
   and it is taken back on return (`GiveKey` / `TakeKey`). With `qbx_vehiclekeys` it uses that
   instead. With neither, no key is handed out.
4. Fuel: the rental is filled to 100% on spawn. Works with state-bag fuel and the `SetFuel` export
   of LegacyFuel, cdn-fuel, ps-fuel, lc_fuel, x-fuel and okokGasStation, plus `ox_fuel`.

### The run

1. **Clock on** at the depot desk (target option). The window has Shift, Vehicles, Order board and
   My run pages.
2. **Rent a company vehicle** (Vehicles page). A refundable deposit is charged the same way as
   checkout (`Config.payment.mode`). Vehicles are set in `Config.courier.vehicles` (label, model,
   level, capacity in box units, biggest box, deposit). Higher courier levels unlock bigger ones.
3. **Claim orders** from the Order board. While at least one courier is clocked on, a ready home
   order (and a locker order, if `lockerDeliveries` is on) is posted to the board instead of going
   to the NPC van. You can hold as many parcels as your level allows (`Config.courier.batch`) and
   as fit in your vehicle (`Config.courier.units`).
4. **Collect from the pile** at the depot, carry the box to your vehicle (press X to put it down)
   and load it. The delivery timer starts when the parcel is loaded.
5. **Deliver**: follow the GPS route, take the parcel out of the vehicle, and place it at the door
   or at the locker wall. The customer's app shows Waiting for a courier, Courier collecting and
   Out for delivery, and a home order shows "Delivered by <name>".
6. **Return the vehicle** at the depot and clock off. The deposit is refunded minus any damage.

### Pay, XP and levels

- Pay is worked out on the server: `(base + perKm * km + size bonus) * (1 + levelBonusPct% per
  level above 1)`, where km is the straight-line distance from the depot to the destination
  (`Config.courier.pay`).
- Time limit per parcel: `baseSeconds + perMeter * distance + perExtraParcel * (parcels held - 1)`
  (`Config.courier.timer`). Late deliveries lose `latePenaltyPct` of the pay for every
  `lateStepSeconds` over, never below `minPct`.
- XP per delivery (`Config.courier.xp`) moves the courier up `Config.courier.levels`.
- Pay is created by the script. It isn't taken from a business or society account.

### Vehicle damage and deposits

Damage is read on the server from the vehicle's engine and body health (average). Under
`Config.courier.damage.tolerance` percent is free, above it the deposit is reduced by
`deposit * damage% * maxDeductPct%`. The deposit is forfeited if the vehicle is destroyed, if the
courier is further than `abandonDistance` from it for `abandonSeconds`, or if they disconnect.
It is refunded if the resource stops, or if a rental is left over from a restart.

### Config toggles

- `allowOwnOrders` - `true` lets couriers claim and deliver orders they placed themselves (they
  still get paid and XP). `false` hides their own orders from them.
- `lockerDeliveries` - `true` lets couriers also carry locker orders to the locker wall. `false`
  keeps couriers on home deliveries only, and locker orders become ready as normal.
- `parcelDeliveries` - lets couriers also deliver parcels sent by other resources (as-passport
  passports, as-birthcert certificates, as-drivingschool replacement licences) to the locker, like a locker order. `true` / `false`,
  or a table with a switch per sending resource (`enabled`, `['as-passport']`, `['as-birthcert']`, `['as-drivingschool']`,
  `other`). Needs `lockerDeliveries = true` as well. See "Parcels from other resources".
- `hud.enabled`, `hud.x`, `hud.y` - the on-screen run list (screen fractions).

### Fallbacks

The order is handed to the NPC van (home) or made ready as normal (locker) when: nobody claims it
within `claimSeconds`, no courier is clocked on, a claimed parcel isn't loaded within `holdSeconds`,
a loaded parcel is `overdueSeconds` past its limit (the courier earns nothing), the courier
abandons the run, loses the job, or disconnects. Parcels from other resources (passports, certificates, licence
replacements, per `parcelDeliveries`) go to couriers too - see "Parcels from other resources".

Server-side checks cover the job, duty, distance to the desk, vehicle and door, vehicle capacity,
box size and level, so none of it trusts the client.

## Custom UI

The courier depot window, notifications, progress bars, run list and "take which parcel" picker
are this resource's own NUI (`ui/courier.js` and `ui/courier.css`, loaded by `ui/index.html`).
Order cancelled / collected messages use the same notifications. `ox_lib` is now only used for
callbacks, keybinds and loading models and animations, not for any menu or popup.

While the depot window is open, notifications drop down from the top of the window. Otherwise they
appear in the top right of the screen. The window header uses `ui/logo.png`.

The courier UI lives on the resource's root NUI page (not the copy sd-phone embeds for the phone
app). FiveM loads that page inside an iframe, so don't add a `window.top` check to `courier.js`.

## Not included

- Multiple concurrent orders per player.
- Society / business funding for courier pay.
- A job-centre entry or admin tool for giving out the courier job or editing courier XP.
- Translations. Text is English and hard-coded.

## Known courier limitations

- The depot coordinates and the parcel carry offsets on the `asparcel_*` models are unverified
  guesses - tune them in game (`/ppcoords`, `Config.courier.carry`).
- If a courier goes AFK, an order can take up to `claimSeconds` (10 minutes by default) to fall
  back to the NPC courier.
- The order board refreshes every few seconds while the window is open, not instantly.
- Clocking on is this script's own duty flag. It isn't tied to your framework's on/off duty, so
  the framework paycheck (job grade payment) is separate from delivery pay.

Everything above is config-driven on purpose - catalog, prices, lockers, prep/expiry timing - so
none of it needs a code change to tune once it's running.
