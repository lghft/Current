local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Don't hardcode your webhook here. Set it before running: getgenv().WEBHOOK_URL = "..."
local webhookUrl = getgenv().WEBHOOK_URL or "PASTE_NEW_WEBHOOK_URL_HERE"

-- Set getgenv().AUTO_SEND = false to send once immediately instead of after every round
local AUTO_SEND = getgenv().AUTO_SEND ~= false

-- Set getgenv().DEBUG = true to enable debug logging
local DEBUG = getgenv().DEBUG or false

local function debug(...)
    if DEBUG then
        print("[WEBHOOK DEBUG]", ...)
    end
end

local inventoryGetters = require(ReplicatedStorage.Modules.Inventory.inventory_getters)
local XpSystem = require(ReplicatedStorage.Modules.XpSystem)
local FactionsModule = require(ReplicatedStorage.Modules.Factions)
local FactionsDatabase = require(ReplicatedStorage.Databases.Factions)
local round_atom = require(ReplicatedStorage.Modules.Round.round_atom)
local Items = require(ReplicatedStorage.Modules.Items)

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Special items to flag inside crates (add more IDs here if needed)
----------------------------------------------------------------------
local SPECIAL_ITEMS = {
    TheWatcherUrn = true,
    WatcherUrn = true,
    DemonicEffigy = true,
    EternalAmulet = true, -- common drop, here for testing
}

-- Returns the matched special item ID (string) or nil
local function matchSpecial(key, item)
    if type(key) == "string" and SPECIAL_ITEMS[key] then
        return key
    end
    if type(item) == "string" and SPECIAL_ITEMS[item] then
        return item
    end
    if type(item) == "table" then
        for _, field in ipairs({ "itemId", "id", "name", "item" }) do
            local v = item[field]
            if type(v) == "string" and SPECIAL_ITEMS[v] then
                return v
            end
        end
    end
    return nil
end

local function getItemName(itemId)
    local ok, itemResult = pcall(Items.get, itemId)
    if ok and itemResult and itemResult.name then
        return itemResult.name
    end
    return itemId
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
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

local function readRoundState()
    local ok, state = pcall(round_atom) -- calling an atom with no args returns its current value
    if ok and type(state) == "table" then
        return state
    end
    return nil
end

