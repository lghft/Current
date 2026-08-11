print("lby?")
getgenv().IsLDLD = true
getgenv().Active = "eventhard"
if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(4)

task.spawn(function()
    repeat task.wait() until game.CoreGui:FindFirstChild('RobloxPromptGui')

    local lp,po,ts = game:GetService('Players').LocalPlayer,game.CoreGui.RobloxPromptGui.promptOverlay,game:GetService('TeleportService')

    po.ChildAdded:connect(function(a)
        if a.Name == 'ErrorPrompt' then
            repeat
                ts:Teleport(game.PlaceId)
                task.wait(2)
            until false
        end
    end)
end)

-- Safer way to wait for GUI elements with proper error handling
local function waitForGui(timeout)
    timeout = timeout or 30
    local startTime = tick()
    repeat
        task.wait(0.1)
        local success, result = pcall(function()
            local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 1)
            local mainGui = playerGui:WaitForChild("MainGui", 1)
            local mainFrames = mainGui:WaitForChild("MainFrames", 1)
            local loadingScreen = mainFrames:WaitForChild("LoadingScreen", 1)
            return loadingScreen.Visible == false
        end)
        if success and result then break end
        if tick() - startTime > timeout then
            warn("GUI load timeout after " .. timeout .. " seconds")
            break
        end
    until false
end

waitForGui(120)
print("Lby Loaded! hell yeah!")

local char = game.Players.LocalPlayer.Character
local Players = game:GetService('Players')
local plrAmount = #Players:GetPlayers()
local eHtele = workspace.Lobby.SummerEventLobby.EventTeleporters.SummerEventHardTeleporter3["Cylinder.119"].VFX.hitbox
local eRtele = workspace.Lobby.SummerEventLobby.EventTeleporters.SummerEventRaidTeleporter["Cylinder.119"].VFX.hitbox
local dtele = workspace.Lobby.DungeonLobby.DungeonTeleporters.Teleporter1.Teleport.DisplayPart
local stele = workspace.Lobby.ClassicPartyTeleporters.Teleporter2
local ptyFind = game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Main2.PartyFinder
local proximityThreshold = 50
getgenv().TeleLoop = true
getgenv().WEBHOOK_URL = "https://discord.com/api/webhooks/1414475376230535199/F6V5IZJkOUMdxd-ZdC32JdlaTw-FGDz-raRMGW7a6FsYTmYtRkqOSfLy123hat3xSNR1"
loadstring(game:HttpGet('https://raw.githubusercontent.com/lghft/Current/refs/heads/main/utd/webhook.lua'))()
function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

-- Helper function to safely get nested GUI elements
local function safeGetGui(path, timeout)
    timeout = timeout or 5
    local success, result = pcall(function()
        local current = path[1]
        for i = 2, #path do
            current = current:WaitForChild(path[i], timeout)
        end
        return current
    end)
    return success and result or nil
end

queueteleport =  missing("function", queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport))
local TeleportCheck = false
Players.LocalPlayer.OnTeleport:Connect(function(State)
	if (not TeleportCheck) and queueteleport then
		TeleportCheck = true
		queueteleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/lghft/Current/refs/heads/main/utd/Lby.lua'))()")
	end
end)

