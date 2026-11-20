-- GamepadReticleOnTarget against a fake game: the controller's reticle, nameplates, CVars,
-- the Settings API, frames, timers and events. From GamepadReticleOnTarget:  luajit tests/run.lua
-- GRT_TEST="part of a name" runs only the tests whose name holds it.
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local only = os.getenv("GRT_TEST")
local function test(name, fn)
    if only and not name:find(only, 1, true) then return end
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; reportLine("FAIL " .. name .. "\n" .. err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

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
        for _, f in ipairs(game.frames) do if f.ev[event] and f.script then f.script(f, event, ...) end end
    end
    game.fire = fire
    local function changed(n) fire("CVAR_UPDATE", n, _G.C_CVar.GetCVar(n)) end
    _G.C_CVar = {
        GetCVar = function(n) if game.temp[n] ~= nil then return game.temp[n] end return game.saved[n] end,
        SetCVar = function(n, v)
            if nameplateOptions.refuse and n:find("^nameplate") then return false end
            game.saved[n] = v; changed(n); return true
        end,
        SetTempCVar = function(n, v) game.temp[n] = v; changed(n) end,
        RemoveTempCVar = function(n) game.temp[n] = nil; changed(n) end,
    }
    _G.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    _G.C_Timer = { After = function(_, fn) game.timers[#game.timers + 1] = fn end }
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
        RegisterAddOnSetting = function(cat, variable, key, tbl, kind, label, def)
            if tbl[key] == nil then tbl[key] = def end
            local s = { variable = variable, key = key, tbl = tbl }
            game.settings[variable] = s
            return s
        end,
        SetOnValueChangedCallback = function(variable, fn) game.callbacks[variable] = fn end,
        CreateColorSwatch = function(_, setting) game.swatch = setting end,
        RegisterProxySetting = function(cat, variable, kind, label, def, getValue, setValue)
            local s = { variable = variable, key = variable, label = label, getValue = getValue, setValue = setValue }
            game.settings[variable] = s
            return s
        end,
        CreateCheckbox = function() end,
        CreateSlider = function(_, setting, options) game.options = game.options or {}; game.options[setting.key] = options end,
        CreateSliderOptions = function(lo, hi, step)
            return { lo = lo, hi = hi, SetLabelFormatter = function(self, _, fn) self.format = fn end }
        end,
        RegisterAddOnCategory = function(cat) game.category = cat end,
        OpenToCategory = function(id) game.opened = id end,
    }
    _G.SlashCmdList = {}
    _G.UIParent = { GetHeight = function() return 768 end }
    _G.GetCursorCenterPosition = function() return 0, 480 end
    _G.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    _G.hooksecurefunc = function(t, m, fn)
        if type(t) == "string" then t, m, fn = _G, t, m end   -- the global form: hooksecurefunc("Name", fn)
        local orig = t[m]; t[m] = function(...) local r = orig(...); fn(...); return r end
    end
    game.recenters = 0
    _G.GamepadReticle = {
        GetEffectiveScale = function() return 1.5 end,
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, p, rel, rp, x, y) self.point = { p, rp, x, y, relativeTo = rel } end,
        -- Like the game: anchored to a nameplate (a restricted region), it can't be measured.
        GetPoint = function(self)
            local q = self.point
            if q and type(q.relativeTo) == "table" and q.relativeTo.restricted then
                error("GamepadReticle:GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]")
            end
            if q then return q[1], q.relativeTo or UIParent, q[2], q[3], q[4] end
        end,
        Recenter = function(self) game.recenters = game.recenters + 1; self.point = { "CENTER", "BOTTOM", 0, 320 } end,
        Icons = { StandardIcon = { color = { 1, 1, 1, 1 }, SetVertexColor = function(self, r, g, b, a) self.color = { r, g, b, a } end } },
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
    _G.UnitIsBattlePetCompanion = function(unit) return kindField(unit, "companion") == true end
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
    _G.print = function(t) printed[#printed + 1] = t end
    local ns = {}
    for _, file in ipairs({ "GamepadReticleOnTarget.lua", "Reticle.lua", "Popup.lua", "Nameplates.lua", "NameplateHiding.lua", "RelatedAddons.lua" }) do
        assert(loadfile(file))("GamepadReticleOnTarget", ns)
    end
    if not releaseBuild then assert(loadfile("Debug.lua"))("GamepadReticleOnTarget", ns) end
    fire("ADDON_LOADED", "GamepadReticleOnTarget")
end
local function frame() local t = game.timers; game.timers = {}; for _, fn in ipairs(t) do fn() end end
local function set(key, value)
    local s = game.settings["GamepadReticleOnTarget_" .. key]
    s.tbl[s.key] = value
    game.callbacks[s.variable](nil, s, value)
end
local get = function(n) return C_CVar.GetCVar(n) end


local function near(a, b, msg) if math.abs(a - b) > 0.01 then error((msg or "") .. ": expected " .. b .. ", got " .. a, 2) end end
local function onUpdateFramesShown()
    local count = 0
    for _, f in ipairs(game.frames) do if f.update and f.shown then count = count + 1 end end
    return count
end
local function enterWorld() game.fire("PLAYER_ENTERING_WORLD"); frame() end

test("registers its page under Options > AddOns, with the defaults; /grt and /gamepadreticleontarget open it", function()
    boot(true, nil)
    eq(game.category.name, "Gamepad Reticle On Target")
    eq(GamepadReticleOnTargetDB.enabled, true); eq(GamepadReticleOnTargetDB.offset, 0)
    eq(game.options.offset.format(10), "10 px up"); eq(game.options.offset.format(-5), "5 px down"); eq(game.options.offset.format(0), "Default")
    eq(SLASH_GAMEPADRETICLEONTARGET1, "/grt"); eq(SLASH_GAMEPADRETICLEONTARGET2, "/gamepadreticleontarget")
    SlashCmdList.GAMEPADRETICLEONTARGET("")
    eq(game.opened, 42)
end)

test("controller, no target: the reticle stays where the game aims, with nothing per frame", function()
    boot(true, nil)
    enterWorld()
    local p = GamepadReticle.point
    near(p[3], 0, "x: the middle, where the controller's targeting aims")
    near(p[4], 320, "the game's aim height (480 / scale 1.5)")
    eq(GamepadReticle.point.relativeTo, UIParent)
    set("offset", 5)
    near(GamepadReticle.point[4], 320, "the vertical offset is for targets: no target, the game's own height")
    eq(onUpdateFramesShown(), 0, "no frame runs every frame")
end)

test("controller, a target: the reticle goes under its nameplate, re-placed only when the target or plates change", function()
    boot(true, nil)
    enterWorld()
    local targetPlate, softPlate = { name = "target's plate" }, { name = "soft target's plate" }
    game.units.softenemy = true; game.nameplates.softenemy = softPlate
    game.fire("PLAYER_SOFT_ENEMY_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, softPlate, "no target of yours: the controller's soft target")
    eq(GamepadReticle.point[2], "BOTTOM"); eq(GamepadReticle.point[4], -12, "just below the nameplate")
    set("offset", -30)
    -- 30 px on a 1536 px tall screen: 15 of its 768 units, at the reticle's scale 1.5: 10
    near(GamepadReticle.point[4], -12 - 10, "the vertical offset: 30 px down from there")
    set("offset", 0)
    game.units.target = true; game.nameplates.target = targetPlate
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, targetPlate, "your target first")
    game.fire("PLAYER_TARGET_CHANGED"); game.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    eq(#game.timers, 1, "several reasons in one frame: placed once, on the next frame")
    frame()
    game.nameplates.target = nil; game.nameplates.softenemy = nil
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); frame()
    eq(GamepadReticle.point.relativeTo, UIParent, "no nameplate left (off screen): back where the game aims")
    game.nameplates.softenemy = softPlate
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate2"); frame()
    eq(GamepadReticle.point.relativeTo, UIParent,
        "a target without a nameplate (a friend, friendly plates off): never jumps to the soft target")
    local friendPlate = { name = "friend's plate" }
    game.nameplates.target = friendPlate
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); frame()
    eq(GamepadReticle.point.relativeTo, friendPlate, "with friendly plates on: on the friend")
    eq(onUpdateFramesShown(), 0, "still nothing per frame: the game moves the nameplate, and the dot with it")
end)

test("the game's own Recenter (a resize) is followed by ours", function()
    boot(true, nil)
    enterWorld()
    local targetPlate = {}
    game.units.target = true; game.nameplates.target = targetPlate
    GamepadReticle:Recenter()
    eq(GamepadReticle.point.relativeTo, targetPlate, "put back on the target")
end)

test("keyboard at login, the controller later: the game's Recenter on the switch brings ours", function()
    local controller = false
    boot(false, nil)
    InputUtil.IsGamepadUIEnabled = function() return controller end
    enterWorld()
    local targetPlate = {}
    game.units.target = true; game.nameplates.target = targetPlate
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point, nil, "keyboard: never touched")
    controller = true
    GamepadReticle:Recenter()   -- the game's InitForGamepad
    eq(GamepadReticle.point.relativeTo, targetPlate, "on the target")
    game.nameplates.target = nil
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); frame()
    eq(GamepadReticle.point.relativeTo, UIParent, "and its events listened to")
end)

