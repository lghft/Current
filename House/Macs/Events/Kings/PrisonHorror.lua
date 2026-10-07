if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(4)
local gameId = game.GameId
repeat task.wait() until gameId == 10463578886 and workspace:WaitForChild("ActiveMap")
Services = setmetatable({}, {
	__index = function(self, name)
		local success, cache = pcall(function()
			return cloneref(game:GetService(name))
		end)
		if success then
			rawset(self, name, cache)
			return cache
		else
			error("Invalid Service: " .. tostring(name))
		end
	end
})

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = Services.Lighting

local Inventory = require(ReplicatedStorage.Modules.Inventory)
local TowerDatabase = require(ReplicatedStorage.Databases.Items.Tower)
local EquippingModule = require(ReplicatedStorage.Modules.Equipping)

getgenv().Ability = false
getgenv().Replay = true
getgenv().Fps = true
getgenv().Debug = false
getgenv().UpgradeMode = "Sequential"-- Priority Sequential
getgenv().Print = false
getgenv().Garden = true
getgenv().GardenWave = 151

local hotbarData = {}
local placedTowersByIndex = {}
local placedTowersUIDByIndex = {}
local soldTowers = {} -- soldTowers[towerIndex] = true. Entries in placedTowersByIndex are NEVER removed, so indices stay stable.
local autoUpgradeQueue = {}
local placedTowerDataByIndex = {} -- placedTowerDataByIndex[towerIndex] = {cframe=CFrame, slot=hotbar slot (placeTower) | uid=tower uid (spawnTempTower)}
local pendingPlacement = nil -- set right before a PlaceTower invoke so the hook knows who placed it
local currentMatchId = 0

local towerModels = {} -- towerModels[towerIndex] = model
local towerModelsById = {} -- towerModelsById[serverId] = model

local antiAfkCon = nil
if getconnections then
    for _, c in getconnections(LocalPlayer.Idled) do
        pcall(function() c:Disable() end) -- supposed to "pause" it
        pcall(function() c:Disconnect() end) -- supposed to disconnect it
    end
end

if antiAfkCon then
    antiAfkCon:Disconnect()
    antiAfkCon = nil
end
antiAfkCon = LocalPlayer.Idled:Connect(function()
    Services.VirtualUser:CaptureController()
    Services.VirtualUser:ClickButton2(Vector2.zero)
end)

local Palette = {
    Background   = Color3.fromRGB(20, 20, 27),
    Panel        = Color3.fromRGB(27, 27, 36),
    PanelAlt     = Color3.fromRGB(32, 32, 42),
    PanelLight   = Color3.fromRGB(58, 58, 76),
    Stroke       = Color3.fromRGB(45, 45, 58),
    Accent       = Color3.fromRGB(124, 108, 255),
    AccentDim    = Color3.fromRGB(90, 79, 191),
    TextPrimary  = Color3.fromRGB(238, 238, 245),
    TextSecond   = Color3.fromRGB(150, 150, 165),
    Success      = Color3.fromRGB(88, 217, 168),
    Warning      = Color3.fromRGB(230, 175, 80),
    Danger       = Color3.fromRGB(200, 50, 50),
    DangerLight  = Color3.fromRGB(250, 70, 70),
    DangerDim    = Color3.fromRGB(200, 80, 80),
}

local LogContainer
local LoggerQueue = { messages = {}, processing = false, maxMessages = 500 }
local stickToBottom = true
local isAutoScrolling = false
local SCROLL_BOTTOM_SLACK = 12

local function isLogScrolledToBottom()
    if not LogContainer then return true end
    local maxY = math.max(0, LogContainer.AbsoluteCanvasSize.Y - LogContainer.AbsoluteWindowSize.Y)
    return LogContainer.CanvasPosition.Y >= (maxY - SCROLL_BOTTOM_SLACK)
end

local function scrollLogToBottom()
    if not LogContainer then return end
    isAutoScrolling = true
    LogContainer.CanvasPosition = Vector2.new(0, math.max(0, LogContainer.AbsoluteCanvasSize.Y))
    isAutoScrolling = false
end

local Logger = {}

function Logger:Log(text, color)
    if not LogContainer then return end
    local wasAtBottom = stickToBottom

    local LogLabel
    local success = pcall(function()
        LogLabel = Instance.new("TextLabel")
        LogLabel.Name = "LogEntry"
        LogLabel.BackgroundTransparency = 1
        LogLabel.Size = UDim2.new(1, 0, 0, 0)
        LogLabel.AutomaticSize = Enum.AutomaticSize.Y
        LogLabel.Font = Enum.Font.Code
        LogLabel.Text = text
        LogLabel.TextColor3 = color or Color3.fromRGB(238, 238, 245)
        LogLabel.TextSize = 12
        LogLabel.TextXAlignment = Enum.TextXAlignment.Left
        LogLabel.TextWrapped = true
        LogLabel.RichText = true
        LogLabel.Parent = LogContainer
    end)
    
    if not success then return end

    local entries = {}
    for _, child in ipairs(LogContainer:GetChildren()) do
        if child:IsA("TextLabel") then
            table.insert(entries, child)
        end
    end
    if #entries > LoggerQueue.maxMessages then
        for i = 1, #entries - LoggerQueue.maxMessages do
            entries[i]:Destroy()
        end
    end

    if wasAtBottom then
        task.defer(scrollLogToBottom)
    end
end

function Logger:Clear()
    if not LogContainer then return end
    for _, item in ipairs(LogContainer:GetChildren()) do
        if item:IsA("TextLabel") then item:Destroy() end
    end
    stickToBottom = true
    isAutoScrolling = true
    LogContainer.CanvasPosition = Vector2.new(0, 0)
    isAutoScrolling = false
end

local function SafeLogUpdate()
    if LoggerQueue.processing or #LoggerQueue.messages == 0 then return end
    LoggerQueue.processing = true
    while #LoggerQueue.messages > 0 do
        local entry = table.remove(LoggerQueue.messages, 1)
        if entry then
            pcall(function() Logger:Log(entry.text, entry.color) end)
        end
    end
    LoggerQueue.processing = false
end

RunService.Heartbeat:Connect(SafeLogUpdate)

local function corner(radius, parent)
    local c
    local success = pcall(function()
        c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius)
        c.Parent = parent
    end)
    return c
end

local function hoverHighlight(button, hoverColor)
    button.BackgroundTransparency = 1
    button.MouseEnter:Connect(function() 
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundTransparency = 0, BackgroundColor3 = hoverColor}):Play() 
    end)
    button.MouseLeave:Connect(function() 
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play() 
    end)
end

local function hoverColorSwap(button, baseColor, hoverColor)
    button.BackgroundColor3 = baseColor
    button.BackgroundTransparency = 0
    button.MouseEnter:Connect(function() 
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundColor3 = hoverColor}):Play() 
    end)
    button.MouseLeave:Connect(function() 
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play() 
    end)
end

local function addClickEffect(button, effectColor)
    effectColor = effectColor or Palette.TextPrimary
    button.ClipsDescendants = true
    local existingCorner = button:FindFirstChildOfClass("UICorner")

    local Flash
    local success = pcall(function()
        Flash = Instance.new("Frame")
        Flash.Name = "ClickFlash"
        Flash.Size = UDim2.new(1, 0, 1, 0)
        Flash.BackgroundColor3 = effectColor
        Flash.BackgroundTransparency = 1
        Flash.BorderSizePixel = 0
        Flash.ZIndex = button.ZIndex + 1
        Flash.Parent = button
        if existingCorner then existingCorner:Clone().Parent = Flash end
    end)
    
    if not success or not Flash then return end

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Flash.BackgroundTransparency = 0.7
            TweenService:Create(Flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
            
            -- Create ripple ring effect
            local absPos = button.AbsolutePosition
            local relX, relY = input.Position.X - absPos.X, input.Position.Y - absPos.Y

            local Ring
            pcall(function()
                Ring = Instance.new("Frame")
                Ring.Name = "ClickRing"
                Ring.AnchorPoint = Vector2.new(0.5, 0.5)
                Ring.Position = UDim2.new(0, relX, 0, relY)
                Ring.Size = UDim2.new(0, 10, 0, 10)
                Ring.BackgroundTransparency = 1
                Ring.BorderSizePixel = 0
                Ring.ZIndex = button.ZIndex + 2
                Ring.Parent = button
                corner(9999, Ring)

                local RingStroke = Instance.new("UIStroke")
                RingStroke.Color = effectColor
                RingStroke.Transparency = 0.3
                RingStroke.Thickness = 2
                RingStroke.Parent = Ring

                local ringTween = TweenService:Create(Ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 60, 0, 60) })
                local strokeTween = TweenService:Create(RingStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
                ringTween:Play()
                strokeTween:Play()
                ringTween.Completed:Connect(function() Ring:Destroy() end)
            end)
        end
    end)
end

if CoreGui:FindFirstChild("MacroDebugGui") then 
    CoreGui:FindFirstChild("MacroDebugGui"):Destroy() 
end

local ScreenGui
local success = pcall(function()
    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "MacroDebugGui"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = 2000
    ScreenGui.Parent = CoreGui
    ScreenGui.Enabled = getgenv().Debug
end)

if not success or not ScreenGui then
    warn("Failed to create ScreenGui - Instance.new restricted by executor")
end

local RestoreBtn
pcall(function()
    RestoreBtn = Instance.new("TextButton")
    RestoreBtn.Name = "RestoreButton"
    RestoreBtn.Size = UDim2.new(0, 46, 0, 46)
    RestoreBtn.Position = UDim2.new(1, -66, 0.5, -23)
    RestoreBtn.BackgroundColor3 = Palette.Panel
    RestoreBtn.AutoButtonColor = false
    RestoreBtn.Text = "DBG"
    RestoreBtn.TextSize = 20
    RestoreBtn.Font = Enum.Font.GothamMedium
    RestoreBtn.Visible = false
    RestoreBtn.Parent = ScreenGui
    corner(23, RestoreBtn)
    local RestoreStroke = Instance.new("UIStroke")
    RestoreStroke.Color = Palette.Accent
    RestoreStroke.Thickness = 1.5
    RestoreStroke.Transparency = 0.4
    RestoreStroke.Parent = RestoreBtn
    addClickEffect(RestoreBtn, Palette.Accent)
end)

local FULL_SIZE = UDim2.new(0, 400, 0, 510)
local COLLAPSED_SIZE = UDim2.new(0, 400, 0, 40)

local MainFrame
local StepLabel -- forward declared so UpdateMacroStep can reach it
pcall(function()
    MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainWindow"
    MainFrame.Size = FULL_SIZE
    MainFrame.Position = UDim2.new(1, -420, 0.5, -250)
    MainFrame.BackgroundColor3 = Palette.Background
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui
    corner(10, MainFrame)
    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = Palette.Stroke
    MainStroke.Thickness = 1
    MainStroke.Parent = MainFrame
end)

