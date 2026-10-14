repeat task.wait() until game:IsLoaded()
-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if player.UserId ~= 1588829513 then
    return
end

while not player do
    task.wait()
    player = Players.LocalPlayer
end

-- State
local looping = false     -- Candy feed loop
local running = true      -- Master flag for all loops
local connections = {}
local statusLabel = nil   -- Assigned when the GUI is built (declared early so helpers can use it)

-- =========================
-- Settings file (per user, saved in the executor's "Htd" folder)
-- =========================
local SETTINGS_FOLDER = "Htd"
local SETTINGS_FILE = SETTINGS_FOLDER .. "/Settings_" .. tostring(player.UserId) .. ".json"

local function canUseFiles()
    return type(readfile) == "function" and type(writefile) == "function" and type(isfile) == "function"
end

-- Reads the saved settings table, or an empty table if there isn't one yet
local function readSettingsFile()
    if not canUseFiles() then return {} end
    local okExists, exists = pcall(isfile, SETTINGS_FILE)
    if not okExists or not exists then return {} end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(SETTINGS_FILE))
    end)
    if ok and type(data) == "table" then
        return data
    end
    return {}
end

-- Writes the settings table to the per-user file, creating the folder if needed
local function writeSettingsFile(data)
    if not canUseFiles() or type(writefile) ~= "function" then return end

    if type(makefolder) == "function" and type(isfolder) == "function" then
        local okFolder, folderExists = pcall(isfolder, SETTINGS_FOLDER)
        if okFolder and not folderExists then
            pcall(makefolder, SETTINGS_FOLDER)
        end
    end

    local ok, err = pcall(function()
        writefile(SETTINGS_FILE, HttpService:JSONEncode(data))
    end)
    if not ok then
        warn("[Candy Loop] Failed to save settings: " .. tostring(err))
    end
end

local savedSettings = readSettingsFile()

-- Returns the saved boolean for a key, or the default if it's missing
local function readSetting(key, default)
    local v = savedSettings[key]
    if type(v) == "boolean" then
        return v
    end
    return default
end

-- =========================
-- Decision settings
-- =========================
local LOBBY_PLACE_ID = 131367064230486
local LOADSTRING_URL = "https://raw.githubusercontent.com/lghft/Current/refs/heads/main/House/EventMisc/Halloween/autoWorldBoss.lua"  -- Runs once, only outside the lobby when nothing is ready
local WORLDBOSS_INTERVAL = 5    -- Minimum seconds between WorldBossEnter fires
local UNKNOWN_TIMEOUT = 15      -- Seconds a system can stay "unknown" before it's treated as not ready
local lastWorldBossFire = 0
local autoWorldBossEnabled = true   -- Auto WorldBoss toggle: gates the world boss remote and the loadstring fallback

-- =========================
-- Candy feed
-- =========================
local function getPrompt()
    local halloweenTown = workspace:FindFirstChild("HalloweenTown")
    if not halloweenTown then return nil end
    local unitShowcase = halloweenTown:FindFirstChild("UnitShowcase")
    if not unitShowcase then return nil end
    local fountain = unitShowcase:FindFirstChild("Fountain")
    if not fountain then return nil end
    local tossSpot = fountain:FindFirstChild("TossSpot")
    if not tossSpot then return nil end
    local promptSpot = tossSpot:FindFirstChild("PromptSpot")
    if not promptSpot then return nil end

    return promptSpot:FindFirstChild("TossCandy")
end

-- =========================
-- Shared helpers
-- =========================
local function round(num)
    return math.floor(num + 0.5)
end

local function getRoot()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- True once the game has loaded, the character exists, and the PlayerGui is ready
local function isGameReady()
    if not game:IsLoaded() then return false end
    if not player:FindFirstChild("PlayerGui") then return false end
    local char = player.Character
    return char ~= nil and char:FindFirstChild("HumanoidRootPart") ~= nil
end

-- Waits until the game is ready, then a short settle time so the teleport overlay has cleared.
-- Returns false if the timeout hits.
local function waitForGameReady(timeout)
    local deadline = os.clock() + (timeout or 60)
    while running and os.clock() < deadline do
        if isGameReady() then
            task.wait(2)
            if isGameReady() then
                return true
            end
        end
        task.wait(0.5)
    end
    return false
end

-- True while Roblox is showing the "Gameplay Paused" overlay (e.g. after a long teleport)
local function isGameplayPaused()
    local ok, paused = pcall(function()
        return player.GameplayPaused
    end)
    if ok and type(paused) == "boolean" then
        return paused
    end

    -- Fallback: look for a visible "Gameplay Paused" label in PlayerGui
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Visible
                and (obj.Text or ""):lower():find("gameplay paused", 1, true) then
                return true
            end
        end
    end
    return false
end

-- Waits until the pause overlay is gone. Returns false if the timeout hits or the script is unloaded.
local function waitForGameplayResumed(timeout)
    local deadline = os.clock() + (timeout or 30)
    while running and isGameplayPaused() and os.clock() < deadline do
        task.wait(0.1)
    end
    return running and not isGameplayPaused()
end

local function formatLeft(seconds)
    local v = math.max(0, math.floor(seconds))
    local h = v // 3600
    local m = v % 3600 // 60
    local s = v % 60
    if h > 0 then
        return string.format("%dh %02dm", h, m)
    end
    if m > 0 then
        return string.format("%dm %02ds", m, s)
    end
    return string.format("%ds", s)
end

-- Instant teleport, used for route entrances and as a fallback when pathing gets stuck
local function teleportTo(pos)
    local root = getRoot()
    if root then
        root.CFrame = CFrame.new(pos)
    end
end

-- Equips an item by firing the holding-item remote
local function setHolding(itemName)
    local ok, err = pcall(function()
        ReplicatedStorage.Modules.Remotes.RemoteEvent.SetHoldingItem:FireServer(itemName)
    end)
    if not ok then
        warn("[Candy Loop] Failed to equip " .. tostring(itemName) .. ": " .. tostring(err))
    end
end

local function equipScythe()
    setHolding("PlayerScythe9")
end

local function equipShovel()
    setHolding("GraveShovel")
end

local function inLobby()
    return game.PlaceId == LOBBY_PLACE_ID
end

-- Launches the lobby experience. Tries the service through FindService first,
-- then GetService, since the plain GetService call returned nil in this context.
local function goToLobby()
    local service = game:FindService("ExperienceService")
    if not service then
        local ok, result = pcall(function()
            return game:GetService("ExperienceService")
        end)
        if ok then
            service = result
        end
    end

    if not service then
        warn("[Candy Loop] ExperienceService is not available in this script's context")
        return false
    end

    local ok, err = pcall(function()
        service:LaunchExperience({
            placeId = LOBBY_PLACE_ID,
        })
    end)
    if not ok then
        warn("[Candy Loop] Failed to teleport to lobby: " .. tostring(err))
    end
    return ok
end

-- Fires the world boss enter remote, throttled so it isn't spammed
local function tryWorldBossEnter()
    if os.clock() - lastWorldBossFire < WORLDBOSS_INTERVAL then return end
    lastWorldBossFire = os.clock()
    local ok, err = pcall(function()
        ReplicatedStorage.Modules.Remotes.RemoteEvent.WorldBossEnter:FireServer()
    end)
    if not ok then
        warn("[Candy Loop] WorldBossEnter failed: " .. tostring(err))
    end
end

-- Runs the loadstring URL once per game session, even if this script is executed again.
-- The flag lives in the executor's global environment so it survives re-execution.
local function runLoadstringOnce()
    local env = (getgenv and getgenv()) or _G
    if env.CANDY_LOADSTRING_RAN or LOADSTRING_URL == "" then return end
    env.CANDY_LOADSTRING_RAN = true

    local ok, err = pcall(function()
        loadstring(game:HttpGet(LOADSTRING_URL))()
    end)
    if not ok then
        warn("[Candy Loop] loadstring failed: " .. tostring(err))
    end
end

-- Walks to a position and waits until it arrives, times out, or isEnabled() goes false
local function walkTo(pos, timeout, isEnabled)
    local humanoid = getHumanoid()
    local root = getRoot()
    if not humanoid or not root then return false end

    humanoid:MoveTo(pos)
    local deadline = os.clock() + (timeout or 5)

    while isEnabled() and os.clock() < deadline do
        if (root.Position - pos).Magnitude <= 4 then
            return true
        end
        task.wait(0.1)
    end

    return false
end

-- Horizontal (XZ) distance from the root to a point, ignoring height
local function horizDistTo(root, pos)
    local dx = root.Position.X - pos.X
    local dz = root.Position.Z - pos.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- =========================
