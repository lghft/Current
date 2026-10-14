local HttpService = game:GetService("HttpService")
local workspace_service = game:GetService("Workspace")
local players = game:GetService("Players")
local player = players.LocalPlayer
local player_gui = player:WaitForChild("PlayerGui")
local user_input_service = game:GetService("UserInputService")
local mouse = player:GetMouse()

local file_name = "captured_macro.json"
local recordedActions = {}
local matchStartTime = os.clock()
_G.record_strat = false

local placedTowersCount = 0
local activeTowerMap = {} -- Maps server tower ID -> Sequential Index
local lastMouseHit = nil

-- Track mouse hit position continuously for placement snapping
mouse.Button1Down:Connect(function()
    if mouse.Target then
        lastMouseHit = mouse.Hit
    end
end)

-- Dynamic & Robust Wave Tracking Function
local function getCurrentWave()
    local success, wave = pcall(function()
        for _, descendant in ipairs(player_gui:GetDescendants()) do
            if descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
                local text = descendant.Text
                if text and text ~= "" then
                    local lowerText = text:lower()
                    if lowerText:find("wave") or descendant.Name:lower():find("wave") then
                        return text
                    end
                end
            end
        end
        return "1"
    end)
    return success and wave or "1"
end

-- Create ScreenGui
local screen_gui = Instance.new("ScreenGui")
screen_gui.Name = "strat_recorder_ui"
screen_gui.ResetOnSpawn = false
screen_gui.Parent = player_gui

-- Main Frame
local main_frame = Instance.new("Frame", screen_gui)
main_frame.Name = "main_frame"
main_frame.Size = UDim2.new(0, 300, 0, 400)
main_frame.Position = UDim2.new(0.35, 0, 0.3, 0)
main_frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
main_frame.Active = true
main_frame.Draggable = true

local ui_corner = Instance.new("UICorner", main_frame)
ui_corner.CornerRadius = UDim.new(0, 8)

-- Resizer
local resizer_frame = Instance.new("Frame", main_frame)
resizer_frame.Name = "resizer_frame"
resizer_frame.Size = UDim2.new(0, 20, 0, 20)
resizer_frame.Position = UDim2.new(1, -20, 1, -20)
resizer_frame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
resizer_frame.BackgroundTransparency = 0.5
local resizer_corner = Instance.new("UICorner", resizer_frame)
resizer_corner.CornerRadius = UDim.new(1, 0)

local is_resizing = false
resizer_frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        is_resizing = true
    end
end)

user_input_service.InputChanged:Connect(function(input)
    if is_resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local mouse_pos = input.Position
        local frame_pos = main_frame.AbsolutePosition
        local new_size_x = mouse_pos.X - frame_pos.X
        local new_size_y = mouse_pos.Y - frame_pos.Y
        main_frame.Size = UDim2.new(0, math.max(200, new_size_x), 0, math.max(150, new_size_y))
    end
end)

user_input_service.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        is_resizing = false
    end
end)

-- Title
local title_label = Instance.new("TextLabel", main_frame)
title_label.Name = "title_label"
title_label.Size = UDim2.new(1, -50, 0, 30)
title_label.Position = UDim2.new(0, 10, 0, 5)
title_label.Text = "Macro JSON Recorder"
title_label.TextColor3 = Color3.new(1, 1, 1)
title_label.BackgroundTransparency = 1
title_label.Font = Enum.Font.GothamBold
title_label.TextSize = 16
title_label.TextXAlignment = Enum.TextXAlignment.Left

-- Close Button
local close_btn = Instance.new("TextButton", main_frame)
close_btn.Name = "close_btn"
close_btn.Size = UDim2.new(0, 30, 0, 30)
close_btn.Position = UDim2.new(1, -35, 0, 5)
close_btn.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
close_btn.Text = "×"
close_btn.TextColor3 = Color3.fromRGB(255, 100, 100)
close_btn.TextSize = 20
Instance.new("UICorner", close_btn)

-- Log Box
local log_box = Instance.new("ScrollingFrame", main_frame)
log_box.Name = "log_box"
log_box.Size = UDim2.new(0.9, 0, 0.6, 0)
log_box.Position = UDim2.new(0.05, 0, 0.15, 0)
log_box.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
log_box.ScrollBarThickness = 4
log_box.CanvasSize = UDim2.new(0, 0, 0, 0)

local log_layout = Instance.new("UIListLayout", log_box)
log_layout.Padding = UDim.new(0, 2)

-- Start & Stop Buttons
local start_btn = Instance.new("TextButton", main_frame)
start_btn.Name = "start_btn"
start_btn.Size = UDim2.new(0.42, 0, 0.12, 0)
start_btn.Position = UDim2.new(0.05, 0, 0.82, 0)
start_btn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
start_btn.Text = "START"
start_btn.Font = Enum.Font.GothamBold
start_btn.TextColor3 = Color3.new(1, 1, 1)
start_btn.TextScaled = true
Instance.new("UICorner", start_btn)

