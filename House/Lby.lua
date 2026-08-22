repeat task.wait() until game:IsLoaded()
local StarterGui = game:GetService("StarterGui")
local gameId = game.GameId
local function SmartTeleportToLobby()
    pcall(function()
        local lobbyId = 131367064230486
        local UserInputService = game:GetService("UserInputService")
        local TeleportService = game:GetService("TeleportService")
        local Globals = getgenv()
        Globals.PrivateCode = ""
        local platform = UserInputService:GetPlatform()
        local IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)
        
        if not IsMobile and Globals.PrivateCode and Globals.PrivateCode ~= "" then
            game:GetService("ExperienceService"):LaunchExperience({
                placeId = lobbyId, 
                linkCode = Globals.PrivateCode
            })
        else
            TeleportService:Teleport(lobbyId)
        end
    end)
end
task.spawn(function()
    task.wait(6000)
    local RunService = game:GetService("RunService")
    RunService.RenderStepped:Connect(function(frame) -- This will fire every time a frame is rendered
    --print("FPS: "..math.round(1/frame)) 
        if math.round(1/frame) < 3 then
            SmartTeleportToLobby()
        end
    end)
end)


repeat task.wait() until gameId == 10463578886 and workspace:WaitForChild("_Scenes"):WaitForChild("Lobby")
-- Loop until the CoreGui successfully disables the PlayerList
task.spawn(function()
    local success = false
    repeat
        success = pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
        end)
        if not success then
            task.wait(0.1) -- Wait briefly before trying again
        end
    until success
    
    print("Player list successfully hidden!")
end)
task.wait(4)
local player = game.Players.LocalPlayer
local proximityThreshold = 10 -- Adjust this distance as needed
getgenv().Mode = "Story" --Story,Event,Garden
getgenv().Floor = 4 -- Event:1, Garden:1
getgenv().Stage = 4 
getgenv().Walk = true

if getgenv().Mode == "Event" or getgenv().Mode == "Garden" then
    getgenv().Floor = 1
end

-- === PURGE DOOR DATABASE === --
-- Will be initialized after PreloadFloor remote
local purgeDoors = nil

local loadoutRequirements = {
    Holy = {
        Team = {"tower129", "tower234", "tower194", "tower496", "tower340"}
    },
    Demon = {
        Team = {"tower234", "tower83", "tower49", "tower435", "tower340"}
    },
    Undead = {
        Team = {"tower485", "tower161", "tower504", "tower234", "tower340"}
    },
    Military = {
        Team = {"tower491", "tower375", "tower255", "tower201", "tower340"}
    },
    Paranormal = {
        Team = {"tower165", "tower360", "tower497", "tower194", "tower340"}
    }
}

-- === HOTBAR DATA MANAGEMENT === --
local hotbarData = {
    [1] = {uid = nil, name = "Empty"},
    [2] = {uid = nil, name = "Empty"},
    [3] = {uid = nil, name = "Empty"},
    [4] = {uid = nil, name = "Empty"},
    [5] = {uid = nil, name = "Empty"},
}

local function updateHotbarData()
    pcall(function()
        local EquippingModule = require(game:GetService("ReplicatedStorage").Modules.Equipping)
        local Inventory = require(game:GetService("ReplicatedStorage").Modules.Inventory)
        
        local hotbarSlots = EquippingModule.getHotbar(player)
        
        if hotbarSlots and #hotbarSlots > 0 then
            -- Reset all slots
            for slot = 1, 5 do
                hotbarData[slot] = {uid = nil, name = "Empty"}
            end
            
            -- Populate slots
            for slotIndex, itemUid in pairs(hotbarSlots) do
                if itemUid then
                    local itemData = Inventory.getItem(itemUid)
                    if itemData then
                        local baseId = itemData.itemId or itemData.id or itemData.uid
                        hotbarData[slotIndex] = {
                            uid = tostring(itemUid),
                            name = tostring(baseId)
                        }
                    end
                end
            end
            
            print("[Hotbar] Updated successfully")
            return true
        end
    end)
    return false
end

local function getCurrentLoadout()
    -- Returns the current hotbar as a table of tower UIDs
    local currentLoadout = {}
    for slot = 1, 5 do
        if hotbarData[slot] and hotbarData[slot].uid then
            table.insert(currentLoadout, hotbarData[slot].uid)
        end
    end
    return currentLoadout
end