local function formatSeconds(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then
        return string.format("%dh %02dm %02ds", h, m, s)
    end
    return string.format("%dm %02ds", m, s)
end

----------------------------------------------------------------------
-- Round tracking
----------------------------------------------------------------------
local tracker = { start = nil, endT = nil, startingInventory = nil }

local function updateTracker(state)
    if not state then return end
    local now = workspace:GetServerTimeNow()

    if state.game_over then
        if not tracker.endT then
            tracker.endT = now
        end
    else
        tracker.endT = nil
        if (state.active or state.started) then
            if not tracker.start then
                tracker.start = now
                local ok, inv = pcall(function()
                    return inventoryGetters.getInventory(player)
                end)
                if ok and inv then
                    tracker.startingInventory = inv
                end
            end
        else
            tracker.start = nil
            tracker.startingInventory = nil
        end
    end
end

local function getResultText(state)
    if not state then return "Unknown" end
    if not state.game_over then
        return "⏳ In Progress"
    end

    local won = (tonumber(state.health) or 0) > 0
    local label = won and "🏆 Victory" or "💀 Defeat"
    local details = string.format(
        "Wave %s/%s • %s",
        tostring(state.wave or "?"),
        tostring(state.max_waves or "?"),
        tostring(state.difficulty or "?")
    )
    return label .. " (" .. details .. ")"
end

local function getRoundTimeText(state, info)
    if not state then return "Unknown" end
    info = info or tracker
    local endT = info.endT or workspace:GetServerTimeNow()

    local s = state.startedAt
    if type(s) == "number" and s > 0 then
        local diff = endT - s
        if diff >= 0 and diff < 86400 then
            return formatSeconds(diff)
        end
    end

    if info.start then
        return formatSeconds(endT - info.start)
    end

    return "Unknown"
end

-- Extracts non-crate rewards from round state
local function getDroppedItemsText(state)
    if not state or type(state.rewards) ~= "table" then
        return "None found"
    end

    local playerRewards = state.rewards["#" .. player.Name]
    if not playerRewards or type(playerRewards) ~= "table" then
        return "None found"
    end

    local itemMap = {}
    local itemOrder = {}

    for _, reward in ipairs(playerRewards) do
        if type(reward) == "table" and not reward.contents then
            local itemId = reward.itemId
            if itemId then
                local amount = reward.amount or 1

                if not itemMap[itemId] then
                    itemMap[itemId] = 0
                    table.insert(itemOrder, itemId)
                end
                itemMap[itemId] = itemMap[itemId] + amount
            end
        end
    end

    if #itemOrder == 0 then
        return "None found"
    end

    local lines = {}
    for _, itemId in ipairs(itemOrder) do
        table.insert(lines, string.format("`%s x%d`", getItemName(itemId), itemMap[itemId]))
    end

    local text = table.concat(lines, "\n")
    if #text > 1000 then -- Discord field limit is 1024
        text = text:sub(1, 997) .. "..."
    end
    return text
end

-- Extracts crate rewards from round state.
-- Each crate is numbered in the order it appears. Any special item found inside a crate
-- is listed separately with its crate number, crate name and item ID.
local function getCrateRewardsText(state)
    if not state or type(state.rewards) ~= "table" then
        return "None found"
    end

    local playerRewards = state.rewards["#" .. player.Name]
    if not playerRewards or type(playerRewards) ~= "table" then
        return "None found"
    end

    local crateMap = {}
    local crateOrder = {}
    local specialLines = {}
    local crateNumber = 0

    for _, reward in ipairs(playerRewards) do
        if type(reward) == "table" and reward.contents and reward.itemId and type(reward.contents) == "table" then
            crateNumber = crateNumber + 1
            local crateId = reward.itemId
            local crateName = getItemName(crateId)

            local maxIndex = 0
            local found = {}

            for key, item in pairs(reward.contents) do
                local num = tonumber(key)
                if num and num > maxIndex then
                    maxIndex = num
                end

                debug("crate", crateNumber, crateId, key, type(item) == "table" and item.itemId or item)

                local matched = matchSpecial(key, item)
                if matched then
                    table.insert(found, matched)
                end
            end

            if maxIndex > 0 then
                if not crateMap[crateId] then
                    crateMap[crateId] = 0
                    table.insert(crateOrder, crateId)
                end
                crateMap[crateId] = crateMap[crateId] + maxIndex

                for _, specialId in ipairs(found) do
                    table.insert(specialLines, string.format("`Crate #%d (%s): %s`", crateNumber, crateName, specialId))
                end
            end
        end
    end

    if #crateOrder == 0 then
        return "None found"
    end

    local lines = {}
    for _, crateId in ipairs(crateOrder) do
        table.insert(lines, string.format("`%s: %d`", getItemName(crateId), crateMap[crateId]))
    end

    if #specialLines > 0 then
        table.insert(lines, "")
        table.insert(lines, "🌟 **Special Items**")
        for _, line in ipairs(specialLines) do
            table.insert(lines, line)
        end
    end

    local text = table.concat(lines, "\n")
    if #text > 1000 then -- Discord field limit is 1024
        text = text:sub(1, 997) .. "..."
    end
    return text
end

----------------------------------------------------------------------
-- Webhook
----------------------------------------------------------------------
local function sendWebhook(snapshot, info)
    info = info or {}
    local success, mainLevel, mainExpBarText, factionKey, factionName, factionLevel, factionExpBarText, startingInventory, endingInventory = pcall(function()
        local mainXp = XpSystem.getXp("Main", player) or 0
        local mLevel = XpSystem.xpToLevel("Main", mainXp)
        local mBaseXp = XpSystem.levelToXp(mLevel)
        local mNextXp = math.max(1, XpSystem.levelToXp(mLevel + 1) - mBaseXp)
        local mainCurrentXp = mainXp - mBaseXp
        local mExpBar = createProgressBar(mainCurrentXp, mNextXp, 10)

        local currentFactionKey = "Omni"
        local successFaction, resFaction = pcall(function()
            return FactionsModule.getCurrentFaction(player)
        end)
        if successFaction and resFaction then
            currentFactionKey = resFaction
        end

        local factionData = FactionsDatabase[currentFactionKey]
        local fName = factionData and factionData.name or currentFactionKey

        local fXp = XpSystem.getXp(currentFactionKey, player) or 0
        local fLevel = XpSystem.xpToLevel(currentFactionKey, fXp)
        local fBaseXp = XpSystem.levelToXp(fLevel)
        local fNextXp = math.max(1, XpSystem.levelToXp(fLevel + 1) - fBaseXp)
        local factionCurrentXp = fXp - fBaseXp
        local fExpBar = createProgressBar(factionCurrentXp, fNextXp, 10)

        local startInv = info.startingInventory or tracker.startingInventory
        local endInv = inventoryGetters.getInventory(player)

        return mLevel, mExpBar, currentFactionKey, fName, fLevel, fExpBar, startInv, endInv
    end)

    if not success then
        warn("Failed to fetch player stats or inventory data.")
        return
    end

    local targetItems = { "Coins", "VoodooToken", "GardenCoins", "RaidTokens", "KingsToken" }

    local foundItems = {}
    if endingInventory then
        for _, itemId in ipairs(targetItems) do
            if endingInventory[itemId] then
                local amount = endingInventory[itemId].amount or 1
                table.insert(foundItems, string.format("`%s:%d`", itemId, amount))
            end
        end
    end
    local inventoryText = #foundItems > 0 and table.concat(foundItems, ", ") or "None found"

    local roundState = snapshot
    if not roundState then
        roundState = readRoundState()
        updateTracker(roundState)
    end

    local droppedItemsText = getDroppedItemsText(roundState)

    local fields = {
        { ["name"] = "Display Name", ["value"] = "||" .. player.DisplayName .. "||", ["inline"] = true },
        { ["name"] = "Username", ["value"] = "||" .. player.Name .. "||", ["inline"] = true },
        {
            ["name"] = "Main Level (" .. tostring(mainLevel or 1) .. ")",
            ["value"] = tostring(mainExpBarText),
            ["inline"] = false
        },
        {
            ["name"] = "Faction (" .. tostring(factionName) .. ") Level (" .. tostring(factionLevel or 1) .. ")",
            ["value"] = tostring(factionExpBarText),
            ["inline"] = false
        },
        { ["name"] = "Target Inventory Items", ["value"] = inventoryText, ["inline"] = false },

        { ["name"] = "Round Result", ["value"] = getResultText(roundState), ["inline"] = false },
        { ["name"] = "Round Time", ["value"] = getRoundTimeText(roundState, info), ["inline"] = false },
        { ["name"] = "Dropped / Rewarded Items", ["value"] = droppedItemsText, ["inline"] = false },
    }

    local crateRewardsText = getCrateRewardsText(roundState)
    if crateRewardsText ~= "None found" then
        table.insert(fields, { ["name"] = "Crate Rewards", ["value"] = crateRewardsText, ["inline"] = false })
    end

    local data = {
        ["content"] = "",
        ["embeds"] = {{
            ["title"] = "📊 Player Status & Inventory",
            ["color"] = 3447003,
            ["fields"] = fields
        }}
    }

    local jsonBody = HttpService:JSONEncode(data)
    local requestMethod = (syn and syn.request) or (http and http.request) or http_request

    if requestMethod then
        requestMethod({
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonBody
        })
    else
        pcall(function()
            HttpService:PostAsync(webhookUrl, jsonBody, Enum.HttpContentType.ApplicationJson)
        end)
    end
end

----------------------------------------------------------------------
-- Trigger (multi-round, duplicate-proof)
----------------------------------------------------------------------
local POLL_RATE = 0.25
local REWARD_DELAY = 2 -- seconds to let the server finish handing out rewards
local REARM_AFTER = 3 -- seconds game_over must be false before the same round ID can send again
local MIN_GAP = 10 -- minimum seconds between any two webhook sends

local runToken = {}
getgenv().__ROUND_WEBHOOK_RUN = runToken -- any older loop sees a different token and exits

local function roundId(state)
    local s = tonumber(state.startedAt) or 0
    if s > 0 then return "s" .. s end
    return "a" .. tostring(state.startAt)
end

local bestSnapshots = {} -- round id -> latest state that contained rewards

local function hasRewards(state)
    local pr = type(state.rewards) == "table" and state.rewards["#" .. player.Name]
    return type(pr) == "table" and #pr > 0
end

local function finishRound(snapshot, info, id)
    task.wait(REWARD_DELAY)

    -- Prefer a fresh read if it still has rewards; otherwise fall back to the
    -- last snapshot we saw with rewards, so leaving the results screen early can't lose them.
    local fresh = readRoundState()
    if fresh and fresh.game_over and roundId(fresh) == id and hasRewards(fresh) then
        snapshot = fresh
    elseif bestSnapshots[id] then
        snapshot = bestSnapshots[id]
    elseif fresh and fresh.game_over and roundId(fresh) == id then
        snapshot = fresh
    end
    bestSnapshots[id] = nil

    info.startingInventory = tracker.startingInventory

    local ok, err = pcall(sendWebhook, snapshot, info)
    if not ok then
        warn("[webhook] send failed:", err)
    end
end

if AUTO_SEND then
    task.spawn(function()
        local lastSentId = nil
        local currentId = nil
        local falseSince = nil

        local initial = readRoundState()
        if initial then
            currentId = roundId(initial)
            updateTracker(initial)
            if initial.game_over then
                lastSentId = currentId
            end
        end

        while task.wait(POLL_RATE) do
            if getgenv().__ROUND_WEBHOOK_RUN ~= runToken then
                break
            end

            local state = readRoundState()
            if state then
                local id = roundId(state)

                if id ~= currentId then
                    currentId = id
                    tracker.start = nil
                    tracker.endT = nil
                end

                updateTracker(state)

                if hasRewards(state) then
                    bestSnapshots[id] = state
                end

                if state.game_over then
                    falseSince = nil

                    if lastSentId ~= id then
                        lastSentId = id

                        local now = os.clock()
                        local last = getgenv().__ROUND_WEBHOOK_LAST or -math.huge
                        if now - last >= MIN_GAP then
                            getgenv().__ROUND_WEBHOOK_LAST = now
                            local info = { start = tracker.start, endT = tracker.endT }
                            task.spawn(finishRound, state, info, id)
                        end
                    end
                else
                    falseSince = falseSince or os.clock()
                    if os.clock() - falseSince >= REARM_AFTER then
                        lastSentId = nil
                    end
                end
            end
        end
    end)
else
    sendWebhook()
end
