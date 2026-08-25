if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(4)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local towerFolder = game.Workspace:WaitForChild("EntityModels"):WaitForChild("Towers")

local placedTowers = {}
local hotbarTowerIDs = {}
local activeAutoAbilities = {}
local currentTowerIndex = 0

-- Global Toggles
getgenv().Ability = false
getgenv().Replay = true
getgenv().Fps = true
getgenv().Debug = false
getgenv().Aizen = false

-- ==========================================
-- FORWARD DECLARATIONS (Scope Fix)
-- ==========================================
local LogContainer   -- ScrollingFrame that holds individual log entries

-- ==========================================
-- LOGGER SYSTEM (ported from UI.lua's Func:CreateLogger)
-- One TextLabel per entry, queued through Heartbeat so entries are
-- always created on the main thread no matter which thread logs.
-- ==========================================
local LoggerQueue = {
    messages = {},      -- each entry: {text = string, color = Color3}
    processing = false,
    maxMessages = 500
}

-- Sticky-bottom auto-scroll: only snap to the newest entry if the user
-- was already at (or near) the bottom before it was added. If they've
-- scrolled up to read older entries, new entries won't yank them back down.
local stickToBottom = true
local isAutoScrolling = false
local SCROLL_BOTTOM_SLACK = 12 -- px of slack still considered "at bottom"

local function isLogScrolledToBottom()
    local maxY = math.max(0, LogContainer.AbsoluteCanvasSize.Y - LogContainer.AbsoluteWindowSize.Y)
    return LogContainer.CanvasPosition.Y >= (maxY - SCROLL_BOTTOM_SLACK)
end

local function scrollLogToBottom()
    isAutoScrolling = true
    LogContainer.CanvasPosition = Vector2.new(0, math.max(0, LogContainer.AbsoluteCanvasSize.Y))
    isAutoScrolling = false
end

local Logger = {}

function Logger:Log(text, color)
    if not LogContainer then return end

    local wasAtBottom = stickToBottom

    local LogLabel = Instance.new("TextLabel")
    LogLabel.Name = "LogEntry"
    LogLabel.BackgroundTransparency = 1
    LogLabel.Size = UDim2.new(1, 0, 0, 0)
    LogLabel.AutomaticSize = Enum.AutomaticSize.Y
    LogLabel.Font = Enum.Font.Code
    LogLabel.Text = text
    LogLabel.TextColor3 = color or Palette.TextPrimary
    LogLabel.TextSize = 12
    LogLabel.TextXAlignment = Enum.TextXAlignment.Left
    LogLabel.TextWrapped = true
    LogLabel.RichText = true
    LogLabel.Parent = LogContainer

    -- Trim oldest entries so the log doesn't grow unbounded
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
        -- Deferred so it runs after the list layout has resized the canvas
        -- for the entry (and any trims) we just made.
        task.defer(scrollLogToBottom)
    end
end

function Logger:Clear()
    for _, item in ipairs(LogContainer:GetChildren()) do
        if item:IsA("TextLabel") then
            item:Destroy()
        end
    end
    stickToBottom = true
    isAutoScrolling = true
    LogContainer.CanvasPosition = Vector2.new(0, 0)
    isAutoScrolling = false
end

local function SafeLogUpdate()
    if LoggerQueue.processing or #LoggerQueue.messages == 0 then
        return
    end

    LoggerQueue.processing = true

    while #LoggerQueue.messages > 0 do
        local entry = table.remove(LoggerQueue.messages, 1)
        if entry then
            pcall(function()
                Logger:Log(entry.text, entry.color)
            end)
        end
    end

    LoggerQueue.processing = false
end

-- Process queue every frame on RunService (guaranteed main thread)
RunService.Heartbeat:Connect(SafeLogUpdate)

-- ==========================================
-- DEBUG GUI & NOTIFY SYSTEM
-- ==========================================
local TweenService = game:GetService("TweenService")
local TweenInf = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Palette
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

if CoreGui:FindFirstChild("MacroDebugGui") then
    CoreGui:FindFirstChild("MacroDebugGui"):Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MacroDebugGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 2000
ScreenGui.Parent = CoreGui
ScreenGui.Enabled = getgenv().Debug

local function corner(radius, parent)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
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

-- For buttons that should stay opaque at all times and only swap color on
-- hover (rather than fading to transparent when the mouse leaves).
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

-- Creates a small outline-only ring click effect
local function addClickEffect(button, effectColor)
    effectColor = effectColor or Palette.TextPrimary
    button.ClipsDescendants = true

    local existingCorner = button:FindFirstChildOfClass("UICorner")

    local Flash = Instance.new("Frame")
    Flash.Name = "ClickFlash"
    Flash.Size = UDim2.new(1, 0, 1, 0)
    Flash.BackgroundColor3 = effectColor
    Flash.BackgroundTransparency = 1
    Flash.BorderSizePixel = 0
    Flash.ZIndex = button.ZIndex + 1
    Flash.Parent = button
    if existingCorner then
        existingCorner:Clone().Parent = Flash
    end

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Flash.BackgroundTransparency = 0.7
            TweenService:Create(Flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 1
            }):Play()

            local absPos = button.AbsolutePosition
            local relX = input.Position.X - absPos.X
            local relY = input.Position.Y - absPos.Y

            local Ring = Instance.new("Frame")
            Ring.Name = "ClickRing"
            Ring.AnchorPoint = Vector2.new(0.5, 0.5)
            Ring.Position = UDim2.new(0, relX, 0, relY)
            -- Start very small (e.g., 10x10 pixels)
            Ring.Size = UDim2.new(0, 10, 0, 10)
            Ring.BackgroundTransparency = 1 -- No interior fill
            Ring.BorderSizePixel = 0
            Ring.ZIndex = button.ZIndex + 2
            Ring.Parent = button
            corner(9999, Ring)

            -- Add a stroke to make it just an outline ring
            local RingStroke = Instance.new("UIStroke")
            RingStroke.Color = effectColor
            RingStroke.Transparency = 0.3
            RingStroke.Thickness = 2
            RingStroke.Parent = Ring

            -- Adjust maxDim to control how far the ring expands (change 60 to your preferred max size)
            local maxDim = 60 
            local ringTween = TweenService:Create(Ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, maxDim, 0, maxDim),
            })
            local strokeTween = TweenService:Create(RingStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 1,
            })

            ringTween:Play()
            strokeTween:Play()

            ringTween.Completed:Connect(function()
                Ring:Destroy()
            end)
        end
    end)
