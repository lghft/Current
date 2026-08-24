local player = game.Players.LocalPlayer

-- Function to handle the auto-sentry action with walking and continuous firing
local function triggerSentry(v)
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local HRP = character:WaitForChild("HumanoidRootPart")
    
    local powerPart = v:FindFirstChild("Power")
    local prompt = v:WaitForChild("Turret"):WaitForChild("Head"):WaitForChild("SentryPrompt")
    local head = v.Turret.Head
    
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 9999
    
    -- 1. Command the humanoid to walk to the sentry head position
    humanoid:MoveTo(head.Position)
    
    -- 2. Wait until the character arrives close to the destination
    local startTime = tick()
    while tick() - startTime < 10 do -- 10-second timeout to prevent infinite yielding
        if (HRP.Position - head.Position).Magnitude < 5 then
            break
        end
        task.wait(0.1)
    end
    
    -- 3. Keep firing the prompt repeatedly until the color changes
    while powerPart and powerPart.Color == Color3.fromRGB(255, 45, 45) do
        fireproximityprompt(prompt)
        task.wait(0.2) -- Adjust delay between fires if needed
    end
end

-- Scan workspace map for AutoSentries sequentially
while true do
    for _, v in ipairs(workspace.ActiveMap:GetChildren()) do
        if v:IsA("Model") and v.Name == "AutoSentry" then
            local powerPart = v:FindFirstChild("Power")
            
            if powerPart and powerPart:IsA("BasePart") then
                -- Check color
                if powerPart.Color == Color3.fromRGB(255, 45, 45) then
                    -- Walks to, stays at, and keeps spamming the prompt 
                    -- until this specific sentry's color changes.
                    triggerSentry(v)
                end
            end
        end
    end
    task.wait(1)
end
