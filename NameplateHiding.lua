-- Hides parts of the nameplates of friendly NPCs and of friendly players' pets
-- (yours too): their health bar, their name, or both, each with its own setting,
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
    -- The setting that hides each part, by kind of unit.
    SETTINGS = {
        npc = { healthBar = "hideNpcHealthBars", name = "hideNpcNames" },
        pet = { healthBar = "hidePetHealthBars", name = "hidePetNames" },
    },
}
ReticleOnTarget.NameplateHiding = NameplateHiding

local originalAlphas = setmetatable({}, { __mode = "k" })   -- part -> its alpha before we hid it

-- Secret values (hidden from addons in some situations) count as unknown.
local function readable(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local function isFriendly(unit)
    if type(UnitReaction) ~= "function" then return false end
    local reaction = tonumber(readable(UnitReaction(unit, "player")))
    return reaction ~= nil and reaction >= NameplateHiding.FRIENDLY_REACTION
end

-- What kind of unit a nameplate shows: "npc" (a friendly NPC), "pet" (a friendly
-- player's pet or guardian) or nil (anything else: players, enemies, neutral NPCs).
function NameplateHiding.Kind(unit)
    if type(UnitExists) ~= "function" or readable(UnitExists(unit)) ~= true then return nil end
    if type(UnitIsPlayer) == "function" and readable(UnitIsPlayer(unit)) == true then return nil end
    if not isFriendly(unit) then return nil end
    local controlledByPlayer = type(UnitPlayerControlled) == "function" and readable(UnitPlayerControlled(unit)) == true
    return controlledByPlayer and "pet" or "npc"
end

-- Whether a part ("healthBar" or "name") of a unit's nameplate should be hidden.
function NameplateHiding.ShouldHide(unit, partName)
    local settingKeys = NameplateHiding.SETTINGS[NameplateHiding.Kind(unit)]
    return settingKeys ~= nil and ReticleOnTarget.GetSettings()[settingKeys[partName]] == true
end

local function unitFrameOf(nameplate)
    local unitFrame = type(nameplate) == "table" and nameplate.UnitFrame
    if type(unitFrame) ~= "table" then return nil end
    if type(unitFrame.IsForbidden) == "function" and unitFrame:IsForbidden() then return nil end
    return unitFrame
end

-- The parts that can be hidden: the health bar with its border (the UnitFrame's
-- HealthBarsContainer, else the bar) and the name.
local function partsOf(unitFrame)
    local parts = { healthBar = unitFrame.HealthBarsContainer or unitFrame.healthBar, name = unitFrame.name }
    for partName, part in pairs(parts) do
        if type(part) ~= "table" or type(part.SetAlpha) ~= "function" then parts[partName] = nil end
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
-- every part shown, the nameplate going back to the game).
local function apply(unitFrame, unit)
    for partName, part in pairs(partsOf(unitFrame)) do
        if unit and NameplateHiding.ShouldHide(unit, partName) then hide(part) else show(part) end
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
