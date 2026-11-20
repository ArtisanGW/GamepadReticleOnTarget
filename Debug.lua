-- /grt debug: an in-game test suite. It runs through the settings one step at a
-- time (a step every Debug.SECONDS_BETWEEN_STEPS, so you can watch the reticle
-- move), checks where the reticle actually is, puts your own settings back, and
-- keeps the findings in GamepadReticleOnTargetDebugDB, which the game writes to
-- disk on /reload or logout. Select a target first to check the nameplate part.
--   /grt debug         runs the suite (out of combat)
--   /grt debug last    prints the last run's findings again
--   /grt debug clear   empties the saved runs
-- A fight stops the run (and puts your settings back). If a reload cuts a run
-- short, your settings are put back at the next login.

local ReticleOnTarget = _G.GamepadReticleOnTarget
local Reticle = ReticleOnTarget.Reticle
local Debug = { SECONDS_BETWEEN_STEPS = 0.6, RUNS_KEPT = 10 }
ReticleOnTarget.Debug = Debug

local SETTING_KEYS = { "enabled", "offset" }

local function say(text) print("|cff88ccffgrt debug|r " .. text) end

-- Saved findings and the settings to put back

local function getDebugStore()
    if type(GamepadReticleOnTargetDebugDB) ~= "table" then GamepadReticleOnTargetDebugDB = {} end
    local debugStore = GamepadReticleOnTargetDebugDB
    if type(debugStore.runs) ~= "table" then debugStore.runs = {} end
    return debugStore
end

local function copyCurrentSettings()
    local settings, copy = ReticleOnTarget.GetSettings(), {}
    for _, key in ipairs(SETTING_KEYS) do copy[key] = settings[key] end
    return copy
end

local function restoreSettings(savedCopy)
    local settings = ReticleOnTarget.GetSettings()
    for _, key in ipairs(SETTING_KEYS) do
        if savedCopy[key] ~= nil then settings[key] = savedCopy[key] end
    end
end

-- Checks

local currentRun   -- the run in progress, or nil

local function recordCheck(name, passed, expected, actual, note)
    local result = (passed == nil and "skip") or (passed and "pass") or "fail"
    currentRun.checks[#currentRun.checks + 1] = {
        name = name,
        result = result,
        expected = expected ~= nil and tostring(expected) or nil,
        actual = actual ~= nil and tostring(actual) or nil,
        note = note,
    }
end

local function expectEqual(name, expected, actual)
    recordCheck(name, tostring(actual) == tostring(expected), expected, actual)
end

local function expectNear(name, expected, actual, tolerance)
    local actualNumber = tonumber(actual)
    local passed = actualNumber ~= nil and math.abs(actualNumber - expected) <= (tolerance or 0.01)
    recordCheck(name, passed, expected, actual)
end

local function skipCheck(name, reason) recordCheck(name, nil, nil, nil, reason) end

local function changeSettings(newValues)
    local settings = ReticleOnTarget.GetSettings()
    for key, value in pairs(newValues) do settings[key] = value end
    Reticle.Place()
end

local function canCheckReticle()
    return ReticleOnTarget.IsControllerUIOn() and type(_G.GamepadReticle) == "table"
        and type(GamepadReticle.GetPoint) == "function"
end

local function getReticlePosition()
    local succeeded, _, _, _, x, y = pcall(GamepadReticle.GetPoint, GamepadReticle, 1)
    if succeeded then return x, y end
end

-- With a target, the reticle is on its nameplate; with none, in the middle at
-- the game's aim height (the vertical offset is for targets).
local function checkReticle(label, offsetPixels)
    local name = "reticle at " .. label
    if not canCheckReticle() then return skipCheck(name, "controller UI off") end
    local nameplate = Reticle.TargetNameplate()
    if nameplate then
        -- Anchored to a nameplate, the reticle can't be measured (a restricted
        -- region): the addon's own record of where it put it is checked instead.
        local placement = Reticle.Placement()
        expectEqual(name .. ": on the target's nameplate", true, placement ~= nil
            and placement.anchor == Reticle.VisibleNameplatePart(nameplate))
        return expectNear(name .. ": height from the nameplate",
            -Reticle.BELOW_NAMEPLATE + Reticle.PixelsToFrameUnits(GamepadReticle, offsetPixels),
            placement and placement.height, 1)
    end
    local aimHeight = Reticle.AimHeight(GamepadReticle)
    if not aimHeight then return skipCheck(name, "the game's aim height can't be read") end
    local x, y = getReticlePosition()
    expectNear(name .. ": x, in the middle, where the game aims", 0, x, 1)
    expectNear(name .. ": y, the game's aim height (the vertical offset is for targets)", aimHeight, y, 1)
end

-- The steps, one every SECONDS_BETWEEN_STEPS.

