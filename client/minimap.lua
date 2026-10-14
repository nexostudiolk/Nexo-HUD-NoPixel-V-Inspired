
local TXD = 'circlemap_nexo'
local KVP_KEY = 'nexo_hud:minimap3'      -- calibration per aspect ratio (new format)
local OLD_KVP_KEY = 'nexo_hud:minimap2'  -- old format: fixed screen fractions, see below


local RING = { left = 0.845, top = 0.10, diameter = 0.105 }

-- Calibration values are stored as FRACTIONS OF THE RING DIAMETER, not as fixed
-- fractions of the screen. GTA's minimap error (the map sitting off-centre in
-- the ring) grows and shrinks together with the size of the ring, so an offset
-- that is a fraction of the ring stays correct at any resolution and at any HUD
-- size chosen in /hudsettings. (The old code used fixed screen fractions, which
-- only lined up at the one resolution / HUD scale it was tuned on.)
--   x / y   -> offset, in ring diameters (x: right = +, y: down = +)
--   scale   -> size of the map circle relative to the ring
--   stretch -> width correction so the circle is round
local DEFAULT_TUNE = { x = -0.2952, y = 0.0857, scale = 0.591, stretch = 0.882 }
local Tune = {
    x = DEFAULT_TUNE.x, y = DEFAULT_TUNE.y,
    scale = DEFAULT_TUNE.scale, stretch = DEFAULT_TUNE.stretch
}

local PRESETS = {
    -- aspect, x, y, scale, stretch
    { aspect = 2.333, x = 1.7000,  y = -0.4500, scale = 0.591, stretch = 0.882 }, -- 21:9 Ultrawide
    { aspect = 1.778, x = -0.2952, y = 0.0857,  scale = 0.591, stretch = 0.882 }, -- 16:9 Standard
    { aspect = 1.600, x = -1.1095, y = 0.3190,  scale = 0.591, stretch = 0.794 }, -- 16:10 (1440x900)
    { aspect = 1.500, x = -1.5670, y = 0.4500,  scale = 0.591, stretch = 0.744 }, -- 3:2
    { aspect = 1.333, x = -2.3310, y = 0.6690,  scale = 0.591, stretch = 0.661 }, -- 4:3 (1024x768)
    { aspect = 1.250, x = -2.7120, y = 0.7780,  scale = 0.591, stretch = 0.620 }, -- 5:4 (1280x1024)
}

