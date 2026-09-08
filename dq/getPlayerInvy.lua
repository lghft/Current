function getplayerinvy()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    -- Call the actual GetPlayerInvy method from the module
    local inventoryData = ReplicatedStorage.remotes.reloadInvy:InvokeServer()
    
    if not inventoryData then
        print("ERROR: Failed to retrieve inventory data!")
        return nil
    end
    
    local allItems = {}
    local itemTypes = {"weapons", "chests", "helmets", "abilities"}
    
    -- Collect all items from inventory
    for _, itemType in ipairs(itemTypes) do
        if inventoryData[itemType] then
            for itemId, itemData in pairs(inventoryData[itemType]) do
                table.insert(allItems, {
                    type = itemType,
                    id = itemId,
                    data = itemData
                })
            end
        end
    end
    
    -- Print inventory
    print("╔══════════════════════════════════╗")
    print("║     PLAYER INVENTORY             ║")
    print("╚══════════════════════════════════╝")
    print("")
    print("Total items: " .. #allItems)
    print("")
    
    local itemTypeCount = {}
    for _, item in ipairs(allItems) do
        itemTypeCount[item.type] = (itemTypeCount[item.type] or 0) + 1
    end
    
    print("Breakdown:")
    for itemType, count in pairs(itemTypeCount) do
        print("  • " .. itemType .. ": " .. count)
    end
    print("")
    print("─────────────────────────────────────")
    print("")
    
    -- Print detailed item info
    local currentType = nil
    for i, item in ipairs(allItems) do
        if currentType ~= item.type then
            if currentType then print("") end
            print("📦 " .. string.upper(item.type))
            print("─────────────────────────────────────")
            currentType = item.type
        end
        
        local itemData = item.data
        
        -- Check if equipped
        local equippedStatus = ""
        if itemData.equipped == true then
            equippedStatus = " ✓ [EQUIPPED]"
        elseif itemData.equipped and type(itemData.equipped) == "table" then
            for key, val in pairs(itemData.equipped) do
                if val == true then
                    equippedStatus = " ✓ [EQUIPPED: " .. string.upper(key) .. "]"
                    break
                end
            end
        end
        
        print("[" .. item.id .. "] " .. itemData.name .. equippedStatus)
        print("    Rarity: " .. itemData.rarity)
        print("    Level Req: " .. itemData.levelReq)
        
        if itemData.physicalDamage then
            print("    Physical Damage: " .. itemData.physicalDamage)
        end
        if itemData.physicalPower and itemData.physicalPower > 0 then
            print("    Physical Power: " .. itemData.physicalPower)
        end
        if itemData.spellPower and itemData.spellPower > 0 then
            print("    Spell Power: " .. itemData.spellPower)
        end
        if itemData.health then
            print("    Health: " .. itemData.health)
        end
        if itemData.currentUpgrade then
            print("    Upgrade: " .. itemData.currentUpgrade .. "/" .. itemData.maxUpgrades)
        end
        if itemData.description then
            print("    Description: " .. itemData.description)
        end
        if itemData.sellPrice then
            print("    Sell Price: " .. itemData.sellPrice)
        end
        
        print("")
    end
    
    print("╔══════════════════════════════════╗")
    print("║         END OF INVENTORY         ║")
    print("╚══════════════════════════════════╝")
    
    return inventoryData
end

-- Call the function
getplayerinvy()
