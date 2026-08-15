local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pchar = player.Character or player.CharacterAdded:Wait()

-- Your custom getRoot function
local function getRoot(char)
	if char and char:FindFirstChildOfClass("Humanoid") then
		return char:FindFirstChildOfClass("Humanoid").RootPart
	else
		return nil
	end
end

-- Your custom randomString function
local function randomString()
	local length = math.random(10, 20)
	local array = {}
	for i = 1, length do
		array[i] = string.char(math.random(32, 126))
	end
	return table.concat(array)
end

-- Simple notification fallback if none exists
local function notify(title, text)
	print("[" .. title .. "]: " .. text)
end

local floatName = randomString()
local floating = true
local floatingFunc, beganListener, endListener, floatDied

if pchar and not pchar:FindFirstChild(floatName) then
	task.spawn(function()
		local floatPoint = -3.1
		local floatPart = Instance.new("Part")
		floatPart.Name = floatName
		floatPart.Parent = pchar
		floatPart.Transparency = 1
		floatPart.Size = Vector3.new(2, 0.2, 1.5)
		floatPart.Anchored = true
		
		notify("Float", "Started floating (Q = down & E = up)")
		
		beganListener = UserInputService.InputBegan:Connect(function(key, processed)
			if processed then return end

			if key.KeyCode == Enum.KeyCode.Q then
				floatPoint -= 0.5
			end
			if key.KeyCode == Enum.KeyCode.E then
				floatPoint += 1.5
			end
		end)
		
		endListener = UserInputService.InputEnded:Connect(function(key, processed)
			if processed then return end

			if key.KeyCode == Enum.KeyCode.Q then
				floatPoint += 0.5
			end
			if key.KeyCode == Enum.KeyCode.E then
				floatPoint -= 1.5
			end
		end)
		
		local humanoid = pchar:FindFirstChildOfClass("Humanoid")
		if humanoid then
			floatDied = humanoid.Died:Connect(function()
				if floatingFunc then floatingFunc:Disconnect() end
				floatPart:Destroy()
				if floatDied then floatDied:Disconnect() end
				if beganListener then beganListener:Disconnect() end
				if endListener then endListener:Disconnect() end
				floatName = nil
			end)
		end
		
		local function floatPadLoop()
			if pchar:FindFirstChild(floatName) and getRoot(pchar) then
				floatPart.CFrame = getRoot(pchar).CFrame * CFrame.new(0, floatPoint, 0)
			else
				if floatingFunc then floatingFunc:Disconnect() end
				floatPart:Destroy()
				if floatDied then floatDied:Disconnect() end
				if beganListener then beganListener:Disconnect() end
				if endListener then endListener:Disconnect() end
				floatName = nil
			end
		end			
		
		floatingFunc = RunService.RenderStepped:Connect(floatPadLoop)
	end)
end