local stop_btn = Instance.new("TextButton", main_frame)
stop_btn.Name = "stop_btn"
stop_btn.Size = UDim2.new(0.42, 0, 0.12, 0)
stop_btn.Position = UDim2.new(0.53, 0, 0.82, 0)
stop_btn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
stop_btn.Text = "STOP"
stop_btn.Font = Enum.Font.GothamBold
stop_btn.TextColor3 = Color3.new(1, 1, 1)
stop_btn.TextScaled = true
Instance.new("UICorner", stop_btn)

-- Helper Functions
local function add_log(msg)
    local log_item = Instance.new("TextLabel", log_box)
    log_item.Name = "log_item"
    log_item.Size = UDim2.new(1, -10, 0, 18)
    log_item.BackgroundTransparency = 1
    log_item.TextColor3 = Color3.fromRGB(200, 200, 200)
    log_item.Text = "> " .. tostring(msg)
    log_item.Font = Enum.Font.Code
    log_item.TextSize = 10
    log_item.TextXAlignment = Enum.TextXAlignment.Left
    
    log_box.CanvasSize = UDim2.new(0, 0, 0, log_layout.AbsoluteContentSize.Y)
    log_box.CanvasPosition = Vector2.new(0, log_box.CanvasSize.Y.Offset)
end

local function save_to_json()
    local success, jsonString = pcall(function()
        return HttpService:JSONEncode(recordedActions)
    end)
    
    if success then
        if writefile then
            writefile(file_name, jsonString)
            add_log("Saved to " .. file_name)
        else
            print("--- JSON MACRO OUTPUT ---")
            print(jsonString)
            add_log("Exported to Console")
        end
    else
        add_log("ERROR: JSON Encoding failed")
    end
end

-- Non-Blocking Asynchronous Network Intercept Hook
local old_namecall
old_namecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    
    if _G.record_strat and (method == "FireServer" or method == "InvokeServer") then
        local remoteName = self.Name
        local lowerName = remoteName:lower()
        
        if lowerName:find("place") then
            placedTowersCount = placedTowersCount + 1
            local assignedIndex = placedTowersCount
            
            if not args[2] and lastMouseHit then
                args[2] = lastMouseHit
            end
            
            -- Execute the placement call and capture the server's returned tower reference/ID
            local results = {old_namecall(self, unpack(args))}
            local serverTowerId = results[1]
            
            if serverTowerId then
                activeTowerMap[tostring(serverTowerId)] = assignedIndex
            end
            
            task.spawn(function()
                local currentWave = getCurrentWave()
                table.insert(recordedActions, {
                    action = remoteName,
                    arguments = args,
                    time = math.floor((os.clock() - matchStartTime) * 100) / 100,
                    wave = currentWave,
                    index = assignedIndex
                })
                add_log(string.format("[%s] Wave: %s | Index: %s", remoteName, tostring(currentWave), tostring(assignedIndex)))
            end)
            
            return unpack(results)
            
        elseif lowerName:find("upgrade") or lowerName:find("sell") or lowerName:find("skip") or lowerName:find("ability") or lowerName:find("target") then
            local assignedIndex = nil
            if args[1] then
                local key = tostring(args[1])
                assignedIndex = activeTowerMap[key] or args[1]
            end
            
            task.spawn(function()
                local currentWave = getCurrentWave()
                table.insert(recordedActions, {
                    action = remoteName,
                    arguments = args,
                    time = math.floor((os.clock() - matchStartTime) * 100) / 100,
                    wave = currentWave,
                    index = assignedIndex
                })
                add_log(string.format("[%s] Wave: %s | Index: %s", remoteName, tostring(currentWave), tostring(assignedIndex)))
            end)
        end
    end
    
    return old_namecall(self, ...)
end)

-- Button Listeners
start_btn.MouseButton1Click:Connect(function()
    _G.record_strat = true
    recordedActions = {}
    placedTowersCount = 0
    activeTowerMap = {}
    matchStartTime = os.clock()
    
    for _, child in ipairs(log_box:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
    
    add_log("--- Recording Started ---")
end)

stop_btn.MouseButton1Click:Connect(function()
    if not _G.record_strat then return end
    _G.record_strat = false
    
    add_log("--- Recording Stopped ---")
    add_log("Total Actions: " .. tostring(#recordedActions))
    save_to_json()
end)

close_btn.MouseButton1Click:Connect(function()
    _G.record_strat = false
    screen_gui:Destroy()
end)

add_log("Recorder GUI Ready")