-- Pumpkin auto
-- Walks the waypoints in order. At each waypoint it services the two plots assigned to it:
-- pick Carved, plant Empty, and carve Grown (pathing to each plot, teleporting if stuck).
-- The route only moves on once both plots at a waypoint are no longer ready.
-- =========================
local PUMPKIN_CONFIG = {
    ENABLED = true,
    AUTO_PLANT = true,
    AUTO_CARVE = true,
    AUTO_PICK = true,
    ROUTE_COOLDOWN = 0.5,
    SWIPE_SETTLE = 0.05,      -- Short pause so the swipe reaches the server before the carves
    SETTLE_WAIT = 0.15,       -- Pause after a pass before checking whether anything changed
    BATCH_TIMEOUT = 5,        -- Max seconds to wait for one parallel batch
    CARVE_RANGE = 18,         -- Must match the server's CARVE_RANGE
    STOP_TIMEOUT = 25,        -- Max seconds to spend servicing the plots at one waypoint
    PATH_TIMEOUT = 10,        -- Max seconds to spend pathing to one target before teleporting
    PATH_RETRIES = 3,         -- Recompute the path this many times if a waypoint is blocked
    WAYPOINT_TIMEOUT = 4,     -- Max seconds to reach one path waypoint before treating it as blocked
    DEBUG = true,             -- Prints pumpkin path status to the console
    STALL_WAIT = 30,          -- If a pass changes nothing, wait before trying again
    MAX_PLOTS = 8,
    TELEPORT_POS = Vector3.new(3506, 272, -456),
    TELEPORT_RANGE = 60,      -- Only teleport to the patch entrance if we're farther than this from it
    ROUTE = {
        { pos = Vector3.new(3535, 272, -456), slots = {1, 2} },
        { pos = Vector3.new(3555, 272, -456), slots = {3, 4} },
        { pos = Vector3.new(3574, 272, -455), slots = {5, 6} },
        { pos = Vector3.new(3595, 272, -455), slots = {7, 8} },
    },
}

local GROWING_STATE = "Growing"

local pumpkinState = {
    initialized = false,
    pumpkinGarden = nil,
    pumpkinModule = nil,
    stalledUntil = 0,
}

-- Logs pumpkin pathing details when PUMPKIN_CONFIG.DEBUG is on
local function pumpkinLog(...)
    if PUMPKIN_CONFIG.DEBUG then
        print("[Candy Loop][Pumpkin]", ...)
    end
end

-- Remotes are looked up separately from the module, so a missing remote
-- doesn't stop the garden data (and the stats) from loading.
local PumpkinGarden, ScytheSwipe

do
    local okRF, RemoteFunction = pcall(function()
        return require(ReplicatedStorage.Modules.Remotes.RemoteFunction)
    end)
    if okRF and RemoteFunction then
        local okPG, pg = pcall(function()
            return RemoteFunction.new("PumpkinGarden")
        end)
        if okPG then PumpkinGarden = pg end
    end

    local okSwipe, swipe = pcall(function()
        return ReplicatedStorage.Modules.Remotes.RemoteEvent:FindFirstChild("ScytheSwipe")
    end)
    if okSwipe then ScytheSwipe = swipe end
end

local function invokeGarden(action, slot)
    if not pumpkinState.pumpkinGarden then return { ok = false } end
    local ok, success, data = pcall(function()
        return pumpkinState.pumpkinGarden:Invoke(action, slot):await()
    end)
    if ok and success and type(data) == "table" then
        return data
    end
    return { ok = false }
end

local function initPumpkinModule()
    local ok, pumpkinModule = pcall(function()
        return require(ReplicatedStorage.Modules.PumpkinPatch)
    end)
    if not ok or type(pumpkinModule) ~= "table" then return false end

    pumpkinState.pumpkinModule = pumpkinModule
    pcall(function()
        if pumpkinModule.Start then
            pumpkinModule.Start()
        end
    end)

    pumpkinState.pumpkinGarden = PumpkinGarden
    pumpkinState.initialized = true
    return true
end

local function getPumpkinGardenState()
    local pumpkinModule = pumpkinState.pumpkinModule
    if not pumpkinModule or not pumpkinModule.atom then return nil end
    local ok, gardenState = pcall(function()
        return pumpkinModule.atom()
    end)
    if ok then return gardenState end
    return nil
end

local function getSlotState(slot)
    local pumpkinModule = pumpkinState.pumpkinModule
    local gardenState = getPumpkinGardenState()
    if not pumpkinModule or not gardenState then
        return "Unknown"
    end
    local ok, st = pcall(function()
        return pumpkinModule.slotState(gardenState, slot)
    end)
    if not ok or not st then
        return "Unknown"
    end
    return st
end

-- Reads readyAt from the PumpkinPatch module's data (same source the module uses for "Ready in")
local function getPumpkinReadyAt(gardenState, slot)
    if type(gardenState) ~= "table" or type(gardenState.plots) ~= "table" then return nil end
    local plot = gardenState.plots[tostring(slot)]
    if type(plot) == "table" and type(plot.readyAt) == "number" then
        return plot.readyAt
    end
    return nil
end

local function getGrowPoint(slot)
    for _, plot in ipairs(CollectionService:GetTagged("PumpkinPlot")) do
        if plot:GetAttribute("GardenSlot") == slot then
            local soil = plot:FindFirstChild("Soil")
            return soil and soil:FindFirstChild("GrowPoint")
        end
    end
    return nil
end

-- Distance from the character to a grow point (huge if there's no character)
local function distToPlot(growPoint)
    local root = getRoot()
    if not root then return math.huge end
    return (root.Position - growPoint.WorldPosition).Magnitude
end

local function inCarveRange(growPoint)
    return distToPlot(growPoint) <= PUMPKIN_CONFIG.CARVE_RANGE
end

-- Reads the garden once and returns every slot's state, so a pass doesn't re-read per slot
local function snapshotStates()
    local states = {}
    local pumpkinModule = pumpkinState.pumpkinModule
    local gardenState = getPumpkinGardenState()
    for slot = 1, PUMPKIN_CONFIG.MAX_PLOTS do
        local st = "Unknown"
        if pumpkinModule and gardenState then
            local ok, result = pcall(pumpkinModule.slotState, gardenState, slot)
            if ok and result then st = result end
        end
        states[slot] = st
    end
    return states
end

-- Runs fn(item) for every item at the same time, then waits until they've all returned (or timed out)
local function runParallel(items, fn)
    if #items == 0 then return end
    local remaining = #items
    for _, item in ipairs(items) do
        task.spawn(function()
            pcall(fn, item)
            remaining = remaining - 1
        end)
    end
    local deadline = os.clock() + PUMPKIN_CONFIG.BATCH_TIMEOUT
    while remaining > 0 and os.clock() < deadline do
        task.wait()
    end
end

-- Formats a list of slot numbers for the status label, e.g. "2, 5"
local function slotList(slots)
    local parts = {}
    for i, slot in ipairs(slots) do
        parts[i] = tostring(slot)
    end
    return table.concat(parts, ", ")
end

-- Shows the current pumpkin action and the plots it's working on
local function setPumpkinStatus(text, color)
    if statusLabel then
        statusLabel.Text = "Status: Pumpkin - " .. text
        statusLabel.TextColor3 = color or Color3.fromRGB(140, 255, 120)
    end
end

-- True for a plot state that needs an action from the script
local function isActionable(st)
    return (st == "Grown" and PUMPKIN_CONFIG.AUTO_CARVE)
        or (st == "Carved" and PUMPKIN_CONFIG.AUTO_PICK)
        or (st == "Empty" and PUMPKIN_CONFIG.AUTO_PLANT)
end

-- Paths to targetPos with PathfindingService, recomputing if a waypoint is blocked.
-- Returns true as soon as isDone() is true, or false if it runs out of retries or time.
local function pathTo(targetPos, isDone, timeout, label)
    local deadline = os.clock() + timeout

    for attempt = 1, PUMPKIN_CONFIG.PATH_RETRIES do
        if isDone() then return true end
        if not PUMPKIN_CONFIG.ENABLED or os.clock() > deadline then return false end

        local humanoid = getHumanoid()
        local root = getRoot()
        if not humanoid or not root then return false end

        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
        })

        local computed = pcall(function()
            path:ComputeAsync(root.Position, targetPos)
        end)

        pumpkinLog(label, "path attempt " .. attempt, "computed=" .. tostring(computed),
            "status=" .. (computed and path.Status.Name or "error"))

        if computed and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            local blocked = false

            -- Waypoint 1 is the start position, so begin at 2
            for i = 2, #waypoints do
                if isDone() then return true end
                if not PUMPKIN_CONFIG.ENABLED or os.clock() > deadline or not root.Parent then
                    return false
                end

                local wp = waypoints[i]
                if wp.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end

                humanoid:MoveTo(wp.Position)

                local wpDeadline = os.clock() + PUMPKIN_CONFIG.WAYPOINT_TIMEOUT
                local reached = false
                while PUMPKIN_CONFIG.ENABLED and os.clock() < wpDeadline do
                    if isDone() then return true end
                    if horizDistTo(root, wp.Position) <= 4 then
                        reached = true
                        break
                    end
                    task.wait(0.1)
                end

                if not reached then
                    blocked = true
                    pumpkinLog(label, "waypoint " .. i .. " blocked")
                    break
                end
            end

            if not blocked and isDone() then return true end
        end

        task.wait(0.3)
    end

    return isDone()