local TitleBar
pcall(function()
    TitleBar = Instance.new("Frame")
    TitleBar.Name = "TitleBar"
    TitleBar.Size = UDim2.new(1, 0, 0, 40)
    TitleBar.BackgroundColor3 = Palette.Panel
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MainFrame
    corner(10, TitleBar)

    local TitleBarMask = Instance.new("Frame")
    TitleBarMask.BackgroundColor3 = Palette.Panel
    TitleBarMask.BorderSizePixel = 0
    TitleBarMask.Size = UDim2.new(1, 0, 0, 10)
    TitleBarMask.Position = UDim2.new(0, 0, 1, -10)
    TitleBarMask.Parent = TitleBar

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -140, 1, 0)
    Title.Position = UDim2.new(0, 15, 0, 0)
    Title.Text = "Macro Debug & Tracer"
    Title.TextColor3 = Palette.TextPrimary
    Title.BackgroundTransparency = 1
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 14
    Title.Parent = TitleBar

    local ControlsFrame = Instance.new("Frame")
    ControlsFrame.Name = "Controls"
    ControlsFrame.Size = UDim2.new(0, 114, 0, 32)
    ControlsFrame.AnchorPoint = Vector2.new(1, 0.5)
    ControlsFrame.Position = UDim2.new(1, -8, 0.5, 0)
    ControlsFrame.BackgroundTransparency = 1
    ControlsFrame.Parent = TitleBar
    local ControlsLayout = Instance.new("UIListLayout")
    ControlsLayout.FillDirection = Enum.FillDirection.Horizontal
    ControlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    ControlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    ControlsLayout.Padding = UDim.new(0, 4)
    ControlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ControlsLayout.Parent = ControlsFrame

    local function makeIconButton(iconText, layoutOrder)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 34, 0, 32)
        btn.LayoutOrder = layoutOrder
        btn.Text = iconText
        btn.TextColor3 = Palette.TextSecond
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 22
        btn.AutoButtonColor = false
        btn.Parent = ControlsFrame
        corner(6, btn)
        return btn
    end

    local MinimizeBtn = makeIconButton("—", 1)
    hoverHighlight(MinimizeBtn, Palette.PanelAlt)
    addClickEffect(MinimizeBtn, Palette.TextPrimary)

    local CollapseBtn = makeIconButton("v", 2)
    hoverHighlight(CollapseBtn, Palette.PanelAlt)
    addClickEffect(CollapseBtn, Palette.TextPrimary)

    local CloseBtn = makeIconButton("X", 3)
    CloseBtn.TextColor3 = Palette.Danger
    hoverHighlight(CloseBtn, Color3.fromRGB(60, 32, 32))
    addClickEffect(CloseBtn, Palette.Danger)

    local Body = Instance.new("Frame")
    Body.Name = "Body"
    Body.Size = UDim2.new(1, -24, 1, -60)
    Body.Position = UDim2.new(0, 12, 0, 50)
    Body.BackgroundTransparency = 1
    Body.Parent = MainFrame

    local StatusCard = Instance.new("Frame")
    StatusCard.Size = UDim2.new(1, 0, 0, 42)
    StatusCard.BackgroundColor3 = Palette.Panel
    StatusCard.BorderSizePixel = 0
    StatusCard.Parent = Body
    corner(8, StatusCard)

    StepLabel = Instance.new("TextLabel")
    StepLabel.Size = UDim2.new(1, -20, 1, 0)
    StepLabel.Position = UDim2.new(0, 10, 0, 0)
    StepLabel.Text = "Current Step: Initializing..."
    StepLabel.TextColor3 = Palette.TextPrimary
    StepLabel.BackgroundTransparency = 1
    StepLabel.TextXAlignment = Enum.TextXAlignment.Left
    StepLabel.Font = Enum.Font.Gotham
    StepLabel.TextSize = 12
    StepLabel.Parent = StatusCard

    LogContainer = Instance.new("ScrollingFrame")
    LogContainer.Name = "LogScroll"
    LogContainer.Size = UDim2.new(1, 0, 1, -120)
    LogContainer.Position = UDim2.new(0, 0, 0, 50)
    LogContainer.BackgroundColor3 = Palette.Panel
    LogContainer.BorderSizePixel = 0
    LogContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    LogContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    LogContainer.ScrollingDirection = Enum.ScrollingDirection.Y
    LogContainer.ScrollBarThickness = 6
    LogContainer.ScrollBarImageColor3 = Palette.Accent
    LogContainer.Parent = Body
    corner(8, LogContainer)

    local LogListLayout = Instance.new("UIListLayout")
    LogListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    LogListLayout.Padding = UDim.new(0, 2)
    LogListLayout.Parent = LogContainer

    local LogPadding = Instance.new("UIPadding")
    LogPadding.PaddingLeft = UDim.new(0, 10)
    LogPadding.PaddingRight = UDim.new(0, 15)
    LogPadding.PaddingTop = UDim.new(0, 6)
    LogPadding.Parent = LogContainer

    LogContainer:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if isAutoScrolling then return end
        stickToBottom = isLogScrolledToBottom()
    end)

    local LogActionBar = Instance.new("Frame")
    LogActionBar.Size = UDim2.new(1, 0, 0, 28)
    LogActionBar.Position = UDim2.new(0, 0, 1, -34)
    LogActionBar.BackgroundTransparency = 1
    LogActionBar.Parent = Body

    local function createActionButton(name, text, position, size, color)
        local btn = Instance.new("TextButton")
        btn.Name = name
        btn.Size = size
        btn.Position = position
        btn.BackgroundColor3 = Palette.Panel
        btn.TextColor3 = color or Palette.TextPrimary
        btn.Text = text
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 11
        btn.AutoButtonColor = false
        btn.Parent = LogActionBar
        corner(6, btn)
        hoverColorSwap(btn, Palette.Panel, Palette.PanelLight)
        addClickEffect(btn, color or Palette.Accent)
        return btn
    end

    local ClearLogsBtn = createActionButton("ClearLogsButton", "Clear Logs", UDim2.new(0, 0, 1, -34), UDim2.new(0.5, -4, 0, 34), Palette.DangerLight)
    local ScrollBottomBtn = createActionButton("ScrollBottomButton", "↓ Bottom", UDim2.new(0.5, 4, 1, -34), UDim2.new(0.5, -4, 0, 34), Palette.Accent)

    ClearLogsBtn.MouseButton1Click:Connect(function()
        Logger:Clear()
    end)

    ScrollBottomBtn.MouseButton1Click:Connect(function()
        stickToBottom = true
        scrollLogToBottom()
    end)

    local dragging = false
    local dragStartInput, dragStartPos

    TitleBar.Active = true
    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStartInput = input.Position
            dragStartPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStartInput
            MainFrame.Position = UDim2.new(dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X, dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y)
        end
    end)

    local MinimizeTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    local RestoreTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local savedPosition = MainFrame.Position
    local savedSize = MainFrame.Size
    local minimizeAnimating = false

    MinimizeBtn.MouseButton1Click:Connect(function()
        if minimizeAnimating then return end
        minimizeAnimating = true
        savedPosition = MainFrame.Position
        savedSize = MainFrame.Size
        local targetPos = UDim2.new(RestoreBtn.Position.X.Scale, RestoreBtn.Position.X.Offset + RestoreBtn.Size.X.Offset / 2, RestoreBtn.Position.Y.Scale, RestoreBtn.Position.Y.Offset + RestoreBtn.Size.Y.Offset / 2)
        local minimizeTween = TweenService:Create(MainFrame, MinimizeTweenInfo, {Size = UDim2.new(0, 0, 0, 0), Position = targetPos, BackgroundTransparency = 1})
        TweenService:Create(MainStroke, MinimizeTweenInfo, {Transparency = 1}):Play()
        minimizeTween:Play()
        minimizeTween.Completed:Connect(function()
            MainFrame.Visible = false
            MainFrame.Size = savedSize
            MainFrame.Position = savedPosition
            MainFrame.BackgroundTransparency = 0
            MainStroke.Transparency = 0
            RestoreBtn.Visible = true
            RestoreBtn.Size = UDim2.new(0, 0, 0, 0)
            TweenService:Create(RestoreBtn, RestoreTweenInfo, {Size = UDim2.new(0, 46, 0, 46)}):Play()
            minimizeAnimating = false
        end)
    end)

    RestoreBtn.MouseButton1Click:Connect(function()
        if minimizeAnimating then return end
        minimizeAnimating = true
        local shrinkTween = TweenService:Create(RestoreBtn, MinimizeTweenInfo, {Size = UDim2.new(0, 0, 0, 0)})
        shrinkTween:Play()
        local startPos = UDim2.new(RestoreBtn.Position.X.Scale, RestoreBtn.Position.X.Offset + (RestoreBtn.Size.X.Offset / 2), RestoreBtn.Position.Y.Scale, RestoreBtn.Position.Y.Offset + (RestoreBtn.Size.Y.Offset / 2))
        MainFrame.Visible = true
        MainFrame.Size = UDim2.new(0, 0, 0, 0)
        MainFrame.Position = startPos
        MainFrame.BackgroundTransparency = 1
        MainStroke.Transparency = 1
        TweenService:Create(MainFrame, RestoreTweenInfo, {Size = savedSize, Position = savedPosition, BackgroundTransparency = 0}):Play()
        TweenService:Create(MainStroke, RestoreTweenInfo, {Transparency = 0}):Play()
        shrinkTween.Completed:Connect(function()
            RestoreBtn.Visible = false
            RestoreBtn.Size = UDim2.new(0, 46, 0, 46)
            minimizeAnimating = false
        end)
    end)

    local isCollapsed = false
    local bodyElements = {Body}
    local TweenInf = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    CollapseBtn.MouseButton1Click:Connect(function()
        isCollapsed = not isCollapsed
        if isCollapsed then
            CollapseBtn.Text = ">"
            for _, element in ipairs(bodyElements) do element.Visible = false end
            TitleBarMask.Visible = false
            TweenService:Create(MainFrame, TweenInf, {Size = COLLAPSED_SIZE}):Play()
        else
            CollapseBtn.Text = "v"
            local expandTween = TweenService:Create(MainFrame, TweenInf, {Size = FULL_SIZE})
            expandTween:Play()
            expandTween.Completed:Connect(function()
                if not isCollapsed then
                    for _, element in ipairs(bodyElements) do element.Visible = true end
                    TitleBarMask.Visible = true
                end
            end)
        end
    end)

    local Overlay = Instance.new("Frame")
    Overlay.Name = "Overlay"
    Overlay.Size = UDim2.new(1, 0, 1, 0)
    Overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Overlay.BackgroundTransparency = 1
    Overlay.Visible = false
    Overlay.ZIndex = 5
    Overlay.Parent = MainFrame

    local UnloadMenu = Instance.new("Frame")
    UnloadMenu.Name = "UnloadMenu"
    UnloadMenu.Size = UDim2.new(0, 0, 0, 0)
    UnloadMenu.Position = UDim2.new(0.5, 0, 0.5, 0)
    UnloadMenu.AnchorPoint = Vector2.new(0.5, 0.5)
    UnloadMenu.BackgroundColor3 = Palette.Panel
    UnloadMenu.ClipsDescendants = true
    UnloadMenu.Visible = false
    UnloadMenu.ZIndex = 6
    UnloadMenu.Parent = MainFrame
    corner(10, UnloadMenu)

    local UnloadTitle = Instance.new("TextLabel")
    UnloadTitle.Size = UDim2.new(1, -30, 0, 22)
    UnloadTitle.Position = UDim2.new(0, 15, 0, 14)
    UnloadTitle.Text = "Unload Debug GUI?"
    UnloadTitle.TextColor3 = Palette.TextPrimary
    UnloadTitle.BackgroundTransparency = 1
    UnloadTitle.TextXAlignment = Enum.TextXAlignment.Left
    UnloadTitle.Font = Enum.Font.GothamBold
    UnloadTitle.TextSize = 14
    UnloadTitle.ZIndex = 6
    UnloadTitle.Parent = UnloadMenu

    local UnloadText = Instance.new("TextLabel")
    UnloadText.Size = UDim2.new(1, -30, 0, 18)
    UnloadText.Position = UDim2.new(0, 15, 0, 38)
    UnloadText.Text = "This action cannot be undone."
    UnloadText.TextColor3 = Palette.TextSecond
    UnloadText.BackgroundTransparency = 1
    UnloadText.TextXAlignment = Enum.TextXAlignment.Left
    UnloadText.Font = Enum.Font.Gotham
    UnloadText.TextSize = 12
    UnloadText.ZIndex = 6
    UnloadText.Parent = UnloadMenu

    local CancelBtn = Instance.new("TextButton")
    CancelBtn.Size = UDim2.new(0, 108, 0, 32)
    CancelBtn.Position = UDim2.new(1, -123, 1, -46)
    CancelBtn.BackgroundColor3 = Palette.PanelAlt
    CancelBtn.TextColor3 = Palette.TextPrimary
    CancelBtn.Text = "Cancel"
    CancelBtn.Font = Enum.Font.GothamMedium
    CancelBtn.TextSize = 13
    CancelBtn.AutoButtonColor = false
    CancelBtn.ZIndex = 6
    CancelBtn.Parent = UnloadMenu
    corner(6, CancelBtn)
    hoverColorSwap(CancelBtn, Palette.PanelAlt, Palette.PanelLight)
    addClickEffect(CancelBtn, Palette.TextPrimary)

    local ConfirmBtn = Instance.new("TextButton")
    ConfirmBtn.Size = UDim2.new(0, 108, 0, 32)
    ConfirmBtn.Position = UDim2.new(0, 15, 1, -46)
    ConfirmBtn.BackgroundColor3 = Palette.Danger
    ConfirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    ConfirmBtn.Text = "Unload"
    ConfirmBtn.Font = Enum.Font.GothamBold
    ConfirmBtn.TextSize = 13
    ConfirmBtn.AutoButtonColor = false
    ConfirmBtn.ZIndex = 6
    ConfirmBtn.Parent = UnloadMenu
    corner(6, ConfirmBtn)
    hoverColorSwap(ConfirmBtn, Palette.Danger, Color3.fromRGB(150, 40, 40))
    addClickEffect(ConfirmBtn, Color3.fromRGB(255, 255, 255))

    CloseBtn.MouseButton1Click:Connect(function()
        Overlay.Visible = true
        UnloadMenu.Visible = true
        TweenService:Create(Overlay, TweenInf, {BackgroundTransparency = 0.4}):Play()
        TweenService:Create(UnloadMenu, TweenInf, {Size = UDim2.new(0, 246, 0, 118)}):Play()
    end)

    CancelBtn.MouseButton1Click:Connect(function()
        TweenService:Create(Overlay, TweenInf, {BackgroundTransparency = 1}):Play()
        local tween = TweenService:Create(UnloadMenu, TweenInf, {Size = UDim2.new(0, 0, 0, 0)})
        tween:Play()
        tween.Completed:Wait()
        UnloadMenu.Visible = false
        Overlay.Visible = false
    end)

    ConfirmBtn.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
        getgenv().Debug = false
    end)
end)

local function Notify(logType, message)
    local logType = logType
    local message = message
    if getgenv().Print == true then
        local timeStamp = os.date("[%I:%M:%S %p]")
        local icon = "[INFO]"
        local color = Palette.TextPrimary

        logType = string.lower(tostring(logType))
        if logType == "warn" then icon = "[WARN]"; color = Palette.Warning; warn(message)
        elseif logType == "error" then icon = "[ERROR]"; color = Palette.Danger; warn("[ERROR]: " .. message)
        else print(message) end

        local formattedMessage = string.format("%s %s: %s", timeStamp, icon, tostring(message))
        if #LoggerQueue.messages < LoggerQueue.maxMessages then 
            table.insert(LoggerQueue.messages, {text = formattedMessage, color = color}) 
        end
    end
end

local OverlayLabels = {}
local currentStepText = "Initializing..."
local currentActionText = "Idle"

