# as-postalprime

Postal Prime: a standalone Amazon-style shopping app for sd-phone. Registers itself into the
real phone through `exports['sd-phone']:addCustomApp` - no sd-phone core files touched. Players
browse a general goods catalog, check out and pick a pickup locker, then physically collect the
order from that locker with `as-interact`, `ox_target` or `qb-target` and a pickup code shown in the app.

## Screenshots

Captured from the real `ui/index.html`, `ui/widget.html` and courier depot with sample data (what you see in-game depends on your catalog, lockers and config).

### Shopping

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/shop-01-home.png" width="200" alt="Home"><br><sub>Home</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-02-home-scrolled.png" width="200" alt="Product grid"><br><sub>Product grid</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-03-search.png" width="200" alt="Search"><br><sub>Search</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-04-category.png" width="200" alt="Categories"><br><sub>Categories</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/shop-05-saved.png" width="200" alt="Saved items (wishlist)"><br><sub>Saved items (wishlist)</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-06-product.png" width="200" alt="Product page"><br><sub>Product page</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-07-product-reviews.png" width="200" alt="Reviews and also bought"><br><sub>Reviews and "also bought"</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-08-out-of-stock.png" width="200" alt="Out of stock"><br><sub>Out of stock</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/shop-09-cart.png" width="200" alt="Cart"><br><sub>Cart</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-10-checkout-locker.png" width="200" alt="Checkout: pick a locker"><br><sub>Checkout: pick a locker</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/shop-11-checkout-gift.png" width="200" alt="Checkout: send as a gift"><br><sub>Checkout: send as a gift</sub></td>
    <td></td>
  </tr>
</table>

### Sales, shipping options and subscriptions

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/sale-01-deals.png" width="200" alt="Lightning and daily deals"><br><sub>Lightning and daily deals</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/sale-02-on-sale-filter.png" width="200" alt="On-sale filter"><br><sub>On-sale filter</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/sale-03-checkout-coupon-plus.png" width="200" alt="Coupon applied (Plus member)"><br><sub>Coupon applied (Plus member)</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/ship-01-home-express-insurance.png" width="200" alt="Home delivery: express and insurance"><br><sub>Home delivery: express and insurance</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/ship-02-total.png" width="200" alt="Itemised total"><br><sub>Itemised total</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/sub-01-subscribe.png" width="200" alt="Subscribe and save"><br><sub>Subscribe &amp; save</sub></td>
    <td></td>
    <td></td>
  </tr>
</table>

### Orders

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/orders-01-in-progress.png" width="200" alt="Preparing and ready"><br><sub>Preparing and ready</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/orders-02-waiting-courier.png" width="200" alt="Waiting for a courier"><br><sub>Waiting for a courier</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/orders-03-out-for-delivery.png" width="200" alt="Out for delivery"><br><sub>Out for delivery</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/orders-04-live-tracking.png" width="200" alt="Live tracking and ETA"><br><sub>Live tracking and ETA</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/orders-05-delivered-insured.png" width="200" alt="Delivered, insured"><br><sub>Delivered, insured</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/orders-06-history-returns.png" width="200" alt="History: returns and points"><br><sub>History: returns and points</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/orders-07-damaged-expired-cancelled.png" width="200" alt="Damaged, expired, cancelled"><br><sub>Damaged, expired, cancelled</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/orders-08-write-review.png" width="200" alt="Write a review"><br><sub>Write a review</sub></td>
  </tr>
</table>

### Your account

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/you-01-profile-plus.png" width="250" alt="Profile and Postal Prime Plus"><br><sub>Profile and Postal Prime Plus</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/you-02-active-plus-selling.png" width="250" alt="Plus member who sells"><br><sub>Plus member who sells</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/you-03-seller.png" width="250" alt="Seller panel and storefront"><br><sub>Seller panel and storefront</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/you-04-loyalty-subscriptions.png" width="250" alt="Loyalty tier and subscriptions"><br><sub>Loyalty tier and subscriptions</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/you-05-locker-rentals.png" width="250" alt="Locker rentals"><br><sub>Locker rentals</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/you-06-spending-stats.png" width="250" alt="Spending stats"><br><sub>Spending stats</sub></td>
  </tr>
</table>