test("turned off or on keyboard: the game's reticle is left alone", function()
    boot(true, nil)
    enterWorld()
    game.units.target = true; game.nameplates.target = {}
    set("enabled", false)
    eq(GamepadReticle.point[3], 0, "recentered by the game's own code")
    eq(GamepadReticle.point[4], 320)
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, nil, "and not put on the target")
    eq(#game.timers, 0, "nothing queued while off")

    boot(false, nil)
    enterWorld()
    game.units.target = true; game.nameplates.target = {}
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point, nil, "keyboard: never touched")
    eq(game.recenters, 0)
end)

test("the reticle goes under the part of the nameplate you see: health bar, else the name", function()
    boot(true, nil)
    enterWorld()
    local function part(visible) return { IsVisible = function() return visible end } end
    local healthBar, name = part(true), part(true)
    local plate = { UnitFrame = { healthBar = healthBar, name = name } }
    game.units.target = true; game.nameplates.target = plate
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, healthBar, "under the health bar")
    plate.UnitFrame.healthBar = part(false)
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); frame()
    eq(GamepadReticle.point.relativeTo, name, "names only (a friendly player): under the name")
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
    eq(box and box.shown, true, "the box")
    eq(box.text.label:find("• friendly player nameplates\n• class colors on friendly player nameplates\n• friendly NPC nameplates\n• friendly player minions (pets, guardians, totems)", 1, true) ~= nil, true,
        "names the two that are off: " .. box.text.label)
    eq(box.text.label:find("enemy nameplates", 1, true), nil, "not the one already on")
    eq(nameplateValues(), "10000", "nothing changed before the click")
    eq(popupButtons(), "No thanks, Turn on"); eq(box.Border.template, "DialogBorderTemplate", "the game's dialog border")
    clickPopup("Turn on")
    eq(nameplateValues(), "11111", "turned on")
    eq(GamepadReticleOnTargetDB.nameplatesAsked, true)
    boot(true, GamepadReticleOnTargetDB, false, { enemies = "1" })
    enterWorld()
    eq(nameplatesBox(), nil, "the next launch doesn't ask again")
