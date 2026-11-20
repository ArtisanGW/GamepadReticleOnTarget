-- Hides parts of the nameplates of friendly NPCs, neutral NPCs and friendly players' minions
-- (their pets, guardians and totems, yours too, as the game's Nameplates options
-- call them): their health bar, their name, or both, each with its own setting,
-- all off by default. The reticle needs a nameplate to sit under, so they stay
-- on; only the chosen parts are made see-through (their alpha), and the game's
-- nameplate keeps working underneath. The alpha each part had is kept and put
-- back when its setting is turned off or the nameplate goes to another unit.
-- Nothing here is protected, so it works in combat too.
--
-- Nameplates the game locks for addons (friendly ones in dungeons and raids)
-- aren't returned to addons at all: those are left as they are.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local NameplateHiding = {
    EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FACTION" },
    FRIENDLY_REACTION = 5,   -- UnitReaction: 5 and up is friendly
    NEUTRAL_REACTION = 4,
    -- The setting that hides each part, by kind of unit.
    SETTINGS = {
        npc = { healthBar = "hideNpcHealthBars", name = "hideNpcNames" },
        neutral = { healthBar = "hideNeutralHealthBars", name = "hideNeutralNames" },
        minion = { healthBar = "hideMinionHealthBars", name = "hideMinionNames" },
    },
}
ReticleOnTarget.NameplateHiding = NameplateHiding

local originalAlphas = setmetatable({}, { __mode = "k" })   -- part -> its alpha before we hid it

-- Secret values (hidden from addons in some situations) count as unknown.
local function readable(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local function reactionTo(unit)
    if type(UnitReaction) ~= "function" then return nil end
    return tonumber(readable(UnitReaction(unit, "player")))
end

-- What kind of unit a nameplate shows: "npc" (a friendly NPC), "neutral" (a neutral
-- NPC: yellow, critters too), "minion" (a friendly player's pet, guardian or
-- totem) or nil (anything else: players, enemies, others' minions).
function NameplateHiding.Kind(unit)
    if type(UnitExists) ~= "function" or readable(UnitExists(unit)) ~= true then return nil end
    if type(UnitIsPlayer) == "function" and readable(UnitIsPlayer(unit)) == true then return nil end
    local reaction = reactionTo(unit)
    if not reaction then return nil end
    local controlledByPlayer = type(UnitPlayerControlled) == "function" and readable(UnitPlayerControlled(unit)) == true
    if reaction >= NameplateHiding.FRIENDLY_REACTION then return controlledByPlayer and "minion" or "npc" end
    if reaction == NameplateHiding.NEUTRAL_REACTION and not controlledByPlayer then return "neutral" end
    return nil
end

-- Whether a part ("healthBar" or "name") of a unit's nameplate should be hidden.
function NameplateHiding.ShouldHide(unit, partName)
    local settings = ReticleOnTarget.GetSettings()
    if not settings.enabled then return false end   -- "Reticle on your target" off: the game's nameplates as they are
    local settingKeys = NameplateHiding.SETTINGS[NameplateHiding.Kind(unit)]
    return settingKeys ~= nil and settings[settingKeys[partName]] == true
end

-- Whether a unit's name gets the look of the game's world names: a friendly or
-- neutral NPC, with "World-style names" ticked for its group.
NameplateHiding.WORLD_NAME_SETTINGS = { npc = "npcWorldNames", neutral = "neutralWorldNames" }
function NameplateHiding.WorldNames(unit)
    local settings = ReticleOnTarget.GetSettings()
    local settingKey = NameplateHiding.WORLD_NAME_SETTINGS[NameplateHiding.Kind(unit)]
    return settings.enabled == true and settingKey ~= nil and settings[settingKey] == true
end

local function unitFrameOf(nameplate)
    local unitFrame = type(nameplate) == "table" and nameplate.UnitFrame
    if type(unitFrame) ~= "table" then return nil end
    if type(unitFrame.IsForbidden) == "function" and unitFrame:IsForbidden() then return nil end
    return unitFrame
end

-- The parts that can be hidden, each a list of regions: the health bar with its
-- border (the UnitFrame's HealthBarsContainer, else the bar) and the level badge
-- beside the name; the name, and our title under it (NameplateNames.lua).
local function partsOf(unitFrame)
    local parts = {
        healthBar = { unitFrame.HealthBarsContainer or unitFrame.healthBar, unitFrame.PlayerLevelDiffFrame },
        name = { unitFrame.name, ReticleOnTarget.NameplateNames.Title(unitFrame) },
    }
    for _, regions in pairs(parts) do
        for i = #regions, 1, -1 do
            if type(regions[i]) ~= "table" or type(regions[i].SetAlpha) ~= "function" then table.remove(regions, i) end
        end
    end
    return parts
end

local function hide(part)
    if originalAlphas[part] == nil then originalAlphas[part] = part:GetAlpha() end
    part:SetAlpha(0)
end

local function show(part)
    local alpha = originalAlphas[part]
    if alpha == nil then return end
    originalAlphas[part] = nil
    part:SetAlpha(alpha)
end

-- Each part of a unit's nameplate hidden or shown, as its setting says (unit nil:
-- every part shown, the nameplate going back to the game). A friendly or neutral
-- NPC can also get its name as the game draws it without nameplates: its color,
-- its title (NameplateNames.lua), when "World-style names" is ticked for it.
local function apply(unitFrame, unit)
    ReticleOnTarget.NameplateNames.Style(unitFrame, unit, unit ~= nil and NameplateHiding.WorldNames(unit))
    for partName, regions in pairs(partsOf(unitFrame)) do
        local hidden = unit and NameplateHiding.ShouldHide(unit, partName)
        for _, region in ipairs(regions) do
            if hidden then hide(region) else show(region) end
        end
    end
end

function NameplateHiding.Update(unit)
    local namePlates = _G.C_NamePlate
    if type(namePlates) ~= "table" or type(namePlates.GetNamePlateForUnit) ~= "function" then return end
    local succeeded, nameplate = pcall(namePlates.GetNamePlateForUnit, unit)
    local unitFrame = succeeded and unitFrameOf(nameplate)
    if unitFrame then apply(unitFrame, unit) end
end

-- Every nameplate on screen again (a setting changed).
function NameplateHiding.Refresh()
    local namePlates = _G.C_NamePlate
    if type(namePlates) ~= "table" or type(namePlates.GetNamePlates) ~= "function" then return end
    local succeeded, nameplates = pcall(namePlates.GetNamePlates)
    if not succeeded or type(nameplates) ~= "table" then return end
    for _, nameplate in ipairs(nameplates) do
        local unitFrame = unitFrameOf(nameplate)
        local unit = unitFrame and (nameplate.namePlateUnitToken or nameplate.unitToken or unitFrame.unit)
        if unit then apply(unitFrame, unit) end
    end
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs(NameplateHiding.EVENTS) do eventFrame:RegisterEvent(event) end
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- The nameplate goes back to the game's pool: give it its own alpha back.
        local namePlates = _G.C_NamePlate
        local succeeded, nameplate = pcall(namePlates.GetNamePlateForUnit, unit)
        local unitFrame = succeeded and unitFrameOf(nameplate)
        if unitFrame then apply(unitFrame, nil) end
    elseif type(unit) == "string" and unit:find("^nameplate") then
        NameplateHiding.Update(unit)   -- a nameplate came, or its unit changed sides
    end
end)