### Marketplace

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/market-01-storefronts.png" width="250" alt="Seller storefronts"><br><sub>Seller storefronts</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/market-02-one-shop.png" width="250" alt="One shop"><br><sub>One shop</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/market-03-listing.png" width="250" alt="A player listing"><br><sub>A player listing</sub></td>
  </tr>
</table>

### Locker keypad

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/locker-01-keypad.png" width="200" alt="Pickup keypad"><br><sub>Pickup keypad</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/locker-02-wrong-code.png" width="200" alt="Wrong code"><br><sub>Wrong code</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/locker-03-lockout.png" width="200" alt="Keypad lockout"><br><sub>Keypad lockout</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/locker-04-opened.png" width="200" alt="Door opened"><br><sub>Door opened</sub></td>
  </tr>
</table>

### Phone widgets

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/widget-01-small-ready.png" width="200" alt="Small widget: ready with code"><br><sub>Small widget: ready with code</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/widget-02-small-preparing.png" width="200" alt="Small widget: preparing"><br><sub>Small widget: preparing</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/widget-03-small-out-for-delivery.png" width="200" alt="Small widget: out for delivery"><br><sub>Small widget: out for delivery</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/widget-04-medium.png" width="200" alt="Medium widget"><br><sub>Medium widget</sub></td>
  </tr>
</table>

### Courier job

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/courier-01-shift.png" width="420" alt="Depot: shift"><br><sub>Depot: shift</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/courier-02-vehicles.png" width="420" alt="Depot: vehicles"><br><sub>Depot: vehicles</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/courier-03-order-board.png" width="420" alt="Depot: order board"><br><sub>Depot: order board</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/courier-04-my-run.png" width="420" alt="Depot: my run"><br><sub>Depot: my run</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/courier-05-run-hud.png" width="420" alt="Run HUD and progress bar"><br><sub>Run HUD and progress bar</sub></td>
    <td></td>
  </tr>
</table>

## Before you start it

1. **Ensure order**: this resource must start *after* `ox_lib`, `oxmysql`, `sd-phone`,
   **`pp_lockerprops`**, and whichever of **`as-interact`/`ox_target`/`qb-target`** you use
   (and after your inventory/framework) in `server.cfg`. Whichever target system you use isn't
   listed in this resource's own `dependencies` (FiveM can't express "either one of these"), so
   make sure it's actually started yourself. `as-interact` itself also needs `ox_lib` started
   before it.
2. **Create the catalog items** in your inventory's own item config - this resource does not
   create item definitions, only sells and hands them out. See "Item definitions" below for the
   full shipped set (`pp_earbuds`, `pp_phonecase`, etc, plus `money` if you use item-based payment).
3. **Fill in `Config.lockers`** with the coordinates/heading for each locker wall you want. This
   resource spawns the locker wall prop (`Config.lockerWall.prop`) at each of these points -
   `heading` is the prop's rotation. The actual model/textures/animations live in the separate
   `pp_lockerprops` resource (see "Locker wall prop" below) - it just needs to be started.
4. **Check `Config.framework` / `Config.inventory`** - `'auto'` detects qbx_core/qb-core/es_extended
   and ox_inventory/qb-inventory. Set explicitly if you run something auto-detect might get wrong.
   **Check `Config.target`** the same way - `'auto'` detects as-interact/ox_target/qb-target
   (whichever is actually started; as-interact wins if somehow more than one is), or set it
   explicitly.
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

## Icons and product pictures

