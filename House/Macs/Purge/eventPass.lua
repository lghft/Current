local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Require modules based on your decompile layout
local BattlePasses = require(ReplicatedStorage.Databases.BattlePasses)
local BattlePassModule = require(ReplicatedStorage.Modules.BattlePass)

-- Change this if your battle pass uses a different identifier string
local passId = "PurgePass" 

local function autoClaimAndReset()
    local passConfig = BattlePasses[passId]
    if not passConfig or not passConfig.tiers then return end

    local allClaimed = true

    -- Loop through all tiers in the battle pass
    for tierIndex, _ in pairs(passConfig.tiers) do
        -- Check if we can claim this specific tier
        if BattlePassModule.canClaim(passId, tierIndex, player) then
            print("Auto-claiming Battle Pass tier: " .. tostring(tierIndex))
            -- Fire the client claim function found in your module
            BattlePassModule.client.claim(passId, tierIndex)
            allClaimed = false
            task.wait(0.5) -- Small delay to prevent network spamming
        elseif not BattlePassModule.isClaimed(passId, tierIndex, player) then
            allClaimed = false
        end
    end

    -- If all rewards are claimed, check if we can reset the battle pass
    if allClaimed or BattlePassModule.isComplete(passId, player) then
        if BattlePassModule.canReset(passId, player) then
            print("All rewards claimed. Resetting Battle Pass...")
            BattlePassModule.client.reset(passId)
        end
    end
end

-- Run continuously or trigger on an interval / event loop
task.spawn(function()
    while true do
        pcall(autoClaimAndReset)
        task.wait(5) -- Checks every 5 seconds
    end
end)
