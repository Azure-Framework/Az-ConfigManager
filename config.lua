Config = Config or {}

Config.Debug = true

-- Admin command/key access.
Config.Command = 'azmanager'
Config.AcePermission = 'azmanager.open'

-- Uses Az-Framework:isAdmin(src) first when Az-Framework is running, then falls back to ACE.
Config.UseAzFrameworkAdmin = true
Config.FrameworkResource = 'Az-Framework'

-- The manager should be ensured last. This delay lets the rest of the server boot before scanning.
Config.InitialScanDelayMs = 8000

-- Editing limits. Increase these if you have very large config files.
Config.MaxFileBytes = 750000
Config.MaxRawSaveBytes = 1000000
Config.MaxTableFieldBytes = 80000
Config.MaxParsedFieldsPerFile = 800

-- Some resources keep a small local Config table at the top of client.lua/server.lua/main.lua.
-- This lets the manager scan those script files too, then the parser only exposes safe config-style fields.
Config.AllowScriptFilesWithLocalConfig = true

-- v6: Recursive scan finds configs even when the fxmanifest uses wildcards or does not list them.
-- This is what makes every resource/config in your resources folder show up instead of only guessed paths.
Config.EnableRecursiveFileScan = true
Config.ShowResourcesWithoutConfig = true
Config.MaxRecursiveFilesPerResource = 1200
Config.MaxContentProbeBytes = 220000
Config.RecursiveSkipPathParts = {
    '/.git/', '/node_modules/', '/stream/', '/html/', '/ui/', '/web/', '/dist/', '/build/',
    '/obj/', '/bin/', '/cache/', '/.vscode/', '/.idea/', '/assets/', '/images/', '/img/',
    '/sounds/', '/audio/', '/fonts/', '/locales/', '/vendor/'
}

-- Resource names to never show in the editor.
Config.IgnoreResources = {
    ['Az-ConfigManager'] = true,
}
-- File extensions that can be opened in the manager.
Config.EditableExtensions = {
    lua = true,
    json = true,
    cfg = true,
    ini = true,
    callout = true,
    txt = true,
}

-- Names/paths that count as useful config files.
Config.ConfigNameKeywords = {
    'config', 'settings', 'shared/items', 'shared/shops', 'items', 'shops', 'jobs',
    'job', 'locations', 'coords', 'routes', 'spawns', 'vehicles', 'prices', 'values',
    'departments', 'permissions', 'licenses', 'weapons', 'callout', 'manifest.json', 'SETTINGS.lua', 'permissions.cfg'
}

-- Common paths checked even when a resource did not list a file in fxmanifest.lua.
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

-- Scans these fxmanifest metadata buckets for exact file paths.
Config.ManifestMetadataKeys = {
    'shared_script', 'shared_scripts',
    'client_script', 'client_scripts',
    'server_script', 'server_scripts',
    'file', 'files'
}

-- Optional safety. Saving still backs up first.
Config.BlockedSaveResources = {
    -- ['Backwood-AntiCheat'] = true,
}

-- Allow restarting target resources from the UI after saving.
Config.AllowRestartButton = true