Everything in the app is vector art, so it looks the same on every machine (emoji depend on each browser's emoji font, which
FiveM's browser often renders badly):

- **Product pictures** are SVG files in `ui/icons/` (earbuds, phonecase, charger, watch, hoodie, cap, sneakers, sunglasses,
  coffee, toolkit, lamp, plant, passport, box). Set `icon = 'earbuds'` on a `Config.catalog` entry (and on `Config.marketplace.allowedItems`) to use
  one. To use your own picture, drop an `.svg` / `.png` into `ui/icons/` and set `icon = 'icons/mything.svg'` - or give a full
  `https://` / `nui://` URL. `icon` can still be an emoji: the common ones are mapped to the matching built-in picture, anything
  else is shown as text.
- **Interface icons** (cart, search, home, truck, shield, ...) are inline SVG. Any emoji left in a translation string or typed by a
  player is swapped for the matching icon when the page renders, so the translation files did not need to change.
- **Seller storefront icons** are picked from a built-in set of ten (store, wrench, burger, car, shirt, coffee, leaf, gift, package, star).
- Parcels sent by other resources can pass `icon = 'passport'` (or any name / path above) instead of an emoji.

## Sealed parcels

Collecting an order (locker or home) no longer hands over the catalog items directly - it hands
over ONE sealed parcel item instead (`Config.parcelItems[order.boxSize]`, so a bigger order gets
a bigger box, same sizing that already picks the locker door/box model). Using that item is what
actually gives the real items and removes the box; what's inside is stored on the item's own
metadata (ox_inventory) / info (qb-inventory), so it survives a restart sitting in someone's
inventory with nothing extra in the database.

Placeholder icons for all four sizes ship in `icons/` - `pp_parcel_s.png` etc. They're plain flat
boxes, not renders of your actual `asparcel_*` locker props, so swap them for something nicer
whenever you like; same filenames, just replace the files.

### ox_inventory (`data/items.lua`)

```lua
['pp_parcel_s']  = { label = 'Small Parcel',       weight = 500,  stack = false, close = true, description = 'A sealed Postal Prime parcel. Use it to open and unpack your order.', server = { export = 'as-postalprime.pp_parcel_s' } },
['pp_parcel_m']  = { label = 'Medium Parcel',      weight = 1500, stack = false, close = true, description = 'A sealed Postal Prime parcel. Use it to open and unpack your order.', server = { export = 'as-postalprime.pp_parcel_m' } },
['pp_parcel_l']  = { label = 'Large Parcel',       weight = 3000, stack = false, close = true, description = 'A sealed Postal Prime parcel. Use it to open and unpack your order.', server = { export = 'as-postalprime.pp_parcel_l' } },
['pp_parcel_xl'] = { label = 'Extra Large Parcel', weight = 5000, stack = false, close = true, description = 'A sealed Postal Prime parcel. Use it to open and unpack your order.', server = { export = 'as-postalprime.pp_parcel_xl' } },
```

`stack = false` matters - each box's contents are unique to it (its metadata), so two different
orders' boxes must never merge into one inventory stack. `server.export` points each parcel at an
`as-postalprime` server export of the same name (`pp_parcel_s`, `pp_parcel_m`, `pp_parcel_l`,
`pp_parcel_xl`) - ox_inventory calls it with the `usingItem`/`usedItem` events when a player uses
the box, and that's what unpacks the contents and removes the parcel. No `client` export needed.

Copy the icons from `icons/` into `ox_inventory/web/images/` - ox_inventory picks them up by item
name automatically.

### qb-inventory (`qb-core`'s shared items)

```lua
['pp_parcel_s']  = { label = 'Small Parcel',       weight = 500,  type = 'item', useable = true, unique = true, shouldClose = true },
['pp_parcel_m']  = { label = 'Medium Parcel',      weight = 1500, type = 'item', useable = true, unique = true, shouldClose = true },
['pp_parcel_l']  = { label = 'Large Parcel',       weight = 3000, type = 'item', useable = true, unique = true, shouldClose = true },
['pp_parcel_xl'] = { label = 'Extra Large Parcel', weight = 5000, type = 'item', useable = true, unique = true, shouldClose = true },
```

`unique = true` is the qb-inventory equivalent of `stack = false` above - every box is its own
inventory slot, never merged. `useable = true` is required - `PPBridge.registerParcelOpener` calls
`QBCore.Functions.CreateUseableItem` for each of these, which only fires for items marked useable.

Most qb-core builds consume the item itself the moment it's used, before that callback runs - if
yours doesn't and parcels are duplicating instead of disappearing, set `Config.qbConsumesOnUse =
false` in `config.lua` and this resource removes it manually instead.

## How it works

1. **Browse & add to cart** - the catalog is entirely config-driven (`Config.catalog`), rendered in
   an Amazon-styled home screen with categories, search, and a product detail sheet.
2. **Checkout** - the player picks exactly one pickup locker from the config list (sorted by real
   in-game distance), then places the order. **Payment happens immediately at checkout** (cash
   account or cash item, per `Config.payment.mode`) - not at collection.
3. **Several orders at once** - a player can have up to `Config.order.maxActive` shop orders in
   flight (preparing, or ready and uncollected). Each has its own pickup code; entering a code at
   a locker opens the door for that order. Parcels sent by other resources never count towards the limit.
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

## Target system (as-interact / ox_target / qb-target)

`Config.target` picks how the locker wall's, courier van's and "Take Parcel"/"Place Parcel"
interactions are shown - `'as-interact'`, `'ox_target'`, `'qb-target'`, or `'auto'` (default)
to detect whichever one is actually started (preferring as-interact, then ox_target, then
qb-target if more than one happens to be). All of `client/main.lua`, `client/home.lua` and
`client/courier.lua` go through a small bridge in `client/target.lua`
(`PPTarget.addEntity`/`addSphereZone`/`removeEntity`/`removeZone`) instead of calling any of
those resources' exports directly, so the rest of the code doesn't care which one is running.
Whichever one you use has to actually be started before `as-postalprime` in `server.cfg` - it
isn't (and can't be) listed in this resource's own `dependencies`, since FiveM has no way to
express "one of these three." If you use `as-interact`, it also needs `ox_lib` started before
it (its own requirement, not this resource's).

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
  player's `{ orders, parcels, order history, plus membership, wishlist, coupon uses, seller
  balance }`. (Saves from before multiple orders existed - which kept one `active` order - are
  migrated automatically on load.)
- **`postalprime_reviews`** - one row per `(item_id, identifier)` pair. `data` is a JSON blob of
  that single review (`rating`, `title`, `body`, author name, timestamp).
- **`postalprime_stock`** - remaining stock for items with a `stock` cap.
- **`postalprime_listings`** - marketplace listings (see "Marketplace").
- **`postalprime_coupons`** - how many times each coupon code has been used server-wide.
- **`postalprime_rentals`** - locker rentals.
- **`postalprime_daily`** - per-day sales counters for `ppadmin stats`.

Saves are targeted: a player row is only written when its contents actually changed, money-related
changes (checkout, refunds, collecting, returns) are written immediately, and minor ones (cart,
wishlist, notification flags) are batched every `Config.storage.flushSeconds` and flushed when the
player leaves or the resource stops. `oxmysql` must be started before this resource - it's listed in
`dependencies` in `fxmanifest.lua`.

## Refunds while offline

If an order expires (or an admin cancels it) while the buyer is offline, the refund is queued on their
record (`pendingRefund`) and paid out the next time they open the app or, if they are online, within a few
seconds. Nothing is lost. Cancelling, expiring and admin-cancelling an order also put the stock and any
coupon use back, and the refund goes to whoever *paid* (the buyer of a gift, not the recipient).

## Phone notifications

A real notification (banner + lockscreen, via sd-phone's own `exports['sd-phone']:notify`) fires
for the player, on top of the in-app "ready" badge, when:

- their order becomes ready for pickup,
- an uncollected order expires and is refunded - and, `Config.notifications.expiryWarnSeconds` before
  that, a "collect it soon" warning,
- a saved (wishlist) item goes on sale or comes back in stock (`Config.notifications.wishlistAlerts`),
- one of their marketplace listings sells (when the buyer collects),
- a parcel arrived damaged and a goodwill refund was paid,
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

## Parcels from other resources

Another resource can put a parcel in a player's locker (as-passport uses this for passports). It goes through the normal prep time, pickup code and locker door, but there is nothing to pay and nothing to refund, and the player can't cancel it.

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
-- ok is true, or false with err = 'busy' (the player already has an active order, try again later),
-- 'bad_locker', 'bad_item' or 'bad_request'

local lockers = exports['as-postalprime']:getLockers()   -- { { id, label }, ... }
```

Server events: `as-postalprime:parcelCollected` (citizenid, ref, source) and `as-postalprime:parcelExpired` (citizenid, ref) when it sat uncollected until it expired. `metadata` is given to the item when the parcel is taken (ox_inventory metadata, or `info` for qb-inventory).

This needed these changes in `server/main.lua` and `server/bridge.lua` (already made): the `createParcel` and `getLockers` exports, items carrying `item` and `metadata` on collection, `PPBridge.addItem(source, item, count, metadata)`, and parcel orders skipping cancel and refund.

## Phone widgets

Two home-screen widgets ship with the app: **small** (the most urgent parcel: its status, or the pickup code once
it is ready at a locker) and **medium** (your two most recent parcels, each with a status). Players add them from the
phone's widget gallery ("Parcel tracking"); tapping one opens Postal Prime. They show the same statuses as the Orders tab
(preparing, waiting for a courier, courier collecting, out for delivery, ready, delivered, collected).

- `Config.widget.enabled` turns them off (they are not registered at all). `refreshSeconds` (min 5) is how often an
  open widget checks for changes, and `historyHours` is how long finished parcels stay in the medium widget.
- `server/widget.lua` answers the `as-postalprime:getWidget` callback (read-only) and `ui/widget.html` is the page the
  phone frames. The widget polls, because sd-phone doesn't push messages into home-screen widgets.
- Widget text is in `locales/en.lua` under `widget.*`, so it follows `Config.locale` like the rest.
- Nothing in sd-phone was changed; the widget uses its documented `widgets` option on `addCustomApp`.


## Sales: deal of the day, lightning deals and coupons

- **Deal of the day** (`Config.deals.daily`): `count` catalog items get `pct` off from midnight to midnight
  (server time), a different set each day.
- **Lightning deal** (`Config.deals.lightning`): one item at `pct` off for `durationSeconds` at the start of
  every `everySeconds` window. The home screen shows a banner for it.
- Deals are worked out from the clock alone, so every player and every restart agrees and nothing is saved.
  Add `noDeals = true` to a catalog item to keep it at full price. Marketplace items are never discounted.
- **Coupons** (`Config.coupons`): codes typed at checkout, as a percentage (`pct`, optionally capped with
  `maxDiscount`) or a flat amount (`flat`), with `minTotal`, a server-wide `uses` cap, `perPlayer` limit,
  `plusOnly` and `expiresAt`. They discount the items total, never the delivery fee. Cancelling or
  expiring the order gives the use back.
- The server prices everything itself - the app only shows a preview - so a modified client can't change a price.

## Returns and damaged parcels

- **Returns** (`Config.returns`): for `windowSeconds` after collecting an order, each item shows a **Return**
  button in the Orders tab. The item has to be in the player's inventory (a sealed parcel has to be opened
  first); they get `refundPct` of what they paid for it (coupon discount included in that maths), and the
  unit goes back into stock if it has a cap. Marketplace items, gifts taken by someone else and parcels
  from other resources can't be returned.
