-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- State
local looping = false     -- Candy feed loop
local running = true      -- Master flag for all loops
local connections = {}

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
local function getRoot()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
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

-- Instant teleport, used only for route entrances
local function teleportTo(pos)
    local root = getRoot()
    if root then
        root.CFrame = CFrame.new(pos)
    end
end

-- Equips the scythe by firing the holding-item remote
local function equipScythe()
    local ok, err = pcall(function()
        ReplicatedStorage.Modules.Remotes.RemoteEvent.SetHoldingItem:FireServer("PlayerScythe9")
    end)
    if not ok then
        warn("[Candy Loop] Failed to equip scythe: " .. tostring(err))
    end
end

local LOBBY_PLACE_ID = 131367064230486

local function inLobby()
    return game.PlaceId == LOBBY_PLACE_ID
end

-- Launches the lobby experience (uses the exact call you provided)
local function goToLobby()
    local ok, err = pcall(function()
        game:GetService("ExperienceService"):LaunchExperience({
            placeId = 131367064230486,
        })
    end)
    if not ok then
        warn("[Candy Loop] Failed to teleport to lobby: " .. tostring(err))
    end
    return ok
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

-- =========================
-- Pumpkin auto (route based)
-- =========================
local PUMPKIN_CONFIG = {
    ENABLED = true,
    AUTO_PLANT = true,
    AUTO_CARVE = true,
    AUTO_PICK = true,
    LOOP_INTERVAL = 0.5,
    ROUTE_COOLDOWN = 2,
    STEP_WAIT = 0.25,
    WAIT_TIMEOUT = 10,
    SWIPE_SETTLE = 0.05,
    STALL_WAIT = 30,          -- If a route starts nothing growing, wait before retrying
    MAX_PLOTS = 8,
    TELEPORT_POS = Vector3.new(3506, 272, -456),
    ROUTE = {
        { pos = Vector3.new(3534, 272, -456), slots = {2, 8} },
        { pos = Vector3.new(3554, 272, -455), slots = {3, 9} },
        { pos = Vector3.new(3574, 272, -456), slots = {4, 10} },
        { pos = Vector3.new(3594, 272, -455), slots = {5, 11} },
    },
}

local GROWING_STATE = "Growing"   -- Change if the module uses a different name

local pumpkinState = {
    initialized = false,
    pumpkinGarden = nil,
    pumpkinModule = nil,
    stalledUntil = 0,
}

local PumpkinGarden, ScytheSwipe
local remotesOk = pcall(function()
    local RemoteFunction = require(ReplicatedStorage.Modules.Remotes.RemoteFunction)
    PumpkinGarden = RemoteFunction.new("PumpkinGarden")
    ScytheSwipe = ReplicatedStorage.Modules.Remotes.RemoteEvent.ScytheSwipe
end)

local function invokeGarden(action, slot)
    local ok, success, data = pcall(function()
        return pumpkinState.pumpkinGarden:Invoke(action, slot):await()
    end)
    if ok and success and type(data) == "table" then
        return data
    end
    return { ok = false }
end

local function initPumpkinModule()
    if not remotesOk then return false end

    local ok, pumpkinModule = pcall(function()
        return require(ReplicatedStorage.Modules.PumpkinPatch)
    end)
    if not ok then return false end

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

-- Looks for a finish time in the slot's data. Field names are a guess.
local function getPumpkinReadyAt(gardenState, slot)
    if type(gardenState) ~= "table" then return nil end
    local slotData = gardenState[slot]
    if type(slotData) ~= "table" and type(gardenState.slots) == "table" then
        slotData = gardenState.slots[slot]
    end
    if type(slotData) ~= "table" then return nil end
    for _, key in ipairs({"readyAt", "growReadyAt", "finishAt", "endsAt"}) do
        if type(slotData[key]) == "number" then
            return slotData[key]
        end
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

