if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(4)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")

local towerFolder = game.Workspace:WaitForChild("EntityModels"):WaitForChild("Towers")

local placedTowers = {}
local hotbarTowerIDs = {}
local activeAutoAbilities = {}
local currentTowerIndex = 0

-- Global Toggles
getgenv().Ability = false
getgenv().Replay = true
getgenv().Fps = false
getgenv().Debug = true
getgenv().Aizen = false

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
    Stroke       = Color3.fromRGB(45, 45, 58),
    Accent       = Color3.fromRGB(124, 108, 255),
    AccentDim    = Color3.fromRGB(90, 79, 191),
    TextPrimary  = Color3.fromRGB(238, 238, 245),
    TextSecond   = Color3.fromRGB(150, 150, 165),
    Success      = Color3.fromRGB(88, 217, 168),
    Danger       = Color3.fromRGB(235, 95, 95),
    DangerDim    = Color3.fromRGB(190, 70, 70),
}

if CoreGui:FindFirstChild("MacroDebugGui") then
    CoreGui:FindFirstChild("MacroDebugGui"):Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MacroDebugGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui
ScreenGui.Enabled = getgenv().Debug

-- Small helper: rounded corner
local function corner(radius, parent)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

-- Small helper: hover highlight for icon buttons
local function hoverHighlight(button, hoverColor)
    button.BackgroundTransparency = 1
    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundTransparency = 0, BackgroundColor3 = hoverColor}):Play()
    end)
    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
    end)
end

-- ==========================================
-- Restore Button (floating, shown when minimized)
-- ==========================================
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

-- ==========================================
-- Main Frame
-- ==========================================
local FULL_SIZE = UDim2.new(0, 400, 0, 510)
local COLLAPSED_SIZE = UDim2.new(0, 400, 0, 40)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainWindow"
MainFrame.Size = FULL_SIZE
MainFrame.Position = UDim2.new(1, -420, 0.5, -250) -- Right side of screen
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

-- Square off the bottom corners of the title bar so it reads as one solid bar
local TitleBarMask = Instance.new("Frame")
TitleBarMask.BackgroundColor3 = Palette.Panel
TitleBarMask.BorderSizePixel = 0
TitleBarMask.Size = UDim2.new(1, 0, 0, 10)
TitleBarMask.Position = UDim2.new(0, 0, 1, -10)
TitleBarMask.Parent = TitleBar

-- Pulsing status dot
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

-- Window Controls (top right, sized to sit neatly inside the bar)
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

local CollapseBtn = makeIconButton("v", 2)
hoverHighlight(CollapseBtn, Palette.PanelAlt)

local CloseBtn = makeIconButton("X", 3)
CloseBtn.TextColor3 = Palette.Danger
hoverHighlight(CloseBtn, Color3.fromRGB(60, 32, 32))

-- ==========================================
-- Body
-- ==========================================
local Body = Instance.new("Frame")
Body.Name = "Body"
Body.Size = UDim2.new(1, -24, 1, -60)
Body.Position = UDim2.new(0, 12, 0, 50)
Body.BackgroundTransparency = 1
Body.Parent = MainFrame

-- Status card (Step + Replay)
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

-- Log section header
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

-- Log panel
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Name = "LogScroll"
ScrollFrame.Size = UDim2.new(1, 0, 1, -140)
ScrollFrame.Position = UDim2.new(0, 0, 0, 96)
ScrollFrame.BackgroundColor3 = Palette.Panel
ScrollFrame.BorderSizePixel = 0
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
ScrollFrame.ScrollBarThickness = 8
ScrollFrame.ScrollBarImageColor3 = Palette.Accent
ScrollFrame.VerticalScrollBarInset = Enum.ScrollBarInset.Always
ScrollFrame.Parent = Body
corner(8, ScrollFrame)

-- NOTE: deliberately NOT using UIPadding on the ScrollingFrame itself.
-- UIPadding there fights with AutomaticCanvasSize's overflow measurement.
-- Padding is instead baked directly into LogLabel's own Size/Position,
-- leaving clear space on the right for the scrollbar track.
local LogLabel = Instance.new("TextLabel")
LogLabel.Name = "LogText"
LogLabel.Size = UDim2.new(1, -32, 0, 0)
LogLabel.Position = UDim2.new(0, 12, 0, 6)
LogLabel.AutomaticSize = Enum.AutomaticSize.Y
LogLabel.BackgroundTransparency = 1
LogLabel.TextColor3 = Palette.TextPrimary
LogLabel.TextXAlignment = Enum.TextXAlignment.Left
LogLabel.TextYAlignment = Enum.TextYAlignment.Top
LogLabel.Text = ""
LogLabel.Font = Enum.Font.Code
LogLabel.TextSize = 12
LogLabel.TextWrapped = true
LogLabel.Parent = ScrollFrame

