repeat task.wait() until game:IsLoaded()

-- [[ SETTINGS ]]
getgenv().Mob = true 
getgenv().AutoClicker = true
getgenv().Targeting = true 
getgenv().Ability = false
getgenv().Boss = true 
getgenv().BossType = "Executioner" 
getgenv().Days = false
getgenv().InfCheck = false 
getgenv().TargetScore = 32400 
getgenv().ZombiesFolder = true
getgenv().Survival = false 

-- [[ UTILITY SETTINGS ]]
getgenv().FastWeapon = true
getgenv().AltAutoClicker = true
getgenv().AntiLag = true
getgenv().FullBright = true
getgenv().AimPart = "Head" 

-- [[ GLOBAL COUNTER ]]
getgenv().EvadeCount = 0

-- [[ TARGETING PRIORITIES ]]
getgenv().PriorityOnly = true       
getgenv().FrequentPriority = false    
getgenv().PriorityList = { ["Zombie"] = true }
getgenv().IgnoreList = {}

----------------------------------------------------------------
-- OPTIMIZATION & LIGHTING
----------------------------------------------------------------
if getgenv().AntiLag then
    task.spawn(function()
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("Texture") or v:IsA("Decal") then
                v:Destroy()
            elseif v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then
                v.Material = Enum.Material.SmoothPlastic
                v.Reflectance = 0
            end
        end
    end)
end

if getgenv().FullBright then
    task.spawn(function()
        local Lighting = game:GetService("Lighting")
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting:GetPropertyChangedSignal("Brightness"):Connect(function() Lighting.Brightness = 2 end)
    end)
end

