-- /gprt debug tooltip: a 30-second check, debug builds only. The controller UI
-- holds the game's soft-target tooltip settings at 0 as temporary settings
-- (Blizzard_Gamepad/Core.lua:24-25). This turns them on from addon code, then
-- logs, at each soft-target change, whether the game's tooltip shows that unit.
-- Your settings are put back at the end (or at the next login after a reload),
-- and a reload box writes the log to GamepadReticleOnTargetDebugDB.tooltipProbe.
local ReticleOnTarget = _G.GamepadReticleOnTarget
local Debug = ReticleOnTarget.Debug

local TooltipProbe = {
    SECONDS = 30,
    SAMPLES_KEPT = 60,
    SETTINGS = { "SoftTargetTooltipEnemy", "SoftTargetTooltipFriend", "SoftTargetTooltipInteract" },
    -- event -> the soft target's unit token
    EVENTS = { PLAYER_SOFT_ENEMY_CHANGED = "softenemy", PLAYER_SOFT_FRIEND_CHANGED = "softfriend",
        PLAYER_SOFT_INTERACT_CHANGED = "softinteract" },
    SAMPLE_DELAY = 0.15,   -- seconds after the change: the game's tooltip has had a frame to show
}
Debug.TooltipProbe = TooltipProbe

local function say(text) print("|cff88ccffgrt debug|r " .. text) end

local function probeStore()
    if type(GamepadReticleOnTargetDebugDB) ~= "table" then GamepadReticleOnTargetDebugDB = {} end
    return GamepadReticleOnTargetDebugDB
end

local function readSettings()
    local values = {}
    for _, name in ipairs(TooltipProbe.SETTINGS) do values[name] = tostring(C_CVar.GetCVar(name)) end
    return values
end

local function putSettingsBack(values)
    if InCombatLockdown() then return false end
    for name, value in pairs(values) do pcall(C_CVar.SetCVar, name, value) end
    return true
end

local probe   -- the check in progress, or nil
local eventFrame = CreateFrame("Frame")
local timerText

-- What the game's tooltip shows now, and the soft target it should show.
local function sample(event, unitToken)
    if not probe or #probe.samples >= TooltipProbe.SAMPLES_KEPT then return end
    local tooltipUnitName = nil
    if GameTooltip:IsShown() and GameTooltip.GetUnit then tooltipUnitName = GameTooltip:GetUnit() end
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner() or nil
    table.insert(probe.samples, {
        at = math.floor((GetTime() - probe.startedAt) * 10) / 10,
        event = event,
        soft = UnitExists(unitToken) and UnitName(unitToken) or nil,
        tooltipShown = GameTooltip:IsShown(),
        tooltipUnit = tooltipUnitName,
        owner = owner and owner.GetName and owner:GetName() or (owner and "unnamed") or nil,
    })
end

local function finish()
    if not probe then return end
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnUpdate", nil)
    if timerText then timerText:Hide() end
    local finished = probe
    probe = nil
    if putSettingsBack(finished.before) then probeStore().tooltipSettingsToRestore = nil end
    local withTooltip = 0
    for _, entry in ipairs(finished.samples) do
        if entry.soft and entry.tooltipUnit == entry.soft then withTooltip = withTooltip + 1 end
    end
    local summary = string.format("%d soft-target changes, %d showed that unit's tooltip. Settings read %s after setting them on.",
        #finished.samples, withTooltip, finished.afterSet.SoftTargetTooltipEnemy)
    finished.summary = summary
    say("tooltip check done. " .. summary)
    ReticleOnTarget.Popup.Show({ text = "Tooltip check done.\n" .. summary .. "\n\nReload to save the results.",
        buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

function TooltipProbe.Start()
    if probe then return say("the tooltip check is already running") end
    if InCombatLockdown() then return say("out of combat only") end
    local before = readSettings()
    probeStore().tooltipSettingsToRestore = before   -- a reload mid-check: put back at the next login
    for _, name in ipairs(TooltipProbe.SETTINGS) do pcall(C_CVar.SetCVar, name, "1") end
    probe = { startedAt = GetTime(), date = date("%Y-%m-%d %H:%M:%S"), before = before, afterSet = readSettings(),
        controllerUI = ReticleOnTarget.IsControllerUIOn(), samples = {} }
    probeStore().tooltipProbe = probe
    for event in pairs(TooltipProbe.EVENTS) do eventFrame:RegisterEvent(event) end
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    if not timerText then
        timerText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        timerText:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -60)
    end
    timerText:Show()
    local pending = {}   -- { event, unitToken, due } sampled a moment after the change
    eventFrame.pending = pending
    eventFrame:SetScript("OnUpdate", function()
        local now = GetTime()
        for i = #pending, 1, -1 do
            if now >= pending[i].due then
                sample(pending[i].event, pending[i].unitToken)
                table.remove(pending, i)
            end
        end
        timerText:SetText(string.format("tooltip check: %d s left", math.max(0, math.ceil(probe.startedAt + TooltipProbe.SECONDS - now))))
        if now >= probe.startedAt + TooltipProbe.SECONDS then finish() end
    end)
    say(string.format("tooltip check for %d s: turn toward enemies, NPCs and objects so the soft target changes.",
        TooltipProbe.SECONDS))
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local values = probeStore().tooltipSettingsToRestore
        if values and putSettingsBack(values) then
            probeStore().tooltipSettingsToRestore = nil
            say("a tooltip check was cut short: your tooltip settings are back")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if probe then probe.stoppedBy = "combat" end
        -- Setting changes wait for the fight's end; the reload box opens then too.
        local waitFrame = CreateFrame("Frame")
        waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        waitFrame:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); finish() end)
    elseif probe then
        table.insert(eventFrame.pending, { event = event, unitToken = TooltipProbe.EVENTS[event],
            due = GetTime() + TooltipProbe.SAMPLE_DELAY })
    end
end)
