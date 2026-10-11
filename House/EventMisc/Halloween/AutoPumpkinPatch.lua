-- Pumpkin Patch Auto Script (Fast, Quiet)
-- Each cycle: pick -> carve -> plant. One swipe covers every carve in the swing window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

local RemoteFunction = require(ReplicatedStorage.Modules.Remotes.RemoteFunction)
local PumpkinGarden = RemoteFunction.new("PumpkinGarden")
local ScytheSwipe = ReplicatedStorage.Modules.Remotes.RemoteEvent.ScytheSwipe

local CONFIG = {
    ENABLED = true,
    AUTO_PLANT = true,
    AUTO_CARVE = true,
    AUTO_PICK = true,

    LOOP_INTERVAL = 0.5,   -- Minimum 0.5 seconds between cycles
    MAX_PLOTS = 8,
    CARVE_RANGE = 18,      -- Must match the server's CARVE_RANGE
    SWIPE_SETTLE = 0.05,   -- Short pause so the swipe reaches the server before the carves
}

local state = {
    initialized = false,
    pumpkinGarden = nil,
    pumpkinModule = nil,
    running = false,
}

-- Calls the PumpkinGarden remote and returns a table with .ok
local function invokeGarden(action, slot)
    local ok, success, data = pcall(function()
        return state.pumpkinGarden:Invoke(action, slot):await()
    end)
    if ok and success and type(data) == "table" then
        return data
    end
    return { ok = false }
end

local function initModule()
    local success, pumpkinModule = pcall(function()
        return require(ReplicatedStorage.Modules.PumpkinPatch)
    end)
    if not success then
        return false
    end

    state.pumpkinModule = pumpkinModule
    pcall(function()
        if pumpkinModule.Start then
            pumpkinModule.Start()
        end
    end)

    state.pumpkinGarden = PumpkinGarden
    state.initialized = true
    return true
end

local function getSlotState(slot)
    local pumpkinModule = state.pumpkinModule
    if not pumpkinModule or not pumpkinModule.atom then
        return "Unknown"
    end
    local success, gardenState = pcall(function()
        return pumpkinModule.atom()
    end)
    if not success or not gardenState then
        return "Unknown"
    end
    return pumpkinModule.slotState(gardenState, slot)
end

-- Returns the GrowPoint part for a slot, using the same lookup as the module
local function getGrowPoint(slot)
    for _, plot in ipairs(CollectionService:GetTagged("PumpkinPlot")) do
        if plot:GetAttribute("GardenSlot") == slot then
            local soil = plot:FindFirstChild("Soil")
            return soil and soil:FindFirstChild("GrowPoint")
        end
    end
    return nil
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function pickSlot(slot)
    if getSlotState(slot) == "Carved" then
        invokeGarden("pick", slot)
    end
end

local function plantSlot(slot)
    if getSlotState(slot) == "Empty" then
        invokeGarden("plant", slot)
    end
end

-- Finds every grown slot in range, sends one swipe, then carves them all in parallel.
-- The server accepts carves for SWING_WINDOW seconds after a swipe, so one swipe covers all of them.
local function carveAll()
    local root = getRoot()
    if not root then
        return
    end

    local targets = {}
    for slot = 1, CONFIG.MAX_PLOTS do
        if getSlotState(slot) == "Grown" then
            local growPoint = getGrowPoint(slot)
            if growPoint and (root.Position - growPoint.WorldPosition).Magnitude <= CONFIG.CARVE_RANGE then
                table.insert(targets, { slot = slot, pos = growPoint.WorldPosition })
            end
        end
    end

    if #targets == 0 then
        return
    end

    ScytheSwipe:FireServer(targets[1].pos)
    task.wait(CONFIG.SWIPE_SETTLE)

    for _, t in ipairs(targets) do
        task.spawn(invokeGarden, "carve", t.slot)
    end
end

local function mainLoop()
    state.running = true

    while state.running and CONFIG.ENABLED do
        if not state.initialized and not initModule() then
            task.wait(2)
            continue
        end

        if CONFIG.AUTO_PICK then
            for slot = 1, CONFIG.MAX_PLOTS do
                pickSlot(slot)
            end
        end

        if CONFIG.AUTO_CARVE then
            carveAll()
        end

        if CONFIG.AUTO_PLANT then
            for slot = 1, CONFIG.MAX_PLOTS do
                plantSlot(slot)
            end
        end

        task.wait(CONFIG.LOOP_INTERVAL)
    end

    state.running = false
end

local API = {
    start = function()
        if not state.running then
            task.spawn(mainLoop)
        end
    end,

    stop = function()
        state.running = false
        CONFIG.ENABLED = false
    end,

    toggle = function()
        CONFIG.ENABLED = not CONFIG.ENABLED
    end,

    setLoopInterval = function(interval)
        CONFIG.LOOP_INTERVAL = math.max(0.5, interval)
    end,
}

initModule()
API.start()

return API
