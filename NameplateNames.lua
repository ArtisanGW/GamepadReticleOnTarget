-- An NPC's name on its nameplate, drawn as the game draws names without
-- nameplates: in its own color (green for friendly, yellow for neutral, the
-- game's UnitSelectionColor, which the game's nameplates can use too) and with
-- its title under it ("<Stable Master>"). Used when "World-style names" is
-- ticked for its group (NameplateHiding.lua); otherwise the game's own look.
--
-- The color is set again after each of the game's own name updates (a post-hook
-- on CompactUnitFrame_UpdateName), and the name's own color is put back when the
-- look ends. The title is our own text under the name, copied from the name's
-- font; the game's name is untouched otherwise.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local NameplateNames = {}
ReticleOnTarget.NameplateNames = NameplateNames

local styled = setmetatable({}, { __mode = "k" })        -- UnitFrame -> true while it has the look
local nameColors = setmetatable({}, { __mode = "k" })    -- name -> { r, g, b } before we colored it
local titles = setmetatable({}, { __mode = "k" })        -- UnitFrame -> our title text

-- Secret values (hidden from addons in some situations) count as unknown.
local function readable(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

-- The NPC's title, the line under its name in its tooltip ("Stable Master"), or
-- nil. Without a title that line is its level, which has a number or the word
-- for level in it, in any language.
function NameplateNames.TitleText(unit)
    local tooltipInfo = _G.C_TooltipInfo
    if type(tooltipInfo) ~= "table" or type(tooltipInfo.GetUnit) ~= "function" then return nil end
    local succeeded, data = pcall(tooltipInfo.GetUnit, unit)
    local line = succeeded and type(data) == "table" and type(data.lines) == "table" and data.lines[2]
    local text = type(line) == "table" and readable(line.leftText)
    if type(text) ~= "string" or text == "" or text:find("%d") then return nil end
    if type(LEVEL) == "string" and text:find(LEVEL, 1, true) then return nil end
    return text
end

-- The NPC's color: the game's own for its names.
local function colorOf(unit)
    if type(UnitSelectionColor) ~= "function" then return nil end
    local red, green, blue = UnitSelectionColor(unit)
    red, green, blue = tonumber(readable(red)), tonumber(readable(green)), tonumber(readable(blue))
    if not (red and green and blue) then return nil end
    return red, green, blue
end

local function colorName(unitFrame, unit)
    local name = unitFrame.name
    local red, green, blue = colorOf(unit)
    if not red then return nil end
    if nameColors[name] == nil then nameColors[name] = { name:GetVertexColor() } end
    name:SetVertexColor(red, green, blue)
    return red, green, blue
end

local function titleOf(unitFrame)
    if not titles[unitFrame] then
        local title = unitFrame:CreateFontString(nil, "OVERLAY")
        title:SetPoint("TOP", unitFrame.name, "BOTTOM", 0, -1)
        titles[unitFrame] = title
    end
    return titles[unitFrame]
end

-- Gives a nameplate's name the world-name look, or takes it away (on false).
function NameplateNames.Style(unitFrame, unit, on)
    local name = unitFrame.name
    if type(name) ~= "table" or type(name.SetVertexColor) ~= "function" then return end
    if not on then
        styled[unitFrame] = nil
        local color = nameColors[name]
        if color then
            nameColors[name] = nil
            name:SetVertexColor(color[1], color[2], color[3])
        end
        if titles[unitFrame] then titles[unitFrame]:Hide() end
        return
    end
    styled[unitFrame] = true
    local red, green, blue = colorName(unitFrame, unit)
    local text = NameplateNames.TitleText(unit)
    if not text then
        if titles[unitFrame] then titles[unitFrame]:Hide() end
        return
    end
    local title = titleOf(unitFrame)
    local font, size, flags = name:GetFont()
    if font then title:SetFont(font, size, flags) end
    title:SetText("<" .. text .. ">")
    if red then title:SetVertexColor(red, green, blue) end
    title:Show()
end

-- Our title on a nameplate, while shown (NameplateHiding hides it with the name).
function NameplateNames.Title(unitFrame)
    local title = titles[unitFrame]
    return title and title:IsShown() and title or nil
end

-- The game colors names again on its own updates (mouseover, target changes):
-- ours after it.
if type(hooksecurefunc) == "function" and type(CompactUnitFrame_UpdateName) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if styled[frame] and type(frame.unit) == "string" then colorName(frame, frame.unit) end
    end)
end
