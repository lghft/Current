local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- Load the inventory module
local inventoryGetters = require(ReplicatedStorage.Modules.Inventory.inventory_getters)

-- Fetch the inventory
local success, inventoryData = pcall(function()
    return inventoryGetters.getInventory(player)
end)

if success and type(inventoryData) == "table" then
    local ok, json = pcall(function()
        return HttpService:JSONEncode(inventoryData)
    end)

    if ok then
        warn("JSON Format: \n" .. json)
    else
        warn("Failed to encode inventory as JSON:", tostring(json))
    end
elseif success then
    warn("Inventory returned a non-table value:", tostring(inventoryData))
else
    warn("Failed to fetch inventory. Error:", tostring(inventoryData))
end