-- Cached values. MUST be declared before UpdateAction/UpdateMacroStep so they
-- capture these locals (otherwise they write to globals the overlay never reads).
local cachedWaveText = "-/-"
local cachedCash = 0
local cachedActionText = "Idle"
local cachedStepText = "Initializing..."

local function formatNumber(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (formatted:gsub("^,", ""))
end

local function UpdateMacroStep(stepString)
    currentStepText = tostring(stepString)
    cachedStepText = currentStepText
    if StepLabel then
        pcall(function()
            StepLabel.Text = "Current Step: " .. currentStepText
        end)
    end
    if OverlayLabels.Step then
        pcall(function()
            OverlayLabels.Step.Text = "Step: " .. currentStepText
        end)
    end
end

local function UpdateAction(actionString)
    actionString = tostring(actionString)
    if currentActionText == actionString then return end
    currentActionText = actionString
    cachedActionText = actionString
    if OverlayLabels.Action then
        pcall(function()
            OverlayLabels.Action.Text = "Action: " .. actionString
        end)
    end
end

if CoreGui:FindFirstChild("FpsModeOverlay") then CoreGui:FindFirstChild("FpsModeOverlay"):Destroy() end
if CoreGui:FindFirstChild("FpsToggleGui") then CoreGui:FindFirstChild("FpsToggleGui"):Destroy() end

-- ============================================================================
-- Enemy Tracker (shown inside the FPS-mode / "3D Rendering Off" overlay)
-- * The panel is built by buildEnemyTracker() when the overlay is created.
-- * Data collection/updating runs inside the ECS system below (Entities.add_system),
--   completely separate from every Heartbeat loop in this script.
-- * System logic is unchanged from the original EnemyTrackerUI module.
-- ============================================================================
local EnemyTracker = {
    bossesOnly = true,      -- Bosses-only filter (ENABLED BY DEFAULT)
    mainFrame = nil,
    scrollingFrame = nil,
    dragConn = nil,
    panelOpen = false,      -- plain flag so the ECS thread never has to touch an Instance
    goals = {},             -- {name, pos} list refreshed by the render loop (ECS thread can't read workspace)
    snapshot = {},          -- latest enemy data written by the ECS system, drawn by the render loop
    snapshotId = 0,
    watchBoss = true,       -- keep collecting final-boss data even if the panel is closed
    finalBoss = nil,        -- {id, totalPercent, base, goalName} for the final boss (written by the ECS system)
}

local function buildEnemyTracker(parent)
    -- Remove old panel if it already exists (clean re-creation)
    if EnemyTracker.dragConn then EnemyTracker.dragConn:Disconnect() EnemyTracker.dragConn = nil end
    if EnemyTracker.mainFrame then EnemyTracker.mainFrame:Destroy() end

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "EnemyTracker"
    mainFrame.Size = UDim2.new(0, 400, 0, 440)
    mainFrame.AnchorPoint = Vector2.new(1, 0)
    mainFrame.Position = UDim2.new(1, -12, 0, 12)
    mainFrame.BackgroundColor3 = Palette.Panel
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.ZIndex = 2
    mainFrame.Parent = parent
    corner(8, mainFrame)

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Palette.Stroke
    mainStroke.Thickness = 1
    mainStroke.Parent = mainFrame

    -- Header Bar (Draggable, Title, Boss Toggle, & Exit Button)
    local headerFrame = Instance.new("Frame")
    headerFrame.Size = UDim2.new(1, 0, 0, 36)
    headerFrame.BackgroundColor3 = Palette.PanelAlt
    headerFrame.BorderSizePixel = 0
    headerFrame.Parent = mainFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -140, 1, 0)
    titleLabel.Position = UDim2.new(0, 10, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Palette.TextPrimary
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "Active Enemies Tracker"
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = headerFrame

    local filterButton = Instance.new("TextButton")
    filterButton.Size = UDim2.new(0, 95, 0, 24)
    filterButton.Position = UDim2.new(1, -132, 0.5, -12)
    filterButton.BackgroundColor3 = Palette.Danger
    filterButton.AutoButtonColor = false
    filterButton.TextColor3 = Palette.TextPrimary
    filterButton.TextSize = 10
    filterButton.Font = Enum.Font.GothamBold
    filterButton.Text = "Filter: Bosses"
    filterButton.Parent = headerFrame
    corner(4, filterButton)

    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 26, 0, 26)
    closeButton.Position = UDim2.new(1, -32, 0.5, -13)
    closeButton.BackgroundColor3 = Palette.Danger
    closeButton.AutoButtonColor = false
    closeButton.TextColor3 = Palette.TextPrimary
    closeButton.TextSize = 12
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "X"
    closeButton.Parent = headerFrame
    corner(4, closeButton)

    local function applyFilterStyle()
        if EnemyTracker.bossesOnly then
            filterButton.Text = "Filter: Bosses"
            filterButton.BackgroundColor3 = Palette.Danger
        else
            filterButton.Text = "Filter: All"
            filterButton.BackgroundColor3 = Palette.PanelLight
        end
    end
    applyFilterStyle()

    closeButton.MouseButton1Click:Connect(function()
        if EnemyTracker.dragConn then EnemyTracker.dragConn:Disconnect() EnemyTracker.dragConn = nil end
        EnemyTracker.panelOpen = false
        EnemyTracker.scrollingFrame = nil
        EnemyTracker.mainFrame = nil
        mainFrame:Destroy()
    end)

    filterButton.MouseButton1Click:Connect(function()
        EnemyTracker.bossesOnly = not EnemyTracker.bossesOnly
        applyFilterStyle()
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

    EnemyTracker.dragConn = UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Scrolling Frame for the Enemy List
    local scrollingFrame = Instance.new("ScrollingFrame")
    scrollingFrame.Size = UDim2.new(1, -12, 1, -48)
    scrollingFrame.Position = UDim2.new(0, 6, 0, 42)
    scrollingFrame.BackgroundTransparency = 1
    scrollingFrame.BorderSizePixel = 0
    scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollingFrame.ScrollBarThickness = 6
    scrollingFrame.ScrollBarImageColor3 = Palette.PanelLight
    scrollingFrame.Parent = mainFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 6)
    listLayout.Parent = scrollingFrame

    EnemyTracker.mainFrame = mainFrame
    EnemyTracker.scrollingFrame = scrollingFrame
    EnemyTracker.panelOpen = true
end

-- ECS system: DATA ONLY. The game's scheduler runs this in a restricted thread that cannot
-- touch Instances at all, so it only reads ECS data and writes a plain-table snapshot.
pcall(function()
    local Jecs = require(ReplicatedStorage.Packages.Jecs)
    local Entities = require(ReplicatedStorage.Modules.Entities)
    local ct = require(ReplicatedStorage.Modules.Entities.ct)

    Entities.add_system(function(world)
        -- Only run this tracking system on the client side
        if not RunService:IsClient() then
            return function() end
        end

        -- Cache ECS query
        local enemyQuery = world:query(ct.Enemy, ct.Position, ct.Health):cached()

        -- Helper to safely extract coordinates
        local function extractCoords(v)
            if not v then return 0, 0, nil end
            local x = v.x or v.X or (typeof(v) == "Vector3" and v.X) or 0
            local y = v.y or v.Y or (typeof(v) == "Vector3" and v.Y) or 0
            local z = v.z or v.Z or (typeof(v) == "Vector3" and v.Z) or nil
            return x, y, z
        end

        -- Helper to identify goal based on closeness to workspace waypoints
        -- (waypoint list is cached in EnemyTracker.goals by the render thread)
        local function getGoalIdentity(goalPos)
            local goals = EnemyTracker.goals

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

        -- Update function executed every tick by the ECS scheduler
        return function(dt)
            if not (EnemyTracker.panelOpen or EnemyTracker.watchBoss) then
                return
            end
            local bossesOnly = EnemyTracker.bossesOnly

            local enemyDataList = {}
            local finalBossInfo = nil

            for id, _, pos, currentHealth in enemyQuery do
                -- Dead enemies (health reached 0) are dropped from the list
                if type(currentHealth) == "number" and currentHealth <= 0 then
                    continue
                end

                local config = world:get(id, ct.Config)
                local isFinalBoss = config and config.final_boss or false
                local isMiniBoss = config and config.mini_boss or false

                -- Filter check if bossesOnly toggle is active
                if bossesOnly and not isFinalBoss and not isMiniBoss then
                    continue
                end

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

                -- Track the final boss: its total path progress (0-100) and which base it is heading to
                if isFinalBoss and pathTable and #pathTable > 0 then
                    local base = nil
                    if string.find(goalName, "Left", 1, true) then base = "Left"
                    elseif string.find(goalName, "Middle", 1, true) then base = "Middle"
                    elseif string.find(goalName, "Right", 1, true) then base = "Right" end

                    finalBossInfo = {
                        id = id,
                        totalPercent = totalPercent,
                        base = base,
                        goalName = goalName,
                    }
                end

                -- Sorting tiers & indicator styles: 1 = Final Boss, 2 = Mini Boss, 3 = Regular
                local tier = 3
                local typeText = "REGULAR"
                local badgeColor = Palette.PanelLight

                if isFinalBoss then
                    tier = 1
                    typeText = "FINAL BOSS"
                    badgeColor = Palette.Danger
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

            EnemyTracker.finalBoss = finalBossInfo

            -- Hand the data to the render thread
            EnemyTracker.snapshot = enemyDataList
            EnemyTracker.snapshotId = EnemyTracker.snapshotId + 1
        end
    end)
end)

-- Render thread: its own loop (NOT the script's Heartbeat connection). Draws the snapshot
-- produced by the ECS system above; this is the only place the tracker touches Instances.
task.spawn(function()
    local uiElements = {}
    local lastSnapshotId = -1
    local lastFrame = nil

    while true do
        task.wait()

        -- Cache workspace waypoints for the ECS thread
        pcall(function()
            local goals = {}
            local activeMap = workspace:FindFirstChild("ActiveMap")
            if activeMap then
                local waypoints = activeMap:FindFirstChild("Waypoints")
                if waypoints then
                    if waypoints:FindFirstChild("Goal") then table.insert(goals, {name = "Goal (Left)", pos = waypoints.Goal.Position}) end
                    if waypoints:FindFirstChild("Goal2") then table.insert(goals, {name = "Goal2 (Middle)", pos = waypoints.Goal2.Position}) end
                    if waypoints:FindFirstChild("Goal3") then table.insert(goals, {name = "Goal3 (Right)", pos = waypoints.Goal3.Position}) end
                end
            end
            EnemyTracker.goals = goals
        end)

        local scrollingFrame = EnemyTracker.scrollingFrame
        if not (scrollingFrame and scrollingFrame.Parent) then
            continue
        end
        if scrollingFrame ~= lastFrame then
            table.clear(uiElements)
            lastFrame = scrollingFrame
            lastSnapshotId = -1
        end
        if EnemyTracker.snapshotId == lastSnapshotId then
            continue
        end
        lastSnapshotId = EnemyTracker.snapshotId

        local currentActiveIDs = {}
        local enemyDataList = EnemyTracker.snapshot

        -- Render/Update UI items inside the ScrollingFrame
        for index, data in ipairs(enemyDataList) do
            local id = data.id
            currentActiveIDs[id] = true
            local card = uiElements[id]

            if not card then
                card = Instance.new("Frame")
                card.Size = UDim2.new(1, -8, 0, 80)
                card.BackgroundColor3 = Palette.PanelAlt
                card.BorderSizePixel = 0

                local cardCorner = Instance.new("UICorner")
                cardCorner.CornerRadius = UDim.new(0, 4)
                cardCorner.Parent = card

                -- Type Badge Label
                local badgeLabel = Instance.new("TextLabel")
                badgeLabel.Name = "BadgeLabel"
                badgeLabel.Size = UDim2.new(0, 80, 0, 18)
                badgeLabel.Position = UDim2.new(0, 6, 0, 6)
                badgeLabel.TextColor3 = Palette.TextPrimary
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
                infoLabel.TextColor3 = Palette.TextPrimary
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
                posLabel.TextColor3 = Palette.Accent
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
                pathLabel.TextColor3 = Palette.Success
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

local FpsToggleBtn 
local FpsOverlayGui = nil 

local function ensureFpsOverlay()
    if FpsOverlayGui then return end
    
    local success = pcall(function()
        FpsOverlayGui = Instance.new("ScreenGui")
        FpsOverlayGui.Name = "FpsModeOverlay"
        FpsOverlayGui.ResetOnSpawn = false
        FpsOverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        FpsOverlayGui.DisplayOrder = 999 
        FpsOverlayGui.IgnoreGuiInset = true 
        FpsOverlayGui.Parent = CoreGui

        local Cover = Instance.new("Frame")
        Cover.Name = "Cover"
        Cover.Size = UDim2.new(1, 0, 1, 0)
        Cover.BackgroundColor3 = Palette.Background
        Cover.BorderSizePixel = 0
        Cover.ZIndex = 1
        Cover.Parent = FpsOverlayGui

        local CoverLabel = Instance.new("TextLabel")
        CoverLabel.Size = UDim2.new(1, 0, 0, 30)
        CoverLabel.Position = UDim2.new(0, 0, 1, -40)
        CoverLabel.BackgroundTransparency = 1
        CoverLabel.Text = "FPS Mode Enabled - 3D Rendering Off"
        CoverLabel.TextColor3 = Palette.TextSecond
        CoverLabel.Font = Enum.Font.GothamMedium
        CoverLabel.TextSize = 13
        CoverLabel.ZIndex = 1
        CoverLabel.Parent = Cover

        local InfoPanel = Instance.new("Frame")
        InfoPanel.Name = "InfoPanel"
        InfoPanel.Size = UDim2.new(0, 360, 0, 0)
        InfoPanel.AutomaticSize = Enum.AutomaticSize.Y
        InfoPanel.Position = UDim2.new(0, 12, 0, 12)
        InfoPanel.BackgroundColor3 = Palette.Panel
        InfoPanel.BorderSizePixel = 0
        InfoPanel.ZIndex = 2
        InfoPanel.Parent = Cover
        corner(8, InfoPanel)

        local InfoStroke = Instance.new("UIStroke")
        InfoStroke.Color = Palette.Stroke
        InfoStroke.Thickness = 1
        InfoStroke.Parent = InfoPanel

        local InfoPadding = Instance.new("UIPadding")
        InfoPadding.PaddingTop = UDim.new(0, 8)
        InfoPadding.PaddingBottom = UDim.new(0, 8)
        InfoPadding.PaddingLeft = UDim.new(0, 10)
        InfoPadding.PaddingRight = UDim.new(0, 10)
        InfoPadding.Parent = InfoPanel

        local InfoLayout = Instance.new("UIListLayout")
        InfoLayout.SortOrder = Enum.SortOrder.LayoutOrder
        InfoLayout.Padding = UDim.new(0, 4)
        InfoLayout.Parent = InfoPanel

        local function makeInfoLabel(key, order, text, color)
            local lbl = Instance.new("TextLabel")
            lbl.Name = key
            lbl.LayoutOrder = order
            lbl.Size = UDim2.new(1, 0, 0, 16)
            lbl.AutomaticSize = Enum.AutomaticSize.Y
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextYAlignment = Enum.TextYAlignment.Top
            lbl.TextWrapped = true
            lbl.TextColor3 = color
            lbl.Text = text
            lbl.ZIndex = 3
            lbl.Parent = InfoPanel
            OverlayLabels[key] = lbl
            return lbl
        end

        makeInfoLabel("Wave",   1, "Wave: -/-",                     Palette.Accent)
        makeInfoLabel("Cash",   2, "Cash: $0",                      Palette.Success)
        makeInfoLabel("Step",   3, "Step: " .. currentStepText,     Palette.TextPrimary)
        makeInfoLabel("Action", 4, "Action: " .. currentActionText, Palette.Warning)

        buildEnemyTracker(Cover)
    end)
    
    if not success then
        warn("Failed to create FPS overlay - executor may not support Instance.new()")
    end
end

local function fpsBooost()
    local Terrain = workspace:FindFirstChildWhichIsA("Terrain")
	Terrain.WaterWaveSize = 0
	Terrain.WaterWaveSpeed = 0
	Terrain.WaterReflectance = 0
	Terrain.WaterTransparency = 1
	Lighting.GlobalShadows = false
	Lighting.FogEnd = 9e9
	Lighting.FogStart = 9e9
	settings().Rendering.QualityLevel = 1
	for _, v in pairs(game:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CastShadow = false
			v.Material = "Plastic"
			v.Reflectance = 0
			v.BackSurface = "SmoothNoOutlines"
			v.BottomSurface = "SmoothNoOutlines"
			v.FrontSurface = "SmoothNoOutlines"
			v.LeftSurface = "SmoothNoOutlines"
			v.RightSurface = "SmoothNoOutlines"
			v.TopSurface = "SmoothNoOutlines"
		elseif v:IsA("Decal") then
			v.Transparency = 1
			v.Texture = ""
		elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
			--v.Lifetime = NumberRange.new(0)
		end
	end
	for _, v in pairs(Lighting:GetDescendants()) do
		if v:IsA("PostEffect") then
			v.Enabled = false
		end
	end
	workspace.DescendantAdded:Connect(function(child)
		task.spawn(function()
			if child:IsA("ForceField") or child:IsA("Sparkles") or child:IsA("Smoke") or child:IsA("Fire") or child:IsA("Beam") then
				RunService.Heartbeat:Wait()
				child:Destroy()
			elseif child:IsA("BasePart") then
				child.CastShadow = false
			end
		end)
	end)
end

local function setFpsMode(state)
    getgenv().Fps = state
    local ok, err = pcall(function() RunService:Set3dRenderingEnabled(not state) end)
    if not ok then Notify("Warn", "[FPS Mode] Set3dRenderingEnabled unavailable: " .. tostring(err)) end

    if state then
        ensureFpsOverlay()
        if FpsOverlayGui then FpsOverlayGui.Enabled = true end
        fpsBooost()
    elseif FpsOverlayGui then
        FpsOverlayGui.Enabled = false
    end

    if FpsToggleBtn then
        FpsToggleBtn.Text = state and "FPS: ON" or "FPS: OFF"
        FpsToggleBtn.TextColor3 = state and Palette.Success or Palette.TextSecond
    end
    Notify("Print", "[FPS Mode] " .. (state and "Enabled" or "Disabled"))
end

local FpsButtonGui
pcall(function()
    FpsButtonGui = Instance.new("ScreenGui")
    FpsButtonGui.Name = "FpsToggleGui"
    FpsButtonGui.ResetOnSpawn = false
    FpsButtonGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    FpsButtonGui.DisplayOrder = 1000
    FpsButtonGui.IgnoreGuiInset = true
    FpsButtonGui.Parent = CoreGui

    FpsToggleBtn = Instance.new("TextButton")
    FpsToggleBtn.Name = "FpsToggleButton"
    FpsToggleBtn.Size = UDim2.new(0, 90, 0, 30)
    FpsToggleBtn.AnchorPoint = Vector2.new(0.5, 0)
    FpsToggleBtn.Position = UDim2.new(0.5, 0, 0, 14)
    FpsToggleBtn.BackgroundColor3 = Palette.Panel
    FpsToggleBtn.AutoButtonColor = false
    FpsToggleBtn.Text = "FPS: OFF"
    FpsToggleBtn.TextColor3 = Palette.TextSecond
    FpsToggleBtn.Font = Enum.Font.GothamMedium
    FpsToggleBtn.TextSize = 13
    FpsToggleBtn.Parent = FpsButtonGui
    corner(8, FpsToggleBtn)
    local FpsToggleStroke = Instance.new("UIStroke")
    FpsToggleStroke.Color = Palette.Accent
    FpsToggleStroke.Thickness = 1
    FpsToggleStroke.Transparency = 0.5
    FpsToggleStroke.Parent = FpsToggleBtn
    hoverColorSwap(FpsToggleBtn, Palette.Panel, Palette.PanelAlt)

    FpsToggleBtn.MouseButton1Click:Connect(function() setFpsMode(not getgenv().Fps) end)
    if getgenv().Fps == true then setFpsMode(getgenv().Fps) end
end)

local function initializeHotbar()
    Notify("print", "[Hotbar] Waiting for hotbar to initialize...")
    
    local hotbarSlots = EquippingModule.getHotbar(LocalPlayer)
    local waitCount = 0
    while not hotbarSlots or #hotbarSlots == 0 do
        if waitCount > 100 then
            Notify("error", "[Hotbar] Timeout waiting for hotbar slots!")
            return false
        end
        task.wait(0.2)
        hotbarSlots = EquippingModule.getHotbar(LocalPlayer)
        waitCount = waitCount + 1
    end
    
    Notify("print", "[Hotbar] Hotbar detected! Populating data...")
    table.clear(hotbarData)
    
    for slotIndex, itemUid in pairs(hotbarSlots) do
        if itemUid then
            local itemData = Inventory.getItem(itemUid)
            
            if itemData then
                local baseId = itemData.itemId or itemData.id or itemData.uid
                local dbEntry = TowerDatabase[baseId]
                
                if dbEntry and type(dbEntry) == "table" and dbEntry.stats then
                    local costs = {}
                    for level, levelData in pairs(dbEntry.stats) do
                        if type(levelData) == "table" and levelData.cost then
                            costs[tonumber(level) or level] = levelData.cost
                        end
                    end
                    
                    hotbarData[slotIndex] = {
                        uid = tostring(itemUid),
                        name = tostring(baseId),
                        dbId = tostring(baseId),
                        costs = costs,
                        fullData = itemData
                    }
                    
                    local costStr = ""
                    for lv = 1, 4 do
                        if costs[lv] then costStr = costStr .. string.format("[%d]=%d ", lv, costs[lv]) end
                    end
                    
                    Notify("print", string.format("[Hotbar] Slot %d -> %s (UID: %s) Costs: %s", 
                        slotIndex, tostring(baseId), tostring(itemUid), costStr))
                else
                    Notify("warn", string.format("[Hotbar] Slot %d: No database entry for %s", 
                        slotIndex, tostring(baseId)))
                end
            else
                Notify("warn", string.format("[Hotbar] Slot %d: UID '%s' has no inventory data", 
                    slotIndex, tostring(itemUid)))
            end
        end
    end
    
    Notify("print", string.format("[Hotbar] Initialization complete! Loaded %d towers", 
        table.getn(hotbarData)))
    return true
end

local CashUtils = nil

local function initCashUtils()
    if not CashUtils then
        pcall(function()
            CashUtils = require(ReplicatedStorage.Modules.Round.utils.cash_utils)
            Notify("print", "[Cash Utils] Module loaded successfully!")
        end)
    end
    return CashUtils
end

local function getPlayerCash()
    local cashUtils = initCashUtils()
    
    if cashUtils and cashUtils.getRoundCash then
        local ok, cash = pcall(function()
            return cashUtils.getRoundCash(LocalPlayer)
        end)
        if ok and cash then return cash or 0 end
    end
    
    local ok, result = pcall(function()
        local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not PlayerGui then return 0 end
        
        local path = {"MainHud", "Hud", "RoundHud", "Hud", "Inner", "BottomCentre", "Cash"}
        local current = PlayerGui
        
        for _, name in ipairs(path) do
            current = current:FindFirstChild(name)
            if not current then return 0 end
        end
        
        if current:IsA("TextLabel") then
            local cashText = tostring(current.Text)
            local cleaned = cashText:gsub("[$,]", "")
            return tonumber(cleaned) or 0
        end
        
        return 0
    end)
    
    return ok and result or 0
end

local function hasCash(amount)
    local cashUtils = initCashUtils()
    if cashUtils and cashUtils.hasCash then
        return cashUtils.hasCash(amount, LocalPlayer)
    end
    return getPlayerCash() >= amount
end

-- Returns a "(current/required)" string for action labels
local function cashTag(required)
    return string.format("(%s/%s)", formatNumber(getPlayerCash()), formatNumber(required or 0))
end

local function waitForCash(amount, maxWait, label)
    maxWait = maxWait or 60
    local startTime = os.clock()
    while getPlayerCash() < amount do
        if os.clock() - startTime > maxWait then
            Notify("error", "[Cash] Timeout waiting for $" .. tostring(amount))
            return false
        end
        UpdateAction(string.format("%s %s", label or "Waiting", cashTag(amount)))
        task.wait(0.1)
    end
    return true
end

local function getTowerCost(towerUid, currentLevel)
    if not towerUid then return 0 end
    currentLevel = currentLevel or 0
    
    for slotIndex, data in pairs(hotbarData) do
        if data.uid == towerUid then
            local nextLevel = currentLevel + 1
            local cost = data.costs[nextLevel] or 0
            return cost
        end
    end
    
    return 0
end

local function getTowerName(towerUid)
    for _, data in pairs(hotbarData) do
        if data.uid == tostring(towerUid) then
            return data.name
        end
    end
    return "Tower"
end

local function getCachedTowerModel(towerIndex)
    if towerModels[towerIndex] then
        return towerModels[towerIndex]
    end
    
    local serverId = placedTowersByIndex[towerIndex]
    if serverId and towerModelsById[tostring(serverId)] then
        local model = towerModelsById[tostring(serverId)]
        towerModels[towerIndex] = model
        return model
    end
    
    return nil
end

local function getCachedTowerLevel(towerIndex)
    local towerModel = getCachedTowerModel(towerIndex)
    if not towerModel then return nil end
    
    local level = towerModel:GetAttribute("Upgrade") or 
                  towerModel:GetAttribute("Level") or
                  towerModel:GetAttribute("Evolution")
    
    if not level then
        local lvlVal = towerModel:FindFirstChild("Upgrade") or 
                      towerModel:FindFirstChild("Level") or
                      towerModel:FindFirstChild("Evolution")
        if lvlVal and lvlVal:IsA("ValueBase") then level = lvlVal.Value end
    end
    
    return tonumber(level) or nil
end

local function verifyAndLogUpgrade(job, oldLevel)
    task.wait(0.3)
    
    local newLevel = getCachedTowerLevel(job.towerIndex)
    
    if newLevel and newLevel > oldLevel then
        Notify("print", "✅ [Upgrade Success] Tower #" .. tostring(job.towerIndex) .. " leveled up: " .. tostring(oldLevel) .. " → " .. tostring(newLevel))
        return true
    else
        Notify("error", "❌ [Upgrade Failed] Tower #" .. tostring(job.towerIndex) .. " level mismatch. Expected: " .. tostring(oldLevel + 1) .. ", Got: " .. tostring(newLevel or "Unknown"))
        return false
    end
end

local function getPlacedTowerStats(towerIndex)
    local serverId = placedTowersByIndex[towerIndex]
    if not serverId then 
        if getgenv().Debug then
            Notify("warn", "[Tower Stats] No serverId found for tower index " .. tostring(towerIndex))
        end
        return nil 
    end
    
    local towerModel = getCachedTowerModel(towerIndex)
    
    if not towerModel then
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") then
                local attrId = obj:GetAttribute("ServerId") or obj:GetAttribute("Id") or obj:GetAttribute("UUID")
                local valId = obj:FindFirstChild("ServerId") or obj:FindFirstChild("Id")
                
                if (attrId and tostring(attrId) == tostring(serverId)) or 
                   (valId and valId:IsA("ValueBase") and tostring(valId.Value) == tostring(serverId)) or
                   (obj.Name == tostring(serverId)) then
                    towerModel = obj
                    towerModels[towerIndex] = towerModel
                    towerModelsById[tostring(serverId)] = towerModel
                    Notify("print", "[Tower Cache] Cached tower #" .. tostring(towerIndex) .. " (ServerId: " .. tostring(serverId) .. ")")
                    break
                end
            end
        end
    end

    if not towerModel then 
        return nil 
    end

    local stats = {
        Level = towerModel:GetAttribute("Upgrade") or 
                towerModel:GetAttribute("Level") or
                towerModel:GetAttribute("Evolution"),
        Target = towerModel:GetAttribute("Target") or 
                towerModel:GetAttribute("Priority")
    }
    
    if not stats.Level then
        local lvlVal = towerModel:FindFirstChild("Upgrade") or 
                      towerModel:FindFirstChild("Level") or
                      towerModel:FindFirstChild("Evolution")
        if lvlVal and lvlVal:IsA("ValueBase") then stats.Level = lvlVal.Value end
    end
    if not stats.Target then
        local tgtVal = towerModel:FindFirstChild("Target") or towerModel:FindFirstChild("Priority")
        if tgtVal and tgtVal:IsA("ValueBase") then stats.Target = tgtVal.Value end
    end

    if getgenv().Debug then
        Notify("print", "[Tower Stats] Tower #" .. tostring(towerIndex) .. " - Level: " .. tostring(stats.Level or "Unknown"))
    end

    return stats
end

local function findDynamicGui(parent, path)
    local current = parent
    for _, name in ipairs(path) do
        current = current:FindFirstChild(name)
        if not current then return nil end
    end
    return current
end

local function spd(value:number)
    local spdEvent = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.SetSpeed
    spdEvent:FireServer(
        value
    )
    task.wait(value or 1)
end

local RemotesPath = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Remotes")
local PlaceTowerEvent = RemotesPath:WaitForChild("RemoteFunction"):WaitForChild("PlaceTower")

local mtHook; mtHook = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if rawequal(self, PlaceTowerEvent) and method == "InvokeServer" then
        local args = {...}
        local towerUID = args[1]
        local ctx = pendingPlacement -- consume immediately (before yielding)
        pendingPlacement = nil
        
        local serverId = mtHook(self, ...)
        
        if serverId then
            table.insert(placedTowersByIndex, serverId)
            local towerIndex = #placedTowersByIndex
            placedTowersUIDByIndex[towerIndex] = towerUID
            placedTowerDataByIndex[towerIndex] = {
                cframe = args[2],
                slot = ctx and ctx.slot or nil, -- placed via placeTower
                uid = ctx and ctx.uid or nil,   -- placed via spawnTempTower
            }
            Notify("print", "✓ Tower Registered: Index #" .. tostring(towerIndex) .. " (UID: " .. tostring(towerUID) .. " | ServerID: " .. tostring(serverId) .. ")")
            if getgenv().Debug then
                Notify("print", "[Debug] Tower will be cached on first stat lookup")
            end

            if getgenv().Fps == true then
                task.spawn(function()
                    local towerModel = nil
                    for i = 1, 6 do
                        task.wait(0.5)
                        for _, obj in ipairs(workspace:GetChildren()) do
                            if obj:IsA("Model") then
                                local attrId = obj:GetAttribute("serverId") or obj:GetAttribute("Id") or obj:GetAttribute("UUID")
                                local valId = obj:FindFirstChild("serverId") or obj:FindFirstChild("Id")
                                
                                if (attrId and tostring(attrId) == tostring(serverId)) or 
                                   (valId and valId:IsA("ValueBase") and tostring(valId.Value) == tostring(serverId)) or
                                   (obj.Name == tostring(serverId)) then
                                    towerModel = obj
                                    break
                                end
                            end
                        end
                        if towerModel then break end
                    end
                    
                    if towerModel then
                        for _, descendant in ipairs(towerModel:GetDescendants()) do
                            if descendant:IsA("AnimationController") then
                                descendant:Destroy()
                            end
                        end
                        if getgenv().Debug then
                            Notify("print", "[FPS Mode] Deleted AnimationController for Tower #" .. tostring(towerIndex))
                        end
                    end
                end)
            end
        else
            Notify("warn", "[Tower Placement] Server returned nil - tower may not have placed!")
        end
        
        return serverId
    end
    return mtHook(self, ...)
end)

local function placeTower(slotIndex, position, waitTime)
    waitTime = waitTime or 1
    
    local slotData = hotbarData[slotIndex]
    if not slotData or not slotData.uid then
        Notify("error", "[Tower Placement] No tower in hotbar slot " .. tostring(slotIndex))
        return false
    end
    
    local placingEvent = ReplicatedStorage.Modules.Remotes.RemoteFunction.PlaceTower
    if not placingEvent then
        Notify("error", "[Tower Placement] PlacingEvent remote not found!")
        return false
    end
    
    local cost = getTowerCost(slotData.uid, 0)
    Notify("print", "[Tower Placement] Tower: " .. tostring(slotData.name) .. " | Cost: $" .. tostring(cost))
    
    if cost > 0 then
        if not waitForCash(cost, 30, "Placing " .. tostring(slotData.name)) then
            Notify("error", "[Tower Placement] Failed to get cash for tower!")
            return false
        end
        Notify("print", "[Tower Placement] Got enough cash! Placing tower...")
    else
        Notify("warn", "[Tower Placement] Cost returned 0 - hotbarData may not be initialized!")
    end
    
    task.wait(0.2)

    local towerCFrame
    local posType = typeof(position)
    if posType == "CFrame" then
        towerCFrame = position
    elseif posType == "Vector3" then
        towerCFrame = CFrame.new(position)
    else
        Notify("error", "[Tower Placement] Invalid position type: " .. tostring(posType) .. " (expected Vector3 or CFrame)")
        return false
    end

    UpdateAction("Placing " .. tostring(slotData.name) .. " " .. cashTag(cost))
    local success, err = pcall(function()
        Notify("print", "[Tower Placement] Invoking server for " .. tostring(slotData.name) .. "...")
        pendingPlacement = {slot = slotIndex}
        local result = placingEvent:InvokeServer(slotData.uid, towerCFrame)
        pendingPlacement = nil
        if not result then
            Notify("warn", "[Tower Placement] Server returned nil for tower ID: " .. tostring(slotData.uid))
        end
        return result
    end)
    
    if not success then
        Notify("error", "[Tower Placement] PCall Error: " .. tostring(err))
    end
    
    task.wait(waitTime)
    return true
end

local function spawnTempTower(uid,pos,maxTowers,waittime)
    local placingEvent = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteFunction.PlaceTower
    if not placingEvent then
        Notify("error", "[Temp Tower] PlacingEvent remote not found!")
        return false
    end

    local towerCFrame
    local posType = typeof(pos)
    if posType == "CFrame" then
        towerCFrame = pos
    elseif posType == "Vector3" then
        towerCFrame = CFrame.new(pos)
    else
        Notify("error", "[Temp Tower] Invalid pos type: " .. tostring(posType) .. " (expected Vector3 or CFrame)")
        return false
    end

    for i = 1, maxTowers do
        local cost = getTowerCost(tostring(uid), 0)
        Notify("print", "[Temp Tower] Tower: " .. tostring(uid) .. " (" .. i .. "/" .. maxTowers .. ") | Cost: $" .. tostring(cost))

        if cost > 0 then
            if not waitForCash(cost, 30, string.format("Placing %s [%d/%d]", getTowerName(uid), i, maxTowers)) then
                Notify("error", "[Temp Tower] Failed to get cash for tower!")
                break
            end
            Notify("print", "[Temp Tower] Got enough cash! Placing tower...")
        else
            Notify("warn", "[Temp Tower] Cost returned 0 - hotbarData may not be initialized!")
        end

        task.wait(0.2)

        UpdateAction(string.format("Placing %s [%d/%d] %s", getTowerName(uid), i, maxTowers, cashTag(cost)))
        local success, err = pcall(function()
            Notify("print", "[Temp Tower] Invoking server for " .. tostring(uid) .. "...")
            pendingPlacement = {uid = tostring(uid)}
            local result = placingEvent:InvokeServer(tostring(uid), towerCFrame)
            pendingPlacement = nil
            if not result then
                Notify("warn", "[Temp Tower] Server returned nil for tower ID: " .. tostring(uid))
            end
            return result
        end)

        if not success then
            Notify("error", "[Temp Tower] PCall Error: " .. tostring(err))
        end

        task.wait()
    end

    task.wait(waittime or 0)
    return true
end

local function autoUpgradeTower(towerIndex, waitForMoney, interval, maxLevel)
    maxLevel = maxLevel or 5
    interval = interval or 1
    
    table.insert(autoUpgradeQueue, {
        towerIndex = towerIndex,
        waitForMoney = waitForMoney,
        interval = interval,
        maxLevel = maxLevel,
        trackedLevel = 1,
        lastUpgradeTime = os.clock()
    })
    
    Notify("print", string.format("[Upgrade Queue] Tower #%d added (Max Level: %d)", 
        towerIndex, maxLevel))
end

local function toggleSkip(enabled)
    local ok, err = pcall(function()
        local Event = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.UpdateSetting
        if Event then
            Event:FireServer("AutoSkip", enabled or false)
            Notify("print", "[Toggle Skip] AutoSkip set to: " .. tostring(enabled))
            return true
        end
        return false
    end)
    
    if not ok then
        Notify("warn", "[Toggle Skip] Error: " .. tostring(err))
        return false
    end
    return true
end

local function placeAllTowers(waitTime, position)
    waitTime = waitTime or 0.1
    position = position or CFrame.new(10000, -14, 100)
    
    Notify("print", "[Place All] Placing " .. tostring(table.getn(hotbarData)) .. " tower types at position")
    
    for slotIndex, _ in pairs(hotbarData) do
        placeTower(slotIndex, position, waitTime)
    end
    
    Notify("print", "[Place All] Tower placement complete!")
end

local function autoUpgradeAll(interval, maxLevel)
    interval = interval or 0.1
    maxLevel = maxLevel or 5
    
    local towersQueued = 0
    for towerIndex = 1, #placedTowersByIndex do
        if placedTowersByIndex[towerIndex] and not soldTowers[towerIndex] then
            autoUpgradeTower(towerIndex, true, interval, maxLevel)
            towersQueued = towersQueued + 1
        end
    end
    
    Notify("print", "[Auto Upgrade All] Queued " .. tostring(towersQueued) .. " towers for upgrade (Max Level: " .. tostring(maxLevel) .. ")")
end

local TargetOrder = {
    Front  = 1,
    Back   = 2,
    Strong = 3,
    Weak   = 4,
}

local function getCurrentTowerTarget(towerIndex)
    local towerModel = getCachedTowerModel(towerIndex)
    if towerModel then
        local target = towerModel:GetAttribute("Target") or towerModel:GetAttribute("Priority")
        if not target then
            local tgtVal = towerModel:FindFirstChild("Target") or towerModel:FindFirstChild("Priority")
            if tgtVal and tgtVal:IsA("ValueBase") then target = tgtVal.Value end
        end
        if target then return tostring(target) end
    end

    local stats = getPlacedTowerStats(towerIndex)
    if stats and stats.Target then
        return tostring(stats.Target)
    end

    return nil
end

local function changeTowerTarget(towerIndex, targetMode)
    local serverId = placedTowersByIndex[towerIndex]
    if not serverId then
        Notify("error", "[Tower Target] Tower #" .. tostring(towerIndex) .. " not placed yet")
        return
    end

    if soldTowers[towerIndex] then
        Notify("warn", "[Tower Target] Tower #" .. tostring(towerIndex) .. " was already sold")
        return
    end

    if not TargetOrder[targetMode] then
        Notify("error", "[Tower Target] Invalid target mode: " .. tostring(targetMode))
        return
    end

    local changeTargetRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.TogglePriority
    if not changeTargetRemote then
        Notify("error", "[Tower Target] TogglePriority remote not found!")
        return
    end

    local currentTarget = getCurrentTowerTarget(towerIndex)
    if not currentTarget or not TargetOrder[currentTarget] then
        if getgenv().Debug then
            Notify("warn", "[Tower Target] Couldn't read current target for tower #" .. tostring(towerIndex) .. ", assuming 'Front'")
        end
        currentTarget = "Front"
    end

    local currentIndex = TargetOrder[currentTarget]
    local targetIndex = TargetOrder[targetMode]

    if currentIndex == targetIndex then
        if getgenv().Debug then
            Notify("print", "[Tower Target] Tower #" .. tostring(towerIndex) .. " already set to " .. targetMode)
        end
        return
    end

    local forwardSteps = (targetIndex - currentIndex) % 4
    local direction, steps
    if forwardSteps <= 2 then
        direction = 1
        steps = forwardSteps
    else
        direction = -1
        steps = 4 - forwardSteps
    end

    for _ = 1, steps do
        pcall(function()
            changeTargetRemote:FireServer(tonumber(serverId), direction)
        end)
        task.wait(0.15)
    end

    Notify("print", "[Tower Target] Tower #" .. tostring(towerIndex) .. " -> " .. targetMode ..
        " (" .. currentTarget .. " -> " .. targetMode .. ", " .. steps .. "x " .. (direction == 1 and "fwd" or "back") .. ")")
end

local function lockTower(towerIndex)
    local serverId = placedTowersByIndex[towerIndex]
    if not serverId then
        Notify("error", "[Tower Locking] Tower #" .. tostring(towerIndex) .. " not placed yet")
        return
    end
    if soldTowers[towerIndex] then
        Notify("warn", "[Tower Locking] Tower #" .. tostring(towerIndex) .. " was already sold")
        return
    end
    local lockRemote = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.ToggleLineLock
    if not lockRemote then
        Notify("error", "[Tower Locking] lock Remote not found!")
        return
    end
    lockRemote:FireServer(serverId)
    Notify("print", "[Tower Locking] Should've Changed Lock Tower")
    task.wait()
end

-- Sells a placed tower by its placement index.
-- IMPORTANT: placedTowersByIndex / placedTowersUIDByIndex are NOT modified, so every
-- other tower's index stays valid. Sold towers are tracked in soldTowers instead.
local function sellTower(towerIndex, waitTime)
    waitTime = waitTime or 0.3

    local serverId = placedTowersByIndex[towerIndex]
    if not serverId then
        Notify("error", "[Tower Selling] Tower #" .. tostring(towerIndex) .. " not placed yet")
        return false
    end

    if soldTowers[towerIndex] then
        Notify("warn", "[Tower Selling] Tower #" .. tostring(towerIndex) .. " was already sold")
        return false
    end

    local sellRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent:FindFirstChild("SellTower")
    if not sellRemote then
        Notify("error", "[Tower Selling] SellTower remote not found!")
        return false
    end

    local towerUid = placedTowersUIDByIndex[towerIndex]
    local towerName = getTowerName(towerUid)
    local model = getCachedTowerModel(towerIndex)
    UpdateAction(string.format("Selling %s #%d", towerName, towerIndex))

    -- Mark as sold first so the upgrade loops stop touching this tower immediately
    soldTowers[towerIndex] = true

    -- Drop pending upgrade jobs for this tower (the queue is not index-based, so this is safe)
    for i = #autoUpgradeQueue, 1, -1 do
        if autoUpgradeQueue[i].towerIndex == towerIndex then
            table.remove(autoUpgradeQueue, i)
        end
    end

    local ok, err = pcall(function()
        sellRemote:FireServer(tonumber(serverId))
    end)
    if not ok then
        soldTowers[towerIndex] = nil
        Notify("error", "[Tower Selling] FireServer failed: " .. tostring(err))
        return false
    end

    task.wait(waitTime)

    -- If the model is still in the world, the server rejected the sale (no_sell modifier / airborne)
    if model and model.Parent then
        soldTowers[towerIndex] = nil
        Notify("warn", "[Tower Selling] Tower #" .. tostring(towerIndex) .. " model still exists - sale rejected (no_sell raid modifier / airborne)")
        return false
    end

    Notify("print", "[Tower Selling] Sold " .. towerName .. " #" .. tostring(towerIndex) .. " (ServerID: " .. tostring(serverId) .. ")")
    return true
end

local function sellAllTowers(waitTime)
    for i = 1, #placedTowersByIndex do
        if placedTowersByIndex[i] and not soldTowers[i] then
            sellTower(i, waitTime or 0.1)
        end
    end
end

local function towerAnimcCheck()
    local totalTowers = #placedTowersByIndex
    local processedTowers = 0
    local animControllersDestroyed = 0
    
    if totalTowers == 0 then
        Notify("warn", "[Anim Check] No towers registered yet!")
        return
    end
    
    for towerIndex = 1, totalTowers do
        local serverId = placedTowersByIndex[towerIndex]
        
        if not serverId or soldTowers[towerIndex] then
            if getgenv().Debug then
                Notify("print", "[Anim Check] Tower #" .. tostring(towerIndex) .. " has no serverId or was sold")
            end
            continue
        end
        
        local towerModel = towerModelsById[serverId]
        
        if not towerModel then
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:IsA("Model") then
                    local attrId = obj:GetAttribute("serverId") or obj:GetAttribute("Id") or obj:GetAttribute("UUID")
                    local valId = obj:FindFirstChild("serverId") or obj:FindFirstChild("Id")
                    
                    if (attrId and tostring(attrId) == tostring(serverId)) or 
                       (valId and valId:IsA("ValueBase") and tostring(valId.Value) == tostring(serverId)) or
                       (obj.Name == tostring(serverId)) then
                        towerModel = obj
                        towerModelsById[serverId] = obj
                        towerModels[towerIndex] = obj
                        break
                    end
                end
            end
        end
        
        if towerModel then
            for _, descendant in ipairs(towerModel:GetDescendants()) do
                if descendant:IsA("AnimationController") then
                    pcall(function()
                        descendant:Destroy()
                        animControllersDestroyed = animControllersDestroyed + 1
                    end)
                end
            end
            processedTowers = processedTowers + 1
            
            if getgenv().Debug then
                Notify("print", "[Anim Check] Tower #" .. tostring(towerIndex) .. " (ServerId: " .. tostring(serverId) .. ") cleaned ✓")
            end
        else
            if getgenv().Debug then
                Notify("warn", "[Anim Check] Tower #" .. tostring(towerIndex) .. " model not found in workspace!")
            end
        end
    end
    
    Notify("print", "[Anim Check] Complete! Processed: " .. tostring(processedTowers) .. "/" .. tostring(totalTowers) .. " towers | Destroyed: " .. tostring(animControllersDestroyed) .. " AnimationControllers")
end

local function voteDifficulty(difficulty, waitTime)
    waitTime = waitTime or 1
    difficulty = difficulty or "Normal"
    
    local RemotesPath = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Remotes")
    RemotesPath.RemoteEvent.RespondToQuery:FireServer("difficulties", difficulty)
    Notify("print", "[Difficulty Vote] Voted for: " .. tostring(difficulty))
    task.wait(waitTime)
end

local function enemyfpsBoost()
    task.spawn(function()
    local v3 = require(game:GetService("ReplicatedStorage").Databases.Challenges)
    for challengeKey, challengeData in pairs(v3) do
        print("Internal Name:", challengeKey, "| Display Name:", challengeData.name)
        local claimChall = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.ClaimReward
        claimChall:FireServer(
            tostring(challengeKey)
        )
    end
    end)
    task.spawn(function()
        getgenv().HealthGui = false
            workspace.DescendantAdded:Connect(function(descendant)
                if descendant.Name == "HealthBar" and descendant:IsA("BillboardGui") then
                    if descendant.Parent and descendant.Parent.Name == "Head" then
                        if getgenv().HealthGui == true then
                            descendant:Destroy()
                        elseif getgenv().HealthGui == false then
                            descendant.Parent.Parent:Destroy()
                        end
                    end
                elseif descendant.Name == "LootDrop_" .. LocalPlayer.Name then
                    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                    local humanoidRoot = character:WaitForChild("HumanoidRootPart", 5)
                    if humanoidRoot then
                        if descendant:IsA("BasePart") then
                            descendant.CFrame = humanoidRoot.CFrame
                        elseif descendant:IsA("Model") then
                            descendant:PivotTo(humanoidRoot.CFrame)
                        end
                    end
                elseif descendant.Name == "MiniBossHealthBar" and descendant:IsA("BillboardGui") then
                    if descendant.Parent and descendant.Parent.Name == "Head" then
                        if getgenv().HealthGui == true then
                            descendant:Destroy()
                        elseif getgenv().HealthGui == false then
                            descendant.Parent.Parent:Destroy()
                        end
                    end
                elseif descendant.Name == "FinalBossHealthBar" and descendant:IsA("BillboardGui") then
                    if descendant.Parent and descendant.Parent.Name == "Head" then
                        if getgenv().HealthGui == true then
                            descendant:Destroy()
                        elseif getgenv().HealthGui == false then
                            descendant.Parent.Parent:Destroy()
                        end
                    end
                end
            end)
    end)
end

local function autoPetrifyBreak()
    local Workspace = game:GetService("Workspace")

    local function autoBreakout(instance)
        if instance:IsA("ClickDetector") and instance.Name == "PetrifyBreakout" then
            task.spawn(function()
                while instance and instance.Parent do
                    fireclickdetector(instance)
                    task.wait(0.02)
                end
            end)
        end
    end

    for _, descendant in ipairs(Workspace:GetDescendants()) do
        autoBreakout(descendant)
    end

    Workspace.DescendantAdded:Connect(autoBreakout)
end

-- ============================================================================
-- Final boss response: when the final boss's totalPercent reaches 60 or more, react
-- based on which base (Left / Middle / Right) it is heading to. Fires once per boss.
-- Reads EnemyTracker.finalBoss (written by the ECS system). The checking loop is
-- started from the wave 45 routine (wv45) inside Macro().
-- ============================================================================
local BossResponsePositions = {
    Left   = CFrame.new(10022, -14, 140),
    Middle = CFrame.new(9984, -14, 154),
    Right  = CFrame.new(9966, -14, 132),
}
local bossResponded = {}   -- bossResponded[bossId] = true once the response has been triggered
local bossResponseBusy = false
local bossWatcherRunning = false


-- ============================================================================
-- Stun replace: after bossResponse has fired, any tower that gets stunned by a
-- normal boss/enemy mechanic (e.g. GroundSlam) is sold and re-placed at the
-- same CFrame, then queued to max upgrade. Petrify stuns are ignored (the
-- PetrifyBreakout auto-clicker already handles those).
-- Server marks stunned towers with the model attribute "Stunned" (tower_stun.lua).
-- ============================================================================
local StunReplace = {
    Enabled = true,
    MaxLevel = 5,        -- same max level bossResponse uses
    PetrifyGrace = 0.6,  -- wait this long after seeing a stun so petrify markers can appear
    RetryCooldown = 5,   -- seconds before retrying a tower whose sale was rejected
    Debug = false,       -- set true to log the watcher's flow (detections, replacements)
    -- stunned towers carrying one of these effect ids are left alone (effect id = module name
    -- in StatusEffects.effects). Add e.g. freeze = true if you don't want those replaced either.
    SkipEffects = {petrify = true},
}
local stunReplaceRunning = false
local stunReplaceBusy = false
local stunRetryAt = {} -- stunRetryAt[towerIndex] = os.clock() time we may try again

-- Prints directly (Notify is silent unless getgenv().Print == true). Warn/error always show.
local function srLog(kind, msg)
    if not (StunReplace.Debug or kind == "warn" or kind == "error") then return end
    msg = "[Stun Replace] " .. msg
    if getgenv().Print == true then
        Notify(kind, msg) -- Notify prints/warns it itself
    elseif kind == "warn" or kind == "error" then
        warn(msg)
    else
        print(msg)
    end
end

-- Same id matching the rest of the script uses to map a workspace model -> serverId
local function modelServerId(obj)
    local id = obj:GetAttribute("ServerId") or obj:GetAttribute("serverId")
        or obj:GetAttribute("Id") or obj:GetAttribute("UUID")
    if id == nil then
        local v = obj:FindFirstChild("ServerId") or obj:FindFirstChild("serverId") or obj:FindFirstChild("Id")
        if v and v:IsA("ValueBase") then id = v.Value end
    end
    return tostring(id or obj.Name)
end

-- tower_stun.lua sets "Stunned" (and "StunSeconds") on the model
local function isModelStunned(m)
    return m:GetAttribute("Stunned") ~= nil or m:GetAttribute("StunSeconds") ~= nil
end

-- ASSUMPTION: a petrified tower carries a PetrifyBreakout ClickDetector somewhere under
-- its model, or a Petrified/Petrify attribute. Verify in Explorer and adjust if needed.
local function isPetrified(model)
    if model:GetAttribute("Petrified") or model:GetAttribute("Petrify") then return true end
    return model:FindFirstChild("PetrifyBreakout", true) ~= nil
end

-- ECS access: the game replicates its Jecs world to the client (every ct component is
-- Replecs.shared). The server entity id is (very likely) the serverId PlaceTower returns,
-- and replicator.client:get_client_entity() maps it to the local entity. Used as a second
-- stun signal next to the model attributes. Everything is pcall'd; if it fails we just
-- fall back to attributes.
local ECS = {ok = false, err = nil}
do
    local ok, err = pcall(function()
        local Entities = ReplicatedStorage.Modules.Entities
        ECS.ct = require(Entities.ct)
        ECS.world = require(Entities.world)
        ECS.replicator = require(Entities.replicator)
        assert(ECS.replicator.client, "replicator.client missing")
    end)
    ECS.ok = ok
    if not ok then ECS.err = tostring(err) end
end

local function clientEntityOf(serverId)
    if not ECS.ok then return nil end
    local ok, ce = pcall(function()
        return ECS.replicator.client:get_client_entity(tonumber(serverId) or serverId)
    end)
    if ok and ce ~= nil and ECS.world:contains(ce) then return ce end
    return nil
end

local function isEntityStunned(serverId)
    local ce = clientEntityOf(serverId)
    if not ce then return false end
    local ok, res = pcall(function() return ECS.world:has(ce, ECS.ct.Stunned) end)
    return ok and res == true
end

local function entityModel(serverId)
    local ce = clientEntityOf(serverId)
    if not ce then return nil end
    local ok, m = pcall(function() return ECS.world:get(ce, ECS.ct.Model) end)
    if ok and typeof(m) == "Instance" and m.Parent then return m end
    return nil
end

local function isTowerStunned(towerIndex)
    local m = towerModels[towerIndex]
    if m and m.Parent and isModelStunned(m) then return true end
    local sid = placedTowersByIndex[towerIndex]
    return sid ~= nil and isEntityStunned(sid)
end

-- StatusEffects.lua: an effect is its own entity with ct.Effect = {id = ...} and a
-- ct.Affects relationship pointing at the target entity. If those entities replicate to the
-- client, we can list the effect ids on a tower (e.g. to recognise petrify).
local function effectIdsOn(serverId)
    local ids = {}
    local ce = clientEntityOf(serverId)
    if not ce then return ids end
    pcall(function()
        for e, data in ECS.world:query(ECS.ct.Effect) do
            local ok, tgt = pcall(function() return ECS.world:target(e, ECS.ct.Affects) end)
            if ok and tgt == ce then
                table.insert(ids, tostring(type(data) == "table" and data.id or data))
            end
        end
    end)
    return ids
end

-- Treated as petrified if the model has a petrify marker OR an effect listed in StunReplace.SkipEffects is on the tower
local function isTowerPetrified(towerIndex, model)
    if model and model.Parent and isPetrified(model) then return true end
    local sid = placedTowersByIndex[towerIndex]
    if sid then
        for _, id in ipairs(effectIdsOn(sid)) do
            if StunReplace.SkipEffects[string.lower(id)] then return true end
        end
    end
    return false
end

-- Scans the workspace (top level + folders up to 3 deep) for stunned models and maps them
-- back to tower indices. Does NOT depend on the model cache being filled beforehand.
local function findStunnedTowers()
    local indexById = {}
    for i = 1, #placedTowersByIndex do
        local sid = placedTowersByIndex[i]
        if sid and not soldTowers[i] then indexById[tostring(sid)] = i end
    end

    local found, seen = {}, {}
    local function consider(obj)
        if not (obj:IsA("Model") and isModelStunned(obj)) then return end
        local i = indexById[modelServerId(obj)]
        if i and not seen[i] and (stunRetryAt[i] or 0) <= os.clock() then
            seen[i] = true
            towerModels[i] = obj
            towerModelsById[tostring(placedTowersByIndex[i])] = obj
            table.insert(found, i)
        end
    end
    local function walk(parent, depth)
        for _, obj in ipairs(parent:GetChildren()) do
            if obj:IsA("Folder") then
                if depth < 3 then walk(obj, depth + 1) end
            else
                consider(obj)
            end
        end
    end
    walk(workspace, 1)

    -- second signal: the replicated ECS Stunned component
    if ECS.ok then
        for sid, i in pairs(indexById) do
            if not seen[i] and (stunRetryAt[i] or 0) <= os.clock() and isEntityStunned(sid) then
                seen[i] = true
                if not (towerModels[i] and towerModels[i].Parent) then
                    local m = entityModel(sid)
                    if m then towerModels[i] = m; towerModelsById[sid] = m end
                end
                table.insert(found, i)
            end
        end
    end
    return found
end

local function replaceStunnedTower(towerIndex)
    local data = placedTowerDataByIndex[towerIndex]
    local cf = data and data.cframe
    if not cf then
        srLog("warn", "Tower #" .. tostring(towerIndex) .. " has no saved placement data, skipping")
        return false
    end

    -- placeTower works by hotbar slot: use the saved slot, or map a temp-tower uid back to a slot
    local slot = data.slot
    if not slot and data.uid then
        for s, h in pairs(hotbarData) do
            if tostring(h.uid) == tostring(data.uid) then slot = s break end
        end
    end
    if not slot then
        srLog("warn", "Tower #" .. tostring(towerIndex) .. " has no hotbar slot, skipping")
        return false
    end

    --srLog("print", string.format("Replacing tower #%d (slot %s)", towerIndex, tostring(slot)))
    local target = getCurrentTowerTarget(towerIndex) -- keep its targeting mode
    if not sellTower(towerIndex, 0.4) then
        srLog("warn", "Sale of tower #" .. tostring(towerIndex) .. " failed/rejected")
        return false
    end

    -- Already sold at this point, so retry the placement a few times if it doesn't register
    local newIndex
    for attempt = 1, 3 do
        local before = #placedTowersByIndex
        placeTower(slot, cf, 0) -- the namecall hook registers the tower synchronously (and saves its slot)
        if #placedTowersByIndex > before then
            newIndex = #placedTowersByIndex
            break
        end
        srLog("warn", string.format("Re-place attempt %d/3 failed for slot %s", attempt, tostring(slot)))
        task.wait(1)
    end
    if not newIndex then
        srLog("error", "Sold tower #" .. tostring(towerIndex) .. " but could not re-place it!")
        return false
    end

    autoUpgradeTower(newIndex, true, 0.05, StunReplace.MaxLevel)
    if target and TargetOrder[target] and target ~= "Front" then
        task.spawn(function()
            task.wait(0.7)
            changeTowerTarget(newIndex, target)
        end)
    end
    --srLog("print", string.format("Tower #%d -> #%d (max level %d queued)", towerIndex, newIndex, StunReplace.MaxLevel))
    return true
end

local function startStunReplaceWatcher()
    if stunReplaceRunning or not StunReplace.Enabled then return end
    stunReplaceRunning = true
    table.clear(stunRetryAt)
    local matchId = currentMatchId
    --srLog("print", "Watcher started (ECS " .. (ECS.ok and "available" or ("UNAVAILABLE: " .. tostring(ECS.err))) .. ")")

    task.spawn(function()
        while currentMatchId == matchId do
            task.wait(0.25)

            if bossResponseBusy or stunReplaceBusy then continue end

            local okScan, stunned = pcall(findStunnedTowers)
            if not okScan then
                srLog("warn", "Scan error: " .. tostring(stunned))
                continue
            end

            if #stunned > 0 then
                --srLog("print", "Stunned towers detected: #" .. table.concat(stunned, ", #"))
                stunReplaceBusy = true
                task.wait(StunReplace.PetrifyGrace)
                local ok, err = pcall(function()
                    for _, i in ipairs(stunned) do
                        if currentMatchId ~= matchId or bossResponseBusy then break end
                        local m = towerModels[i]
                        if soldTowers[i] or not isTowerStunned(i) then continue end

                        if isTowerPetrified(i, m) then
                            stunRetryAt[i] = os.clock() + 2
                        elseif not replaceStunnedTower(i) then
                            stunRetryAt[i] = os.clock() + StunReplace.RetryCooldown
                        end
                    end
                end)
                if not ok then srLog("error", "Error: " .. tostring(err)) end
                stunReplaceBusy = false
            end
        end
        stunReplaceRunning = false
        --srLog("print", "Watcher stopped")
    end)
end

local function bossResponse()
    local boss = EnemyTracker.finalBoss
    if not boss then
        table.clear(bossResponded) -- boss gone: allow the next one to trigger
        return false
    end
    if bossResponded[boss.id] or bossResponseBusy then return false end

    local totalPercent, base = boss.totalPercent, boss.base
    local pos = base and BossResponsePositions[base]
    if not (totalPercent and pos and totalPercent >= 60) then return false end

    bossResponded[boss.id] = true
    bossResponseBusy = true
    Notify("print", "[Boss Response] Reacting to " .. string.upper(base) .. " threat")
    startStunReplaceWatcher() -- idles while bossResponseBusy, then replaces towers stunned by boss mechanics
    local ok, err = pcall(function()
        --print("[Boss Response] Reacting to " .. string.upper(base) .. " threat: totalPercent=" .. tostring(totalPercent) .. ", base=" .. tostring(base))
        sellAllTowers(0.1)
        placeAllTowers(0.05, pos)
        placeAllTowers(0.05, pos)
        placeAllTowers(0.05, pos)
        placeAllTowers(0.05, pos)
        autoUpgradeAll(0.05, 5)
    end)
    if not ok then Notify("warn", "[Boss Response] Error: " .. tostring(err)) end
    bossResponseBusy = false
    return true
end

local function Macro()
    currentMatchId = currentMatchId + 1
    table.clear(placedTowersByIndex)
    table.clear(placedTowersUIDByIndex)
    table.clear(placedTowerDataByIndex)
    table.clear(soldTowers)
    table.clear(autoUpgradeQueue)
    table.clear(towerModels)
    table.clear(towerModelsById)

    UpdateMacroStep("Starting Match Template")
    UpdateAction("Idle")
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
    local waveRoutineRunning = false

    local function waitForUpgrades()
        while #autoUpgradeQueue > 0 and isMatchActive do
            task.wait(0.5)
        end
    end
    
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
        voteDifficulty("Horror",0)--Easy,Normal,Horror,Endless,Gauntlet

        Notify("print", "[Macro] Waiting for vote GUI to disappear...")
        repeat task.wait(0.25) until not findDynamicGui(PlayerGui, {"MainHud", "DifficultyVote"})
        Notify("print", "[Macro] Difficulty GUI cleared. Macro active.")
    else
        Notify("warn", "[Macro] Difficulty vote GUI never appeared (might already be voted)")
    end

    task.spawn(function()
        while isMatchActive and task.wait(0.1) do
            if #autoUpgradeQueue == 0 then
                if not waveRoutineRunning then UpdateAction("Idle") end
                continue
            end
            
            if getgenv().UpgradeMode == "Sequential" then
                local job = autoUpgradeQueue[1]
                if not job then continue end

                -- Skip jobs for towers that were sold
                if soldTowers[job.towerIndex] then
                    table.remove(autoUpgradeQueue, 1)
                    continue
                end
                
                local serverId = placedTowersByIndex[job.towerIndex]
                
                if not serverId then 
                    if getgenv().Debug then
                        Notify("warn", "[Sequential] Tower #" .. tostring(job.towerIndex) .. " has no serverId yet")
                    end
                    continue 
                end
                
                local currentLevel = getCachedTowerLevel(job.towerIndex)
                
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
                
                do
                    local pUid = placedTowersUIDByIndex[job.towerIndex]
                    local pCost = getTowerCost(pUid, currentLevel)
                    UpdateAction(string.format("Upgrading %s #%d (Lv %d → %d) %s",
                        getTowerName(pUid), job.towerIndex, currentLevel, currentLevel + 1, cashTag(pCost)))
                end

                if os.clock() - job.lastUpgradeTime >= job.interval then
                    local towerUid = placedTowersUIDByIndex[job.towerIndex]
                    local cost = getTowerCost(towerUid, currentLevel)
                    
                    if getgenv().Debug then
                        --Notify("print", "[Sequential] Tower #" .. tostring(job.towerIndex) .. " - Level: " .. tostring(currentLevel) .. "/" .. tostring(job.maxLevel) .. " | Cost: $" .. tostring(cost))
                    end
                    
                    local towerName = getTowerName(towerUid)
                    if job.waitForMoney and cost > 0 and getPlayerCash() < cost then
                        UpdateAction(string.format("Upgrading %s #%d (Lv %d → %d) %s",
                            towerName, job.towerIndex, currentLevel, currentLevel + 1, cashTag(cost)))
                        continue
                    end
                    
                    local UpgradeTowerRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.UpgradeTower
                    if UpgradeTowerRemote then
                        if getgenv().Debug then
                            Notify("print", "[Sequential] Upgrading tower #" .. tostring(job.towerIndex) .. " from level " .. tostring(currentLevel) .. " to " .. tostring(currentLevel + 1))
                        end
                        UpdateAction(string.format("Upgrading %s #%d (Lv %d → %d) %s",
                            towerName, job.towerIndex, currentLevel, currentLevel + 1, cashTag(cost)))
                        UpgradeTowerRemote:FireServer(tonumber(serverId))
                        job.trackedLevel = currentLevel + 1
                        job.lastUpgradeTime = os.clock()
                        task.wait(0.2)
                    end
                end

            elseif getgenv().UpgradeMode == "Priority" then
                local i = 1
                local labelSet = false
                while i <= #autoUpgradeQueue do
                    local job = autoUpgradeQueue[i]

                    -- Skip jobs for towers that were sold
                    if soldTowers[job.towerIndex] then
                        table.remove(autoUpgradeQueue, i)
                        continue
                    end

                    local serverId = placedTowersByIndex[job.towerIndex]
                    
                    if not serverId then
                        if getgenv().Debug then
                            Notify("warn", "[Upgrade] Tower #" .. tostring(job.towerIndex) .. " has no serverId yet")
                        end
                        i = i + 1
                        continue
                    end
                    
                    local currentLevel = getCachedTowerLevel(job.towerIndex)
                    
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
                    
                    if currentLevel >= job.maxLevel then
                        Notify("print", "[Upgrade] Priority Completed: Tower #" .. tostring(job.towerIndex) .. " (Level " .. tostring(currentLevel) .. ")")
                        table.remove(autoUpgradeQueue, i)
                        continue 
                    end
                    
                    local towerUid = placedTowersUIDByIndex[job.towerIndex]
                    local cost = getTowerCost(towerUid, currentLevel)
                    local hasEnoughCash = (cost == 0 or getPlayerCash() >= cost)
                    
                    if getgenv().Debug then
                        Notify("print", "[Upgrade] Tower #" .. tostring(job.towerIndex) .. " - Level: " .. tostring(currentLevel) .. "/" .. tostring(job.maxLevel) .. " | Cost: $" .. tostring(cost) .. " | Cash: $" .. tostring(getPlayerCash()))
                    end
                    
                    local towerName = getTowerName(towerUid)
                    if job.waitForMoney and not hasEnoughCash then
                        if not labelSet then
                            UpdateAction(string.format("Upgrading %s #%d (Lv %d → %d) %s",
                                towerName, job.towerIndex, currentLevel, currentLevel + 1, cashTag(cost)))
                        end
                        break
                    end
                    
                    if not labelSet then
                        labelSet = true
                        UpdateAction(string.format("Upgrading %s #%d (Lv %d → %d) %s",
                            towerName, job.towerIndex, currentLevel, currentLevel + 1, cashTag(cost)))
                    end

                    if os.clock() - job.lastUpgradeTime >= job.interval then
                        local UpgradeTowerRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.UpgradeTower
                        if UpgradeTowerRemote then
                            if getgenv().Debug then
                                Notify("print", "[Upgrade] Upgrading tower #" .. tostring(job.towerIndex) .. " from level " .. tostring(currentLevel) .. " to " .. tostring(currentLevel + 1))
                            end
                            UpdateAction(string.format("Upgrading %s #%d (Lv %d → %d) %s",
                                towerName, job.towerIndex, currentLevel, currentLevel + 1, cashTag(cost)))
                            UpgradeTowerRemote:FireServer(tonumber(serverId))
                            job.trackedLevel = currentLevel + 1
                            job.lastUpgradeTime = os.clock()
                            task.wait(0.2)
                        end
                    end
                    
                    i = i + 1
                end
            end
        end
    end)


local function wv1()
        spd(2)
        Notify("print", "[Wave 1]")
        --Titan
        placeTower(2, CFrame.new(10000, -14, 77), 0.5) --1
        placeTower(2, CFrame.new(10000, -14, 3), 0.5) --2
        --master
        placeTower(5, CFrame.new(10037, -14, 172), 0.5) --3
        placeTower(5, CFrame.new(9994, -14, 173), 0.5) --4
        placeTower(5, CFrame.new(9951, -14, 168), 0.5) --5
        --beast
        placeTower(1, CFrame.new(9968, -14, 60), 0.5) --6
        placeTower(1, CFrame.new(10025, -14, 70), 0.5) --7
        placeTower(1, CFrame.new(10025, -14, 70), 0.5) --8
        --watcher
        placeTower(3, CFrame.new(10032, -14, 10), 0.5) --9
        placeTower(3, CFrame.new(10013, -14, 8), 0.5) --10
        placeTower(3, CFrame.new(9992, -14, -18), 0.5) --11
        --arch
        placeTower(4, CFrame.new(9987, -14, 7), 0.5) --12
        placeTower(4, CFrame.new(10005, -14, 8), 0.5) --13
        placeTower(4, CFrame.new(10023, -14, 9), 0.5) --14
        placeTower(4, CFrame.new(10006, -14, -19), 0.5) --15
    end
    local function wv2()
        changeTowerTarget(9, "Strong")
        changeTowerTarget(10, "Strong")
        changeTowerTarget(11, "Strong")

        changeTowerTarget(12, "Strong")
        changeTowerTarget(13, "Strong")
        changeTowerTarget(14, "Strong")
        changeTowerTarget(15, "Strong")
    end
    local function wv3()
        Notify("print", "[Wave 3]")
        --master
        autoUpgradeTower(3, true, 0.1)
        autoUpgradeTower(4, true, 0.1)
        autoUpgradeTower(5, true, 0.1)
        --titan
        autoUpgradeTower(1, true, 0.1)
        autoUpgradeTower(2, true, 0.1)
        waitForUpgrades()
    end
    local function wv8()
        Notify("print", "[Wave 16]")
        --Beast
        autoUpgradeTower(6, true, 0.1)
        autoUpgradeTower(7, true, 0.1)
        autoUpgradeTower(8, true, 0.1)
        --watcher
        autoUpgradeTower(9, true, 0.1)
        autoUpgradeTower(10, true, 0.1)
        autoUpgradeTower(11, true, 0.1)
        waitForUpgrades()
    end
    local function wv9()
        Notify("print", "[Wave 17]")
        --arch
        autoUpgradeTower(12, true, 0.1)
        autoUpgradeTower(13, true, 0.1)
        autoUpgradeTower(14, true, 0.1)
        autoUpgradeTower(15, true, 0.1)
        waitForUpgrades()
    end
    local function wv44()
        Notify("print", "[Wave 44]")
        toggleSkip(false)
        waitForUpgrades()
    end
    local function wv45()
        Notify("print", "[Wave 45]")
        toggleSkip(true)

        -- Start checking the final boss (distance to goal / base) from wave 45 onward
        if not bossWatcherRunning then
            bossWatcherRunning = true
            task.spawn(function()
                while isMatchActive do
                    task.wait(0.1)
                    pcall(bossResponse)
                end
                bossWatcherRunning = false
            end)
        end

        waitForUpgrades()
    end
    
    local waveActions = {
        [1] = wv1,
        [2] = wv2,
        [3] = wv3,
        [8] = wv8,
        [9] = wv9,
        [44] = wv44,
        [45] = wv45
    }

    local sortedWaves = {}
    for waveNum in pairs(waveActions) do
        table.insert(sortedWaves, waveNum)
    end
    table.sort(sortedWaves)

    local waveQueue = {}
    local completedWaves = {} -- Track which waves have actually FINISHED (not just queued)
    local queuedWaves = {} -- Track which waves are already in the queue to prevent duplicates
    local executingWaves = {} -- Track waves currently being executed
    local runningWave = nil
    local completedCount = 0
    local lastCheckedWave = 0 -- Track last wave we checked to prevent continuous re-queueing

    -- Rebuilds the Step label from the REAL queue state. Called every time the
    -- queue changes (wave queued, wave started, wave finished) so it never goes stale.
    local function refreshWaveStatus()
        if not isMatchActive then return end
        local queuedList = {}
        for _, w in ipairs(waveQueue) do table.insert(queuedList, tostring(w)) end

        local nextTrigger = nil
        for _, w in ipairs(sortedWaves) do
            if not completedWaves[w] and w ~= runningWave then nextTrigger = w break end
        end

        local text = runningWave and ("Running Wave " .. runningWave) or "No routine running"
        text = text .. string.format(" | Queued: %d", #waveQueue) -- FIXED: Count actual queue length
        if #queuedList > 0 then text = text .. " [" .. table.concat(queuedList, ", ") .. "]" end
        text = text .. string.format(" | Done: %d/%d", completedCount, #sortedWaves)
        if nextTrigger then text = text .. " | Next: W" .. nextTrigger end
        UpdateMacroStep(text)
    end

    task.spawn(function()
        while isMatchActive do
            local nextWave = table.remove(waveQueue, 1)
            if nextWave then
                queuedWaves[nextWave] = nil -- Remove from queued tracking when about to run
                executingWaves[nextWave] = true -- Mark as executing
                runningWave = nextWave
                refreshWaveStatus()
                Notify("print", "[Macro] Running Wave " .. tostring(nextWave) .. " routine. Remaining in queue: " .. tostring(#waveQueue))
                waveRoutineRunning = true
                
                local ok, err = pcall(waveActions[nextWave])
                
                waveRoutineRunning = false
                -- Mark complete AFTER pcall finishes
                executingWaves[nextWave] = nil -- Wave is done executing
                completedWaves[nextWave] = true -- Mark as completed
                completedCount = completedCount + 1
                runningWave = nil
                refreshWaveStatus()
                
                if not ok then
                    Notify("error", "[Macro] Wave " .. tostring(nextWave) .. " routine errored: " .. tostring(err))
                end
                Notify("print", "[Macro] Wave " .. tostring(nextWave) .. " completed! [" .. tostring(completedCount) .. "/" .. tostring(#sortedWaves) .. "]")
                if #waveQueue == 0 and #autoUpgradeQueue == 0 then
                    UpdateAction("Idle")
                end
            else
                task.wait(0.1)
            end
        end
    end)

    task.spawn(function()
        while isMatchActive and task.wait(0.5) do
            local gameOverGui = findDynamicGui(PlayerGui, {"MainHud", "Hud", "RoundHud", "Hud", "GameOver"})
            if gameOverGui then
                UpdateMacroStep("Match Ended - Cleaning up")
                Notify("print", "[Macro] GameOver UI spawned. Stopping loops...")
                getgenv().Ability = false
                isMatchActive = false

                if getgenv().Garden == true then
                    UpdateMacroStep("Garden Mode - Cashing Out")
                    Notify("print", "[Macro] Garden mode enabled. Cashing out...")
                    local Event = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.CancelEndless
                    pcall(function()
                        Event:FireServer()
                    end)
                    Notify("print", "[Macro] Cash out remote fired!")
                    task.wait(2)
                end

                if getgenv().Replay == true then
                    UpdateMacroStep("Voting Replay")
                    task.spawn(function()
                        print("sendingWebHook")
                        getgenv().WEBHOOK_URL = "https://discord.com/api/webhooks/1414475376230535199/F6V5IZJkOUMdxd-ZdC32JdlaTw-FGDz-raRMGW7a6FsYTmYtRkqOSfLy123hat3xSNR1"
                        getgenv().AUTO_SEND = true
                        getgenv().DEBUG = true
                        loadstring(game:HttpGet('https://raw.githubusercontent.com/lghft/Current/refs/heads/main/House/webhook.lua'))()
                        --print("Sent WebHook??")
                    end)
                    local RespondRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent.RespondToQuery
                    if RespondRemote then
                        RespondRemote:FireServer("game_over", true)
                    end
                    
                    Notify("print", "[Macro] Waiting for new match DifficultyVote GUI...")
                    task.wait(2)
                    task.spawn(Macro)
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
                local waveText = (tostring(waveLabel.Text):gsub("<[^>]->", ""))
                local currentWave = tonumber(waveText:match("Wave%s*(%d+)")) or tonumber(waveText:match("(%d+)"))
                
                if getgenv().Garden == true and currentWave and currentWave >= getgenv().GardenWave and not completedWaves["gardencashout"] then
                    completedWaves["gardencashout"] = true
                    UpdateMacroStep("Garden Cashout Wave " .. tostring(getgenv().GardenWave))
                    Notify("print", "[Macro] Garden mode: Reached wave " .. tostring(getgenv().GardenWave) .. ". Cashing out...")
                    local Event = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.CancelEndless
                    pcall(function()
                        Event:FireServer()
                    end)
                    Notify("print", "[Macro] Cash out remote fired!")
                end
                
                if currentWave then
                    for _, waveNum in ipairs(sortedWaves) do
                        -- Only queue if: not completed, not already queued, not currently executing, and not already in waveQueue
                        local alreadyInQueue = false
                        for _, qw in ipairs(waveQueue) do
                            if qw == waveNum then alreadyInQueue = true break end
                        end
                        
                        if currentWave >= waveNum and not completedWaves[waveNum] and not queuedWaves[waveNum] and not executingWaves[waveNum] and not alreadyInQueue then
                            table.insert(waveQueue, waveNum)
                            queuedWaves[waveNum] = true -- Mark as queued
                            refreshWaveStatus()
                            Notify("print", "[Macro] Queued Wave " .. tostring(waveNum) .. " routine (current wave: " .. tostring(currentWave) .. ", queue size: " .. tostring(#waveQueue) .. ")")
                        end
                    end
                end
            end
        end
    end)
end

-- Main thread updater: reads GUI values and caches them for the spawned overlay loop
RunService.Heartbeat:Connect(function()
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            local label = findDynamicGui(playerGui, {"MainHud", "Hud", "RoundHud", "Hud", "Inner", "CentreTop", "Info", "WaveCounter"})
            if label and label:IsA("TextLabel") then
                local text = (tostring(label.Text):gsub("<[^>]->", ""))
                local cur, max = text:match("(%d+)%s*/%s*(.+)")
                if cur and max then
                    max = max:match("^%s*(.-)%s*$")
                    if max ~= "" then 
                        cachedWaveText = cur .. "/" .. max
                    else
                        cachedWaveText = cur
                    end
                else
                    local onlyCur = text:match("(%d+)")
                    if onlyCur then cachedWaveText = onlyCur end
                end
            end
        end
        
        cachedCash = getPlayerCash()
    end)
end)

task.spawn(function()
    while true do
        task.wait(0.25)
        if not (FpsOverlayGui and FpsOverlayGui.Enabled) then 
            task.wait(0.1)
            continue 
        end

        if OverlayLabels.Wave then
            OverlayLabels.Wave.Text = "Wave: " .. cachedWaveText
        end
        if OverlayLabels.Cash then
            OverlayLabels.Cash.Text = "Cash: $" .. formatNumber(cachedCash)
        end
        if OverlayLabels.Step then
            OverlayLabels.Step.Text = "Step: " .. cachedStepText
        end
        if OverlayLabels.Action then
            OverlayLabels.Action.Text = "Action: " .. cachedActionText
        end
    end
end)

autoPetrifyBreak()
Macro()