local function loadoutsMatch(loadout1, loadout2)
    -- Compare two loadouts (as tables of UIDs)
    if #loadout1 ~= #loadout2 then return false end
    
    for i, uid in ipairs(loadout1) do
        if uid ~= loadout2[i] then
            return false
        end
    end
    return true
end

local function getOpenPurgeDoors()
    if not purgeDoors then
        warn("[Purge Doors] purgeDoors not initialized!")
        return {}
    end
    
    local openDoors = {}
    for elementName, doorData in pairs(purgeDoors) do
        if doorData.prompt then
            local proximityPrompt = doorData.prompt:FindFirstChildWhichIsA("ProximityPrompt")
            if proximityPrompt and proximityPrompt.Enabled then
                table.insert(openDoors, {name = elementName, data = doorData})
            end
        end
    end
    return openDoors
end

local function getHighestPriorityDoor(openDoors)
    table.sort(openDoors, function(a, b)
        return a.data.priority < b.data.priority
    end)
    return openDoors[1]
end

local function equipLoadout(elementName)
    -- Unequip all current towers
    print("[Loadout] Unequipping all towers...")
    pcall(function()
        local unequipRemote = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.UnequipAll
        unequipRemote:FireServer()
    end)
    
    task.wait(0.5)
    
    -- Equip the new loadout
    local requiredTeam = loadoutRequirements[elementName]
    if not requiredTeam or not requiredTeam.Team then
        warn("[Loadout] No loadout found for element: " .. elementName)
        return false
    end
    
    print("[Loadout] Equipping loadout for: " .. elementName)
    
    local equipRemote = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.Equip
    local equipped = 0
    
    for slot, towerUid in ipairs(requiredTeam.Team) do
        if slot <= 5 then  -- Only 5 slots
            pcall(function()
                print("[Loadout] Equipping slot " .. slot .. ": " .. towerUid)
                equipRemote:FireServer(towerUid, slot)
                equipped = equipped + 1
            end)
            task.wait(0.2)
        end
    end
    
    print("[Loadout] Equipped " .. equipped .. " towers for " .. elementName)
    task.wait(0.5)
    
    -- Update hotbar data
    updateHotbarData()
    return true
end

local function checkPlayerLoadout(requiredElement)
    -- Update current hotbar data
    updateHotbarData()
    
    local requiredTeam = loadoutRequirements[requiredElement]
    if not requiredTeam or not requiredTeam.Team then
        warn("[Loadout] No loadout found for element: " .. requiredElement)
        return false
    end
    
    local currentLoadout = getCurrentLoadout()
    local requiredLoadout = requiredTeam.Team
    
    -- Check if loadouts match
    local matches = loadoutsMatch(currentLoadout, requiredLoadout)
    
    if matches then
        print("[Loadout] ✓ Current loadout matches " .. requiredElement)
        return true
    else
        print("[Loadout] ✗ Current loadout does NOT match " .. requiredElement)
        print("[Loadout] Current: " .. table.concat(currentLoadout, ", "))
        print("[Loadout] Required: " .. table.concat(requiredLoadout, ", "))
        return false
    end
end

local function waitForCorrectLoadout(requiredElement, timeout)
    timeout = timeout or 120
    local startTime = tick()
    
    print("[Loadout] Checking loadout for: " .. requiredElement)
    
    -- First check if loadout is already correct
    if checkPlayerLoadout(requiredElement) then
        print("[Loadout] Loadout already correct! Proceeding...")
        return true
    end
    
    -- Loadout doesn't match, equip the correct one
    print("[Loadout] Loadout mismatch! Equipping correct loadout...")
    local equipSuccess = equipLoadout(requiredElement)
    
    if not equipSuccess then
        warn("[Loadout] Failed to equip loadout for " .. requiredElement)
        return false
    end
    
    -- Wait for loadout to be confirmed
    repeat
        task.wait(0.5)
        if checkPlayerLoadout(requiredElement) then
            print("[Loadout] ✓ Loadout confirmed! Proceeding...")
            return true
        end
        if tick() - startTime > timeout then
            warn("[Loadout] Timeout waiting for loadout: " .. requiredElement)
            return false
        end
    until false
end

