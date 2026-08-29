function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

cloneref = missing("function", cloneref, function(...) return ... end)
firetouchinterest = missing("function", firetouchinterest)

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
RunService = Services.RunService
UserInputService = Services.UserInputService
local speaker = game.Players.LocalPlayer
local beganListener: RBXScriptConnection
local endListener: RBXScriptConnection
local floatingFunc: RBXScriptConnection
local pchar = speaker.Character

function randomString()
	local length = math.random(10,20)
	local array = {}
	for i = 1, length do
		array[i] = string.char(math.random(32, 126))
	end
	return table.concat(array)
end

function getRoot(char)
	if char and char:FindFirstChildOfClass("Humanoid") then
		return char:FindFirstChildOfClass("Humanoid").RootPart
	else
		return nil
	end
end

pcall(function() Noclipping:Disconnect() end)

Clip = false
task.wait(0.1)
NoclipParts = {}
Noclipping = RunService.Stepped:Connect(function()
    if Clip == false and speaker.Character ~= nil then
        for _, child in pairs(speaker.Character:GetDescendants()) do
            if child:IsA("BasePart") and child.CanCollide == true and child.Name ~= floatName then
                child.CanCollide = false
                NoclipParts[child] = true
            end
        end
    end
end)

floating = false

floatName = randomString()
floating = true

if pchar and not pchar:FindFirstChild(floatName) then
    task.spawn(function()
        local floatPoint = -3.1
        local floatPart = Instance.new('Part')
        floatPart.Name = floatName
        floatPart.Parent = pchar
        floatPart.Transparency = 1
        floatPart.Size = Vector3.new(2, 0.2, 1.5)
        floatPart.Anchored = true
        
        beganListener = UserInputService.InputBegan:Connect(function(key, processed)
            if processed then return end

            if key.KeyCode == Enum.KeyCode.X then
                floatPoint -= 0.5
            end
            if key.KeyCode == Enum.KeyCode.C then
                floatPoint += 1.5
            end
        end)
        endListener = UserInputService.InputEnded:Connect(function(key, processed)
            if processed then return end

            if key.KeyCode == Enum.KeyCode.X then
                floatPoint += 0.5
            end
            if key.KeyCode == Enum.KeyCode.C then
                floatPoint -= 1.5
            end
        end)
        
        floatDied = speaker.Character:FindFirstChildOfClass('Humanoid').Died:Connect(function()
            floatingFunc:Disconnect()
            floatPart:Destroy()
            floatDied:Disconnect()
            beganListener:Disconnect()
            endListener:Disconnect()
            floatName = nil
        end)
        local function floatPadLoop()
            if pchar:FindFirstChild(floatName) and getRoot(pchar) then
                floatPart.CFrame = getRoot(pchar).CFrame * CFrame.new(0, floatPoint, 0)
            else
                floatingFunc:Disconnect()
                floatPart:Destroy()
                floatDied:Disconnect()
                beganListener:Disconnect()
                endListener:Disconnect()
                floatName = nil
            end
        end			
        floatingFunc = RunService.PreAnimation:Connect(floatPadLoop)
    end)
end

