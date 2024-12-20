--[[ FX Information ]] --
fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'

--[[ Resource Information ]] --
name 'bcso_dispatch_addon'
author 'MineCop'
version '3.2.2'
description 'MineScripts Dev'

--[[ Manifest ]] --
dependencies {
	'ox_lib',
	'es_extended',
	'ps-dispatch'
}

shared_scripts {
	'@ox_lib/init.lua',
	'@es_extended/imports.lua',
	'config.lua',
	'shared.lua'
}

server_scripts {
	'sv_config.lua',
	'server.lua'
}

client_script 'client.lua'
