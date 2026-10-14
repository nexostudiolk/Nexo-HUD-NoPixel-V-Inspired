
NexoHud = {
    loaded = false,       -- player is logged in / character loaded
    cinematic = false,    -- cinematic bars active
    radioActive = false,  -- voice resource radio transmit state
    voiceResource = false, -- 'pma-voice' or 'qb-voice', set once detected
    hideNativeCrosshair = false,
    needs = { hunger = 100, thirst = 100 }
}

local Framework = Config.Framework
local FrameworkResource = Config.FrameworkResources[Framework]
local Core = nil


function NexoHud.Clamp(value, min, max)
    value = tonumber(value) or 0
    if value < min then return min end
    if value > max then return max end
    return value
end

function NexoHud.IsVisible()
    return NexoHud.loaded and not NexoHud.cinematic and not IsPauseMenuActive()
end


function NexoHud.Setting(group, key, default)
    local settings = NexoHud.Settings
    local section = settings and settings[group]
    if section == nil or section[key] == nil then return default end
    return section[key]
end

local function setNeeds(hunger, thirst)
    if hunger ~= nil then NexoHud.needs.hunger = NexoHud.Clamp(hunger, 0, 100) end
    if thirst ~= nil then NexoHud.needs.thirst = NexoHud.Clamp(thirst, 0, 100) end
end

local function readMetadata(playerData)
    if type(playerData) ~= 'table' or type(playerData.metadata) ~= 'table' then return end
    setNeeds(playerData.metadata.hunger, playerData.metadata.thirst)
end


local function refreshNeeds()
    if Framework == 'qbcore' and Core then
        local ok, data = pcall(function() return Core.Functions.GetPlayerData() end)
        if ok then readMetadata(data) end
    elseif Framework == 'qbox' then
        local ok, data = pcall(function() return exports[FrameworkResource]:GetPlayerData() end)
        if ok then readMetadata(data) end
    elseif Framework == 'esx' then
        for _, name in ipairs({ 'hunger', 'thirst' }) do
            TriggerEvent('esx_status:getStatus', name, function(status)
                if not status then return end
                local percent = status.percent
                if percent == nil and status.getPercent then percent = status.getPercent() end
                if percent == nil and status.val then percent = status.val / 10000 end
                if percent ~= nil then setNeeds(name == 'hunger' and percent or nil, name == 'thirst' and percent or nil) end
            end)
        end
    end
end

CreateThread(function()
    if not FrameworkResource then
        print(('^1[nexo-hud]^7 Unknown Config.Framework "%s". Use qbcore, esx or qbox.'):format(tostring(Framework)))
        return
    end

    while GetResourceState(FrameworkResource) ~= 'started' do Wait(500) end

    if Framework == 'qbcore' then
        Core = exports[FrameworkResource]:GetCoreObject()
        NexoHud.loaded = LocalPlayer.state.isLoggedIn == true
    elseif Framework == 'qbox' then
        NexoHud.loaded = LocalPlayer.state.isLoggedIn == true
    elseif Framework == 'esx' then
        Core = exports[FrameworkResource]:getSharedObject()
        NexoHud.loaded = Core and Core.IsPlayerLoaded and Core.IsPlayerLoaded() or false
    end

    refreshNeeds()

    while true do
        Wait(Config.NeedsRefreshInterval or 5000)
        if Framework ~= 'esx' then
            NexoHud.loaded = LocalPlayer.state.isLoggedIn == true
        end
        refreshNeeds()
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if Framework == 'esx' then return end
    NexoHud.loaded = true
    refreshNeeds()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if Framework == 'esx' then return end
    NexoHud.loaded = false
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    NexoHud.loaded = false
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    if Framework == 'esx' then return end
    readMetadata(data)
end)

RegisterNetEvent('esx:playerLoaded', function()
    if Framework ~= 'esx' then return end
    NexoHud.loaded = true
    refreshNeeds()
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    if Framework ~= 'esx' then return end
    NexoHud.loaded = false
end)

RegisterNetEvent('esx_status:onTick', function(statuses)
    if Framework ~= 'esx' or type(statuses) ~= 'table' then return end
    for _, status in ipairs(statuses) do
        if status.name == 'hunger' then setNeeds(status.percent, nil) end
        if status.name == 'thirst' then setNeeds(nil, status.percent) end
    end
end)

RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst)
    setNeeds(hunger, thirst)
end)


RegisterNetEvent('pma-voice:radioActive', function(active)
    NexoHud.radioActive = active and true or false
end)

RegisterNetEvent('qb-voice:radioActive', function(active)
    NexoHud.radioActive = active and true or false
end)

CreateThread(function()
    local function resolveVoiceResource()
        local wanted = Config.VoiceResource

        if wanted == 'pma-voice' or wanted == 'qb-voice' then
            return GetResourceState(wanted) == 'started' and wanted or false
        end

        -- 'auto' (or anything else): detect whichever is started, pma-voice first.
        if GetResourceState('pma-voice') == 'started' then return 'pma-voice' end
        if GetResourceState('qb-voice') == 'started' then return 'qb-voice' end
        return false
    end

    -- Voice resources can start slightly after this resource, so keep checking
    -- for a while instead of only checking once on load.
    for _ = 1, 20 do
        local resource = resolveVoiceResource()
        if resource then
            NexoHud.voiceResource = resource
            break
        end
        Wait(1000)
    end
end)


function NexoHud.SetCinematic(state)
    NexoHud.cinematic = state and true or false
    SendNUIMessage({ action = 'cinematicBars', state = NexoHud.cinematic })
end

local function toggleCinematic()
    NexoHud.SetCinematic(not NexoHud.cinematic)
end

if Config.Commands and Config.Commands.cinematic then
    RegisterCommand(Config.Commands.cinematic, toggleCinematic, false)
end

RegisterNetEvent('hud:client:ToggleCinematic', toggleCinematic)


NexoHud.devMode = false

local function toggleDevMode()
    NexoHud.devMode = not NexoHud.devMode
    SendNUIMessage({ action = 'devMode', state = NexoHud.devMode })
end

if Config.Commands and Config.Commands.devmode then
    -- restricted = true: only players granted the "command.<name>" ACE
    -- permission (see the ace setup in README.md) can run this.
    RegisterCommand(Config.Commands.devmode, toggleDevMode, true)
end

RegisterNetEvent('hud:client:ToggleDevMode', toggleDevMode)


CreateThread(function()
    local minimap = RequestScaleformMovie('minimap')
    while not HasScaleformMovieLoaded(minimap) do Wait(0) end

    local lastVisible = nil

    while true do
        Wait(0)

        local visible = NexoHud.IsVisible() and NexoHud.Setting('map', 'showMinimap', true)
        if visible ~= lastVisible then
            lastVisible = visible
            DisplayRadar(visible)
        end

        HideHudComponentThisFrame(6)
        HideHudComponentThisFrame(7)
        HideHudComponentThisFrame(8)
        HideHudComponentThisFrame(9)

        if NexoHud.hideNativeCrosshair then
            HideHudComponentThisFrame(14)
        end

        BeginScaleformMovieMethod(minimap, 'SETUP_HEALTH_ARMOUR')
        ScaleformMovieMethodAddParamInt(3)
        EndScaleformMovieMethod()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    DisplayRadar(true)
    SetRadarBigmapEnabled(false, false)
end)

-- Built-in chat disabled: override keymapping command so pressing T does nothing in this HUD
RegisterCommand('nexo_chat_open', function() end, false)