----------------------------------------------------------------
-- UTILS & WEBHOOK
----------------------------------------------------------------
local function generateRandomPassword(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local randomString = ""
    for i = 1, length do
        local rand = math.random(1, #chars)
        local char = string.sub(chars, rand, rand)
        randomString = randomString .. char
    end
    return randomString
end

local hasSentWebhook = false
local function sendLobbyWebhook()
    if hasSentWebhook then return end
    local plr = game.Players.LocalPlayer
    local OSTime = os.time()
    local Time = os.date('!*t', OSTime)
    pcall(function()
        local stats = plr:WaitForChild("Stats")
        local request = (syn and syn.request) or (http and http.request) or http_request
        if request then
            request({
                Url = 'https://discord.com/api/webhooks/1414475376230535199/F6V5IZJkOUMdxd-ZdC32JdlaTw-FGDz-raRMGW7a6FsYTmYtRkqOSfLy123hat3xSNR1',
                Method = 'POST',
                Headers = {['Content-Type'] = 'application/json'},
                Body = game:GetService('HttpService'):JSONEncode({
                    content = "🏠 **Back in Lobby**",
                    embeds = {{
                        ["title"] = "**「 COMZ2 - Lobby Update 」**",
                        ["description"] = "Player: ||**" .. plr.Name .. "**||",
                        ["color"] = tonumber(0x93c47d),
                        ["fields"] = {{
                            ["name"] = "📊 **Current Balance**",
                            ["value"] = "💰 **Coins:** " .. stats.Coins.Value .. "\n💎 **Gems:** " .. stats.Crystals.Value .. 
                            "\n⚙️ **Gears:** " .. stats.Gears.Value .. "\n🧬 **DNA:** " .. stats.DNA.Value .. 
                            "\n🫀 **Self-Revives:** " .. stats.SelfRevives.Value .. "\n📅 **Days Survived:** " .. stats.DAY.Value,
                            ["inline"] = false
                        }},
                        ["timestamp"] = string.format('%d-%02d-%02dT%02d:%02d:%02dZ', Time.year, Time.month, Time.day, Time.hour, Time.min, Time.sec)
                    }}
                })
            })
            hasSentWebhook = true
        end
    end)
end

local function sendReconnectWebhook(reason)
    local plr = game.Players.LocalPlayer
    local OSTime = os.time()
    local Time = os.date('!*t', OSTime)
    pcall(function()
        local request = (syn and syn.request) or (http and http.request) or http_request
        if request then
            request({
                Url = 'https://discord.com/api/webhooks/1414475376230535199/F6V5IZJkOUMdxd-ZdC32JdlaTw-FGDz-raRMGW7a6FsYTmYtRkqOSfLy123hat3xSNR1',
                Method = 'POST',
                Headers = {['Content-Type'] = 'application/json'},
                Body = game:GetService('HttpService'):JSONEncode({
                    content = "🔄 **Auto-Reconnect Triggered**",
                    embeds = {{
                        ["title"] = "**「 COMZ2 - Connection Alert 」**",
                        ["description"] = "Player: ||**" .. plr.Name .. "**||\n**Status:** Reconnecting to Lobby\n**Reason:** " .. (reason or "Unknown Error") .. "\n GameID: " .. tostring(game.PlaceId),
                        ["color"] = tonumber(0x227EE6),
                        ["timestamp"] = string.format('%d-%02d-%02dT%02d:%02d:%02dZ', Time.year, Time.month, Time.day, Time.hour, Time.min, Time.sec)
                    }}
                })
            })
        end
    end)
end

-- [[ RECONNECT LOGIC ]]
task.spawn(function()
    local GuiService = game:GetService("GuiService")
    local Players = game:GetService("Players")
    local TeleportService = game:GetService("TeleportService")

    local player = Players.LocalPlayer

    local TARGET_PLACE_ID = 15899178400

    local function onErrorMessageChanged(errorMessage)
    if errorMessage and errorMessage ~= "" then
            task.spawn(function()
                pcall(function() sendReconnectWebhook(errorMessage) end)
            end)

            while task.wait(0.5) do 
                print("Attempting to escape crash...")
                pcall(function()
                    TeleportService:Teleport(TARGET_PLACE_ID)
                end)
            end
        end
    end

    GuiService.ErrorMessageChanged:Connect(onErrorMessageChanged)

    print("rejoin time")

    print("Auto reconnect script loaded!")
end)

----------------------------------------------------------------
-- MISSION STATE HELPERS
----------------------------------------------------------------
local function getUIState()
    local plr = game.Players.LocalPlayer
    local hud = plr.PlayerGui:FindFirstChild("HUD")
    local mainMenu = plr.PlayerGui:FindFirstChild("MainMenu")
    local mainFrame = mainMenu and mainMenu:FindFirstChild("MainFrame")
    local mapFolder = workspace:FindFirstChild("CURRENT_MAP")
    local hasMap = mapFolder and #mapFolder:GetChildren() > 0

    return {
        hudEnabled       = hud and hud.Enabled or false,
        mainMenuEnabled  = mainMenu and mainMenu.Enabled or false,
        mainFrameVisible = mainFrame and mainFrame.Visible or false,
        hasMap           = hasMap or false,
    }
end

local function isBuggedState()
    local s = getUIState()
    local plr = game.Players.LocalPlayer
    local gunGUI = plr.PlayerGui:FindFirstChild("GunGUI")
    local gunGUIActive = gunGUI and gunGUI.Enabled or false

    if s.hudEnabled and s.mainMenuEnabled then return true end
    if not s.hudEnabled and gunGUIActive and s.mainMenuEnabled then return true end

    return false
end

local function isPlayerInMission()
    local s = getUIState()
    return s.hasMap or s.hudEnabled
end

local function isInLobby()
    local s = getUIState()
    if s.hudEnabled and s.mainMenuEnabled then return false end
    if s.hasMap or s.hudEnabled then return false end
    return s.mainMenuEnabled and s.mainFrameVisible
end

local function isResultVisible()
    local plr = game.Players.LocalPlayer
    local menu = plr.PlayerGui:FindFirstChild("MainMenu")
    local missionComplete = plr.PlayerGui:FindFirstChild("MissionComplete")
    local standardResult = menu and menu.Enabled and menu:FindFirstChild("ResultFrame") and menu.ResultFrame.Visible
    local daysResult = missionComplete and missionComplete.Enabled and missionComplete:FindFirstChild("MainFrame") and missionComplete.MainFrame.Visible
    return standardResult or daysResult
end

local function isCinematicActive()
    local plr = game.Players.LocalPlayer
    local cinematic = plr.PlayerGui:FindFirstChild("CINEMATIC")
    
    local guiActive = cinematic and cinematic.Enabled or false
    local cam = workspace.CurrentCamera
    local cameraScriptable = cam and cam.CameraType == Enum.CameraType.Scriptable

    return guiActive or cameraScriptable
end

----------------------------------------------------------------
-- CLICK HELPER
----------------------------------------------------------------
function clickButton(ClickOnPart)
    if not ClickOnPart or not ClickOnPart:IsA("GuiObject") then return end
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local inset1 = game:GetService('GuiService'):GetGuiInset()
        local center = ClickOnPart.AbsolutePosition + (ClickOnPart.AbsoluteSize / 2) + inset1
        vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
        task.wait(0.01)
        vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
    end)
end

----------------------------------------------------------------
-- TARGETING HELPERS
----------------------------------------------------------------
local function isIgnored(model)
    if not model then return false end
    for name, _ in pairs(getgenv().IgnoreList) do
        if model.Name == name then return true end
    end
    return false
end

local function isPriority(model)
    if not model then return false end
    for name, _ in pairs(getgenv().PriorityList) do
        if model.Name == name then return true end
    end
    return false
end

local function isValidTarget(model)
    if isIgnored(model) then return false end
    if getgenv().PriorityOnly and not isPriority(model) then return false end
    return true
end

----------------------------------------------------------------
-- WEAPON MODS
----------------------------------------------------------------
local function applyFastWeapons()
    if not getgenv().FastWeapon then return end
    for _, obj in ipairs(getgc(true)) do
        if type(obj) == "table" then
            if rawget(obj, "Damage") then
                obj.Damage = 999999
            end
            if rawget(obj, "FireRate") and rawget(obj, "ReloadTime") then
                local isReadOnly = isreadonly(obj)
                if isReadOnly then setreadonly(obj, false) end
                obj.FireRate = 0
                obj.ReloadTime = 0
                if isReadOnly then setreadonly(obj, true) end
            end
        end
    end
end

game.Players.LocalPlayer.CharacterAdded:Connect(function()
    task.wait(2.5)
    applyFastWeapons()
end)

applyFastWeapons()

----------------------------------------------------------------
-- GUI SETUP
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui", game.CoreGui)
local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0, 220, 0, 255) 
mainFrame.Position = UDim2.new(0, 10, 0, 10)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BackgroundTransparency = 0.3
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local function createLabel(text, pos)
    local label = Instance.new("TextLabel", mainFrame)
    label.Size = UDim2.new(1, -20, 0, 25)
    label.Position = pos
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Text = text
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    return label
end

