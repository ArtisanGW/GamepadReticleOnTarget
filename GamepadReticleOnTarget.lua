-- GamepadReticleOnTarget: puts the controller UI's reticle (its aiming dot) just
-- below your target's nameplate, so it stays on what you attack. Settings sit in
-- the game's Options > AddOns > Gamepad Reticle On Target, or /grt.
--
-- Files, one job each:
--   GamepadReticleOnTarget.lua   saved settings, the settings page, events, /grt
--   Reticle.lua                  where the reticle goes, and when it's placed again
--   Popup.lua                    a popup in the game's style
--   Nameplates.lua               asks to turn on the nameplates the reticle sits under
--   NameplateHiding.lua          makes friendly NPCs' and pets' nameplates see-through
--   RelatedAddons.lua             hints for our other controller addons
--   Debug.lua                    /grt debug, the in-game test suite (not in the release)
local ADDON_NAME = ...

local ReticleOnTarget = {
    -- enabled: the reticle goes on your target.
    -- offset:  its vertical offset from just below the nameplate, -200 (down) to 200
    --          (up) screen pixels. Pixels, not a percentage: a nameplate keeps its
    --          size on screen at any distance, so a pixel offset puts the dot at the
    --          same place on it.
    -- hideFriendlyNpcs, hidePets: their nameplates see-through (NameplateHiding.lua).
    DEFAULTS = { enabled = true, offset = 0, hideFriendlyNpcs = true, hidePets = true },
    OFFSET_MIN = -200, OFFSET_MAX = 200, OFFSET_STEP = 5,
}
_G.GamepadReticleOnTarget = ReticleOnTarget

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end
ReticleOnTarget.Clamp = clamp

function ReticleOnTarget.GetSettings()
    if type(GamepadReticleOnTargetDB) ~= "table" then GamepadReticleOnTargetDB = {} end
    local settings = GamepadReticleOnTargetDB
    for key, defaultValue in pairs(ReticleOnTarget.DEFAULTS) do
        if settings[key] == nil then settings[key] = defaultValue end
    end
    return settings
end

function ReticleOnTarget.IsControllerUIOn()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function"
        and InputUtil.IsGamepadUIEnabled() == true
end

-- Settings: Options > AddOns > Gamepad Reticle On Target

-- The offset slider's label: "Default", or pixels with a direction ("20 px down").
function ReticleOnTarget.OffsetLabel(value)
    local number = tonumber(value) or 0
    local amount = math.floor(math.abs(number) + 0.5)
    if amount == 0 then return "Default" end
    return string.format("%d px %s", amount, number < 0 and "down" or "up")
end

local function sliderOptions(minimum, maximum, step, formatLabel)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    local rightLabel = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        and MinimalSliderWithSteppersMixin.Label.Right
    if rightLabel and options.SetLabelFormatter then options:SetLabelFormatter(rightLabel, formatLabel) end
    return options
end

function ReticleOnTarget.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local settings = ReticleOnTarget.GetSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Gamepad Reticle On Target")
    ReticleOnTarget.category = category

    -- onChange (optional): what to run when it changes; placing the reticle again by default.
    local function addSetting(key, valueType, label, tooltip, options, onChange)
        local variableName = "GamepadReticleOnTarget_" .. key
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, settings, valueType, label,
            ReticleOnTarget.DEFAULTS[key])
        Settings.SetOnValueChangedCallback(variableName, onChange or function() ReticleOnTarget.Reticle.Place() end)
        if valueType == Settings.VarType.Boolean then
            Settings.CreateCheckbox(category, setting, tooltip)
        else
            Settings.CreateSlider(category, setting, options, tooltip)
        end
    end

    addSetting("enabled", Settings.VarType.Boolean, "Reticle on your target",
        "With the controller UI on, puts its reticle (and its auto-attack timer) just below "
        .. "your target's nameplate, so it stays on what you attack as you both move.\n\n"
        .. "• Your target first, else the controller's soft target\n"
        .. "• No target, or nameplates off: where the game aims\n\n"
        .. "What the controller targets is still decided by the game.")
    addSetting("offset", Settings.VarType.Number, "Vertical offset",
        "Moves the reticle up or down from just below your target's nameplate, in screen pixels.\n\n"
        .. "• Default: just below the nameplate\n"
        .. "• No target: where the game aims",
        sliderOptions(ReticleOnTarget.OFFSET_MIN, ReticleOnTarget.OFFSET_MAX, ReticleOnTarget.OFFSET_STEP,
            ReticleOnTarget.OffsetLabel))
    local function refreshHiding() ReticleOnTarget.NameplateHiding.Refresh() end
    addSetting("hideFriendlyNpcs", Settings.VarType.Boolean, "Hide friendly NPCs",
        "Makes friendly NPCs' nameplates see-through. The reticle still goes on them.\n\n"
        .. "Turned off, they show again.", nil, refreshHiding)
    addSetting("hidePets", Settings.VarType.Boolean, "Hide friendly pets",
        "Makes the nameplates of friendly players' pets see-through, yours too. "
        .. "The reticle still goes on them.\n\n"
        .. "Turned off, they show again.", nil, refreshHiding)

    if ReticleOnTarget.AddNameplatesButton then ReticleOnTarget.AddNameplatesButton(layout) end   -- Nameplates.lua
    if ReticleOnTarget.AddRelatedAddonButtons then ReticleOnTarget.AddRelatedAddonButtons(layout) end   -- RelatedAddons.lua
    Settings.RegisterAddOnCategory(category)
end

function ReticleOnTarget.Open()
    if ReticleOnTarget.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ReticleOnTarget.category:GetID())
    end
end

-- Events

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        ReticleOnTarget.GetSettings()
        pcall(ReticleOnTarget.RegisterSettings)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ReticleOnTarget.Reticle.Watch()
    end
end)

-- /grt (or /gamepadreticleontarget) opens the settings; /grt debug ... goes to the debug suite (Debug.lua).
SLASH_GAMEPADRETICLEONTARGET1 = "/grt"
SLASH_GAMEPADRETICLEONTARGET2 = "/gamepadreticleontarget"
SlashCmdList.GAMEPADRETICLEONTARGET = function(message)
    local command, arguments = tostring(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" and ReticleOnTarget.Debug then return ReticleOnTarget.Debug.Command(arguments) end
    ReticleOnTarget.Open()
end
