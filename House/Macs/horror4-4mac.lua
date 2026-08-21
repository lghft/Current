local function hardMacro()
    currentMatchId = currentMatchId + 1
    table.clear(placedTowersByIndex)
    table.clear(placedTowersUIDByIndex)
    table.clear(autoUpgradeQueue)
    table.clear(towerModels) -- Clear tower model caches for new match
    table.clear(towerModelsById)

    UpdateMacroStep("Starting Match Template")
    Notify("print", "==================================================")
    Notify("print", "[Macro] Main match function started! Mode: " .. tostring(getgenv().UpgradeMode))
    Notify("print", "==================================================")

    if not initializeHotbar() then
        Notify("error", "[Macro] Failed to initialize hotbar! Aborting.")
        return
    end

    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local isMatchActive = true
    local firedWaves = {}
    
    -- WAIT FOR AND VOTE DIFFICULTY
    Notify("print", "[Macro] Waiting for difficulty vote GUI...")
    local difficultyGui = nil
    local diffWaitCount = 0
    while not difficultyGui and diffWaitCount < 50 do
        difficultyGui = findDynamicGui(PlayerGui, {"MainHud", "DifficultyVote"})
        if not difficultyGui then
            task.wait(0.1)
            diffWaitCount = diffWaitCount + 1
        end
    end
    
    if difficultyGui then
        Notify("print", "[Macro] Difficulty vote GUI found! Voting...")
        voteDifficulty("Horror",0)
        Notify("print", "[Macro] Waiting for vote GUI to disappear...")
        repeat task.wait(0.25) until not findDynamicGui(PlayerGui, {"MainHud", "DifficultyVote"})
        Notify("print", "[Macro] Difficulty GUI cleared. Macro active.")
    else
        Notify("warn", "[Macro] Difficulty vote GUI never appeared (might already be voted)")
    end

    -- Upgrade loop
    task.spawn(function()
        while isMatchActive and task.wait(0.1) do
            if #autoUpgradeQueue == 0 then continue end
            
            if getgenv().UpgradeMode == "Sequential" then
                local job = autoUpgradeQueue[1]
                if not job then continue end
                
                local serverId = placedTowersByIndex[job.towerIndex]
                
                if not serverId then 
                    if getgenv().Debug then
                        Notify("warn", "[Sequential] Tower #" .. tostring(job.towerIndex) .. " has no serverId yet")
                    end
                    continue 
                end
                
                -- Try to get level from cached model first (fastest)
                local currentLevel = getCachedTowerLevel(job.towerIndex)
                
                -- Fall back to full stats lookup if cache miss
                if not currentLevel then
                    local stats = getPlacedTowerStats(job.towerIndex)
                    if stats and stats.Level then
                        currentLevel = tonumber(stats.Level) or 1
                    else
                        currentLevel = job.trackedLevel
                        if getgenv().Debug then
                            --Notify("warn", "[Sequential] Using tracked level " .. tostring(currentLevel) .. " for tower #" .. tostring(job.towerIndex))
                        end
                    end
                end
                
                if not currentLevel then currentLevel = 1 end
                
                if currentLevel >= job.maxLevel then
                    Notify("print", "[Sequential] Completed: Tower #" .. tostring(job.towerIndex) .. " (Level " .. tostring(currentLevel) .. ")")
                    table.remove(autoUpgradeQueue, 1)
                    continue
                end
                
                if os.clock() - job.lastUpgradeTime >= job.interval then
                    local towerUid = placedTowersUIDByIndex[job.towerIndex]
                    local cost = getTowerCost(towerUid, currentLevel)
                    
                    if getgenv().Debug then
                        --Notify("print", "[Sequential] Tower #" .. tostring(job.towerIndex) .. " - Level: " .. tostring(currentLevel) .. "/" .. tostring(job.maxLevel) .. " | Cost: $" .. tostring(cost))
                    end
                    
                    if job.waitForMoney and cost > 0 and getPlayerCash() < cost then
                        continue
                    end
                    
                    local UpgradeTowerRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.UpgradeTower
                    if UpgradeTowerRemote then
                        if getgenv().Debug then
                            Notify("print", "[Sequential] Upgrading tower #" .. tostring(job.towerIndex) .. " from level " .. tostring(currentLevel) .. " to " .. tostring(currentLevel + 1))
                        end
                        UpgradeTowerRemote:FireServer(tonumber(serverId))
                        job.trackedLevel = currentLevel + 1
                        job.lastUpgradeTime = os.clock()
                        -- Wait for server to process upgrade
                        task.wait(0.2)
                    end
                end

            elseif getgenv().UpgradeMode == "Priority" then
                local i = 1
                while i <= #autoUpgradeQueue do
                    local job = autoUpgradeQueue[i]
                    local serverId = placedTowersByIndex[job.towerIndex]
                    
                    if not serverId then
                        if getgenv().Debug then
                            Notify("warn", "[Upgrade] Tower #" .. tostring(job.towerIndex) .. " has no serverId yet")
                        end
                        i = i + 1
                        continue
                    end
                    
                    -- Try to get level from cached model first (fastest)
                    local currentLevel = getCachedTowerLevel(job.towerIndex)
                    
                    -- Fall back to full stats lookup if cache miss
                    if not currentLevel then
                        local stats = getPlacedTowerStats(job.towerIndex)
                        if stats and stats.Level then
                            currentLevel = tonumber(stats.Level) or 1
                        else
                            currentLevel = job.trackedLevel
                            if getgenv().Debug then
                                Notify("warn", "[Upgrade] Using tracked level " .. tostring(currentLevel) .. " for tower #" .. tostring(job.towerIndex))
                            end
                        end
                    end
                    
                    if not currentLevel then currentLevel = 1 end
                    
                    -- Check if tower is complete
                    if currentLevel >= job.maxLevel then
                        Notify("print", "[Upgrade] Priority Completed: Tower #" .. tostring(job.towerIndex) .. " (Level " .. tostring(currentLevel) .. ")")
                        table.remove(autoUpgradeQueue, i)
                        -- Don't increment i here because the next tower shifts into this index
                        continue 
                    end
                    
                    -- Get cost for next upgrade
                    local towerUid = placedTowersUIDByIndex[job.towerIndex]
                    local cost = getTowerCost(towerUid, currentLevel)
                    local hasEnoughCash = (cost == 0 or getPlayerCash() >= cost)
                    
                    if getgenv().Debug then
                        Notify("print", "[Upgrade] Tower #" .. tostring(job.towerIndex) .. " - Level: " .. tostring(currentLevel) .. "/" .. tostring(job.maxLevel) .. " | Cost: $" .. tostring(cost) .. " | Cash: $" .. tostring(getPlayerCash()))
                    end
                    
                    -- Wait for cash if needed
                    if job.waitForMoney and not hasEnoughCash then
                        break
                    end
                    
                    -- Upgrade if interval passed
                    if os.clock() - job.lastUpgradeTime >= job.interval then
                        local UpgradeTowerRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.UpgradeTower
                        if UpgradeTowerRemote then
                            if getgenv().Debug then
                                Notify("print", "[Upgrade] Upgrading tower #" .. tostring(job.towerIndex) .. " from level " .. tostring(currentLevel) .. " to " .. tostring(currentLevel + 1))
                            end
                            UpgradeTowerRemote:FireServer(tonumber(serverId))
                            job.trackedLevel = currentLevel + 1
                            job.lastUpgradeTime = os.clock()
                            -- Wait for server to process upgrade
                            task.wait(0.2)
                        end
                    end
                    
                    i = i + 1
                end
            end
        end
    end)

    -- Wave actions
    local function wv1()
        getgenv().Ability = true
        spd(2)
        
        placeTower(3,Vector3.new(9611.64165, -24.37354, -116.84044),1) --1
        placeTower(2,Vector3.new(9628, -24, -107),1)--2
        --2 saint
        placeTower(3,Vector3.new(9611.641615, -24.37354, -116.84084),1)--3
        placeTower(3,Vector3.new(9611.64165, -24.373554, -116.840484),1)--4
        --2 dd
        placeTower(2,Vector3.new(9628, -24, -107),1)--5
        placeTower(2,Vector3.new(9628, -24, -107),1)--6
        --3 hf
        placeTower(5,Vector3.new(9646.0925, -24.5050098, -117.62257568),1)--7
        placeTower(5,Vector3.new(9646.09035, -24.508, -117.627968),1)--8
        placeTower(5,Vector3.new(9646.0203125, -24.50398, -117.6257568),1)--9
        --3 angel
        placeTower(1,Vector3.new(9646.145, -24.3464, -123.723),1)--10
        placeTower(1,Vector3.new(9646.145, -24.3464, -123.723),1)--11
        placeTower(1,Vector3.new(9646.145, -24.3464, -123.723),1)--12
        --3 duchess
        placeTower(4,Vector3.new(9646.09035, -24.508, -117.627968),1)--13
        placeTower(4,Vector3.new(9646.09035, -24.508, -117.627968),1)--14
        placeTower(4,Vector3.new(9646.09035, -24.508, -117.627968),1)--15
        towerAnimcCheck()
    end

    local function wv3()
        autoUpgradeTower(7, true, 1)
        autoUpgradeTower(8, true, 1)
        autoUpgradeTower(9, true, 1)
        towerAnimcCheck()
    end
    local function wv11()
        autoUpgradeTower(2, true, 1)
        autoUpgradeTower(10, true, 1)
        autoUpgradeTower(1, true, 1)
        towerAnimcCheck()
    end
    local function wv19()
        autoUpgradeTower(5, true, 1)
        autoUpgradeTower(6, true, 1)
        towerAnimcCheck()
    end
    
    local waveActions = {
        [1] = wv1, [3] = wv3,[11] = wv11, [19] = wv19
    }

    -- Wave detection loop
    task.spawn(function()
        while isMatchActive and task.wait(0.5) do
            local gameOverGui = findDynamicGui(PlayerGui, {"MainHud", "Hud", "RoundHud", "Hud", "GameOver"})
            if gameOverGui then
                UpdateMacroStep("Match Ended - Cleaning up")
                Notify("print", "[Macro] GameOver UI spawned. Stopping loops...")
                getgenv().Ability = false
                isMatchActive = false

                if getgenv().Replay == true then
                    UpdateMacroStep("Voting Replay")
                    local RespondRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.RespondToQuery
                    if RespondRemote then
                        RespondRemote:FireServer("game_over", true)
                    end
                    
                    Notify("print", "[Macro] Waiting for new match DifficultyVote GUI...")
                    task.wait(5)
                    task.spawn(TemplateMacro)
                else
                    UpdateMacroStep("Returning to Lobby")
                    local RespondRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.RespondToQuery
                    if RespondRemote then
                        RespondRemote:FireServer("game_over", false)
                    end
                end
                break
            end
            
            local waveLabel = findDynamicGui(PlayerGui, {"MainHud", "Hud", "RoundHud", "Hud", "Inner", "CentreTop", "Info", "WaveCounter"})
            if waveLabel and waveLabel:IsA("TextLabel") then
                local currentWave = tonumber(tostring(waveLabel.Text):match("Wave%s*(%d+)%s*/"))
                if currentWave and waveActions[currentWave] and not firedWaves[currentWave] then
                    firedWaves[currentWave] = true
                    UpdateMacroStep("Wave " .. tostring(currentWave))
                    Notify("print", "[Macro] Triggering Wave " .. tostring(currentWave) .. " routine.")
                    task.spawn(waveActions[currentWave])
                end
            end
        end
    end)
end
