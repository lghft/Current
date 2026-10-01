local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------
local POLL_INTERVAL = 0.1     -- how often to check for an offer
local SETTLE_DELAY = 0.2      -- wait for the GUI to finish animating
local RETRY_AFTER = 2         -- if the same offer is still up after this many seconds, try again
local REMOTE_ARG = "name"     -- "name" or "index": what RespondToQuery expects. Flip if picks don't register.
local DEBUG = false

local function log(...)
    if DEBUG then
        print("[AUTO-PICKER]", ...)
    end
end

--------------------------------------------------------------------
-- PRIORITY LISTS
-- Names are matched against the card's displayed name (spaces,
-- apostrophes and other non-letters are ignored, case-insensitive).
--------------------------------------------------------------------
local PRIORITY_BUFFS = {
    "Reinforcements",   -- Legendary (wave 100+): +1 unit placement, any unit.
    "ParanormalReach",  -- Epic: Paranormal towers gain 10% range.
    "SharpenedEdges",   -- Rare: All towers deal 10/15/20/30% more damage (tiers).
    "Overclock",        -- Rare: All towers attack 10/15/20% faster (tiers).
    "HolyFervor",       -- Epic: Holy towers deal 15% more damage.
    "Requisition",      -- Epic: Military towers deal 15% more damage.
    "GraveRite",        -- Epic: Undead towers deal 15% more damage.
    "DemonPact",        -- Epic: Demon towers deal 15% more damage.
    "FortifytheGate",   -- Epic ("Fortify the Gate"): +25/35/50/75/100 base health (tiers).
}

local PRIORITY_DEBUFFS = {
    "OpenTheSecondGate", -- Rare: Second track opens early (gives way at wave 9 regardless).
    "OpenTheThirdGate",  -- Epic: Third track opens early (gives way at wave 24 regardless). Requires second gate open.
    "OpenTheFourthGate", -- Legendary: Fourth track opens early (gives way at wave 45 regardless). Requires third gate open.
    "DemonWard",         -- Epic (wave 24+): Enemies take 40/60/80/95% less damage from Demon towers. Forever.
    "UndeadWard",        -- Epic (wave 24+): Enemies take 40/60/80/95% less damage from Undead towers. Forever.
    "AdrenalSurge",      -- Common: Enemies move 10/20/30/40/55/70% faster (tiers).
    "ParanormalWard",    -- Epic (wave 24+): Enemies take 40/60/80/95% less damage from Paranormal towers. Forever.
    "HolyWard",          -- Epic (wave 24+): Enemies take 40/60/80/95% less damage from Holy towers. Forever.
    "MilitaryWard",      -- Epic (wave 24+): Enemies take 40/60/80/95% less damage from Military towers. Forever.
    "ThickHide",         -- Common: Enemies gain 10% health (waves up to 75), or 5% health (wave 76+). Repeatable.
}

local PRIORITY_MOBS = {
    "EvilEye",          -- Epic: A Gazer joins every third wave. Its eye stays shut... for now.
    "DemonPack",        -- Rare (max wave 25): 3 more Demon Minions every wave.
    "ClipperBloom",     -- Common (max wave 25): 4 more Clippers every wave.
    "SporeStorm",       -- Common (max wave 25): 6 more Spores every wave.
    "GargoyleRoost",    -- Rare (waves 22-50): 3 more Gargoyle Minions every wave.
    "CrimsonBloom",     -- Epic (waves 22-50): 2 more Red Spores every wave.
    "ChompersToll",     -- Epic ("Chomper's Toll", waves 47-75): Two Chompers join every wave.
    "WildHunt",         -- Epic: The Deer joins every third wave. It only watches... for now.
    "NightTerrors",     -- Epic: A Bat joins every third wave. It sleeps... for now.
    "HiveGrowth",       -- Legendary (waves 47-75): 2 more Bees every wave. Slow, and very hard to put down.
    "SleeplessEye",     -- Rare (waves 55-120, needs Evil Eye): A Gazer every 2 waves, then every single wave.
    "QuickenedHunt",    -- Rare (waves 70-120, needs Wild Hunt): The Deer every 2 waves, then every single wave.
    "PetrifyingGaze",   -- Epic (wave 75+, needs Evil Eye): Gazers have a 25/50/75/100% chance to stun towers.
    "PrimalCharge",     -- Epic (wave 90+, needs Wild Hunt): The Deer has a 25/50/75/100% chance to charge.
    "RestlessRoost",    -- Rare (waves 40-120, needs Night Terrors): A Bat every 2 waves, then every single wave.
    "SnatchingScreech", -- Epic (wave 60+, needs Night Terrors): Bats have a 25/50/75/100% chance to snatch towers.
}

--------------------------------------------------------------------
-- SCORING
--------------------------------------------------------------------
-- Lowercase and strip everything that isn't a letter, so
-- "Chomper's Toll" and "ChompersToll" both become "chomperstoll".
local function normalize(name)
    return (name:lower():gsub("[^%a]", ""))
end

local function getScore(cardName, priorityList)
    local normalizedCard = normalize(cardName)
    for rank, priorityName in ipairs(priorityList) do
        if normalize(priorityName) == normalizedCard then
            return rank
        end
    end
    return 999
end

local function listContains(list, normalizedCard)
    for _, name in ipairs(list) do
        if normalize(name) == normalizedCard then
            return true
        end
    end
    return false
end

