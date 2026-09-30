if setthreadidentity then
    setthreadidentity(7)
elseif setidentity then
    setidentity(7)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Cursing = require(ReplicatedStorage.Modules.Cursing)
local Inventory = require(ReplicatedStorage.Modules.Inventory)
local CurseStations = require(ReplicatedStorage.Databases.CurseStations)

-- Safe requires for Equipping & Inventory Getters
local Equipping, inventoryGetters
pcall(function() Equipping = require(ReplicatedStorage.Modules.Equipping) end)
pcall(function() inventoryGetters = require(ReplicatedStorage.Modules.Inventory.inventory_getters) end)

--------------------------------------------------------------------------------
-- CURSE GRADIENT & STYLING CONFIGURATION
--------------------------------------------------------------------------------
local CURSE_GRADIENTS = {
    ["BrittleBones"] = {
        color1 = Color3.fromRGB(180, 180, 220),
        color2 = Color3.fromRGB(255, 255, 255)
    },
    ["GrimFortune"] = {
        color1 = Color3.fromRGB(220, 160, 50),
        color2 = Color3.fromRGB(255, 240, 120)
    },
    ["CrimsonHunger"] = {
        color1 = Color3.fromRGB(255, 80, 80),
        color2 = Color3.fromRGB(255, 180, 150)
    },
    ["SoulTether"] = {
        color1 = Color3.fromRGB(150, 255, 240),
        color2 = Color3.fromRGB(100, 255, 220)
    },
    ["CryptBreath"] = {
        color1 = Color3.fromRGB(130, 220, 255),
        color2 = Color3.fromRGB(180, 255, 255)
    },
    ["PlagueBite"] = {
        color1 = Color3.fromRGB(120, 240, 80),
        color2 = Color3.fromRGB(180, 255, 150)
    },
    ["ShadowVeil"] = {
        color1 = Color3.fromRGB(220, 140, 255),
        color2 = Color3.fromRGB(255, 180, 255)
    },
    ["DreadPulse"] = {
        color1 = Color3.fromRGB(255, 120, 255),
        color2 = Color3.fromRGB(255, 150, 220)
    },
    ["Fallen"] = {
        color1 = Color3.fromRGB(130, 160, 255),
        color2 = Color3.fromRGB(200, 230, 255)
    },
    ["HexFlame"] = {
        color1 = Color3.fromRGB(255, 160, 80),
        color2 = Color3.fromRGB(255, 220, 140)
    },
    ["DevilsPact"] = {
        color1 = Color3.fromRGB(255, 255, 120),
        color2 = Color3.fromRGB(255, 230, 80)
    },
    ["Nightmare"] = {
        color1 = Color3.fromRGB(255, 140, 255),
        color2 = Color3.fromRGB(220, 120, 255)
    }
}

local TweenService = game:GetService("TweenService")

local function addAnimatedGradient(label, color1, color2, speed)
    speed = speed or 1.6
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, color1),
        ColorSequenceKeypoint.new(1, color2)
    }
    gradient.Rotation = 0
    gradient.Offset = Vector2.new(-1, 0)
    gradient.Transparency = NumberSequence.new(0)
    gradient.Parent = label
    
    -- Animate with TweenService
    local tweenInfo = TweenInfo.new(
        speed,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out,
        -1,  -- Repeat count (-1 = infinite)
        true -- Reverse
    )
    local tween = TweenService:Create(gradient, tweenInfo, {Offset = Vector2.new(1, 0)})
    tween:Play()
    
    return gradient, tween
end

local function addGradientToLabel(label, color1, color2, animate, noStroke)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, color1),
        ColorSequenceKeypoint.new(1, color2)
    }
    gradient.Rotation = 0
    if animate then
        gradient.Offset = Vector2.new(-1, 0)
    end
    gradient.Transparency = NumberSequence.new(0)
    gradient.Parent = label
    
    if not noStroke then
        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        stroke.Color = Color3.fromRGB(0, 0, 0)
        stroke.LineJoinMode = Enum.LineJoinMode.Round
        stroke.Thickness = 2
        stroke.Transparency = 0
        stroke.Parent = label
    end
    
    -- Add animation if requested (left to right movement with TweenService)
    if animate then
        local tweenInfo = TweenInfo.new(
            1.6,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.Out,
            -1,  -- Repeat count (-1 = infinite)
            true -- Reverse
        )
        local tween = TweenService:Create(gradient, tweenInfo, {Offset = Vector2.new(1, 0)})
        tween:Play()
    end
    
    return gradient
end