end

local function addSmallClickEffect(button, effectColor, ringSize)
    effectColor = effectColor or Palette.TextPrimary
    ringSize = ringSize or 35 -- Adjust this number to make the final ring smaller or larger
    button.ClipsDescendants = true

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local absPos = button.AbsolutePosition
            local relX = input.Position.X - absPos.X
            local relY = input.Position.Y - absPos.Y

            local Ring = Instance.new("Frame")
            Ring.Name = "ClickRing"
            Ring.AnchorPoint = Vector2.new(0.5, 0.5)
            Ring.Position = UDim2.new(0, relX, 0, relY)
            Ring.Size = UDim2.new(0, 8, 0, 8) -- Starting tiny size
            Ring.BackgroundTransparency = 1 -- No interior fill
            Ring.BorderSizePixel = 0
            Ring.ZIndex = button.ZIndex + 2
            Ring.Parent = button
            corner(9999, Ring)

            local RingStroke = Instance.new("UIStroke")
            RingStroke.Color = effectColor
            RingStroke.Transparency = 0.3
            RingStroke.Thickness = 1.5
            RingStroke.Parent = Ring

            local ringTween = TweenService:Create(Ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, ringSize, 0, ringSize),
            })
            local strokeTween = TweenService:Create(RingStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 1,
            })

            ringTween:Play()
            strokeTween:Play()

            ringTween.Completed:Connect(function()
                Ring:Destroy()
            end)
        end
    end)
end


-- Restore Button
local RestoreBtn = Instance.new("TextButton")
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

-- Main Frame
local FULL_SIZE = UDim2.new(0, 400, 0, 510)
local COLLAPSED_SIZE = UDim2.new(0, 400, 0, 40)

local MainFrame = Instance.new("Frame")
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

-- Title Bar
local TitleBar = Instance.new("Frame")
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

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(0, 14, 0.5, -4)
StatusDot.BackgroundColor3 = Palette.Success
StatusDot.BorderSizePixel = 0
StatusDot.Parent = TitleBar
corner(4, StatusDot)

task.spawn(function()
    while StatusDot.Parent do
        TweenService:Create(StatusDot, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.6}):Play()
        task.wait(1)
        TweenService:Create(StatusDot, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0}):Play()
        task.wait(1)
    end
end)

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, -140, 1, 0)
Title.Position = UDim2.new(0, 30, 0, 0)
Title.Text = "Macro Debug"
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

-- Body
local Body = Instance.new("Frame")
Body.Name = "Body"
Body.Size = UDim2.new(1, -24, 1, -60)
Body.Position = UDim2.new(0, 12, 0, 50)
Body.BackgroundTransparency = 1
Body.Parent = MainFrame

-- Status card
local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, 0, 0, 62)
StatusCard.BackgroundColor3 = Palette.Panel
StatusCard.BorderSizePixel = 0
StatusCard.Parent = Body
corner(8, StatusCard)

local StatusPadding = Instance.new("UIPadding")
StatusPadding.PaddingLeft = UDim.new(0, 10)
StatusPadding.PaddingRight = UDim.new(0, 10)
StatusPadding.Parent = StatusCard

local StatusLayout = Instance.new("UIListLayout")
StatusLayout.FillDirection = Enum.FillDirection.Vertical
StatusLayout.VerticalAlignment = Enum.VerticalAlignment.Center
StatusLayout.Padding = UDim.new(0, 4)
StatusLayout.SortOrder = Enum.SortOrder.LayoutOrder
StatusLayout.Parent = StatusCard

local StepLabel = Instance.new("TextLabel")
StepLabel.Size = UDim2.new(1, 0, 0, 20)
StepLabel.LayoutOrder = 1
StepLabel.Text = "Current Step: Initializing..."
StepLabel.TextColor3 = Palette.TextPrimary
StepLabel.BackgroundTransparency = 1
StepLabel.TextXAlignment = Enum.TextXAlignment.Left
StepLabel.Font = Enum.Font.Gotham
StepLabel.TextSize = 13
StepLabel.TextTruncate = Enum.TextTruncate.AtEnd
StepLabel.Parent = StatusCard