local function waitForGui(timeout)
    timeout = timeout or 30
    local startTime = tick()
    repeat
        task.wait(0.1)
        local success, result = pcall(function()
            local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 1)
            local mainGui = playerGui:WaitForChild("MainHud", 1)
            local hud = mainGui:WaitForChild("Hud",1)
            local lbyHud = hud:WaitForChild("LobbyHud",1)
            return lbyHud.Visible == true
        end)
        if success and result then break end
        if tick() - startTime > timeout then
            warn("GUI load timeout after " .. timeout .. " seconds")
            break
        end
    until false
end

waitForGui(120)

-- Initialize hotbar data for loadout checking
print("[Loadout] Initializing hotbar data...")
updateHotbarData()

player.CharacterAdded:Connect(function(char)
    loadstring(game:HttpGet('https://raw.githubusercontent.com/lghft/Current/refs/heads/main/House/Float.lua'))()
end)

task.spawn(function()
    loadstring(game:HttpGet('https://raw.githubusercontent.com/lghft/Current/refs/heads/main/House/Float.lua'))()
end)

local v3 = require(game:GetService("ReplicatedStorage").Databases.Challenges)

-- Loop through all entries in the v3 table
for challengeKey, challengeData in pairs(v3) do
    --print("Internal Name:", challengeKey, "| Display Name:", challengeData.name)
    local claimChall = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.ClaimReward
    claimChall:FireServer(tostring(challengeKey))
end
task.spawn(function()
    local ddeal = workspace._Scenes["Death's Office"]["Deaths Office"].Death.DeathDeals.RE.BuyDeal
    ddeal:FireServer(
        1
    )
end)


local SetEle = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.SetInElevator
SetEle:FireServer(true)
task.wait()
print("set")
local LoadFlr = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteFunction.PreloadFloor
LoadFlr:InvokeServer(tostring(getgenv().Mode), tonumber(getgenv().Floor))
print("ld flr")
task.wait()

-- === INITIALIZE PURGE DOORS AFTER PRELOAD === --
if getgenv().Mode == "Event" or getgenv().Mode == "Garden" then
    print("[Purge Doors] Initializing after preload...")
    purgeDoors = {
        Holy = {
            prompt = workspace:FindFirstChild("HolyPurgeDoor") and workspace.HolyPurgeDoor:FindFirstChild("HolyPurgeGamepad") and workspace.HolyPurgeDoor.HolyPurgeGamepad:FindFirstChild("Prompt"),
            gamepad = workspace:FindFirstChild("HolyPurgeDoor") and workspace.HolyPurgeDoor:FindFirstChild("HolyPurgeGamepad") and workspace.HolyPurgeDoor.HolyPurgeGamepad:FindFirstChild("GamePad"),
            priority = 1,
            element = "Holy"
        },
        Demon = {
            prompt = workspace:FindFirstChild("DemonPurgeDoor") and workspace.DemonPurgeDoor:FindFirstChild("DemonPurgeGamepad") and workspace.DemonPurgeDoor.DemonPurgeGamepad:FindFirstChild("Prompt"),
            gamepad = workspace:FindFirstChild("DemonPurgeDoor") and workspace.DemonPurgeDoor:FindFirstChild("DemonPurgeGamepad") and workspace.DemonPurgeDoor.DemonPurgeGamepad:FindFirstChild("GamePad"),
            priority = 2,
            element = "Demon"
        },
        Undead = {
            prompt = workspace:FindFirstChild("UndeadPurgeDoor") and workspace.UndeadPurgeDoor:FindFirstChild("UndeadPurgeGamepad") and workspace.UndeadPurgeDoor.UndeadPurgeGamepad:FindFirstChild("Prompt"),
            gamepad = workspace:FindFirstChild("UndeadPurgeDoor") and workspace.UndeadPurgeDoor:FindFirstChild("UndeadPurgeGamepad") and workspace.UndeadPurgeDoor.UndeadPurgeGamepad:FindFirstChild("GamePad"),
            priority = 3,
            element = "Undead"
        },
        Military = {
            prompt = workspace:FindFirstChild("MilitaryPurgeDoor") and workspace.MilitaryPurgeDoor:FindFirstChild("MilitaryPurgeGamepad") and workspace.MilitaryPurgeDoor.MilitaryPurgeGamepad:FindFirstChild("Prompt"),
            gamepad = workspace:FindFirstChild("MilitaryPurgeDoor") and workspace.MilitaryPurgeDoor:FindFirstChild("MilitaryPurgeGamepad") and workspace.MilitaryPurgeDoor.MilitaryPurgeGamepad:FindFirstChild("GamePad"),
            priority = 4,
            element = "Military"
        },
        Paranormal = {
            prompt = workspace:FindFirstChild("ParanormalPurgeDoor") and workspace.ParanormalPurgeDoor:FindFirstChild("ParanormalPurgeGamepad") and workspace.ParanormalPurgeDoor.ParanormalPurgeGamepad:FindFirstChild("Prompt"),
            gamepad = workspace:FindFirstChild("ParanormalPurgeDoor") and workspace.ParanormalPurgeDoor:FindFirstChild("ParanormalPurgeGamepad") and workspace.ParanormalPurgeDoor.ParanormalPurgeGamepad:FindFirstChild("GamePad"),
            priority = 5,
            element = "Paranormal"
        }
    }
    print("[Purge Doors] Initialized successfully!")
