local RESOURCE = GetCurrentResourceName()
local nuiOpen = false
local requestCounter = 0
local pendingCallbacks = {}

local function setOpen(open, payload)
    nuiOpen = open == true
    SetNuiFocus(nuiOpen, nuiOpen)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = nuiOpen and 'open' or 'close',
        payload = payload or {}
    })
end

local function serverRequest(action, payload, cb)
    requestCounter = requestCounter + 1
    local requestId = tostring(GetGameTimer()) .. ':' .. tostring(requestCounter)
    pendingCallbacks[requestId] = cb
    TriggerServerEvent('az-configmanager:server:request', requestId, action, payload or {})

    SetTimeout(12000, function()
        if pendingCallbacks[requestId] then
            local callback = pendingCallbacks[requestId]
            pendingCallbacks[requestId] = nil
            callback(false, 'Request timed out.')
        end
    end)
end

RegisterCommand(Config.Command or 'azmanager', function()
    TriggerServerEvent('az-configmanager:server:open')
end, false)

RegisterNetEvent('az-configmanager:client:open', function(payload)
    setOpen(true, payload or {})
end)

RegisterNetEvent('az-configmanager:client:notify', function(data)
    SendNUIMessage({ action = 'toast', payload = data or {} })
end)

RegisterNetEvent('az-configmanager:client:response', function(requestId, ok, data)
    local cb = pendingCallbacks[tostring(requestId)]
    if cb then
        pendingCallbacks[tostring(requestId)] = nil
        cb(ok == true, data)
    end
end)

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('serverRequest', function(data, cb)
    data = data or {}
    serverRequest(data.action, data.payload or {}, function(ok, response)
        cb({ ok = ok, data = response })
    end)
end)

RegisterNUICallback('getPlayerCoords', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    cb({
        ok = true,
        data = {
            x = tonumber(string.format('%.3f', coords.x)),
            y = tonumber(string.format('%.3f', coords.y)),
            z = tonumber(string.format('%.3f', coords.z)),
            w = tonumber(string.format('%.3f', heading)),
            heading = tonumber(string.format('%.3f', heading))
        }
    })
end)

CreateThread(function()
    while true do
        if nuiOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustPressed(0, 200) then
                setOpen(false)
            end
            Wait(0)
        else
            Wait(350)
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE and nuiOpen then
        SetNuiFocus(false, false)
    end
end)
