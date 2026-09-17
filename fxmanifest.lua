fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-postalprime'
author 'you'
description 'Postal Prime - standalone Amazon-style shopping app for sd-phone. Buy from a general goods catalog, pick a pickup locker at checkout, collect from a locker wall with ox_target or qb-target + a pickup code. No sd-phone core files touched.'
version '1.0.0'

shared_script '@ox_lib/init.lua'

shared_scripts {
    'config.lua',
}

server_scripts {
    'server/bridge.lua',
    'server/store.lua',
    'server/main.lua',
}

client_scripts {
    'client/target.lua', -- must load before main.lua - defines the PPTarget bridge it uses
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
-- NOTE: this resource also needs ONE of ox_target or qb-target started before it (see
-- Config.target in config.lua) - not listed below since `dependencies` can't express "either
-- one of these", so make sure whichever one you use is started first in server.cfg yourself.
dependencies {
    'ox_lib',
    'oxmysql',
    'sd-phone',
    'pp_lockerprops',
}
