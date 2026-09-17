# as-postalprime

Postal Prime: a standalone Amazon-style shopping app for sd-phone. Registers itself into the
real phone through `exports['sd-phone']:addCustomApp` - no sd-phone core files touched. Players
browse a general goods catalog, check out and pick a pickup locker, then physically collect the
order from that locker with `ox_target` or `qb-target` and a pickup code shown in the app.

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
7. **Edit `Config.catalog`** to whatever you actually want to sell - prices, icons, categories,
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
3. **One order at a time** - a player can't place a new order while they already have one
   outstanding (preparing, or ready and uncollected). They have to collect it or let it expire
   first.
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
**own resource, `pp_lockerprops`** (started as a dependency, no scripts, just streamed assets and
a `data_file 'DLC_ITYP_REQUEST'` registration in its own `fxmanifest.lua`) - keeping the prop
files out of the app's own code. `as-postalprime` just references the archetype by name
(`Config.lockerWall.prop`), and spawns one wall at each `Config.lockers` entry's `coords`/
`heading`. `Config.lockerBoxOffsets` are local offsets (relative to the wall prop) for where each
numbered door's parcel sits - used to place the "Take Parcel" point once that door is open, no
extra prop model needed for the parcel itself.

The `mdx_parcel_s/m/l/xl` box props ship in `pp_lockerprops` too - `Config.lockerBoxOffsets`
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
re-browsing Home from scratch.

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
- **Restock from the server console**: `pprestock <itemId> <amount>` (console/RCON only, not a
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
before.

## Locker capacity indicator

The locker list at checkout shows how busy each locker currently is - "Quiet", "Some activity", or
"Busy" - based on how many of that locker's doors currently have a ready, uncollected order sitting
in them (out of `Config.lockerWall.totalDoors`). This is just an indicator to help players spread
out, not a hard cap - a locker will still accept more orders even at "Busy".

## Order-ready map ping

The moment an order becomes ready, the player gets a blip + waypoint dropped on their assigned
locker (in addition to the phone notification), so they don't have to remember which of the
configured lockers it's sitting at. It clears automatically once the order is collected or expires.

## Not included

- Multiple concurrent orders per player.

Everything above is config-driven on purpose - catalog, prices, lockers, prep/expiry timing - so
none of it needs a code change to tune once it's running.
