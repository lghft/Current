-- Target Module Path: ReplicatedStorage.Modules.LiveOps.RareDropChat
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local targetModule = ReplicatedStorage:FindFirstChild("Modules") 
    and ReplicatedStorage.Modules:FindFirstChild("LiveOps") 
    and ReplicatedStorage.Modules.LiveOps:FindFirstChild("RareDropChat")

-- Hook require to intercept and neutralize the module
local oldRequire
oldRequire = hookfunction(require, function(module)
    if module == targetModule then
        -- Return a dummy table with blank functions so other scripts don't error out when calling them
        return {
            announce = function() end,
            announceSummon = function() end,
            Start = function() end
        }
    end
    return oldRequire(module)
end)

-- If the module was already required before this script ran, 
-- we can also manually clear/overwrite its active functions if accessible:
pcall(function()
    local loadedModule = require(targetModule)
    if type(loadedModule) == "table" then
        loadedModule.announce = function() end
        loadedModule.announceSummon = function() end
        loadedModule.Start = function() end
    end
end)

print("[+] RareDropChat successfully blocked.")
