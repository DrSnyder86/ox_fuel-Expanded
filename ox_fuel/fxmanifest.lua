fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'

name 'ox_fuel_expanded'
author 'Overextended, CommunityOx contributors, and ox_fuel Expanded contributors'
version '1.5.2-expanded.2'
description 'Expanded community preview of ox_fuel with physical pumps, EV charging, positional audio, and a live register UI'

dependencies {
	'ox_lib',
	'ox_inventory',
	'san_andreas_sound',
	'ox_fuel_assets',
}

shared_scripts {
	'@ox_lib/init.lua',
	'config.lua',
	'electric_profiles.lua'
}

server_scripts {
	'server/version.lua',
	'server.lua'
}

client_script 'client/init.lua'

ui_page 'web/index.html'

files {
	'locales/*.json',
	'data/stations.lua',
	'nozzle_offsets.lua',
	'fuel_grades.lua',
	'vehicle_profiles.lua',
	'client/*.lua',
	'assets/sounds/*.ogg',
	'web/index.html',
	'web/style.css',
	'web/app.js',
	'web/ev.js',
	'web/checkout.js',
	'web/logos/*.png',
	'web/logos/ui/*.png',
}

ox_libs {
	'math',
	'locale',
}