local function defaultFor(aspect)
    if aspect >= PRESETS[1].aspect then
        local p = PRESETS[1]
        return { x = p.x, y = p.y, scale = p.scale, stretch = p.stretch }
    end
    if aspect <= PRESETS[#PRESETS].aspect then
        local p = PRESETS[#PRESETS]
        return { x = p.x, y = p.y, scale = p.scale, stretch = p.stretch }
    end

    for i = 1, #PRESETS - 1 do
        local p1 = PRESETS[i]
        local p2 = PRESETS[i + 1]
        if aspect <= p1.aspect and aspect >= p2.aspect then
            local span = p1.aspect - p2.aspect
            local t = span > 0 and ((aspect - p2.aspect) / span) or 0
            return {
                x = p2.x + ((p1.x - p2.x) * t),
                y = p2.y + ((p1.y - p2.y) * t),
                scale = p2.scale + ((p1.scale - p2.scale) * t),
                stretch = p2.stretch + ((p1.stretch - p2.stretch) * t)
            }
        end
    end

    return { x = DEFAULT_TUNE.x, y = DEFAULT_TUNE.y, scale = DEFAULT_TUNE.scale, stretch = DEFAULT_TUNE.stretch }
end

-- Manual calibrations made with /vhudmap, one per aspect ratio (16:9, 16:10,
-- 21:9 ...). Every resolution with the same aspect ratio shares it, because the
-- values are relative to the ring size.
local Saved = {}
local currentKey = nil
local calibrating = false


local BASE_ASPECT  = 16 / 9
local STD_CIRCLE_H = 0.183
local CIRCLE_W_FRAC = 389 / 512
local CIRCLE_H_FRAC = 389 / 396


local STD = {
    minimap = { x = 0.000,  y = -0.047, w = 0.1638, h = 0.183 },
    blur    = { x = -0.010, y = 0.025,  w = 0.262,  h = 0.300 },
    mask    = { x = 0.000,  y = 0.000,  w = 0.128,  h = 0.200 }
}

local METERS_PER_MILE = 1609.344


local function getActiveAspect(resX, resY)
    local aspect = GetAspectRatio and GetAspectRatio(false) or 0.0
    if aspect <= 0.5 or aspect > 4.0 then
        aspect = (resX and resY and resX > 0 and resY > 0) and (resX / resY) or (16 / 9)
    end
    return aspect
end

local function aspectKey(resX, resY)
    return ('%.2f'):format(getActiveAspect(resX, resY))
end

local function copyTune(t)
    return { x = t.x, y = t.y, scale = t.scale, stretch = t.stretch }
end

local function loadSaved()
    -- The old key stored offsets in screen fractions. They can't be converted
    -- reliably (the resolution they were made at isn't known), and they are the
    -- reason the map only fitted at one resolution, so they are dropped.
    if GetResourceKvpString(OLD_KVP_KEY) then DeleteResourceKvp(OLD_KVP_KEY) end

    local raw = GetResourceKvpString(KVP_KEY)
    if not raw or raw == '' then return end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return end

    for key, entry in pairs(data) do
        if type(entry) == 'table' then
            local numKey = tonumber(key)
            -- Discard old broken 4:3 / 5:4 saved calibration if it has old clamped offscreen x
            local isOldBrokenNarrow = numKey and numKey <= 1.35 and (tonumber(entry.x) or 0) > -1.5
            if not isOldBrokenNarrow then
                Saved[tostring(key)] = {
                    x       = tonumber(entry.x)       or DEFAULT_TUNE.x,
                    y       = tonumber(entry.y)       or DEFAULT_TUNE.y,
                    scale   = tonumber(entry.scale)   or DEFAULT_TUNE.scale,
                    stretch = tonumber(entry.stretch) or DEFAULT_TUNE.stretch
                }
            end
        end
    end
end

local function persistSaved()
    if next(Saved) == nil then
        DeleteResourceKvp(KVP_KEY)
    else
        SetResourceKvp(KVP_KEY, json.encode(Saved))
    end
end

-- Picks the calibration for the current aspect ratio (saved one, else default).
local function selectTune(resX, resY)
    local aspect = getActiveAspect(resX, resY)
    local key = ('%.2f'):format(aspect)
    local source = Saved[key] or defaultFor(aspect)
    Tune.x, Tune.y = source.x, source.y
    Tune.scale, Tune.stretch = source.scale, source.stretch
    currentKey = key
    return key, Saved[key] ~= nil
end

loadSaved()


local function getAlignment(resX, resY)
    local ok, x0, y0, x1, y1 = pcall(function()
        SetScriptGfxAlign(76, 66) -- 'L', 'B'
        SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
        local ax0, ay0 = GetScriptGfxAlignPosition(0.0, 0.0)
        local ax1, ay1 = GetScriptGfxAlignPosition(1.0, 1.0)
        return ax0, ay0, ax1, ay1
    end)
    ResetScriptGfxAlign()

    local dx = (ok and x0 and x1) and math.abs(x1 - x0) or 0.0
    local dy = (ok and y0 and y1) and math.abs(y1 - y0) or 0.0

    if ok and x0 and y0 and dx > 0.01 and dy > 0.01 then
        return x0, y0, dx, dy
    end

    local aspect = getActiveAspect(resX, resY)
    local region = aspect > BASE_ASPECT and (BASE_ASPECT / aspect) or 1.0
    local margin = (1.0 - GetSafeZoneSize()) / 2.0
    return ((1.0 - region) / 2.0) + (margin * region), 1.0 - margin, region, 1.0
end


local textureReady = false
local lastResX, lastResY, lastSafezone, lastAspect = 0, 0, 0.0, 0.0

local function applyMaskTextures()
    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', TXD, 'radarmasksm')
    AddReplaceTexture('platform:/textures/graphics', 'radarmasklg', TXD, 'radarmasklg')
end

CreateThread(function()
    RequestStreamedTextureDict(TXD, false)
    while not HasStreamedTextureDictLoaded(TXD) do Wait(0) end

    applyMaskTextures()
    textureReady = true
    lastResX = 0 -- force the minimap to be placed with the circle mask
end)


local function applyMinimap()
    local resX, resY = GetActiveScreenResolution()
    if resX <= 0 or resY <= 0 then return end

    local ax, ay, bx, by = getAlignment(resX, resY)
    local aspect = getActiveAspect(resX, resY)

    local layout = NexoHud.GetMapLayout and NexoHud.GetMapLayout() or nil
    local lx = layout and layout.x or 0.0
    local ly = layout and layout.y or 0.0
    local ls = layout and layout.scale or 1.0

    -- Ring diameter in pixels (same size the NUI ring has, incl. /hudsettings scale).
    local ringPx = RING.diameter * resX * ls
    local diameterPx = ringPx * Tune.scale

    -- Offsets are in ring diameters -> convert to screen fractions for this resolution.
    local centerX = RING.left + lx + ((RING.diameter / 2.0) * ls) + (Tune.x * ringPx / resX)
    local centerY = RING.top + ly + (((RING.diameter * aspect) / 2.0) * ls) + (Tune.y * ringPx / resY)

    local hudCX = (centerX - ax) / bx
    local hudCY = (centerY - ay) / by

    local maskW = ((diameterPx / CIRCLE_W_FRAC) / (resX * bx)) * Tune.stretch
    local maskH = (diameterPx / CIRCLE_H_FRAC) / (resY * by)

    local s = diameterPx / (STD_CIRCLE_H * resY * by)
    local stdMaskCX = STD.mask.x + (STD.mask.w / 2.0)
    local stdMaskCY = STD.mask.y - (STD.mask.h / 2.0)

    local function place(name, c)
        local w, h = c.w * s * Tune.stretch, c.h * s
        local cx = hudCX + ((c.x + (c.w / 2.0) - stdMaskCX) * s * Tune.stretch)
        local cy = hudCY + (((c.y - (c.h / 2.0)) - stdMaskCY) * s)
        SetMinimapComponentPosition(name, 'L', 'B', cx - (w / 2.0), cy + (h / 2.0), w, h)
    end

    applyMaskTextures()
    SetMinimapClipType(1) -- circle
    place('minimap', STD.minimap)
    place('minimap_blur', STD.blur)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B',
        hudCX - (maskW / 2.0), hudCY + (maskH / 2.0), maskW, maskH)

    SetBlipAlpha(GetNorthRadarBlip(), 0)

    SetRadarBigmapEnabled(true, false)
    Wait(0)
    SetRadarBigmapEnabled(false, false)
end

local applying = false

local function safeApply()
    if applying or calibrating or not textureReady then return end
    applying = true

    local resX, resY = GetActiveScreenResolution()
    if resX > 0 and resY > 0 then selectTune(resX, resY) end

    applyMinimap()
    applying = false
end

function NexoHud.RefreshMinimap()
    if not textureReady or applying then
        lastResX = 0 -- the monitor loop below re-applies it within a second
        lastAspect = 0.0
        return
    end
    CreateThread(safeApply)
end


local sequenceId = 0

local function reapplySequence()
    sequenceId = sequenceId + 1
    local id = sequenceId

    CreateThread(function()
        for _, delay in ipairs({ 0, 700, 1500, 3000, 4000 }) do
            Wait(delay)
            if id ~= sequenceId then return end

            local waited = 0
            while (not textureReady or not IsScreenFadedIn() or IsPauseMenuActive()) and waited < 60000 do
                Wait(250)
                waited = waited + 250
                if id ~= sequenceId then return end
            end

            safeApply()
        end
    end)
end

AddEventHandler('playerSpawned', reapplySequence)
AddEventHandler('onClientResourceStart', function(name)
    if name == GetCurrentResourceName() then reapplySequence() end
end)


CreateThread(function()
    local safezoneWarningShown = false
    local wasLoaded = false
    local wasFadedIn = false
    local wasPaused = false

    while true do
        Wait(Config.Intervals.minimap)

        local resX, resY = GetActiveScreenResolution()
        local safezone = GetSafeZoneSize()
        local aspect = getActiveAspect(resX, resY)

        local loaded = NexoHud.loaded == true
        local fadedIn = IsScreenFadedIn()
        local paused = IsPauseMenuActive()

        if (loaded and not wasLoaded) or (fadedIn and not wasFadedIn) or (wasPaused and not paused) then
            reapplySequence()
        end
        wasLoaded, wasFadedIn, wasPaused = loaded, fadedIn, paused

        if textureReady and (resX ~= lastResX or resY ~= lastResY or safezone ~= lastSafezone or math.abs(aspect - lastAspect) > 0.01) then
            lastResX, lastResY, lastSafezone, lastAspect = resX, resY, safezone, aspect
            safeApply()
        end

        local warn = Config.ShowSafezoneWarning
            and loaded
            and not paused
            and safezone < Config.RequiredSafezone

        if warn ~= safezoneWarningShown then
            safezoneWarningShown = warn
            SendNUIMessage({ action = warn and 'showSafezoneWarning' or 'hideSafezoneWarning' })
        end
    end
end)


-- Zoom distance in game-world meters (SET_RADAR_ZOOM_TO_DISTANCE), plus the
-- radar position/rotation lock -- same mechanism as the ChaseHudRadar
-- reference: the map is centered on the player and rotated to match the
-- camera heading every frame, instead of relying on GTA's default zoom/rotation.
local zoom = tonumber(Config.MapZoom) or 140.0
local mapTracking = false

RegisterCommand('mapzoom', function(_, args)
    local value = tonumber(args[1])
    if not value then
        print(('[nexo-hud] usage: /mapzoom <number>  (meters, now: %s)'):format(zoom))
        return
    end
    zoom = math.max(10.0, value)
    print(('[nexo-hud] map zoom = %s meters'):format(zoom))
end, false)

local function releaseMapTracking()
    if not mapTracking then return end
    UnlockMinimapAngle()
    UnlockMinimapPosition()
    mapTracking = false
end

CreateThread(function()
    while true do
        Wait(0)

        if NexoHud.IsVisible() then
            local coords = GetEntityCoords(PlayerPedId())
            SetRadarAsExteriorThisFrame()
            SetRadarZoomToDistance(zoom)
            LockMinimapPosition(coords.x, coords.y)
            LockMinimapAngle(math.floor(GetGameplayCamRot(2).z + 0.5) % 360)
            mapTracking = true
        else
            releaseMapTracking()
            Wait(200)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then releaseMapTracking() end
end)


local function getHeading()
    return (-GetGameplayCamRot(2).z) % 360.0
end

CreateThread(function()
    local last = nil
    local hidden = false

    while true do
        Wait(Config.Intervals.compassHeading)

        if NexoHud.IsVisible() then
            hidden = false
            local heading = getHeading()

            if not last or math.abs(heading - last) >= 0.05 then
                last = heading
                SendNUIMessage({ action = 'updateCompassHeading', heading = heading })
            end
        elseif not hidden then
            hidden = true
            last = nil
            SendNUIMessage({ action = 'hideCompass' })
        end
    end
end)



local function getWaypointDirection(from, to)
    local bearing = math.deg(math.atan(to.x - from.x, to.y - from.y)) % 360.0
    local relative = ((bearing - getHeading() + 540.0) % 360.0) - 180.0

    if math.abs(relative) <= 45.0 then return 'straight' end
    if relative > 45.0 and relative <= 135.0 then return 'right' end
    if relative < -45.0 and relative >= -135.0 then return 'left' end
    return 'back'
end

CreateThread(function()
    local lastStreet, lastZone, lastWaypoint = nil, nil, nil
    local hidden = false

    while true do
        Wait(Config.Intervals.compassDetails)

        if NexoHud.IsVisible() then
            hidden = false

            local coords = GetEntityCoords(PlayerPedId())

            -- Street + zone
            local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z)) or ''
            local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
            if zone == 'NULL' then zone = '' end
            street, zone = street:upper(), zone:upper()

            if street ~= lastStreet or zone ~= lastZone then
                lastStreet, lastZone = street, zone
                SendNUIMessage({ action = 'updateCompassDetails', street = street, zone = zone })
            end

            -- Waypoint
            local blip = GetFirstBlipInfoId(8)
            if DoesBlipExist(blip) then
                local wp = GetBlipInfoIdCoord(blip)
                local dx, dy = wp.x - coords.x, wp.y - coords.y
                local distance = ('%.2f mi'):format(math.sqrt((dx * dx) + (dy * dy)) / METERS_PER_MILE)
                local direction = getWaypointDirection(coords, wp)
                local key = distance .. direction

                if key ~= lastWaypoint then
                    lastWaypoint = key
                    SendNUIMessage({ action = 'updateWaypoint', distance = distance, direction = direction })
                end
            elseif lastWaypoint then
                lastWaypoint = nil
                SendNUIMessage({ action = 'hideWaypoint' })
            end
        elseif not hidden then
            hidden = true
            lastStreet, lastZone, lastWaypoint = nil, nil, nil
            SendNUIMessage({ action = 'hideWaypoint' })
        end
    end
end)


