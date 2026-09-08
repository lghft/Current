repeat task.wait(1) until game:IsLoaded()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local userId = localPlayer.UserId

getgenv().Crate = "Rare"  --"Leg","Epic" or "Rare"
getgenv().Vip = false -- if mobile set false

-- Configuration
local vipCode = "87759810925755092842120714459863"

local TARGET_COSMETICS = {
    -- ["Game Master's Book"] = { priority = "High" },
    -- ["Black Swordsman"] = { priority = "High" },
    -- ["Hologram"] = {priority = "Low"},
    ["Corrupt Overlord"] = {priority = "Low"},
    ["Blade Of Corruption"] = {priority = "Low"},
    --["Scott"] = {priority = "Low"},
    -- ["Fireaxe"] = {priority = "Low"},
    -- ["Elucidator"] = {priority = "Low"},
    --[[
    ["Inferno"] = {priority = "Low"},
    ["Rage"] = {priority = "Low"},
    ["Destruction Essence"] = {priority = "Low"},
    ["Solar Burst"] = {priority = "Low"},
    ]]
    -- [""] = {priority = "Low"},
}

local remotes = ReplicatedStorage:WaitForChild("remotes")
local introClickThread = nil  -- Track intro click thread

local function waitForGui(path, timeout, Type)
    timeout = timeout or 30
    Type = Type or "Enabled"
    local startTime = tick()
    repeat
        task.wait(0.1)
        local success, result = pcall(function()
            return path and path[Type] == true
        end)
        if success and result then break end
        if tick() - startTime > timeout then
            warn("GUI load timeout after " .. timeout .. " seconds")
            break
        end
    until false
end

function clickButton(ClickOnPart)
    if not ClickOnPart or not ClickOnPart:IsA("GuiObject") then return end
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local inset1 = game:GetService('GuiService'):GetGuiInset()
        local center = ClickOnPart.AbsolutePosition + (ClickOnPart.AbsoluteSize / 2) + inset1
        vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
        task.wait(0.05)
        vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
    end)
end

-- Handle Intro Screen
local introGui = playerGui:WaitForChild("introGui")
waitForGui(introGui, 30, "Enabled")
print("has waited for Intro?")

introClickThread = task.spawn(function()
    local introGui = playerGui:WaitForChild("introGui")
    local introBtn = introGui:WaitForChild("title"):WaitForChild("Frame"):WaitForChild("TextButton")
    
    -- Monitor if intro GUI is destroyed
    local connection
    connection = introGui.AncestryChanged:Connect(function()
        if not introGui.Parent then
            print("Intro GUI destroyed, stopping intro clicks")
            connection:Disconnect()
            return
        end
    end)
    
    -- Click until intro is gone
    while introGui.Parent and introGui.Enabled do
        if introBtn and introBtn.Parent then
            clickButton(introBtn)
            task.wait(0.1)  -- Slight delay between clicks
        else
            break
        end
    end
    
    if connection then
        connection:Disconnect()
    end
    print("Intro sequence complete")
end)

local function handleCaseResult(resultTable)
    if typeof(resultTable) == "table" then
        local itemName = resultTable.cosmetic or resultTable.Item or resultTable.Name or "Unknown"
        local category = resultTable.cosmeticType or resultTable.Type or "Unknown"
        
        local targetData = TARGET_COSMETICS[itemName]

        if targetData then
            print(string.format("\n========================================"))
            print(string.format("🎯 [TARGET ACQUIRED] Keeping Roll!"))
            print(string.format("   Item Name  : %s", itemName))
            print(string.format("   Category   : %s", category))
            print(string.format("   Priority   : %s", targetData.priority))
            print(string.format("========================================\n"))
        else
            print(string.format("\n----------------------------------------"))
            print(string.format("📦 [NON-TARGET] Unwanted item: %s", itemName))
            print(string.format("   Triggering fast reconnect to save currency..."))
            print(string.format("----------------------------------------\n"))
            
            pcall(function()
                if getgenv().Vip == true then
                    game:GetService("ExperienceService"):LaunchExperience({
                        placeId = 77649408247578, 
                        linkCode = tostring(vipCode)
                    })
                else
                    TeleportService:Teleport(game.PlaceId, localPlayer)
                end
                return true
            end)
        end
    end
end

-- Scan and hook incoming remote traffic
for _, descendant in ipairs(remotes:GetDescendants()) do
    if descendant:IsA("RemoteEvent") then
        descendant.OnClientEvent:Connect(function(...)
            local args = { ... }
            for _, arg in ipairs(args) do
                if typeof(arg) == "table" then
                    if arg.cosmetic or arg.Item or arg.Name or arg.success ~= nil or arg.rarity then
                        handleCaseResult(arg)
                    end
                end
            end
        end)
    end
end

