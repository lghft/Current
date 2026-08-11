local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function sendWebhook()
    -- Safely fetch UI elements and leaderstats with error handling
    local success, eventCurrency, gold, level, gems = pcall(function()
        local mainGui = player.PlayerGui:WaitForChild("MainGui", 2)
        
        local ec = mainGui.MainFrames.EventStore.Main.Foreground.TopPanel.Currencies.EventCurrency.Button.Price.Amount.Text
        local g = player.leaderstats.Gold.Value
        local lvl = player.leaderstats.Level.Value
        local gem = mainGui.HUD.Currencies.Gem.Frame.amount.Text
        
        return ec, g, lvl, gem
    end)

    if not success then
        warn("Failed to retrieve one or more path values for the webhook.")
        return
    end

    -- Construct the payload for Discord (using an embed for clean formatting)
    local data = {
        ["content"] = "",
        ["embeds"] = {{
            ["title"] = "📊 Player Status Update",
            ["color"] = 65280, -- Green color
            ["fields"] = {
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
                    ["name"] = "Level",
                    ["value"] = tostring(level),
                    ["inline"] = true
                },
                {
                    ["name"] = "Gems",
                    ["value"] = tostring(gems),
                    ["inline"] = true
                }
            },
            ["footer"] = {
                ["text"] = "Player: |" .. player.Name .. "|"
            }
        }}
    }

    local jsonBody = HttpService:JSONEncode(data)

    -- Send the request (Must be executed on the server, or with HttpEnabled / external proxy if client-side)
    local requestMethod = (syn and syn.request) or (http and http.request) or http_request

    if requestMethod then
        -- Exploit/Executor environment request
        requestMethod({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = jsonBody
        })
    else
        -- Standard Roblox Server-side request
        local successPost, err = pcall(function()
            HttpService:PostAsync(getgenv().WEBHOOK_URL, jsonBody)
        end)
        
        if not successPost then
            warn("Error posting to Discord webhook: " .. tostring(err))
        end
    end
end

-- Call the function to send the webhook
sendWebhook()
