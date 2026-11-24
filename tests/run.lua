-- GamepadReticleOnTarget against a fake game: the controller's reticle, nameplates, CVars,
-- the Settings API, frames, timers and events. From GamepadReticleOnTarget:  luajit tests/run.lua
-- GRT_TEST="part of a name" runs only the tests whose name holds it.
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local only = os.getenv("GRT_TEST")
local function test(name, testBody)
    if only and not name:find(only, 1, true) then return end
    local ok, err = xpcall(testBody, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; reportLine("FAIL " .. name .. "\n" .. err) end
end
local function expectEqual(actual, expected, message)
    if actual ~= expected then error((message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local game
-- releaseBuild: as in the release zip, without Debug.lua (see .pkgmeta).
-- nameplateOptions: { enemies, friends, classColors } as "0"/"1" (default all "0"),
-- refuse = true: the game won't take a change to them.
local function boot(gamepad, saved, releaseBuild, nameplateOptions)
    nameplateOptions = nameplateOptions or {}
    _G.C_AddOns = {
        DoesAddOnExist = function(name)
            return name == "GamepadReticleCustomizer" and (nameplateOptions.customizerInstalled == true or nameplateOptions.customizerOff == true)
        end,
        -- Turned off: as the game, GetAddOnInfo's reason says so.
        GetAddOnInfo = function(name)
            if name == "GamepadReticleCustomizer" and nameplateOptions.customizerOff then return name, name, "", false, "DISABLED", "INSECURE" end
            return name, name, "", true, "", "INSECURE"
        end,
    }
    game = { saved = {}, temp = {}, timers = {}, frames = {}, settings = {}, callbacks = {}, events = 0 }
    game.saved.nameplateShowEnemies = nameplateOptions.enemies or "0"
    game.saved.nameplateShowFriendlyPlayers = nameplateOptions.friends or "0"
    game.saved.nameplateShowFriendlyClassColor = nameplateOptions.classColors or "0"
    game.saved.nameplateShowFriendlyNpcs = nameplateOptions.npcs or "0"
    game.saved.nameplateShowFriendlyPlayerMinions = nameplateOptions.minions or "0"
    local function fire(event, ...)
        for _, fakeFrame in ipairs(game.frames) do if fakeFrame.ev[event] and fakeFrame.script then fakeFrame.script(fakeFrame, event, ...) end end
    end
    game.fire = fire
    local function changed(cvarName) fire("CVAR_UPDATE", cvarName, _G.C_CVar.GetCVar(cvarName)) end
    _G.C_CVar = {
        GetCVar = function(cvarName) if game.temp[cvarName] ~= nil then return game.temp[cvarName] end return game.saved[cvarName] end,
        SetCVar = function(cvarName, value)
            if nameplateOptions.refuse and cvarName:find("^nameplate") then return false end
            game.saved[cvarName] = value; changed(cvarName); return true
        end,
        SetTempCVar = function(cvarName, value) game.temp[cvarName] = value; changed(cvarName) end,
        RemoveTempCVar = function(cvarName) game.temp[cvarName] = nil; changed(cvarName) end,
    }
    _G.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    _G.C_Timer = { After = function(_, callback) game.timers[#game.timers + 1] = callback end }
    local function newFakeRegion()
        local fakeRegion = {}
        for _, methodName in ipairs({ "SetAllPoints", "SetColorTexture", "SetPoint", "SetWidth", "SetSize", "SetFrameStrata", "RegisterForClicks", "EnableMouse",
            "SetAutoFocus", "SetFocus", "SetToplevel", "SetHeight", "ClearAllPoints", "SetJustifyH" }) do
            fakeRegion[methodName] = function() end
        end
        function fakeRegion:SetText(text) self.label = text end
        function fakeRegion:GetText() return self.label end
        function fakeRegion:HighlightText() self.highlighted = true end
        function fakeRegion:GetStringHeight() return 30 end
        function fakeRegion:SetShown(shown) self.shown = shown and true or false end
        function fakeRegion:IsShown() return self.shown == true end
        function fakeRegion:SetAtlas(atlas) self.atlas = atlas end
        function fakeRegion:Show() self.shown = true end
        function fakeRegion:Hide() self.shown = false end
        function fakeRegion:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
        function fakeRegion:CreateTexture() return newFakeRegion() end
        function fakeRegion:CreateFontString() return newFakeRegion() end
        return fakeRegion
    end
    _G.CreateFrame = function(frameType, name, parent, template)
        local fakeFrame = newFakeRegion()
        fakeFrame.ev, fakeFrame.frameType, fakeFrame.name, fakeFrame.template = {}, frameType, name, template
        if name then _G[name] = fakeFrame end
        function fakeFrame:RegisterEvent(eventName) self.ev[eventName] = true end
        function fakeFrame:UnregisterEvent(eventName) self.ev[eventName] = nil end
        function fakeFrame:SetScript(scriptType, handler)
            if scriptType == "OnUpdate" then self.update = handler
            elseif scriptType == "OnClick" then self.click = handler
            elseif scriptType == "PreClick" then self.preClick = handler
            elseif scriptType == "OnHide" then self.onHide = handler
            else self.script = handler end
        end
        function fakeFrame:Show() self.shown = true end
        function fakeFrame:Hide()
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.onHide then self.onHide(self) end
        end
        function fakeFrame:GetName() return self.name end
        function fakeFrame:Click() if self.click then self.click(self) end end
        game.frames[#game.frames + 1] = fakeFrame
        return fakeFrame
    end
    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            return { name = name, GetID = function() return 42 end }, { AddInitializer = function(_, initializer) game.buttons[#game.buttons + 1] = initializer end }
        end,
        RegisterAddOnSetting = function(category, variable, key, savedTable, kind, label, defaultValue)
            if savedTable[key] == nil then savedTable[key] = defaultValue end
            local setting = { variable = variable, key = key, tbl = savedTable }
            game.settings[variable] = setting
            return setting
        end,
        SetOnValueChangedCallback = function(variable, callback) game.callbacks[variable] = callback end,
        CreateColorSwatch = function(_, setting) game.swatch = setting end,
        RegisterProxySetting = function(category, variable, kind, label, defaultValue, getValue, setValue)
            local setting = { variable = variable, key = variable, label = label, getValue = getValue, setValue = setValue }
            game.settings[variable] = setting
            return setting
        end,
        CreateCheckbox = function(_, setting, tooltip)
            local initializer = { checkbox = setting.key, tooltip = tooltip }
            function initializer:Indent() self.indented = true end
            game.buttons[#game.buttons + 1] = initializer
            return initializer
        end,
        CreateSlider = function(_, setting, options) game.options = game.options or {}; game.options[setting.key] = options end,
        CreateSliderOptions = function(minimum, maximum, step)
            return { lo = minimum, hi = maximum, SetLabelFormatter = function(self, _, formatter) self.format = formatter end }
        end,
        RegisterAddOnCategory = function(category) game.category = category end,
        OpenToCategory = function(id) game.opened = id end,
    }
    _G.SlashCmdList = {}
    _G.UIParent = { GetHeight = function() return 768 end }
    _G.GetCursorCenterPosition = function() return 0, 480 end
    _G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    _G.hooksecurefunc = function(owner, methodName, hook)
        if type(owner) == "string" then owner, methodName, hook = _G, owner, methodName end   -- the global form: hooksecurefunc("Name", fn)
        local original = owner[methodName]; owner[methodName] = function(...) local result = original(...); hook(...); return result end
    end
    game.recenters = 0
    _G.GamepadReticle = {
        GetEffectiveScale = function() return 1.5 end,
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, point, relativeFrame, relativePoint, x, y) self.point = { point, relativePoint, x, y, relativeTo = relativeFrame } end,
        -- Like the game: anchored to a nameplate (a restricted region), it can't be measured.
        GetPoint = function(self)
            local anchor = self.point
            if anchor and type(anchor.relativeTo) == "table" and anchor.relativeTo.restricted then
                error("GamepadReticle:GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]")
            end
            if anchor then return anchor[1], anchor.relativeTo or UIParent, anchor[2], anchor[3], anchor[4] end
        end,
        Recenter = function(self) game.recenters = game.recenters + 1; self.point = { "CENTER", "BOTTOM", 0, 320 } end,
        Icons = { StandardIcon = { color = { 1, 1, 1, 1 }, SetVertexColor = function(self, red, green, blue, alpha) self.color = { red, green, blue, alpha } end } },
    }
    -- Units and their nameplates: game.units[unit] = true, game.nameplates[unit] = a frame.
    game.units, game.nameplates = {}, {}
    _G.UnitExists = function(unit) return game.units[unit] == true or game.unitKinds[unit] ~= nil end
    _G.GetPhysicalScreenSize = function() return 2304, 1536 end
    game.buttons = {}
    _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, addSearchTags, newTagID, gameDataFunc, gameDataEvent)
        local initializer = { name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip,
            shownPredicates = {} }
        function initializer:AddShownPredicate(predicate) table.insert(self.shownPredicates, predicate) end
        -- As the game lays out the page: the row shows only if every shown predicate says so.
        function initializer:Shown()
            for _, predicate in ipairs(self.shownPredicates) do if not predicate() then return false end end
            return true
        end
        return initializer
    end
    local function addInitializer(_, initializer) game.buttons[#game.buttons + 1] = initializer end
    _G.CreateSettingsListSectionHeaderInitializer = function(name) return { heading = name } end
    _G.SettingsPanel = { GetLayout = function() return { AddInitializer = addInitializer } end }
    _G.C_NamePlate = {
        GetNamePlateForUnit = function(unit) return game.nameplates[unit] end,
        GetNamePlates = function()
            local list = {}
            for unit, plate in pairs(game.nameplates) do
                if unit:find("^nameplate") then plate.namePlateUnitToken = unit; list[#list + 1] = plate end
            end
            return list
        end,
    }
    -- What each unit is: game.unitKinds[unit] = { reaction = 1..8, player = true/false, controlled = true/false }.
    game.unitKinds = {}
    local function kindField(unit, field) return game.unitKinds[unit] and game.unitKinds[unit][field] end
    _G.UnitReaction = function(unit) return kindField(unit, "reaction") end
    _G.UnitIsPlayer = function(unit) return kindField(unit, "player") == true end
    _G.UnitPlayerControlled = function(unit) return kindField(unit, "controlled") == true end
    -- As the game: green for friendly, yellow for neutral, red for enemies.
    _G.UnitSelectionColor = function(unit)
        local reaction = kindField(unit, "reaction") or 0
        if reaction >= 5 then return 0, 1, 0 elseif reaction == 4 then return 1, 1, 0 end
        return 1, 0, 0
    end
    -- A unit's tooltip: its name, then its title (game.unitKinds[unit].title) or its level.
    _G.C_TooltipInfo = { GetUnit = function(unit)
        local title = kindField(unit, "title")
        return { lines = { { leftText = "Someone" }, { leftText = title or "Level 30" } } }
    end }
    _G.LEVEL = "Level"
    _G.CompactUnitFrame_UpdateName = function() end
    _G.NamePlateSetupOptions = { healthBarFontHeight = 16 }
    game.combat = false
    _G.InCombatLockdown = function() return game.combat end
    game.bindings, game.bindingOwners = {}, {}
    _G.SetOverrideBindingClick = function(owner, _, key, buttonName) game.bindings[key] = buttonName; game.bindingOwners[key] = owner end
    _G.ClearOverrideBindings = function(owner)
        for key, keyOwner in pairs(game.bindingOwners) do
            if keyOwner == owner then game.bindings[key], game.bindingOwners[key] = nil, nil end
        end
    end
    _G.GetBuildInfo = function() return "1.60.1", "70959", "", 16001 end
    _G.GamepadReticleOnTargetDB = saved
    _G.GamepadReticleOnTargetDebugDB = nil
    _G.GamepadReticleOnTargetPopup = nil
    local printed = {}
    game.printed = printed
    _G.print = function(text) printed[#printed + 1] = text end
    local namespace = {}
    for _, file in ipairs({ "GamepadReticleOnTarget.lua", "Reticle.lua", "Popup.lua", "Nameplates.lua", "NameplateNames.lua", "NameplateHiding.lua", "RelatedAddons.lua" }) do
        assert(loadfile(file))("GamepadReticleOnTarget", namespace)
    end
    if not releaseBuild then
        assert(loadfile("Debug.lua"))("GamepadReticleOnTarget", namespace)
        assert(loadfile("DebugTooltip.lua"))("GamepadReticleOnTarget", namespace)
    end
    fire("ADDON_LOADED", "GamepadReticleOnTarget")
end
local function runNextFrame() local dueTimers = game.timers; game.timers = {}; for _, timer in ipairs(dueTimers) do timer() end end
local function set(key, value)
    local setting = game.settings["GamepadReticleOnTarget_" .. key]
    setting.tbl[setting.key] = value
    game.callbacks[setting.variable](nil, setting, value)
end
local get = function(cvarName) return C_CVar.GetCVar(cvarName) end


local function near(actual, expected, message) if math.abs(actual - expected) > 0.01 then error((message or "") .. ": expected " .. expected .. ", got " .. actual, 2) end end
local function onUpdateFramesShown()
    local count = 0
    for _, fakeFrame in ipairs(game.frames) do if fakeFrame.update and fakeFrame.shown then count = count + 1 end end
    return count
end
local function enterWorld() game.fire("PLAYER_ENTERING_WORLD"); runNextFrame() end

test("registers its page under Options > AddOns, with the defaults; /grt and /gamepadreticleontarget open it", function()
    boot(true, nil)
    expectEqual(game.category.name, "Gamepad Reticle On Target")
    expectEqual(GamepadReticleOnTargetDB.enabled, true); expectEqual(GamepadReticleOnTargetDB.offset, 0)
    expectEqual(game.options.offset.format(10), "10 px up"); expectEqual(game.options.offset.format(-5), "5 px down"); expectEqual(game.options.offset.format(0), "Default")
    expectEqual(SLASH_GAMEPADRETICLEONTARGET1, "/grt"); expectEqual(SLASH_GAMEPADRETICLEONTARGET2, "/gamepadreticleontarget")
    SlashCmdList.GAMEPADRETICLEONTARGET("")
    expectEqual(game.opened, 42)
end)

test("controller, no target: the reticle stays where the game aims, with nothing per frame", function()
    boot(true, nil)
    enterWorld()
    local point = GamepadReticle.point
    near(point[3], 0, "x: the middle, where the controller's targeting aims")
    near(point[4], 320, "the game's aim height (480 / scale 1.5)")
    expectEqual(GamepadReticle.point.relativeTo, UIParent)
    set("offset", 5)
    near(GamepadReticle.point[4], 320, "the vertical offset is for targets: no target, the game's own height")
    expectEqual(onUpdateFramesShown(), 0, "no frame runs every frame")
end)

test("controller, a target: the reticle goes under its nameplate, re-placed only when the target or plates change", function()
    boot(true, nil)
    enterWorld()
    local targetPlate, softPlate = { name = "target's plate" }, { name = "soft target's plate" }
    game.units.softenemy = true; game.nameplates.softenemy = softPlate
    game.fire("PLAYER_SOFT_ENEMY_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, softPlate, "no target of yours: the controller's soft target")
    expectEqual(GamepadReticle.point[2], "BOTTOM"); expectEqual(GamepadReticle.point[4], -12, "just below the nameplate")
    set("offset", -30)
    -- 30 px on a 1536 px tall screen: 15 of its 768 units, at the reticle's scale 1.5: 10
    near(GamepadReticle.point[4], -12 - 10, "the vertical offset: 30 px down from there")
    set("offset", 0)
    game.units.target = true; game.nameplates.target = targetPlate
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, targetPlate, "your target first")
    game.fire("PLAYER_TARGET_CHANGED"); game.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    expectEqual(#game.timers, 2, "several reasons in one frame: placed once on the next frame, and once more a moment after the target change")
    runNextFrame()
    game.nameplates.target = nil; game.nameplates.softenemy = nil
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, UIParent, "no nameplate left (off screen): back where the game aims")
    game.nameplates.softenemy = softPlate
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate2"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, UIParent,
        "a target without a nameplate (a friend, friendly plates off): never jumps to the soft target")
    local friendPlate = { name = "friend's plate" }
    game.nameplates.target = friendPlate
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, friendPlate, "with friendly plates on: on the friend")
    expectEqual(onUpdateFramesShown(), 0, "still nothing per frame: the game moves the nameplate, and the dot with it")
end)

test("the game's own Recenter (a resize) is followed by ours", function()
    boot(true, nil)
    enterWorld()
    local targetPlate = {}
    game.units.target = true; game.nameplates.target = targetPlate
    GamepadReticle:Recenter()
    expectEqual(GamepadReticle.point.relativeTo, targetPlate, "put back on the target")
end)

test("keyboard at login, the controller later: the game's Recenter on the switch brings ours", function()
    local controller = false
    boot(false, nil)
    InputUtil.IsGamepadUIEnabled = function() return controller end
    enterWorld()
    local targetPlate = {}
    game.units.target = true; game.nameplates.target = targetPlate
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point, nil, "keyboard: never touched")
    controller = true
    GamepadReticle:Recenter()   -- the game's InitForGamepad
    expectEqual(GamepadReticle.point.relativeTo, targetPlate, "on the target")
    game.nameplates.target = nil
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, UIParent, "and its events listened to")
end)

test("turned off or on keyboard: the game's reticle is left alone", function()
    boot(true, nil)
    enterWorld()
    game.units.target = true; game.nameplates.target = {}
    set("enabled", false)
    expectEqual(GamepadReticle.point[3], 0, "recentered by the game's own code")
    expectEqual(GamepadReticle.point[4], 320)
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, nil, "and not put on the target")
    expectEqual(#game.timers, 0, "nothing queued while off")

    boot(false, nil)
    enterWorld()
    game.units.target = true; game.nameplates.target = {}
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point, nil, "keyboard: never touched")
    expectEqual(game.recenters, 0)
end)

test("the reticle goes under the part of the nameplate you see: health bar, else the name", function()
    boot(true, nil)
    enterWorld()
    local function part(visible) return { IsVisible = function() return visible end } end
    local healthBar, name = part(true), part(true)
    local plate = { UnitFrame = { healthBar = healthBar, name = name } }
    game.units.target = true; game.nameplates.target = plate
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, healthBar, "under the health bar")
    plate.UnitFrame.healthBar = part(false)
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, name, "names only (a friendly player): under the name")
end)

-- Nameplates for "Reticle on your target"

local function popup() local frame = _G.GamepadReticleOnTargetPopup; return frame and frame.shown and frame or nil end
local function popupButtons()
    local frame, texts = _G.GamepadReticleOnTargetPopup, {}
    for _, button in ipairs(frame.buttons) do if button.shown then texts[#texts + 1] = button.label end end
    if frame.reloadButton.shown then texts[#texts + 1] = "[secure] " .. frame.reloadButton.label end
    table.sort(texts)
    return table.concat(texts, ", ")
end
local function clickPopup(text)
    local frame = _G.GamepadReticleOnTargetPopup
    for _, button in ipairs(frame.buttons) do if button.shown and button.label == text then return button:Click() end end
end
local function nameplatesBox() local frame = popup(); return frame and frame.text.label:find("nameplate", 1, true) and frame or nil end
local function nameplateValues()
    return game.saved.nameplateShowEnemies .. game.saved.nameplateShowFriendlyPlayers .. game.saved.nameplateShowFriendlyClassColor
        .. game.saved.nameplateShowFriendlyNpcs .. game.saved.nameplateShowFriendlyPlayerMinions
end

test("first launch: a box says which nameplate settings are off; Turn on turns those on; asked once", function()
    boot(true, nil, false, { enemies = "1" })
    enterWorld()
    local box = nameplatesBox()
    expectEqual(box and box.shown, true, "the box")
    expectEqual(box.text.label:find("• friendly player nameplates\n• class colors on friendly player nameplates\n• friendly NPC nameplates\n• friendly player minions (pets, guardians, totems)", 1, true) ~= nil, true,
        "names the two that are off: " .. box.text.label)
    expectEqual(box.text.label:find("enemy nameplates", 1, true), nil, "not the one already on")
    expectEqual(nameplateValues(), "10000", "nothing changed before the click")
    expectEqual(popupButtons(), "No thanks, Turn on"); expectEqual(box.Border.template, "DialogBorderTemplate", "the game's dialog border")
    clickPopup("Turn on")
    expectEqual(nameplateValues(), "11111", "turned on")
    expectEqual(GamepadReticleOnTargetDB.nameplatesAsked, true)
    boot(true, GamepadReticleOnTargetDB, false, { enemies = "1" })
    enterWorld()
    expectEqual(nameplatesBox(), nil, "the next launch doesn't ask again")
end)

test("on the controller: A turns the nameplates on, B says no; closing gives the buttons back", function()
    boot(true, nil)
    enterWorld()
    expectEqual(game.bindings.PAD1, "GamepadReticleOnTargetPopupButton1", "A: Turn on")
    expectEqual(game.bindings.PAD2, "GamepadReticleOnTargetPopupButton2", "B: No thanks")
    _G[game.bindings.PAD1]:Click()
    expectEqual(nameplateValues(), "11111", "turned on with A")
    expectEqual(game.bindings.PAD1, nil, "given back"); expectEqual(game.bindings.PAD2, nil)
end)

test("No thanks changes nothing; the settings page's button asks again", function()
    boot(true, nil)
    enterWorld()
    clickPopup("No thanks")
    expectEqual(nameplateValues(), "00000", "nothing changed")
    expectEqual(GamepadReticleOnTargetDB.enabled, true, "the setting kept")
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Nameplates" then button = initializer end end
    expectEqual(button.buttonText, "Turn on nameplates")
    expectEqual(#button.shownPredicates, 0, "no shown predicate: it froze the controller's navigation")
    button.onClick()
    expectEqual(nameplatesBox().shown, true, "asked again")
end)

test("no box or row when the nameplates are on; no box when turned off", function()
    boot(true, nil, false, { enemies = "1", friends = "1", classColors = "1", npcs = "1", minions = "1" })
    enterWorld()
    expectEqual(nameplatesBox(), nil, "all on")
    for _, initializer in ipairs(game.buttons) do expectEqual(initializer.name ~= "Nameplates", true, "all on: no row") end
    boot(true, { enabled = false })
    enterWorld()
    expectEqual(nameplatesBox(), nil, "off: not needed")
end)

test("first launch in a fight: the box waits for its end", function()
    boot(true, nil)
    game.combat = true
    enterWorld()
    expectEqual(nameplatesBox(), nil, "not in combat")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(nameplatesBox().shown, true, "after the fight")
end)

test("if the game won't take the nameplate settings, Reticle on your target goes off and says why", function()
    boot(true, nil, false, { refuse = true })
    enterWorld()
    clickPopup("Turn on")
    expectEqual(nameplateValues(), "00000")
    expectEqual(GamepadReticleOnTargetDB.enabled, false, "the setting that needs them, off")
    expectEqual(game.printed[#game.printed]:find("couldn't turn on", 1, true) ~= nil, true, game.printed[#game.printed])
end)

test("without Gamepad Reticle Customizer: a button shows its link to copy; with it, no button", function()
    boot(true, nil)
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Customize the reticle" then button = initializer end end
    expectEqual(button and button.buttonText, "Get the addon")
    button.onClick()
    local box = popup()
    expectEqual(box.editBox:GetText(), "https://www.curseforge.com/projects/1818557", "its CurseForge page")
    expectEqual(box.editBox.highlighted, true, "selected, ready for Ctrl+C")
    expectEqual(popupButtons(), "Close, [secure] Reload", "a Reload for once it's installed")
    boot(true, nil, false, { customizerInstalled = true })
    for _, initializer in ipairs(game.buttons) do expectEqual(initializer.name ~= "Customize the reticle", true, "installed: no button") end
end)

-- /grt debug: the in-game suite, run here against the fake game.
local function runUntilNoTimersLeft()
    for _ = 1, 200 do if #game.timers == 0 then return end; runNextFrame() end
    error("the debug run never ended")
end
local function expectAllPassed(run)
    for _, check in ipairs(run.checks) do
        if check.result ~= "pass" then
            error(check.result .. ": " .. check.name .. " expected " .. tostring(check.expected)
                .. " got " .. tostring(check.actual) .. " " .. tostring(check.note))
        end
    end
end
local allNameplatesOn = { enemies = "1", friends = "1", classColors = "1", npcs = "1", minions = "1" }

test("/grt debug on a controller: every check passes, settings come back, a reload box", function()
    boot(true, { enabled = true, offset = -5 }, false, allNameplatesOn)
    game.fire("PLAYER_LOGIN"); enterWorld()
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    runUntilNoTimersLeft()
    local run = GamepadReticleOnTargetDebugDB.runs[1]
    expectAllPassed(run)
    expectEqual(run.passed > 5, true, "passed " .. run.passed)
    expectEqual(GamepadReticleOnTargetDB.offset, -5, "your settings back"); expectEqual(GamepadReticleOnTargetDB.enabled, true)
    expectEqual(popupButtons(), "Later, [secure] Reload")
end)

test("/grt debug with a target: the reticle on its nameplate is checked without measuring it (a restricted region)", function()
    boot(true, { enabled = true, offset = -5 }, false, allNameplatesOn)
    game.units.target = true; game.nameplates.target = { restricted = true }
    game.fire("PLAYER_LOGIN"); enterWorld()
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    runUntilNoTimersLeft()
    local run = GamepadReticleOnTargetDebugDB.runs[1]
    expectAllPassed(run)
    local onNameplate = 0
    for _, check in ipairs(run.checks) do
        if check.name:find("on the target's nameplate", 1, true) then onNameplate = onNameplate + 1 end
    end
    expectEqual(onNameplate > 0, true, "the nameplate checks ran")
end)

test("/grt debug on keyboard: reticle checks skipped, nothing fails", function()
    boot(false, nil, false, allNameplatesOn)
    enterWorld()
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    runUntilNoTimersLeft()
    local run = GamepadReticleOnTargetDebugDB.runs[1]
    expectEqual(run.failed, 0); expectEqual(run.skipped > 0, true)
end)

test("/grt debug: a fight stops it and puts your settings back; a cut-short run is undone at login", function()
    boot(true, { enabled = true, offset = 10 }, false, allNameplatesOn)
    enterWorld()
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    runNextFrame(); runNextFrame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    expectEqual(GamepadReticleOnTargetDebugDB.runs[1].stopped, "combat")
    expectEqual(GamepadReticleOnTargetDB.offset, 10)
    boot(true, { enabled = false, offset = 40 })
    GamepadReticleOnTargetDebugDB = { runs = {}, settingsToRestore = { enabled = true, offset = 3 } }
    game.fire("PLAYER_LOGIN")
    expectEqual(GamepadReticleOnTargetDB.enabled, true); expectEqual(GamepadReticleOnTargetDB.offset, 3)
end)

test("the release leaves Debug.lua out; listed under Gamepad", function()
    local function readFile(path) local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text end
    assert(readFile(".pkgmeta"):find("\n  %- Debug%.lua\n"), ".pkgmeta ignores Debug.lua, alone on its line")
    local toc = readFile("GamepadReticleOnTarget.toc"):gsub("\r", "")
    local releaseToc = toc:gsub("#@do%-not%-package@.-#@end%-do%-not%-package@\n?", "")
    local loadedFiles = {}
    for line in releaseToc:gmatch("[^\n]+") do
        if not line:find("^#") then loadedFiles[#loadedFiles + 1] = line end
    end
    expectEqual(table.concat(loadedFiles, ","), "GamepadReticleOnTarget.lua,Reticle.lua,Popup.lua,Nameplates.lua,NameplateNames.lua,NameplateHiding.lua,RelatedAddons.lua")
    expectEqual(toc:match("## Category: ([^\n]+)"), "Gamepad")
end)

test("without Debug.lua (the release), the addon works and /grt debug opens the settings", function()
    boot(true, {}, true)
    expectEqual(GamepadReticleOnTarget.Debug, nil)
    enterWorld()
    expectEqual(GamepadReticle.point.relativeTo, UIParent, "placed")
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    expectEqual(game.opened, 42)
end)

test("its icon in the AddOns list: Media/icon-64.png, shipped", function()
    local function readFile(path) local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text end
    local toc = readFile("GamepadReticleOnTarget.toc"):gsub("\r", "")
    expectEqual(toc:match("## IconTexture: ([^\n]+)"), "Interface\\AddOns\\GamepadReticleOnTarget\\Media\\icon-64.png")
    expectEqual(readFile("Media/icon-64.png"):sub(2, 4), "PNG", "a PNG file")
    expectEqual(readFile(".pkgmeta"):find("- Media/icon-64.png", 1, true), nil, "not left out of the release")
end)

test("debug build: Gamepad Reticle Customizer turned off counts as missing, to see its button; the release doesn't", function()
    local function button()
        for _, initializer in ipairs(game.buttons) do if initializer.name == "Customize the reticle" then return initializer end end
    end
    boot(true, nil, false, { customizerOff = true })
    expectEqual(button() ~= nil, true, "turned off: the button, as players without it see it")
    boot(true, nil, true, { customizerOff = true })
    expectEqual(button(), nil, "the release: installed is installed")
    boot(true, nil, false, { customizerInstalled = true })
    expectEqual(button(), nil, "debug build, turned on: no button")
end)

test("a Get button for each missing sibling, in order, each with its own CurseForge link", function()
    boot(true, nil, false, { enemies = "1", friends = "1", classColors = "1", npcs = "1", minions = "1" })
    local names = {}
    for _, initializer in ipairs(game.buttons) do if initializer.buttonText then names[#names + 1] = initializer.name .. ": " .. initializer.buttonText end end
    expectEqual(table.concat(names, ", "), "Camera over shoulder: Get the addon, Customize the reticle: Get the addon, Map without its hitch: Get the addon")
    for _, initializer in ipairs(game.buttons) do
        if initializer.name == "Camera over shoulder" then initializer.onClick() end
    end
    expectEqual(_G.GamepadReticleOnTargetPopup.editBox:GetText(), "https://www.curseforge.com/projects/1818297")
end)

-- Hiding health bars and names on friendly NPCs' and minions' nameplates

-- A nameplate on screen for a unit: its UnitFrame with a health bar container and
-- a name, each with an alpha, as the game's.
local function addPlate(unit, kind, barAlpha)
    local function part(startAlpha)
        local region = { alpha = startAlpha or 1, color = { 1, 1, 1 }, shown = true }
        function region:SetAlpha(value) self.alpha = value end
        function region:GetAlpha() return self.alpha end
        function region:SetVertexColor(red, green, blue) self.color = { red, green, blue } end
        function region:GetVertexColor() return self.color[1], self.color[2], self.color[3] end
        function region:GetFont() return "font", 12, "" end
        function region:SetFont(font) self.font = font end
        function region:SetTextHeight(height) self.height = height end
        function region:SetText(text) self.text = text end
        function region:SetPoint() end
        function region:Show() self.shown = true end
        function region:Hide() self.shown = false end
        function region:IsShown() return self.shown end
        return region
    end
    local unitFrame = part(1)
    unitFrame.unit = unit
    unitFrame.HealthBarsContainer = part(barAlpha)
    unitFrame.PlayerLevelDiffFrame = part(1)
    unitFrame.name = part(1)
    function unitFrame:CreateFontString() self.title = part(1); return self.title end
    game.nameplates[unit] = { UnitFrame = unitFrame }
    game.unitKinds[unit] = kind
    game.fire("NAME_PLATE_UNIT_ADDED", unit)
    return unitFrame
end
-- "bar name" alphas of a plate, e.g. "0 1".
local function looks(unitFrame) return unitFrame.HealthBarsContainer.alpha .. " " .. unitFrame.name.alpha end
local FRIENDLY_NPC = { reaction = 5 }
local FRIENDLY_MINION = { reaction = 5, controlled = true }
local FRIENDLY_PLAYER = { reaction = 5, player = true, controlled = true }
local ENEMY_NPC = { reaction = 2 }
local NEUTRAL_NPC = { reaction = 4 }
local function hideAll() return { hideNpcHealthBars = true, hideNpcNames = true, hideNeutralHealthBars = true,
    hideNeutralNames = true, hideMinionHealthBars = true, hideMinionNames = true } end

test("all six off by default: every nameplate as the game draws it", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    for _, key in ipairs({ "hideNpcHealthBars", "hideNpcNames", "hideNeutralHealthBars", "hideNeutralNames", "hideMinionHealthBars", "hideMinionNames" }) do
        expectEqual(GamepadReticleOnTargetDB[key], false, key)
    end
    expectEqual(looks(addPlate("nameplate1", FRIENDLY_NPC)), "1 1"); expectEqual(looks(addPlate("nameplate2", FRIENDLY_MINION)), "1 1")
end)

test("each of the four on its own: only its part, only on its kind of unit", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    local npc, pet = addPlate("nameplate1", FRIENDLY_NPC), addPlate("nameplate2", FRIENDLY_MINION)
    set("hideNpcHealthBars", true)
    expectEqual(looks(npc), "0 1", "NPC: bar hidden, name kept"); expectEqual(looks(pet), "1 1", "minion untouched")
    set("hideNpcHealthBars", false); set("hideNpcNames", true)
    expectEqual(looks(npc), "1 0", "NPC: name hidden, bar kept")
    set("hideNpcNames", false); set("hideMinionHealthBars", true)
    expectEqual(looks(pet), "0 1", "minion: bar hidden"); expectEqual(looks(npc), "1 1", "NPC untouched")
    set("hideMinionHealthBars", false); set("hideMinionNames", true)
    expectEqual(looks(pet), "1 0", "minion: name hidden")
    set("hideMinionNames", false)
    expectEqual(looks(pet), "1 1"); expectEqual(looks(npc), "1 1")
end)

test("all four on: friendly NPCs and minions fully hidden; players, enemies and neutral ones untouched", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc, pet = addPlate("nameplate1", FRIENDLY_NPC), addPlate("nameplate2", FRIENDLY_MINION)
    expectEqual(looks(npc), "0 0"); expectEqual(looks(pet), "0 0")
    expectEqual(npc.alpha, 1, "the nameplate itself untouched")
    expectEqual(looks(addPlate("nameplate3", FRIENDLY_PLAYER)), "1 1", "a friendly player")
    expectEqual(looks(addPlate("nameplate4", ENEMY_NPC)), "1 1", "an enemy")
    expectEqual(looks(addPlate("nameplate5", NEUTRAL_NPC)), "0 0", "a neutral NPC: its own boxes, also on here")
end)

test("turned off, a part gets its own alpha back", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc = addPlate("nameplate1", FRIENDLY_NPC, 0.8)
    set("hideNpcHealthBars", false)
    expectEqual(npc.HealthBarsContainer.alpha, 0.8, "its own alpha back"); expectEqual(npc.name.alpha, 0, "the name still hidden")
end)

test("a nameplate going back to the game's pool gets its alphas back; a unit changing sides is checked again", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc = addPlate("nameplate1", FRIENDLY_NPC)
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    expectEqual(looks(npc), "1 1", "given back before the game reuses it")
    local turning = addPlate("nameplate2", FRIENDLY_NPC)
    expectEqual(looks(turning), "0 0")
    game.unitKinds.nameplate2 = ENEMY_NPC
    game.fire("UNIT_FACTION", "nameplate2")
    expectEqual(looks(turning), "1 1", "now an enemy: shown")
end)

test("the reticle still goes on a friendly NPC whose nameplate is fully hidden", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    addPlate("nameplate1", FRIENDLY_NPC)
    game.units.target = true; game.nameplates.target = game.nameplates.nameplate1
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, game.nameplates.nameplate1, "under its nameplate")
end)

test("a nameplate the game locks for addons is left alone", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc = addPlate("nameplate1", FRIENDLY_NPC)
    npc.HealthBarsContainer.alpha, npc.name.alpha = 1, 1
    function npc:IsForbidden() return true end
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    expectEqual(looks(npc), "1 1", "not touched")
end)

test("laid out as the game's Nameplates options: a heading per group, its boxes indented below", function()
    boot(true, nil, false, allNameplatesOn)
    local rows = {}
    for _, row in ipairs(game.buttons) do
        if row.heading then rows[#rows + 1] = "# " .. row.heading
        elseif row.checkbox then rows[#rows + 1] = (row.indented and "  " or "") .. row.checkbox end
    end
    expectEqual(table.concat(rows, ", "), "enabled, # Friendly NPC Nameplates,   hideNpcHealthBars,   hideNpcNames,   hideNpcLevels, "
        .. "  npcWorldNames, # Neutral NPC Nameplates,   hideNeutralHealthBars,   hideNeutralNames,   hideNeutralLevels, "
        .. "  neutralWorldNames, # Friendly Player Minions,   hideMinionHealthBars,   hideMinionNames,   hideMinionLevels")
    expectEqual(game.settings.GamepadReticleOnTarget_hideMinionNames ~= nil, true)
end)

test("neutral NPCs: their own two boxes; enemies and others' minions never touched", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    local neutral, npc = addPlate("nameplate1", NEUTRAL_NPC), addPlate("nameplate2", FRIENDLY_NPC)
    local enemy = addPlate("nameplate3", ENEMY_NPC)
    local enemyMinion = addPlate("nameplate4", { reaction = 4, controlled = true })
    set("hideNeutralHealthBars", true)
    expectEqual(looks(neutral), "0 1", "neutral: bar hidden"); expectEqual(looks(npc), "1 1", "friendly NPC untouched")
    set("hideNeutralNames", true)
    expectEqual(looks(neutral), "0 0")
    expectEqual(looks(enemy), "1 1", "an enemy, never"); expectEqual(looks(enemyMinion), "1 1", "a neutral player's minion, never")
end)

test("saved keys the addon doesn't use are dropped; its own record of the nameplate question kept", function()
    boot(true, { enabled = true, offset = 5, hidePets = true, somethingElse = 1, nameplatesAsked = true })
    expectEqual(GamepadReticleOnTargetDB.hidePets, nil); expectEqual(GamepadReticleOnTargetDB.somethingElse, nil)
    expectEqual(GamepadReticleOnTargetDB.offset, 5); expectEqual(GamepadReticleOnTargetDB.nameplatesAsked, true)
end)

test("turned off: the nameplate settings it turned on go back as they were; one you changed since, or that was already on, stays", function()
    boot(true, nil, false, { enemies = "1" })
    enterWorld()
    clickPopup("Turn on")
    expectEqual(nameplateValues(), "11111", "turned on")
    expectEqual(GamepadReticleOnTargetDB.nameplatesBefore.nameplateShowEnemies, nil, "already on: nothing to put back")
    C_CVar.SetCVar("nameplateShowFriendlyNpcs", "0")   -- you changed one yourself since
    set("enabled", false)
    expectEqual(nameplateValues(), "10000", "back as before; the one you changed left as you set it")
    expectEqual(GamepadReticleOnTargetDB.nameplatesBefore, nil, "nothing left to put back")
    expectEqual(game.printed[#game.printed]:find("back as they were", 1, true) ~= nil, true, game.printed[#game.printed])
    set("enabled", true)
    expectEqual(nameplatesBox() ~= nil, true, "turned on again: asked again")
end)

test("turned off in a fight: put back once it's over, if still off", function()
    boot(true, nil, false, { enemies = "1" })
    enterWorld()
    clickPopup("Turn on")
    game.combat = true
    set("enabled", false)
    expectEqual(nameplateValues(), "11111", "not in combat")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(nameplateValues(), "10000", "after the fight")
end)

test("what it turned on is remembered across reloads", function()
    boot(true, nil, false, { enemies = "1" })
    enterWorld()
    clickPopup("Turn on")
    boot(true, GamepadReticleOnTargetDB, false, { enemies = "1", friends = "1", classColors = "1", npcs = "1", minions = "1" })
    set("enabled", false)
    expectEqual(nameplateValues(), "10000", "put back after a reload")
end)

test("turned off: hidden health bars and names show again", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc = addPlate("nameplate1", FRIENDLY_NPC)
    expectEqual(looks(npc), "0 0")
    set("enabled", false)
    expectEqual(looks(npc), "1 1", "the game's nameplate as it is")
    set("enabled", true)
    expectEqual(looks(npc), "0 0", "hidden again")
end)

test("World-style names: friendly and neutral NPCs' names in the game's color, title under it; the level badge stays", function()
    boot(true, { npcWorldNames = true, neutralWorldNames = true, hideNpcHealthBars = true }, false, allNameplatesOn)
    enterWorld()
    local master = addPlate("nameplate1", { reaction = 5, title = "Stable Master" })
    expectEqual(table.concat(master.name.color, " "), "0 1 0", "green, as the game's world names")
    expectEqual(master.title.text, "<Stable Master>"); expectEqual(table.concat(master.title.color, " "), "0 1 0"); expectEqual(master.title.shown, true)
    expectEqual(master.PlayerLevelDiffFrame.alpha, 1, "the level badge stays")
    local emissary = addPlate("nameplate2", { reaction = 4 })
    expectEqual(table.concat(emissary.name.color, " "), "1 1 0", "neutral: yellow")
    expectEqual(emissary.title, nil, "no title (its tooltip's second line is its level): none added")
end)

test("World-style names off: the name's own color back, the title hidden; Hide names hides the title too", function()
    boot(true, { npcWorldNames = true }, false, allNameplatesOn)
    enterWorld()
    local master = addPlate("nameplate1", { reaction = 5, title = "Stable Master" })
    set("hideNpcNames", true)
    expectEqual(master.name.alpha, 0); expectEqual(master.title.alpha, 0, "the title with the name")
    set("hideNpcNames", false)
    expectEqual(master.title.alpha, 1)
    set("npcWorldNames", false)
    expectEqual(table.concat(master.name.color, " "), "1 1 1", "the game's white back"); expectEqual(master.title.shown, false)
end)

test("the game's own name update is followed by our color", function()
    boot(true, { npcWorldNames = true }, false, allNameplatesOn)
    enterWorld()
    local master = addPlate("nameplate1", { reaction = 5 })
    master.name:SetVertexColor(1, 1, 1)
    CompactUnitFrame_UpdateName(master)
    expectEqual(table.concat(master.name.color, " "), "0 1 0")
end)

test("off by default, and minions keep the game's name look", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    expectEqual(GamepadReticleOnTargetDB.npcWorldNames, false); expectEqual(GamepadReticleOnTargetDB.neutralWorldNames, false)
    local npc = addPlate("nameplate1", { reaction = 5, title = "Stable Master" })
    expectEqual(table.concat(npc.name.color, " "), "1 1 1", "the game's own look"); expectEqual(npc.title, nil)
    set("hideNpcHealthBars", true)
    expectEqual(table.concat(npc.name.color, " "), "1 1 1", "hiding the bar alone keeps the game's name")
    boot(true, { npcWorldNames = true, neutralWorldNames = true }, false, allNameplatesOn)
    enterWorld()
    local minion = addPlate("nameplate2", FRIENDLY_MINION)
    expectEqual(table.concat(minion.name.color, " "), "1 1 1"); expectEqual(minion.title, nil)
end)

test("Hide level: the level beside the name, per group, off by default", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    expectEqual(GamepadReticleOnTargetDB.hideNpcLevels, false); expectEqual(GamepadReticleOnTargetDB.hideMinionLevels, false)
    local npc, minion = addPlate("nameplate1", FRIENDLY_NPC), addPlate("nameplate2", FRIENDLY_MINION)
    set("hideNpcLevels", true)
    expectEqual(npc.PlayerLevelDiffFrame.alpha, 0); expectEqual(npc.HealthBarsContainer.alpha, 1, "the bar kept"); expectEqual(npc.name.alpha, 1)
    expectEqual(minion.PlayerLevelDiffFrame.alpha, 1, "minions: their own box")
    set("hideMinionLevels", true)
    expectEqual(minion.PlayerLevelDiffFrame.alpha, 0)
end)

test("Name size: world-style names at a percentage of the game's nameplate name size; Default and off give the game's back", function()
    boot(true, { npcWorldNames = true }, false, allNameplatesOn)
    enterWorld()
    expectEqual(game.options.npcNameSize.format(100), "Default"); expectEqual(game.options.npcNameSize.format(150), "150%")
    local npc = addPlate("nameplate1", FRIENDLY_NPC)
    expectEqual(npc.name.height, nil, "Default: the game's height untouched")
    set("npcNameSize", 150)
    expectEqual(npc.name.height, 24, "150% of the game's 16")
    set("npcNameSize", 100)
    expectEqual(npc.name.height, 16, "back to the game's")
    set("npcNameSize", 125)
    set("npcWorldNames", false)
    expectEqual(npc.name.height, 16, "World-style names off: the game's size back")
end)

test("on a nameplate with the game's interaction icon frame: centered on it, the offset from there", function()
    boot(true, nil)
    enterWorld()
    local iconSpot = { name = "SoftTargetFrame" }
    local plate = { UnitFrame = { SoftTargetFrame = iconSpot } }
    game.units.target = true; game.nameplates.target = plate
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, iconSpot, "where the game shows its icon")
    expectEqual(GamepadReticle.point[2], "CENTER"); expectEqual(GamepadReticle.point[4], 0, "right on it by default")
    set("offset", -30)
    near(GamepadReticle.point[4], -10, "30 px down from there")
end)

test("a quest giver (the game draws its \"!\" above the head): the reticle below the name, not on the icon spot", function()
    boot(true, nil)
    enterWorld()
    local iconSpot, healthBar = { name = "SoftTargetFrame" }, { IsVisible = function() return true end }
    local plate = { UnitFrame = { SoftTargetFrame = iconSpot, healthBar = healthBar } }
    local cursorTexture
    _G.SetUnitCursorTexture = function(texture) function texture:GetTexture() return cursorTexture end; return true end
    game.units.target = true; game.nameplates.target = plate
    cursorTexture = "Cursor Crosshair_Quest_64"
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, healthBar, "below the nameplate, clear of the \"!\"")
    expectEqual(GamepadReticle.point[2], "BOTTOM")
    cursorTexture = "Cursor Crosshair_Trainer_64"
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point.relativeTo, iconSpot, "a trainer: on the icon spot")
    _G.SetUnitCursorTexture = nil
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