end

-- Paths to a plot until it's in carve range. Teleports next to the plot if pathing gets stuck.
local function pathToPlot(slot, growPoint)
    setPumpkinStatus("Pathing to plot " .. slot, Color3.fromRGB(255, 205, 70))

    local reached = pathTo(growPoint.WorldPosition, function()
        return inCarveRange(growPoint)
    end, PUMPKIN_CONFIG.PATH_TIMEOUT, "plot " .. slot)

    if not reached and PUMPKIN_CONFIG.ENABLED and not inCarveRange(growPoint) then
        pumpkinLog("plot " .. slot .. " pathing stuck, teleporting to plot")
        setPumpkinStatus("Teleporting to plot " .. slot, Color3.fromRGB(255, 205, 70))
        teleportTo(growPoint.WorldPosition + Vector3.new(0, 3, 0))
        task.wait(0.15)
    end

    return inCarveRange(growPoint)
end

-- Walks to a waypoint's position. Teleports there if pathing gets stuck.
local function walkToWaypoint(stopIdx, stop)
    local target = stop.pos
    local function arrived()
        local r = getRoot()
        return r ~= nil and horizDistTo(r, target) <= 4
    end

    setPumpkinStatus("Going to waypoint " .. stopIdx .. " (plots " .. slotList(stop.slots) .. ")",
        Color3.fromRGB(255, 205, 70))

    local reached = pathTo(target, arrived, PUMPKIN_CONFIG.PATH_TIMEOUT, "waypoint " .. stopIdx)

    if not reached and PUMPKIN_CONFIG.ENABLED and not arrived() then
        pumpkinLog("waypoint " .. stopIdx .. " pathing stuck, teleporting")
        teleportTo(target)
        task.wait(0.15)
    end
end

