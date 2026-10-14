fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'nexo'
description 'Nexo HUD'
version '1.2.1'

ui_page 'web/index.html'

shared_script 'config.lua'

client_scripts {
    'client/main.lua',
    'client/settings.lua',
    'client/player.lua',
    'client/vehicle.lua',
    'client/minimap.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'web/index.html',
    'web/css/*.css',
    'web/fonts/*.woff2',
    'web/js/*.js',
    'audiodirectory/seatbelt_sounds.awc',
    'data/seatbelt_sounds.dat54.rel'
}

-- Custom seatbelt sounds (played by the seatbelt resource, e.g. qb-smallresources)
data_file 'AUDIO_WAVEPACK' 'audiodirectory'
data_file 'AUDIO_SOUNDDATA' 'data/seatbelt_sounds.dat'