local function addGradientToText(label, color1, color2, animate)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, color1),
        ColorSequenceKeypoint.new(1, color2)
    }
    gradient.Rotation = 0
    if animate then
        gradient.Offset = Vector2.new(-1, 0)
    end
    gradient.Transparency = NumberSequence.new(0)
    gradient.Parent = label
    
    -- Add animation if requested (left to right movement with TweenService)
    if animate then
        local tweenInfo = TweenInfo.new(
            1.6,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.Out,
            -1,  -- Repeat count (-1 = infinite)
            true -- Reverse
        )
        local tween = TweenService:Create(gradient, tweenInfo, {Offset = Vector2.new(1, 0)})
        tween:Play()
    end
    
    return gradient
end

local function getCurseGradient(curseName)
    return CURSE_GRADIENTS[curseName] or {
        color1 = Color3.fromRGB(100, 100, 150),
        color2 = Color3.fromRGB(200, 200, 255)
    }
end

--------------------------------------------------------------------------------
-- CONFIGURATION & DEFAULTS
--------------------------------------------------------------------------------
local STATION_ID = next(CurseStations)

local curseList = {
    "BrittleBones", "GrimFortune", "CrimsonHunger", "SoulTether",
    "CryptBreath", "PlagueBite", "ShadowVeil", "DreadPulse",
    "Fallen", "HexFlame", "DevilsPact", "Nightmare"
}

local selectedCurses = {
    ["Nightmare"] = true
}

--------------------------------------------------------------------------------
-- SAFE PLAYERGUI PARENTING
--------------------------------------------------------------------------------
local localPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
local playerGui = localPlayer:WaitForChild("PlayerGui")

if playerGui:FindFirstChild("CurseAutoRollGUI") then
    playerGui.CurseAutoRollGUI:Destroy()
end

--------------------------------------------------------------------------------
-- TOWER NAME RESOLVER (FILTERS GENERIC 'TOWER' & RESOLVES SPECIFIC UNIT NAMES)
--------------------------------------------------------------------------------
local function getTowerName(slotTowerId)
    local strId = tostring(slotTowerId)
    local realName = nil
    local baseTowerId = nil

    -- Ignore non-specific generic strings
    local function isValidName(str)
        if type(str) ~= "string" or str == "" then return false end
        local lower = str:lower()
        if lower == "tower" or lower == "item" or lower == "unit" or lower == "token" or lower == strId:lower() then
            return false
        end
        return true
    end

    -- 1. Fetch inventory item data using fullinv getter
    if inventoryGetters and inventoryGetters.getInventory then
        local success, invData = pcall(function()
            return inventoryGetters.getInventory(localPlayer)
        end)

        if success and type(invData) == "table" then
            local itemEntry = invData[strId]
            if not itemEntry then
                for _, category in pairs(invData) do
                    if type(category) == "table" and category[strId] then
                        itemEntry = category[strId]
                        break
                    end
                end
            end

            if type(itemEntry) == "table" then
                -- Inspect keys for explicit unit identifiers or names
                local candidateKeys = {
                    "towerId", "unitId", "towerName", "unitName", "displayName", "DisplayName", 
                    "name", "Name", "tower", "unit", "id", "itemId", "type"
                }

                for _, key in ipairs(candidateKeys) do
                    local val = itemEntry[key]
                    if type(val) == "string" and isValidName(val) then
                        realName = val
                        baseTowerId = val
                        break
                    elseif type(val) == "number" or (type(val) == "string" and not isValidName(val)) then
                        if type(val) == "string" and val ~= "tower" then
                            baseTowerId = val
                        end
                    end
                end

                -- Check nested data/config tables
                if not realName then
                    for _, subTableKey in ipairs({"data", "config", "info", "stats"}) do
                        local sub = itemEntry[subTableKey]
                        if type(sub) == "table" then
                            for _, key in ipairs(candidateKeys) do
                                local val = sub[key]
                                if type(val) == "string" and isValidName(val) then
                                    realName = val
                                    baseTowerId = val
                                    break
                                end
                            end
                        end
                        if realName then break end
                    end
                end
            end
        end
    end

    -- 2. Search Database Modules in ReplicatedStorage for real display names
    local searchIds = { baseTowerId, strId }
    local searchFolders = {
        ReplicatedStorage:FindFirstChild("Databases"),
        ReplicatedStorage:FindFirstChild("Database"),
        ReplicatedStorage:FindFirstChild("Modules")
    }

    for _, folder in ipairs(searchFolders) do
        if folder then
            for _, dbChild in ipairs(folder:GetChildren()) do
                if dbChild:IsA("ModuleScript") then
                    local success, dbTable = pcall(require, dbChild)
                    if success and type(dbTable) == "table" then
                        for _, searchId in ipairs(searchIds) do
                            if searchId then
                                local info = dbTable[searchId] or dbTable[tostring(searchId)]
                                if type(info) == "table" then
                                    local n = info.name or info.Name or info.displayName or info.DisplayName or info.title or info.Title
                                    if type(n) == "string" and isValidName(n) then
                                        realName = n
                                        break
                                    end
                                elseif type(info) == "string" and isValidName(info) then
                                    realName = info
                                    break
                                end
                            end
                        end
                    end
                end
                if realName and isValidName(realName) then break end
            end
        end
        if realName and isValidName(realName) then break end
    end

    if realName and isValidName(realName) then
        return realName, strId
    else
        return strId, strId
    end