task.wait()
if plrAmount == 1 and game.Players.LocalPlayer and game.Workspace.Lobby and plrAmount < 2 then
    print("=1 plr")
    if getgenv().Active == "eventhard" then -- eHtelo
        task.spawn(function()
            while getgenv().TeleLoop == true do
                task.wait(1)
                local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
                local targetPos = eHtele.Position
                if not humanoidRoot then break end
                
                local distance = (humanoidRoot.Position - targetPos).Magnitude
                
                if distance <= proximityThreshold then
                    getgenv().TeleLoop = false
                    print("telsse Loop Breeak!?#")
                    break
                else
                    char:MoveTo(eHtele.Position)
                end
            end
        end)
        
    elseif getgenv().Active == "eventraid" then -- ERtele
        print("YEAH RAIDING!!!!#@(#?")
        char:MoveTo(eRtele.Position)
        task.wait(60)
        if plrAmount == 1 then
            task.spawn(function()
                while getgenv().TeleLoop == true do
                    task.wait(1)
                    local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
                    local targetPos = eRtele.Position
                    if not humanoidRoot then break end
                    
                    local distance = (humanoidRoot.Position - targetPos).Magnitude
                    
                    if distance <= proximityThreshold then
                        getgenv().TeleLoop = false
                        print("telsse Loop Breeak!?#")
                        break
                    else
                        char:MoveTo(Vector3.new(11249, 23, 90))
                    end
                end
            end)
        end
    elseif dtele and getgenv().Active == "dun" then
        task.wait(1)
        local success = pcall(function()
            local dunMap = game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.FloorSelection.SelectedMap.MapName
            if dunMap.Text == "Forsaken Prison - Floor 10" or dunMap.Text == "Forsaken Prison - Floor 9" or dunMap.Text == "Desolate Crypt - Floor 11" then
                game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("GlobalInit"):WaitForChild("RemoteEvents"):WaitForChild("PlayerClaimDungeonReward"):FireServer()
                print("YESSS Collected...")
            end
        end)
        if not success then warn("Failed to check dungeon reward") end
        
        task.wait()
        print("=1 dun")
        wait()
        if char:FindFirstChild("PrimaryPart") then
            char.PrimaryPart.CFrame = CFrame.new(43.3874359, -23.1395016, 4058.01099, -0.766061664, 0, 0.642767608, 0, 1, 0, -0.642767608, 0, -0.766061664)
        end
        
        local floorSelection = safeGetGui({game:GetService("Players").LocalPlayer.PlayerGui, "MainGui", "MainFrames", "FloorSelection"}, 10)
        if floorSelection then
            repeat wait() until floorSelection.Visible == true
            local hard = floorSelection:FindFirstChild("SelectedMap") and floorSelection.SelectedMap:FindFirstChild("Buttons") and floorSelection.SelectedMap.Buttons:FindFirstChild("HardcoreButton")
            if hard then
                firesignal(hard.Activated)
                wait(1)
                local strt = floorSelection.SelectedMap.Buttons:FindFirstChild("StartButton")
                if strt then
                    firesignal(strt.Activated)
                else
                    warn("StartButton not found")
                end
            else
                warn("HardcoreButton not found")
            end
        else
            warn("FloorSelection GUI not found")
        end
    elseif stele and getgenv().Active == "story" then
        print("=1 story")
        wait()
        if char:FindFirstChild("PrimaryPart") then
            char.PrimaryPart.CFrame = CFrame.new(-269, 34, -135)
        end
        wait()
        
        local mapSelection = safeGetGui({game:GetService("Players").LocalPlayer.PlayerGui, "MainGui", "MainFrames", "MapSelection"}, 10)
        if mapSelection then
            repeat task.wait() until mapSelection.Visible == true
            
            local mapS = mapSelection:FindFirstChild("MapList") and mapSelection.MapList:FindFirstChild("ScrollingFrame") and mapSelection.MapList.ScrollingFrame:FindFirstChild("LasNoches")
            if mapS then
                firesignal(mapS.Activated)
                task.wait(0.5)
                local hrdB = mapSelection:FindFirstChild("SelectedMap") and mapSelection.SelectedMap:FindFirstChild("Buttons") and mapSelection.SelectedMap.Buttons:FindFirstChild("HardButton")
                if hrdB then
                    firesignal(hrdB.Activated)
                    task.wait(0.55)
                    local strtB = mapSelection.SelectedMap.Buttons:FindFirstChild("StartButton")
                    if strtB then
                        firesignal(strtB.Activated)
                    else
                        warn("StartButton not found")
                    end
                else
                    warn("HardButton not found")
                end
            else
                warn("LasNoches map not found")
            end
        else
            warn("MapSelection GUI not found")
        end
        wait()
    end
elseif plrAmount > 1 and game.Workspace.Lobby then
    print(">1")
    if ptyFind and ptyFind.Visible == true then
        task.wait(1)
        spawn(function()
            while true do
                local success, _ = pcall(function()
                    local partyFinder = game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.PartyFinder
                    local genServ = partyFinder.Main.MyServerPanel.Main.Content.LastSavedServer.Panel.GenerateNewServerButton
                    firesignal(genServ.Activated)
                    task.wait(1)
                    local jlservB = partyFinder.Main.MyServerPanel.Main.Content.LastSavedServer.Panel.Join
                    firesignal(jlservB.Activated)
                end)
                if not success then
                    warn("Party finder error, retrying...")
                    task.wait(2)
                else
                    task.wait()
                end
            end
        end)
    end
end