end)

test("on the controller: A turns the nameplates on, B says no; closing gives the buttons back", function()
    boot(true, nil)
    enterWorld()
    eq(game.bindings.PAD1, "GamepadReticleOnTargetPopupButton1", "A: Turn on")
    eq(game.bindings.PAD2, "GamepadReticleOnTargetPopupButton2", "B: No thanks")
    _G[game.bindings.PAD1]:Click()
    eq(nameplateValues(), "11111", "turned on with A")
    eq(game.bindings.PAD1, nil, "given back"); eq(game.bindings.PAD2, nil)
end)

test("No thanks changes nothing; the settings page's button asks again", function()
    boot(true, nil)
    enterWorld()
    clickPopup("No thanks")
    eq(nameplateValues(), "00000", "nothing changed")
    eq(GamepadReticleOnTargetDB.enabled, true, "the setting kept")
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Nameplates" then button = initializer end end
    eq(button.buttonText, "Turn on nameplates")
    eq(#button.shownPredicates, 0, "no shown predicate: it froze the controller's navigation")
    button.onClick()
    eq(nameplatesBox().shown, true, "asked again")
end)

test("no box or row when the nameplates are on; no box when turned off", function()
    boot(true, nil, false, { enemies = "1", friends = "1", classColors = "1", npcs = "1", minions = "1" })
    enterWorld()
    eq(nameplatesBox(), nil, "all on")
    for _, initializer in ipairs(game.buttons) do eq(initializer.name ~= "Nameplates", true, "all on: no row") end
    boot(true, { enabled = false })
    enterWorld()
    eq(nameplatesBox(), nil, "off: not needed")
end)

test("first launch in a fight: the box waits for its end", function()
    boot(true, nil)
    game.combat = true
    enterWorld()
    eq(nameplatesBox(), nil, "not in combat")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    eq(nameplatesBox().shown, true, "after the fight")
end)

test("if the game won't take the nameplate settings, Reticle on your target goes off and says why", function()
    boot(true, nil, false, { refuse = true })
    enterWorld()
    clickPopup("Turn on")
    eq(nameplateValues(), "00000")
    eq(GamepadReticleOnTargetDB.enabled, false, "the setting that needs them, off")
    eq(game.printed[#game.printed]:find("couldn't turn on", 1, true) ~= nil, true, game.printed[#game.printed])
end)

test("without Gamepad Reticle Customizer: a button shows its link to copy; with it, no button", function()
    boot(true, nil)
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Customize the reticle" then button = initializer end end
    eq(button and button.buttonText, "Get the addon")
    button.onClick()
    local box = popup()
    eq(box.editBox:GetText(), "https://www.curseforge.com/projects/1818557", "its CurseForge page")
    eq(box.editBox.highlighted, true, "selected, ready for Ctrl+C")
    eq(popupButtons(), "Close, [secure] Reload", "a Reload for once it's installed")
    boot(true, nil, false, { customizerInstalled = true })
    for _, initializer in ipairs(game.buttons) do eq(initializer.name ~= "Customize the reticle", true, "installed: no button") end
end)

-- /grt debug: the in-game suite, run here against the fake game.
local function runUntilNoTimersLeft()
    for _ = 1, 200 do if #game.timers == 0 then return end; frame() end
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
    eq(run.passed > 5, true, "passed " .. run.passed)
    eq(GamepadReticleOnTargetDB.offset, -5, "your settings back"); eq(GamepadReticleOnTargetDB.enabled, true)
    eq(popupButtons(), "Later, [secure] Reload")
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
    eq(onNameplate > 0, true, "the nameplate checks ran")
end)

test("/grt debug on keyboard: reticle checks skipped, nothing fails", function()
    boot(false, nil, false, allNameplatesOn)
    enterWorld()
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    runUntilNoTimersLeft()
    local run = GamepadReticleOnTargetDebugDB.runs[1]
    eq(run.failed, 0); eq(run.skipped > 0, true)
end)

test("/grt debug: a fight stops it and puts your settings back; a cut-short run is undone at login", function()
    boot(true, { enabled = true, offset = 10 }, false, allNameplatesOn)
    enterWorld()
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    frame(); frame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    eq(GamepadReticleOnTargetDebugDB.runs[1].stopped, "combat")
    eq(GamepadReticleOnTargetDB.offset, 10)
    boot(true, { enabled = false, offset = 40 })
    GamepadReticleOnTargetDebugDB = { runs = {}, settingsToRestore = { enabled = true, offset = 3 } }
    game.fire("PLAYER_LOGIN")
    eq(GamepadReticleOnTargetDB.enabled, true); eq(GamepadReticleOnTargetDB.offset, 3)
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
    eq(table.concat(loadedFiles, ","), "GamepadReticleOnTarget.lua,Reticle.lua,Popup.lua,Nameplates.lua,NameplateHiding.lua,RelatedAddons.lua")
    eq(toc:match("## Category: ([^\n]+)"), "Gamepad")
end)

test("without Debug.lua (the release), the addon works and /grt debug opens the settings", function()
    boot(true, {}, true)
    eq(GamepadReticleOnTarget.Debug, nil)
    enterWorld()
    eq(GamepadReticle.point.relativeTo, UIParent, "placed")
    SlashCmdList.GAMEPADRETICLEONTARGET("debug")
    eq(game.opened, 42)
end)

test("its icon in the AddOns list: Media/icon-64.png, shipped", function()
    local function readFile(path) local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text end
    local toc = readFile("GamepadReticleOnTarget.toc"):gsub("\r", "")
    eq(toc:match("## IconTexture: ([^\n]+)"), "Interface\\AddOns\\GamepadReticleOnTarget\\Media\\icon-64.png")
    eq(readFile("Media/icon-64.png"):sub(2, 4), "PNG", "a PNG file")
    eq(readFile(".pkgmeta"):find("- Media/icon-64.png", 1, true), nil, "not left out of the release")
end)

test("debug build: Gamepad Reticle Customizer turned off counts as missing, to see its button; the release doesn't", function()
    local function button()
        for _, initializer in ipairs(game.buttons) do if initializer.name == "Customize the reticle" then return initializer end end
    end
    boot(true, nil, false, { customizerOff = true })
    eq(button() ~= nil, true, "turned off: the button, as players without it see it")
    boot(true, nil, true, { customizerOff = true })
    eq(button(), nil, "the release: installed is installed")
    boot(true, nil, false, { customizerInstalled = true })
    eq(button(), nil, "debug build, turned on: no button")
end)

test("a Get button for each missing sibling, in order, each with its own CurseForge link", function()
    boot(true, nil, false, { enemies = "1", friends = "1", classColors = "1", npcs = "1", minions = "1" })
    local names = {}
    for _, initializer in ipairs(game.buttons) do if initializer.buttonText then names[#names + 1] = initializer.name .. ": " .. initializer.buttonText end end
    eq(table.concat(names, ", "), "Camera over shoulder: Get the addon, Customize the reticle: Get the addon")
    for _, initializer in ipairs(game.buttons) do
        if initializer.name == "Camera over shoulder" then initializer.onClick() end
    end
    eq(_G.GamepadReticleOnTargetPopup.editBox:GetText(), "https://www.curseforge.com/projects/1818297")
end)

-- Hiding health bars and names on friendly NPCs' and pets' nameplates

-- A nameplate on screen for a unit: its UnitFrame with a health bar container and
-- a name, each with an alpha, as the game's.
local function addPlate(unit, kind, barAlpha)
    local function part(startAlpha)
        local region = { alpha = startAlpha or 1 }
        function region:SetAlpha(value) self.alpha = value end
        function region:GetAlpha() return self.alpha end
        return region
    end
    local unitFrame = part(1)
    unitFrame.unit = unit
    unitFrame.HealthBarsContainer = part(barAlpha)
    unitFrame.name = part(1)
    game.nameplates[unit] = { UnitFrame = unitFrame }
    game.unitKinds[unit] = kind
    game.fire("NAME_PLATE_UNIT_ADDED", unit)
    return unitFrame
end
-- "bar name" alphas of a plate, e.g. "0 1".
local function looks(unitFrame) return unitFrame.HealthBarsContainer.alpha .. " " .. unitFrame.name.alpha end
local FRIENDLY_NPC = { reaction = 5 }
local FRIENDLY_PET = { reaction = 5, controlled = true }
local FRIENDLY_PLAYER = { reaction = 5, player = true, controlled = true }
local ENEMY_NPC = { reaction = 2 }
local NEUTRAL_NPC = { reaction = 4 }
local function hideAll() return { hideNpcHealthBars = true, hideNpcNames = true, hidePetHealthBars = true, hidePetNames = true } end

test("all four off by default: every nameplate as the game draws it", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    for _, key in ipairs({ "hideNpcHealthBars", "hideNpcNames", "hidePetHealthBars", "hidePetNames" }) do
        eq(GamepadReticleOnTargetDB[key], false, key)
    end
    eq(looks(addPlate("nameplate1", FRIENDLY_NPC)), "1 1"); eq(looks(addPlate("nameplate2", FRIENDLY_PET)), "1 1")
end)

test("each of the four on its own: only its part, only on its kind of unit", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    local npc, pet = addPlate("nameplate1", FRIENDLY_NPC), addPlate("nameplate2", FRIENDLY_PET)
    set("hideNpcHealthBars", true)
    eq(looks(npc), "0 1", "NPC: bar hidden, name kept"); eq(looks(pet), "1 1", "pet untouched")
    set("hideNpcHealthBars", false); set("hideNpcNames", true)
    eq(looks(npc), "1 0", "NPC: name hidden, bar kept")
    set("hideNpcNames", false); set("hidePetHealthBars", true)
    eq(looks(pet), "0 1", "pet: bar hidden"); eq(looks(npc), "1 1", "NPC untouched")
    set("hidePetHealthBars", false); set("hidePetNames", true)
    eq(looks(pet), "1 0", "pet: name hidden")
    set("hidePetNames", false)
    eq(looks(pet), "1 1"); eq(looks(npc), "1 1")
end)

test("all four on: friendly NPCs and pets fully hidden; players, enemies and neutral ones untouched", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc, pet = addPlate("nameplate1", FRIENDLY_NPC), addPlate("nameplate2", FRIENDLY_PET)
    eq(looks(npc), "0 0"); eq(looks(pet), "0 0")
    eq(npc.alpha, 1, "the nameplate itself untouched")
    eq(looks(addPlate("nameplate3", FRIENDLY_PLAYER)), "1 1", "a friendly player")
    eq(looks(addPlate("nameplate4", ENEMY_NPC)), "1 1", "an enemy")
    eq(looks(addPlate("nameplate5", NEUTRAL_NPC)), "1 1", "a neutral NPC")
end)

test("turned off, a part gets its own alpha back", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc = addPlate("nameplate1", FRIENDLY_NPC, 0.8)
    set("hideNpcHealthBars", false)
    eq(npc.HealthBarsContainer.alpha, 0.8, "its own alpha back"); eq(npc.name.alpha, 0, "the name still hidden")
end)

test("a nameplate going back to the game's pool gets its alphas back; a unit changing sides is checked again", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc = addPlate("nameplate1", FRIENDLY_NPC)
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    eq(looks(npc), "1 1", "given back before the game reuses it")
    local turning = addPlate("nameplate2", FRIENDLY_NPC)
    eq(looks(turning), "0 0")
    game.unitKinds.nameplate2 = ENEMY_NPC
    game.fire("UNIT_FACTION", "nameplate2")
    eq(looks(turning), "1 1", "now an enemy: shown")
end)

test("the reticle still goes on a friendly NPC whose nameplate is fully hidden", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    addPlate("nameplate1", FRIENDLY_NPC)
    game.units.target = true; game.nameplates.target = game.nameplates.nameplate1
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, game.nameplates.nameplate1, "under its nameplate")
end)

test("a nameplate the game locks for addons is left alone", function()
    boot(true, hideAll(), false, allNameplatesOn)
    enterWorld()
    local npc = addPlate("nameplate1", FRIENDLY_NPC)
    npc.HealthBarsContainer.alpha, npc.name.alpha = 1, 1
    function npc:IsForbidden() return true end
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(looks(npc), "1 1", "not touched")
end)

test("Hide companions: a companion's whole nameplate, anyone's; off by default, and the NPC and pet boxes leave it alone", function()
    boot(true, nil, false, allNameplatesOn)
    enterWorld()
    eq(GamepadReticleOnTargetDB.hideCompanions, false)
    local mine = addPlate("nameplate1", { reaction = 5, companion = true })
    local enemyPlayers = addPlate("nameplate2", { reaction = 2, companion = true })
    set("hideNpcHealthBars", true); set("hideNpcNames", true); set("hidePetHealthBars", true); set("hidePetNames", true)
    eq(looks(mine), "1 1", "not an NPC or a pet to the other boxes")
    set("hideCompanions", true)
    eq(looks(mine), "0 0", "bar and name"); eq(looks(enemyPlayers), "0 0", "an enemy player's companion too")
    eq(looks(addPlate("nameplate3", FRIENDLY_NPC)), "0 0", "the NPC boxes still work")
    set("hideCompanions", false)
    eq(looks(mine), "1 1")
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