end

--------------------------------------------------------------------------------
-- GUI CREATION (Main Window: 420x420)
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CurseAutoRollGUI"
screenGui.ResetOnSpawn = false

if syn and syn.protect_gui then
    syn.protect_gui(screenGui)
elseif protectgui then
    protectgui(screenGui)
end

screenGui.Parent = playerGui

-- MAIN FRAME
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 420, 0, 420)
mainFrame.Position = UDim2.new(0.4, -210, 0.35, -210)
mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(50, 50, 60)
stroke.Thickness = 1.5
stroke.Parent = mainFrame

-- TITLE
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 36)
title.Position = UDim2.new(0, 12, 0, 4)
title.BackgroundTransparency = 1
title.Font = Enum.Font.SourceSansBold
title.Text = "Auto Curse Roller"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = mainFrame

-- EXIT BUTTON
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
closeBtn.Font = Enum.Font.SourceSansBold
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 15
closeBtn.Parent = mainFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn

-- INPUT CONTAINER
local inputContainer = Instance.new("Frame")
inputContainer.Size = UDim2.new(1, -24, 0, 32)
inputContainer.Position = UDim2.new(0, 12, 0, 44)
inputContainer.BackgroundTransparency = 1
inputContainer.Parent = mainFrame

local itemIdLabel = Instance.new("TextLabel")
itemIdLabel.Size = UDim2.new(0, 60, 1, 0)
itemIdLabel.BackgroundTransparency = 1
itemIdLabel.Font = Enum.Font.SourceSansSemibold
itemIdLabel.Text = "Item ID:"
itemIdLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
itemIdLabel.TextSize = 14
itemIdLabel.Parent = inputContainer

local itemIdBox = Instance.new("TextBox")
itemIdBox.Size = UDim2.new(0, 160, 1, 0)
itemIdBox.Position = UDim2.new(0, 60, 0, 0)
itemIdBox.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
itemIdBox.Font = Enum.Font.SourceSans
itemIdBox.Text = "tower194"
itemIdBox.TextColor3 = Color3.fromRGB(255, 255, 255)
itemIdBox.TextSize = 14
itemIdBox.Parent = inputContainer

local itemBoxCorner = Instance.new("UICorner")
itemBoxCorner.CornerRadius = UDim.new(0, 6)
itemBoxCorner.Parent = itemIdBox

local tierLabel = Instance.new("TextLabel")
tierLabel.Size = UDim2.new(0, 75, 1, 0)
tierLabel.Position = UDim2.new(0, 235, 0, 0)
tierLabel.BackgroundTransparency = 1
tierLabel.Font = Enum.Font.SourceSansSemibold
tierLabel.Text = "Target Tier:"
tierLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
tierLabel.TextSize = 14
tierLabel.Parent = inputContainer

local tierBox = Instance.new("TextBox")
tierBox.Size = UDim2.new(0, 55, 1, 0)
tierBox.Position = UDim2.new(0, 310, 0, 0)
tierBox.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
tierBox.Font = Enum.Font.SourceSansBold
tierBox.Text = "3"
tierBox.TextColor3 = Color3.fromRGB(255, 255, 255)
tierBox.TextSize = 15
tierBox.Parent = inputContainer

local tierBoxCorner = Instance.new("UICorner")
tierBoxCorner.CornerRadius = UDim.new(0, 6)
tierBoxCorner.Parent = tierBox