-- Keep a reference under the old name so the rest of the script (Notify,
-- ClearBtn, etc.) doesn't need to change how it reads/writes log text.
local LogBox = LogLabel

-- AutomaticCanvasSize isn't reliably supported by every exploit client, and
-- when it silently no-ops the CanvasSize stays (0,0,0,0) forever, which is
-- why the scrollbar never showed up in-game. Compute it manually instead,
-- driven directly off the label's own AbsoluteSize so it always works.
local function updateCanvasSize()
    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, LogLabel.AbsoluteSize.Y + 12)
end
LogLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvasSize)
updateCanvasSize()

-- Footer: Clear Logs
local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(1, 0, 0, 34)
ClearBtn.Position = UDim2.new(0, 0, 1, -34)
ClearBtn.Text = "Clear Logs"
ClearBtn.BackgroundColor3 = Palette.PanelAlt
ClearBtn.TextColor3 = Palette.Danger
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

hoverHighlight(ClearBtn, Palette.PanelAlt)
ClearBtn.BackgroundTransparency = 0 -- keep footer visible at rest (override hover default)
ClearBtn.MouseEnter:Connect(function()
    TweenService:Create(ClearBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(48, 30, 30)}):Play()
end)
ClearBtn.MouseLeave:Connect(function()
    TweenService:Create(ClearBtn, TweenInfo.new(0.15), {BackgroundColor3 = Palette.PanelAlt}):Play()
end)

-- ==========================================
-- Unload Confirmation Modal
-- ==========================================
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
UnloadMenu.Size = UDim2.new(0, 0, 0, 0) -- Starts scaled to 0 for tween
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

-- ==========================================
-- Drag support (move the window by its title bar)
-- ==========================================
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

-- ==========================================
-- BUTTON LOGIC & TWEENS
-- ==========================================

-- Minimize Button (shrinks the window down into the floating restore button, then hides it)
local MinimizeTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local RestoreTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local savedPosition = MainFrame.Position
local savedSize = MainFrame.Size
local minimizeAnimating = false

MinimizeBtn.MouseButton1Click:Connect(function()
    if minimizeAnimating then return end
    minimizeAnimating = true

    -- Remember where the window currently is/was sized (it may have been dragged or collapsed)
    savedPosition = MainFrame.Position
    savedSize = MainFrame.Size

    -- Shrink toward the center of the floating restore button
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

        -- Reset the frame back to its real size/position/opacity so it's ready to be restored
        MainFrame.Size = savedSize
        MainFrame.Position = savedPosition
        MainFrame.BackgroundTransparency = 0
        MainStroke.Transparency = 0

        -- Pop the restore button in
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

    -- Grow back out from the restore button's position
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
        RestoreBtn.Size = UDim2.new(0, 46, 0, 46) -- reset so it's ready for next minimize
        minimizeAnimating = false
    end)
end)

-- Collapse Button
-- MainFrame uses the default AnchorPoint (0, 0), so its Position is always
-- its TOP-left corner and only tweening Size means the frame collapses
-- downward from a fixed top edge, leaving only the title bar visible.
local isCollapsed = false
local bodyElements = {Body}

CollapseBtn.MouseButton1Click:Connect(function()
    isCollapsed = not isCollapsed
    if isCollapsed then
        CollapseBtn.Text = ">"
        for _, element in ipairs(bodyElements) do
            element.Visible = false
        end
        -- With no body left below it, the mask would otherwise square off
        -- MainFrame's own bottom corners instead of just the title bar's.
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

-- Close Button (X) - Open unload confirmation
CloseBtn.MouseButton1Click:Connect(function()
    Overlay.Visible = true
    UnloadMenu.Visible = true
    TweenService:Create(Overlay, TweenInf, {BackgroundTransparency = 0.4}):Play()
    TweenService:Create(UnloadMenu, TweenInf, {Size = UDim2.new(0, 246, 0, 118)}):Play()
end)

-- Cancel Close
CancelBtn.MouseButton1Click:Connect(function()
    TweenService:Create(Overlay, TweenInf, {BackgroundTransparency = 1}):Play()
    local tween = TweenService:Create(UnloadMenu, TweenInf, {Size = UDim2.new(0, 0, 0, 0)})
    tween:Play()
    tween.Completed:Wait()
    UnloadMenu.Visible = false
    Overlay.Visible = false
end)

-- Confirm Close
ConfirmBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
    getgenv().Debug = false
end)

