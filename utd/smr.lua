if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(4)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local towerFolder = game.Workspace:WaitForChild("EntityModels"):WaitForChild("Towers")

local placedTowers = {}
local currentTowerIndex = 0
getgenv().Ability = false
getgenv().Replay = true
getgenv().Aizen = false

-- Non-blocking asynchronous listener for tower placement confirmations
task.spawn(function()
    print("[Init] Waiting for TowerPlacedSuccessfully remote to exist...")
    
    local Event
    local maxWait = 0
    
    -- Wait for the remote to be created (happens on first tower placement)
    while not Event and maxWait < 300 do
        Event = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
            and game:GetService("ReplicatedStorage").Modules:FindFirstChild("GlobalInit")
            and game:GetService("ReplicatedStorage").Modules.GlobalInit:FindFirstChild("RemoteEvents")
            and game:GetService("ReplicatedStorage").Modules.GlobalInit.RemoteEvents:FindFirstChild("TowerPlacedSuccessfully")
        
        if not Event then
            task.wait(0.5)
            maxWait = maxWait + 0.5
        end
    end
    
    if Event then
        print("[Init] TowerPlacedSuccessfully remote found! Setting up interception...")
        
        local lastPlacedTower = nil
        local lastPlaceTime = 0
        
        for _, Connection in getconnections(Event.OnClientEvent) do
            local old; old = hookfunction(Connection.Function, function(unitID, towerID, ...)
                local currentTime = tick()
                local key = tostring(unitID) .. ":" .. tostring(towerID)
                
                -- Check if this is a duplicate within 0.5 seconds
                if lastPlacedTower == key and (currentTime - lastPlaceTime) < 0.5 then
                    print(string.format("[Tower] Duplicate detected (unitID=%s, towerID=%s) - skipping", tostring(unitID), tostring(towerID)))
                    return old(unitID, towerID, ...)
                end
                
                currentTowerIndex = currentTowerIndex + 1
                
                local towerData = {
                    towerIndex = currentTowerIndex,
                    unitID = tostring(unitID),
                    towerID = tostring(towerID)
                }
                
                table.insert(placedTowers, towerData)
                print(string.format("[Tower Registered] Index: %d | UnitID: %s | TowerID: %s", currentTowerIndex, tostring(unitID), tostring(towerID)))
                
                lastPlacedTower = key
                lastPlaceTime = currentTime
                
                return old(unitID, towerID, ...)
            end)
        end
        
        -- Register any towers that were already placed before interception was set up
        print("[Init] Checking for pre-existing towers...")
        for _, tower in ipairs(towerFolder:GetChildren()) do
            currentTowerIndex = currentTowerIndex + 1
            local towerData = {
                towerIndex = currentTowerIndex,
                unitID = tostring(tower.Name),
                towerID = "pre-existing"
            }
            table.insert(placedTowers, towerData)
            print(string.format("[Tower Registered - Pre-existing] Index: %d | UnitID: %s", currentTowerIndex, tostring(tower.Name)))
        end
        
    else
        warn("[Warning] TowerPlacedSuccessfully remote was not created within timeout. Will rely on tower folder detection.")
    end
end)

-- Helper function to find a tower's data by sequential index
local function getTowerByIndex(index)
    for _, towerData in ipairs(placedTowers) do
        if towerData.towerIndex == index then
            return towerData
        end
    end
    return nil
end

function clickButton(ClickOnPart)
    local vim = game:GetService("VirtualInputManager")
    local inset1, inset2 = game:GetService("GuiService"):GetGuiInset()
    local insetOffset = inset1 - inset2
    local part = ClickOnPart
    local topLeft = part.AbsolutePosition + insetOffset
    local center = topLeft + (part.AbsoluteSize / 2)
    local X = center.X + 15
    local Y = center.Y
    vim:SendMouseButtonEvent(X, Y, 0, true, game, 0)
    task.wait(0.1)
    vim:SendMouseButtonEvent(X, Y, 0, false, game, 0)
    task.wait(1)
    print("Clicked: ", ClickOnPart)
end

