local plr = game.Players.LocalPlayer
local plrs = game.Players:GetPlayers()
if #plrs < 2 and #plrs == 1 then
plr.CharacterAdded:Connect(function(char)
    loadstring(game:HttpGet('https://raw.githubusercontent.com/lghft/Current/refs/heads/main/dq/float.lua'))()
end)
end
