-- GamepadReticleOnTarget: puts the controller UI's reticle (its aiming dot) just
-- below your target's nameplate, so it stays on what you attack. Settings sit in
-- the game's Options > AddOns > Gamepad Reticle On Target, or /gprt.
--
-- Files, one job each:
--   GamepadReticleOnTarget.lua   saved settings, the settings page, events, /gprt
--   Reticle.lua                  where the reticle goes, and when it's placed again
--   Popup.lua                    a popup in the game's style
--   Nameplates.lua               asks to turn on the nameplates the reticle sits under
--   NameplateNames.lua           an NPC's name drawn as the game's world names: color, title
--   NameplateHiding.lua          hides health bars or names on friendly and neutral NPCs' and minions' nameplates
--   RelatedAddons.lua             hints for our other controller addons
--   ReticleTooltip.lua            the unit tooltip for the unit the reticle is on
--   Debug.lua                     development builds only: /gprt debug
--   DebugTooltip.lua              development builds only: /gprt debug tooltip
local ADDON_NAME = ...

local ReticleOnTarget = {
    -- enabled: the reticle goes on your target.
    -- offset:  its vertical offset from just below the nameplate, -200 (down) to 200
    --          (up) screen pixels. Pixels, not a percentage: a nameplate keeps its
    --          size on screen at any distance, so a pixel offset puts the dot at the
    --          same place on it.
    -- hideNpcHealthBars, hideNpcNames, hideMinionHealthBars, hideMinionNames: that part
    --          of friendly NPCs', neutral NPCs' and minions' nameplates hidden
    --          (NameplateHiding.lua); hideNeutralHealthBars, hideNeutralNames too.
    -- npcWorldNames, neutralWorldNames: their names drawn as the game's world names,
    --          colored and with their title (NameplateNames.lua), not the nameplate's white.
    -- hideNpcLevels, hideNeutralLevels, hideMinionLevels: the level beside the name hidden.
    -- npcNameSize, neutralNameSize: world-style names' size, 50 to 200% of the game's
    --          (100, the game's own, by default).
    --          Off by default: the addon never changes how the game looks unless asked.
    DEFAULTS = { enabled = true, offset = 0, hideNpcHealthBars = false, hideNpcNames = false,
        hideNeutralHealthBars = false, hideNeutralNames = false, npcWorldNames = false, neutralWorldNames = false,
        hideNpcLevels = false, hideNeutralLevels = false, hideMinionLevels = false, npcNameSize = 100, neutralNameSize = 100,
        hideMinionHealthBars = false, hideMinionNames = false, reticleTooltip = false },
    OFFSET_MIN = -200, OFFSET_MAX = 200, OFFSET_STEP = 5,
    NAME_SIZE_MIN = 50, NAME_SIZE_MAX = 200, NAME_SIZE_STEP = 5,
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
    -- Saved keys this addon doesn't use: dropped. Its own records are kept
    -- (Nameplates.lua): nameplatesAsked, that the nameplate question was asked,
    -- and nameplatesBefore, the nameplate settings it turned on and their values before.
    for key in pairs(settings) do
        if ReticleOnTarget.DEFAULTS[key] == nil and key ~= "nameplatesAsked" and key ~= "nameplatesBefore" then
            settings[key] = nil
        end
    end
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
            return Settings.CreateCheckbox(category, setting, tooltip)
        end
        return Settings.CreateSlider(category, setting, options, tooltip)
    end

    -- A heading, as the game's Nameplates options have them.
    local function addHeading(name)
        if type(CreateSettingsListSectionHeaderInitializer) ~= "function" then return end
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
    end

    addSetting("enabled", Settings.VarType.Boolean, "Reticle on your target",
        "With the controller UI on, puts its reticle (and its auto-attack timer) on your target's "
        .. "nameplate, where the game shows its interaction icon, so it stays on what you attack as you both move.\n\n"
        .. "• Your target first, else the controller's soft target\n"
        .. "• No target, or nameplates off: where the game aims\n\n"
        .. "What the controller targets is still decided by the game. Turned off, the nameplate settings "
        .. "it turned on go back as they were, and any hidden health bars or names show again.",
        nil, function()
            ReticleOnTarget.Reticle.Place()
            ReticleOnTarget.NameplateHiding.Refresh()
            if ReticleOnTarget.GetSettings().enabled then ReticleOnTarget.Nameplates.Ask()
            else ReticleOnTarget.Nameplates.PutBack() end
        end)
    addSetting("offset", Settings.VarType.Number, "Vertical offset",
        "Moves the reticle up or down from where the game shows its interaction icon on your target, in screen pixels.\n\n"
        .. "• Default: on that icon, just above the nameplate\n"
        .. "• No target: where the game aims",
        sliderOptions(ReticleOnTarget.OFFSET_MIN, ReticleOnTarget.OFFSET_MAX, ReticleOnTarget.OFFSET_STEP,
            ReticleOnTarget.OffsetLabel))
    addSetting("reticleTooltip", Settings.VarType.Boolean, "Tooltip on the reticle",
        "Keeps the tooltip of the unit the reticle is on, as the mouse shows it on a unit.\n\n"
        .. "• Your target first, else the controller's soft target: an enemy, else a friend\n"
        .. "• A tooltip open for something else stays; this one comes back after it\n\n"
        .. "With the controller UI on, the game shows its own only for NPCs you can talk to and objects.",
        nil, function() ReticleOnTarget.ReticleTooltip.Refresh() end)
    local function refreshHiding() ReticleOnTarget.NameplateHiding.Refresh() end
    -- Indented under a heading, as the game indents its Minions under Friendly
    -- Player Nameplates.
    -- more (optional): a sentence added to the tooltip's details.
    local function addHideSetting(key, label, what, whose, more)
        local initializer = addSetting(key, Settings.VarType.Boolean, label, "Hides " .. what .. " on the nameplates of "
            .. whose .. ".\n\n" .. (more and (more .. " ") or "")
            .. "The reticle still goes on them. Turned off, it shows again.", nil, refreshHiding)
        if type(initializer) == "table" and type(initializer.Indent) == "function" then initializer:Indent() end
    end
    addHeading("Friendly NPC Nameplates")
    -- The name's look: the game's nameplate one (white) or its world names' one.
    local function addWorldNamesSetting(key, whose, color)
        local initializer = addSetting(key, Settings.VarType.Boolean, "World-style names",
            "Shows " .. whose .. "' names as the game does without nameplates: " .. color .. ", with their title "
            .. "(\"<Stable Master>\").\n\nTurned off, the nameplate's own white name.", nil, refreshHiding)
        if type(initializer) == "table" and type(initializer.Indent) == "function" then initializer:Indent() end
    end
    local function addNameSizeSetting(key, whose)
        local initializer = addSetting(key, Settings.VarType.Number, "Name size",
            "The size of " .. whose .. "' world-style names, from the game's own nameplate name size.\n\n"
            .. "The game's world names shrink with distance; these keep one size, like all nameplate text.",
            sliderOptions(ReticleOnTarget.NAME_SIZE_MIN, ReticleOnTarget.NAME_SIZE_MAX, ReticleOnTarget.NAME_SIZE_STEP,
                function(value)
                    local percent = math.floor((tonumber(value) or 100) + 0.5)
                    return percent == 100 and "Default" or (percent .. "%")
                end), refreshHiding)
        if type(initializer) == "table" and type(initializer.Indent) == "function" then initializer:Indent() end
    end
    addHideSetting("hideNpcHealthBars", "Hide health bars", "the health bar", "friendly NPCs")
    addHideSetting("hideNpcNames", "Hide names", "the name", "friendly NPCs")
    addHideSetting("hideNpcLevels", "Hide level", "the level", "friendly NPCs")
    addWorldNamesSetting("npcWorldNames", "friendly NPCs", "green")
    addNameSizeSetting("npcNameSize", "friendly NPCs")
    addHeading("Neutral NPC Nameplates")
    addHideSetting("hideNeutralHealthBars", "Hide health bars", "the health bar", "neutral NPCs, critters too")
    addHideSetting("hideNeutralNames", "Hide names", "the name", "neutral NPCs, critters too")
    addHideSetting("hideNeutralLevels", "Hide level", "the level", "neutral NPCs, critters too")
    addWorldNamesSetting("neutralWorldNames", "neutral NPCs", "yellow")
    addNameSizeSetting("neutralNameSize", "neutral NPCs")
    addHeading("Friendly Player Minions")
    addHideSetting("hideMinionHealthBars", "Hide health bars", "the health bar", "friendly players' minions (pets, guardians, totems, yours too)")
    addHideSetting("hideMinionNames", "Hide names", "the name", "friendly players' minions (pets, guardians, totems, yours too)")
    addHideSetting("hideMinionLevels", "Hide level", "the level", "friendly players' minions (pets, guardians, totems, yours too)")

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

-- /gprt (or /gamepadreticleontarget) opens the settings.
SLASH_GAMEPADRETICLEONTARGET1 = "/gprt"
SLASH_GAMEPADRETICLEONTARGET2 = "/gamepadreticleontarget"
SlashCmdList.GAMEPADRETICLEONTARGET = function(message)
    local command, arguments = tostring(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" and ReticleOnTarget.Debug then return ReticleOnTarget.Debug.Command(arguments) end
    ReticleOnTarget.Open()
end
