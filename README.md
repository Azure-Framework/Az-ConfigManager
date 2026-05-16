# Az-ConfigManager v6

Blue in-game admin config manager for Azure Framework/FiveM.

## v6 fixes
- Recursive resource scanning so configs are found even if they are not listed directly in fxmanifest.lua.
- Shows every resource, including resources with zero detected config files.
- Category buttons filter files only; they no longer hide resources from the left list.
- Detects local Config tables inside client/server/shared/main Lua files.
- Detects config-like Lua assignments, JSON, CFG, INI, and .callout files.
- Keeps the v5.2 debounce crash fix.

## Install
Ensure this resource last after your other resources:

```cfg
add_ace group.admin azmanager.open allow
ensure Az-ConfigManager
```

Open with `/azmanager`.