function spd()
    local args = { "2" }
    ReplicatedStorage:WaitForChild("Modules")
    :WaitForChild("GlobalInit"):WaitForChild("RemoteEvents")
    :WaitForChild("ClientRequestGameSpeed"):FireServer(unpack(args))
end

function startMatch()
    ReplicatedStorage:WaitForChild("Modules")
    :WaitForChild("GlobalInit")
    :WaitForChild("RemoteEvents")
    :WaitForChild("PlayerVoteToStartMatch"):FireServer()
end

function placeUnit(towerID, pos, waittime, rotation)
    rotation = rotation or 0
    local placeRemote = ReplicatedStorage:WaitForChild("GenericModules"):WaitForChild("Service"):WaitForChild("Network"):WaitForChild("PlayerPlaceTower")
    local formattedTowerString = tostring(LocalPlayer.UserId) .. ":" .. tostring(towerID)
    
    placeRemote:FireServer(formattedTowerString, pos, rotation)
    task.wait(waittime or 1)
end

function upgradeUnit(towerIndex, pathSelection, waittime)
    local towerData = getTowerByIndex(towerIndex)
    if not towerData then return end
    
    local remote = ReplicatedStorage:WaitForChild("GenericModules"):WaitForChild("Service"):WaitForChild("Network"):WaitForChild("PlayerUpgradeTower")
    
    if pathSelection then
        remote:FireServer(towerData.unitID, pathSelection)
        task.wait(waittime or 0.5)
        remote:FireServer(towerData.unitID, pathSelection)
    else
        remote:FireServer(towerData.unitID)  -- Only send unitID if no path
    end
    
    task.wait(waittime or 0.5)
    if pathSelection then
        print(string.format("[Upgrade] Tower Index: %d | UnitID: %s | Path: %d", towerIndex, towerData.unitID, pathSelection))
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
    else
        print(string.format("[Upgrade] Tower Index: %d | UnitID: %s | No Path Specified", towerIndex, towerData.unitID))
    end
end

function _sellUnit(towerIndex, waittime)
    -- Implement selling logic here if needed
end

function targetUnit(towerIndex, targeting, waittime)
    local towerData = getTowerByIndex(towerIndex)
    if not towerData then return end

    local args = {
        [1] = tostring(towerData.unitID),
        [2] = tostring(targeting)
    }
    
    ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GlobalInit"):WaitForChild("RemoteEvents"):WaitForChild("PlayerSetTowerTargetMode"):FireServer(unpack(args))
    task.wait(waittime or 0.5)
end

function useTowerAbility(towerIndex, waittime)
    local towerData = getTowerByIndex(towerIndex)
    if not towerData then return end

    local args = {
        [1] = tostring(towerData.unitID)
    }

    ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GlobalInit"):WaitForChild("RemoteEvents"):WaitForChild("PlayerActivateTowerAbility"):FireServer(unpack(args))
    task.wait(waittime or 0.5) 
end

function autoTowerAbility(towerIndex, interval)
    task.spawn(function()
        while getgenv().Ability == true do
            local towerData = getTowerByIndex(towerIndex)
            if towerData then
                useTowerAbility(towerIndex, interval or 1)
            else
                task.wait(1) -- Wait for tower to be registered if called too early
            end
        end
    end)
end