local ReplayLabel = Instance.new("TextLabel")
ReplayLabel.Size = UDim2.new(1, 0, 0, 20)
ReplayLabel.LayoutOrder = 2
ReplayLabel.Text = "Replay: " .. (getgenv().Replay and "On" or "Off")
ReplayLabel.TextColor3 = getgenv().Replay and Palette.Success or Palette.Danger
ReplayLabel.BackgroundTransparency = 1
ReplayLabel.TextXAlignment = Enum.TextXAlignment.Left
ReplayLabel.Font = Enum.Font.Gotham
ReplayLabel.TextSize = 13
ReplayLabel.Parent = StatusCard

local LogHeader = Instance.new("TextLabel")
LogHeader.Size = UDim2.new(1, 0, 0, 18)
LogHeader.Position = UDim2.new(0, 0, 0, 70)
LogHeader.Text = "ACTIVITY LOG"
LogHeader.TextColor3 = Palette.TextSecond
LogHeader.BackgroundTransparency = 1
LogHeader.TextXAlignment = Enum.TextXAlignment.Left
LogHeader.Font = Enum.Font.GothamMedium
LogHeader.TextSize = 11
LogHeader.Parent = Body

-- Log panel assignment (one entry per log line, ported from UI.lua's Logger)
LogContainer = Instance.new("ScrollingFrame")
LogContainer.Name = "LogScroll"
LogContainer.Size = UDim2.new(1, 0, 1, -140)
LogContainer.Position = UDim2.new(0, 0, 0, 96)
LogContainer.BackgroundColor3 = Palette.Panel
LogContainer.BorderSizePixel = 0
LogContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
LogContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogContainer.ScrollingDirection = Enum.ScrollingDirection.Y
LogContainer.ScrollBarThickness = 8
LogContainer.ScrollBarImageColor3 = Palette.Accent
LogContainer.VerticalScrollBarInset = Enum.ScrollBarInset.Always
LogContainer.Parent = Body
corner(8, LogContainer)

local LogListLayout = Instance.new("UIListLayout")
LogListLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogListLayout.Padding = UDim.new(0, 2)
LogListLayout.Parent = LogContainer

local LogPadding = Instance.new("UIPadding")
LogPadding.PaddingLeft = UDim.new(0, 12)
LogPadding.PaddingRight = UDim.new(0, 20)
LogPadding.PaddingTop = UDim.new(0, 6)
LogPadding.Parent = LogContainer

-- Track whether the user is at the bottom so new entries only auto-scroll
-- when they haven't scrolled up to read something. Skips updates that were
-- caused by our own auto-scroll, so it only reacts to real user input.
LogContainer:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    if isAutoScrolling then return end
    stickToBottom = isLogScrolledToBottom()
end)

-- Footer: Clear Logs + Scroll to Bottom
local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.5, -4, 0, 34)
ClearBtn.Position = UDim2.new(0, 0, 1, -34)
ClearBtn.Text = "Clear Logs"
ClearBtn.BackgroundColor3 = Palette.PanelAlt
ClearBtn.TextColor3 = Palette.DangerLight
ClearBtn.Font = Enum.Font.GothamMedium
ClearBtn.TextSize = 13
ClearBtn.AutoButtonColor = false
ClearBtn.Parent = Body
corner(8, ClearBtn)

local ClearStroke = Instance.new("UIStroke")
ClearStroke.Color = Palette.DangerDim
ClearStroke.Transparency = 0.5
ClearStroke.Thickness = 1
ClearStroke.Parent = ClearBtn

hoverColorSwap(ClearBtn, Palette.Panel, Color3.fromRGB(48, 30, 30))
addClickEffect(ClearBtn, Palette.Danger)

local ScrollBottomBtn = Instance.new("TextButton")
ScrollBottomBtn.Size = UDim2.new(0.5, -4, 0, 34)
ScrollBottomBtn.Position = UDim2.new(0.5, 4, 1, -34)
ScrollBottomBtn.Text = "↓ Bottom"
ScrollBottomBtn.BackgroundColor3 = Palette.PanelLight
ScrollBottomBtn.TextColor3 = Palette.Accent
ScrollBottomBtn.Font = Enum.Font.GothamMedium
ScrollBottomBtn.TextSize = 13
ScrollBottomBtn.AutoButtonColor = false
ScrollBottomBtn.Parent = Body
corner(8, ScrollBottomBtn)

local ScrollBottomStroke = Instance.new("UIStroke")
ScrollBottomStroke.Color = Palette.AccentDim
ScrollBottomStroke.Transparency = 0.5
ScrollBottomStroke.Thickness = 1
ScrollBottomStroke.Parent = ScrollBottomBtn

hoverColorSwap(ScrollBottomBtn, Palette.Panel, Color3.fromRGB(45, 40, 70))
addClickEffect(ScrollBottomBtn, Palette.Accent)

-- Unload Confirmation Modal
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

local UnloadStroke = Instance.new("UIStroke")
UnloadStroke.Color = Palette.Stroke
UnloadStroke.Thickness = 1
UnloadStroke.Parent = UnloadMenu

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

