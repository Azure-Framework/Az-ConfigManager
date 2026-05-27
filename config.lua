Config = Config or {}

Config.Debug = true


Config.Command = 'azmanager'
Config.AcePermission = 'azmanager.open'


Config.UseAzFrameworkAdmin = true
Config.FrameworkResource = 'Az-Framework'


Config.InitialScanDelayMs = 8000


Config.MaxFileBytes = 750000
Config.MaxRawSaveBytes = 1000000
Config.MaxTableFieldBytes = 80000
Config.MaxParsedFieldsPerFile = 800



Config.AllowScriptFilesWithLocalConfig = true



Config.EnableRecursiveFileScan = true
Config.ShowResourcesWithoutConfig = true
Config.MaxRecursiveFilesPerResource = 1200
Config.MaxContentProbeBytes = 220000
Config.RecursiveSkipPathParts = {
    '/.git/', '/node_modules/', '/stream/', '/html/', '/ui/', '/web/', '/dist/', '/build/',
    '/obj/', '/bin/', '/cache/', '/.vscode/', '/.idea/', '/assets/', '/images/', '/img/',
    '/sounds/', '/audio/', '/fonts/', '/locales/', '/vendor/'
}


Config.IgnoreResources = {
    ['Az-ConfigManager'] = true,
}

Config.EditableExtensions = {
    lua = true,
    json = true,
    cfg = true,
    ini = true,
    callout = true,
    txt = true,
}


Config.ConfigNameKeywords = {
    'config', 'settings', 'shared/items', 'shared/shops', 'items', 'shops', 'jobs',
    'job', 'locations', 'coords', 'routes', 'spawns', 'vehicles', 'prices', 'values',
    'departments', 'permissions', 'licenses', 'weapons', 'callout', 'manifest.json', 'SETTINGS.lua', 'permissions.cfg'
}


Config.CommonConfigFiles = {
    'config.lua',
    'shared/config.lua',
    'shared/items.lua',
    'shared/shops.lua',
    'shared/jobs.lua',
    'shared/locations.lua',
    'settings.lua',
    'jobs.lua',
    'locations.lua',
    'routes.lua',
    'vehicles.lua',
    'items.lua',
    'shops.lua',
    'data/config.json',
    'config/config.lua',
    'config/jobs.lua',
    'config/locations.lua',
    'config/departments_runtime.json',
    'characterui/spawns.json',
    'callouts/manifest.json',
    'client.lua',
    'server.lua',
    'main.lua',
    'shared.lua',
    'client/main.lua',
    'server/main.lua',
    'shared/main.lua',
}


Config.ManifestMetadataKeys = {
    'shared_script', 'shared_scripts',
    'client_script', 'client_scripts',
    'server_script', 'server_scripts',
    'file', 'files'
}


Config.BlockedSaveResources = {
    
}


Config.AllowRestartButton = true