local mobStatusLabel  = createLabel("Mob: " .. tostring(getgenv().Mob), UDim2.new(0, 10, 0, 5))
local zombiesLabel    = createLabel("Zombies/Obj: 0",          UDim2.new(0, 10, 0, 30))
local trackingLabel   = createLabel("Tracking: None",          UDim2.new(0, 10, 0, 55))
local posLabel        = createLabel("Pos: Default",            UDim2.new(0, 10, 0, 80))
local statusLabel     = createLabel("Status: Initializing...", UDim2.new(0, 10, 0, 105))
local scoreLabel      = createLabel("Score: 0",                UDim2.new(0, 10, 0, 130))
local evadeCountLabel = createLabel("Evades: 0/4",             UDim2.new(0, 10, 0, 155))
local lobbyLabel      = createLabel("Lobby: Unknown",          UDim2.new(0, 10, 0, 180))

local toggleButton = Instance.new("TextButton", mainFrame)
toggleButton.Size = UDim2.new(1, -20, 0, 35)
toggleButton.Position = UDim2.new(0, 10, 0, 210)
toggleButton.BackgroundColor3 = getgenv().Mob and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(50, 200, 50)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.Text = getgenv().Mob and "STOP AUTOFARM" or "START AUTOFARM"
Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 6)

toggleButton.MouseButton1Click:Connect(function()
    getgenv().Mob = not getgenv().Mob
    mobStatusLabel.Text = "Mob: " .. tostring(getgenv().Mob)
    toggleButton.Text = getgenv().Mob and "STOP AUTOFARM" or "START AUTOFARM"
    toggleButton.BackgroundColor3 = getgenv().Mob and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(50, 200, 50)
    
    if not getgenv().Mob then
        statusLabel.Text = "Status: Disabled"
        trackingLabel.Text = "Tracking: None"
    end
end)