function ragnaOnLastBoss(towerIndex)
    local enemiesFolder = workspace:WaitForChild("EntityModels"):WaitForChild("Enemies")
    print("[Ragna Logic] Wave 25 detected. Waiting for final boss (1 enemy remaining)...")
    local bossgui = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("BossGui")
    local Bossbar = bossgui.Bar
    repeat task.wait() until bossgui.Enabled == true
    print("[Ragna Logic] Boss GUI detected. Monitoring for final boss...")
    repeat task.wait() until Bossbar.Visible == true
    print("[Ragna Logic] Boss bar detected. Monitoring for final boss...")
    repeat task.wait(0.5) until #enemiesFolder:GetChildren() == 1
    print("[Ragna Logic] Final boss detected. Monitoring position and health for ability activation...")
    local lastBoss = enemiesFolder:GetChildren()[1]
    print("[Ragna Logic] Last boss detected: " .. lastBoss.Name)

    local DETECT_RADIUS = 55 -- studs

    while true do
        task.wait(0.2)

        local towerData = getTowerByIndex(towerIndex)
        if towerData and lastBoss and lastBoss.Parent and lastBoss:FindFirstChild("HumanoidRootPart") then
            local ragnaModel = workspace.EntityModels.Towers:FindFirstChild(towerData.unitID)

            if ragnaModel and ragnaModel:FindFirstChild("HumanoidRootPart") then
                local rPos = ragnaModel.HumanoidRootPart.Position
                local eHRP = lastBoss.HumanoidRootPart
                local ePos = eHRP.Position

                -- true circular/spherical distance check instead of box check
                local distance = (ePos - rPos).Magnitude
                local inRange = distance <= DETECT_RADIUS

                if inRange then
                    local healthFill = eHRP:FindFirstChild("EnemyGui")
                        and eHRP.EnemyGui:FindFirstChild("HealthBar")
                        and eHRP.EnemyGui.HealthBar:FindFirstChild("Frame")
                        and eHRP.EnemyGui.HealthBar.Frame:FindFirstChild("Fill")

                    if healthFill then
                        local isShielded = healthFill.BackgroundColor3 == Color3.fromRGB(0, 255, 255)
                        if not isShielded then
                            print("Boss isn't Shielded! Checking health bar color...")
                            if healthFill.BackgroundColor3 == Color3.fromRGB(115, 0, 255) then
                                print("[Ragna Logic] Boss in range with purple health bar! Activating ability...")
                                useTowerAbility(towerIndex, 0.5)
                            end
                        end
                    end
                end
            end
        else
            if not lastBoss or not lastBoss.Parent then
                print("[Ragna Logic] Boss defeated or despawned.")
                break
            end
        end
    end