local STEPS = {}
local function addStep(stepFunction) STEPS[#STEPS + 1] = stepFunction end

addStep(function()
    changeSettings({ enabled = true, offset = 0 })
    expectEqual("settings page registered", true, ReticleOnTarget.category ~= nil)
    checkReticle("Default", 0)
end)

for _, offsetPixels in ipairs({ 40, -40, 0 }) do
    addStep(function()
        changeSettings({ offset = offsetPixels })
        checkReticle("vertical offset " .. ReticleOnTarget.OffsetLabel(offsetPixels), offsetPixels)
    end)
end

addStep(function()
    changeSettings({ enabled = false })
    if not canCheckReticle() then return skipCheck("reticle off", "controller UI off") end
    local x = getReticlePosition()
    expectNear("off: back in the middle, where the game puts it", 0, x, 1)
end)

addStep(function()
    changeSettings({ enabled = true })
    checkReticle("on again", 0)
end)

-- The end: a reload writes the findings to disk. Addon code can't call
-- ReloadUI() on this client: the popup's Reload (Popup.lua) is a secure /reload
-- button; in a fight, the popup opens once it's over.
local function showReloadBox(text)
    ReticleOnTarget.Popup.Show({ text = text, buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

-- Results

local function countResults(run)
    local counts = { pass = 0, fail = 0, skip = 0 }
    for _, check in ipairs(run.checks) do counts[check.result] = counts[check.result] + 1 end
    return counts
end

function Debug.PrintRun(run)
    if not run then say("no saved run yet: /grt debug"); return end
    local counts = countResults(run)
    local stoppedNote = run.stopped and (" (stopped: " .. run.stopped .. ")") or ""
    say(string.format("%s: %d passed, %d failed, %d skipped%s", run.time or "?",
        counts.pass, counts.fail, counts.skip, stoppedNote))
    for _, check in ipairs(run.checks) do
        if check.result == "fail" then
            say(string.format("|cffff5555FAIL|r %s: expected %s, got %s",
                check.name, check.expected or "?", check.actual or "nil"))
        end
    end
end

local function finishRun(stopReason)
    local run = currentRun
    currentRun = nil
    run.stopped = stopReason

    local debugStore = getDebugStore()
    if debugStore.settingsToRestore then
        restoreSettings(debugStore.settingsToRestore)
        debugStore.settingsToRestore = nil
    end
    Reticle.Place()

    local counts = countResults(run)
    run.passed, run.failed, run.skipped = counts.pass, counts.fail, counts.skip
    debugStore.runs[#debugStore.runs + 1] = run
    while #debugStore.runs > Debug.RUNS_KEPT do table.remove(debugStore.runs, 1) end

    Debug.PrintRun(run)
    say("your settings are back. /reload writes the findings to GamepadReticleOnTargetDebugDB")
    showReloadBox(string.format("GamepadReticleOnTarget debug: %d passed, %d failed, %d skipped.\n"
        .. "Reload to save the findings (or type /reload).", counts.pass, counts.fail, counts.skip))
end

local function runNextStep()
    if not currentRun then return end
    currentRun.stepNumber = currentRun.stepNumber + 1
    local stepFunction = STEPS[currentRun.stepNumber]
    if not stepFunction then return finishRun() end
    local succeeded, errorMessage = pcall(stepFunction)
    if not succeeded then recordCheck("step " .. currentRun.stepNumber, false, "no error", errorMessage) end
    C_Timer.After(Debug.SECONDS_BETWEEN_STEPS, runNextStep)
end

local function describeEnvironment()
    local environment = {}
    if type(GetBuildInfo) == "function" then
        local succeeded, version, build, _, interfaceVersion = pcall(GetBuildInfo)
        if succeeded then
            environment.version, environment.build, environment.interfaceVersion = version, build, interfaceVersion
        end
    end
    environment.controllerUI = ReticleOnTarget.IsControllerUIOn()
    environment.reticleFound = type(_G.GamepadReticle) == "table"
    environment.hasTarget = Reticle.TargetNameplate() ~= nil
    environment.screenHeight = UIParent:GetHeight()
    environment.uiScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or nil
    environment.settings = copyCurrentSettings()
    return environment
end

function Debug.Start()
    if currentRun then say("already running"); return end
    if InCombatLockdown() then say("not in combat"); return end
    getDebugStore().settingsToRestore = copyCurrentSettings()
    currentRun = {
        time = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
        environment = describeEnvironment(),
        checks = {},
        stepNumber = 0,
    }
    say(string.format("running %d steps, about %d s.", #STEPS, math.ceil(#STEPS * Debug.SECONDS_BETWEEN_STEPS)))
    runNextStep()
end

function Debug.Command(arguments)
    if arguments == "" or arguments == "run" then
        Debug.Start()
    elseif arguments == "last" then
        local runs = getDebugStore().runs
        Debug.PrintRun(runs[#runs])
    elseif arguments == "clear" then
        getDebugStore().runs = {}
        say("saved runs cleared")
    else
        say("/grt debug (run the suite), /grt debug last, /grt debug clear")
    end
end

Debug.eventFrame = CreateFrame("Frame")
Debug.eventFrame:RegisterEvent("PLAYER_LOGIN")
Debug.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
Debug.eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- A reload during a run left the test settings in: put yours back.
        local debugStore = getDebugStore()
        if debugStore.settingsToRestore then
            restoreSettings(debugStore.settingsToRestore)
            debugStore.settingsToRestore = nil
            say("a run was cut short: your settings are back")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if currentRun then finishRun("combat") end
    end
end)