- **Damaged parcels**: a collected shop order has a `damagedChance` percent chance to "arrive damaged". The
  items are still handed over, plus `damagedRefundPct` of the item total as a goodwill refund and a phone notification.

## Automatic restock and low-stock alerts

An item's `stock` number in `Config.catalog` is its **maximum**. Every `Config.restock.intervalMinutes` each
capped item gets `Config.restock.amount` back (or its own `restockAmount`, 0 = never), up to the maximum.
Units returned by cancelled, expired or returned orders never push an item above its maximum.
When a capped item drops to `lowStockThreshold` or fewer a `lowstock` entry is written to the log.

## Marketplace (players selling)

Players with a job in `Config.marketplace.jobs` get a **Sell on Postal Prime** card in the You tab. They pick one
of `allowedItems` (each with its own min/max price), a quantity and a price. The stock is taken from their
inventory straight away (held in escrow on the listing) and the listing shows in the shop, under the
**Marketplace** category, as "Sold by <name>". Checkout works exactly like any other item (lockers, home
delivery, gifts, couriers, coupons - though not deals).

- The seller is paid when the buyer **collects** the order, minus `commissionPct`, into a balance in the app
  that they **Withdraw** to their bank. Cancelled and expired orders therefore never touch seller money, and the
  units go back on the listing.
