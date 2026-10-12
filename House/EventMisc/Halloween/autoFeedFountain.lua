-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

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

-- State
local looping = false
local running = true
local connections = {}

-- Main ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CandyFeedGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Main Frame (draggable container)
local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = UDim2.new(0, 180, 0, 130)
frame.Position = UDim2.new(0.05, 0, 0.1, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = frame

-- Title Bar (drag handle)
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
titleLabel.Size = UDim2.new(1, 0, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "Candy Loop"
titleLabel.Parent = titleBar

-- Toggle Button
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.new(1, -20, 0, 40)
toggleButton.Position = UDim2.new(0, 10, 0, 38)
toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 16
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Text = "Feed Loop: OFF"
toggleButton.Parent = frame

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

-- Unload Button
local unloadButton = Instance.new("TextButton")
unloadButton.Name = "UnloadButton"
unloadButton.Size = UDim2.new(1, -20, 0, 30)
unloadButton.Position = UDim2.new(0, 10, 0, 88)
unloadButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
unloadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadButton.TextSize = 14
unloadButton.Font = Enum.Font.GothamBold
unloadButton.Text = "Unload"
unloadButton.Parent = frame

local unloadCorner = Instance.new("UICorner")
unloadCorner.CornerRadius = UDim.new(0, 8)
unloadCorner.Parent = unloadButton

-- Dragging Logic
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

-- Toggle Logic
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

-- Loop
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

-- Unload: stop loop, disconnect listeners, delete GUI
unloadButton.MouseButton1Click:Connect(function()
    running = false
    looping = false
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    table.clear(connections)
    screenGui:Destroy()
end)
