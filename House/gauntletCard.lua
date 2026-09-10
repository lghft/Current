local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remote = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Remotes"):WaitForChild("RemoteEvent"):WaitForChild("RespondToQuery")

-- Priority order: Index 1 is top priority
local PRIORITY_BUFFS = {
    "Reinforcements",   -- Extra unit placement (+1)
    "Sharpened Edges",  -- +% Tower Damage
    "Overclock",        -- +% Tower Speed
    "Demon Pact",       -- Demon Tower Damage
    "Paranormal Reach", -- Paranormal Range
    "Fortify the Gate", -- +Base Health
    
    "Holy Fervor",      -- Holy Tower Damage
    "Requisition",      -- Military Tower Damage
    "Grave Rite",       -- Undead Tower Damage
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
    "ClipperBloom",
    "SporeStorm",
    "DemonPack",
    "GargoyleRoost",
    "CrimsonBloom",
    "ChompersToll",
    "HiveGrowth",
    "NightTerrors",
    "WildHunt",
    "EvilEye",
}

local function getScore(card, priorityList)
    local id = card.id or ""
    local name = card.name or ""
    
    for rank, priorityName in ipairs(priorityList) do
        if priorityName:lower() == id:lower() or priorityName:lower() == name:lower() then
            return rank
        end
    end
    return 999
end

local function pickBestCard(cards)
    local bestCard = cards[1]
    local bestScore = 9999

    for _, card in ipairs(cards) do
        local priorityList = PRIORITY_BUFFS
        
        -- Categorize into Mobs, Buffs, or Debuffs
        if card.spawn or card.spawn_every_wave or card.ability then
            priorityList = PRIORITY_MOBS
        elseif card.kind == "debuff" then
            priorityList = PRIORITY_DEBUFFS
        end

        local score = getScore(card, priorityList)
        if score < bestScore then
            bestScore = score
            bestCard = card
        end
    end

    return bestCard
end

-- ============================================================================
-- EXECUTOR UI HOOK
-- Intercepts React components as they render
-- ============================================================================
local GauntletUI = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Ui"):WaitForChild("App"):WaitForChild("GauntletOffer"):WaitForChild("GauntletOfferInterface")
local originalFunc = require(GauntletUI)

-- Hook the React component when it's rendered in-game
local function autoPick(props)
    if props and props.cards and #props.cards > 0 then
        task.spawn(function()
            local best = pickBestCard(props.cards)
            if best then
                print("[Auto-Picker] Voting for:", best.name or best.id)
                Remote:FireServer("GauntletOffer", best.id)
            end
        end)
    end
end

-- Hook requirement
hookfunction(originalFunc, function(props)
    autoPick(props)
    return originalFunc(props)
end)

print("[Executor] Card Priority Picker Loaded Successfully!")
