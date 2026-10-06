-- Script Path: ReplicatedStorage.Modules.Round.systems.client.EnemyTrackerUI
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Entities = require(ReplicatedStorage.Modules.Entities)
local ct = require(ReplicatedStorage.Modules.Entities.ct)

return Entities.add_system(function(world)
    -- Only run this UI tracking system on the client side
    if not RunService:IsClient() then
        return function() end
    end

    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- 1. Remove old GUI if it already exists (ensures clean re-execution)
    if playerGui:FindFirstChild("EnemyTrackerGui") then
        playerGui.EnemyTrackerGui:Destroy()
    end

    -- State for Bosses-Only filter setting
    local bossesOnly = false

    -- 2. Create ScreenGui Container
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EnemyTrackerGui"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    -- 3. Create Main Window Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 400, 0, 440)
    mainFrame.Position = UDim2.new(0, 20, 0, 120)
    mainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 8)
    mainCorner.Parent = mainFrame

    -- 4. Header Bar (Draggable, Title, Boss Toggle, & Exit Button)
    local headerFrame = Instance.new("Frame")
    headerFrame.Size = UDim2.new(1, 0, 0, 36)
    headerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    headerFrame.BorderSizePixel = 0
    headerFrame.Parent = mainFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -140, 1, 0)
    titleLabel.Position = UDim2.new(0, 10, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "Active Enemies Tracker"
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = headerFrame

    -- Boss Filter Toggle Button
    local filterButton = Instance.new("TextButton")
    filterButton.Size = UDim2.new(0, 95, 0, 24)
    filterButton.Position = UDim2.new(1, -132, 0.5, -12)
    filterButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    filterButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    filterButton.TextSize = 10
    filterButton.Font = Enum.Font.GothamBold
    filterButton.Text = "Filter: All"
    filterButton.Parent = headerFrame

    local filterCorner = Instance.new("UICorner")
    filterCorner.CornerRadius = UDim.new(0, 4)
    filterCorner.Parent = filterButton

    -- Exit Close Button
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 26, 0, 26)
    closeButton.Position = UDim2.new(1, -32, 0.5, -13)
    closeButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextSize = 12
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "X"
    closeButton.Parent = headerFrame

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 4)
    closeCorner.Parent = closeButton

    closeButton.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)

    filterButton.MouseButton1Click:Connect(function()
        bossesOnly = not bossesOnly
        if bossesOnly then
            filterButton.Text = "Filter: Bosses"
            filterButton.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
        else
            filterButton.Text = "Filter: All"
            filterButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        end
    end)

    -- Make Window Draggable via Header
    local dragging, dragInput, dragStart, startPos
    headerFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    headerFrame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- 5. Scrolling Frame for the Enemy List
    local scrollingFrame = Instance.new("ScrollingFrame")
    scrollingFrame.Size = UDim2.new(1, -12, 1, -48)
    scrollingFrame.Position = UDim2.new(0, 6, 0, 42)
    scrollingFrame.BackgroundTransparency = 1
    scrollingFrame.BorderSizePixel = 0
    scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollingFrame.ScrollBarThickness = 6
    scrollingFrame.Parent = mainFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 6)
    listLayout.Parent = scrollingFrame

    -- 6. Cache ECS query
    local enemyQuery = world:query(ct.Enemy, ct.Position, ct.Health):cached()
    local uiElements = {}

    -- Helper to safely extract coordinates
    local function extractCoords(v)
        if not v then return 0, 0, nil end
        local x = v.x or v.X or (typeof(v) == "Vector3" and v.X) or 0
        local y = v.y or v.Y or (typeof(v) == "Vector3" and v.Y) or 0
        local z = v.z or v.Z or (typeof(v) == "Vector3" and v.Z) or nil
        return x, y, z
    end

    -- Helper to identify goal based on closeness to workspace waypoints
    local function getGoalIdentity(goalPos)
        local goals = {}
        pcall(function()
            local activeMap = workspace:FindFirstChild("ActiveMap")
            if activeMap then
                local waypoints = activeMap:FindFirstChild("Waypoints")
                if waypoints then
                    if waypoints:FindFirstChild("Goal") then table.insert(goals, {name = "Goal (Left)", pos = waypoints.Goal.Position}) end
                    if waypoints:FindFirstChild("Goal2") then table.insert(goals, {name = "Goal2 (Middle)", pos = waypoints.Goal2.Position}) end
                    if waypoints:FindFirstChild("Goal3") then table.insert(goals, {name = "Goal3 (Right)", pos = waypoints.Goal3.Position}) end
                end
            end
        end)

        if #goals == 0 then
            return "Goal"
        end

        local closestName = "Goal"
        local minDist = math.huge
        local gVec = Vector3.new(goalPos.X, goalPos.Y, goalPos.Z or 0)
        
        for _, g in ipairs(goals) do
            local gPos = g.pos
            local targetVec = Vector3.new(gPos.X, gPos.Y, gPos.Z or 0)
            local dist = (gVec - targetVec).Magnitude
            if dist < minDist then
                minDist = dist
                closestName = g.name
            end
        end
        return closestName
    end

    -- Return the update function executed every frame/tick
    return function(dt)
        local currentActiveIDs = {}
        local enemyDataList = {}

        for id, _, pos, currentHealth in enemyQuery do
            local config = world:get(id, ct.Config)
            local isFinalBoss = config and config.final_boss or false
            local isMiniBoss = config and config.mini_boss or false

            -- Filter check if bossesOnly toggle is active
            if bossesOnly and not isFinalBoss and not isMiniBoss then
                continue
            end

            currentActiveIDs[id] = true

            local maxHealth = config and config.health or 100
            local enemyName = config and (config.name or config.Name or config.EnemyName) or "Enemy"

            -- Extract Position coordinates
            local pX, pY, pZ = extractCoords(pos)

            -- Extract Current Waypoint coordinates
            local waypoint = world:get(id, ct.Waypoint)
            local wpX, wpY, wpZ = extractCoords(waypoint)

            -- Retrieve path target and find path details
            local pathTarget = world:target(id, ct.FollowsPath)
            local pathTable = pathTarget and world:get(pathTarget, ct.Path) or nil
            local goalX, goalY, goalZ = 0, 0, nil
            local totalPercent = 0
            local segPercent = 0
            local goalName = "Goal"

            if pathTable and #pathTable > 0 then
                local finalNode = pathTable[#pathTable]
                local fPos = finalNode.position or finalNode
                goalX, goalY, goalZ = extractCoords(fPos)
                goalName = getGoalIdentity(Vector3.new(goalX, goalY, goalZ or 0))

                -- Get path index progress data
                local followData = world:get(id, Jecs.pair(ct.FollowsPath, pathTarget))
                local pathIndex = followData and followData.pathIndex or 1

                totalPercent = math.clamp((pathIndex / #pathTable) * 100, 0, 100)

                -- Calculate current segment percentage (Pos -> Waypoint)
                if pathIndex > 0 and pathIndex <= #pathTable then
                    local currWPNode = pathTable[pathIndex]
                    local currWPPos = currWPNode.position or currWPNode
                    local prevWPNode = pathIndex > 1 and pathTable[pathIndex - 1] or currWPNode
                    local prevWPPos = prevWPNode.position or prevWPNode

                    local vCurr = Vector3.new(pX, pY, pZ or 0)
                    local vWP = Vector3.new(extractCoords(currWPPos))
                    local vPrev = Vector3.new(extractCoords(prevWPPos))

                    local totalSegDist = (vWP - vPrev).Magnitude
                    local remDist = (vWP - vCurr).Magnitude

                    if totalSegDist > 0.01 then
                        segPercent = math.clamp((1 - (remDist / totalSegDist)) * 100, 0, 100)
                    else
                        segPercent = 100
                    end
                end
            end

            -- Sorting tiers & indicator styles: 1 = Final Boss, 2 = Mini Boss, 3 = Regular
            local tier = 3
            local typeText = "REGULAR"
            local badgeColor = Color3.fromRGB(50, 50, 50)

            if isFinalBoss then
                tier = 1
                typeText = "FINAL BOSS"
                badgeColor = Color3.fromRGB(160, 35, 35)
            elseif isMiniBoss then
                tier = 2
                typeText = "MINI BOSS"
                badgeColor = Color3.fromRGB(190, 110, 20)
            end

            table.insert(enemyDataList, {
                id = id,
                name = enemyName,
                currentHealth = currentHealth,
                maxHealth = maxHealth,
                pX = pX, pY = pY, pZ = pZ,
                wpX = wpX, wpY = wpY, wpZ = wpZ,
                goalX = goalX, goalY = goalY, goalZ = goalZ,
                goalName = goalName,
                segPercent = segPercent,
                totalPercent = totalPercent,
                tier = tier,
                typeText = typeText,
                badgeColor = badgeColor
            })
        end

        -- Sort: Final Bosses first, then Mini-Bosses, then regular enemies
        table.sort(enemyDataList, function(a, b)
            if a.tier ~= b.tier then return a.tier < b.tier end
            return a.id < b.id
        end)

        -- Render/Update UI items inside the ScrollingFrame
        for index, data in ipairs(enemyDataList) do
            local id = data.id
            local card = uiElements[id]

            if not card then
                card = Instance.new("Frame")
                card.Size = UDim2.new(1, -8, 0, 80)
                card.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
                card.BorderSizePixel = 0

                local cardCorner = Instance.new("UICorner")
                cardCorner.CornerRadius = UDim.new(0, 4)
                cardCorner.Parent = card

                -- Type Badge Label
                local badgeLabel = Instance.new("TextLabel")
                badgeLabel.Name = "BadgeLabel"
                badgeLabel.Size = UDim2.new(0, 80, 0, 18)
                badgeLabel.Position = UDim2.new(0, 6, 0, 6)
                badgeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                badgeLabel.TextSize = 9
                badgeLabel.Font = Enum.Font.GothamBold
                badgeLabel.Parent = card

                local badgeCorner = Instance.new("UICorner")
                badgeCorner.CornerRadius = UDim.new(0, 3)
                badgeCorner.Parent = badgeLabel

                -- Info Text (Name, ID & HP)
                local infoLabel = Instance.new("TextLabel")
                infoLabel.Name = "InfoLabel"
                infoLabel.Size = UDim2.new(1, -95, 0, 18)
                infoLabel.Position = UDim2.new(0, 90, 0, 6)
                infoLabel.BackgroundTransparency = 1
                infoLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
                infoLabel.TextSize = 11
                infoLabel.Font = Enum.Font.Code
                infoLabel.TextXAlignment = Enum.TextXAlignment.Left
                infoLabel.Parent = card

                -- Position Text Line with Segment Progress Percentage
                local posLabel = Instance.new("TextLabel")
                posLabel.Name = "PosLabel"
                posLabel.Size = UDim2.new(1, -12, 0, 18)
                posLabel.Position = UDim2.new(0, 6, 0, 28)
                posLabel.BackgroundTransparency = 1
                posLabel.TextColor3 = Color3.fromRGB(180, 210, 255)
                posLabel.TextSize = 11
                posLabel.Font = Enum.Font.Code
                posLabel.TextXAlignment = Enum.TextXAlignment.Left
                posLabel.Parent = card

                -- Waypoint & Goal Text Line with Total Progress Percentage
                local pathLabel = Instance.new("TextLabel")
                pathLabel.Name = "PathLabel"
                pathLabel.Size = UDim2.new(1, -12, 0, 18)
                pathLabel.Position = UDim2.new(0, 6, 0, 48)
                pathLabel.BackgroundTransparency = 1
                pathLabel.TextColor3 = Color3.fromRGB(170, 255, 170)
                pathLabel.TextSize = 10
                pathLabel.Font = Enum.Font.Code
                pathLabel.TextXAlignment = Enum.TextXAlignment.Left
                pathLabel.Parent = card

                card.Parent = scrollingFrame
                uiElements[id] = card
            end

            card.LayoutOrder = index

            -- Update Badge info
            local badgeLabel = card:FindFirstChild("BadgeLabel")
            if badgeLabel then
                badgeLabel.Text = data.typeText
                badgeLabel.BackgroundColor3 = data.badgeColor
            end

            -- Update Name, ID & HP
            local infoLabel = card:FindFirstChild("InfoLabel")
            if infoLabel then
                infoLabel.Text = string.format("%s [#%d] HP: %d/%d", data.name, id, data.currentHealth, data.maxHealth)
            end

            -- Update Position line with Segment Percentage
            local posLabel = card:FindFirstChild("PosLabel")
            if posLabel then
                local posStr = data.pZ and string.format("(%.1f, %.1f, %.1f)", data.pX, data.pY, data.pZ) or string.format("(%.1f, %.1f)", data.pX, data.pY)
                posLabel.Text = string.format("Pos: %s | Seg: %.1f/100%%", posStr, data.segPercent)
            end

            -- Update Current Waypoint & Goal with Total Progress Percentage
            local pathLabel = card:FindFirstChild("PathLabel")
            if pathLabel then
                local wpStr = data.wpZ and string.format("(%.0f, %.0f, %.0f)", data.wpX, data.wpY, data.wpZ) or string.format("(%.0f, %.0f)", data.wpX, data.wpY)
                local goalStr = data.goalZ and string.format("(%.0f, %.0f, %.0f)", data.goalX, data.goalY, data.goalZ) or string.format("(%.0f, %.0f)", data.goalX, data.goalY)
                pathLabel.Text = string.format("WP: %s -> %s: %s | Total: %.1f/100%%", wpStr, data.goalName, goalStr, data.totalPercent)
            end
        end

        -- Clean up dead/despawned/filtered enemy UI cards
        for id, card in pairs(uiElements) do
            if not currentActiveIDs[id] then
                card:Destroy()
                uiElements[id] = nil
            end
        end
    end
end)