end

local MovFlr = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.MoveToFloor
MovFlr:FireServer(tostring(getgenv().Mode), tonumber(getgenv().Floor),tonumber(getgenv().Stage))
local SetEle = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.SetInElevator
SetEle:FireServer(false)
task.wait()
print("mv flr")
-- === DYNAMIC FLOOR SELECTION === --

local function getTargetPromptPart(targetFloor, targetRoom)
    local floorsFolder = workspace:FindFirstChild("_Floors")
    if not floorsFolder then return nil end

    -- 1. Try to find the room dynamically using Attributes
    for _, floorModel in pairs(floorsFolder:GetChildren()) do
        local conditions = floorModel:FindFirstChild("ConditionModels")
        if conditions then
            for _, roomModel in pairs(conditions:GetChildren()) do
                -- Check if the Attributes match our current Floor and Stage
                if roomModel:GetAttribute("Floor") == targetFloor and roomModel:GetAttribute("Room") == targetRoom then
                    local pad = roomModel:FindFirstChild("GamePad1")
                    if pad and pad:FindFirstChild("Prompt") then
                        return pad.Prompt
                    end
                end
            end
        end
    end

    -- 2. Fallback based on naming conventions if Attributes fail
    local floorName = "Floor" .. tostring(targetFloor)
    if targetFloor == 2 then floorName = "Floor2-Toys" end
    
    local specificFloor = floorsFolder:FindFirstChild(floorName)
    if specificFloor then
        -- Floor 4 structure fallback
        if specificFloor:FindFirstChild("ConditionModels") then
            local roomName = "Room" .. tostring(targetRoom) .. "Complete"
            local roomData = specificFloor.ConditionModels:FindFirstChild(roomName)
            if roomData and roomData:FindFirstChild("GamePad1") and roomData.GamePad1:FindFirstChild("Prompt") then
                return roomData.GamePad1.Prompt
            end
        end
        -- Floor 2 fallback structure based on your original script
        if targetFloor == 2 and specificFloor:FindFirstChild("GamePad1") and specificFloor.GamePad1:FindFirstChild("Prompt") then
            return specificFloor.GamePad1.Prompt
        end
    end

    return nil
end

local promptPart = getTargetPromptPart(getgenv().Floor, getgenv().Stage)
print(promptPart)
local proximityPrompt = nil
--[[
local exitPart = workspace._Floors.Floor4["Story#Floor4Elevator"].Exit
repeat
    task.wait(0.1)
    local char = player.Character
    if char then
        local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
        if humanoidRoot then
            local distance = (humanoidRoot.Position - exitPart.CFrame.Position).Magnitude
            print("Distance to Exit: " .. tostring(distance))
        end
    end
until (player.Character and player.Character:FindFirstChild("HumanoidRootPart") and (player.Character.HumanoidRootPart.Position - exitPart.CFrame.Position).Magnitude <= proximityThreshold)

print("Player is close to Exit!")
]]