-- Drag support
local UserInputService = game:GetService("UserInputService")
local dragging = false
local dragStartInput, dragStartPos

TitleBar.Active = true
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
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
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartInput
        MainFrame.Position = UDim2.new(
            dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X,
            dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y
        )
    end
end)

-- Minimize Button
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

    local targetPos = UDim2.new(
        RestoreBtn.Position.X.Scale, RestoreBtn.Position.X.Offset + RestoreBtn.Size.X.Offset / 2,
        RestoreBtn.Position.Y.Scale, RestoreBtn.Position.Y.Offset + RestoreBtn.Size.Y.Offset / 2
    )

    local minimizeTween = TweenService:Create(MainFrame, MinimizeTweenInfo, {
        Size = UDim2.new(0, 0, 0, 0),
        Position = targetPos,
        BackgroundTransparency = 1,
    })
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
    local restoreBtnHalfW = RestoreBtn.Size.X.Offset / 2
    local restoreBtnHalfH = RestoreBtn.Size.Y.Offset / 2
    local shrinkTween = TweenService:Create(RestoreBtn, MinimizeTweenInfo, {Size = UDim2.new(0, 0, 0, 0)})
    shrinkTween:Play()

    local startPos = UDim2.new(
        RestoreBtn.Position.X.Scale, RestoreBtn.Position.X.Offset + restoreBtnHalfW,
        RestoreBtn.Position.Y.Scale, RestoreBtn.Position.Y.Offset + restoreBtnHalfH
    )

    MainFrame.Visible = true
    MainFrame.Size = UDim2.new(0, 0, 0, 0)
    MainFrame.Position = startPos
    MainFrame.BackgroundTransparency = 1
    MainStroke.Transparency = 1

    TweenService:Create(MainFrame, RestoreTweenInfo, {
        Size = savedSize,
        Position = savedPosition,
        BackgroundTransparency = 0,
    }):Play()
    TweenService:Create(MainStroke, RestoreTweenInfo, {Transparency = 0}):Play()

    shrinkTween.Completed:Connect(function()
        RestoreBtn.Visible = false
        RestoreBtn.Size = UDim2.new(0, 46, 0, 46) 
        minimizeAnimating = false
    end)
end)

-- Collapse Button
local isCollapsed = false
local bodyElements = {Body}

CollapseBtn.MouseButton1Click:Connect(function()
    isCollapsed = not isCollapsed
    if isCollapsed then
        CollapseBtn.Text = ">"
        for _, element in ipairs(bodyElements) do
            element.Visible = false
        end
        TitleBarMask.Visible = false
        TweenService:Create(MainFrame, TweenInf, {Size = COLLAPSED_SIZE}):Play()
    else
        CollapseBtn.Text = "v"
        local expandTween = TweenService:Create(MainFrame, TweenInf, {Size = FULL_SIZE})
        expandTween:Play()
        expandTween.Completed:Connect(function()
            if not isCollapsed then
                for _, element in ipairs(bodyElements) do
                    element.Visible = true
                end
                TitleBarMask.Visible = true
            end
        end)
    end
end)

-- Close / Clear
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

ClearBtn.MouseButton1Click:Connect(function()
    Logger:Clear()
end)

ScrollBottomBtn.MouseButton1Click:Connect(function()
    stickToBottom = true
    scrollLogToBottom()
end)

task.spawn(function()
    while task.wait(1) do
        if not getgenv().Debug and ScreenGui then
            ScreenGui.Enabled = false
        elseif getgenv().Debug and ScreenGui then
            ScreenGui.Enabled = true
        end
        ReplayLabel.Text = "Replay: " .. (getgenv().Replay and "On" or "Off")
        ReplayLabel.TextColor3 = getgenv().Replay and Palette.Success or Palette.Danger
    end
end)

local function UpdateMacroStep(stepString)
    StepLabel.Text = "Current Step: " .. stepString
end

local function Notify(logType, message)
    local timeStamp = os.date("[%I:%M:%S %p]")
    local icon = ""
    local color = Palette.TextPrimary

    logType = string.lower(tostring(logType))

    if logType == "print" then
        icon = "[INFO]"
        color = Palette.TextPrimary
        print(message)
    elseif logType == "warn" then
        icon = "[WARN]"
        color = Palette.Warning
        warn(message)
    elseif logType == "error" then
        icon = "[ERROR]"
        color = Palette.Danger
        warn("[ERROR]: " .. message)
    else
        icon = "[INFO]"
        color = Palette.TextPrimary
        print(message)
    end

    local formattedMessage = string.format("%s %s: %s", timeStamp, icon, tostring(message))

    if #LoggerQueue.messages < LoggerQueue.maxMessages then
        table.insert(LoggerQueue.messages, {text = formattedMessage, color = color})
    end
end



if CoreGui:FindFirstChild("FpsModeOverlay") then
    CoreGui:FindFirstChild("FpsModeOverlay"):Destroy()
end
if CoreGui:FindFirstChild("FpsToggleGui") then
    CoreGui:FindFirstChild("FpsToggleGui"):Destroy()
end

local FpsToggleBtn -- forward declared; assigned when the button is created below
local FpsOverlayGui = nil -- created lazily the first time Fps mode is turned on; never destroyed after