----------------------------------------------------------------
-- SCORE & INF-CHECK TRACKING
----------------------------------------------------------------
local currentScore = 0

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local plr = game.Players.LocalPlayer
            local hud = plr.PlayerGui:FindFirstChild("HUD")
            if hud and hud:FindFirstChild("HealthFrame") then
                local sText = hud.HealthFrame.INFO.MAIN.SCORE.Text
                scoreLabel.Text = "Score: " .. sText
                if getgenv().InfCheck and tonumber(sText) and tonumber(sText) >= getgenv().TargetScore then
                    getgenv().Mob = false
                    mobStatusLabel.Text = "Mob: false"
                    toggleButton.Text = "START AUTOFARM"
                    toggleButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
                    statusLabel.Text = "Status: Target Score Reached!"
                end
            else
                local stats = plr:FindFirstChild("leaderstats") or plr:FindFirstChild("Stats")
                if stats then
                    local scoreVal = stats:FindFirstChild("Score") or stats:FindFirstChild("Cash") or stats:FindFirstChild("Points")
                    if scoreVal then
                        currentScore = scoreVal.Value
                        scoreLabel.Text = "Score: " .. tostring(currentScore)
                        if getgenv().InfCheck and currentScore >= getgenv().TargetScore then
                            getgenv().Mob = false
                            mobStatusLabel.Text = "Mob: false"
                            toggleButton.Text = "START AUTOFARM"
                            toggleButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
                            statusLabel.Text = "Status: Target Score Reached!"
                        end
                    end
                end
            end
        end)
    end
end)

----------------------------------------------------------------
-- LAST START TIME & DAYS REMOTE HELPER
----------------------------------------------------------------
local lastStartTime = 0

local function fireDaysRemote()
    statusLabel.Text = "Status: Starting Days..."
    lastStartTime = tick()
    pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("BeginDay"):FireServer("DAYS")
    end)
    task.wait(5)
    applyFastWeapons()
end

----------------------------------------------------------------
-- AUTO-CLICKERS (Cinematic Aware)
----------------------------------------------------------------
task.spawn(function()
    local vim = game:GetService("VirtualInputManager")
    while task.wait(0.1) do
        if getgenv().Boss and isCinematicActive() then 
            statusLabel.Text = "Status: Waiting for Cinematic..."
            continue 
        end

        local mapFolder = workspace:FindFirstChild("CURRENT_MAP")
        local hasMap = mapFolder and #mapFolder:GetChildren() > 0

        if getgenv().AutoClicker and getgenv().Mob and (isPlayerInMission() or hasMap) and not isResultVisible() then
            local vp = workspace.CurrentCamera.ViewportSize
            vim:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, true, game, 0)
            task.wait(0.01)
            vim:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, false, game, 0)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if getgenv().Boss and isCinematicActive() then continue end

        local mapFolder = workspace:FindFirstChild("CURRENT_MAP")
        local hasMap = mapFolder and #mapFolder:GetChildren() > 0

        if getgenv().AltAutoClicker and getgenv().Mob and (isPlayerInMission() or hasMap) and not isResultVisible() then
            pcall(function()
                local gunGUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild("GunGUI")
                if gunGUI then
                    local zone = gunGUI:FindFirstChild("ico_zone")
                    if zone then
                        zone.Visible = true
                        clickButton(zone)
                    end
                    local mobileBtns = gunGUI:FindFirstChild("MobileButtons")
                    if mobileBtns and mobileBtns:FindFirstChild("FireButton") then
                        mobileBtns.FireButton.Visible = true
                    end
                end
            end)
        end
    end
end)

----------------------------------------------------------------
-- ABILITY LOOP (Cinematic Aware)
----------------------------------------------------------------
task.spawn(function()
    local AbilityRE = game:GetService("ReplicatedStorage"):WaitForChild("AbilityRE")
    local lastAbility = 0
    local ABILITY_COOLDOWN = 0.5

    while task.wait() do
        if not getgenv().Ability or not getgenv().Mob or not isPlayerInMission() or isResultVisible() then
            continue
        end

        if getgenv().Boss and isCinematicActive() then continue end

        local hrp = game.Players.LocalPlayer.Character and
                    game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        if getgenv().Boss and getgenv().BossType == "Atomizer" then
            for _, v in pairs(workspace:GetChildren()) do
                if v.Name:find("BlackholeBall") or v.Name:find("BlackHoleBall") then
                    local ballPart = v:IsA("BasePart") and v or v:FindFirstChildWhichIsA("BasePart")
                    if ballPart and (ballPart.Position - hrp.Position).Magnitude <= 12 then
                        if tick() - lastAbility > 1.5 then
                            lastAbility = tick()
                            pcall(function() AbilityRE:FireServer("ACTIVATE") end)
                        end
                    end
                end
            end
        else
            if tick() - lastAbility >= ABILITY_COOLDOWN then
                lastAbility = tick()
                pcall(function() AbilityRE:FireServer("ACTIVATE") end)
            end
        end
    end
end)