-- Services the two plots assigned to a waypoint until neither needs an action,
-- or the stop times out. Picks Carved, plants Empty, and carves Grown.
local function servicePlots(stop)
    local deadline = os.clock() + PUMPKIN_CONFIG.STOP_TIMEOUT

    while PUMPKIN_CONFIG.ENABLED and os.clock() < deadline do
        local states = snapshotStates()
        local carved, empty, grown = {}, {}, {}

        for _, slot in ipairs(stop.slots) do
            local st = states[slot]
            if st == "Carved" and PUMPKIN_CONFIG.AUTO_PICK then
                table.insert(carved, slot)
            elseif st == "Empty" and PUMPKIN_CONFIG.AUTO_PLANT then
                table.insert(empty, slot)
            elseif st == "Grown" and PUMPKIN_CONFIG.AUTO_CARVE then
                table.insert(grown, slot)
            end
        end

        if #carved + #empty + #grown == 0 then
            return true
        end

        if #carved > 0 then
            setPumpkinStatus("Picking plot" .. (#carved > 1 and "s " or " ") .. slotList(carved))
            runParallel(carved, function(slot)
                invokeGarden("pick", slot)
            end)
        end

        if #empty > 0 then
            setPumpkinStatus("Planting plot" .. (#empty > 1 and "s " or " ") .. slotList(empty))
            runParallel(empty, function(slot)
                invokeGarden("plant", slot)
            end)
        end

        if #grown > 0 then
            -- Path to any grown plot that's out of carve range
            for _, slot in ipairs(grown) do
                if not PUMPKIN_CONFIG.ENABLED then return false end
                local gp = getGrowPoint(slot)
                if gp and not inCarveRange(gp) then
                    pathToPlot(slot, gp)
                end
            end

            -- Carve everything that's in range now, with one swipe
            local inRange = {}
            for _, slot in ipairs(grown) do
                local gp = getGrowPoint(slot)
                if gp and inCarveRange(gp) then
                    table.insert(inRange, { slot = slot, growPoint = gp })
                end
            end

            if #inRange > 0 then
                local carveSlots = {}
                for _, g in ipairs(inRange) do
                    table.insert(carveSlots, g.slot)
                end
                setPumpkinStatus("Carving plot" .. (#carveSlots > 1 and "s " or " ") .. slotList(carveSlots))

                if ScytheSwipe then
                    ScytheSwipe:FireServer(inRange[1].growPoint.WorldPosition)
                    task.wait(PUMPKIN_CONFIG.SWIPE_SETTLE)
                end

                runParallel(inRange, function(g)
                    invokeGarden("carve", g.slot)
                end)
            end
        end

        task.wait(0.15)
    end

    return false
end

-- Teleports to the patch if needed, waits for the "Gameplay Paused" overlay to clear, equips the
-- scythe, then visits each waypoint in order and services its plots. Only stalls when work was
-- attempted and nothing changed, so walking between waypoints doesn't count as a failed pass.
local function runPumpkinRoute()
    local before = table.concat(snapshotStates(), ",")

    local root = getRoot()
    if not root or (root.Position - PUMPKIN_CONFIG.TELEPORT_POS).Magnitude > PUMPKIN_CONFIG.TELEPORT_RANGE then
        teleportTo(PUMPKIN_CONFIG.TELEPORT_POS)
        task.wait(0.15)
    end

    if statusLabel then
        statusLabel.Text = "Status: Pumpkin - Waiting for gameplay to resume"
        statusLabel.TextColor3 = Color3.fromRGB(255, 205, 70)
    end
    if not waitForGameplayResumed(30) then
        return
    end

    equipScythe()

    local attempted = false

    for stopIdx, stop in ipairs(PUMPKIN_CONFIG.ROUTE) do
        if not PUMPKIN_CONFIG.ENABLED then return end

        -- Skip waypoints whose plots don't need anything right now
        local states = snapshotStates()
        local hasWork = false
        for _, slot in ipairs(stop.slots) do
            if isActionable(states[slot]) then
                hasWork = true
            end
        end

        if hasWork then
            attempted = true
            walkToWaypoint(stopIdx, stop)
            if not PUMPKIN_CONFIG.ENABLED then return end
            servicePlots(stop)
        end
    end

    task.wait(PUMPKIN_CONFIG.SETTLE_WAIT)

    if attempted and table.concat(snapshotStates(), ",") == before then
        pumpkinState.stalledUntil = os.clock() + PUMPKIN_CONFIG.STALL_WAIT
    end
end

-- =========================
-- Graveyard auto (route based)
-- =========================
-- Each stop digs the two graves listed for it. Walks to any grave that's out of dig range.
local GRAVE_CONFIG = {
    ENABLED = true,
    ROUTE_COOLDOWN = 2,
    STEP_WAIT = 0.25,
    WAIT_TIMEOUT = 20,        -- Dig time is about 2.6s per grave, so give each stop room
    STALL_WAIT = 30,
    MAX_GRAVES = 8,
    DIG_RANGE = 20,           -- Server allows 22, stay a bit under it
    TELEPORT_POS = Vector3.new(1786, 271, -2600),
    ROUTE = {
        { pos = Vector3.new(1754, 272, -2600), graves = {1, 2} },
        { pos = Vector3.new(1736, 272, -2600), graves = {3, 4} },
        { pos = Vector3.new(1718, 272, -2600), graves = {5, 6} },
        { pos = Vector3.new(1700, 272, -2600), graves = {7, 8} },
    },
}

local graveState = {
    initialized = false,
    module = nil,
    remote = nil,
    stalledUntil = 0,
}

local function initGraveModule()
    local ok, graveModule = pcall(function()
        return require(ReplicatedStorage.Modules.GraveyardDig)
    end)
    if not ok or not graveModule or not graveModule.atom then return false end

    local okRemote, remote = pcall(function()
        local RF = require(ReplicatedStorage.Modules.Remotes.RemoteFunction)
        return RF.new("GraveyardDig")
    end)
    if not okRemote or not remote then return false end

    graveState.module = graveModule
    graveState.remote = remote
    graveState.initialized = true
    return true
end

local function invokeGrave(action, slot)
    local ok, success, data = pcall(function()
        return graveState.remote:Invoke(action, slot):await()
    end)
    if ok and success and type(data) == "table" then
        return data
    end
    return { ok = false }
end

local function getGravePlayerData()
    local graveModule = graveState.module
    if not graveModule then return nil end
    local ok, playerData = pcall(function()
        return graveModule.atom()
    end)
    if ok then return playerData end
    return nil
end

local function getGraveStatus(slot)
    local graveModule = graveState.module
    local playerData = getGravePlayerData()
    if not graveModule or not playerData then return "Unknown" end
    local ok, st = pcall(function()
        return graveModule.graveState(playerData, slot)
    end)
    if not ok or not st then return "Unknown" end
    return st
end

local function getDigPoint(slot)
    for _, plot in ipairs(CollectionService:GetTagged("GravePlot")) do
        if plot:GetAttribute("GraveSlot") == slot and plot:IsDescendantOf(workspace) then
            local soil = plot:FindFirstChild("Soil")
            return soil and soil:FindFirstChild("DigPoint")
        end
    end
    return nil
end

local function hasShovel()
    local ok, count = pcall(function()
        return require(ReplicatedStorage.Modules.Inventory).countId("GraveShovel")
    end)
    return ok and count and count > 0
end

local function anyGraveRefilling()
    for slot = 1, GRAVE_CONFIG.MAX_GRAVES do
        if getGraveStatus(slot) == "Refilling" then
            return true
        end
    end
    return false
end

-- Digs the listed graves at a stop. If a grave is out of dig range, walks to it first.
-- Returns when none of the listed graves are ready anymore, or the timeout hits.
local function tendGraves(graveSlots)
    local deadline = os.clock() + GRAVE_CONFIG.WAIT_TIMEOUT
    local function enabled() return GRAVE_CONFIG.ENABLED end

    while enabled() and os.clock() < deadline do
        if not hasShovel() then return false end

        local pending = false
        for _, slot in ipairs(graveSlots) do
            if getGraveStatus(slot) == "Ready" then
                pending = true
                if statusLabel then
                    statusLabel.Text = "Status: Graveyard - Digging grave " .. slot
                    statusLabel.TextColor3 = Color3.fromRGB(140, 255, 120)
                end

                local dp = getDigPoint(slot)
                local root = getRoot()

                if dp and root then
                    if (root.Position - dp.WorldPosition).Magnitude > GRAVE_CONFIG.DIG_RANGE then
                        walkTo(dp.WorldPosition, 5, enabled)
                        root = getRoot()
                    end

                    if root and (root.Position - dp.WorldPosition).Magnitude <= GRAVE_CONFIG.DIG_RANGE then
                        invokeGrave("dig", slot)
                    end
                end
            end
        end

        if not pending then
            return true
        end

        task.wait(GRAVE_CONFIG.STEP_WAIT)
    end

    return false
end

-- Teleports to the graveyard entrance, equips the shovel, walks each stop and digs its graves,
-- then equips the scythe once every stop is finished.
local function runGraveRoute()
    teleportTo(GRAVE_CONFIG.TELEPORT_POS)
    task.wait(0.3)
    equipShovel()
    task.wait(0.3)

    local function enabled() return GRAVE_CONFIG.ENABLED end

    for stopIdx, stop in ipairs(GRAVE_CONFIG.ROUTE) do
        if not GRAVE_CONFIG.ENABLED then return end

        local gravesText = table.concat(stop.graves, ", ")
        if statusLabel then
            statusLabel.Text = "Status: Graveyard route - Stop " .. stopIdx .. "/4 (Graves: " .. gravesText .. ")"
            statusLabel.TextColor3 = Color3.fromRGB(140, 255, 120)
        end

        walkTo(stop.pos, 5, enabled)
        tendGraves(stop.graves)
    end

    equipScythe()

    if not anyGraveRefilling() then
        graveState.stalledUntil = os.clock() + GRAVE_CONFIG.STALL_WAIT
    end
end

-- =========================
-- Trick or Treat auto (pathfinding)
-- =========================
local TRICK_CONFIG = {
    ENABLED = true,           -- Starts ON
    ROUTE_COOLDOWN = 2,
    START_POS = Vector3.new(833, 383, 215),  -- Teleported to once at the start of each trick route
    KNOCK_GAP = 2,            -- Pause after each knock so the outcome can play out
    APPROACH_DIST = 2.5,      -- How far in front of the door to stand
    PATH_RETRIES = 3,         -- Recompute the path this many times before giving up on a door
    WAYPOINT_TIMEOUT = 4,     -- Max seconds to reach one waypoint before treating it as blocked
    RESULT_TIMEOUT = 6,       -- Max seconds to wait for the door text to change after a knock
    READY_TEXT = "trick or treat",
    DEBUG = true,             -- Prints path status and door info to the console
}

local function trickLog(...)
    if TRICK_CONFIG.DEBUG then
        print("[Candy Loop][Trick]", ...)
    end
end

-- True when a door prompt shows the knockable text
local function isReadyText(text)
    return (text or ""):lower():find(TRICK_CONFIG.READY_TEXT, 1, true) ~= nil
end

-- Works for both BasePart doors and Model doors. Returns a CFrame for the door, or nil.
local function getDoorCFrame(door)
    if door:IsA("BasePart") then
        return door.CFrame
    elseif door:IsA("Model") then
        return door:GetPivot()
    end
    return nil
end

local function getDoorPosition(door)
    local cf = getDoorCFrame(door)
    return cf and cf.Position
end

-- Doors whose Knock prompt says "Trick or Treat?"
local function getReadyDoors()
    local list = {}
    local folder = workspace:FindFirstChild("TrickOrTreatDoors")
    if not folder then return list end

    for _, door in ipairs(folder:GetChildren()) do
        if door:IsA("BasePart") or door:IsA("Model") then
            local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and isReadyText(prompt.ObjectText) then
                table.insert(list, door)
            end
        end
    end
    return list
end

-- Horizontal distance, so height differences don't affect arrival checks
local function flatDist(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- Waits until the root is within radius of pos, or times out
local function waitNear(root, pos, radius, timeout, isEnabled)
    local deadline = os.clock() + timeout
    while isEnabled() and os.clock() < deadline do
        if not root.Parent then return false end
        if flatDist(root.Position, pos) <= radius then
            return true
        end
        task.wait(0.1)
    end
    return false
end

-- Walks to endPos using PathfindingService so the character goes around walls.
-- Recomputes the path if a waypoint is blocked.
local function followPath(endPos)
    local function enabled() return TRICK_CONFIG.ENABLED end

    for attempt = 1, TRICK_CONFIG.PATH_RETRIES do
        if not enabled() then return false end

        local humanoid = getHumanoid()
        local root = getRoot()
        if not humanoid or not root then return false end

        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
        })

        local computed = pcall(function()
            path:ComputeAsync(root.Position, endPos)
        end)

        trickLog("path attempt " .. attempt, "computed=" .. tostring(computed),
            "status=" .. (computed and path.Status.Name or "error"))

        if computed and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            local blocked = false

            -- Waypoint 1 is the start position, so begin at 2
            for i = 2, #waypoints do
                if not enabled() or not root.Parent then return false end

                local wp = waypoints[i]
                if wp.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end

                humanoid:MoveTo(wp.Position)
                if not waitNear(root, wp.Position, 4, TRICK_CONFIG.WAYPOINT_TIMEOUT, enabled) then
                    blocked = true
                    trickLog("waypoint " .. i .. " blocked")
                    break
                end
            end

            if not blocked and flatDist(root.Position, endPos) <= 5 then
                return true
            end
        end

        task.wait(0.5)
    end

    return false
end

-- Walks to a door and presses its Knock prompt. Returns true if the door text changed.
local function knockDoor(door)
    local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
    local root = getRoot()
    local doorCF = getDoorCFrame(door)
    if not prompt or not root or not doorCF then
        trickLog("knock aborted: missing prompt, root, or door pivot")
        return false
    end

    -- Stand in front of the door, at ground level
    local front = doorCF.Position + doorCF.LookVector * TRICK_CONFIG.APPROACH_DIST
    local target = Vector3.new(front.X, root.Position.Y, front.Z)

    if statusLabel then
        statusLabel.Text = "Status: Trick or Treat - Approaching door at (" .. round(doorCF.Position.X) .. ", " .. round(doorCF.Position.Z) .. ")"
        statusLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
    end

    if not followPath(target) then
        trickLog("no path to door at", doorCF.Position, "- using direct move")

        -- Pathfinding failed (no route, or stuck on a roof), so move directly
        local r = getRoot()
        if r then
            r.CFrame = CFrame.new(target)
            task.wait(0.5)
        end
    end

    if not TRICK_CONFIG.ENABLED then return false end

    if statusLabel then
        statusLabel.Text = "Status: Trick or Treat - Knocking door at (" .. round(doorCF.Position.X) .. ", " .. round(doorCF.Position.Z) .. ")"
        statusLabel.TextColor3 = Color3.fromRGB(140, 255, 120)
    end

    trickLog("firing prompt on door at", doorCF.Position)
    fireproximityprompt(prompt)

    local deadline = os.clock() + TRICK_CONFIG.RESULT_TIMEOUT
    while TRICK_CONFIG.ENABLED and os.clock() < deadline and isReadyText(prompt.ObjectText) do
        task.wait(0.2)
    end

    local changed = not isReadyText(prompt.ObjectText)
    trickLog("knock result changed=" .. tostring(changed))
    return changed
end

-- Teleports to the trick or treat start point, then knocks every ready door, nearest first,
-- until none are left
local function runTrickRoute()
    teleportTo(TRICK_CONFIG.START_POS)
    task.wait(0.3)

    local failed = {}
    local humanoid = getHumanoid()
    local originalSpeed = humanoid and humanoid.WalkSpeed or 16

    if humanoid then
        humanoid.WalkSpeed = 43
    end

    local lastPos = getRoot() and getRoot().Position or Vector3.new(0, 0, 0)
    local lastPosTime = os.clock()

    while TRICK_CONFIG.ENABLED do
        local root = getRoot()
        if not root then
            if humanoid then
                humanoid.WalkSpeed = originalSpeed
            end
            return
        end

        -- Timeout: if player hasn't moved in 15 seconds and doors remain, reset
        if os.clock() - lastPosTime >= 15 then
            if flatDist(root.Position, lastPos) < 2 then  -- Hasn't moved significantly
                local doors = getReadyDoors()
                if #doors > 0 then
                    print("[Candy Loop] Trick: Player stuck for 15 seconds, retrying...")
                    if statusLabel then
                        statusLabel.Text = "Status: Stuck, retrying trick or treat..."
                        statusLabel.TextColor3 = Color3.fromRGB(255, 205, 70)
                    end
                    lastPos = root.Position
                    lastPosTime = os.clock()
                    task.wait(0.5)
                    continue
                end
            end
            lastPos = root.Position
            lastPosTime = os.clock()
        end

        local best, bestDist
        local doorsCount = 0
        for _, door in ipairs(getReadyDoors()) do
            doorsCount = doorsCount + 1
            if not failed[door] then
                local pos = getDoorPosition(door)
                if pos then
                    local d = flatDist(pos, root.Position)
                    if not bestDist or d < bestDist then
                        best, bestDist = door, d
                    end
                end
            end
        end

        if not best then
            trickLog("no ready doors left (ready=" .. doorsCount .. ", failed=" .. #failed .. ")")
            if humanoid then
                humanoid.WalkSpeed = originalSpeed
            end
            return
        end

        local bestPos = getDoorPosition(best)
        local doorX = round(bestPos.X)
        local doorZ = round(bestPos.Z)
        local distance = round(bestDist)
        if statusLabel then
            statusLabel.Text = "Status: Going to door at (" .. doorX .. ", " .. doorZ .. ") - Distance: " .. distance .. "studs [" .. doorsCount .. " left]"
            statusLabel.TextColor3 = Color3.fromRGB(140, 255, 120)
        end

        if not knockDoor(best) then
            failed[best] = true
        end

        task.wait(TRICK_CONFIG.KNOCK_GAP or 0)
    end

    if humanoid then
        humanoid.WalkSpeed = originalSpeed
    end
end

-- =========================
-- Ready check
-- =========================
-- Each system reports one of three states:
--   "ready"    - it has work to do
--   "notready" - it's loaded and has nothing to do (or is disabled/stalled)
--   "unknown"  - its module or data isn't loaded yet
-- "unknown" blocks the world boss and loadstring branches only until UNKNOWN_TIMEOUT
-- has passed, so a system that never loads outside the lobby can't stop them forever.

local function pumpkinStatus()
    if not PUMPKIN_CONFIG.ENABLED then return "notready" end
    if os.clock() < pumpkinState.stalledUntil then return "notready" end

    if not pumpkinState.initialized then
        initPumpkinModule()
        if not pumpkinState.initialized then return "unknown" end
    end

    local growing = 0
    local actionable = false

    for slot = 1, PUMPKIN_CONFIG.MAX_PLOTS do
        local st = getSlotState(slot)
        if st == "Unknown" then
            return "unknown"
        elseif st == GROWING_STATE then
            growing = growing + 1
        elseif isActionable(st) then
            actionable = true
        end
    end

    -- Every plot is growing, so there's nothing to do
    if growing == PUMPKIN_CONFIG.MAX_PLOTS then
        return "notready"
    end

    -- At least one plot is ready to carve, pick, or plant
    if actionable then
        return "ready"
    end

    return "notready"
end

local function graveStatus()
    if not GRAVE_CONFIG.ENABLED then return "notready" end
    if os.clock() < graveState.stalledUntil then return "notready" end

    if not graveState.initialized then
        initGraveModule()
        if not graveState.initialized then return "unknown" end
    end

    if not hasShovel() then return "notready" end

    local sawReady = false
    for slot = 1, GRAVE_CONFIG.MAX_GRAVES do
        local st = getGraveStatus(slot)
        if st == "Unknown" then
            return "unknown"
        elseif st == "Refilling" then
            return "notready"
        elseif st == "Ready" then
            sawReady = true
        end
    end

    return sawReady and "ready" or "notready"
end

local function trickStatus()
    if not TRICK_CONFIG.ENABLED then return "notready" end
    if #getReadyDoors() > 0 then return "ready" end
    return "notready"
end

-- The priority routes only run when Pumpkin, Graveyard, Trick or Treat, and Auto WorldBoss are all ON
local function priorityEnabled()
    return PUMPKIN_CONFIG.ENABLED and GRAVE_CONFIG.ENABLED and TRICK_CONFIG.ENABLED and autoWorldBossEnabled
end

-- Tracks how long the loop has been blocked by an unknown system.
local unknownSince = nil
local function unknownTimedOut(isBlocked)
    if not isBlocked then
        unknownSince = nil
        return false
    end
    unknownSince = unknownSince or os.clock()
    return os.clock() - unknownSince >= UNKNOWN_TIMEOUT
end

-- Returns a state and the route name. Checks trick first so it's not blocked by unknown states.
local function decideRoute()
    if not priorityEnabled() then
        unknownTimedOut(false)
        return "notready", nil
    end

    local pumpkin = pumpkinStatus()
    local grave = graveStatus()
    local trick = trickStatus()

    -- Trick or Treat is checked first so it's never blocked by unknown states
    if trick == "ready" then return "ready", "trick" end

    if pumpkin == "ready" then return "ready", "pumpkin" end
    if grave == "ready" then return "ready", "grave" end

    local blocked = pumpkin == "unknown" or grave == "unknown"
    if blocked and not unknownTimedOut(true) then
        return "unknown", nil
    end
    unknownTimedOut(blocked)

    return "notready", nil
end

-- Runs one route. Only called when inside the lobby.
local function runRoute(name)
    if name == "pumpkin" then
        runPumpkinRoute()
        task.wait(PUMPKIN_CONFIG.ROUTE_COOLDOWN)
    elseif name == "grave" then
        runGraveRoute()
        task.wait(GRAVE_CONFIG.ROUTE_COOLDOWN)
    elseif name == "trick" then
        runTrickRoute()
        task.wait(TRICK_CONFIG.ROUTE_COOLDOWN)
    end
end

-- =========================
-- GUI
-- =========================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CandyFeedGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10000
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = UDim2.new(0, 360, 0, 430)
frame.Position = UDim2.new(0.05, 0, 0.1, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = frame

-- Title bar (drag handle)
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.Parent = frame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -30, 1, 0)
titleLabel.Position = UDim2.new(0, 6, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Candy Loop"
titleLabel.Parent = titleBar

-- Tab bar
local function makeTab(name, text, xScale)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0.5, -12, 0, 22)
    btn.Position = UDim2.new(xScale, xScale == 0 and 10 or 2, 0, 32)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.Text = text
    btn.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    return btn
end

local mainTab = makeTab("MainTab", "Main", 0)
local statsTab = makeTab("StatsTab", "Stats", 0.5)

-- Pages (below the tab bar)
local mainPage = Instance.new("Frame")
mainPage.Name = "MainPage"
mainPage.Size = UDim2.new(1, 0, 1, -62)
mainPage.Position = UDim2.new(0, 0, 0, 58)
mainPage.BackgroundTransparency = 1
mainPage.Parent = frame

local statsPage = Instance.new("Frame")
statsPage.Name = "StatsPage"
statsPage.Size = UDim2.new(1, 0, 1, -62)
statsPage.Position = UDim2.new(0, 0, 0, 58)
statsPage.BackgroundTransparency = 1
statsPage.Visible = false
statsPage.Parent = frame

-- Status label (assigns the forward-declared statusLabel above)
statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -20, 0, 40)
statusLabel.Position = UDim2.new(0, 10, 0, 6)
statusLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
statusLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
statusLabel.TextSize = 13
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Center
statusLabel.TextWrapped = true
statusLabel.Text = "Status: Idle"
statusLabel.Parent = mainPage

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 6)
statusCorner.Parent = statusLabel

-- Candy toggle
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.new(1, -20, 0, 36)
toggleButton.Position = UDim2.new(0, 10, 0, 54)
toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 16
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Text = "Feed Loop: OFF"
toggleButton.Parent = mainPage

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

-- Pumpkin toggle (starts ON, highest priority)
local pumpkinButton = Instance.new("TextButton")
pumpkinButton.Name = "PumpkinButton"
pumpkinButton.Size = UDim2.new(1, -20, 0, 36)
pumpkinButton.Position = UDim2.new(0, 10, 0, 98)
pumpkinButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
pumpkinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
pumpkinButton.TextSize = 16
pumpkinButton.Font = Enum.Font.GothamBold
pumpkinButton.Text = "Pumpkin: ON"
pumpkinButton.Parent = mainPage

local pumpkinCorner = Instance.new("UICorner")
pumpkinCorner.CornerRadius = UDim.new(0, 8)
pumpkinCorner.Parent = pumpkinButton

-- Graveyard toggle (starts ON)
local graveButton = Instance.new("TextButton")
graveButton.Name = "GraveButton"
graveButton.Size = UDim2.new(1, -20, 0, 36)
graveButton.Position = UDim2.new(0, 10, 0, 142)
graveButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
graveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
graveButton.TextSize = 16
graveButton.Font = Enum.Font.GothamBold
graveButton.Text = "Graves: ON"
graveButton.Parent = mainPage

local graveCorner = Instance.new("UICorner")
graveCorner.CornerRadius = UDim.new(0, 8)
graveCorner.Parent = graveButton

-- Trick or Treat toggle (starts ON)
local trickButton = Instance.new("TextButton")
trickButton.Name = "TrickButton"
trickButton.Size = UDim2.new(1, -20, 0, 36)
trickButton.Position = UDim2.new(0, 10, 0, 186)
trickButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
trickButton.TextColor3 = Color3.fromRGB(255, 255, 255)
trickButton.TextSize = 16
trickButton.Font = Enum.Font.GothamBold
trickButton.Text = "Trick or Treat: ON"
trickButton.Parent = mainPage

local trickCorner = Instance.new("UICorner")
trickCorner.CornerRadius = UDim.new(0, 8)
trickCorner.Parent = trickButton

-- ESP toggle (starts ON)
local espButton = Instance.new("TextButton")
espButton.Name = "ESPButton"
espButton.Size = UDim2.new(1, -20, 0, 36)
espButton.Position = UDim2.new(0, 10, 0, 230)
espButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
espButton.TextColor3 = Color3.fromRGB(255, 255, 255)
espButton.TextSize = 16
espButton.Font = Enum.Font.GothamBold
espButton.Text = "Door ESP: ON"
espButton.Parent = mainPage

local espCorner = Instance.new("UICorner")
espCorner.CornerRadius = UDim.new(0, 8)
espCorner.Parent = espButton

-- Auto WorldBoss toggle (starts ON). Gates the world boss remote and the loadstring fallback.
local worldBossButton = Instance.new("TextButton")
worldBossButton.Name = "WorldBossButton"
worldBossButton.Size = UDim2.new(1, -20, 0, 36)
worldBossButton.Position = UDim2.new(0, 10, 0, 274)
worldBossButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
worldBossButton.TextColor3 = Color3.fromRGB(255, 255, 255)
worldBossButton.TextSize = 16
worldBossButton.Font = Enum.Font.GothamBold
worldBossButton.Text = "Auto WorldBoss: ON"
worldBossButton.Parent = mainPage

local worldBossCorner = Instance.new("UICorner")
worldBossCorner.CornerRadius = UDim.new(0, 8)
worldBossCorner.Parent = worldBossButton

local priorityLabel = Instance.new("TextLabel")
priorityLabel.Name = "PriorityNote"
priorityLabel.Size = UDim2.new(1, -20, 0, 36)
priorityLabel.Position = UDim2.new(0, 10, 0, 318)
priorityLabel.BackgroundTransparency = 1
priorityLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
priorityLabel.TextSize = 12
priorityLabel.Font = Enum.Font.Gotham
priorityLabel.TextWrapped = true
priorityLabel.Text = "Priority: Pumpkin > Graveyard > TrickOrTreat (needs Pumpkin, Graves, Trick, and Auto WorldBoss all ON)"
priorityLabel.Parent = mainPage

-- Stats list (scrolls)
local statsScroll = Instance.new("ScrollingFrame")
statsScroll.Name = "StatsScroll"
statsScroll.Size = UDim2.new(1, -16, 1, -8)
statsScroll.Position = UDim2.new(0, 8, 0, 4)
statsScroll.BackgroundTransparency = 1
statsScroll.BorderSizePixel = 0
statsScroll.ScrollBarThickness = 4
statsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
statsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
statsScroll.Parent = statsPage

local statsLayout = Instance.new("UIListLayout")
statsLayout.Padding = UDim.new(0, 6)
statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsLayout.Parent = statsScroll

-- Creates a header and a 2-column grid with `count` cells. Returns the cooldown labels.
local function makeGridSection(name, order, count, prefix)
    local header = Instance.new("TextLabel")
    header.Name = name .. "Header"
    header.Size = UDim2.new(1, -6, 0, 20)
    header.BackgroundTransparency = 1
    header.TextColor3 = Color3.fromRGB(255, 255, 255)
    header.TextSize = 15
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = name
    header.LayoutOrder = order
    header.Parent = statsScroll

    local grid = Instance.new("Frame")
    grid.Name = name .. "Grid"
    grid.Size = UDim2.new(1, -6, 0, 0)
    grid.AutomaticSize = Enum.AutomaticSize.Y
    grid.BackgroundTransparency = 1
    grid.LayoutOrder = order + 1
    grid.Parent = statsScroll

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0.5, -4, 0, 46)
    gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.FillDirectionMaxCells = 2
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = grid

    local labels = {}
    for i = 1, count do
        local cell = Instance.new("Frame")
        cell.Name = prefix .. " " .. i
        cell.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        cell.BorderSizePixel = 0
        cell.LayoutOrder = i
        cell.Parent = grid

        local cellCorner = Instance.new("UICorner")
        cellCorner.CornerRadius = UDim.new(0, 6)
        cellCorner.Parent = cell

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.Size = UDim2.new(1, -12, 0, 16)
        nameLabel.Position = UDim2.new(0, 6, 0, 3)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 13
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Text = prefix .. " " .. i
        nameLabel.Parent = cell

        local cdLabel = Instance.new("TextLabel")
        cdLabel.Name = "Cooldown"
        cdLabel.Size = UDim2.new(1, -12, 0, 18)
        cdLabel.Position = UDim2.new(0, 6, 0, 22)
        cdLabel.BackgroundTransparency = 1
        cdLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
        cdLabel.TextSize = 12
        cdLabel.Font = Enum.Font.Gotham
        cdLabel.TextXAlignment = Enum.TextXAlignment.Left
        cdLabel.TextTruncate = Enum.TextTruncate.AtEnd
        cdLabel.Text = "..."
        cdLabel.Parent = cell

        labels[i] = cdLabel
    end

    return labels
end

local statCells = {
    pumpkin = makeGridSection("Pumpkin Patch", 1, PUMPKIN_CONFIG.MAX_PLOTS, "Plot"),
    grave = makeGridSection("Graveyard", 3, GRAVE_CONFIG.MAX_GRAVES, "Grave"),
}

-- Single-cell stat section for Trick or Treat
local function makeSingleStat(name, order)
    local header = Instance.new("TextLabel")
    header.Name = name .. "Header"
    header.Size = UDim2.new(1, -6, 0, 20)
    header.BackgroundTransparency = 1
    header.TextColor3 = Color3.fromRGB(255, 255, 255)
    header.TextSize = 15
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = name
    header.LayoutOrder = order
    header.Parent = statsScroll

    local cell = Instance.new("Frame")
    cell.Name = name .. "Cell"
    cell.Size = UDim2.new(1, -6, 0, 46)
    cell.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    cell.BorderSizePixel = 0
    cell.LayoutOrder = order + 1
    cell.Parent = statsScroll

    local cellCorner = Instance.new("UICorner")
    cellCorner.CornerRadius = UDim.new(0, 6)
    cellCorner.Parent = cell

    local label = Instance.new("TextLabel")
    label.Name = "Cooldown"
    label.Size = UDim2.new(1, -12, 1, 0)
    label.Position = UDim2.new(0, 6, 0, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(170, 170, 170)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = "..."
    label.Parent = cell

    return label
end

local trickStatLabel = makeSingleStat("Trick or Treat", 5)

-- =========================
-- Unload button and confirmation (built before anything that could wait or fail)
-- =========================
local unloadButton = Instance.new("TextButton")
unloadButton.Name = "UnloadButton"
unloadButton.Size = UDim2.new(0, 20, 0, 20)
unloadButton.Position = UDim2.new(1, -24, 0, 4)
unloadButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
unloadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadButton.TextSize = 14
unloadButton.Font = Enum.Font.GothamBold
unloadButton.Text = "X"
unloadButton.Parent = frame

local unloadCorner = Instance.new("UICorner")
unloadCorner.CornerRadius = UDim.new(0, 6)
unloadCorner.Parent = unloadButton

local confirmFrame = Instance.new("Frame")
confirmFrame.Name = "ConfirmFrame"
confirmFrame.Size = UDim2.new(0, 240, 0, 120)
confirmFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
confirmFrame.AnchorPoint = Vector2.new(0.5, 0.5)
confirmFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
confirmFrame.BorderSizePixel = 0
confirmFrame.Visible = false
confirmFrame.ZIndex = 10
confirmFrame.Parent = screenGui

local confirmCorner = Instance.new("UICorner")
confirmCorner.CornerRadius = UDim.new(0, 8)
confirmCorner.Parent = confirmFrame

local confirmText = Instance.new("TextLabel")
confirmText.Name = "Message"
confirmText.Size = UDim2.new(1, -20, 0, 50)
confirmText.Position = UDim2.new(0, 10, 0, 10)
confirmText.BackgroundTransparency = 1
confirmText.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmText.TextSize = 15
confirmText.Font = Enum.Font.GothamBold
confirmText.TextWrapped = true
confirmText.Text = "Unload the script?\nThis stops all loops and removes the GUI."
confirmText.ZIndex = 11
confirmText.Parent = confirmFrame

local yesButton = Instance.new("TextButton")
yesButton.Name = "YesButton"
yesButton.Size = UDim2.new(0.5, -18, 0, 32)
yesButton.Position = UDim2.new(0, 10, 1, -42)
yesButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
yesButton.TextColor3 = Color3.fromRGB(255, 255, 255)
yesButton.TextSize = 14
yesButton.Font = Enum.Font.GothamBold
yesButton.Text = "Yes, Unload"
yesButton.ZIndex = 11
yesButton.Parent = confirmFrame

local yesCorner = Instance.new("UICorner")
yesCorner.CornerRadius = UDim.new(0, 6)
yesCorner.Parent = yesButton

local noButton = Instance.new("TextButton")
noButton.Name = "NoButton"
noButton.Size = UDim2.new(0.5, -18, 0, 32)
noButton.Position = UDim2.new(0.5, 8, 1, -42)
noButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
noButton.TextColor3 = Color3.fromRGB(255, 255, 255)
noButton.TextSize = 14
noButton.Font = Enum.Font.GothamBold
noButton.Text = "Cancel"
noButton.ZIndex = 11
noButton.Parent = confirmFrame

local noCorner = Instance.new("UICorner")
noCorner.CornerRadius = UDim.new(0, 6)
noCorner.Parent = noButton

-- =========================
-- Door ESP (Highlight) - never blocks. If the doors folder isn't loaded yet, it's attached when it appears.
-- Works for both BasePart and Model doors.
-- =========================
local ESP_ENABLED = true
local espHighlights = {}
local espConnections = {}
local doorsFolder = nil

local function removeESP(door)
    if espHighlights[door] then
        espHighlights[door]:Destroy()
        espHighlights[door] = nil
    end
end

local function createESP(door)
    if not ESP_ENABLED or espHighlights[door] then return end

    if door:IsA("BasePart") then
        door.Transparency = 0
    end

    local highlight = Instance.new("Highlight")
    highlight.FillColor = Color3.fromRGB(255, 140, 0)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Parent = door

    espHighlights[door] = highlight
end

local function checkDoor(door)
    if not (door:IsA("BasePart") or door:IsA("Model")) then return end

    local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt or not ESP_ENABLED then
        removeESP(door)
        return
    end

    if (prompt.ObjectText or ""):lower():find("trick") then
        createESP(door)
    else
        removeESP(door)
    end
end

local function setupDoor(door)
    checkDoor(door)

    local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        table.insert(espConnections, prompt.Changed:Connect(function()
            checkDoor(door)
        end))
    end

    table.insert(espConnections, door.ChildRemoved:Connect(function(child)
        if child:IsA("ProximityPrompt") then
            checkDoor(door)
        end
    end))
end

local function attachDoorsFolder(folder)
    if doorsFolder then return end
    doorsFolder = folder

    for _, door in ipairs(folder:GetChildren()) do
        setupDoor(door)
    end
    table.insert(espConnections, folder.ChildAdded:Connect(function(door)
        task.wait(0.1)
        setupDoor(door)
        checkDoor(door)
    end))
end

local function setESP(on)
    ESP_ENABLED = on
    if not doorsFolder then return end

    if on then
        for _, door in ipairs(doorsFolder:GetChildren()) do
            checkDoor(door)
        end
    else
        for door in pairs(espHighlights) do
            removeESP(door)
        end
    end
end

local function clearESP()
    ESP_ENABLED = false
    for _, conn in ipairs(espConnections) do
        conn:Disconnect()
    end
    table.clear(espConnections)
    for door in pairs(espHighlights) do
        removeESP(door)
    end
end

-- Attach now if the folder exists, otherwise attach when it's added to the workspace
do
    local existing = workspace:FindFirstChild("TrickOrTreatDoors")
    if existing then
        attachDoorsFolder(existing)
    end
    table.insert(espConnections, workspace.ChildAdded:Connect(function(child)
        if child.Name == "TrickOrTreatDoors" and not doorsFolder then
            attachDoorsFolder(child)
        end
    end))
end

-- =========================
-- Dragging
-- =========================
local dragging = false
local dragStart
local startPos

table.insert(connections, titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position

        local endedConn
        endedConn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                endedConn:Disconnect()
            end
        end)
    end
end))

table.insert(connections, UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end))

-- =========================
-- Tabs
-- =========================
local function setTab(name)
    local onStats = name == "Stats"
    mainPage.Visible = not onStats
    statsPage.Visible = onStats
    mainTab.BackgroundColor3 = onStats and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(70, 70, 70)
    statsTab.BackgroundColor3 = onStats and Color3.fromRGB(70, 70, 70) or Color3.fromRGB(40, 40, 40)
end

setTab("Main")

table.insert(connections, mainTab.MouseButton1Click:Connect(function()
    setTab("Main")
end))

table.insert(connections, statsTab.MouseButton1Click:Connect(function()
    setTab("Stats")
end))

-- =========================
-- Toggle logic (with saved settings)
-- =========================
-- Sets a toggle button's text and color to match its state
local function styleToggle(button, label, on)
    button.Text = label .. (on and ": ON" or ": OFF")
    button.BackgroundColor3 = on and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(40, 40, 40)
end

-- Writes every toggle's current state to this user's settings file
local function saveToggleStates()
    writeSettingsFile({
        feedLoop = looping,
        pumpkin = PUMPKIN_CONFIG.ENABLED,
        graves = GRAVE_CONFIG.ENABLED,
        trick = TRICK_CONFIG.ENABLED,
        esp = ESP_ENABLED,
        worldBoss = autoWorldBossEnabled,
    })
end

-- Restore the saved toggle states before the buttons are shown.
-- Feed Loop always starts OFF, regardless of the saved value.
looping = false
PUMPKIN_CONFIG.ENABLED = readSetting("pumpkin", true)
GRAVE_CONFIG.ENABLED = readSetting("graves", true)
TRICK_CONFIG.ENABLED = readSetting("trick", true)
autoWorldBossEnabled = readSetting("worldBoss", true)
setESP(readSetting("esp", true))

styleToggle(toggleButton, "Feed Loop", looping)
styleToggle(pumpkinButton, "Pumpkin", PUMPKIN_CONFIG.ENABLED)
styleToggle(graveButton, "Graves", GRAVE_CONFIG.ENABLED)
styleToggle(trickButton, "Trick or Treat", TRICK_CONFIG.ENABLED)
styleToggle(espButton, "Door ESP", ESP_ENABLED)
styleToggle(worldBossButton, "Auto WorldBoss", autoWorldBossEnabled)

saveToggleStates()

table.insert(connections, toggleButton.MouseButton1Click:Connect(function()
    looping = not looping
    styleToggle(toggleButton, "Feed Loop", looping)
    saveToggleStates()
end))

table.insert(connections, pumpkinButton.MouseButton1Click:Connect(function()
    PUMPKIN_CONFIG.ENABLED = not PUMPKIN_CONFIG.ENABLED
    styleToggle(pumpkinButton, "Pumpkin", PUMPKIN_CONFIG.ENABLED)
    saveToggleStates()
end))

table.insert(connections, graveButton.MouseButton1Click:Connect(function()
    GRAVE_CONFIG.ENABLED = not GRAVE_CONFIG.ENABLED
    styleToggle(graveButton, "Graves", GRAVE_CONFIG.ENABLED)
    saveToggleStates()
end))

table.insert(connections, trickButton.MouseButton1Click:Connect(function()
    TRICK_CONFIG.ENABLED = not TRICK_CONFIG.ENABLED
    styleToggle(trickButton, "Trick or Treat", TRICK_CONFIG.ENABLED)
    saveToggleStates()
end))

table.insert(connections, espButton.MouseButton1Click:Connect(function()
    setESP(not ESP_ENABLED)
    styleToggle(espButton, "Door ESP", ESP_ENABLED)
    saveToggleStates()
end))

table.insert(connections, worldBossButton.MouseButton1Click:Connect(function()
    autoWorldBossEnabled = not autoWorldBossEnabled
    styleToggle(worldBossButton, "Auto WorldBoss", autoWorldBossEnabled)
    saveToggleStates()
end))

table.insert(connections, unloadButton.MouseButton1Click:Connect(function()
    confirmFrame.Visible = true
end))

table.insert(connections, noButton.MouseButton1Click:Connect(function()
    confirmFrame.Visible = false
end))

-- =========================
-- Stats refresh
-- =========================
local function refreshPumpkinStats()
    local labels = statCells.pumpkin
    if not pumpkinState.initialized and not initPumpkinModule() then
        for slot = 1, PUMPKIN_CONFIG.MAX_PLOTS do
            labels[slot].Text = "Unavailable"
        end
        return
    end

    local now = workspace:GetServerTimeNow()
    local gardenState = getPumpkinGardenState()

    for slot = 1, PUMPKIN_CONFIG.MAX_PLOTS do
        local label = labels[slot]
        local st = getSlotState(slot)
        local readyAt = getPumpkinReadyAt(gardenState, slot)

        if st == GROWING_STATE then
            if readyAt then
                label.Text = "Ready in " .. formatLeft(readyAt - now)
            else
                label.Text = "Growing"
            end
            label.TextColor3 = Color3.fromRGB(255, 205, 70)
        elseif st == "Grown" then
            label.Text = "Ready to carve"
            label.TextColor3 = Color3.fromRGB(140, 255, 120)
        elseif st == "Carved" then
            label.Text = "Ready to pick"
            label.TextColor3 = Color3.fromRGB(140, 255, 120)
        elseif st == "Empty" then
            label.Text = "Empty, ready to plant"
            label.TextColor3 = Color3.fromRGB(170, 170, 170)
        else
            label.Text = "Unavailable"
            label.TextColor3 = Color3.fromRGB(170, 170, 170)
        end
    end
end

local function refreshGraveStats()
    local labels = statCells.grave
    if not graveState.initialized and not initGraveModule() then
        for slot = 1, GRAVE_CONFIG.MAX_GRAVES do
            labels[slot].Text = "Unavailable"
        end
        return
    end

    local now = workspace:GetServerTimeNow()
    local playerData = getGravePlayerData()

    for slot = 1, GRAVE_CONFIG.MAX_GRAVES do
        local label = labels[slot]
        local st = getGraveStatus(slot)

        if st == "Refilling" then
            local grave = playerData and playerData.graves and playerData.graves[tostring(slot)]
            local readyAt = grave and grave.readyAt or now
            label.Text = "Refilling: " .. formatLeft(readyAt - now) .. " left"
            label.TextColor3 = Color3.fromRGB(255, 205, 70)
        elseif st == "Ready" then
            label.Text = "Ready to dig"
            label.TextColor3 = Color3.fromRGB(140, 255, 120)
        elseif st == "Locked" then
            label.Text = "Locked"
            label.TextColor3 = Color3.fromRGB(170, 170, 170)
        else
            label.Text = "Unavailable"
            label.TextColor3 = Color3.fromRGB(170, 170, 170)
        end
    end
end

-- Reads the Trick or Treat module's daily data, so it works from any place.
-- A door counts as ready when it hasn't been knocked today.
local function refreshTrickStats()
    local label = trickStatLabel

    local okMod, TrickMod = pcall(function()
        return require(ReplicatedStorage.Modules.TrickOrTreat)
    end)
    local okDoors, doors = pcall(function()
        return require(ReplicatedStorage.Modules.TownGhosts.Config).DOORS
    end)
    if not okMod or not okDoors or type(doors) ~= "table" then
        label.Text = "Unavailable"
        label.TextColor3 = Color3.fromRGB(170, 170, 170)
        return
    end

    local okData, data = pcall(function()
        return TrickMod.atom()
    end)
    if not okData or type(data) ~= "table" then
        label.Text = "Unavailable"
        label.TextColor3 = Color3.fromRGB(170, 170, 170)
        return
    end

    local total, knocked = 0, 0
    for i, door in pairs(doors) do
        if not door.gone then
            total = total + 1
            if TrickMod.visited(data, i) then
                knocked = knocked + 1
            end
        end
    end

    local ready = total - knocked
    if ready > 0 then
        label.Text = "Ready: " .. ready .. " of " .. total .. " doors"
        label.TextColor3 = Color3.fromRGB(140, 255, 120)
    else
        local secondsLeft = 86400 - os.time() % 86400
        label.Text = "Resets in " .. formatLeft(secondsLeft) .. " (00:00 UTC)"
        label.TextColor3 = Color3.fromRGB(255, 205, 70)
    end
end

-- =========================
-- Loops
-- =========================
-- Candy feed loop
task.spawn(function()
    while running do
        if looping then
            local prompt = getPrompt()
            if prompt and prompt:IsA("ProximityPrompt") then
                fireproximityprompt(prompt)
                if statusLabel then
                    statusLabel.Text = "Status: Feeding candy loop..."
                    statusLabel.TextColor3 = Color3.fromRGB(140, 255, 120)
                end
            end
        end
        task.wait(0.1)
    end
end)

-- Decision loop:
--   priority paused (any of Pumpkin, Graves, Trick, Auto WorldBoss OFF) -> no routes
--   unknown                    -> wait (up to UNKNOWN_TIMEOUT, then treated as not ready)
--   ready + outside lobby      -> teleport to lobby, then wait for the load
--   ready + inside lobby       -> run the highest-priority ready route
--   not ready + inside lobby   -> fire WorldBossEnter (throttled), only if Auto WorldBoss is ON
--   not ready + outside lobby  -> run the loadstring URL once, only if Auto WorldBoss is ON
task.spawn(function()
    while running do
        -- Don't make any decision while the teleport screen is still up
        waitForGameReady(60)

        local state, route = decideRoute()
        local atLobby = inLobby()

        if state == "unknown" then
            if statusLabel then
                statusLabel.Text = "Status: Loading modules..."
                statusLabel.TextColor3 = Color3.fromRGB(255, 205, 70)
            end
            task.wait(1)
        elseif state == "ready" and not atLobby then
            if statusLabel then
                statusLabel.Text = "Status: Teleporting to lobby for " .. (route or "unknown")
                statusLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
            end
            goToLobby()
            task.spawn(function()
                local targetCode2 = "20187371346491136469671725312837"--htd
                game:GetService("ExperienceService"):LaunchExperience({
                    placeId = 131367064230486,
                    linkCode = tostring(targetCode2)
                })
            end)
            task.wait(10)
            task.spawn(function()
                local targetCode2 = "20187371346491136469671725312837"--htd
                game:GetService("ExperienceService"):LaunchExperience({
                    placeId = 131367064230486,
                    linkCode = tostring(targetCode2)
                })
            end)
        elseif state == "ready" and atLobby then
            if statusLabel then
                statusLabel.Text = "Status: Running " .. (route or "unknown") .. " route"
                statusLabel.TextColor3 = Color3.fromRGB(140, 255, 120)
            end
            runRoute(route)
        elseif atLobby then
            if autoWorldBossEnabled then
                if statusLabel then
                    statusLabel.Text = "Status: In lobby, waiting for world boss..."
                    statusLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
                end
                tryWorldBossEnter()
            else
                if statusLabel then
                    statusLabel.Text = "Status: In lobby, Auto WorldBoss is OFF"
                    statusLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
                end
            end
        else
            if autoWorldBossEnabled then
                if statusLabel then
                    statusLabel.Text = "Status: Nothing ready, running backup..."
                    statusLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
                end
                runLoadstringOnce()
            else
                if statusLabel then
                    statusLabel.Text = "Status: Nothing ready, Auto WorldBoss is OFF"
                    statusLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
                end
            end
        end

        task.wait(0.5)
    end
end)

-- Stats loop: refreshes only while the Stats tab is open
task.spawn(function()
    while running do
        if statsPage.Visible then
            refreshPumpkinStats()
            refreshGraveStats()
            refreshTrickStats()
        end
        task.wait(1)
    end
end)

-- =========================
-- Unload
-- =========================
local function unload()
    running = false
    looping = false
    PUMPKIN_CONFIG.ENABLED = false
    GRAVE_CONFIG.ENABLED = false
    TRICK_CONFIG.ENABLED = false
    if statusLabel then
        statusLabel.Text = "Status: Unloaded"
        statusLabel.TextColor3 = Color3.fromRGB(180, 40, 40)
    end
    clearESP()
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    table.clear(connections)
    task.wait(0.5)
    screenGui:Destroy()
end

table.insert(connections, yesButton.MouseButton1Click:Connect(function()
    unload()
end))