ClearBtn.MouseButton1Click:Connect(function()
    LogBox.Text = ""
end)

-- Background loop to check toggle status
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

    logType = string.lower(tostring(logType))

    if logType == "print" then
        icon = "[INFO]"
        print(message)
    elseif logType == "warn" then
        icon = "[WARN]"
        warn(message)
    elseif logType == "error" then
        icon = "[ERROR]"
        warn("[ERROR]: " .. message)
    else
        icon = "[INFO]"
        print(message)
    end

    local formattedMessage = string.format("%s %s: %s", timeStamp, icon, tostring(message))

    if LogBox.Text == "" then
        LogBox.Text = formattedMessage
    else
        LogBox.Text = LogBox.Text .. "\n" .. formattedMessage
    end

    ScrollFrame.CanvasPosition = Vector2.new(0, 999999)
end
-- ==========================================


-- Function to dynamically fetch tower IDs from the Hotbar
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

-- Non-blocking asynchronous listener for tower placement confirmations
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
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 1 FUNCTION <<<")
        spd()
        startMatch()
        placeUnit(4, Vector3.new(-1170.2559814453, 135.236328125, -1688.1260986328), 1) 
        placeUnit(6, Vector3.new(-1288.8853759766, 144.26679992676, -1668.8966064453), 1)
        task.wait(1)
        placeUnit(1, Vector3.new(-1507.9349365234, 134.66094970703, -1313.7093505859), 0)
        getgenv().Ability = true
        autoTowerAbility(3, 1) 
        task.wait()
        autoTowerAbility(2, 1)
        task.wait()
        placeUnit(3, Vector3.new(-1508.0070800781, 137.1851348877, -1335.5341796875), 1)
        Notify("Print", "[Wave Action] >>> WAVE 1 COMPLETED <<<")
    end
    
    local function wv10()
        UpdateMacroStep("Wave 10 Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 10 FUNCTION <<<")
        placeUnit(5, Vector3.new(-1189.3095703125, 137.37525939941, -1681.1402587891), 1)
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
        Notify("Print", "[Wave Action] >>> WAVE 10 COMPLETED <<<")
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
        Notify("Print", "[Wave Action] >>> WAVE 15 COMPLETED <<<")
    end

    local function wv25()
        UpdateMacroStep("Wave 25 (Boss) Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 25 FUNCTION <<<")
        task.wait(5)
        task.spawn(function()
            Notify("Print", "[Wave Action] >>> Ragna on Last Boss Logic Initiated <<<")
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
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 1 FUNCTION <<<")
        placeUnit(1, Vector3.new(-1507.9349365234, 134.66094970703, -1313.7093505859), 0)
        getgenv().Ability = true
        autoTowerAbility(3, 1) 
        task.wait()
        autoTowerAbility(2, 1)
        task.wait()
        placeUnit(3, Vector3.new(-1508.0070800781, 137.1851348877, -1335.5341796875), 1)
        Notify("Print", "[Wave Action] >>> WAVE 1 COMPLETED <<<")
    end
    
    local function wv10()
        UpdateMacroStep("Wave 10 Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 10 FUNCTION <<<")
        getgenv().Aizen = false

        placeUnit(5, Vector3.new(-1189.3095703125, 137.37525939941, -1681.1402587891), 1)
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
        Notify("Print", "[Wave Action] >>> WAVE 10 COMPLETED <<<")
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
        Notify("Print", "[Wave Action] >>> WAVE 15 COMPLETED <<<")
    end

    local function wv25()
        UpdateMacroStep("Wave 25 (Boss) Routine")
        Notify("Print", "[Wave Action] >>> EXECUTING WAVE 25 FUNCTION <<<")
        task.wait(5)
        task.spawn(function()
            Notify("Print", "[Wave Action] >>> Ragna on Last Boss Logic Initiated <<<")
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
