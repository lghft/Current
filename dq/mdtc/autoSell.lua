repeat task.wait() until game:IsLoaded()
local plr = game.Players.LocalPlayer
local userId = plr.UserId

if userId ~= 1032280386 or userId ~= 8488618320 then 
    print("wrong ID") 
    return 
end

-- ==========================================
-- AUTO-SELL CONFIGURATION
-- ==========================================
_G.autosell = true
_G.testSell = false
_G.keep_items_level_requirement = 186
_G.keep2spells = true

_G.keep_items_from_class = {
    ["physical"] = false,
    ["mage"] = false,
}

_G.keeprarities = {
    ['ultimate'] = true,
    ['legendary'] = true,
    ['epic'] = false,
    ['rare'] = false,
    ['uncommon'] = false,
    ['common'] = false,
}

_G.itemlist = {
    ["Valhalla Mage Helmet"] = {"epic", "rare", "uncommon"},
    ["Valhalla Mage Armor"] = {"epic", "rare", "uncommon"},
    ["Valhalla Warrior Helmet"] = {"epic", "rare", "uncommon"},
    ["Valhalla Warrior Armor"] = {"epic", "rare", "uncommon"},

    ["Valhalla Guardian Helmet"] = {"epic", "rare"},
    ["Valhalla Guardian Armor"] = {"epic", "rare"},
    
    ["Staff of the North"] = {"epic", "rare"},
    ["Frost Giant Greataxe"] = {"epic", "rare"},
    ["Mjolnir"] = {"legendary"},
    ["Gungnir"] = {"legendary"},
    ["Hofund"] = {"ultimate"},
    ["Laevateinn"] = {"ultimate"},
    
    ["Enhanced Inner Rage"] = {"legendary"},
    ["Enhanced Inner Focus"] = {"legendary"},
}

-- ==========================================
-- WEBHOOK CONFIGURATION
-- ==========================================
local WEBHOOK_URL = "https://discord.com/api/webhooks/1559062127078285312/TOZpD3Uy0TVMc-BueguA6sNdQ6v3AnT4BWzPrdzENqR24tHm1W5iHVFk2PTQcmlmXpMh"

-- ==========================================
-- INVENTORY FUNCTIONS (DEFINED FIRST)
-- ==========================================

local function getPlayerInvy()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local success, inventoryData = pcall(function()
        return ReplicatedStorage.remotes.reloadInvy:InvokeServer()
    end)
    
    if success and inventoryData then
        return inventoryData
    else
        warn("ERROR: Failed to retrieve inventory data from server!")
        return
    end
end

local getplayerinvy = getPlayerInvy

local function isItemEquipped(item)
    if not item then
        return false
    end
    
    if item.equipped == nil then
        return false
    end

    if item.equipped == true then
        return true
    end

    if type(item.equipped) == "table" then
        for key, val in pairs(item.equipped) do
            if val == true then
                return true
            end
        end
    end

    return false
end

local function getItemType(v, includeHealth)
    if v.health == nil then
        if (v.spellPower or 0) < (v.physicalDamage or 0) then
            return "physical"
        else
            return "mage"
        end
    else
        if (v.spellPower or 0) > (v.physicalPower or 0) then
            if includeHealth then
                if (v.spellPower or 0) > (v.health or 0) then
                    return "mage"
                else
                    return "guardian"
                end
            else
                return "mage"
            end
        else
            if includeHealth then
                if (v.physicalPower or 0) > (v.health or 0) then
                    return "physical"
                else
                    return "guardian"
                end
            else
                return "physical"
            end
        end
    end
end

local function lobbyStrCheck(a, b)
    local la, lb = string.lower(a), string.lower(b)
    la = string.gsub(la, "'", "")
    lb = string.gsub(lb, "'", "")
    la = string.gsub(la, "s", "")
    lb = string.gsub(lb, "s", "")
    return la == lb
end

local function isItemInList(name)
    for itemName, _ in pairs(_G.itemlist) do
        if lobbyStrCheck(itemName, name) then
            return true
        end
    end
    return false
end

local function checkSell(rare, name)
    for itemName, rareTable in pairs(_G.itemlist) do
        if lobbyStrCheck(itemName, name) then
            for _, j in pairs(rareTable) do
                if rare == j then
                    return false
                end
            end
        end
    end
    return not _G.keeprarities[rare]
end

local function extractItemId(key, itemData)
    local keyNum = tostring(key):match("%d+") or tostring(key)
    if itemData and itemData.UniqueItemID then
        return keyNum .. ":" .. itemData.UniqueItemID
    end
    return keyNum
end

-- ==========================================
-- NUMBER ABBREVIATION FUNCTION
-- ==========================================

local function abbreviateNumber(num)
    if num >= 1000000 then
        return string.format("%.2f", num / 1000000) .. "M"
    elseif num >= 1000 then
        return string.format("%.2f", num / 1000) .. "K"
    else
        return tostring(math.floor(num))
    end
end

