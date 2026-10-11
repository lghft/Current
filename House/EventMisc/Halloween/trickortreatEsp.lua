local doorsFolder = workspace:WaitForChild("TrickOrTreatDoors", 10)
local activeHighlights = {}

print("[ESP] Door ESP (Highlight) Loaded")

local function removeESP(door)
    if activeHighlights[door] then
        activeHighlights[door]:Destroy()
        activeHighlights[door] = nil
        print("[ESP] Removed highlight from:", door.Name)
    end
end

local function createESP(door)
    if activeHighlights[door] then return end
    
    -- Make door visible (not transparent)
    door.Transparency = 0
    
    -- Create a Highlight object on the door
    local highlight = Instance.new("Highlight")
    highlight.Parent = door
    highlight.FillColor = Color3.fromRGB(255, 140, 0)  -- Orange
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)  -- White
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    
    activeHighlights[door] = highlight
    print("[ESP] Highlighted:", door.Name)
end

local function checkDoor(door)
    if not door:IsA("BasePart") then return end
    
    local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then
        removeESP(door)
        return
    end
    
    local objectText = prompt.ObjectText or ""
    
    -- Check if ObjectText contains "Trick" (for trick-or-treat doors)
    if objectText:lower():find("trick") then
        createESP(door)
    else
        removeESP(door)
    end
end

local function setupDoor(door)
    checkDoor(door)
    
    -- Monitor for prompt changes
    local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        prompt.Changed:Connect(function()
            checkDoor(door)
        end)
    end
    
    -- Monitor for prompt being removed
    door.ChildRemoved:Connect(function(child)
        if child:IsA("ProximityPrompt") then
            checkDoor(door)
        end
    end)
end

-- Setup all existing doors
if doorsFolder then
    print("[ESP] Found", #doorsFolder:GetChildren(), "doors")
    for _, door in ipairs(doorsFolder:GetChildren()) do
        setupDoor(door)
    end
    
    -- Listen for new doors
    doorsFolder.ChildAdded:Connect(function(door)
        task.wait(0.1)
        setupDoor(door)
    end)
else
    warn("[ESP] Doors folder not found!")
end

print("[ESP] Highlight ESP Active!")
