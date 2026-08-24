local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local webhookUrl = getgenv().WEBHOOK_URL or "https://discord.com/api/webhooks/1414475376230535199/F6V5IZJkOUMdxd-ZdC32JdlaTw-FGDz-raRMGW7a6FsYTmYtRkqOSfLy123hat3xSNR1"

-- Load required modules based on your dumped paths
local inventoryGetters = require(ReplicatedStorage.Modules.Inventory.inventory_getters)
local XpSystem = require(ReplicatedStorage.Modules.XpSystem)
local Factions = require(ReplicatedStorage.Databases.Factions)

-- Safely attempt to get HotbarContext for the active faction
local HotbarContext = pcall(function() 
    return require(ReplicatedStorage.Modules.Ui.App.Contexts.HotbarContext) 
end)

local player = Players.LocalPlayer

-- Helper function to generate an ASCII progress bar
local function createProgressBar(current, max, length)
    length = length or 10
    current = tonumber(current) or 0
    max = tonumber(max) or 1
    if max <= 0 then max = 1 end
    
    local percentage = math.clamp(current / max, 0, 1)
    local filledCount = math.floor(percentage * length)
    local emptyCount = length - filledCount
    
    local bar = string.rep("█", filledCount) .. string.rep("░", emptyCount)
    local percentText = math.floor(percentage * 100) .. "%"
    
    return string.format("%s `[%d/%d]` (%s)", bar, current, max, percentText)
end

local function sendWebhook()
    local success, mainLevel, mainExpBarText, factionName, factionLevel, factionExpBarText, inventoryData = pcall(function()
        -- 1. Main Level & XP Calculation
        local mainXp = XpSystem.getXp("Main", player) or 0
        local mLevel = XpSystem.xpToLevel("Main", mainXp)
        local mBaseXp = XpSystem.levelToXp(mLevel)
        local mNextXp = math.max(1, XpSystem.levelToXp(mLevel + 1) - mBaseXp)
        local mainCurrentXp = mainXp - mBaseXp
        local mExpBar = createProgressBar(mainCurrentXp, mNextXp, 10)
        
        -- 2. Determine Current Faction & Stats
        local currentFactionKey = "Main"
        if HotbarContext and pcall(function() return React end) then
            local successCtx, contextVal = pcall(function()
                return React.useContext(HotbarContext.Consumer).faction
            end)
            if successCtx and contextVal then
                currentFactionKey = contextVal
            end
        end
        
        -- Get faction display name
        local factionData = Factions[currentFactionKey]
        local fName = factionData and factionData.name or currentFactionKey
        
        -- Calculate Faction Level & XP
        local fXp = XpSystem.getXp(currentFactionKey, player) or 0
        local fLevel = XpSystem.xpToLevel(currentFactionKey, fXp)
        local fBaseXp = XpSystem.levelToXp(fLevel)
        local fNextXp = math.max(1, XpSystem.levelToXp(fLevel + 1) - fBaseXp)
        local factionCurrentXp = fXp - fBaseXp
        local fExpBar = createProgressBar(factionCurrentXp, fNextXp, 10)

        -- 3. Fetch Inventory
        local inv = inventoryGetters.getInventory(player)
        
        return mLevel, mExpBar, fName, fLevel, fExpBar, inv
    end)

    if not success then
        warn("Failed to fetch player stats or inventory data.")
        return
    end

    -- Define target inventory items to extract
    local targetItems = {
        ["Coins"] = "Coins",
        ["VoodooTokens"] = "VoodooTokens",
        ["PurgeCoins"] = "PurgeCoins"
    }

    local foundItems = {}
    if inventoryData then
        for itemId, itemData in pairs(inventoryData) do
            if targetItems[itemId] then
                local amount = itemData.amount or 1
                table.insert(foundItems, string.format("`%s:%d`", itemId, amount))
            end
        end
    end

    local inventoryText = #foundItems > 0 and table.concat(foundItems, ", ") or "None found"

    -- Construct the payload for Discord
    local data = {
        ["content"] = "",
        ["embeds"] = {{
            ["title"] = "📊 Player Status & Inventory",
            ["color"] = 3447003,
            ["fields"] = {
                {
                    ["name"] = "Display Name",
                    ["value"] = "||" .. player.DisplayName .. "||",
                    ["inline"] = true
                },
                {
                    ["name"] = "Username",
                    ["value"] = "||" .. player.Name .. "||",
                    ["inline"] = true
                },
                {
                    ["name"] = "Main Level (" .. tostring(mainLevel or 1) .. ")",
                    ["value"] = tostring(mainExpBarText),
                    ["inline"] = false
                },
                -- Faction Information (Placed above inventory)
                {
                    ["name"] = "Faction (" .. tostring(factionName) .. ") Level (" .. tostring(factionLevel or 1) .. ")",
                    ["value"] = tostring(factionExpBarText),
                    ["inline"] = false
                },
                -- Inventory Information
                {
                    ["name"] = "Target Inventory Items",
                    ["value"] = inventoryText,
                    ["inline"] = false
                }
            }
        }}
    }

    local jsonBody = HttpService:JSONEncode(data)
    local requestMethod = (syn and syn.request) or (http and http.request) or http_request

    if requestMethod then
        requestMethod({
            Url = webhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = jsonBody
        })
    else
        pcall(function()
            HttpService:PostAsync(webhookUrl, jsonBody, Enum.HttpContentType.ApplicationJson)
        end)
    end
end

-- Execute the webhook function
sendWebhook()