-- LIVE CURSE DISPLAY WITH GRADIENT
local curseDisplayContainer = Instance.new("Frame")
curseDisplayContainer.Name = "CurseDisplayContainer"
curseDisplayContainer.Size = UDim2.new(1, -24, 0, 34)
curseDisplayContainer.Position = UDim2.new(0, 12, 0, 84)
curseDisplayContainer.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
curseDisplayContainer.BorderSizePixel = 0
curseDisplayContainer.Parent = mainFrame

local displayCorner = Instance.new("UICorner")
displayCorner.CornerRadius = UDim.new(0, 6)
displayCorner.Parent = curseDisplayContainer

addGradientToLabel(curseDisplayContainer, Color3.fromRGB(150, 150, 170), Color3.fromRGB(200, 200, 220), false, true)

local curseDisplayLabel = Instance.new("TextLabel")
curseDisplayLabel.Name = "CurseDisplayLabel"
curseDisplayLabel.Size = UDim2.new(1, -20, 1, 0)
curseDisplayLabel.Position = UDim2.new(0, 10, 0, 0)
curseDisplayLabel.BackgroundTransparency = 1
curseDisplayLabel.Font = Enum.Font.SourceSansSemibold
curseDisplayLabel.Text = "Current Curse:"
curseDisplayLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
curseDisplayLabel.TextSize = 14
curseDisplayLabel.TextXAlignment = Enum.TextXAlignment.Left
curseDisplayLabel.Parent = curseDisplayContainer

local curseDisplay = Instance.new("TextLabel")
curseDisplay.Name = "CurseDisplay"
curseDisplay.Size = UDim2.new(1, -130, 1, 0)
curseDisplay.Position = UDim2.new(0, 100, 0, 0)
curseDisplay.BackgroundTransparency = 1
curseDisplay.Font = Enum.Font.SourceSansSemibold
curseDisplay.Text = "Fetching..."
curseDisplay.TextColor3 = Color3.fromRGB(255, 255, 255)
curseDisplay.TextSize = 15
curseDisplay.TextXAlignment = Enum.TextXAlignment.Center
curseDisplay.TextYAlignment = Enum.TextYAlignment.Center
curseDisplay.Parent = curseDisplayContainer

local lockEmoji = Instance.new("TextLabel")
lockEmoji.Name = "LockEmoji"
lockEmoji.Size = UDim2.new(0, 30, 1, 0)
lockEmoji.Position = UDim2.new(1, -30, 0, 0)
lockEmoji.BackgroundTransparency = 1
lockEmoji.Font = Enum.Font.SourceSansSemibold
lockEmoji.Text = ""
lockEmoji.TextColor3 = Color3.fromRGB(255, 215, 100)
lockEmoji.TextSize = 16
lockEmoji.Parent = curseDisplayContainer

-- CURSE SELECTION SECTION
local sectionLabel = Instance.new("TextLabel")
sectionLabel.Size = UDim2.new(1, -24, 0, 20)
sectionLabel.Position = UDim2.new(0, 12, 0, 124)
sectionLabel.BackgroundTransparency = 1
sectionLabel.Font = Enum.Font.SourceSansSemibold
sectionLabel.Text = "Select Target Curses:"
sectionLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
sectionLabel.TextSize = 14
sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
sectionLabel.Parent = mainFrame

-- CURSE LISTBOX
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -24, 0, 180)
scrollFrame.Position = UDim2.new(0, 12, 0, 146)
scrollFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 5
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 220)
scrollFrame.Parent = mainFrame

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = scrollFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.48, 0, 0, 32)
gridLayout.CellPadding = UDim2.new(0.03, 0, 0, 5)
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.Parent = scrollFrame

local gridPadding = Instance.new("UIPadding")
gridPadding.PaddingTop = UDim.new(0, 5)
gridPadding.PaddingLeft = UDim.new(0, 5)
gridPadding.PaddingRight = UDim.new(0, 5)
gridPadding.Parent = scrollFrame

