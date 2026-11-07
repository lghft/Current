local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local IDLE_THRESHOLD = 90 -- Seconds required to trigger
local MOVEMENT_THRESHOLD = 0.5 -- Studs moved to count as "moving"

local idleTime = 0
local lastPosition = nil
local statusLabel = nil

-- Function to check if any child in workspace.GameMap contains "Raid"
local function hasRaidMap()
	local gameMap = Workspace:FindFirstChild("GameMap")
	if not gameMap then return false end
	
	for _, child in ipairs(gameMap:GetChildren()) do
		if string.find(string.lower(child.Name), "raid") then
			return true
		end
	end
	return false
end

-- Function to dynamically find the SLH Hub ScreenGui in CoreGui
local function getSLHHub()
	for _, gui in ipairs(CoreGui:GetChildren()) do
		if string.find(gui.Name, "SLH Hub Modified") then
			return gui
		end
	end
	return nil
end

-- Function to create or update the timer TextLabel with milliseconds and a thicker red border
local function updateTimerDisplay(currentTime)
	local hub = getSLHHub()
	if not hub then return end
	
	local mainFrame = hub:FindFirstChild("main")
	if not mainFrame then return end
	
	if not statusLabel or not statusLabel.Parent then
		statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "AFKTimerLabel"
		statusLabel.Size = UDim2.new(0, 150, 0, 50)
		statusLabel.Position = UDim2.new(1, 10, 0.4, 0)
		statusLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		statusLabel.BorderColor3 = Color3.fromRGB(255, 0, 0)
		statusLabel.BorderSizePixel = 2 -- Thicker red stroke/border
		statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		statusLabel.TextSize = 13
		statusLabel.Font = Enum.Font.SourceSansBold
		statusLabel.ZIndex = 10
		statusLabel.Parent = mainFrame
	end
	
	-- Calculate remaining time with millisecond precision (1 decimal place)
	local timeLeft = math.max(0, IDLE_THRESHOLD - currentTime)
	statusLabel.Text = string.format("AFK Timer:\n%.1fs / %ds", timeLeft, IDLE_THRESHOLD)
end

-- Function to find the button dynamically based on its Label text
local function getKillAuraButton(itemsFolder)
	for _, descendant in ipairs(itemsFolder:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant.Name == "Label" then
			if descendant.Text == "Kill Aura(Only ExtremeDimension)" then
				return descendant.Parent
			end
		end
	end
	return nil
end

-- Main initialization and monitoring loop
task.spawn(function()
	print("Waiting for SLH Hub to load...")
	
	-- Pause the script here until the GUI actually exists in CoreGui
	while not getSLHHub() do
		task.wait(0.5)
	end
	
	print("SLH Hub detected! Starting AFK and Raid monitor...")
	
	while true do
		task.wait(0.1) 
		
		local character = LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		
		if hrp then
			if lastPosition then
				local distance = (hrp.Position - lastPosition).Magnitude
				
				if distance < MOVEMENT_THRESHOLD then
					idleTime = idleTime + 0.1
				else
					-- Player moved, reset timer
					idleTime = 0
				end
			end
			lastPosition = hrp.Position
		end
		
		-- Update the timer display on the GUI with milliseconds
		updateTimerDisplay(idleTime)
		
		-- Check if idle time has exceeded 150 seconds
		if idleTime >= IDLE_THRESHOLD then
			-- Check if the map does NOT contain "Raid"
			if not hasRaidMap() then
				print("Conditions met: Inactive for 150s + Non-Raid map. Executing action...")
				
				local hub = getSLHHub()
				if hub then
					local success, err = pcall(function()
						local itemsFolder = hub.main.rightside.InGameSector.items
						local btn = getKillAuraButton(itemsFolder)
						
						if btn then
							print("yes")
							firesignal(btn.MouseButton1Down)
							print('btndown')
							task.wait(1)
							firesignal(btn.MouseButton1Down)
							print('btnup')
						else
							print("no? (Could not find a button with the Kill Aura label text)")
						end
					end)
					if not success then
						warn("Error interacting with UI: " .. tostring(err))
					end
				else
					warn("SLH Hub Modified GUI not found in CoreGui.")
				end
				
				-- Reset the timer after execution
				idleTime = 0 
			end
		end
	end
end)