- A listing can only be removed while none of its units are in uncollected orders; removing it returns the rest
  of the stock to the seller's inventory (it fails if they can't carry it).
- Marketplace items have no reviews and can't be returned. Admins can remove a listing with `/ppadmin market remove <id>`.

## Searching and discovery

The Home tab can be sorted (featured, price, rating, biggest deals) and filtered (on sale, in stock, bought before).
A product page shows **Customers also bought** - worked out from what players actually collected together,
recounted every 5 minutes, padded with the best-rated items in the same category when there isn't enough history yet.

## Live order tracking

While a player courier is driving an order to you, the Orders tab shows **Track on map**: a moving courier blip on
your map and a live ETA. Only the owner of the order can see it, and only while the courier has it loaded.

## Security and logging

- **Keypad lockout** (`Config.security.collect`): wrong pickup codes are counted per player and per locker. After
  `maxAttempts` the player's keypad is locked (the lock doubles each time, up to `maxLockSeconds`); a locker that
  sees too many wrong codes from anyone locks too. Every lockout fires the server event
  `as-postalprime:suspiciousCollect` (`source, citizenid, lockerId, lockCount`) so you can hook a police alert on it.
  (A pickup code is only ever matched against the *caller's own* ready orders, so this is abuse protection and
  an audit trail rather than a hole being closed.)
