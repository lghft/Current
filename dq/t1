repeat task.wait() until game:IsLoaded()
  task.spawn(function()
      print("requestscrpt")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local remotes = ReplicatedStorage:WaitForChild("remotes")

    local showJoinRequest = remotes:WaitForChild("showJoinRequest")
    local respondJoinRequest = remotes:WaitForChild("respondJoinRequest")

    -- Whitelist dictionary (O(1) lookups)
    local WHITELISTED_PLAYERS = {
        ["Thrsxtrn"] = true,
    }

    showJoinRequest.OnClientEvent:Connect(function(requestId, playerName, action)
        -- Ignore close events or invalid payloads
        if action == "close" or not requestId or type(playerName) ~= "string" then
            return
        end

        -- Check if player is whitelisted
        local isWhitelisted = WHITELISTED_PLAYERS[playerName] or false

        if isWhitelisted then
            print(string.format("[AutoAccept] Accepted request from %s (ID: %s)", playerName, tostring(requestId)))
            respondJoinRequest:FireServer(requestId, true)
        else
            print(string.format("[AutoAccept] Rejected request from %s (ID: %s)", playerName, tostring(requestId)))
            respondJoinRequest:FireServer(requestId, false)
        end
    end)
end)

task.spawn(function()
    print("staffkickstuff")
    local Players = game:GetService("Players")

    local TARGET_PLACEID = 85776757589518 -- this is nl dungeon by default
    local CHECK_DELAY = 0.5

    local Whitelist = {
        "y7_s",
        "Thrsxtrn",
    }

    if game.PlaceId ~= TARGET_PLACEID then
        return
    end

    local LocalPlayer = Players.LocalPlayer
    while not LocalPlayer do
        task.wait()
        LocalPlayer = Players.LocalPlayer
    end

    local function IsWhitelisted(username: string): boolean
        username = username:lower()
        for _, allowedName in ipairs(Whitelist) do
            if username == allowedName:lower() then
                return true
            end
        end
        return false
    end

    local function KillClient()
        if LocalPlayer then
            print("A player who was not whitelisted joined your game.")
            LocalPlayer:Kick("A player who was not whitelisted joined your game.")
        end
    end

    local function CheckPlayer(player: Player)
        if player == LocalPlayer then
            return
        end
        if not IsWhitelisted(player.Name) then
            KillClient()
        end
    end

    Players.PlayerAdded:Connect(function(player)
        task.wait(CHECK_DELAY) 
        CheckPlayer(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        CheckPlayer(player)
    end
end)