local function showHelp(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function calibrate()
    if calibrating then return end
    calibrating = true

    do -- make sure we start from the calibration of the current aspect ratio
        local resX, resY = GetActiveScreenResolution()
        if resX > 0 and resY > 0 then selectTune(resX, resY) end
    end

    local backup = copyTune(Tune)
    local dirty = false

    while calibrating do
        Wait(0)

        local step = 0.0005
        if IsControlPressed(0, 21) then step = 0.004 end  -- Shift
        if IsControlPressed(0, 36) then step = 0.0001 end -- Ctrl

        -- Arrow keys move in ring-diameter units (~1px per tap at the default step).
        local move = step / RING.diameter

        local moved = false
        if IsControlPressed(0, 174) then Tune.x = Tune.x - move; moved = true end  -- left
        if IsControlPressed(0, 175) then Tune.x = Tune.x + move; moved = true end  -- right
        if IsControlPressed(0, 172) then Tune.y = Tune.y - move; moved = true end  -- up
        if IsControlPressed(0, 173) then Tune.y = Tune.y + move; moved = true end  -- down
        if IsControlPressed(0, 10) then Tune.scale = Tune.scale + (step * 2); moved = true end                 -- PgUp
        if IsControlPressed(0, 11) then Tune.scale = math.max(0.2, Tune.scale - (step * 2)); moved = true end -- PgDn
        if IsControlPressed(0, 38) then Tune.stretch = Tune.stretch + (step * 2); moved = true end             -- E
        if IsControlPressed(0, 44) then Tune.stretch = math.max(0.2, Tune.stretch - (step * 2)); moved = true end -- Q

        if moved then
            dirty = true
        elseif dirty then
            dirty = false
            applyMinimap()
        end

        local resX, resY = GetActiveScreenResolution()
        showHelp(('~b~Minimap calibration~s~~n~Arrows: move  |  PgUp/PgDn: size  |  Q/E: narrower/wider~n~Enter: save  |  Backspace: cancel~n~'
            .. 'x=%.4f  y=%.4f  scale=%.3f  stretch=%.3f~n~%dx%d (aspect %s)  safezone=%.2f~n~Saved for every resolution with this aspect ratio')
            :format(Tune.x, Tune.y, Tune.scale, Tune.stretch, resX, resY, currentKey or '?', GetSafeZoneSize()))

        if IsControlJustPressed(0, 191) then -- Enter
            Saved[currentKey] = copyTune(Tune)
            persistSaved()
            print(('[nexo-hud] minimap saved for aspect %s: x=%.4f y=%.4f scale=%.3f stretch=%.3f (%dx%d)')
                :format(currentKey, Tune.x, Tune.y, Tune.scale, Tune.stretch, resX, resY))
            calibrating = false
        elseif IsControlJustPressed(0, 177) then -- Backspace
            Tune.x, Tune.y, Tune.scale, Tune.stretch = backup.x, backup.y, backup.scale, backup.stretch
            applyMinimap()
            calibrating = false
        end
    end
end

RegisterCommand('vhudmap', function(_, args)
    if args[1] == 'debug' then
        CreateThread(function()
            local resX, resY = GetActiveScreenResolution()
            local key, isSaved = selectTune(resX, resY)
            local ax, ay, bx, by = getAlignment(resX, resY)
            local text = ('res=%dx%d  aspect=%.4f (key %s, %s)  nativeAspect=%.4f~n~safezone=%.3f~n~align ax=%.4f ay=%.4f bx=%.4f by=%.4f~n~tune x=%.4f y=%.4f scale=%.3f stretch=%.3f')
                :format(resX, resY, resX / resY, key, isSaved and 'saved' or 'auto default', GetAspectRatio(false),
                    GetSafeZoneSize(), ax, ay, bx, by,
                    Tune.x, Tune.y, Tune.scale, Tune.stretch)
            print('[nexo-hud] ' .. text:gsub('~n~', ' | '))

            local untilTime = GetGameTimer() + 20000
            while GetGameTimer() < untilTime do
                Wait(0)
                showHelp('~b~vhudmap debug~s~~n~' .. text)
            end
        end)
        return
    end

    if args[1] == 'reset' then
        -- Drops every manual calibration -> back to the automatic default everywhere.
        Saved = {}
        persistSaved()
        local resX, resY = GetActiveScreenResolution()
        if resX > 0 and resY > 0 then selectTune(resX, resY) end
        applyMinimap()
        return
    end

    CreateThread(calibrate)
end, false)
