-- The game's unit tooltip for the unit the reticle is on: your target, else the
-- controller's soft target (an enemy, else a friend), as the mouse shows it on a
-- unit. It stays up while that unit is there: hidden by something else, it comes
-- back the frame after, once nothing else uses the tooltip.
--
-- The game has this as settings (ReticleTooltipEnemy/Friend), but the
-- controller UI holds them at 0 as temporary settings (forever branch,
-- Blizzard_Gamepad/Core.lua:24-25), and addon code can't turn them back on:
-- checked in game on 2026-11-24 (/gprt debug tooltip, DebugTooltip.lua). Its
-- interact tooltip (NPCs you can talk to, objects) stays on, so that one is left
-- to the game. This shows the game's own tooltip (GameTooltip, at its default
-- place, GameTooltip_SetDefaultAnchor) with the game's unit data (SetUnit).
-- A tooltip the game shows for something else (a button, a map pin) is left alone.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local ReticleTooltip = {
    -- Looked at in this order: your target, then the soft enemy, as the reticle
    -- does (Reticle.TARGET_UNITS), then a soft friend.
    UNITS = { "target", "softenemy", "softfriend" },
    EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED",
        "PLAYER_SOFT_INTERACT_CHANGED" },
}
ReticleOnTarget.ReticleTooltip = ReticleTooltip

local shownUnit   -- the unit token whose tooltip we show, or nil
local hiding = false   -- we're hiding it ourselves: don't bring it back
local refreshQueued = false

local function tooltipUsable()
    return type(GameTooltip) == "table" and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden())
        and type(GameTooltip_SetDefaultAnchor) == "function"
end

local function ourTooltipShown()
    return shownUnit ~= nil and GameTooltip:IsShown() and GameTooltip:GetOwner() == UIParent
end

local function hideOurs()
    local wasOurs = shownUnit and tooltipUsable() and ourTooltipShown()
    shownUnit = nil
    if wasOurs then
        hiding = true
        GameTooltip:Hide()
        hiding = false
    end
end

local function reticleUnit()
    for _, unitToken in ipairs(ReticleTooltip.UNITS) do
        if UnitExists(unitToken) then return unitToken end
    end
end

function ReticleTooltip.Refresh()
    local settings = ReticleOnTarget.GetSettings()
    if not (settings.reticleTooltip and ReticleOnTarget.IsControllerUIOn() and tooltipUsable()) then
        return hideOurs()
    end
    local unitToken = reticleUnit()
    if not unitToken then return hideOurs() end
    -- The game's tooltip is on something else: leave it.
    if GameTooltip:IsShown() and not ourTooltipShown() then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:SetUnit(unitToken)
    shownUnit = unitToken
end

-- Hidden by something else (the game's own tooltip code, another tooltip that
-- took it and let go): shown again the frame after, if the unit is still there.
local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        ReticleTooltip.Refresh()
    end)
end

local hooked = false
local function hookTooltip()
    if hooked or not tooltipUsable() then return end
    hooked = true
    GameTooltip:HookScript("OnHide", function()
        if hiding or not ReticleOnTarget.GetSettings().reticleTooltip then return end
        queueRefresh()
    end)
end

function ReticleTooltip.Watch() hookTooltip(); ReticleTooltip.Refresh() end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs(ReticleTooltip.EVENTS) do eventFrame:RegisterEvent(event) end
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then return ReticleTooltip.Watch() end
    ReticleTooltip.Refresh()
end)
