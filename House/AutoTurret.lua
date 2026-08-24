local player = game.Players.LocalPlayer

-- Function to handle the auto-sentry action
local function triggerSentry(v)
    local character = player.Character or player.CharacterAdded:Wait()
    local HRP = character:WaitForChild("HumanoidRootPart")
    
    local prompt = v:WaitForChild("Turret"):WaitForChild("Head"):WaitForChild("SentryPrompt")
    local head = v.Turret.Head
    
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 9999
    
    -- 1. Teleport player to the sentry head
    HRP.CFrame = head.CFrame
    
    -- 2. Fire the proximity prompt
    fireproximityprompt(prompt)
    
    -- 3. Teleport back to the spawn location
    local spawnLocation = workspace.ActiveMap:FindFirstChild("SpawnLocation")
    if spawnLocation and spawnLocation:IsA("BasePart") then
        -- Adding a tiny offset upwards prevents getting stuck inside the spawn floor
        HRP.CFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
    end
end

-- Scan workspace map for AutoSentries
while true do
    for _, v in ipairs(workspace.ActiveMap:GetChildren()) do
        if v:IsA("Model") and v.Name == "AutoSentry" then
            local powerPart = v:FindFirstChild("Power")
            
            if powerPart and powerPart:IsA("BasePart") then
                -- 1. Check color immediately upon running
                if powerPart.Color == Color3.fromRGB(255, 45, 45) then
                    triggerSentry(v)
                end
            end
        end
    end
    task.wait()
end