-- ==========================================
-- POTENTIAL CALCULATION FUNCTION
-- ==========================================

local function calculatePotential(item)
    if not item then return 0 end
    
    local maxUpgrades = item.maxUpgrades or 0
    local itemType = getItemType(item, true)
    local basePotential = maxUpgrades * 10
    local stat = 0
    
    if itemType == "physical" then
        stat = item.physicalDamage or item.physicalPower or 0
    elseif itemType == "mage" then
        stat = item.spellPower or 0
    elseif itemType == "guardian" then
        stat = item.health or 0
    end
    
    return basePotential + stat
end

-- ==========================================
-- WEBHOOK FUNCTIONS (UPDATED FORMAT)
-- ==========================================

local function sendWebhook(itemName, rarity, itemType, potential)
    if WEBHOOK_URL == "" or not WEBHOOK_URL then
        return false
    end
    
    local success, result = pcall(function()
        local colorMap = {
            ["ULTIMATE"] = 16711680,      -- Red
            ["LEGENDARY"] = 16776960,     -- Yellow
            ["EPIC VALHALLA"] = 16711935  -- Magenta
        }
        
        local embed = {
            title = "🚨RARE ITEM DETECTED🚨",
            description = "A Rare item has been found in inventory!",
            color = colorMap[rarity] or 16711680,
            fields = {
                { name = "Item Name", value = tostring(itemName), inline = true },
                { name = "Rarity", value = tostring(rarity), inline = true },
                { name = "Item Type", value = tostring(itemType or "Unknown"), inline = true },
                { name = "Potential", value = abbreviateNumber(potential or 0), inline = true },
                { name = "Player", value = "||" .. plr.DisplayName .. "||", inline = true },
                { name = "Timestamp", value = os.date("%Y-%m-%d %H:%M:%S"), inline = false }
            },
            footer = { text = "Webhook System" }
        }
        
        local payload = {
            embeds = { embed },
            username = "Webhook Bot"
        }
        
        local http = game:GetService("HttpService")
        local jsonPayload = http:JSONEncode(payload)
        
        local requestMethod = (syn and syn.request) 
            or request 
            or http_request 
            or (fluxus and fluxus.request) 
            or (Krnl and Krnl.Request)
            or (identifyexecutor and select(1, identifyexecutor()) == "Delta" and syn and syn.request)

        if not requestMethod then
            error("Executor request function not found!")
        end
        
        requestMethod({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonPayload
        })
        
        return true
    end)
    
    return success
end

-- ==========================================
-- SHUTDOWN FUNCTIONS
-- ==========================================

local function triggerShutdown(itemName, rarity, itemType, item)
    print("[Security] ⚠️ DANGER DETECTED: " .. itemName .. " (" .. rarity .. ")")
    warn("[Security] Dangerous item detected! Shutting down for safety.")
    local potential = 0
    if item then
        potential = calculatePotential(item)
    end
    sendWebhook(itemName, rarity, itemType, potential)
    task.wait()
    plr:Kick("[Safeguard] Dangerous item detected (" .. rarity .. "). Shutting down.")
    task.wait()
    game:Shutdown()
end

local function checkForDangerItems(gitems)
    if not gitems then return end
    
    local gearTypes = { "weapons", "chests", "helmets" }
    
    for _, itemFolderName in ipairs(gearTypes) do
        local itemFolder = gitems[itemFolderName]
        if itemFolder then
            for _, item in pairs(itemFolder) do
                if item and item.name and item.rarity and not isItemEquipped(item) then
                    local rarityLower = string.lower(item.rarity or "")
                    local nameLower = string.lower(item.name or "")
                    
                    if rarityLower == "ultimate" then
                        print("[Security] 🚨 ULTIMATE item found: " .. item.name)
                        triggerShutdown(item.name, "ULTIMATE", itemFolderName, item)
                        return
                    end
                    
                    if rarityLower == "legendary" then
                        print("[Security] 🚨 LEGENDARY item found: " .. item.name)
                        triggerShutdown(item.name, "LEGENDARY", itemFolderName, item)
                        return
                    end
                    
                    if rarityLower == "epic" and string.find(nameLower, "valhalla") then
                        print("[Security] 🚨 EPIC VALHALLA item found: " .. item.name)
                        triggerShutdown(item.name, "EPIC VALHALLA", itemFolderName, item)
                        return
                    end
                end
            end
        end
    end
    
    if gitems.abilities then
        for _, item in pairs(gitems.abilities) do
            if item and item.name and item.rarity and not isItemEquipped(item) then
                local rarityLower = string.lower(item.rarity or "")
                
                if rarityLower == "ultimate" then
                    print("[Security] 🚨 ULTIMATE ability found: " .. item.name)
                    triggerShutdown(item.name, "ULTIMATE", "ability", item)
                    return
                end
                
                if rarityLower == "legendary" then
                    print("[Security] 🚨 LEGENDARY ability found: " .. item.name)
                    triggerShutdown(item.name, "LEGENDARY", "ability", item)
                    return
                end
            end
        end
    end
