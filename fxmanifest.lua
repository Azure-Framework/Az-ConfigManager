fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'MadeByAzure'
description 'Azure Framework Resource Config Manager'
version '1.2.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'backups/.keep'
}
