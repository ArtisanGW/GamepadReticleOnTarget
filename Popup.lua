-- A popup that looks like the game's own: its dialog border (DialogBorderTemplate,
-- forever branch Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml:69, the frame
-- of the game's popups), its fonts and buttons. A message, an optional line to copy
-- (a web link: the game can't open one, so it's shown selected for Ctrl+C), and up
-- to three buttons; one can be Reload, a secure /reload button (addon code can't
-- call ReloadUI() on this client), with something to do just before it reloads.
--   ReticleOnTarget.Popup.Show({ text = "...", copyText = "https://...",
--       buttons = { { text = "Reload", reload = true, beforeReload = function() end },
--                   { text = "Close" } } })
-- A button without onClick closes the popup.
--
-- On the controller UI, while it's open, the controller's bottom face button (A)
-- clicks the first button and the right one (B) the last, through the popup's own
-- override bindings (GAMEPAD_FACE_BOTTOM/RIGHT, Shared/GamepadConstants.lua:7-8,
-- forever branch), cleared when it closes: the game's controller navigation
-- doesn't reach it (kept apart on purpose), and a real button press is what lets
-- the secure Reload work. Each of the two buttons then shows the controller
-- button's icon at its left, as the game marks its own buttons in controller mode
-- (GamepadMode.AddGamepadIconToButton, FrameReformUtility.lua:25): the active
-- controller's atlas from InputIconTextureSetUtility (InputIconTexture.lua:565).
-- Without one, a hint line says which does what instead. It's our own frame, not the game's
-- StaticPopup (shared windows the controller steers: our code in them breaks its
-- navigation). Holding a secure button, it can't be shown in a fight: it
-- opens once the fight is over.
local ReticleOnTarget = _G.GamepadReticleOnTarget

local Popup = { WIDTH = 440, BUTTON_WIDTH = 170, BUTTON_HEIGHT = 24, BUTTONS = 3, HINT_HEIGHT = 18 }
ReticleOnTarget.Popup = Popup

local frame, waitingForCombatEnd, pendingOptions

local function build()
    frame = CreateFrame("Frame", "GamepadReticleOnTargetPopup", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetWidth(Popup.WIDTH)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -135)   -- where the game's popups open
    frame.Border = CreateFrame("Frame", nil, frame, "DialogBorderTemplate")
    frame.Border:SetAllPoints()

    frame.text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.text:SetPoint("TOP", frame, "TOP", 0, -20)
    frame.text:SetWidth(Popup.WIDTH - 50)

    frame.editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.editBox:SetSize(Popup.WIDTH - 70, 24)
    frame.editBox:SetPoint("TOP", frame.text, "BOTTOM", 0, -12)
    frame.editBox:SetAutoFocus(false)
    frame.editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

    -- Plain buttons, and one secure Reload (created now, out of combat).
    frame.buttons = {}
    for index = 1, Popup.BUTTONS do
        local button = CreateFrame("Button", "GamepadReticleOnTargetPopupButton" .. index, frame, "UIPanelButtonTemplate")
        button:SetSize(Popup.BUTTON_WIDTH, Popup.BUTTON_HEIGHT)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function(self)
            local onClick = self.onClick
            frame:Hide()
            if onClick then onClick() end
        end)
        frame.buttons[index] = button
    end
    frame.reloadButton = CreateFrame("Button", "GamepadReticleOnTargetPopupReload", frame,
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    frame.reloadButton:SetSize(Popup.BUTTON_WIDTH, Popup.BUTTON_HEIGHT)
    frame.reloadButton:SetAttribute("type", "macro")
    frame.reloadButton:SetAttribute("macrotext", "/reload")
    frame.reloadButton:RegisterForClicks("AnyUp", "AnyDown")
    frame.reloadButton:SetScript("PreClick", function(self)
        if self.beforeReload then pcall(self.beforeReload) end
    end)
    -- The controller hint, under the buttons.
    frame.hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    -- Closing gives the controller's buttons back (after the fight if in one).
    frame:SetScript("OnHide", function() Popup.ReleaseControllerButtons() end)
    Popup.frame = frame
end

local function controllerUIOn()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function"
        and InputUtil.IsGamepadUIEnabled() == true
end

-- A controller button's name as the game shows it, else a plain letter.
local function buttonLabel(key, fallback)
    local text = type(GetBindingText) == "function" and GetBindingText(key) or nil
    if type(text) ~= "string" or text == "" or text == key then return fallback end
    return text
end

local releaseAfterCombat
function Popup.ReleaseControllerButtons()
    if not frame or type(ClearOverrideBindings) ~= "function" then return end
    if InCombatLockdown() then
        releaseAfterCombat = releaseAfterCombat or CreateFrame("Frame")
        releaseAfterCombat:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if not frame:IsShown() then ClearOverrideBindings(frame) end
        end)
        releaseAfterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ClearOverrideBindings(frame)
end

