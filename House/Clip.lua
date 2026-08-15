local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

pcall(function() Noclipping:Disconnect() end)
Clip = false
task.wait(0.1)
NoclipParts = {}
floatName = floatName or "" -- Fallback in case floatName isn't defined

Noclipping = RunService.Stepped:Connect(function()
    local character = LocalPlayer.Character
    if Clip == false and character ~= nil then
        for _, child in pairs(character:GetDescendants()) do
            if child:IsA("BasePart") and child.CanCollide == true and child.Name ~= floatName then
                child.CanCollide = false
                NoclipParts[child] = true
            end
        end
    end
end)