print("[Case Interceptor] Active and monitoring incoming rewards against target list.")

-- Wait for intro to finish before proceeding
task.wait(2)

-- Navigate Shop UI
local mainInter = playerGui:WaitForChild("mainInterface")
waitForGui(mainInter, 30, "Enabled")
task.wait(0.5)
print("has waited for main?")

local shopBtn = mainInter:WaitForChild("buttons"):WaitForChild("shopButton")

-- Retry loop to ensure shop GUI appears
local shopGui = nil
local shopAppeared = false
local maxRetries = 10
local retryCount = 0

while not shopAppeared and retryCount < maxRetries do
    task.wait(0.25)
    clickButton(shopBtn)
    print("Clicked shop button (attempt " .. (retryCount + 1) .. ")")
    
    task.wait(1)  -- Wait for shop to potentially open
    
    -- Check if shop GUI exists and is visible
    local success, result = pcall(function()
        shopGui = mainInter:WaitForChild("shop", 1)  -- 1 second timeout
        return shopGui and shopGui.Visible == true
    end)
    
    if success and result then
        shopAppeared = true
        print("Shop GUI appeared successfully!")
        task.wait(0.25)
    else
        retryCount = retryCount + 1
        print("Shop GUI not visible yet, retrying... (" .. retryCount .. "/" .. maxRetries .. ")")
        task.wait(0.25)
    end
end

if not shopAppeared then
    warn("Failed to open shop after " .. maxRetries .. " attempts!")
    return
end

print("has waited for shop?")

-- Switch to Crate Tab
local crateTabBtn = shopGui:WaitForChild("crateTab")
task.wait()
clickButton(crateTabBtn)
task.wait()
clickButton(crateTabBtn)
task.wait()
print("has pressed tab for crate?")

-- Verify Crates are Visible (with retry)
local cratesVisible = false
local maxCrateVisibilityRetries = 10
local crateVisibilityRetryCount = 0

while not cratesVisible and crateVisibilityRetryCount < maxCrateVisibilityRetries do
    task.wait(0.3)
    
    local success, result = pcall(function()
        local crates = shopGui:WaitForChild("crates", 1)
        return crates and crates.Visible == true
    end)
    
    if success and result then
        cratesVisible = true
        print("Crates are now visible!")
    else
        print("Crates not visible yet, clicking crate tab again... (" .. (crateVisibilityRetryCount + 1) .. "/" .. maxCrateVisibilityRetries .. ")")
        clickButton(crateTabBtn)
        crateVisibilityRetryCount = crateVisibilityRetryCount + 1
        task.wait(0.3)
    end
end

if not cratesVisible then
    warn("Failed to make crates visible after " .. maxCrateVisibilityRetries .. " attempts!")
    return
end

-- Select Configured Crate with retry logic
local crateType = getgenv().Crate or "Leg"
local crateSelected = false
local maxCrateRetries = 5
local crateRetryCount = 0

while not crateSelected and crateRetryCount < maxCrateRetries do
    task.wait(0.3)
    
    if crateType == "Leg" then
        local success, legBtn = pcall(function()
            return shopGui:WaitForChild("crates", 2):WaitForChild("LegFrame", 2):WaitForChild("LegendaryButton", 2)
        end)
        if success and legBtn then
            clickButton(legBtn)
            print("Clicked Legendary crate")
            crateSelected = true
        else
            print("Legendary button not found, retrying... (" .. (crateRetryCount + 1) .. "/" .. maxCrateRetries .. ")")
        end
        
    elseif crateType == "Epic" then
        local success, epicBtn = pcall(function()
            return shopGui:WaitForChild("crates", 2):WaitForChild("EpicFrame", 2):WaitForChild("EpicButton", 2)
        end)
        if success and epicBtn then
            clickButton(epicBtn)
            print("Clicked Epic crate")
            crateSelected = true
        else
            print("Epic button not found, retrying... (" .. (crateRetryCount + 1) .. "/" .. maxCrateRetries .. ")")
        end
        
    elseif crateType == "Rare" then
        local success, rareBtn = pcall(function()
            return shopGui:WaitForChild("crates", 2):WaitForChild("RareFrame", 2):WaitForChild("RareButton", 2)
        end)
        if success and rareBtn then
            clickButton(rareBtn)
            print("Clicked Rare crate")
            crateSelected = true
        else
            print("Rare button not found, retrying... (" .. (crateRetryCount + 1) .. "/" .. maxCrateRetries .. ")")
        end
    end
    
    crateRetryCount = crateRetryCount + 1
    if not crateSelected then
        task.wait(0.5)
    end
end

if not crateSelected then
    warn("Failed to select " .. crateType .. " crate after " .. maxCrateRetries .. " attempts!")
else
    print(crateType .. " crate selected successfully!")
end
