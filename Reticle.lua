-- The reticle: the controller UI's GamepadReticle, a small dot the game puts at the
-- screen's middle (x) and the engine's aim height (GetCursorCenterPosition): where
-- the controller's automatic targeting aims. It also holds the auto-attack swing
-- timer, so it stays. The game places it once and again only on a resize or a
-- switch to the controller (GamepadReticleMixin:Recenter, forever branch
-- Blizzard_Gamepad/UI/Reticle/GamepadReticle.lua:22-26).
--
-- With a target (yours, or else the controller's soft target), the dot goes just
-- below the target's nameplate: anchored to it, so the game moves it with the
-- target and nothing here runs per frame. It's placed again only when the target
-- changes or a nameplate comes or goes. With no target, or no nameplate (they're
-- off, or the target is off screen), it stays where the game aims. The vertical
-- offset setting moves it up or down from the nameplate. It's a plain frame, not
-- a protected one, so it moves in combat too.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local Reticle = {
    -- This far below the nameplate, in UI units.
    BELOW_NAMEPLATE = 12,
    -- Whose nameplate it goes on: your target, friendly or not, or with no target
    -- the controller's soft target (what it would attack). With a target selected
    -- it never jumps to another unit: no nameplate for it (friendly ones are off
    -- unless the game's friendly nameplates are on), and it stays where the game aims.
    TARGET_UNITS = { "target", "softenemy" },
    EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" },
    -- The screen is 768 units tall at an effective scale of 1, whatever its pixels.
    SCREEN_HEIGHT_IN_UNITS = 768,
}
ReticleOnTarget.Reticle = Reticle

-- Secret values (hidden from addons in some situations) can't be used in math.
local function readableOrNil(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local placedOn    -- "nameplate", "screen", or nil while the game placed it
local placement   -- on a nameplate: { anchor = the part it's under, height = its offset }

local function shouldMove()
    return ReticleOnTarget.GetSettings().enabled and ReticleOnTarget.IsControllerUIOn()
        and type(GamepadReticle) == "table"
end

-- The height the game aims at, in the reticle's units.
function Reticle.AimHeight(reticle)
    local scale = reticle:GetEffectiveScale()
    if type(GetCursorCenterPosition) ~= "function" or not scale or scale <= 0 then return nil end
    local _, aimY = GetCursorCenterPosition()
    aimY = tonumber(readableOrNil(aimY))
    return aimY and aimY / scale or nil
end

-- Screen pixels as a frame's own units.
function Reticle.PixelsToFrameUnits(frame, pixels)
    local scale = frame:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    local physicalHeight
    if type(GetPhysicalScreenSize) == "function" then
        local _, height = GetPhysicalScreenSize()
        physicalHeight = tonumber(readableOrNil(height))
    end
    if not physicalHeight or physicalHeight <= 0 then physicalHeight = Reticle.SCREEN_HEIGHT_IN_UNITS end
    return pixels * Reticle.SCREEN_HEIGHT_IN_UNITS / physicalHeight / scale
end

-- The part of a nameplate you see: its health bar, or with names only (friendly
-- players, as an option) its name, else the whole plate. The plate keeps its
-- full size either way, so its own bottom can sit well below a name.
function Reticle.VisibleNameplatePart(nameplate)
    local unitFrame = nameplate.UnitFrame
    if type(unitFrame) == "table" then
        for _, part in ipairs({ unitFrame.healthBar, unitFrame.name }) do
            if type(part) == "table" and type(part.IsVisible) == "function" and part:IsVisible() then return part end
        end
    end
    return nameplate
end

-- The reticle's unit: the first of TARGET_UNITS that exists. Then its nameplate,
-- if it has one, and the unit.
function Reticle.TargetNameplate()
    local namePlates = _G.C_NamePlate
    if type(namePlates) ~= "table" or type(namePlates.GetNamePlateForUnit) ~= "function" then return nil end
    if type(UnitExists) ~= "function" then return nil end
    for _, unit in ipairs(Reticle.TARGET_UNITS) do
        if UnitExists(unit) then
            local succeeded, nameplate = pcall(namePlates.GetNamePlateForUnit, unit)
            if succeeded and nameplate then return nameplate, unit end
            return nil, unit
        end
    end
    return nil
end

function Reticle.Place()
    local reticle = _G.GamepadReticle
    if not shouldMove() then
        if placedOn and type(reticle) == "table" then
            placedOn = nil
            if type(reticle.Recenter) == "function" then reticle:Recenter() end
        end
        return
    end
    local nameplate = Reticle.TargetNameplate()
    if nameplate then
        local anchor = Reticle.VisibleNameplatePart(nameplate)
        local settings = ReticleOnTarget.GetSettings()
        local offsetPixels = ReticleOnTarget.Clamp(settings.offset, ReticleOnTarget.OFFSET_MIN, ReticleOnTarget.OFFSET_MAX, 0)
        local heightFromNameplate = -Reticle.BELOW_NAMEPLATE + Reticle.PixelsToFrameUnits(reticle, offsetPixels)
        reticle:ClearAllPoints()
        reticle:SetPoint("CENTER", anchor, "BOTTOM", 0, heightFromNameplate)
        placedOn = "nameplate"
        placement = { anchor = anchor, height = heightFromNameplate }
        return
    end
    local aimHeight = Reticle.AimHeight(reticle)
    if not aimHeight then return end
    reticle:ClearAllPoints()
    reticle:SetPoint("CENTER", UIParent, "BOTTOM", 0, aimHeight)
    placedOn = "screen"
end
function Reticle.PlacedOn() return placedOn end
-- Where it was put on a nameplate: { anchor, height }. Asked here, not measured:
-- a frame anchored to a nameplate (a restricted region) can't be measured from
-- addon code (GetPoint fails: "Can't measure restricted regions").
function Reticle.Placement() return placedOn == "nameplate" and placement or nil end

-- Placed again on the next frame, once, however many reasons came in this frame
-- (a nameplate going away is still on its unit while its event runs).
local placeQueued = false
local function placeNextFrame()
    if placeQueued or not shouldMove() then return end
    placeQueued = true
    C_Timer.After(0, function()
        placeQueued = false
        Reticle.Place()
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function() placeNextFrame() end)

-- Called once the world is entered: listens for target and nameplate changes
-- (each one checks the setting and the controller UI first, so a switch to the
-- controller later needs nothing more), and follows the game's own Recenter.
local watching = false
function Reticle.Watch()
    local reticle = _G.GamepadReticle
    if not watching and type(reticle) == "table" and type(reticle.Recenter) == "function"
        and type(hooksecurefunc) == "function" then
        watching = true
        for _, event in ipairs(Reticle.EVENTS) do pcall(eventFrame.RegisterEvent, eventFrame, event) end
        -- The game's own Recenter (a resize, a switch to the controller) puts it back in the middle: ours after it.
        hooksecurefunc(reticle, "Recenter", function()
            if shouldMove() then Reticle.Place() else placedOn = nil end
        end)
    end
    Reticle.Place()
end
