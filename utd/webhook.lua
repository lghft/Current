local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

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
    -- Safely fetch UI elements and leaderstats with error handling
    local success, eventCurrency, gold, level, bplevel, gems, bpExpBar = pcall(function()
        local mainGui = player.PlayerGui:WaitForChild("MainGui", 2)
        local eventBpBtn = game:GetService("Players").LocalPlayer.PlayerGui.MainGui.MainFrames.Battlepass.Main.Foreground.RightPanel.Battlepass.Filters.SummerEventBattlepass26.Button
        firesignal(eventBpBtn.Activated)
        task.wait()
        local ec = mainGui.MainFrames.EventStore.Main.Foreground.TopPanel.Currencies.EventCurrency.Button.Price.Amount.Text
        local g = player.leaderstats.Gold.Value
        local lvl = player.leaderstats.Level.Value
        local bplvl = mainGui.MainFrames.Battlepass.Main.Foreground.RightPanel.Battlepass.TopFrame.Progress.Top.Level.TextLabel.Text
        local gem = mainGui.HUD.Currencies.Gem.Frame.amount.Text
        
        -- Fetch raw experience string (e.g., "500/1000")
        local rawExpText = mainGui.MainFrames.Battlepass.Main.Foreground.RightPanel.Battlepass.TopFrame.Progress.Top.Experience.TextLabel.Text
        
        -- Extract current and max experience numbers using string matching
        local curExp, maxExp = rawExpText:match("(%d+)%s*/%s*(%d+)")
        curExp = tonumber(curExp) or 0
        maxExp = tonumber(maxExp) or 1000

        local progressBar = createProgressBar(curExp, maxExp, 10)
        
        return ec, g, lvl, bplvl, gem, progressBar
    end)

    if not success then
        warn("Failed to retrieve one or more path values for the webhook.")
        return
    end

    -- Construct the payload for Discord matching your exact layout
    local data = {
        ["content"] = "",
        ["embeds"] = {{
            ["title"] = "📊 Lobby Player Status",
            ["color"] = 65280, -- Green color
            ["fields"] = {
                {
                    ["name"] = "Display",
                    ["value"] = "||" .. player.DisplayName .. "||",
                    ["inline"] = false
                },
                {
                    ["name"] = "User",
                    ["value"] = "||" .. player.Name .. "||",
                    ["inline"] = false
                },
                {
                    ["name"] = "Level",
                    ["value"] = tostring(level),
                    ["inline"] = true
                },
                {
                    ["name"] = "BattlePass Level",
                    ["value"] = tostring(bplevel),
                    ["inline"] = true
                },
                {
                    ["name"] = "BattlePass EXP",
                    ["value"] = bpExpBar,
                    ["inline"] = false
                },
                {
                    ["name"] = "Clams",
                    ["value"] = tostring(eventCurrency),
                    ["inline"] = true
                },
                {
                    ["name"] = "Gold",
                    ["value"] = tostring(gold),
                    ["inline"] = true
                },
                {
                    ["name"] = "Gems",
                    ["value"] = tostring(gems),
                    ["inline"] = false
                }
            }
        }}
    }

    local jsonBody = HttpService:JSONEncode(data)

    local requestMethod = (syn and syn.request) or (http and http.request) or http_request

    if requestMethod then
        requestMethod({
            Url = getgenv().WEBHOOK_URL or WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = jsonBody
        })
    else
        local successPost, err = pcall(function()
            HttpService:PostAsync(getgenv().WEBHOOK_URL or WEBHOOK_URL, jsonBody)
        end)
        
        if not successPost then
            warn("Error posting to Discord webhook: " .. tostring(err))
        end
    end
end

-- Call the function to send the webhook
sendWebhook()