-- === EVENT/GARDEN MODE === --
if getgenv().Mode == "Event" or getgenv().Mode == "Garden" then
    print("Starting " .. getgenv().Mode .. " mode selection...")
    
    -- Get open purge doors
    local openDoors = getOpenPurgeDoors()
    
    if #openDoors == 0 then
        warn("No purge doors are currently open!")
    else
        print("Found " .. #openDoors .. " open doors")
        for _, doorInfo in pairs(openDoors) do
            print("  - " .. doorInfo.name .. " (Priority: " .. doorInfo.data.priority .. ")")
        end
        
        -- Get highest priority door
        local targetDoor = getHighestPriorityDoor(openDoors)
        print("Selected door: " .. targetDoor.name)
        
        -- Wait for correct loadout
        local loadoutCorrect = waitForCorrectLoadout(targetDoor.name, 120)
        
        if loadoutCorrect and targetDoor.data.prompt then
            promptPart = targetDoor.data.prompt
            proximityPrompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
            
            local targetPos = promptPart.WorldCFrame.Position
            getgenv().TeleLoop = true
            
            -- Only create platform if using teleport mode
            local platform
            if not getgenv().Walk then
                local platPos = promptPart.WorldCFrame.Position - Vector3.new(0, 20, 0)
                platform = Instance.new("Part")
                platform.Name = "dgdfghrthhfgplatform"
                platform.Shape = Enum.PartType.Block
                platform.Size = Vector3.new(10, 1, 10)
                platform.Color = Color3.fromRGB(0, 255, 0)
                platform.Material = Enum.Material.Neon
                platform.CanCollide = true
                platform.CFrame = CFrame.new(platPos)
                platform.Transparency = 0.3
                platform.Parent = workspace
                task.wait(1)
                print("created platform?")
            end
            
            if getgenv().Walk == true then
                -- WALK MODE
                local char = player.Character
                if char then
                    local humanoid = char:FindFirstChild("Humanoid")
                    if humanoid then
                        humanoid:MoveTo(targetPos)
                        print("Walking to " .. targetDoor.name .. " door...")
                        
                        local walkTimeout = tick() + 120
                        repeat
                            task.wait(0.1)
                            char = player.Character
                            if not char then break end
                            local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
                            if humanoidRoot then
                                local distance = (humanoidRoot.Position - targetPos).Magnitude
                                if distance <= proximityThreshold then
                                    print("Reached " .. targetDoor.name .. " door! Distance: " .. tostring(distance))
                                    getgenv().TeleLoop = false
                                    break
                                end
                                if humanoid:GetState() == Enum.HumanoidStateType.Running or humanoid:GetState() == Enum.HumanoidStateType.Landed then
                                    humanoid:MoveTo(targetPos)
                                end
                            end
                            if tick() > walkTimeout then
                                warn("Walk timeout!")
                                break
                            end
                        until false
                    end
                end
            else
                -- TELEPORT MODE
                while getgenv().TeleLoop do
                    task.wait()
                    local char = player.Character
                    if not char then continue end
                    local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
                    local humanoid = char:FindFirstChild("Humanoid")
                    if not humanoidRoot or not humanoid then continue end
                    
                    local distance = (humanoidRoot.Position - targetPos).Magnitude
                    if distance <= proximityThreshold then
                        getgenv().TeleLoop = false
                        print("Teleport loop broken at " .. targetDoor.name .. " door!")
                        break
                    else
                        humanoidRoot.Velocity = Vector3.new(0, 0, 0)
                        humanoidRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
                        humanoid:ChangeState(Enum.HumanoidStateType.Flying)
                        
                        task.spawn(function()
                            humanoidRoot.CFrame = CFrame.new(targetPos)
                            task.wait()
                        end)
                    end
                end
            end
            
            task.wait(1)
            
            if proximityPrompt then
                proximityPrompt.MaxActivationDistance = math.huge
                proximityPrompt.HoldDuration = 0
                fireproximityprompt(proximityPrompt)
                warn("Prompt fired for: " .. targetDoor.name)
            end
            
            task.wait()
            
            local gamePadDir = targetDoor.data.gamepad
            if gamePadDir then
                pcall(function()
                    local setCapacityRemote = gamePadDir:FindFirstChild("RF") and gamePadDir.RF:FindFirstChild("setCapacity")
                    if setCapacityRemote then
                        setCapacityRemote:InvokeServer(1)
                        print("set capacity")
                    end
                end)

                task.wait()

                pcall(function()
                    local setCapacityRemote = gamePadDir:FindFirstChild("RF") and gamePadDir.RF:FindFirstChild("setCapacity")
                    if setCapacityRemote then
                        setCapacityRemote:InvokeServer(1)
                        print("set capacity")
                    end
                end)

                task.wait(0.25)

                pcall(function()
                    local startRemote = gamePadDir:FindFirstChild("RE") and gamePadDir.RE:FindFirstChild("Start")
                    if startRemote then
                        startRemote:FireServer()
                        print("started event")
                    end
                end)
            else
                warn("Could not find GamePad for " .. targetDoor.name)
            end
        else
            warn("Loadout check failed or prompt not found for " .. targetDoor.name)
        end
    end

-- === STORY MODE === --
elseif promptPart then
    proximityPrompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
    
    local targetPos = promptPart.WorldCFrame.Position
    getgenv().TeleLoop = true
    
    local platform
    if not getgenv().Walk then
        local platPos = promptPart.WorldCFrame.Position - Vector3.new(0, 20, 0)
        platform = Instance.new("Part")
        platform.Name = "dgdfghrthhfgplatform"
        platform.Shape = Enum.PartType.Block
        platform.Size = Vector3.new(10, 1, 10)
        platform.Color = Color3.fromRGB(0, 255, 0)
        platform.Material = Enum.Material.Neon
        platform.CanCollide = true
        platform.CFrame = CFrame.new(platPos)
        platform.Transparency = 0.3
        platform.Parent = workspace
        task.wait(1)
        print("created platform?")
    end
    
    if getgenv().Walk == true then
        -- WALK MODE
        local char = player.Character
        if char then
            local humanoid = char:FindFirstChild("Humanoid")
            if humanoid then
                humanoid:MoveTo(targetPos)
                print("Walking to target position...")
                
                local walkTimeout = tick() + 120
                repeat
                    task.wait(0.1)
                    char = player.Character
                    if not char then break end
                    local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
                    if humanoidRoot then
                        local distance = (humanoidRoot.Position - targetPos).Magnitude
                        if distance <= proximityThreshold then
                            print("Reached target! Distance: " .. tostring(distance))
                            getgenv().TeleLoop = false
                            break
                        end
                        if humanoid:GetState() == Enum.HumanoidStateType.Running or humanoid:GetState() == Enum.HumanoidStateType.Landed then
                            humanoid:MoveTo(targetPos)
                        end
                    end
                    if tick() > walkTimeout then
                        warn("Walk timeout! Fell back to teleport.")
                        break
                    end
                until false
            end
        end
    else
        -- TELEPORT MODE
        while getgenv().TeleLoop do
            task.wait()
            local char = player.Character
            if not char then continue end
            local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChild("Humanoid")
            if not humanoidRoot or not humanoid then continue end
            
            local distance = (humanoidRoot.Position - targetPos).Magnitude
            if distance <= proximityThreshold then
                getgenv().TeleLoop = false
                print("Teleport loop broken successfully at dynamic target!")
                break
            else
                humanoidRoot.Velocity = Vector3.new(0, 0, 0)
                humanoidRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
                humanoid:ChangeState(Enum.HumanoidStateType.Flying)
                
                task.spawn(function()
                    humanoidRoot.CFrame = CFrame.new(targetPos)
                    task.wait()
                end)
                
                print("teleported? Distance: " .. tostring(distance))
            end
        end
    end

    task.wait(1)

    if proximityPrompt then
        proximityPrompt.MaxActivationDistance = math.huge
        proximityPrompt.HoldDuration = 0
        fireproximityprompt(proximityPrompt)
        warn("Prompt fired: ", proximityPrompt.Parent.Name)
    end
    task.wait()

    local gamePadDir = promptPart.Parent:FindFirstChild("GamePad")
        
    if gamePadDir then
        pcall(function()
            local setCapacityRemote = gamePadDir:FindFirstChild("RF") and gamePadDir.RF:FindFirstChild("setCapacity")
            if setCapacityRemote then
                setCapacityRemote:InvokeServer(1)
                print("set")
            end
        end)

        task.wait()

        pcall(function()
            local setCapacityRemote = gamePadDir:FindFirstChild("RF") and gamePadDir.RF:FindFirstChild("setCapacity")
            if setCapacityRemote then
                setCapacityRemote:InvokeServer(1)
                print("set")
            end
        end)

        task.wait(0.25)

        pcall(function()
            local startRemote = gamePadDir:FindFirstChild("RE") and gamePadDir.RE:FindFirstChild("Start")
            if startRemote then
                startRemote:FireServer()
                 print("started")
            elseif getgenv().Floor == 2 then
                startRemote:InvokeServer(1)
                print("started")
            end
        end)
    else
        warn("Could not find GamePad directory to fire remotes dynamically.")
    end
else
    warn("Could not locate the prompt for Floor: " .. tostring(getgenv().Floor) .. " Room: " .. tostring(getgenv().Stage))
end