- **Logging** (`Config.logging`): purchases, cancellations, returns, damaged parcels, lockouts, low stock,
  marketplace listings/sales, coupon use and admin actions go to the console, ox_lib's logger (`lib.logger`) and/or a
  Discord webhook. `webhookEvents` picks which events are posted to Discord.

## Admin commands

Give your admins the ACE `add_ace group.admin command.ppadmin allow`, then (in game or from the console):

| Command | What it does |
| --- | --- |
| `ppadmin orders <id\|citizenid>` | list a player's in-flight orders |
| `ppadmin cancel <orderId>` | cancel any uncollected shop order; refunds the buyer, returns stock and the coupon use |
| `ppadmin refund <id\|citizenid> <amount>` | pay a refund (queued if they are offline) |
| `ppadmin plus <id\|citizenid> <days>` | grant Postal Prime Plus |
| `ppadmin stock <itemId> [amount]` | show or set an item's stock |
| `ppadmin restock <itemId> <amount>` | add stock (`pprestock` from the console still works) |
| `ppadmin coupon <CODE> [reset]` | show or reset a coupon's server-wide use count |
| `ppadmin market [remove <id>]` | list marketplace listings / remove one |
| `ppadmin loyalty <id\|citizenid> [points]` | show, or add (negative removes) loyalty points |
| `ppadmin rentals [end <id>]` | list locker rentals / end one |
| `ppadmin subs <id\|citizenid>` | list a player's subscriptions |
| `ppadmin stats [days]` | sales dashboard |
| `ppadmin repair [apply]` | scan for stuck orders etc. (add `apply` to fix them) |

## Config check and locales

On start (and any time with the `ppcheck` console command) the resource checks `config.lua` and prints plain-English
problems: duplicate or invalid catalog ids and prices, inventory items that don't exist in ox_inventory (including the
sealed-parcel boxes), bad locker coordinates, missing locker door models, a target system that isn't started,
coupon/deal settings that can't work, marketplace config, and any locale file that is missing keys or has a
`%s`/`%d` placeholder mismatch against English.

Outside the server, `lua tools/check-locales.lua` (from the resource folder) compares every `locales/*.lua` with
`locales/en.lua` and lists missing / extra / mismatched keys. Missing keys fall back to English at runtime.

## Shipping speed and delivery insurance

- **Express shipping** (`Config.shipping.express`): at checkout the player can pay `fee` (Plus members `plusFee`)
  to skip the queue; the order is ready after `prepSeconds` instead of the normal / Plus prep time.
- **Delivery insurance** (`Config.insurance`), home delivery only: an optional fee of `pct` % of the items total
  (between `minFee` and `maxFee`). If an insured doorstep parcel is taken by *someone else*, the owner is refunded what they
  paid for the items automatically and gets a phone notification. (Doorstep parcels can be taken by anyone by design -
  this is the safety net.)

## Loyalty points

`Config.loyalty`: collecting an order earns `pointsPerDollar` x what was paid for the items x the buyer's tier
multiplier (Bronze / Silver / Gold / Platinum by default; the tier comes from points earned over the lifetime, spending
points never lowers it). At checkout a switch redeems points as money off the items (`redeem.pointsPerDollar` points = $1,
up to `maxPct` of the items total). Cancelling an order gives the points back; returning items takes back the points
they earned. Orders taken by someone else earn nothing.

## Subscribe & save

