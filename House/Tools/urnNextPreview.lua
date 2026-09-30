--Shows the next drops of the amount of urns used
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UrnsModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Urns"))
local chosenUrn = "TitanUrn"
local urnAmount = 30
-- Helper function to format tables nicely for output
local function inspectTable(tbl, indent)
	indent = indent or "    "
	local result = {}
	for k, v in pairs(tbl) do
		local formatting = string.format("%s%s = ", indent, tostring(k))
		if type(v) == "table" then
			table.insert(result, formatting .. "{\n" .. inspectTable(v, indent .. "    ") .. "\n" .. indent .. "}")
		else
			table.insert(result, string.format("%s%s", formatting, tostring(v)))
		end
	end
	return table.concat(result, "\n")
end

local function inspectUrnRewards(urnName: string, previewCount: number, targetPlayer: Player?)
	local player = targetPlayer or Players:GetPlayers()[1]
	
	local success, rewards = pcall(function()
		return UrnsModule.getNextRewards(urnName, previewCount, player)
	end)
	
	if not success then
		warn(string.format("Error fetching rewards for '%s': %s", urnName, tostring(rewards)))
		return
	end
	
	print(string.format("\n=== Next %d Reward(s) for Urn: %s ===", previewCount, urnName))
	if rewards and #rewards > 0 then
		for index, reward in ipairs(rewards) do
			if type(reward) == "table" then
				print(string.format("  [%d] -> Table Contents:", index))
				print(inspectTable(reward, "      "))
			else
				print(string.format("  [%d] -> %s", index, tostring(reward)))
			end
		end
	else
		print("  No rewards returned. Verify the urn name exists in your Items database.")
	end
	print("====================================================\n")
end

-- Example Usage:
inspectUrnRewards(tostring(chosenUrn), urnAmount)