local curseButtons = {}
for _, curseName in ipairs(curseList) do
    local btn = Instance.new("TextButton")
    btn.Name = curseName
    btn.Font = Enum.Font.SourceSansSemibold
    btn.Text = curseName
    btn.TextSize = 14
    btn.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
    btn.Parent = scrollFrame

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 5)
    bCorner.Parent = btn

    local function updateVisual()
        if selectedCurses[curseName] then
            local gradient = getCurseGradient(curseName)
            btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            -- Add gradient without stroke with animation
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("UIGradient") or child:IsA("UIStroke") then
                    child:Destroy()
                end
            end
            local btnGradient = Instance.new("UIGradient")
            btnGradient.Color = ColorSequence.new{
                ColorSequenceKeypoint.new(0, gradient.color1),
                ColorSequenceKeypoint.new(1, gradient.color2)
            }
            btnGradient.Rotation = 0
            btnGradient.Offset = Vector2.new(-1, 0)
            btnGradient.Transparency = NumberSequence.new(0)
            btnGradient.Parent = btn
            
            -- Add animation to curse button gradient
            local tweenInfo = TweenInfo.new(
                1.6,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out,
                -1,  -- Repeat count (-1 = infinite)
                true -- Reverse
            )
            local tween = TweenService:Create(btnGradient, tweenInfo, {Offset = Vector2.new(1, 0)})
            tween:Play()
            
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            -- Remove gradient and stroke if exists
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("UIGradient") or child:IsA("UIStroke") then
                    child:Destroy()
                end
            end
            btn.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
            btn.TextColor3 = Color3.fromRGB(150, 150, 160)
        end
    end

    btn.MouseButton1Click:Connect(function()
        selectedCurses[curseName] = not selectedCurses[curseName]
        updateVisual()
    end)

    updateVisual()
    curseButtons[curseName] = btn
end

-- STATUS LABEL WITH GRADIENT
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -24, 0, 22)
statusLabel.Position = UDim2.new(0, 12, 0, 332)
statusLabel.BackgroundTransparency = 0
statusLabel.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
statusLabel.Font = Enum.Font.SourceSansItalic
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextSize = 14
statusLabel.Parent = mainFrame

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 6)
statusCorner.Parent = statusLabel

addGradientToLabel(statusLabel, Color3.fromRGB(120, 120, 150), Color3.fromRGB(170, 170, 200), false, true)

-- TOGGLE AUTO ROLL BUTTON
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -24, 0, 48)
toggleBtn.Position = UDim2.new(0, 12, 0, 358)
toggleBtn.BackgroundColor3 = Color3.fromRGB(70, 140, 95)
toggleBtn.Font = Enum.Font.SourceSansBold
toggleBtn.Text = "START AUTO ROLL"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 18
toggleBtn.Parent = mainFrame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = toggleBtn

--------------------------------------------------------------------------------
-- SIDE FRAME: HOTBAR TOWERS LIST (Width: 220px)
--------------------------------------------------------------------------------
local sideFrame = Instance.new("Frame")
sideFrame.Name = "SideFrame"
sideFrame.Size = UDim2.new(0, 220, 1, 0)
sideFrame.Position = UDim2.new(1, 10, 0, 0)
sideFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
sideFrame.BorderSizePixel = 0
sideFrame.Parent = mainFrame

local sideCorner = Instance.new("UICorner")
sideCorner.CornerRadius = UDim.new(0, 10)
sideCorner.Parent = sideFrame

local sideStroke = Instance.new("UIStroke")
sideStroke.Color = Color3.fromRGB(50, 50, 60)
sideStroke.Thickness = 1.5
sideStroke.Parent = sideFrame

local sideTitle = Instance.new("TextLabel")
sideTitle.Size = UDim2.new(1, -40, 0, 36)
sideTitle.Position = UDim2.new(0, 10, 0, 4)
sideTitle.BackgroundTransparency = 1
sideTitle.Font = Enum.Font.SourceSansBold
sideTitle.Text = "Hotbar Slots"
sideTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
sideTitle.TextSize = 18
sideTitle.TextXAlignment = Enum.TextXAlignment.Left
sideTitle.Parent = sideFrame

local refreshBtn = Instance.new("TextButton")
refreshBtn.Name = "RefreshButton"
refreshBtn.Size = UDim2.new(0, 26, 0, 26)
refreshBtn.Position = UDim2.new(1, -32, 0, 8)
refreshBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
refreshBtn.Font = Enum.Font.SourceSansBold
refreshBtn.Text = "🔄"
refreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshBtn.TextSize = 13
refreshBtn.Parent = sideFrame

local refreshCorner = Instance.new("UICorner")
refreshCorner.CornerRadius = UDim.new(0, 6)
refreshCorner.Parent = refreshBtn

local hotbarScroll = Instance.new("ScrollingFrame")
hotbarScroll.Size = UDim2.new(1, -16, 1, -50)
hotbarScroll.Position = UDim2.new(0, 8, 0, 42)
hotbarScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
hotbarScroll.BorderSizePixel = 0
hotbarScroll.ScrollBarThickness = 5
hotbarScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
hotbarScroll.Parent = sideFrame

local hotbarScrollCorner = Instance.new("UICorner")
hotbarScrollCorner.CornerRadius = UDim.new(0, 6)
hotbarScrollCorner.Parent = hotbarScroll

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = hotbarScroll

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.Parent = hotbarScroll