----------------------------------------------------------------
-- UI CLOSER
----------------------------------------------------------------
task.spawn(function()
    while task.wait(0.5) do
        local plr = game.Players.LocalPlayer
        if not isResultVisible() then continue end

        local closed = false

        local mainMenu = plr.PlayerGui:FindFirstChild("MainMenu")
        if mainMenu and mainMenu.Enabled then
            local resFrame = mainMenu:FindFirstChild("ResultFrame")
            if resFrame and resFrame.Visible then
                local closeBtn
                for _, name in ipairs({"CloseButton","Close","OkButton","Continue","Exit"}) do
                    closeBtn = resFrame:FindFirstChild(name)
                    if closeBtn then break end
                end
                if not closeBtn then
                    for _, v in pairs(resFrame:GetDescendants()) do
                        if v:IsA("TextButton") or v:IsA("ImageButton") then
                            closeBtn = v break
                        end
                    end
                end
                if closeBtn then clickButton(closeBtn) closed = true end
            end
        end

        local missionComplete = plr.PlayerGui:FindFirstChild("MissionComplete")
        if missionComplete and missionComplete.Enabled then
            local mFrame = missionComplete:FindFirstChild("MainFrame")
            if mFrame and mFrame.Visible then
                local sFrame = mFrame:FindFirstChild("Frame")
                local searchRoot = sFrame or mFrame
                local closeBtn
                for _, name in ipairs({"CloseButton","Close","OkButton","Continue","Exit"}) do
                    closeBtn = searchRoot:FindFirstChild(name)
                    if closeBtn then break end
                end
                if not closeBtn then
                    for _, v in pairs(searchRoot:GetDescendants()) do
                        if v:IsA("TextButton") or v:IsA("ImageButton") then
                            closeBtn = v break
                        end
                    end
                end
                if closeBtn then clickButton(closeBtn) closed = true sendLobbyWebhook() task.wait(1.6) end
            end
        end

        if closed and getgenv().Days then
            task.wait(2)
            if isInLobby() and (tick() - lastStartTime > 5) then
                fireDaysRemote()
            end
        end
    end
end)

