fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-postalprime'
author 'ACE Studios'
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
    'client/target.lua', 
    'client/main.lua',
}

ui_page 'ui/index.html'
files { 'ui/**/*' }

dependencies {
    'ox_lib',
    'oxmysql',
    'sd-phone',
    'as-lockerprops',
}
