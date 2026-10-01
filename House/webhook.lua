local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Don't hardcode your webhook here. Set it before running: getgenv().WEBHOOK_URL = "..."
local webhookUrl = getgenv().WEBHOOK_URL or "https://discord.com/api/webhooks/1414475376230535199/F6V5IZJkOUMdxd-ZdC32JdlaTw-FGDz-raRMGW7a6FsYTmYtRkqOSfLy123hat3xSNR1"

-- Set getgenv().AUTO_SEND = false to send once immediately instead of after every round
local AUTO_SEND = getgenv().AUTO_SEND ~= false

local inventoryGetters = require(ReplicatedStorage.Modules.Inventory.inventory_getters)
local XpSystem = require(ReplicatedStorage.Modules.XpSystem)
local FactionsModule = require(ReplicatedStorage.Modules.Factions)
local FactionsDatabase = require(ReplicatedStorage.Databases.Factions)
local round_atom = require(ReplicatedStorage.Modules.Round.round_atom)

local player = Players.LocalPlayer

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
-- round_atom has no end timestamp, so we record the moment game_over flips to true.
-- We also record our own start time as a fallback in case startedAt isn't usable.
----------------------------------------------------------------------
local tracker = { start = nil, endT = nil }

local function updateTracker(state)
    if not state then return end
    local now = workspace:GetServerTimeNow()

    if state.game_over then
        if not tracker.endT then
            tracker.endT = now
        end
    else
        -- A new round is underway (or none yet): clear last round's end marker
        tracker.endT = nil
        if (state.active or state.started) then
            if not tracker.start then
                tracker.start = now
            end
        else
            tracker.start = nil
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

local function getRoundTimeText(state)
    if not state then return "Unknown" end
    local endT = tracker.endT or workspace:GetServerTimeNow()

    -- Prefer the game's own startedAt
    local s = state.startedAt
    if type(s) == "number" and s > 0 then
        local diff = endT - s
        if diff >= 0 and diff < 86400 then
            return formatSeconds(diff)
        end
    end

    -- Fall back to when this script first saw the round go active
    if tracker.start then
        return formatSeconds(endT - tracker.start)
    end

    return "Unknown"
end

-- Round rewards are stored per player in round_atom().rewards["#" .. PlayerName]
-- as an array of { itemId, amount, _bonusSource?, shiny?, spirit? } (see giveRoundRewards).
local function getRoundRewardsText(state)
    if not state or type(state.rewards) ~= "table" then
        return "None found"
    end

    local list = state.rewards["#" .. player.Name]
    if type(list) ~= "table" or #list == 0 then
        return "None found"
    end

    -- Merge entries with the same item (bonus-source entries are split in the atom)
    local order, totals = {}, {}
    for _, reward in ipairs(list) do
        local name = tostring(reward.itemId or "Unknown")
        if reward.shiny then name = "Shiny " .. name end
        if reward.spirit then name = "Spirit " .. name end
        if not totals[name] then
            totals[name] = 0
            table.insert(order, name)
        end
        totals[name] = totals[name] + (tonumber(reward.amount) or 1)
    end

    local lines = {}
    for _, name in ipairs(order) do
        table.insert(lines, string.format("`%s x%d`", name, totals[name]))
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
local function sendWebhook()
    local success, mainLevel, mainExpBarText, factionKey, factionName, factionLevel, factionExpBarText, inventoryData = pcall(function()
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

        local inv = inventoryGetters.getInventory(player)

        return mLevel, mExpBar, currentFactionKey, fName, fLevel, fExpBar, inv
    end)

    if not success then
        warn("Failed to fetch player stats or inventory data.")
        return
    end

    local targetItems = { "Coins", "VoodooToken", "GardenCoins", "RaidTokens", "KingsToken" }

    local foundItems = {}
    if inventoryData then
        for _, itemId in ipairs(targetItems) do
            if inventoryData[itemId] then
                local amount = inventoryData[itemId].amount or 1
                table.insert(foundItems, string.format("`%s:%d`", itemId, amount))
            end
        end
    end
    local inventoryText = #foundItems > 0 and table.concat(foundItems, ", ") or "None found"

    -- Round info
    local roundState = readRoundState()
    updateTracker(roundState)

    local data = {
        ["content"] = "",
        ["embeds"] = {{
            ["title"] = "📊 Player Status & Inventory",
            ["color"] = 3447003,
            ["fields"] = {
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

                -- Round section
                { ["name"] = "Round Result", ["value"] = getResultText(roundState), ["inline"] = false },
                { ["name"] = "Round Time", ["value"] = getRoundTimeText(roundState), ["inline"] = false },
                { ["name"] = "Dropped / Rewarded Items", ["value"] = getRoundRewardsText(roundState), ["inline"] = false },
            }
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
-- Trigger
----------------------------------------------------------------------
if AUTO_SEND then
    task.spawn(function()
        local wasGameOver = false
        local initial = readRoundState()
        if initial then
            wasGameOver = initial.game_over == true -- don't re-send a round that already ended before launch
            updateTracker(initial)
        end

        while task.wait(0.5) do
            local state = readRoundState()
            if state then
                updateTracker(state) -- stamps the end time on the first tick game_over is true

                local isGameOver = state.game_over == true
                if isGameOver and not wasGameOver then
                    task.wait(2) -- give the server time to finish handing out rewards
                    sendWebhook()
                end
                wasGameOver = isGameOver
            end
        end
    end)
else
    sendWebhook()
end