-- True when no slot on the route is still growing
local function isPumpkinRouteReady()
    for _, stop in ipairs(PUMPKIN_CONFIG.ROUTE) do
        for _, slot in ipairs(stop.slots) do
            local st = getSlotState(slot)
            if st == GROWING_STATE or st == "Unknown" then
                return false
            end
        end
    end
    return true
end

local function anyPumpkinGrowing()
    for _, stop in ipairs(PUMPKIN_CONFIG.ROUTE) do
        for _, slot in ipairs(stop.slots) do
            if getSlotState(slot) == GROWING_STATE then
                return true
            end
        end
    end
    return false
end

-- Sends one swipe, then carves every grown slot in the list
local function carveSlots(slots)
    local targets = {}
    for _, slot in ipairs(slots) do
        local growPoint = getGrowPoint(slot)
        if growPoint then
            table.insert(targets, { slot = slot, pos = growPoint.WorldPosition })
        end
    end

    if #targets == 0 then return end

    ScytheSwipe:FireServer(targets[1].pos)
    task.wait(PUMPKIN_CONFIG.SWIPE_SETTLE)

    for _, t in ipairs(targets) do
        task.spawn(invokeGarden, "carve", t.slot)
    end
end

-- Keeps working the two slots until both are growing (or the timeout hits)
local function tendSlots(slots)
    local deadline = os.clock() + PUMPKIN_CONFIG.WAIT_TIMEOUT

    while PUMPKIN_CONFIG.ENABLED and os.clock() < deadline do
        local allGrowing = true
        local grownSlots = {}

        for _, slot in ipairs(slots) do
            local st = getSlotState(slot)
            if st ~= GROWING_STATE then
                allGrowing = false
            end

            if st == "Carved" and PUMPKIN_CONFIG.AUTO_PICK then
                invokeGarden("pick", slot)
            elseif st == "Empty" and PUMPKIN_CONFIG.AUTO_PLANT then
                invokeGarden("plant", slot)
            elseif st == "Grown" and PUMPKIN_CONFIG.AUTO_CARVE then
                table.insert(grownSlots, slot)
            end
        end

        if #grownSlots > 0 then
            carveSlots(grownSlots)
        end

        if allGrowing then
            return true
        end

        task.wait(PUMPKIN_CONFIG.STEP_WAIT)
    end

    return false
end

-- Teleports once to the patch entrance, equips the scythe, then walks each stop and tends its two plots
local function runPumpkinRoute()
    teleportTo(PUMPKIN_CONFIG.TELEPORT_POS)
    task.wait(0.3)
    equipScythe()

    local function enabled() return PUMPKIN_CONFIG.ENABLED end

    for _, stop in ipairs(PUMPKIN_CONFIG.ROUTE) do
        if not PUMPKIN_CONFIG.ENABLED then return end

        walkTo(stop.pos, 5, enabled)
        tendSlots(stop.slots)
    end

    if not anyPumpkinGrowing() then
        pumpkinState.stalledUntil = os.clock() + PUMPKIN_CONFIG.STALL_WAIT
    end
end

