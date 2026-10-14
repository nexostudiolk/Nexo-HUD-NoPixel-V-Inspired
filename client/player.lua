
local GROUP_MELEE = 2685387236
local GROUP_PARACHUTE = 431593103
local GROUP_SNIPER = 3082541095

local UNARMED = GetHashKey('WEAPON_UNARMED')

local cache = nil
local hiddenSent = false

local function changed(new, old)
    if not old then return true end
    for key, value in pairs(new) do
        if old[key] ~= value then return true end
    end
    return false
end


local currentVoiceMode = 2
local isTalkingEvent = false

local function setTalking(talking)
    local state = talking and true or false
    if isTalkingEvent ~= state then
        isTalkingEvent = state
        SendNUIMessage({
            action = 'updateVoiceTalking',
            isTalking = state
        })
    end
end

RegisterNetEvent('pma-voice:setTalkingMode', function(mode)
    if tonumber(mode) then
        currentVoiceMode = math.floor(NexoHud.Clamp(tonumber(mode), 1, 3))
        SendNUIMessage({ action = 'updateVoiceMode', voice = currentVoiceMode })
    end
end)

RegisterNetEvent('qb-voice:setTalkingMode', function(mode)
    if tonumber(mode) then
        currentVoiceMode = math.floor(NexoHud.Clamp(tonumber(mode), 1, 3))
        SendNUIMessage({ action = 'updateVoiceMode', voice = currentVoiceMode })
    end
end)

RegisterNetEvent('hud:client:ProximityActive', function(mode)
    if tonumber(mode) then
        currentVoiceMode = math.floor(NexoHud.Clamp(tonumber(mode), 1, 3))
        SendNUIMessage({ action = 'updateVoiceMode', voice = currentVoiceMode })
    end
end)

RegisterNetEvent('mumble:talkingStatus', setTalking)
RegisterNetEvent('pma-voice:setTalking', setTalking)
RegisterNetEvent('SaltyChat_TalkStateChanged', setTalking)

AddStateBagChangeHandler('talking', nil, function(bagName, _, value)
    local ply = GetPlayerFromStateBagName(bagName)
    if ply == PlayerId() then
        setTalking(value)
    end
end)

AddStateBagChangeHandler('proximity', nil, function(bagName, _, value)
    local ply = GetPlayerFromStateBagName(bagName)
    if ply == PlayerId() then
        if type(value) == 'table' then
            local idx = tonumber(value.index) or tonumber(value.mode)
            if idx then
                currentVoiceMode = math.floor(NexoHud.Clamp(idx, 1, 3))
                SendNUIMessage({ action = 'updateVoiceMode', voice = currentVoiceMode })
            end
        elseif tonumber(value) then
            currentVoiceMode = math.floor(NexoHud.Clamp(tonumber(value), 1, 3))
            SendNUIMessage({ action = 'updateVoiceMode', voice = currentVoiceMode })
        end
    end
end)

local function getVoiceMode()
    local proximity = LocalPlayer.state.proximity
    if type(proximity) == 'table' then
        local idx = tonumber(proximity.index) or tonumber(proximity.mode)
        if idx then return math.floor(NexoHud.Clamp(idx, 1, 3)) end
    elseif tonumber(proximity) then
        return math.floor(NexoHud.Clamp(tonumber(proximity), 1, 3))
    end
    return currentVoiceMode
end

local function isPlayerTalking(playerId)
    if isTalkingEvent then return true end
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.talking then return true end
    if MumbleIsPlayerTalking and (MumbleIsPlayerTalking(playerId) == 1 or MumbleIsPlayerTalking(playerId) == true) then return true end
    if NetworkIsPlayerTalking and (NetworkIsPlayerTalking(playerId) == 1 or NetworkIsPlayerTalking(playerId) == true) then return true end
    return false
end

local function getWeaponData(ped)
    local weapon = GetSelectedPedWeapon(ped)
    if weapon == 0 or weapon == UNARMED then return false, 0, 0, 0 end

    local group = GetWeapontypeGroup(weapon)
    if group == GROUP_MELEE or group == GROUP_PARACHUTE then return false, 0, 0, group end

    local total = GetAmmoInPedWeapon(ped, weapon)
    local maxClip = GetMaxAmmoInClip(ped, weapon, true)
    local clip, reserve

    if maxClip and maxClip > 0 then
        local ok, inClip = GetAmmoInClip(ped, weapon)
        clip = ok and inClip or 0
        reserve = math.max(total - clip, 0)
    else
        clip, reserve = total, 0
    end

    return true, clip, reserve, group
end

CreateThread(function()
    while true do
        Wait(Config.Intervals.player)

        if NexoHud.IsVisible() then
            hiddenSent = false

            local ped = PlayerPedId()
            local playerId = PlayerId()

            local maxHealth = GetEntityMaxHealth(ped)
            local health = GetEntityHealth(ped) - 100
            local healthRange = math.max(maxHealth - 100, 1)
            if IsEntityDead(ped) or health < 0 then health = 0 end

            local hasWeapon, ammoClip, ammoTotal, weaponGroup = getWeaponData(ped)

            local isAiming = Config.UseCustomCrosshair
                and NexoHud.Setting('player', 'crosshair', true)
                and IsPlayerFreeAiming(playerId)
                and weaponGroup ~= GROUP_SNIPER
                or false

            local inVehicle = IsPedInAnyVehicle(ped, false)
            local isSwimming = IsPedSwimming(ped)
            local showStamina = not inVehicle
                and not isSwimming
                and (IsPedRunning(ped) or IsPedSprinting(ped))

            local underwater = IsPedSwimmingUnderWater(ped)

            local data = {
                health = math.floor(NexoHud.Clamp((health / healthRange) * 100, 0, 100)),
                armor = math.floor(NexoHud.Clamp(GetPedArmour(ped), 0, 100)),
                hunger = math.floor(NexoHud.needs.hunger),
                thirst = math.floor(NexoHud.needs.thirst),
                showStamina = showStamina,
                stamina = math.floor(NexoHud.Clamp(100 - GetPlayerSprintStaminaRemaining(playerId), 0, 100)),
                isUnderwater = underwater,
                isSwimming = isSwimming,
                oxygen = math.floor(NexoHud.Clamp(GetPlayerUnderwaterTimeRemaining(playerId) * 10, 0, 100)),
                voice = getVoiceMode(),
                isTalking = isPlayerTalking(playerId),
                isRadio = NexoHud.radioActive and true or false,
                isAiming = isAiming,
                hasWeapon = hasWeapon,
                ammoClip = ammoClip,
                ammoTotal = ammoTotal
            }

            NexoHud.hideNativeCrosshair = isAiming

            if changed(data, cache) then
                cache = data
                SendNUIMessage({ action = 'updatePlayerHud', data = data })
            end
        elseif not hiddenSent then
            hiddenSent = true
            cache = nil
            NexoHud.hideNativeCrosshair = false
            SendNUIMessage({ action = 'hidePlayerHud' })
        end
    end
end)
