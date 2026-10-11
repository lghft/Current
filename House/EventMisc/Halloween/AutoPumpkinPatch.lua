-- Pumpkin Patch Auto Script (Verbose - Shows Everything)
-- Use this version to see exactly what's happening

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Load the RemoteFunction module and create PumpkinGarden instance
local RemoteFunction = require(ReplicatedStorage.Modules.Remotes.RemoteFunction)
local PumpkinGarden = RemoteFunction.new("PumpkinGarden")

local CONFIG = {
    ENABLED = true,
    AUTO_PLANT = true,
    AUTO_CARVE = true,
    AUTO_PICK = true,
    
    LOOP_INTERVAL = 1,  -- Longer interval so we can see logs
    ACTION_DELAY = 0.5,
    MAX_PLOTS = 8,
}

local state = {
    initialized = false,
    pumpkinGarden = nil,
    pumpkinModule = nil,
    running = false,
}

local function log(prefix, message)
    print("[" .. prefix .. "] " .. message)
end

local function initModule()
    log("INIT", "Loading PumpkinPatch module...")
    
    local success, pumpkinModule = pcall(function()
        return require(ReplicatedStorage.Modules.PumpkinPatch)
    end)
    
    if not success then
        log("ERROR", "Failed to load module: " .. tostring(pumpkinModule))
        return false
    end
    
    state.pumpkinModule = pumpkinModule
    log("INIT", "✓ Module loaded")
    
    -- Initialize
    log("INIT", "Calling Start()...")
    pcall(function()
        if pumpkinModule.Start then
            pumpkinModule.Start()
        end
    end)
    
    state.pumpkinGarden = PumpkinGarden
    state.initialized = true
    log("INIT", "✓ RemoteFunction ready!")
    return true
end

local function getGardenState()
    if not state.pumpkinModule then
        return nil
    end
    
    local atom = state.pumpkinModule.atom
    if not atom then
        log("STATE", "No atom available")
        return nil
    end
    
    local success, gardenState = pcall(function()
        return atom()
    end)
    
    if success and gardenState then
        return gardenState
    end
    
    return nil
end

local function getSlotState(slot)
    local gardenState = getGardenState()
    if not gardenState then
        return "Unknown"
    end
    
    return state.pumpkinModule.slotState(gardenState, slot)
end

local function testPlant(slot)
    log("PLANT", "Testing slot " .. slot .. "...")
    
    local slotState = getSlotState(slot)
    log("PLANT", "  Current state: " .. slotState)
    
    if slotState ~= "Empty" then
        log("PLANT", "  ✗ Not empty, skipping")
        return false
    end
    
    log("PLANT", "  Invoking plant...")
    
    if not state.pumpkinGarden then
        log("ERROR", "  PumpkinGarden remote not available")
        return false
    end
    
    local success, result = pcall(function()
        return state.pumpkinGarden:Invoke("plant", slot):await()
    end)
    
    log("PLANT", "  Invoke success: " .. tostring(success))
    log("PLANT", "  Result: " .. tostring(result))
    
    if success and result and type(result) == "table" then
        log("PLANT", "  Result.ok: " .. tostring(result.ok))
        if result.message then
            log("PLANT", "  Message: " .. result.message)
        end
        
        if result.ok then
            log("PLANT", "  ✓ Plant successful!")
            return true
        else
            log("PLANT", "  ✗ Plant failed")
            return false
        end
    else
        log("ERROR", "  Invalid result format")
        return false
    end
end