end
function replayMatch()
    print("==================================================")
    print("[REPLAY Match] Main match function started!")
    print("==================================================")

    local waveLabel = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("Wave"):WaitForChild("WaveIndex")
    local endGui = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("RoundOver")
    
    local matchConnections = {}

    local function onRoundOver()
        if endGui.Visible == true then
            print("[Match Ended] RoundOver UI detected. Stopping loops and cleaning up...")
            getgenv().Ability = false
            
            for _, conn in ipairs(matchConnections) do
                if conn.Connected then
                    conn:Disconnect()
                end
            end
            table.clear(matchConnections)

            if getgenv().Replay == true then
                print("[Match Ended] Replay is enabled. Voting for replay...")
                if endGui.Continue.Visible then
                    ReplicatedStorage:WaitForChild("Modules")
                    :WaitForChild("GlobalInit"):WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReplay"):FireServer()
                else
                    print("[Replay] Continue button not visible. Returning To Lobby.")
                    game:GetService("ReplicatedStorage")
                    :WaitForChild("Modules")
                    :WaitForChild("GlobalInit")
                    :WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReturn"):FireServer()
                end
                
                
                -- Wait for the end screen to close
                repeat
                    task.wait(0.5)
                until endGui.Visible == false

                -- Wait until the old towers are cleared out of the workspace
                print("[Replay] Waiting for server to clear old match data...")
                repeat
                    task.wait(0.5)
                until #towerFolder:GetChildren() == 0

                -- Extra buffer to ensure cash & wave state are fully reset on the new map
                task.wait(3)
                
                -- Reset tracking tables for the fresh match
                table.clear(placedTowers)
                currentTowerIndex = 0
                
                print("[Replay] Starting new match sequence...")
                replayMatch()
                
            else
                print("[Match Ended] Waiting to lobby...")

                --[[
                ReplicatedStorage:WaitForChild("Modules")
                :WaitForChild("GlobalInit"):WaitForChild("RemoteEvents")
                :WaitForChild("PlayerRequestReturnLobby"):FireServer()
                ]]
            end
        end
    end

    table.insert(matchConnections, endGui:GetPropertyChangedSignal("Visible"):Connect(onRoundOver))
    onRoundOver()
    local function wv1()
        print("[Wave Action] >>> EXECUTING WAVE 1 FUNCTION <<<")
        spd()
        startMatch()
        placeUnit(230016, Vector3.new(-1170.2559814453, 135.236328125, -1688.1260986328), 1) -- dante (Index 1)
        placeUnit(226295, Vector3.new(-1288.8853759766, 144.26679992676, -1668.8966064453), 1) -- yumeko (Index 2)
        task.wait(1)
        placeUnit(233025, Vector3.new(-1507.9349365234, 134.66094970703, -1313.7093505859), 0) -- ichigo (Index 3) 229949
        --placeUnit(233025, Vector3.new(-1240.6032714844, 143.72987365723, -1697.6192626953), 0) -- emilia (Index 3)
        getgenv().Ability = true
        autoTowerAbility(3, 1) -- Auto-use Emilia's ability every 1 second
        task.wait()
        autoTowerAbility(2, 1)
        task.wait()
        placeUnit(228582, Vector3.new(-1508.0070800781, 137.1851348877, -1335.5341796875), 1) -- ulq (Index 4)
        --placeUnit(228582, Vector3.new(-1507.8286132812, 144.07293701172, -1390.3227539062), 1) -- ulq (Index 4)
        print("[Wave Action] >>> WAVE 1 COMPLETED <<<")
    end
    local function wv10()
        print("[Wave Action] >>> EXECUTING WAVE 10 FUNCTION <<<")
        placeUnit(233240, Vector3.new(-1189.3095703125, 137.37525939941, -1681.1402587891), 1) -- ragna (Index 5)
        --placeUnit(233240, Vector3.new(-1237.8453369141, 143.48547363281, -1678.2745361328), 1) -- ragna old placement (Index 5)
        upgradeUnit(5, 1, 1) -- chooses Ragna Comet path  
        task.wait(1)
        task.wait(1)
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
        if getgenv().Aizen == true then
            placeUnit(231880, Vector3.new(-1237.7738037109, 143.60464477539, -1682.4620361328), 1) -- aizen (Index 6)
        else
            placeUnit(231758, Vector3.new(-1175.7613525391, 135.85260009766, -1681.7412109375), 1) -- claudius (Index 6)
            upgradeUnit(6, 2, 1) -- chooses Claudius Bride path
            autoTowerAbility(6, 1) -- Auto-use Claudius's ability
            task.wait(1)
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
            --[[
            placeUnit(227497, Vector3.new(-1237.7738037109, 143.60464477539, -1682.4620361328), 1.5) -- choso (Index 6)
            placeUnit(227497, Vector3.new(-1235.8198242188, 143.49151611328, -1688.2373046875), 1.5) -- choso (Index 7)
            placeUnit(227497, Vector3.new(-1236.2359619141, 143.47979736328, -1685.6025390625), 1.5) -- choso (Index 8)
            task.wait(1)
            autoTowerAbility(6, 1) -- Auto-use Choso's ability
            task.wait(1)
            autoTowerAbility(7, 1) -- Auto-use Choso's ability
            task.wait(1)
            autoTowerAbility(8, 1) -- Auto-use Choso's ability
            ]]
        end
        print("[Wave Action] >>> WAVE 10 COMPLETED <<<")
    end

    local function wv15()
        print("[Wave Action] >>> EXECUTING WAVE 15 FUNCTION <<<")
        task.wait(1)
        if getgenv().Aizen == true then
            autoTowerAbility(6, 1) -- Auto-use Sacrifice
        end
        autoTowerAbility(6, 1)
        task.wait(1)
        print("[Wave Action] >>> WAVE 15 COMPLETED <<<")
    end

    local function wv25()
        print("[Wave Action] >>> EXECUTING WAVE 25 FUNCTION <<<")
        task.wait(5)
        task.spawn(function()
            print("[Wave Action] >>> Ragna on Last Boss Logic Initiated <<<")
            ragnaOnLastBoss(5)
        end)
    end

    local waveActions = {
        [1] = wv1,
        [10] = wv10,
        [15] = wv15,
        [25] = wv25,
    }

    local firedWaves = {}

    local function checkCurrentWave()
        local rawText = tostring(waveLabel.Text)
        local currentWave = tonumber(rawText:match("(%d+)%s*/"))

        print(string.format("[Wave Check] Raw Text: '%s' | Extracted Wave Number: %s", rawText, tostring(currentWave)))

        if currentWave and waveActions[currentWave] and not firedWaves[currentWave] then
            print(string.format("[Wave Check] Match found for Wave %d! Triggering action...", currentWave))
            firedWaves[currentWave] = true
            waveActions[currentWave]()
        end
    end

    table.insert(matchConnections, waveLabel:GetPropertyChangedSignal("Text"):Connect(checkCurrentWave))
    
    task.spawn(function()
        for i = 1, 15 do
            checkCurrentWave()
            if firedWaves[0] then
                break
            end
            task.wait(0.5)
        end
    end)