local hotbarSlotDisplays = {}

local function refreshHotbarList()
    for _, child in ipairs(hotbarScroll:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("TextLabel") or child:IsA("Frame") then
            child:Destroy()
        end
    end
    hotbarSlotDisplays = {}

    if not Equipping or not Equipping.getHotbar then
        local errLabel = Instance.new("TextLabel")
        errLabel.Size = UDim2.new(1, 0, 0, 30)
        errLabel.BackgroundTransparency = 1
        errLabel.Font = Enum.Font.SourceSansItalic
        errLabel.Text = "Equipping module missing"
        errLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        errLabel.TextSize = 13
        errLabel.Parent = hotbarScroll
        return
    end

    local hotbar = Equipping.getHotbar()
    local count = 0

    if hotbar then
        for slot, towerId in pairs(hotbar) do
            if towerId then
                count = count + 1
                local stringTowerId = tostring(towerId)
                local towerName, resolvedTowerId = getTowerName(stringTowerId)

                -- Create a container frame for the slot button with border
                local slotContainer = Instance.new("Frame")
                slotContainer.Name = "Slot_Container_" .. tostring(slot)
                slotContainer.Size = UDim2.new(1, 0, 0, 64)
                slotContainer.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
                slotContainer.BorderSizePixel = 0
                slotContainer.LayoutOrder = tonumber(slot) or count
                slotContainer.Parent = hotbarScroll

                -- Add gradient border to container (without black stroke)
                local borderGradient = Instance.new("UIGradient")
                borderGradient.Color = ColorSequence.new{
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 180, 200)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 150, 180))
                }
                borderGradient.Rotation = 0
                borderGradient.Transparency = NumberSequence.new(0)
                borderGradient.Parent = slotContainer

                local slotCorner = Instance.new("UICorner")
                slotCorner.CornerRadius = UDim.new(0, 6)
                slotCorner.Parent = slotContainer

                local towerBtn = Instance.new("TextButton")
                towerBtn.Name = "Slot_" .. tostring(slot)
                towerBtn.Size = UDim2.new(1, -6, 1, -6)
                towerBtn.Position = UDim2.new(0, 3, 0, 3)
                towerBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
                towerBtn.Font = Enum.Font.SourceSansSemibold
                towerBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
                towerBtn.TextSize = 12
                towerBtn.Parent = slotContainer

                if towerName ~= stringTowerId then
                    towerBtn.Text = string.format("Slot %s: %s\n(%s)", tostring(slot), towerName, stringTowerId)
                else
                    towerBtn.Text = string.format("Slot %s: %s", tostring(slot), stringTowerId)
                end

                local tCorner = Instance.new("UICorner")
                tCorner.CornerRadius = UDim.new(0, 5)
                tCorner.Parent = towerBtn

                towerBtn.MouseButton1Click:Connect(function()
                    itemIdBox.Text = stringTowerId
                    statusLabel.Text = "Status: Selected Slot " .. tostring(slot)
                end)

                -- Create curse label with gradient text
                local curseLabel = Instance.new("TextLabel")
                curseLabel.Name = "CurseLabel_" .. tostring(slot)
                curseLabel.Size = UDim2.new(0.9, 0, 0, 20)
                curseLabel.Position = UDim2.new(0.05, 0, 1, -22)
                curseLabel.BackgroundTransparency = 1
                curseLabel.Font = Enum.Font.SourceSansSemibold
                curseLabel.Text = "No Curse"
                curseLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
                curseLabel.TextSize = 13
                curseLabel.TextXAlignment = Enum.TextXAlignment.Center
                curseLabel.Parent = slotContainer

                hotbarSlotDisplays[stringTowerId] = {
                    label = curseLabel,
                    container = slotContainer
                }
            end
        end
    end

    if count == 0 then
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, 0, 0, 30)
        emptyLabel.BackgroundTransparency = 1
        emptyLabel.Font = Enum.Font.SourceSansItalic
        emptyLabel.Text = "No hotbar items found"
        emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
        emptyLabel.TextSize = 13
        emptyLabel.Parent = hotbarScroll
    end

    hotbarScroll.CanvasSize = UDim2.new(0, 0, 0, count * 70 + 12)
end

refreshBtn.MouseButton1Click:Connect(refreshHotbarList)
refreshHotbarList()

--------------------------------------------------------------------------------
-- DRAG SYSTEM
--------------------------------------------------------------------------------
local dragging, dragInput, dragStart, startPos
mainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
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

mainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

--------------------------------------------------------------------------------
-- LIVE CURSE DISPLAY UPDATER (WITH HOTBAR SLOT CURSE DISPLAY)
--------------------------------------------------------------------------------
task.spawn(function()
    while screenGui and screenGui.Parent do
        local activeItemId = itemIdBox.Text
        local itemData = Inventory and Inventory.getItem and Inventory.getItem(activeItemId)
        
        if itemData and itemData.curse then
            local curseType = Cursing.getTypeAndTier(itemData.curse)
            curseDisplay.Text = tostring(itemData.curse)
            lockEmoji.Text = itemData.curseLock and "🔒" or ""
            
            -- Update curse display text gradient
            local gradient = getCurseGradient(curseType or itemData.curse)
            for _, child in ipairs(curseDisplay:GetChildren()) do
                if child:IsA("UIGradient") then
                    child:Destroy()
                end
            end
            addGradientToText(curseDisplay, gradient.color1, gradient.color2, false)
        else
            curseDisplay.Text = "None"
            lockEmoji.Text = ""
            -- Reset to default gradient
            for _, child in ipairs(curseDisplay:GetChildren()) do
                if child:IsA("UIGradient") then
                    child:Destroy()
                end
            end
            addGradientToText(curseDisplay, Color3.fromRGB(150, 150, 170), Color3.fromRGB(200, 200, 220), false)
        end

        -- Update hotbar slot curse displays
        for towerId, slotData in pairs(hotbarSlotDisplays) do
            local slotItemData = Inventory and Inventory.getItem and Inventory.getItem(towerId)
            local curseLabel = slotData.label
            local container = slotData.container
            
            if slotItemData and slotItemData.curse then
                local curseType = Cursing.getTypeAndTier(slotItemData.curse)
                curseLabel.Text = tostring(slotItemData.curse)
                
                -- Apply curse gradient to container border
                local gradient = getCurseGradient(curseType or slotItemData.curse)
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("UIGradient") and child.Name ~= "BorderGradient" then
                        child:Destroy()
                    end
                end
                local borderGradient = Instance.new("UIGradient")
                borderGradient.Name = "BorderGradient"
                borderGradient.Color = ColorSequence.new{
                    ColorSequenceKeypoint.new(0, gradient.color1),
                    ColorSequenceKeypoint.new(1, gradient.color2)
                }
                borderGradient.Rotation = 0
                borderGradient.Offset = Vector2.new(-1, 0)
                borderGradient.Transparency = NumberSequence.new(0)
                borderGradient.Parent = container
                
                -- Add animation to border gradient using TweenService
                local tweenInfo = TweenInfo.new(
                    1.6,
                    Enum.EasingStyle.Linear,
                    Enum.EasingDirection.Out,
                    -1,  -- Repeat count (-1 = infinite)
                    true -- Reverse
                )
                local tween = TweenService:Create(borderGradient, tweenInfo, {Offset = Vector2.new(1, 0)})
                tween:Play()
                
                -- Apply curse gradient to curse text
                for _, child in ipairs(curseLabel:GetChildren()) do
                    if child:IsA("UIGradient") then
                        child:Destroy()
                    end
                end
                addGradientToText(curseLabel, gradient.color1, gradient.color2, true)
            else
                curseLabel.Text = "No Curse"
                -- Reset to default gradient
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("UIGradient") and child.Name == "BorderGradient" then
                        child:Destroy()
                    end
                end
                local defaultBorderGradient = Instance.new("UIGradient")
                defaultBorderGradient.Name = "BorderGradient"
                defaultBorderGradient.Color = ColorSequence.new{
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 100, 150)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 255))
                }
                defaultBorderGradient.Rotation = 0
                defaultBorderGradient.Offset = Vector2.new(-1, 0)
                defaultBorderGradient.Transparency = NumberSequence.new(0)
                defaultBorderGradient.Parent = container
                
                -- Add animation to default border gradient using TweenService
                local tweenInfo = TweenInfo.new(
                    1.6,
                    Enum.EasingStyle.Linear,
                    Enum.EasingDirection.Out,
                    -1,  -- Repeat count (-1 = infinite)
                    true -- Reverse
                )
                local tween = TweenService:Create(defaultBorderGradient, tweenInfo, {Offset = Vector2.new(1, 0)})
                tween:Play()
                
                -- Apply curse gradient to curse text
                for _, child in ipairs(curseLabel:GetChildren()) do
                    if child:IsA("UIGradient") then
                        child:Destroy()
                    end
                end
                addGradientToText(curseLabel, Color3.fromRGB(150, 150, 200), Color3.fromRGB(220, 220, 255), true)
            end
        end

        task.wait(0.2)
    end
