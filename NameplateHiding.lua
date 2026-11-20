-- Hides the nameplates that only clutter the screen: friendly NPCs', and the pets
-- of friendly players (yours too), each with its own setting. The reticle needs a
-- nameplate to sit under, so they stay on; only what they show is made
-- see-through (the alpha of the nameplate's UnitFrame), and the game's nameplate
-- keeps working underneath. The alpha each had is kept and put back when its
-- setting is turned off or the nameplate goes to another unit. Nothing here is
-- protected, so it works in combat too.
--
-- Nameplates the game locks for addons (friendly ones in dungeons and raids)
-- aren't returned to addons at all: those are left as they are.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local NameplateHiding = {
    EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FACTION" },
    FRIENDLY_REACTION = 5,   -- UnitReaction: 5 and up is friendly
}
ReticleOnTarget.NameplateHiding = NameplateHiding

local originalAlphas = setmetatable({}, { __mode = "k" })   -- UnitFrame -> its alpha before we hid it

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

-- What kind of unit a nameplate shows, for hiding: "npc" (a friendly NPC), "pet"
-- (a friendly player's pet or guardian) or nil (anything else: players, enemies,
-- neutral NPCs).
function NameplateHiding.Kind(unit)
    if type(UnitExists) ~= "function" or readable(UnitExists(unit)) ~= true then return nil end
    if type(UnitIsPlayer) == "function" and readable(UnitIsPlayer(unit)) == true then return nil end
    if not isFriendly(unit) then return nil end
    local controlledByPlayer = type(UnitPlayerControlled) == "function" and readable(UnitPlayerControlled(unit)) == true
    return controlledByPlayer and "pet" or "npc"
end

function NameplateHiding.ShouldHide(unit)
    local settings = ReticleOnTarget.GetSettings()
    local kind = NameplateHiding.Kind(unit)
    return (kind == "npc" and settings.hideFriendlyNpcs == true) or (kind == "pet" and settings.hidePets == true)
end

local function unitFrameOf(nameplate)
    local unitFrame = type(nameplate) == "table" and nameplate.UnitFrame
    if type(unitFrame) ~= "table" or type(unitFrame.SetAlpha) ~= "function" then return nil end
    if type(unitFrame.IsForbidden) == "function" and unitFrame:IsForbidden() then return nil end
    return unitFrame
end

local function hide(unitFrame)
    if originalAlphas[unitFrame] == nil then originalAlphas[unitFrame] = unitFrame:GetAlpha() end
    unitFrame:SetAlpha(0)
end

local function show(unitFrame)
    local alpha = originalAlphas[unitFrame]
    if alpha == nil then return end
    originalAlphas[unitFrame] = nil
    unitFrame:SetAlpha(alpha)
end

-- Hides or shows one unit's nameplate, as its setting says.
function NameplateHiding.Update(unit)
    local namePlates = _G.C_NamePlate
    if type(namePlates) ~= "table" or type(namePlates.GetNamePlateForUnit) ~= "function" then return end
    local succeeded, nameplate = pcall(namePlates.GetNamePlateForUnit, unit)
    local unitFrame = succeeded and unitFrameOf(nameplate)
    if not unitFrame then return end
    if NameplateHiding.ShouldHide(unit) then hide(unitFrame) else show(unitFrame) end
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
        if unit then
            if NameplateHiding.ShouldHide(unit) then hide(unitFrame) else show(unitFrame) end
        end
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
        if unitFrame then show(unitFrame) end
    elseif type(unit) == "string" and unit:find("^nameplate") then
        NameplateHiding.Update(unit)   -- a nameplate came, or its unit changed sides
    end
end)
