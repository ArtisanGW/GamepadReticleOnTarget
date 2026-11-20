-- A hint on the settings page: Gamepad Reticle Customizer, a separate addon,
-- customizes the reticle (shape, size, color, border, an icon on
-- your target). Shown only when it isn't installed; its button opens the popup
-- (Popup.lua) with the download link selected to copy (the game can't open a web
-- page) and a Reload for once it's installed. The other
-- addon is named here only as text: nothing calls it or depends on it.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local RelatedAddon = {
    NAME = "GamepadReticleCustomizer",
    TITLE = "Gamepad Reticle Customizer",
    -- CurseForge's permanent short address for its project (redirects to its page).
    LINK = "https://www.curseforge.com/projects/1818557",
}
ReticleOnTarget.RelatedAddon = RelatedAddon

-- Whether it's turned off for this character in the AddOns list: first whether
-- it can load (GetAddOnInfo's reason "DISABLED"), then its switch for this
-- character (GetAddOnEnableState, 0 = off; the character is its GUID, as the
-- game's AddOns list uses).
function RelatedAddon.TurnedOff()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" then return false end
    if type(addOns.GetAddOnInfo) == "function" then
        local succeeded, _, _, _, _, reason = pcall(addOns.GetAddOnInfo, RelatedAddon.NAME)
        if succeeded and reason == "DISABLED" then return true end
    end
    if type(addOns.GetAddOnEnableState) == "function" then
        local character = type(UnitGUID) == "function" and UnitGUID("player") or nil
        local succeeded, state = pcall(addOns.GetAddOnEnableState, RelatedAddon.NAME, character)
        if succeeded and tonumber(state) == 0 then return true end
    end
    return false
end

-- Whether it's installed. Debug.lua (never in the release) sets
-- RelatedAddon.countTurnedOffAsMissing, so turning it off in the AddOns list
-- shows what players without it see: the button and its popup.
function RelatedAddon.Installed()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, RelatedAddon.NAME)
    if not (succeeded and exists == true) then return false end
    return not (RelatedAddon.countTurnedOffAsMissing and RelatedAddon.TurnedOff())
end

-- Its link to copy, and a Reload for once it's installed (Popup.lua).
function RelatedAddon.ShowLink()
    ReticleOnTarget.Popup.Show({
        text = "To get " .. RelatedAddon.TITLE .. ":\n"
            .. "• Copy the link (Ctrl+C)\n"
            .. "• Install it\n"
            .. "• Reload",
        copyText = RelatedAddon.LINK,
        buttons = { { text = "Reload", reload = true }, { text = "Close" } },
    })
end

-- The settings page's button (GamepadReticleOnTarget.lua calls this while building it).
function ReticleOnTarget.AddRelatedAddonButton(layout)
    if RelatedAddon.Installed() then return end
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    layout:AddInitializer(CreateSettingsButtonInitializer(RelatedAddon.TITLE, "Get " .. RelatedAddon.TITLE,
        function() RelatedAddon.ShowLink() end,
        "Customizes the reticle:\n\n"
        .. "• Its shape, size, color and border\n"
        .. "• An icon on your target: its class, a raid marker\n\n"
        .. "A separate addon; this one works without it.", true))
end
