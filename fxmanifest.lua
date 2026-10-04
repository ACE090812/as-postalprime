fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-postalprime'
author 'you'
description 'Postal Prime - standalone Amazon-style shopping app for sd-phone. Buy from a general goods catalog, pick a pickup locker at checkout, collect from a locker wall with as-interact, ox_target or qb-target + a pickup code. No sd-phone core files touched.'
version '1.0.0'

shared_script '@ox_lib/init.lua'

shared_scripts {
    'config.lua',
    'shared/locale.lua', -- T() helper (client + server)
    'locales/*.lua',     -- language files, picked with Config.locale
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/housing.lua',   -- home delivery: reads nolag_properties / qbx_properties
    'server/log.lua',       -- PPLog: audit log (console / ox_lib logger / Discord webhook)
    'server/deals.lua',     -- PPDeals: deal of the day, lightning deals, coupons
    'server/store.lua',     -- SQL persistence
    'server/main.lua',      -- core: the shared PP table, helpers, the app's state feed
    'server/shop.lua',      -- checkout, cancel, returns, Plus
    'server/lockers.lua',   -- locker doors, keypad, taking parcels
    'server/reviews.lua',
    'server/delivery.lua',  -- home / business delivery
    'server/parcels.lua',   -- exports for other resources
    'server/market.lua',    -- player marketplace
    'server/discovery.lua', -- also-bought, bought-before, wishlist alerts
    'server/tracking.lua',  -- live order tracking
    'server/restock.lua',   -- automatic restock + low-stock alerts
    'server/widget.lua',    -- phone widget feed (reads PP)
    'server/courier.lua',   -- player courier job (needs the PP table)
    'server/sweep.lua',     -- background sweep: ready / expire / notifications
    'server/admin.lua',     -- /ppadmin, pprestock
    'server/validate.lua',  -- startup config + locale check, ppcheck
}

client_scripts {
    'client/target.lua', -- must load before main.lua - defines the PPTarget bridge it uses
    'client/takeanim.lua', -- "take it out" animation, used by main.lua and home.lua's take zones
    'client/screen.lua', -- on-model DUI screen; defines PPScreen used by main.lua
    'client/home.lua',   -- home delivery: courier van + doorstep parcel boxes
    'client/courier.lua', -- player courier job: depot, rental, carrying, GPS
    'client/main.lua',
}

-- Postal Prime's own screen: sd-phone frames this inside an iframe pointed at
-- https://cfx-nui-as-postalprime/ui/index.html (see exports['sd-phone']:addCustomApp in client/main.lua)
-- - a completely separate page served by THIS resource, not sd-phone's own React app.
ui_page 'ui/index.html'
files { 'ui/**/*' }

-- The locker wall model/textures/door animations (mdx_cap_lockers) live in their own resource,
-- pp_lockerprops - this just needs it started first so the archetype is loadable by name.
-- oxmysql must also be started first - orders/plus/reviews are stored in your database now,
-- not a JSON file (see server/store.lua).
--
-- NOTE: this resource also needs ONE of as-interact, ox_target or qb-target started before it
-- (see Config.target in config.lua) - not listed below since `dependencies` can't express "either
-- one of these", so make sure whichever one you use is started first in server.cfg yourself.
-- (as-interact itself also needs ox_lib started before it, if that's the one you use.)
dependencies {
    'ox_lib',
    'oxmysql',
    'sd-phone',
    'as-lockerprops',
}