local function ensureFpsOverlay()
    if FpsOverlayGui then return end

    FpsOverlayGui = Instance.new("ScreenGui")
    FpsOverlayGui.Name = "FpsModeOverlay"
    FpsOverlayGui.ResetOnSpawn = false
    FpsOverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    FpsOverlayGui.DisplayOrder = 999 -- below the toggle button's ScreenGui
    FpsOverlayGui.IgnoreGuiInset = true -- no gap at the top; covers the entire screen
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
end

local function setFpsMode(state)
    getgenv().Fps = state

    local ok, err = pcall(function()
        RunService:Set3dRenderingEnabled(not state)
    end)
    if not ok then
        Notify("Warn", "[FPS Mode] Set3dRenderingEnabled unavailable on this executor: " .. tostring(err))
    end

    if state then
        ensureFpsOverlay()
        FpsOverlayGui.Enabled = true
    elseif FpsOverlayGui then
        FpsOverlayGui.Enabled = false
    end

    if FpsToggleBtn then
        FpsToggleBtn.Text = state and "FPS: ON" or "FPS: OFF"
        FpsToggleBtn.TextColor3 = state and Palette.Success or Palette.TextSecond
    end

    Notify("Print", "[FPS Mode] " .. (state and "Enabled" or "Disabled"))
end

-- Own ScreenGui so this button survives even if MacroDebugGui is unloaded
local FpsButtonGui = Instance.new("ScreenGui")
FpsButtonGui.Name = "FpsToggleGui"
FpsButtonGui.ResetOnSpawn = false
FpsButtonGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
FpsButtonGui.DisplayOrder = 1000 -- always above the overlay
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
addSmallClickEffect(FpsToggleBtn, Palette.Accent, 12)

FpsToggleBtn.MouseButton1Click:Connect(function()
    setFpsMode(not getgenv().Fps)
end)
if getgenv().Fps == true then
    setFpsMode(getgenv().Fps)
end


local function updateHotbarTowers()
    table.clear(hotbarTowerIDs)
    local hBar = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("HUD"):WaitForChild("Toolbox"):WaitForChild("Hotbar")
    
    for _, Slot in ipairs(hBar:GetChildren()) do
        if Slot:IsA("Frame") then
            local towerID = Slot.Name:match("^%d+:(.+)$")
            local slotIndex = Slot.LayoutOrder
            
            if towerID and slotIndex >= 1 and slotIndex <= 6 then
                hotbarTowerIDs[slotIndex] = towerID
                Notify("Print", string.format("[Hotbar Loaded] Slot %d -> TowerID %s", slotIndex, towerID))
            end
        end
    end
end

task.spawn(function()
    Notify("Print", "[Init] Waiting for TowerPlacedSuccessfully remote to exist...")
    
    local Event
    local maxWait = 0
    
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
        Notify("Print", "[Init] TowerPlacedSuccessfully remote found! Setting up interception...")
        
        local lastPlacedTower = nil
        local lastPlaceTime = 0
        
        for _, Connection in getconnections(Event.OnClientEvent) do
            local old; old = hookfunction(Connection.Function, function(unitID, towerID, ...)
                local currentTime = tick()
                local key = tostring(unitID) .. ":" .. tostring(towerID)
                
                if lastPlacedTower == key and (currentTime - lastPlaceTime) < 0.5 then
                    Notify("Warn", string.format("[Tower] Duplicate detected (unitID=%s, towerID=%s) - skipping", tostring(unitID), tostring(towerID)))
                    return old(unitID, towerID, ...)
                end
                
                currentTowerIndex = currentTowerIndex + 1
                
                local towerData = {
                    towerIndex = currentTowerIndex,
                    unitID = tostring(unitID),
                    towerID = tostring(towerID)
                }
                
                table.insert(placedTowers, towerData)
                Notify("Print", string.format("[Tower Registered] Index: %d | UnitID: %s | TowerID: %s", currentTowerIndex, tostring(unitID), tostring(towerID)))
                
                lastPlacedTower = key
                lastPlaceTime = currentTime
                
                return old(unitID, towerID, ...)
            end)
        end
        
        Notify("Print", "[Init] Checking for pre-existing towers...")
        for _, tower in ipairs(towerFolder:GetChildren()) do
            currentTowerIndex = currentTowerIndex + 1
            local towerData = {
                towerIndex = currentTowerIndex,
                unitID = tostring(tower.Name),
                towerID = "pre-existing"
            }
            table.insert(placedTowers, towerData)
            Notify("Print", string.format("[Tower Registered - Pre-existing] Index: %d | UnitID: %s", currentTowerIndex, tostring(tower.Name)))
        end
        
    else
        Notify("Error", "[Warning] TowerPlacedSuccessfully remote was not created within timeout. Will rely on tower folder detection.")
    end
end)

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
    Notify("Print", "Clicked: " .. tostring(ClickOnPart))
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