local function testCarve(slot)
    log("CARVE", "Testing slot " .. slot .. "...")
    
    local slotState = getSlotState(slot)
    log("CARVE", "  Current state: " .. slotState)
    
    if slotState ~= "Grown" then
        log("CARVE", "  Not grown, skipping")
        return false
    end
    
    log("CARVE", "  Invoking carve...")
    
    if not state.pumpkinGarden then
        log("ERROR", "  PumpkinGarden remote not available")
        return false
    end
    
    local success, result = pcall(function()
        return state.pumpkinGarden:Invoke("carve", slot):await()
    end)
    
    log("CARVE", "  Invoke success: " .. tostring(success))
    
    if success and result and type(result) == "table" and result.ok then
        log("CARVE", "  ✓ Carve successful!")
        return true
    else
        log("CARVE", "  ✗ Carve failed")
        return false
    end
end

local function testPick(slot)
    log("PICK", "Testing slot " .. slot .. "...")
    
    local slotState = getSlotState(slot)
    log("PICK", "  Current state: " .. slotState)
    
    if slotState ~= "Carved" then
        log("PICK", "  Not carved, skipping")
        return false
    end
    
    log("PICK", "  Invoking pick...")
    
    if not state.pumpkinGarden then
        log("ERROR", "  PumpkinGarden remote not available")
        return false
    end
    
    local success, result = pcall(function()
        return state.pumpkinGarden:Invoke("pick", slot):await()
    end)
    
    log("PICK", "  Invoke success: " .. tostring(success))
    
    if success and result and type(result) == "table" and result.ok then
        log("PICK", "  ✓ Pick successful!")
        return true
    else
        log("PICK", "  ✗ Pick failed")
        return false
    end
end

local function printAllStates()
    log("STATE", "Current plot states:")
    for slot = 1, CONFIG.MAX_PLOTS do
        local state = getSlotState(slot)
        log("STATE", "  Slot " .. slot .. ": " .. state)
    end
end

local function mainLoop()
    state.running = true
    
    while state.running and CONFIG.ENABLED do
        if not state.initialized then
            log("MAIN", "Not initialized, trying to init...")
            if not initModule() then
                log("MAIN", "Init failed, retrying in 2 seconds...")
                wait(2)
                continue
            end
        end
        
        log("MAIN", "=== CYCLE START ===")
        
        -- Show current state
        printAllStates()
        
        -- Try actions
        if CONFIG.AUTO_CARVE then
            log("MAIN", "--- CARVING ---")
            for slot = 1, CONFIG.MAX_PLOTS do
                testCarve(slot)
                wait(CONFIG.ACTION_DELAY)
            end
        end
        
        wait(CONFIG.LOOP_INTERVAL)
        
        if CONFIG.AUTO_PLANT then
            log("MAIN", "--- PLANTING ---")
            for slot = 1, CONFIG.MAX_PLOTS do
                testPlant(slot)
                wait(CONFIG.ACTION_DELAY)
            end
        end
        
        wait(CONFIG.LOOP_INTERVAL)
        
        if CONFIG.AUTO_PICK then
            log("MAIN", "--- PICKING ---")
            for slot = 1, CONFIG.MAX_PLOTS do
                testPick(slot)
                wait(CONFIG.ACTION_DELAY)
            end
        end
        
        log("MAIN", "=== CYCLE END ===\n")
        wait(CONFIG.LOOP_INTERVAL)
    end
    
    state.running = false
end

-- API
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
        log("API", "Script " .. (CONFIG.ENABLED and "enabled" or "disabled"))
    end,
    
    setLoopInterval = function(interval)
        CONFIG.LOOP_INTERVAL = math.max(0.5, interval)
        log("API", "Loop interval set to " .. CONFIG.LOOP_INTERVAL)
    end,
    
    setActionDelay = function(delay)
        CONFIG.ACTION_DELAY = math.max(0.1, delay)
        log("API", "Action delay set to " .. CONFIG.ACTION_DELAY)
    end,
}

log("STARTUP", "🎃 Pumpkin Auto Script (Verbose Mode)")
log("STARTUP", "Starting initialization...")

if initModule() then
    log("STARTUP", "✓ Initialization successful")
    printAllStates()
    API.start()
else
    log("STARTUP", "✗ Initialization failed, will retry automatically")
    API.start()
end

return API
