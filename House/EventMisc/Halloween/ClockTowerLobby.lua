 -- Lobby Automation Script for LabRooms
-- Teleports to lobby, selects a door, enters it, and starts a game
repeat task.wait() until game:IsLoaded()
if game.PlaceId ~= 131367064230486 then
    return
end
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local labEvent = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.LabRooms

-- SETTINGS
local LOBBY_POSITION = Vector3.new(3000, 91, 6062)
local SELECTED_MAP_NUMBER = 5 -- Select a map: 1-5
local WAIT_FOR_GUI_TIMEOUT = 10 -- seconds


-- Door and proximity prompt references (lazy-loaded to avoid errors)
local function getDoors()
    return {
        pcall(function() return workspace.ClockTowerLobby.LabDoors["1_ClockTower"].LabRoomEntry end) and workspace.ClockTowerLobby.LabDoors["1_ClockTower"].LabRoomEntry or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["2_DemonLab"].LabRoomEntry end) and workspace.ClockTowerLobby.LabDoors["2_DemonLab"].LabRoomEntry or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["3_StormEngine"].LabRoomEntry end) and workspace.ClockTowerLobby.LabDoors["3_StormEngine"].LabRoomEntry or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["4_HolyLab"].LabRoomEntry end) and workspace.ClockTowerLobby.LabDoors["4_HolyLab"].LabRoomEntry or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["5_CrazyLab"].LabRoomEntry end) and workspace.ClockTowerLobby.LabDoors["5_CrazyLab"].LabRoomEntry or nil,
    }
end

local function getPrompts()
    return {
        pcall(function() return workspace.ClockTowerLobby.LabDoors["1_ClockTower"].LabRoomEntry.EnterPrompt end) and workspace.ClockTowerLobby.LabDoors["1_ClockTower"].LabRoomEntry.EnterPrompt or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["2_DemonLab"].LabRoomEntry.EnterPrompt end) and workspace.ClockTowerLobby.LabDoors["2_DemonLab"].LabRoomEntry.EnterPrompt or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["3_StormEngine"].LabRoomEntry.EnterPrompt end) and workspace.ClockTowerLobby.LabDoors["3_StormEngine"].LabRoomEntry.EnterPrompt or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["4_HolyLab"].LabRoomEntry.EnterPrompt end) and workspace.ClockTowerLobby.LabDoors["4_HolyLab"].LabRoomEntry.EnterPrompt or nil,
        pcall(function() return workspace.ClockTowerLobby.LabDoors["5_CrazyLab"].LabRoomEntry.EnterPrompt end) and workspace.ClockTowerLobby.LabDoors["5_CrazyLab"].LabRoomEntry.EnterPrompt or nil,
    }
end

-- Alternative: TouchInterest pads for Halloween town
local TOUCH_PADS = {
    workspace.HalloweenTown.ClockTowerDoors.TowerEntry.ClockTowerEnterPad.TouchInterest,
}

local MAP_NAMES = {
    [1] = "ClockTower",
    [2] = "DemonLab",
    [3] = "StormEngine",
    [4] = "HolyLab",
    [5] = "CrazyLab",
}

-- Get door by map number
local function getDoor(mapNumber)
    if mapNumber < 1 or mapNumber > 5 then
        print("[Lobby] Error: Map number must be 1-5")
        return nil
    end
    
    local doors = getDoors()
    local door = doors[mapNumber]
    if not door then
        print("[Lobby] Error: Door " .. mapNumber .. " not found in workspace")
        return nil
    end
    
    return door
end

-- Function to teleport player
local function teleportToLobby()
    print("[Lobby] Disabling gameplay paused notification...")
    game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(false)
    
    print("[Lobby] Teleporting to lobby...")
    humanoidRootPart.CFrame = CFrame.new(LOBBY_POSITION)
    
    -- Wait until teleporting is finished
    print("[Lobby] Waiting for teleport to complete...")
    local startTime = os.clock()
    local timeout = 15
    
    while os.clock() - startTime < timeout do
        if not player:GetAttribute("Teleporting") then
            task.wait(1) -- Extra wait to ensure everything is loaded
            print("[Lobby] Arrived at lobby")
            return true
        end
        task.wait(0.1)
    end
    
    print("[Lobby] Teleport timeout!")
    return false
end