local function pickBestCard(cardNames)
    local bestIndex = 1
    local bestScore = math.huge

    for index, cardName in ipairs(cardNames) do
        local normalizedCard = normalize(cardName)
        local priorityList = PRIORITY_BUFFS

        if listContains(PRIORITY_MOBS, normalizedCard) then
            priorityList = PRIORITY_MOBS
        elseif listContains(PRIORITY_DEBUFFS, normalizedCard) then
            priorityList = PRIORITY_DEBUFFS
        end

        local score = getScore(cardName, priorityList)
        log("Scoring", cardName, "=", score)
        if score < bestScore then
            bestScore = score
            bestIndex = index
        end
    end

    return bestIndex
end

--------------------------------------------------------------------
-- CLICKING
--------------------------------------------------------------------
local function clickButton(guiObject)
    local inset1, inset2 = GuiService:GetGuiInset()
    local insetOffset = inset1 - inset2
    local topLeft = guiObject.AbsolutePosition + insetOffset
    local center = topLeft + (guiObject.AbsoluteSize / 2)
    local X = center.X + 15
    local Y = center.Y

    VirtualInputManager:SendMouseButtonEvent(X, Y, 0, true, game, 0)
    task.wait(0.1)
    VirtualInputManager:SendMouseButtonEvent(X, Y, 0, false, game, 0)
    task.wait(0.5)
    log("Clicked:", guiObject:GetFullName())
end

local function fireRemote(cardName, cardIndex)
    local remote = ReplicatedStorage.Modules.Remotes.RemoteEvent.RespondToQuery
    local arg = (REMOTE_ARG == "index") and tostring(cardIndex) or tostring(cardName)
    remote:FireServer("GauntletOffer", arg)
end

--------------------------------------------------------------------
-- GUI HELPERS
--------------------------------------------------------------------
-- Returns the GauntletOffer object only if it exists AND is actually showing.
local function getVisibleOffer()
    local mainHud = PlayerGui:FindFirstChild("MainHud")
    if not mainHud then return nil end

    local offer = mainHud:FindFirstChild("GauntletOffer")
    if not offer then return nil end

    if offer:IsA("GuiObject") and not offer.Visible then return nil end
    if offer:IsA("LayerCollector") and not offer.Enabled then return nil end
    if mainHud:IsA("LayerCollector") and not mainHud.Enabled then return nil end

    return offer
end

local function getListings(cardRow)
    local listings = {}
    for _, child in ipairs(cardRow:GetChildren()) do
        if child.Name:match("^listing%d+$") then
            table.insert(listings, child)
        end
    end
    -- GetChildren order isn't guaranteed; sort by the number in the name
    table.sort(listings, function(a, b)
        return tonumber(a.Name:match("%d+")) < tonumber(b.Name:match("%d+"))
    end)
    return listings
end

local function getCardNames(listings)
    local names = {}
    for _, listing in ipairs(listings) do
        local content = listing:FindFirstChild("Content")
        local cardName = content and content:FindFirstChild("CardName")
        if cardName and cardName:IsA("TextLabel") then
            table.insert(names, cardName.Text)
        else
            -- keep indices aligned with listings even if one is missing
            table.insert(names, "")
        end
    end
    return names
end

--------------------------------------------------------------------
-- PICK LOGIC
--------------------------------------------------------------------
local lastSelection = ""
local lastPickTime = 0
local debounce = false

local function performPick(cardRow)
    -- Re-read everything after the settle delay so we act on the current state
    local listings = getListings(cardRow)
    if #listings == 0 then return end

    local cardNames = getCardNames(listings)
    local anyName = false
    for _, n in ipairs(cardNames) do
        if n ~= "" then anyName = true break end
    end
    if not anyName then return end

    local bestIndex = pickBestCard(cardNames)
    local bestName = cardNames[bestIndex]
    local listing = listings[bestIndex]
    if not listing then
        warn("[AUTO-PICKER] No listing at index", bestIndex)
        return
    end

    lastSelection = bestName
    lastPickTime = os.clock()
    print("[CLICK] Picking card", bestIndex, ":", bestName)

    -- Server remote
    local okRemote, errRemote = pcall(fireRemote, bestName, bestIndex)
    if not okRemote then
        warn("[AUTO-PICKER] Remote failed:", errRemote)
    end

    -- GUI click fallbacks (each isolated so one failure can't stop the rest)
    local button = listing:FindFirstChild("Button") or listing

    if button:IsA("GuiButton") then
        if firesignal then
            pcall(function() firesignal(button.Activated) end)
            pcall(function() firesignal(button.MouseButton1Click) end)
        end
    end

    pcall(clickButton, button)
end

local function watchGauntletOffer()
    while true do
        task.wait(POLL_INTERVAL)

        local offer = getVisibleOffer()

        -- Offer gone: reset so the next offer is always treated fresh
        if not offer then
            lastSelection = ""
            continue
        end

        if debounce then continue end

        local cardRow = offer:FindFirstChild("CardRow")
        if not cardRow then continue end

        local listings = getListings(cardRow)
        if #listings == 0 then continue end

        -- Same offer still on screen after a pick? Only retry after a timeout.
        local names = getCardNames(listings)
        local best = names[pickBestCard(names)]
        if best ~= "" and best == lastSelection and (os.clock() - lastPickTime) < RETRY_AFTER then
            continue
        end

        debounce = true
        task.spawn(function()
            task.wait(SETTLE_DELAY)

            -- pcall guarantees debounce is always released, even on error
            local ok, err = pcall(performPick, cardRow)
            if not ok then
                warn("[AUTO-PICKER] Error:", err)
            end

            task.wait(0.5)
            debounce = false
        end)
    end
end

print("[Executor] Card Priority Picker Loaded (GUI Mode)")
task.spawn(watchGauntletOffer)