On a product page, **Subscribe & save** orders the item again every day / week / 2 weeks (`Config.subscriptions.intervals`)
to a locker of your choice, at `discountPct` off (`plusDiscountPct` for Plus members). It is charged when due while the
player is online (a missed one waits for them) and is placed as an ordinary shop order, so it appears in Orders, has a
pickup code and counts towards `Config.order.maxActive`. If the player can't pay it retries every `retryMinutes` and
pauses after `maxFailures`. Manage them (pause / resume / cancel) in the You tab.

## Locker rentals

`Config.rentals`: rent a private storage door at any locker for `pricePerDay`. The renter sees a 6-digit code in the You
tab (they can share it or change it); typing it into **that locker's keypad** opens an ox_inventory stash (opened server-side,
and the stash ids are random, so other players can't open it by guessing). Because anyone holding a code can open a rental, every
wrong attempt at a locker that has rentals counts towards the keypad lockout. When a rental runs out the code stops
working; for `graceHours` the owner can still extend it, after that the rental ends (`clearOnExpire = true` also wipes what
was left inside; the default keeps the stash untouched but unreachable). **Needs ox_inventory.**

## Spending stats

The You tab shows lifetime totals: orders collected, money spent, money saved (deals, coupons, points), the last 6 months,
spending by category and most-bought items. Totals are kept on the player's record, so they are not limited to the few orders
the history keeps. (Orders are counted for whoever collected them.)

## Storefronts

Sellers can give their marketplace listings a **shop name, tagline and icon** (You tab). The Marketplace category shows a
card per shop to filter by seller. Clients only ever see an opaque seller key, never a citizen id.

## Offline notifications

A phone notification for a player who is offline (order ready, expired, marketplace sale, points earned, rental ending...)
is queued on their record (max 8, dropped after 48 hours) and delivered when they are next around.

## Inventory support

ox_inventory, qb-inventory and plain ESX (built-in inventory) are supported. ESX has no item metadata, so there the
sealed-parcel box is skipped and orders are handed over as plain items (the config check tells you so). Whatever the
inventory, a **full inventory never eats an order**: the hand-over is checked first, the player is told to make room, and the
door / box stays so they can try again (an unopened parcel box stays in their inventory).

## Sales dashboard and repair

- `ppadmin stats [days]` prints orders, revenue, average order, cancelled / expired / returns / damaged, refunds, coupon and
  points discounts, express and insurance fees and payouts, Plus and rental sales, marketplace volume and commission, and the
  top items. The counters are kept per day in `postalprime_daily`.
- `ppadmin repair` reports orders that are stuck or inconsistent - finished orders still listed as in flight, two ready
  orders sharing a locker door, a missing pickup code, a courier who vanished, negative stock or listings, expired rentals,
  subscriptions pointing at removed items - and `ppadmin repair apply` fixes what it can.
- `ppadmin loyalty`, `ppadmin rentals` and `ppadmin subs` look after the new features (see the admin table).

## Exports for other resources

Besides `createParcel` / `getParcels` / `getDeliveryInfo` / `getLockers` (see "Parcels from other resources"), these server
exports are available (all trusted, server-side only):

| Export | What it does |
| --- | --- |
| `addCatalogItem(entry)` | add a product at runtime (not saved - call it each time your resource starts) |
| `removeCatalogItem(id)` | take a product off sale (orders already placed still get their items) |
| `addCoupon(code, def)` / `removeCoupon(code)` | runtime coupon codes |
| `giftItems(cid, { itemId = qty }, { lockerId, sender, ref })` | put catalog items in someone's locker as a free parcel |
| `getOrders(cid)` | the character's in-flight orders |
| `getStock(itemId)` / `setStock(itemId, n)` | read / set stock |
| `addLoyaltyPoints(cid, points)` / `getLoyalty(cid)` | loyalty points |
| `grantPlus(cid, days)` | grant Postal Prime Plus |

Server events: `as-postalprime:orderPlaced (cid, orderId, total)`, `as-postalprime:orderCollected (cid, orderId, total)`,
plus the existing parcel events and `as-postalprime:suspiciousCollect`.

## Not included

Everything above is config-driven on purpose - catalog, prices, lockers, prep/expiry timing - so
none of it needs a code change to tune once it's running.