end

-- ==========================================
-- INTERCEPT: Clone Reward GUI Hook
-- ==========================================
local function setupRewardGuiIntercept()
    local Event = game:GetService("ReplicatedStorage").remotes.cloneRewardGui
    local Callback = getcallbackvalue(Event, "OnClientInvoke")
    
    Event.OnClientInvoke = function(...)
        local Args = table.pack(...)
        
        local Result = table.pack(
            Callback(table.unpack(Args, 1, Args.n))
        )
        
        print("[Intercept] Clone Reward GUI triggered - running danger check...")
        task.wait(0.5)
        local gitems = getPlayerInvy()
        checkForDangerItems(gitems)
        
        return table.unpack(Result, 1, Result.n)
    end
    
    local mtHook; mtHook = hookmetamethod(game, "__newindex", function(...)
        local self, key, value = ...
        
        if (
            rawequal(self, Event) and
            rawequal(key, "OnClientInvoke") and
            typeof(value) == "function" and
            not checkcaller()
        ) then
            Callback = value
        end
        
        return mtHook(...)
    end)
    
    print("[Intercept] ✓ Clone Reward GUI intercept initialized with danger detection")
end

pcall(setupRewardGuiIntercept)

-- ==========================================
-- AUTO-SELL FUNCTION
-- ==========================================

local function sell()
    if not _G.autosell then return end
    
    local gitems = getPlayerInvy()
    if not gitems then return end
    
    checkForDangerItems(gitems)

    local tallyList = {}

    local gearTypes = { "weapons", "chests", "helmets" }
    for _, itemFolderName in ipairs(gearTypes) do
        local itemFolder = gitems[itemFolderName]
        if itemFolder then
            for i, item in pairs(itemFolder) do
                if not isItemEquipped(item) then
                    local itemType = getItemType(item, false)
                    local itemTypeCheck = not _G.keep_items_from_class[itemType]
                    local cleanId = extractItemId(i, item)
                    
                    local failsRarityCheck = checkSell(item.rarity, item.name)
                    local isExplicitlyListed = isItemInList(item.name)
                    local isBelowLevelReq = (item.levelReq or 0) < _G.keep_items_level_requirement

                    if cleanId and failsRarityCheck and (isExplicitlyListed or isBelowLevelReq) and itemTypeCheck then
                        if _G.testSell then
                            print('[TEST SELL] Selling ' .. itemFolderName .. ': ' .. tostring(item.name) .. ' (Rarity: ' .. tostring(item.rarity) .. ', ID: ' .. cleanId .. ')')
                        else
                            if itemFolderName == "weapons" then
                                game:GetService("ReplicatedStorage").remotes.sellItemEvent:FireServer({ ["ability"] = {}, ["helmet"] = {}, ["chest"] = {}, ["weapon"] = { cleanId } })
                            elseif itemFolderName == "chests" then
                                game:GetService("ReplicatedStorage").remotes.sellItemEvent:FireServer({ ["ability"] = {}, ["helmet"] = {}, ["chest"] = { cleanId }, ["weapon"] = {} })
                            elseif itemFolderName == "helmets" then
                                game:GetService("ReplicatedStorage").remotes.sellItemEvent:FireServer({ ["ability"] = {}, ["helmet"] = { cleanId }, ["chest"] = {}, ["weapon"] = {} })
                            end
                        end
                    end
                end
            end
        end
    end

    if gitems.abilities then
        for i, item in pairs(gitems.abilities) do
            if not isItemEquipped(item) then
                tallyList[item.name] = (tallyList[item.name] or 0) + 1
                local cleanId = extractItemId(i, item)

                local failsRarityCheck = checkSell(item.rarity, item.name)
                local isExplicitlyListed = isItemInList(item.name)
                local isBelowLevelReq = (item.levelReq or 0) < _G.keep_items_level_requirement
                local isExtraDuplicate = tallyList[item.name] > 2 and _G.keep2spells

                if cleanId and ((failsRarityCheck and (isExplicitlyListed or isBelowLevelReq)) or isExtraDuplicate) then
                    if _G.testSell then
                        print('[TEST SELL] Selling ability: ' .. tostring(item.name) .. ' (ID: ' .. cleanId .. ')')
                    else
                        game:GetService("ReplicatedStorage").remotes.sellItemEvent:FireServer({ ["ability"] = { cleanId }, ["helmet"] = {}, ["chest"] = {}, ["weapon"] = {} })
                    end
                end
            end
        end
    end
end

task.spawn(function()
    while true do
        sell()
        task.wait(0.5)
    end
end)

print("=" .. string.rep("=", 50))
print("Auto-sell with Shutdown Protection Initialized")
print("Monitoring for: Ultimate, Legendary, Epic Valhalla")
print("Webhook Status: 🟢 CONFIGURED")
print("Status: 🟢 ACTIVE")
print("=" .. string.rep("=", 50))

sell()
print("Auto-sell check complete.")