-- Function to walk to a target position
local function walkToTarget(targetPosition, stoppingDistance)
    stoppingDistance = stoppingDistance or 5
    
    print("[Lobby] Walking to target position...")
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not humanoidRootPart then
        return false
    end
    
    humanoid:MoveTo(targetPosition)
    
    local startTime = os.clock()
    local timeout = 60 -- 60 second timeout
    
    while true do
        local distance = (humanoidRootPart.Position - targetPosition).Magnitude
        
        if distance < stoppingDistance then
            print("[Lobby] Reached target position")
            humanoid:MoveTo(humanoidRootPart.Position)
            return true
        end
        
        if os.clock() - startTime > timeout then
            print("[Lobby] Walking timeout!")
            return false
        end
        
        if humanoid.Health <= 0 then
            return false
        end
        
        task.wait(0.1)
    end
end

-- Function to trigger proximity prompt
local function triggerProximityPrompt(mapNumber)
    print("[Lobby] Triggering proximity prompt...")
    
    local prompts = getPrompts()
    local proximityPrompt = prompts[mapNumber]
    
    if not proximityPrompt then
        print("[Lobby] No proximity prompt found for map " .. mapNumber)
        return false
    end
    
    -- Fire the proximity prompt
    fireproximityprompt(proximityPrompt)
    
    task.wait(0.5)
    
    return true
end

-- Function to wait for GUI to appear
local function waitForGUI(timeout)
    timeout = timeout or WAIT_FOR_GUI_TIMEOUT
    
    print("[Lobby] Waiting for GUI to appear...")
    
    local startTime = os.clock()
    local playerGui = player:WaitForChild("PlayerGui", 5)
    
    if not playerGui then
        print("[Lobby] PlayerGui not found!")
        return false
    end
    
    while os.clock() - startTime < timeout do
        -- Look for MainHud which contains the LabRoom GUI
        local mainHud = playerGui:FindFirstChild("MainHud")
        
        if mainHud then
            local hud = mainHud:FindFirstChild("Hud")
            if hud then
                print("[Lobby] GUI detected!")
                task.wait(1.5) -- Wait for GUI to fully load and render
                return true
            end
        end
        
        task.wait(0.3)
    end
    
    print("[Lobby] GUI timeout - GUI did not appear within " .. timeout .. " seconds")
    return false
end

-- Function to set capacity
local function setCapacity(capacityValue)
    print("[Lobby] Setting capacity to " .. capacityValue)
    
    local success = pcall(function()
        labEvent:FireServer("setCapacity", 1)
    end)
    
    if success then
        task.wait(0.5)
        return true
    end
    
    print("[Lobby] Failed to set capacity")
    return false
end

-- Function to start the game
local function startGame()
    print("[Lobby] Starting game...")
    
    local success = pcall(function()
        labEvent:FireServer("start")
    end)
    
    if success then
        task.wait(0.5)
        return true
    end
    
    print("[Lobby] Failed to start game")
    return false
end

-- Main execution
local function main()
    print("[Lobby] Script started")
    print("[Lobby] Selected map: " .. MAP_NAMES[SELECTED_MAP_NUMBER] .. " (Map " .. SELECTED_MAP_NUMBER .. ")")
    
    -- Step 1: Teleport to lobby
    if not teleportToLobby() then
        print("[Lobby] Script failed: Teleport did not complete")
        return
    end
    task.wait()
    
    -- Step 2: Get the selected door
    local door = getDoor(SELECTED_MAP_NUMBER)
    if not door then
        print("[Lobby] Script failed: Could not find door")
        return
    end
    
    task.wait()
    
    -- Step 3: Walk to the door
    local doorPosition = door.Position
    if not walkToTarget(doorPosition, 8) then
        print("[Lobby] Script failed: Could not reach door")
        return
    end
    
    task.wait()
    
    -- Step 4: Trigger the proximity prompt
    if not triggerProximityPrompt(SELECTED_MAP_NUMBER) then
        print("[Lobby] Script failed: Could not trigger proximity prompt")
        return
    end
    
    task.wait()
    
    -- Step 5: Wait for GUI to appear
    if not waitForGUI(WAIT_FOR_GUI_TIMEOUT) then
        print("[Lobby] Script failed: GUI did not appear")
        return
    end
    
    task.wait()
    
    -- Step 6: Set capacity to 1
    if not setCapacity(1) then
        print("[Lobby] Script warning: Failed to set capacity")
    end
    
    task.wait()
    
    -- Step 7: Start the game
    if not startGame() then
        print("[Lobby] Script warning: Failed to start game")
    end
    
    print("[Lobby] Script completed!")
end

-- Run the script
task.spawn(main)
