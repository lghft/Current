repeat task.wait() until game:IsLoaded()
local StarterGui = game:GetService("StarterGui")

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

getgenv().Floor = 4
getgenv().Stage = 4 -- Acts as the "Room" variable

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
LoadFlr:InvokeServer("Story", tonumber(getgenv().Floor))
print("ld flr")
task.wait()
local MovFlr = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.MoveToFloor
MovFlr:FireServer("Story", tonumber(getgenv().Floor))
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

if promptPart then
    proximityPrompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
    
    -- Calculate position 20 studs below the Prompt's WorldCFrame
    local targetPos = promptPart.WorldCFrame.Position - Vector3.new(0, 15, 0)
    getgenv().TeleLoop = true
    local platPos = promptPart.WorldCFrame.Position - Vector3.new(0, 20, 0)
    local platform = Instance.new("Part")
    platform.Name = "dgdfghrthhfgplatform"
    platform.Shape = Enum.PartType.Block
    platform.Size = Vector3.new(10, 1, 10) -- 10x1x10 studs
    platform.Color = Color3.fromRGB(0, 255, 0) -- Green
    platform.Material = Enum.Material.Neon
    platform.CanCollide = true
    platform.CFrame = CFrame.new(platPos)
    platform.Transparency = 0.3 -- Semi-transparent so you can see through
    platform.Parent = workspace
    task.wait(1)
    print("created platform?")
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
        -- Reset velocity to prevent physics from pulling back
        humanoidRoot.Velocity = Vector3.new(0, 0, 0)
        humanoidRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        
        -- Set humanoid state to prevent interference
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
        humanoid:ChangeState(Enum.HumanoidStateType.Flying)
        
        -- Teleport
        task.spawn(function()
            while true do
                humanoidRoot.CFrame = CFrame.new(targetPos)
                task.wait()
            end
        end)
        
        print("teleported? Distance: " .. tostring(distance))
    end
end
else
    warn("Could not locate the prompt for Floor: " .. tostring(getgenv().Floor) .. " Room: " .. tostring(getgenv().Stage))
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