end
function summerMatch()
    print("==================================================")
    print("[SummerMatch] Main match function started!")
    print("==================================================")

    local waveLabel = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("Wave"):WaitForChild("WaveIndex")
    local endGui = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("RoundOver")
    
    local matchConnections = {}

    local function onRoundOver()
        if endGui.Visible == true then
            print("[Match Ended] RoundOver UI detected. Stopping loops and cleaning up...")
            getgenv().Ability = false
            
            for _, conn in ipairs(matchConnections) do
                if conn.Connected then
                    conn:Disconnect()
                end
            end
            table.clear(matchConnections)

            if getgenv().Replay == true then
                print("[Match Ended] Replay is enabled. Voting for replay...")
                if endGui.Continue.Visible then
                    ReplicatedStorage:WaitForChild("Modules")
                    :WaitForChild("GlobalInit"):WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReplay"):FireServer()
                else
                    print("[Replay] Continue button not visible. Returning To Lobby.")
                    game:GetService("ReplicatedStorage")
                    :WaitForChild("Modules")
                    :WaitForChild("GlobalInit")
                    :WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReturn"):FireServer()
                end
                
                -- Wait for the end screen to close
                repeat task.wait(0.5) until endGui.Visible == false

                -- Wait until the old towers are cleared out of the workspace
                print("[Replay] Waiting for server to clear old match data...")
                repeat
                    task.wait(0.5)
                until #towerFolder:GetChildren() == 0

                -- Extra buffer to ensure cash & wave state are fully reset on the new map
                task.wait(3)
                
                -- Reset tracking tables for the fresh match
                table.clear(placedTowers)
                currentTowerIndex = 0
                
                print("[Replay] Starting new match sequence...")
                replayMatch()
            else
                print("[Match Ended] Waiting to lobby...")
                --[[
                ReplicatedStorage:WaitForChild("Modules")
                :WaitForChild("GlobalInit"):WaitForChild("RemoteEvents")
                :WaitForChild("PlayerRequestReturnLobby"):FireServer()
                ]]
            end
        end
    end

    table.insert(matchConnections, endGui:GetPropertyChangedSignal("Visible"):Connect(onRoundOver))
    onRoundOver()

    spd()
    placeUnit(230016, Vector3.new(-1173.5047607422, 135.64385986328, -1687.5249023438), 1) -- dante (Index 1)
    placeUnit(226295, Vector3.new(-1307.4481201172, 144.26693725586, -1684.2392578125), 1) -- yumeko (Index 2)
    startMatch()

    local function wv1()
        print("[Wave Action] >>> EXECUTING WAVE 1 FUNCTION <<<")
        placeUnit(233025, Vector3.new(-1507.9349365234, 134.66094970703, -1313.7093505859), 0) -- ichigo (Index 3) 229949
        --placeUnit(233025, Vector3.new(-1240.6032714844, 143.72987365723, -1697.6192626953), 0) -- emilia (Index 3)
        getgenv().Ability = true
        autoTowerAbility(3, 1) -- Auto-use Emilia's ability every 1 second
        task.wait()
        autoTowerAbility(2, 1)
        task.wait()
        placeUnit(228582, Vector3.new(-1508.0070800781, 137.1851348877, -1335.5341796875), 1) -- ulq (Index 4)
        --placeUnit(228582, Vector3.new(-1507.8286132812, 144.07293701172, -1390.3227539062), 1) -- ulq (Index 4)
        print("[Wave Action] >>> WAVE 1 COMPLETED <<<")
    end
    local function wv10()
        print("[Wave Action] >>> EXECUTING WAVE 10 FUNCTION <<<")
        placeUnit(233240, Vector3.new(-1189.3095703125, 137.37525939941, -1681.1402587891), 1) -- ragna (Index 5)
        --placeUnit(233240, Vector3.new(-1237.8453369141, 143.48547363281, -1678.2745361328), 1) -- ragna old placement (Index 5)
        upgradeUnit(5, 1, 1) -- chooses Ragna Comet path  
        task.wait(1)
        task.wait(1)
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
        if getgenv().Aizen == true then
            placeUnit(231880, Vector3.new(-1237.7738037109, 143.60464477539, -1682.4620361328), 1) -- aizen (Index 6)
        else
            placeUnit(231758, Vector3.new(-1175.7613525391, 135.85260009766, -1681.7412109375), 1) -- claudius (Index 6)
            upgradeUnit(6, 2, 1) -- chooses Claudius Bride path
            autoTowerAbility(6, 1) -- Auto-use Claudius's ability
            task.wait(1)
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
            --[[
            placeUnit(227497, Vector3.new(-1237.7738037109, 143.60464477539, -1682.4620361328), 1.5) -- choso (Index 6)
            placeUnit(227497, Vector3.new(-1235.8198242188, 143.49151611328, -1688.2373046875), 1.5) -- choso (Index 7)
            placeUnit(227497, Vector3.new(-1236.2359619141, 143.47979736328, -1685.6025390625), 1.5) -- choso (Index 8)
            task.wait(1)
            autoTowerAbility(6, 1) -- Auto-use Choso's ability
            task.wait(1)
            autoTowerAbility(7, 1) -- Auto-use Choso's ability
            task.wait(1)
            autoTowerAbility(8, 1) -- Auto-use Choso's ability
            ]]
        end
        print("[Wave Action] >>> WAVE 10 COMPLETED <<<")
    end

    local function wv15()
        print("[Wave Action] >>> EXECUTING WAVE 15 FUNCTION <<<")
        task.wait(1)
        if getgenv().Aizen == true then
            autoTowerAbility(6, 1) -- Auto-use Sacrifice
        end
        autoTowerAbility(6, 1)
        task.wait(1)
        print("[Wave Action] >>> WAVE 15 COMPLETED <<<")
    end

    local function wv25()
        print("[Wave Action] >>> EXECUTING WAVE 25 FUNCTION <<<")
        task.wait(5)
        task.spawn(function()
            print("[Wave Action] >>> Ragna on Last Boss Logic Initiated <<<")
            ragnaOnLastBoss(5)
        end)
    end

    local waveActions = {
        [1] = wv1,
        [10] = wv10,
        [15] = wv15,
        [25] = wv25,
    }

    local firedWaves = {}

    local function checkCurrentWave()
        local rawText = tostring(waveLabel.Text)
        local currentWave = tonumber(rawText:match("(%d+)%s*/"))

        print(string.format("[Wave Check] Raw Text: '%s' | Extracted Wave Number: %s", rawText, tostring(currentWave)))

        if currentWave and waveActions[currentWave] and not firedWaves[currentWave] then
            print(string.format("[Wave Check] Match found for Wave %d! Triggering action...", currentWave))
            firedWaves[currentWave] = true
            waveActions[currentWave]()
        end
    end

    table.insert(matchConnections, waveLabel:GetPropertyChangedSignal("Text"):Connect(checkCurrentWave))
    
    task.spawn(function()
        for i = 1, 15 do
            checkCurrentWave()
            if firedWaves[0] then
                break
            end
            task.wait(0.5)
        end
    end)
end

summerMatch()
