-- Hints on the settings page for our other controller addons: a "Get" button
-- for each one that isn't installed. Its popup (Popup.lua) shows the download
-- link selected to copy (the game can't open a web page) and a Reload for once
-- it's installed. The other addons are named here only as text: nothing calls
-- them or depends on them.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local RelatedAddons = {
    -- Each: its folder name, its title, its settings row's label, its CurseForge
    -- page (the project's permanent short address, which redirects to it) and
    -- the row's tooltip.
    SIBLINGS = {
        {
            NAME = "GamepadCameraOffset",
            TITLE = "Gamepad Camera Offset",
            LABEL = "Camera over shoulder",   -- the settings row: what it does
            LINK = "https://www.curseforge.com/projects/1818297",
            TOOLTIP = "Moves the camera over your shoulder, with a controller too.\n\n"
            .. "A separate addon; this one works without it.",
        },
        {
            NAME = "GamepadReticleCustomizer",
            TITLE = "Gamepad Reticle Customizer",
            LABEL = "Customize the reticle",   -- the settings row: what it does
            LINK = "https://www.curseforge.com/projects/1818557",
            TOOLTIP = "Customizes the reticle:\n\n"
            .. "• Its shape, size, color and border\n"
            .. "• An icon on your target: its class, a raid marker\n\n"
            .. "A separate addon; this one works without it.",
        },
        {
            NAME = "GamepadFastMap",
            TITLE = "Gamepad Fast Map",
            LABEL = "Map without its hitch",   -- the settings row: what it does
            LINK = "https://www.curseforge.com/projects/1827949",
            TOOLTIP = "Opens and closes the world map without its hitch on the controller UI.\n\n"
            .. "A separate addon; this one works without it.",
        },
    },
}
ReticleOnTarget.RelatedAddons = RelatedAddons

-- Whether a sibling is turned off for this character in the AddOns list: first
-- whether it can load (GetAddOnInfo's reason "DISABLED"), then its switch for
-- this character (GetAddOnEnableState, 0 = off; the character is its GUID, as
-- the game's AddOns list uses).
function RelatedAddons.TurnedOff(sibling)
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" then return false end
    if type(addOns.GetAddOnInfo) == "function" then
        local succeeded, _, _, _, _, reason = pcall(addOns.GetAddOnInfo, sibling.NAME)
        if succeeded and reason == "DISABLED" then return true end
    end
    if type(addOns.GetAddOnEnableState) == "function" then
        local character = type(UnitGUID) == "function" and UnitGUID("player") or nil
        local succeeded, state = pcall(addOns.GetAddOnEnableState, sibling.NAME, character)
        if succeeded and tonumber(state) == 0 then return true end
    end
    return false
end

-- Whether a sibling is installed. With countTurnedOffAsMissing set (development
-- builds), one turned off in the AddOns list counts as missing too.
function RelatedAddons.Installed(sibling)
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, sibling.NAME)
    if not (succeeded and exists == true) then return false end
    return not (RelatedAddons.countTurnedOffAsMissing and RelatedAddons.TurnedOff(sibling))
end

-- The siblings that aren't installed, in order.
function RelatedAddons.Missing()
    local missing = {}
    for _, sibling in ipairs(RelatedAddons.SIBLINGS) do
        if not RelatedAddons.Installed(sibling) then missing[#missing + 1] = sibling end
    end
    return missing
end

-- Its link to copy, and a Reload for once it's installed (Popup.lua).
-- intro (optional): a first paragraph.
function RelatedAddons.ShowLink(sibling, intro)
    ReticleOnTarget.Popup.Show({
        text = (intro or "") .. "To get " .. sibling.TITLE .. ":\n"
            .. "• Copy the link (Ctrl+C)\n"
            .. "• Install it\n"
            .. "• Reload",
        copyText = sibling.LINK,
        buttons = { { text = "Reload", reload = true }, { text = "Close" } },
    })
end

-- The settings page's buttons (GamepadReticleOnTarget.lua calls this while building it).
function ReticleOnTarget.AddRelatedAddonButtons(layout)
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    for _, sibling in ipairs(RelatedAddons.Missing()) do
        layout:AddInitializer(CreateSettingsButtonInitializer(sibling.LABEL, "Get the addon",
            function() RelatedAddons.ShowLink(sibling) end, sibling.TOOLTIP, true))
    end
end