-- =========================
-- Graveyard auto (route based)
-- =========================
local GRAVE_CONFIG = {
    ENABLED = true,
    LOOP_INTERVAL = 0.5,
    ROUTE_COOLDOWN = 2,
    STEP_WAIT = 0.25,
    WAIT_TIMEOUT = 20,        -- Dig time is about 2.6s per grave, so give each stop room
    STALL_WAIT = 30,
    MAX_GRAVES = 8,
    DIG_RANGE = 20,           -- Server allows 22, stay a bit under it
    PER_STOP = 2,             -- Graves handled per waypoint
    TELEPORT_POS = Vector3.new(1786, 271, -2600),
    ROUTE = {
        { pos = Vector3.new(1754, 272, -2600) },
        { pos = Vector3.new(1736, 272, -2600) },
        { pos = Vector3.new(1718, 272, -2600) },
        { pos = Vector3.new(1700, 272, -2600) },
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

-- Gives each waypoint the closest unlocked graves that no earlier waypoint has claimed
local function buildGraveAssignments()
    local taken = {}
    local assignments = {}

    for i, stop in ipairs(GRAVE_CONFIG.ROUTE) do
        local candidates = {}
        for slot = 1, GRAVE_CONFIG.MAX_GRAVES do
            if not taken[slot] and getGraveStatus(slot) ~= "Locked" then
                local dp = getDigPoint(slot)
                if dp then
                    local dx = dp.WorldPosition.X - stop.pos.X
                    local dz = dp.WorldPosition.Z - stop.pos.Z
                    table.insert(candidates, { slot = slot, dist = math.sqrt(dx * dx + dz * dz) })
                end
            end
        end

        table.sort(candidates, function(a, b) return a.dist < b.dist end)

        local slots = {}
        for j = 1, math.min(GRAVE_CONFIG.PER_STOP, #candidates) do
            table.insert(slots, candidates[j].slot)
            taken[candidates[j].slot] = true
        end
        assignments[i] = slots
    end

    return assignments
end

-- True when no unlocked grave is refilling and at least one is ready
local function isGraveRouteReady()
    if not hasShovel() then return false end

    local sawReady = false
    for slot = 1, GRAVE_CONFIG.MAX_GRAVES do
        local st = getGraveStatus(slot)
        if st == "Refilling" or st == "Unknown" then
            return false
        end
        if st == "Ready" then
            sawReady = true
        end
    end
    return sawReady
end

local function anyGraveRefilling()
    for slot = 1, GRAVE_CONFIG.MAX_GRAVES do
        if getGraveStatus(slot) == "Refilling" then
            return true
        end
    end
    return false
end

-- Digs the assigned graves at a stop until none are ready (or the timeout hits)
local function tendGraves(slots)
    local deadline = os.clock() + GRAVE_CONFIG.WAIT_TIMEOUT

    while GRAVE_CONFIG.ENABLED and os.clock() < deadline do
        if not hasShovel() then return false end

        local pending = false
        for _, slot in ipairs(slots) do
            if getGraveStatus(slot) == "Ready" then
                pending = true
                local dp = getDigPoint(slot)
                local root = getRoot()
                if dp and root and (root.Position - dp.WorldPosition).Magnitude <= GRAVE_CONFIG.DIG_RANGE then
                    invokeGrave("dig", slot)
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

-- Teleports once to the graveyard entrance, then walks each stop and digs its graves.
-- Equips the scythe again once every stop is finished.
local function runGraveRoute()
    local assignments = buildGraveAssignments()

    teleportTo(GRAVE_CONFIG.TELEPORT_POS)
    task.wait(0.3)

    local function enabled() return GRAVE_CONFIG.ENABLED end

    for i, stop in ipairs(GRAVE_CONFIG.ROUTE) do
        if not GRAVE_CONFIG.ENABLED then return end

        walkTo(stop.pos, 5, enabled)
        tendGraves(assignments[i])
    end

    equipScythe()

    if not anyGraveRefilling() then
        graveState.stalledUntil = os.clock() + GRAVE_CONFIG.STALL_WAIT
    end
end

-- =========================
-- GUI
-- =========================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CandyFeedGui"
screenGui.ResetOnSpawn = false
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

-- Candy toggle
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.new(1, -20, 0, 36)
toggleButton.Position = UDim2.new(0, 10, 0, 6)
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
pumpkinButton.Position = UDim2.new(0, 10, 0, 50)
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
graveButton.Position = UDim2.new(0, 10, 0, 94)
graveButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
graveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
graveButton.TextSize = 16
graveButton.Font = Enum.Font.GothamBold
graveButton.Text = "Graves: ON"
graveButton.Parent = mainPage

local graveCorner = Instance.new("UICorner")
graveCorner.CornerRadius = UDim.new(0, 8)
graveCorner.Parent = graveButton

local priorityLabel = Instance.new("TextLabel")
priorityLabel.Name = "PriorityNote"
priorityLabel.Size = UDim2.new(1, -20, 0, 36)
priorityLabel.Position = UDim2.new(0, 10, 0.55, 138)
priorityLabel.BackgroundTransparency = 1
priorityLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
priorityLabel.TextSize = 8
priorityLabel.Font = Enum.Font.Gotham
priorityLabel.TextWrapped = true
priorityLabel.Text = "Priority: PumpkinPatch > Graveyard"
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

-- Small unload button in the top-right corner
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

-- Confirmation popup
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
-- Toggle logic
-- =========================
table.insert(connections, toggleButton.MouseButton1Click:Connect(function()
    looping = not looping
    if looping then
        toggleButton.Text = "Feed Loop: ON"
        toggleButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    else
        toggleButton.Text = "Feed Loop: OFF"
        toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    end
end))

table.insert(connections, pumpkinButton.MouseButton1Click:Connect(function()
    PUMPKIN_CONFIG.ENABLED = not PUMPKIN_CONFIG.ENABLED
    if PUMPKIN_CONFIG.ENABLED then
        pumpkinButton.Text = "Pumpkin: ON"
        pumpkinButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    else
        pumpkinButton.Text = "Pumpkin: OFF"
        pumpkinButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    end
end))

table.insert(connections, graveButton.MouseButton1Click:Connect(function()
    GRAVE_CONFIG.ENABLED = not GRAVE_CONFIG.ENABLED
    if GRAVE_CONFIG.ENABLED then
        graveButton.Text = "Graves: ON"
        graveButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    else
        graveButton.Text = "Graves: OFF"
        graveButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    end
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
                label.Text = "Growing: " .. formatLeft(readyAt - now) .. " left"
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
            end
        end
        task.wait(0.1)
    end
end)

-- Route loop with priority: pumpkin patch first, graveyard only when the patch isn't ready
task.spawn(function()
    while running do
        local didRoute = false

        -- 1st priority: pumpkin patch
        if PUMPKIN_CONFIG.ENABLED and os.clock() >= pumpkinState.stalledUntil then
            if not pumpkinState.initialized and not initPumpkinModule() then
                -- module not available yet, fall through to the graveyard
            elseif isPumpkinRouteReady() then
                didRoute = true
                if inLobby() then
                    runPumpkinRoute()
                    task.wait(PUMPKIN_CONFIG.ROUTE_COOLDOWN)
                else
                    goToLobby()
                    task.wait(10)  -- give the teleport time to start before checking again
                end
            end
        end

        -- 2nd priority: graveyard, only when the patch did not run
        if not didRoute and GRAVE_CONFIG.ENABLED and os.clock() >= graveState.stalledUntil then
            if not graveState.initialized and not initGraveModule() then
                -- module not available yet
            elseif isGraveRouteReady() then
                didRoute = true
                if inLobby() then
                    runGraveRoute()
                    task.wait(GRAVE_CONFIG.ROUTE_COOLDOWN)
                else
                    goToLobby()
                    task.wait(10)
                end
            end
        end

        if not didRoute then
            task.wait(0.5)
        end
    end
end)

-- Stats loop: refreshes only while the Stats tab is open
task.spawn(function()
    while running do
        if statsPage.Visible then
            refreshPumpkinStats()
            refreshGraveStats()
        end
        task.wait(1)
    end
end)

-- =========================
-- Unload confirmation
-- =========================
local function unload()
    running = false
    looping = false
    PUMPKIN_CONFIG.ENABLED = false
    GRAVE_CONFIG.ENABLED = false
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    table.clear(connections)
    screenGui:Destroy()
end

table.insert(connections, unloadButton.MouseButton1Click:Connect(function()
    confirmFrame.Visible = true
end))

table.insert(connections, noButton.MouseButton1Click:Connect(function()
    confirmFrame.Visible = false
end))

table.insert(connections, yesButton.MouseButton1Click:Connect(function()
    unload()
end))