end)

--------------------------------------------------------------------------------
-- UNLOAD & AUTO ROLL LOGIC
--------------------------------------------------------------------------------
getgenv().AutoRollActive = false

local function stopRoll(message, color)
    getgenv().AutoRollActive = false
    toggleBtn.Text = "START AUTO ROLL"
    toggleBtn.BackgroundColor3 = Color3.fromRGB(70, 140, 95)
    statusLabel.Text = "Status: " .. (message or "Stopped")
    
    -- Update status label gradient based on state (no animation)
    for _, child in ipairs(statusLabel:GetChildren()) do
        if child:IsA("UIGradient") then
            child:Destroy()
        end
    end
    if color == Color3.fromRGB(50, 255, 50) then
        addGradientToLabel(statusLabel, Color3.fromRGB(80, 220, 80), Color3.fromRGB(150, 255, 150), false, true)
    elseif color == Color3.fromRGB(255, 60, 60) then
        addGradientToLabel(statusLabel, Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 150, 150), false, true)
    else
        addGradientToLabel(statusLabel, Color3.fromRGB(100, 100, 150), Color3.fromRGB(200, 200, 255), false, true)
    end
end

local function unloadGUI()
    stopRoll("Unloading GUI...")
    if screenGui then
        screenGui:Destroy()
    end
end

closeBtn.MouseButton1Click:Connect(unloadGUI)

local function startRoll()
    local targetItemId = itemIdBox.Text
    local targetTier = tonumber(tierBox.Text) or 3

    local hasSelection = false
    for _, isSelected in pairs(selectedCurses) do
        if isSelected then
            hasSelection = true
            break
        end
    end

    if not hasSelection then
        stopRoll("Select at least 1 curse!", Color3.fromRGB(255, 60, 60))
        return
    end

    getgenv().AutoRollActive = true
    toggleBtn.Text = "STOP AUTO ROLL"
    toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 70, 70)
    statusLabel.Text = "Status: Rolling..."
    
    -- Update status label gradient for rolling state (no animation)
    for _, child in ipairs(statusLabel:GetChildren()) do
        if child:IsA("UIGradient") then
            child:Destroy()
        end
    end
    addGradientToLabel(statusLabel, Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 200, 80), false, true)

    task.spawn(function()
        while getgenv().AutoRollActive do
            targetItemId = itemIdBox.Text
            targetTier = tonumber(tierBox.Text) or 3

            local itemData = Inventory.getItem(targetItemId)
            
            if not itemData then
                stopRoll(string.format("Item '%s' not found!", targetItemId), Color3.fromRGB(255, 60, 60))
                break
            end

            local currentCurseType, currentTier = Cursing.getTypeAndTier(itemData.curse)

            -- Check hit target curse at or above target tier
            if currentCurseType and selectedCurses[currentCurseType] and currentTier >= targetTier then
                stopRoll(string.format("SUCCESS! Hit %s Tier %d", itemData.curse, currentTier), Color3.fromRGB(50, 255, 50))
                break
            end

            -- Unlock unselected curse
            if currentCurseType and not selectedCurses[currentCurseType] and itemData.curseLock then
                statusLabel.Text = "Status: Unlocking wrong curse..."
                Cursing.toggleLock(targetItemId)
                task.wait(0.4)
                continue
            end

            -- Lock target curse for higher tier
            if currentCurseType and selectedCurses[currentCurseType] and currentTier < targetTier then
                if not itemData.curseLock then
                    statusLabel.Text = string.format("Status: Locking %s for Tier %d...", currentCurseType, currentTier + 1)
                    Cursing.toggleLock(targetItemId)
                    task.wait(0.5)
                    itemData = Inventory.getItem(targetItemId)
                    
                    if not itemData.curseLock then
                        task.wait(0.2)
                        continue
                    end
                end
            end

            -- Roll
            statusLabel.Text = "Status: Rolling curse..."
            local result = Cursing.onRoll(targetItemId, STATION_ID)
            
            if result == false then
                stopRoll("Roll Failed (No Voodoo Tokens)", Color3.fromRGB(255, 60, 60))
                break
            end

            task.wait(0.25)
        end
    end)
end

toggleBtn.MouseButton1Click:Connect(function()
    if getgenv().AutoRollActive then
        stopRoll("Stopped by User")
    else
        startRoll()
    end
end)