function placeUnit(slotNumber, pos, waittime, rotation)
    rotation = rotation or 0
    local towerID = hotbarTowerIDs[slotNumber]
    
    if not towerID then
        Notify("Error", "[Error] No tower found in Hotbar Slot " .. tostring(slotNumber))
        return
    end

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
        remote:FireServer(towerData.unitID)
    end
    
    task.wait(waittime or 1)
    if pathSelection then
        Notify("Print", string.format("[Upgrade] Tower Index: %d | UnitID: %s | Path: %d", towerIndex, towerData.unitID, pathSelection))
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
    else
        Notify("Print", string.format("[Upgrade] Tower Index: %d | UnitID: %s | No Path Specified", towerIndex, towerData.unitID))
    end
end

function sellUnit(towerIndex, waittime)
    local towerData = getTowerByIndex(towerIndex)
    if not towerData then return end
    local Event = game:GetService("ReplicatedStorage").GenericModules.Service.Network.PlayerSellTower
    Event:FireServer(tostring(towerData.UnitID))
    task.wait(waittime or 1)
end

function targetUnit(towerIndex, targeting, waittime)
    local towerData = getTowerByIndex(towerIndex)
    if not towerData then return end

    local args = {
        [1] = tostring(towerData.unitID),
        [2] = tostring(targeting)
    }
    
    ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GlobalInit"):WaitForChild("RemoteEvents"):WaitForChild("PlayerSetTowerTargetMode"):FireServer(unpack(args))
    task.wait(waittime or 1)
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
    if activeAutoAbilities[towerIndex] then return end
    activeAutoAbilities[towerIndex] = true

    task.spawn(function()
        while activeAutoAbilities[towerIndex] and getgenv().Ability == true do
            local towerData = getTowerByIndex(towerIndex)
            if towerData then
                useTowerAbility(towerIndex, interval or 1)
            else
                task.wait(1) 
            end
        end
        -- Always clear the flag here, whatever caused the loop to exit
        -- (Ability toggled off, tower gone, or an explicit stop). Without
        -- this, a leftover `true` blocks autoTowerAbility from ever
        -- restarting this tower on the next match.
        activeAutoAbilities[towerIndex] = false
        Notify("Print", string.format("[AutoAbility] Loop ended for Tower Index: %d", towerIndex))
    end)
end

function stopAutoTowerAbility(towerIndex)
    if activeAutoAbilities[towerIndex] then
        activeAutoAbilities[towerIndex] = false
        Notify("Warn", string.format("[AutoAbility] Stopping auto ability for Tower Index: %d", towerIndex))
    end
end

function ragnaOnLastBoss(towerIndex)
    local enemiesFolder = workspace:WaitForChild("EntityModels"):WaitForChild("Enemies")
    Notify("Print", "[Ragna Logic] Wave 25 detected. Waiting for final boss (1 enemy remaining)...")
    local bossgui = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("BossGui")
    local Bossbar = bossgui.Bar
    repeat task.wait() until bossgui.Enabled == true
    Notify("Print", "[Ragna Logic] Boss GUI detected. Monitoring for final boss...")
    repeat task.wait() until Bossbar.Visible == true
    Notify("Print", "[Ragna Logic] Boss bar detected. Monitoring for final boss...")
    repeat task.wait(0.5) until #enemiesFolder:GetChildren() == 1
    Notify("Print", "[Ragna Logic] Final boss detected. Monitoring position and health...")
    local lastBoss = enemiesFolder:GetChildren()[1]
    Notify("Print", "[Ragna Logic] Last boss detected: " .. lastBoss.Name)

    local DETECT_RADIUS = 55 

    while true do
        task.wait(0.2)

        local towerData = getTowerByIndex(towerIndex)
        if towerData and lastBoss and lastBoss.Parent and lastBoss:FindFirstChild("HumanoidRootPart") then
            local ragnaModel = workspace.EntityModels.Towers:FindFirstChild(towerData.unitID)

            if ragnaModel and ragnaModel:FindFirstChild("HumanoidRootPart") then
                local rPos = ragnaModel.HumanoidRootPart.Position
                local eHRP = lastBoss.HumanoidRootPart
                local ePos = eHRP.Position

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
                            if healthFill.BackgroundColor3 == Color3.fromRGB(115, 0, 255) then
                                Notify("Warn", "[Ragna Logic] Boss in range with purple health bar! Activating ability...")
                                useTowerAbility(towerIndex, 0.5)
                            end
                        end
                    end
                end
            end
        else
            if not lastBoss or not lastBoss.Parent then
                Notify("Print", "[Ragna Logic] Boss defeated or despawned.")
                break
            end
        end
    end
end

