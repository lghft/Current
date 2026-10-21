local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- Load the inventory module
local inventoryGetters = require(ReplicatedStorage.Modules.Inventory.inventory_getters)

-- Helper function to deeply print tables to the console
local function printTable(t, indent)
    indent = indent or ""
    if type(t) ~= "table" then
        print(indent .. tostring(t))
        return
    end
    
    for k, v in pairs(t) do
        local keyString = tostring(k)
        if type(v) == "table" then
            print(indent .. keyString .. ": {")
            printTable(v, indent .. "  ")
            print(indent .. "}")
        else
            print(indent .. keyString .. ": " .. tostring(v))
        end
    end
end

-- Fetch and print the inventory
local success, inventoryData = pcall(function()
    return inventoryGetters.getInventory(player)
end)

print("=== START OF PLAYER INVENTORY ===")

if success and inventoryData then
    if type(inventoryData) == "table" then
        printTable(inventoryData)
        
        -- Optional: Also attempt to print it as a JSON string for easy copying
        pcall(function()
            warn("JSON Format: \n" .. HttpService:JSONEncode(inventoryData))
        end)
    else
        print("Inventory returned a non-table value: ", tostring(inventoryData))
    end
else
    warn("Failed to fetch inventory. Error:", tostring(inventoryData))
end

print("=== END OF PLAYER INVENTORY ===")
