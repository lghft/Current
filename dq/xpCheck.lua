local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Wait for the XP and XPNeeded Value instances under LocalPlayer
local xp = LocalPlayer:WaitForChild("XP")
local xpNeeded = LocalPlayer:WaitForChild("XPNeeded")

-- Helper function to format numbers with commas
local function formatCommas(number)
    local formatted = tostring(number)
    local k
    repeat
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return formatted
end

local function printXP()
    print(string.format("XP: %s / %s", formatCommas(xp.Value), formatCommas(xpNeeded.Value)))
end

-- Print current values on script run
printXP()

-- Listen for changes to either XP or XPNeeded
xp:GetPropertyChangedSignal("Value"):Connect(printXP)
xpNeeded:GetPropertyChangedSignal("Value"):Connect(printXP)