function replayMatch()
    UpdateMacroStep("Replaying Match")
    Notify("Print", "==================================================")
    Notify("Print", "[REPLAY Match] Main match function started!")
    Notify("Print", "==================================================")
    
    updateHotbarTowers() 

    local waveLabel = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("Wave"):WaitForChild("WaveIndex")
    local endGui = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("RoundOver")
    
    local matchConnections = {}

    local function onRoundOver()
        if endGui.Visible == true then
            UpdateMacroStep("Match Ended - Cleaning up")
            Notify("Print", "[Match Ended] RoundOver UI detected. Stopping loops and cleaning up...")
            getgenv().Ability = false
            
            for _, conn in ipairs(matchConnections) do
                if conn.Connected then
                    conn:Disconnect()
                end
            end
            table.clear(matchConnections)

            if getgenv().Replay == true then
                UpdateMacroStep("Voting Replay")
                Notify("Print", "[Match Ended] Replay is enabled. Voting for replay...")
                if endGui.Continue.Visible == true then
                    Notify("Print", "Voting Replay")
                    ReplicatedStorage:WaitForChild("Modules")
                    :WaitForChild("GlobalInit"):WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReplay"):FireServer()
                elseif endGui.Continue.Visible == false then
                    Notify("Warn", "[Replay] Continue button not visible. Returning To Lobby.")
                    game:GetService("ReplicatedStorage")
                    :WaitForChild("Modules")
                    :WaitForChild("GlobalInit")
                    :WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReturn"):FireServer()
                end
                repeat task.wait(0.5) until endGui.Visible == false

                UpdateMacroStep("Waiting for Data Clear")
                Notify("Print", "[Replay] Waiting for server to clear old match data...")
                repeat task.wait(0.5) until #towerFolder:GetChildren() == 0

                task.wait(3)
                
                table.clear(placedTowers)
                currentTowerIndex = 0
                
                Notify("Print", "[Replay] Starting new match sequence...")
                replayMatch()
                
            else
                Notify("Print", "[Match Ended] Waiting to lobby...")
            end
        end
    end

    table.insert(matchConnections, endGui:GetPropertyChangedSignal("Visible"):Connect(onRoundOver))
    onRoundOver()

    local function wv1()
        UpdateMacroStep("Wave 1 Routine")
        --Notify("Print", "[Wave Action] >>> EXECUTING WAVE 1 FUNCTION <<<")
        spd()
        startMatch()
        placeUnit(4, Vector3.new(-1170.2559814453, 135.236328125, -1688.1260986328), 1) 
        placeUnit(6, Vector3.new(-1288.8853759766, 144.26679992676, -1668.8966064453), 1)
        task.wait(1)
        placeUnit(1, Vector3.new(-1177.3988037109, 136.49728393555, -1315.2202148438), 0)-- -1177.3988037109, 136.49728393555, -1315.2202148438
        getgenv().Ability = true
        autoTowerAbility(3, 1) 
        task.wait()
        autoTowerAbility(2, 1)
        task.wait()
        placeUnit(3, Vector3.new(-1166.2114257812, 135.05136108398, -1308.1571044922), 1)---1166.2114257812, 135.05136108398, -1308.1571044922
        --Notify("Print", "[Wave Action] >>> WAVE 1 COMPLETED <<<")
        placeUnit(5, Vector3.new(-1504.6909179688, 138.24360656738, -1344.4370117188), 1)
        print("should've ulq")
    end
    local function wv5()
        UpdateMacroStep("Wave 10 Routine")
        --Notify("Print", "[Wave Action] >>> EXECUTING WAVE 10 FUNCTION <<<")
        placeUnit(5, Vector3.new(-1504.6909179688, 138.24360656738, -1344.4370117188), 1)
        upgradeUnit(5, 1, 1) 
        task.wait(2)
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
        if getgenv().Aizen == true then
            placeUnit(2, Vector3.new(-1237.7738037109, 143.60464477539, -1682.4620361328), 1) 
        else
            placeUnit(2, Vector3.new(-1175.7613525391, 135.85260009766, -1681.7412109375), 1)
            upgradeUnit(6, 2, 1) 
            autoTowerAbility(6, 1) 
            task.wait(1)
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
        end
        --Notify("Print", "[Wave Action] >>> WAVE 10 COMPLETED <<<")
    end

    local function wv15()
        UpdateMacroStep("Wave 15 Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 15 FUNCTION <<<")
        task.wait(1)
        if getgenv().Aizen == true then
            autoTowerAbility(6, 1)
        end
        autoTowerAbility(6, 1)
        task.wait(1)
        --Notify("Print", "[Wave Action] >>> WAVE 15 COMPLETED <<<")
    end

    local function wv20()
        UpdateMacroStep("Wave 25 (Boss) Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 25 FUNCTION <<<")
        task.wait(5)
        task.spawn(function()
            --Notify("Print", "[Wave Action] >>> Ragna on Last Boss Logic Initiated <<<")
            ragnaOnLastBoss(5)
        end)
    end

    local waveActions = {
        [1] = wv1,
        [5] = wv5,
        [15] = wv15,
        [20] = wv20,
    }

    local firedWaves = {}

    local function checkCurrentWave()
        local rawText = tostring(waveLabel.Text)
        local currentWave = tonumber(rawText:match("(%d+)%s*/"))

        if currentWave and waveActions[currentWave] and not firedWaves[currentWave] then
            Notify("Print", string.format("[Wave Check] Match found for Wave %d! Triggering action...", currentWave))
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
    UpdateMacroStep("Starting Summer Match")
    Notify("Print", "==================================================")
    Notify("Print", "[SummerMatch] Main match function started!")
    Notify("Print", "==================================================")
    
    updateHotbarTowers()

    local waveLabel = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("Wave"):WaitForChild("WaveIndex")
    local endGui = LocalPlayer.PlayerGui:WaitForChild("MainGui"):WaitForChild("MainFrames"):WaitForChild("RoundOver")
    
    local matchConnections = {}

    local function onRoundOver()
        if endGui.Visible == true then
            UpdateMacroStep("Match Ended - Cleaning up")
            Notify("Print", "[Match Ended] RoundOver UI detected. Stopping loops and cleaning up...")
            getgenv().Ability = false
            
            for _, conn in ipairs(matchConnections) do
                if conn.Connected then
                    conn:Disconnect()
                end
            end
            table.clear(matchConnections)

            if getgenv().Replay == true then
                UpdateMacroStep("Voting Replay")
                Notify("Print", "[Match Ended] Replay is enabled. Voting for replay...")
                if endGui.Continue.Visible == true then
                    Notify("Print", "Voting Replay")
                    ReplicatedStorage:WaitForChild("Modules")
                    :WaitForChild("GlobalInit"):WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReplay"):FireServer()
                elseif endGui.Continue.Visible == false then
                    Notify("Warn", "[Replay] Continue button not visible. Returning To Lobby.")
                    game:GetService("ReplicatedStorage")
                    :WaitForChild("Modules")
                    :WaitForChild("GlobalInit")
                    :WaitForChild("RemoteEvents")
                    :WaitForChild("PlayerVoteReturn"):FireServer()
                end
                
                repeat task.wait(0.5) until endGui.Visible == false

                UpdateMacroStep("Waiting for Data Clear")
                Notify("Print", "[Replay] Waiting for server to clear old match data...")
                repeat task.wait(0.5) until #towerFolder:GetChildren() == 0

                task.wait(3)
                
                table.clear(placedTowers)
                currentTowerIndex = 0
                
                Notify("Print", "[Replay] Starting new match sequence...")
                replayMatch()
            else
                Notify("Print", "[Match Ended] Waiting to lobby...")
            end
        end
    end

    table.insert(matchConnections, endGui:GetPropertyChangedSignal("Visible"):Connect(onRoundOver))
    onRoundOver()

    spd()
    placeUnit(4, Vector3.new(-1173.5047607422, 135.64385986328, -1687.5249023438), 1) 
    placeUnit(6, Vector3.new(-1307.4481201172, 144.26693725586, -1684.2392578125), 1)
    startMatch()

    local function wv1()
        UpdateMacroStep("Wave 1 Routine")
        --Notify("Print", "[Wave Action] >>> EXECUTING WAVE 1 FUNCTION <<<")
        placeUnit(1, Vector3.new(-1177.3988037109, 136.49728393555, -1315.2202148438), 0)-- -1177.3988037109, 136.49728393555, -1315.2202148438
        getgenv().Ability = true
        autoTowerAbility(3, 1) 
        task.wait()
        autoTowerAbility(2, 1)
        task.wait()
        placeUnit(3, Vector3.new(-1166.2114257812, 135.05136108398, -1308.1571044922), 1)---1166.2114257812, 135.05136108398, -1308.1571044922
        --Notify("Print", "[Wave Action] >>> WAVE 1 COMPLETED <<<")
        placeUnit(5, Vector3.new(-1504.6909179688, 138.24360656738, -1344.4370117188), 1)
        print("should've ulq")
    end
    
    local function wv5()
        UpdateMacroStep("Wave 10 Routine")
        --Notify("Print", "[Wave Action] >>> EXECUTING WAVE 10 FUNCTION <<<")
        placeUnit(5, Vector3.new(-1504.6909179688, 138.24360656738, -1344.4370117188), 1)
        upgradeUnit(5, 1, 1) 
        task.wait(2)
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
        game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
        if getgenv().Aizen == true then
            placeUnit(2, Vector3.new(-1237.7738037109, 143.60464477539, -1682.4620361328), 1) 
        else
            placeUnit(2, Vector3.new(-1175.7613525391, 135.85260009766, -1681.7412109375), 1)
            upgradeUnit(6, 2, 1) 
            autoTowerAbility(6, 1) 
            task.wait(1)
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.HUD.Visible = true
            game:GetService("Players").LocalPlayer.PlayerGui.MainGui.UpgradePathSelection.Visible = false
        end
        --Notify("Print", "[Wave Action] >>> WAVE 10 COMPLETED <<<")
    end

    local function wv15()
        UpdateMacroStep("Wave 15 Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 15 FUNCTION <<<")
        task.wait(1)
        if getgenv().Aizen == true then
            autoTowerAbility(6, 1) 
        end
        autoTowerAbility(6, 1)
        task.wait(1)
        --Notify("Print", "[Wave Action] >>> WAVE 15 COMPLETED <<<")
    end

    local function wv20()
        UpdateMacroStep("Wave 25 (Boss) Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 25 FUNCTION <<<")
        task.wait(5)
        task.spawn(function()
            --Notify("Print", "[Wave Action] >>> Ragna on Last Boss Logic Initiated <<<")
            ragnaOnLastBoss(5)
        end)
    end

    local waveActions = {
        [1] = wv1,
        [5] = wv5,
        [15] = wv15,
        [20] = wv20,
    }

    local firedWaves = {}

    local function checkCurrentWave()
        local rawText = tostring(waveLabel.Text)
        local currentWave = tonumber(rawText:match("(%d+)%s*/"))

        if currentWave and waveActions[currentWave] and not firedWaves[currentWave] then
            Notify("Print", string.format("[Wave Check] Match found for Wave %d! Triggering action...", currentWave))
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