-- The active controller's icon for a button key (an atlas), or nil.
local function controllerIconAtlas(key)
    local iconUtility = _G.InputIconTextureSetUtility
    if type(iconUtility) ~= "table" or type(iconUtility.GetNormalActiveInputIconButtonTexture) ~= "function" then return nil end
    local succeeded, atlas = pcall(iconUtility.GetNormalActiveInputIconButtonTexture, key)
    return succeeded and type(atlas) == "string" and atlas or nil
end

-- Shows (or hides, with no key) a controller button's icon at a button's left.
local function setButtonIcon(button, key)
    if not button.controllerIcon then
        button.controllerIcon = button:CreateTexture(nil, "OVERLAY")
        button.controllerIcon:SetSize(Popup.BUTTON_HEIGHT - 4, Popup.BUTTON_HEIGHT - 4)
        button.controllerIcon:SetPoint("LEFT", button, "LEFT", 4, 0)
    end
    local atlas = key and controllerIconAtlas(key)
    if atlas then button.controllerIcon:SetAtlas(atlas); button.controllerIcon:Show() else button.controllerIcon:Hide() end
    return atlas ~= nil
end

-- A clicks the first button, B the last, while the popup is open. Returns the
-- hint line's height (0 when the buttons show their icons).
local function takeControllerButtons(first, last)
    frame.hint:SetText("")
    for _, button in ipairs(frame.buttons) do setButtonIcon(button, nil) end
    setButtonIcon(frame.reloadButton, nil)
    if not (controllerUIOn() and type(SetOverrideBindingClick) == "function") then return 0 end
    local confirmKey, backKey = GAMEPAD_FACE_BOTTOM or "PAD1", GAMEPAD_FACE_RIGHT or "PAD2"
    ClearOverrideBindings(frame)
    SetOverrideBindingClick(frame, true, confirmKey, first:GetName(), "LeftButton")
    local iconsShown = setButtonIcon(first, confirmKey)
    local hint = buttonLabel(confirmKey, "A") .. ": " .. first:GetText()
    if last ~= first then
        SetOverrideBindingClick(frame, true, backKey, last:GetName(), "LeftButton")
        iconsShown = setButtonIcon(last, backKey) and iconsShown
        hint = hint .. "      " .. buttonLabel(backKey, "B") .. ": " .. last:GetText()
    end
    if iconsShown then return 0 end
    frame.hint:SetText(hint)   -- no icons on this client: say it in words
    return Popup.HINT_HEIGHT
end

local function layout(options)
    frame.text:SetText(options.text or "")
    -- Centered as the game's popups are; a list ("•" lines) reads better left-aligned.
    frame.text:SetJustifyH((options.text or ""):find("•", 1, true) and "LEFT" or "CENTER")
    local height = 20 + (frame.text:GetStringHeight() or 40) + 16
    frame.editBox:SetShown(options.copyText ~= nil)
    frame.editBox:SetText(options.copyText or "")
    if options.copyText then height = height + 36 end

    for _, button in ipairs(frame.buttons) do button:Hide() end
    frame.reloadButton:Hide()
    local shown = {}
    local plainIndex = 0
    for _, spec in ipairs(options.buttons or { { text = CLOSE or "Close" } }) do
        local button
        if spec.reload then
            button = frame.reloadButton
            button.beforeReload = spec.beforeReload
        else
            plainIndex = plainIndex + 1
            button = frame.buttons[plainIndex]
            button.onClick = spec.onClick
        end
        button:SetText(spec.text)
        shown[#shown + 1] = button
    end
    -- The buttons in a centered row at the bottom, as the game's popups have them.
    local gap = 10
    local rowWidth = #shown * Popup.BUTTON_WIDTH + (#shown - 1) * gap
    for _, button in ipairs(shown) do
        button:ClearAllPoints()
        button:Show()
    end
    local hintHeight = takeControllerButtons(shown[1], shown[#shown])
    for index, button in ipairs(shown) do
        button:SetPoint("BOTTOMLEFT", frame, "BOTTOM", -rowWidth / 2 + (index - 1) * (Popup.BUTTON_WIDTH + gap), 16 + hintHeight)
    end
    frame:SetHeight(height + Popup.BUTTON_HEIGHT + 16 + hintHeight)
end

function Popup.Show(options)
    if InCombatLockdown() then
        -- A frame holding a secure button can't be shown in combat: after the fight.
        pendingOptions = options
        if not waitingForCombatEnd then
            waitingForCombatEnd = CreateFrame("Frame")
            waitingForCombatEnd:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if pendingOptions then local waiting = pendingOptions; pendingOptions = nil; Popup.Show(waiting) end
            end)
        end
        waitingForCombatEnd:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    if not frame then build() end
    layout(options)
    frame:Show()
    if options.copyText then
        frame.editBox:SetFocus()
        frame.editBox:HighlightText()
    end
    return true
end

function Popup.Hide() if frame then frame:Hide() end end
