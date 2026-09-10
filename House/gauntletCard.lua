local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local PRIORITY_BUFFS = {
    "Reinforcements",
    "SharpenedEdges",
    "Overclock",
    "DemonPact",
    "ParanormalReach",
    "FortifytheGate",
    "HolyFervor",
    "Requisition",
    "GraveRite",
}

local PRIORITY_DEBUFFS = {
    "OpenSecondGate",
    "OpenThirdGate",
    "OpenFourthGate",
    "ThickHide",
    "AdrenalSurge",
    "HolyWard",
    "MilitaryWard",
    "UndeadWard",
    "ParanormalWard",
    "DemonWard",
}

local PRIORITY_MOBS = {
    "DemonPack",
    "ClipperBloom",
    "SporeStorm",
    "GargoyleRoost",
    "CrimsonBloom",
    "ChompersToll",
    "HiveGrowth",
    "NightTerrors",
    "WildHunt",
    "EvilEye",
}

local function getScore(cardName, priorityList)
    -- Remove spaces for comparison
    local normalizedCard = cardName:gsub(" ", ""):lower()
    
    for rank, priorityName in ipairs(priorityList) do
        local normalizedPriority = priorityName:gsub(" ", ""):lower()
        if normalizedPriority == normalizedCard then
            return rank
        end
    end
    return 999
end

function clickButton(ClickOnPart)
    local vim = game:GetService("VirtualInputManager")
    local inset1, inset2 = game:GetService("GuiService"):GetGuiInset()
    local insetOffset = inset1 - inset2
    local part = ClickOnPart
    local topLeft = part.AbsolutePosition + insetOffset
    local center = topLeft + (part.AbsoluteSize / 2)
    local X = center.X + 15
    local Y = center.Y
    vim:SendMouseButtonEvent(X, Y, 0, true, game, 0)
    task.wait(0.1)
    vim:SendMouseButtonEvent(X, Y, 0, false, game, 0)
    task.wait(1)
    Notify("Print", "Clicked: " .. tostring(ClickOnPart))
end

local function pickBestCard(cardNames)
    local bestIndex = 1
    local bestScore = 9999

    for index, cardName in ipairs(cardNames) do
        local normalizedCard = cardName:gsub(" ", ""):lower()
        local priorityList = PRIORITY_BUFFS
        
        -- Check if it's a mob/debuff
        for _, mobName in ipairs(PRIORITY_MOBS) do
            if mobName:lower() == normalizedCard then
                priorityList = PRIORITY_MOBS
                break
            end
        end
        for _, debuffName in ipairs(PRIORITY_DEBUFFS) do
            if debuffName:lower() == normalizedCard then
                priorityList = PRIORITY_DEBUFFS
                break
            end
        end

        local score = getScore(cardName, priorityList)
        --print("[DEBUG] Scoring", cardName, "as", normalizedCard, "= score", score)
        if score < bestScore then
            bestScore = score
            bestIndex = index  -- Store index instead of name
        end
    end

    return bestIndex  -- Return the index
end

local lastSelection = ""
local debounce = false

-- Watch for GauntletOffer GUI appearing
local function watchGauntletOffer()
    while true do
        task.wait(0.1)
        
        if debounce then continue end
        
        -- Check if GauntletOffer GUI exists
        local mainHud = PlayerGui:FindFirstChild("MainHud")
        if not mainHud then continue end
        
        local gauntletOffer = mainHud:FindFirstChild("GauntletOffer")
        if not gauntletOffer then continue end
        
        local cardRow = gauntletOffer:FindFirstChild("CardRow")
        if not cardRow then continue end
        
        -- Get all listing children (listing1, listing2, listing3, etc.)
        local listings = {}
        for _, child in ipairs(cardRow:GetChildren()) do
            if child.Name:match("^listing%d+$") then
                table.insert(listings, child)
            end
        end
        
        if #listings == 0 then continue end
        
        -- Extract card names from each listing
        local cardNames = {}
        for _, listing in ipairs(listings) do
            local content = listing:FindFirstChild("Content")
            if content then
                local cardName = content:FindFirstChild("CardName")
                if cardName and cardName:IsA("TextLabel") then
                    table.insert(cardNames, cardName.Text)
                    --print("[DEBUG] Found card:", cardName.Text)
                end
            end
        end
        
        if #cardNames == 0 then continue end
        
        --print("[INFO] Cards available:", table.concat(cardNames, ", "))
        
        debounce = true
        task.spawn(function()
            task.wait(0.2) -- Give GUI time to settle
            
            local bestCardIndex = pickBestCard(cardNames)
            local bestCardName = cardNames[bestCardIndex]
            --print("[AUTO-PICKER] Best card:", bestCardName, "(index", bestCardIndex, ")")
            
            if bestCardName ~= lastSelection then
                lastSelection = bestCardName
                
                -- Get listings in order
                local listings = {}
                for _, child in ipairs(cardRow:GetChildren()) do
                    if child.Name:match("^listing%d+$") then
                        table.insert(listings, child)
                    end
                end
                
                -- Click by index (no name matching needed)
                if listings[bestCardIndex] then
                    local listing = listings[bestCardIndex]
                    local button = listing:FindFirstChild("Button") or listing
                    
                    print("[CLICK] Clicking card at index", bestCardIndex, ":", bestCardName)
                    task.spawn(function()
                        local chooseCard = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.RespondToQuery
                        chooseCard:FireServer("GauntletOffer",tostring(bestCardName)) 
                    end)
                    local chooseCard = game:GetService("ReplicatedStorage").Modules.Remotes.RemoteEvent.RespondToQuery
                    chooseCard:FireServer("GauntletOffer",tostring(bestCardIndex)) 

                    if button:IsA("GuiButton") or button:IsA("TextButton") then
                        firesignal(button.Activated)
                        pcall(function()
                            clickButton(button)
                        end)
                        pcall(function()
                            button.MouseButton1Click:Fire()
                        end)
                    else
                        pcall(function()
                            listing.MouseButton1Click:Fire()
                        end)
                    end
                    
                    task.wait(0.5)
                else
                    print("[ERROR] Could not find listing at index", bestCardIndex)
                end
            end
            
            task.wait(0.5)
            debounce = false
        end)
    end
end

print("[Executor] Card Priority Picker Loaded (GUI Mode)")
task.spawn(watchGauntletOffer)
