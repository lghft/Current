local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local ServerType = game:GetService('RobloxReplicatedStorage').GetServerType:InvokeServer()
local LocalPlayer = Players.LocalPlayer
local IDLE_THRESHOLD = 40 -- Seconds required to trigger (timer 1)
local IDLE_THRESHOLD_2 = 90 -- Seconds required to trigger (timer 2)
local MOVEMENT_THRESHOLD = 0.5 -- Studs moved to count as "moving"

local idleTime = 0
local idleTime2 = 0
local lastPosition = nil
local statusLabel = nil
local statusLabel2 = nil

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

-- Creates or updates a timer label. yOffset stacks multiple labels vertically.
local function updateTimerDisplay(existingLabel, labelName, title, yOffset, currentTime, threshold)
	local hub = getSLHHub()
	if not hub then return existingLabel end

	local mainFrame = hub:FindFirstChild("main")
	if not mainFrame then return existingLabel end

	local label = existingLabel
	if not label or not label.Parent then
		label = Instance.new("TextLabel")
		label.Name = labelName
		label.Size = UDim2.new(0, 150, 0, 50)
		label.Position = UDim2.new(1, 10, 0.4, yOffset)
		label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		label.BorderColor3 = Color3.fromRGB(255, 0, 0)
		label.BorderSizePixel = 2 -- Thicker red stroke/border
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextSize = 13
		label.Font = Enum.Font.SourceSansBold
		label.ZIndex = 10
		label.Parent = mainFrame
	end

	-- Calculate remaining time with millisecond precision (1 decimal place)
	local timeLeft = math.max(0, threshold - currentTime)
	label.Text = string.format("%s\n%.1fs / %ds", title, timeLeft, threshold)

	return label
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
					idleTime2 = idleTime2 + 0.1
				else
					-- Player moved, reset both timers
					idleTime = 0
					idleTime2 = 0
				end
			end
			lastPosition = hrp.Position
		end

		-- Update both timer displays
		statusLabel = updateTimerDisplay(statusLabel, "AFKTimerLabel", "AFK Timer:", 0, idleTime, IDLE_THRESHOLD)
		statusLabel2 = updateTimerDisplay(statusLabel2, "AFKTimerLabel90", "AFK Timer (90s):", 60, idleTime2, IDLE_THRESHOLD_2)

		-- Timer 1: original 40s check
		if idleTime >= IDLE_THRESHOLD then
			if not hasRaidMap() then
				print("Conditions met: Inactive for " .. IDLE_THRESHOLD .. "s + Non-Raid map. Executing action...")

				local hub = getSLHHub()
				if hub then
					local success, err = pcall(function()
						local itemsFolder = hub.main.rightside.InGameSector.items
						local btn = getKillAuraButton(itemsFolder)

						if btn then
							if btn.Frame.Visible then
								print("btn is on")
								firesignal(btn.MouseButton1Down)
								print('btndown')
								task.wait(1)
								firesignal(btn.MouseButton1Down)
								print('btnup')
							else
								print("btn is off")
								firesignal(btn.MouseButton1Down)
								print('btndown')
							end
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

				-- Reset timer 1 after execution
				idleTime = 0
			end
		end

		-- Timer 2: 90s check
		if idleTime2 >= IDLE_THRESHOLD_2 then
			if not hasRaidMap() then
				print("90s idle threshold reached + Non-Raid map. Running second action...")

				if game:GetService("Players").LocalPlayer.PlayerGui.UniversalGui.UniversalCenterUIFrame.ResultUI.Visible == true then
					local targetCode8 = "11167079176002922000164780725282"
					task.spawn(function()
						if ServerType ~= "VIPServer" then
							game:GetService("ExperienceService"):LaunchExperience({
								placeId = 6938803436,
								linkCode = tostring(targetCode8)
							})
						end
					end)
				end

				-- Reset timer 2 after execution
				idleTime2 = 0
			end
		end
	end
end)