----------------------------------------------------------------
-- AUTOFARM
----------------------------------------------------------------
function autoFarm()
    -- Executioner Logic Helpers
    local function isVulnerableBossProp(obj)
        if not obj then return false end
        local hrp = obj:FindFirstChild("HumanoidRootPart") or (obj:IsA("BasePart") and obj)
        if hrp then
            local healthUI = hrp:FindFirstChild("Health")
            if healthUI and healthUI:IsA("BillboardGui") then
                return healthUI.Enabled == true
            end
        end
        return false
    end

    local function getExecutionerPhase(main)
        if not main then return "None" end
        if isVulnerableBossProp(main:FindFirstChild("BOX1")) or isVulnerableBossProp(main:FindFirstChild("BOX2")) then 
            return "Box" 
        end
        if isVulnerableBossProp(main:FindFirstChild("CRYSTAL")) then 
            return "Crystal" 
        end
        local lasers = main:FindFirstChild("LASERS")
        if lasers then
            for _, l in pairs(lasers:GetChildren()) do
                if isVulnerableBossProp(l) then return "Lasers" end
            end
        end
        return "None"
    end

    local atomizerPositions = { CFrame.new(105, 34, -172), CFrame.new(157, 34, -119) }
    local currentPosIndex = 1
    local lastSwitch = 0

    task.spawn(function()
        while task.wait() do
            if not getgenv().Mob then continue end
            
            local hrp = game.Players.LocalPlayer.Character and
                        game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end

            if getgenv().Boss and getgenv().BossType == "Atomizer" then
                for _, v in pairs(workspace:GetChildren()) do
                    if v.Name:find("BlackholeBall") or v.Name:find("BlackHoleBall") then
                        local ballPart = v:IsA("BasePart") and v or v:FindFirstChildWhichIsA("BasePart")
                        if ballPart and (ballPart.Position - hrp.Position).Magnitude <= 12
                           and (tick() - lastSwitch > 1.5) then
                            currentPosIndex = (currentPosIndex == 1) and 2 or 1
                            lastSwitch = tick()
                            getgenv().EvadeCount = getgenv().EvadeCount + 1
                            evadeCountLabel.Text = "Evades: " .. getgenv().EvadeCount .. (getgenv().EvadeCount >= 4 and " (CRATES ON)" or "/4")
                            statusLabel.Text = "Status: EVADING BLACKHOLE!"
                            pcall(function()
                                game:GetService("ReplicatedStorage"):WaitForChild("AbilityRE"):FireServer("ACTIVATE")
                            end)
                            posLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                        end
                    end
                end
                hrp.CFrame = atomizerPositions[currentPosIndex]
                posLabel.Text = "Pos: Atomizer " .. currentPosIndex
            else
                local map = workspace:FindFirstChild("CURRENT_MAP") and workspace.CURRENT_MAP:GetChildren()[1]
                
                if getgenv().Boss and getgenv().BossType == "Executioner" and map and map.Name == "Prison" then
                    local main = map:FindFirstChild("MAIN")
                    local phase = getExecutionerPhase(main)
                    
                    if phase == "Box" then
                        hrp.CFrame = CFrame.new(-80, 28 + 10, 147)
                        posLabel.Text = "Pos: Box +10"
                    elseif phase == "Crystal" then
                        hrp.CFrame = CFrame.new(160, 3 + 50, 138)
                        posLabel.Text = "Pos: Crystal +50"
                    elseif phase == "Lasers" then
                        hrp.CFrame = CFrame.new(7, 3 + 50, 143)
                        posLabel.Text = "Pos: Lasers +50"
                    else
                        if map:FindFirstChild("PLAYER_SPAWN") then
                            hrp.CFrame = map.PLAYER_SPAWN.CFrame * CFrame.new(0, 50, 0)
                            posLabel.Text = "Pos: Boss/Spawn +50"
                        end
                    end
                    posLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                else
                    if map and map:FindFirstChild("PLAYER_SPAWN") then
                        local yOffset = getgenv().Days and 60 or (getgenv().Survival and 45 or 50)
                        hrp.CFrame = map.PLAYER_SPAWN.CFrame * CFrame.new(0, yOffset, 0)
                        posLabel.Text = "Pos: Spawn +" .. yOffset
                        posLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    end
                end
            end
            hrp.Velocity = Vector3.zero
        end
    end)

    while task.wait() do
        if not getgenv().Mob then continue end
        
        local root = game.Players.LocalPlayer.Character and
                     game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local mapFolder = workspace:FindFirstChild("CURRENT_MAP")

        if not (mapFolder and root) then continue end

        local pList, nList, cList = {}, {}, {}
        local map = mapFolder:GetChildren()[1]

        -- Boss Logic
        if getgenv().Boss and getgenv().BossType == "Executioner" and map and map.Name == "Prison" then
            pcall(function()
                local props = map:FindFirstChild("PROPS")
                if props then
                    if props:FindFirstChild("ROOF") then props.ROOF:Destroy() end
                    if props:FindFirstChild("ROOFTOP") then props.ROOFTOP:Destroy() end
                end
            end)

            local main = map:FindFirstChild("MAIN")
            if main then
                for _, tName in ipairs({"BOX1", "BOX2", "CRYSTAL"}) do
                    local obj = main:FindFirstChild(tName)
                    if obj and isVulnerableBossProp(obj) then
                        local targetHRP = obj:FindFirstChild("HumanoidRootPart") or (obj:IsA("BasePart") and obj)
                        if targetHRP then table.insert(cList, targetHRP) end
                    end
                end
                
                if main:FindFirstChild("LASERS") then
                    for _, laser in pairs(main.LASERS:GetChildren()) do
                        if isVulnerableBossProp(laser) then
                            local targetHRP = laser:FindFirstChild("HumanoidRootPart") or (laser:IsA("BasePart") and laser)
                            if targetHRP then table.insert(cList, targetHRP) end
                        end
                    end
                end
            end

            -- Check specifically for Box or Laser vulnerability to block Zombie
            local blockZombieTeleport = false
            for _, tName in ipairs({"BOX1", "BOX2"}) do
                if isVulnerableBossProp(main:FindFirstChild(tName)) then
                    blockZombieTeleport = true
                    break
                end
            end
            
            if not blockZombieTeleport and main:FindFirstChild("LASERS") then
                for _, laser in pairs(main.LASERS:GetChildren()) do
                    if isVulnerableBossProp(laser) then
                        blockZombieTeleport = true
                        break
                    end
                end
            end

            -- 3. Zombie Boss Check
            -- Teleport if no Boxes/Lasers are active (allowing it to teleport alongside Crystal)
            if not blockZombieTeleport then
                local zombie = map:FindFirstChild("Zombie")
                if zombie then
                    local ff = zombie:FindFirstChild("FF")
                    if (not ff) or (ff and ff.Transparency == 1) then
                        local zHrp = zombie:FindFirstChild("HumanoidRootPart")
                        if zHrp then table.insert(cList, zHrp) end
                    end
                end
            end
        end

        if getgenv().Boss and getgenv().BossType == "Atomizer" then
            local arena = mapFolder:FindFirstChild("Arena") or (map and map:FindFirstChild("Arena"))
            if arena then
                if arena:FindFirstChild("Pillars") then arena.Pillars:Destroy() end
                for _, folder in pairs(arena:GetChildren()) do
                    if folder.Name == "CRYSTALS" then
                        for _, crystal in pairs(folder:GetChildren()) do
                            local targetHRP = crystal:FindFirstChild("HumanoidRootPart") or (crystal:IsA("BasePart") and crystal)
                            if targetHRP then table.insert(cList, targetHRP) end
                        end
                    end
                end
            end
        end

        local scanned = {}
        local function scan(v)
            if scanned[v] then return end
            scanned[v] = true

            if v.Name == "Zombie" and v.Parent == map and getgenv().BossType == "Executioner" then
                return
            end

            if getgenv().EvadeCount >= 4 and v.Name == "Crate" and v:IsA("Model") then
                local crateHRP = v:FindFirstChild("HumanoidRootPart") or v:FindFirstChildWhichIsA("BasePart")
                if crateHRP then table.insert(pList, crateHRP) return end
            end

            if v:IsA("Model") and v:FindFirstChild("HumanoidRootPart") and not v:FindFirstChild("TEAM") then
                if isValidTarget(v) then
                    if getgenv().FrequentPriority and isPriority(v) then
                        table.insert(pList, 1, v.HumanoidRootPart)
                    elseif isPriority(v) then
                        table.insert(pList, v.HumanoidRootPart)
                    else
                        table.insert(nList, v.HumanoidRootPart)
                    end
                end
            elseif (v.Name == "Money" or v.Name == "MedKit") and v:FindFirstChild("MAIN") then
                v.MAIN.CFrame = root.CFrame
            end
        end

        if map then
            for _, v in pairs(map:GetDescendants()) do scan(v) end
            for _, v in pairs(mapFolder:GetChildren()) do scan(v) end

            if getgenv().ZombiesFolder then
                local zFolder = map:FindFirstChild("ZombiesSpawnedIn") or map:FindFirstChild("Zombies")
                if zFolder then
                    for _, v in pairs(zFolder:GetDescendants()) do scan(v) end
                end
            end

            if getgenv().Days and map:FindFirstChild("RESUPPLY") then
                pcall(function()
                    local res = map.RESUPPLY
                    if res:FindFirstChild("SUPPLY_PICKUP") then
                        if res.SUPPLY_PICKUP:IsA("BasePart") then
                            res.SUPPLY_PICKUP.CFrame = root.CFrame
                        else
                            res.SUPPLY_PICKUP:SetPrimaryPartCFrame(root.CFrame)
                        end
                        firetouchinterest(res.SUPPLY_PICKUP, root, 0)
                        task.wait()
                        firetouchinterest(res.SUPPLY_PICKUP, root, 1)
                    end
                    if res:FindFirstChild("SupplyBox") then
                        res.SupplyBox.CFrame = root.CFrame
                    end
                end)
            end

            if getgenv().Survival then
                pcall(function()
                    for _, v in pairs(map:GetDescendants()) do
                        if v.Name == "Objective" or v.Name == "Package" or v.Name == "Crate" then
                            if v:IsA("BasePart") then
                                v.CFrame = root.CFrame
                            elseif v:IsA("Model") and v.PrimaryPart then
                                v:SetPrimaryPartCFrame(root.CFrame)
                            end
                        end
                    end
                end)
            end
        end

        local finalTargets = {}
        for _, t in ipairs(cList) do table.insert(finalTargets, t) end
        if getgenv().PriorityOnly then
            for _, t in ipairs(pList) do table.insert(finalTargets, t) end
        elseif getgenv().FrequentPriority then
            local toAdd = (#pList > 0) and pList or nList
            for _, t in ipairs(toAdd) do table.insert(finalTargets, t) end
        else
            for _, t in ipairs(pList) do table.insert(finalTargets, t) end
            for _, t in ipairs(nList) do table.insert(finalTargets, t) end
        end

        local totalTargets = 0
        for _, t in ipairs(finalTargets) do
            pcall(function()
                t.Anchored = true
                t.CFrame = (root.CFrame * CFrame.new(2.5, -5, -7)) * CFrame.Angles(0, math.pi, 0)
                totalTargets = totalTargets + 1
            end)
        end

        zombiesLabel.Text = "Zombies/Obj: " .. totalTargets

        if getgenv().Targeting and #finalTargets > 0 then
            if not (getgenv().Boss and isCinematicActive()) then
                local bestTarget = finalTargets[1]
                local aimPart = (getgenv().AimPart == "Head" and bestTarget.Parent and bestTarget.Parent:FindFirstChild("Head"))
                                or bestTarget
                workspace.CurrentCamera.CFrame = CFrame.new(
                    workspace.CurrentCamera.CFrame.Position,
                    aimPart.Position
                )
                trackingLabel.Text = "Tracking: " .. (bestTarget.Parent and bestTarget.Parent.Name or "Unknown")
            end
            
            if not statusLabel.Text:find("EVADING") and not isCinematicActive() then
                statusLabel.Text = "Status: Farming..."
            end
        else
            trackingLabel.Text = "Tracking: None"
            if not statusLabel.Text:find("EVADING") and not isCinematicActive() then
                statusLabel.Text = "Status: Waiting..."
            end
        end
    end
end

----------------------------------------------------------------
-- LOBBY LOGIC
----------------------------------------------------------------
local function isVideoFrameVisible()
    local success, isVis = pcall(function()
        return game:GetService("Players").LocalPlayer.PlayerGui.MainMenu.VideoFrame.Visible
    end)
    return success and isVis
end

task.spawn(function()
    while task.wait(1) do
        if not getgenv().Mob then continue end
        
        local inLobby   = isInLobby()
        local inMission = isPlayerInMission()
        local bugged    = isBuggedState()
        local videoVis  = isVideoFrameVisible()

        lobbyLabel.Text  = "Lobby: " .. (inLobby and "Yes" or (bugged and "Bugged" or "No"))

        if bugged and getgenv().Days and (tick() - lastStartTime > 10) then
            fireDaysRemote()
        elseif (tick() - lastStartTime > 20) and (getgenv().Boss or getgenv().Survival) then
            getgenv().EvadeCount = 0
            evadeCountLabel.Text = "Evades: 0/4"
            sendLobbyWebhook()

            if getgenv().Boss then
                lastStartTime = tick()
                pcall(function()
                    game:GetService("ReplicatedStorage"):WaitForChild("PartySystem"):FireServer("CREATE", {
                        RoomID = 9696969691, Boss = getgenv().BossType, Limit = 4, Status = false, Password = generateRandomPassword(15)
                    })
                end)
                task.wait(1)
                pcall(function() game:GetService("ReplicatedStorage"):WaitForChild("PartySystem"):FireServer("START") end)
                task.wait()
                applyFastWeapons()
            elseif getgenv().Survival then
                lastStartTime = tick()
                pcall(function()
                    game:GetService("ReplicatedStorage"):WaitForChild("PartySystem2"):FireServer("CREATE", {
                        Password = generateRandomPassword(15), Limit = 4, Status = false, RoomID = 290218770, Difficulty = "Hard", Map = "Glacier"
                    })
                end)
                task.wait(1)
                pcall(function() game:GetService("ReplicatedStorage"):WaitForChild("PartySystem2"):FireServer("START") end)
                task.wait()
                applyFastWeapons()
            end
        elseif inLobby and (tick() - lastStartTime > 20) and getgenv().Days then
            getgenv().EvadeCount = 0
            evadeCountLabel.Text = "Evades: 0/4"
            sendLobbyWebhook()
            fireDaysRemote()
        end
    end
end)

task.spawn(autoFarm)
