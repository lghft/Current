-- Mausoleum Macro Manager
-- LATEST CHANGES:
-- • Added "Auto Replay" toggle (Main tab): fires RespondToQuery("game_over", true) when phase == "over" and the GameOver GUI exists
-- • Added "Auto Petrify Break" toggle to automatically fire PetrifyBreakout click detectors
-- • Final tier (6/6) waits for a RoomKey change / DraculaCrypt; closest-Gather check; Gather path in status label with position
-- • Added Current RoomKey display under the gather part in the status label
-- • Updated gather check to strictly compare against Teleport Gather part + 30-stud proximity fallback check
-- • Room anchor now resolved by scanning slots using Teleport-matching logic; playback waits for build phase + delay
-- • Debug button: teleport to the tower the current macro step acts on
-- • ProximityPrompt.HoldDuration set to 0 and triggered using fireproximityprompt(prompt) for instant vault fire
-- • Vault teleport only at 6/6 tier
-- • Special case: 5/6 cleared phase with Slot4 Tier=6 detection teleports directly to Slot5
-- • 3 second delay before build phase before macro swap
-- • 2 second delay before teleporting to next room (with teleport validation failsafe)
-- • Added red (previous) and green (current) gather part sphere indicators during playback
-- • Added "Current Playback Part" tracking with action/position info under Current RoomKey

local success, initError = pcall(function()
    if not game:IsLoaded() then game.Loaded:Wait() end

    local sessionEnvironment = (getgenv and getgenv()) or shared
    local sessionKey = "MausoleumMacroManager_Session"
    local previousSession = sessionEnvironment[sessionKey]

    if previousSession then
        if previousSession.Window then
            pcall(function() previousSession.Window:Unload() end)
        end
    end

    local currentSession = {Loading = true}
    sessionEnvironment[sessionKey] = currentSession

    -- Loops use this instead of Window.unloaded (Window doesn't exist yet when they start)
    local function sessionAlive()
        return sessionEnvironment[sessionKey] == currentSession
    end

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = Players.LocalPlayer
    local player_gui = LocalPlayer:WaitForChild("PlayerGui")

    local EquippingModule = require(ReplicatedStorage.Modules.Equipping)
    local Inventory = require(ReplicatedStorage.Modules.Inventory)
    local TowerDatabase = require(ReplicatedStorage.Databases.Items.Tower)

    print("[Mausoleum] Loading Rayfield UI...")
    local rayfieldSuccess, Rayfield = pcall(function()
        return loadstring(game:HttpGet('https://raw.githubusercontent.com/lghft/Current/refs/heads/main/astd/Lib/gen2'))()
    end)

    if not rayfieldSuccess or not Rayfield then
        error("Failed to load Rayfield Gen2 library from URL.")
    end

    -- Forward declaration (used by the watcher loop before the real definition)
    local refreshDropdowns

    _G.is_recording = false
    _G.is_playing = false
    -- Bumped every time a playback is started or stopped; a running macro only keeps
    -- going while its own token is still current (so a stopped macro can never
    -- resume or clobber the state of the macro that replaced it).
    local playbackToken = 0

    -- ============================================================================
    -- FILE SYSTEM & CONFIGURATION
    -- ============================================================================

    local ROOT_FOLDER = "HouseMausoleum"
    local SAVE_FOLDER = ROOT_FOLDER .. "/Macros"
    local CONFIG_FOLDER = ROOT_FOLDER .. "/Configs"

    if writefile and makefolder then
        if not isfolder(ROOT_FOLDER) then makefolder(ROOT_FOLDER) end
        if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
        if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
    end

    -- ============================================================================
    -- SETTINGS & MAP PERSISTENCE
    -- ============================================================================

    getgenv().MacroMapConfig = getgenv().MacroMapConfig or {}

    local DEFAULT_SETTINGS = {
        macro_profile = "None available",
        macro_record = false,
        macro_playback = false,
        auto_room_playback = true,
        playback_type = "Time",
        macro_record_time_offset = 0,
        macro_playback_time_offset = 0,
        auto_fire_delay = 0.25,
        room_resolve_delay = 1.5,
        use_closest_gather = false,
        final_tier_wait = false,
        retry_on_fail = true,
        retry_delay = 1,
        max_retries = 5,
        use_returning_units = true,
        auto_ready = true,
        auto_difficulty = false,
        difficulty_choice = "Normal",
        macro_maps = {},
        -- AUTO-UPGRADE SETTINGS
        auto_sequential_upgrade = false,
        auto_upgrade_priority = "1,2,3,4,5",
        auto_upgrade_delay = 0.1,
        -- AUTO-TELEPORT SETTINGS
        auto_teleport_next_room = false,
        -- AUTO-PETRIFY BREAK SETTINGS
        auto_petrify_break = false,
        -- AUTO-REPLAY SETTINGS
        auto_replay = false,
    }

    local SETTINGS_FILE = CONFIG_FOLDER .. "/MacroSettings.json"
    local Settings = {}
    for k, v in pairs(DEFAULT_SETTINGS) do Settings[k] = v end

    if readfile and isfile and isfile(SETTINGS_FILE) then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(SETTINGS_FILE))
        end)
        if ok and type(decoded) == "table" then
            for k, _ in pairs(DEFAULT_SETTINGS) do
                if decoded[k] ~= nil then Settings[k] = decoded[k] end
            end
            if type(decoded.macro_maps) == "table" then
                getgenv().MacroMapConfig = decoded.macro_maps
            end
        end
    end

    Settings.macro_record = false

    local function SaveSettings()
        pcall(function()
            if writefile then
                Settings.macro_maps = getgenv().MacroMapConfig or {}
                writefile(SETTINGS_FILE, HttpService:JSONEncode(Settings))
            end
        end)
    end

    local MAUSOLEUM_ROOMS = {
        "Descent", "Ossuary", "Flooded", "BonePit", "Chapel",
        "Sarcophagi", "GreatCrypt", "BloodCellar", "CoffinHall",
        "BatRoost", "RedFountain", "BridesGallery", "Catacombs",
        "FeastHall", "CarriageVault", "Reliquary", "Cloister",
        "DraculaCrypt", "BloodThrone", "Tomb"
    }

    local function getSelectionString(selected)
        if type(selected) == "table" then return selected[1]
        elseif type(selected) == "string" then return selected end
        return nil
    end

    -- ============================================================================
    -- CASH & TOWER DATABASE UTILITIES
    -- ============================================================================

    local CashUtils = nil
    local function initCashUtils()
        if not CashUtils then
            pcall(function()
                CashUtils = require(ReplicatedStorage.Modules.Round.utils.cash_utils)
            end)
        end
        return CashUtils
    end

    local function getPlayerCash()
        local cashUtils = initCashUtils()
        if cashUtils and cashUtils.getRoundCash then
            local ok, cash = pcall(function() return cashUtils.getRoundCash(LocalPlayer) end)
            if ok and cash then return cash or 0 end
        end

        local ok, result = pcall(function()
            local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
            if not PlayerGui then return 0 end
            local path = {"MainHud", "Hud", "RoundHud", "Hud", "Inner", "BottomCentre", "Cash"}
            local current = PlayerGui
            for _, name in ipairs(path) do
                current = current:FindFirstChild(name)
                if not current then return 0 end
            end
            if current:IsA("TextLabel") then
                local cashText = tostring(current.Text)
                local cleaned = cashText:gsub("[$,]", "")
                return tonumber(cleaned) or 0
            end
            return 0
        end)
        return ok and result or 0
    end

    local function waitForCash(amount, maxWait, token)
        maxWait = maxWait or 60
        local startTime = os.clock()
        while getPlayerCash() < amount do
            if not _G.is_playing or (token and token ~= playbackToken) then return false end
            if os.clock() - startTime > maxWait then return false end
            task.wait(0.1)
        end
        return true
    end

    -- ============================================================================
    -- PERK DETECTION (placement discount)
    -- ============================================================================

    local PerkCache = {
        lastUpdate = 0,
        updateInterval = 5,
        cachedPerks = {},
        placeDiscountMultiplier = 1.0,
    }

    local PLACEMENT_AFFECTING_PERKS = {
        placeDiscount = true,
        startingCash = true,
        moneyGain = true,
    }

    local function getPerkDatabase()
        local ok, nodes = pcall(function()
            return require(ReplicatedStorage.Databases.SkillTreeNodes)
        end)
        return ok and nodes or {}
    end

    local function getUnlockedPerks()
        local ok, skillTree = pcall(function()
            return require(ReplicatedStorage.Modules.SkillTree)
        end)
        if not ok then return {} end
        local ok2, unlocked = pcall(skillTree.unlocked)
        if not ok2 or type(unlocked) ~= "table" then return {} end
        local list = {}
        for nodeId, isUnlocked in pairs(unlocked) do
            if isUnlocked then table.insert(list, nodeId) end
        end
        return list
    end

    local function getTeamFactions()
        local ok, factions = pcall(function()
            return require(ReplicatedStorage.Modules.Factions)
        end)
        if not ok then return {} end
        local teamFactions = {}
        pcall(function() teamFactions = factions.getTeamFactions() or {} end)
        return teamFactions
    end

    local function getActivePerks()
        local perkDb = getPerkDatabase()
        local teamFactions = getTeamFactions()
        local active = {}
        for _, perkId in ipairs(getUnlockedPerks()) do
            local node = perkDb[perkId]
            local reward = node and node.reward
            if reward and reward.type == "StatBoost" and PLACEMENT_AFFECTING_PERKS[reward.stat] then
                local isActive = true
                if reward.faction then
                    isActive = (teamFactions[reward.faction] or 0) > 0
                end
                if isActive then
                    active[reward.stat] = (active[reward.stat] or 0) + (reward.amount or 0)
                end
            end
        end
        return active
    end

    local function updatePerkCache()
        local now = os.clock()
        if now - PerkCache.lastUpdate < PerkCache.updateInterval then return end
        PerkCache.lastUpdate = now
        local ok, active = pcall(getActivePerks)
        if not ok then return end
        PerkCache.cachedPerks = active
        PerkCache.placeDiscountMultiplier = math.max(0.1, 1 - (active.placeDiscount or 0))
    end

    local function getPlaceDiscountMultiplier()
        updatePerkCache()
        return PerkCache.placeDiscountMultiplier
    end

    local function getAppliedPlacementCost(baseCost)
        return math.ceil(baseCost * getPlaceDiscountMultiplier())
    end

    local function logActivePlacementPerks()
        PerkCache.lastUpdate = 0
        updatePerkCache()
        local d = PerkCache.cachedPerks.placeDiscount or 0
        if d > 0 then
            return string.format("[Mausoleum] Place Discount active: %.0f%%", d * 100)
        end
        return "[Mausoleum] No place discount perks active"
    end

    -- ============================================================================
    -- HOTBAR & SLOT MAPPING
    -- ============================================================================

    local hotbarData = {}
    local hotbarCosts = {}
    local hotbarItemIds = {}

    local function initializeHotbar()
        local hotbarSlots = EquippingModule.getHotbar(LocalPlayer)
        local waitCount = 0
        while not hotbarSlots or #hotbarSlots == 0 do
            if waitCount > 50 then
                warn("[Mausoleum] Hotbar did not load in time")
                return false
            end
            task.wait(0.2)
            hotbarSlots = EquippingModule.getHotbar(LocalPlayer)
            waitCount = waitCount + 1
        end

        table.clear(hotbarData)
        table.clear(hotbarCosts)
        table.clear(hotbarItemIds)

        for slotIndex, itemUid in pairs(hotbarSlots) do
            if itemUid then
                hotbarData[slotIndex] = tostring(itemUid)
                local itemData = Inventory.getItem(itemUid)
                if itemData then
                    local baseId = itemData.itemId or itemData.id or itemData.uid
                    hotbarItemIds[slotIndex] = tostring(baseId)
                    local dbEntry = TowerDatabase[baseId]
                    if dbEntry and type(dbEntry) == "table" and dbEntry.stats then
                        local costs = {}
                        for level, levelData in pairs(dbEntry.stats) do
                            if type(levelData) == "table" and levelData.cost then
                                costs[tonumber(level) or level] = levelData.cost
                            end
                        end
                        hotbarCosts[slotIndex] = costs
                    end
                end
            end
        end
        return true
    end

    local function getSlotFromTowerUID(uid)
        for slotIndex, itemUid in pairs(hotbarData) do
            if tostring(itemUid) == tostring(uid) then
                return slotIndex
            end
        end
        return 1
    end

    local function getTowerPlacementCost(slotIndex)
        local costs = hotbarCosts[slotIndex]
        if costs and costs[1] then return getAppliedPlacementCost(costs[1]) end
        return 0
    end

    -- ============================================================================
    -- ROUND STATE & MAUSOLEUM DATA DETECTOR
    -- ============================================================================

    local function GetMausoleumData()
        local mausData = nil
        pcall(function()
            local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")
            if modulesFolder then
                local roundFolder = modulesFolder:FindFirstChild("Round")
                if roundFolder then
                    local atomModule = roundFolder:FindFirstChild("round_atom")
                    if atomModule then
                        local res = require(atomModule)
                        if type(res) == "function" then
                            local evaluated = res()
                            if type(evaluated) == "table" and evaluated.mausoleum then
                                mausData = evaluated.mausoleum
                            end
                        end
                    end
                end
            end
        end)
        return mausData
    end

    -- ============================================================================
    -- SINGLE SOURCE OF TRUTH: FIGHT TIMER
    -- ============================================================================

    local roomFightStart = nil

    task.spawn(function()
        local lastPhase, lastRoom, lastStep
        while sessionAlive() do
            local maus = GetMausoleumData()
            if maus then
                if maus.phase == "fight" then
                    if lastPhase ~= "fight" or maus.room ~= lastRoom or maus.step ~= lastStep then
                        roomFightStart = tick()
                    end
                else
                    roomFightStart = nil
                end
                lastPhase, lastRoom, lastStep = maus.phase, maus.room, maus.step
            else
                roomFightStart = nil
                lastPhase, lastRoom, lastStep = nil, nil, nil
            end
            task.wait(0.1)
        end
    end)

    local FINAL_TIER_TARGET_KEY = "DraculaCrypt"
    local FINAL_TIER_MAX_WAIT = 8
    local roomKeySnapshot = {}
    local finalTierSince = nil
    local finalTierLoggedKey = nil

    local function isFinalTier(maus)
        return maus ~= nil and tonumber(maus.step) == 6 and tonumber(maus.steps) == 6
    end

    local function getRoomSlots()
        local rooms = workspace:FindFirstChild("ActiveMap") and workspace.ActiveMap:FindFirstChild("Rooms")
        return rooms and rooms:GetChildren() or {}
    end

    -- Unified room model resolver leveraging strict RoomKey validation on shifted slots
    local function findRoomModelByKey(maus)
        if not maus or not maus.room then return nil end
        local activeRooms = workspace:FindFirstChild("ActiveMap")
            and workspace.ActiveMap:FindFirstChild("Rooms")
        if not activeRooms then return nil end

        local step = tonumber(maus.step) or 1
        local steps = tonumber(maus.steps) or 1
        local currentRoomKeyStr = tostring(maus.room)

        -- 1. Handle shifted tier layouts with strict RoomKey check
        if steps == 6 then
            if step == 5 then
                local slot4 = activeRooms:FindFirstChild("Slot4")
                if slot4 and tostring(slot4:GetAttribute("RoomKey")) == currentRoomKeyStr then
                    return slot4
                end
            elseif step == 6 then
                local slot5 = activeRooms:FindFirstChild("Slot5")
                if slot5 and tostring(slot5:GetAttribute("RoomKey")) == currentRoomKeyStr then
                    return slot5
                end
            end
        end

        -- 2. Direct slot target matching standard progression, validated by RoomKey
        local targetSlotName = "Slot" .. tostring(step)
        local slotModel = activeRooms:FindFirstChild(targetSlotName)
        if slotModel and tostring(slotModel:GetAttribute("RoomKey")) == currentRoomKeyStr then
            return slotModel
        end

        -- 3. Fallback: Search children strictly matching current RoomKey
        for _, child in ipairs(activeRooms:GetChildren()) do
            local roomKey = child:GetAttribute("RoomKey")
            if roomKey ~= nil and tostring(roomKey) == currentRoomKeyStr then
                return child
            end
        end

        return nil
    end

    local function matchRoomSlotByKey(maus)
        return findRoomModelByKey(maus)
    end

    local function getActiveRoomModel()
        local maus = GetMausoleumData()
        if not maus then return nil end
        return findRoomModelByKey(maus)
    end

    local function gatherObjCFrame(obj)
        if not obj then return nil end
        if obj:IsA("BasePart") then return obj.CFrame end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart.CFrame end
            local ok, pivot = pcall(function() return obj:GetPivot() end)
            if ok then return pivot end
        end
        return nil
    end

    -- Every "Gather" under ActiveMap.Rooms (cached for 0.5s with validity checks)
    local gatherCache = { time = 0, list = {} }
    local function getAllGatherParts()
        if tick() - gatherCache.time > 0.5 then
            gatherCache.time = tick()
            local list = {}
            pcall(function()
                local rooms = workspace:FindFirstChild("ActiveMap") and workspace.ActiveMap:FindFirstChild("Rooms")
                if rooms then
                    for _, d in ipairs(rooms:GetDescendants()) do
                        if d.Name == "Gather" and (d:IsA("BasePart") or d:IsA("Model")) then
                            if d:IsDescendantOf(workspace) and d.Parent ~= nil then
                                table.insert(list, d)
                            end
                        end
                    end
                end
            end)
            gatherCache.list = list
        end
        return gatherCache.list
    end

    local lastGatherLogKey = nil

    -- Fetches the Teleport Gather part and validates/re-checks closest Gather within 30 studs
    local function getActiveGatherPart()
        local teleportGather = nil
        local roomModel = getActiveRoomModel()
        if roomModel then
            teleportGather = roomModel:FindFirstChild("Gather") or roomModel:FindFirstChild("Gather", true)
        end

        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        
        local originPos = nil
        if hrp then
            originPos = hrp.Position
        elseif teleportGather then
            local tcf = gatherObjCFrame(teleportGather)
            if tcf then originPos = tcf.Position end
        end

        if not originPos then
            return teleportGather, "teleport_slot"
        end

        local closestIn30, closestDist = nil, math.huge
        for _, g in ipairs(getAllGatherParts()) do
            if g.Parent then
                local cf = gatherObjCFrame(g)
                if cf then
                    local d = (cf.Position - originPos).Magnitude
                    if d <= 30 and d < closestDist then
                        closestIn30 = g
                        closestDist = d
                    end
                end
            end
        end

        if teleportGather and closestIn30 == teleportGather then
            return teleportGather, "teleport_slot (verified)"
        end

        if closestIn30 then
            if closestIn30 == teleportGather then
                return closestIn30, "30-stud match"
            end
        end

        return teleportGather, "teleport_slot (fallback)"
    end

    local function getActiveRoomAnchorCFrame()
        local gatherCF = gatherObjCFrame(getActiveGatherPart())
        if gatherCF then return gatherCF end

        local roomModel = getActiveRoomModel()
        if roomModel then
            if roomModel:IsA("Model") and roomModel.PrimaryPart then return roomModel.PrimaryPart.CFrame
            elseif roomModel:IsA("Model") then return roomModel:GetPivot()
            elseif roomModel:IsA("BasePart") then return roomModel.CFrame end
        end
        return CFrame.new()
    end

    local function debugRoomSlots()
        local maus = GetMausoleumData()
        print("========== [Mausoleum] Room Slot Debug ==========")
        print("room:", tostring(maus and maus.room), "| step:", tostring(maus and maus.step), "| steps:", tostring(maus and maus.steps), "| phase:", tostring(maus and maus.phase))
        print("use_closest_gather:", tostring(Settings.use_closest_gather), "| final_tier_wait:", tostring(Settings.final_tier_wait))

        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local function distTo(obj)
            local cf = hrp and gatherObjCFrame(obj)
            return cf and string.format("%.0f", (cf.Position - hrp.Position).Magnitude) or "n/a"
        end

        local rooms = workspace:FindFirstChild("ActiveMap") and workspace.ActiveMap:FindFirstChild("Rooms")
        if not rooms then
            print("ActiveMap.Rooms not found")
            print("=================================================")
            return
        end

        for _, child in ipairs(rooms:GetChildren()) do
            local gather = child:FindFirstChild("Gather") or child:FindFirstChild("Gather", true)
            local matches = maus and tostring(child:GetAttribute("RoomKey")) == tostring(maus.room)
            print(string.format("%s%s [%s] RoomKey=%s | Tier=%s | Gather=%s | %s studs from you",
                matches and "* " or "  ", child.Name, child.ClassName,
                tostring(child:GetAttribute("RoomKey")), tostring(child:GetAttribute("Tier")),
                gather and gather:GetFullName() or "none", distTo(gather)))
        end
        print("(* = RoomKey matches the current room)")

        local plain = maus and matchRoomSlotByKey(maus)
        local resolved = maus and findRoomModelByKey(maus)
        local activeModel = getActiveRoomModel()
        print("plain RoomKey match :", plain and plain.Name or "none")
        print("resolved slot       :", resolved and resolved.Name or "none (waiting / no match)")
        print("active room model   :", activeModel and activeModel.Name or "none")
        print("=================================================")
    end

    local function getNextRoomModel()
        local maus = GetMausoleumData()
        if not maus then return nil end

        local activeRooms = workspace:FindFirstChild("ActiveMap")
            and workspace.ActiveMap:FindFirstChild("Rooms")

        if activeRooms then
            local nextStep = (maus.step or 1) + 1
            local targetSlotName = "Slot" .. tostring(nextStep)
            local slotModel = activeRooms:FindFirstChild(targetSlotName)
            if slotModel then return slotModel end

            for _, child in ipairs(activeRooms:GetChildren()) do
                local roomKey = child:GetAttribute("RoomKey")
                local tier = child:GetAttribute("Tier")
                if roomKey == maus.room and (tier == nextStep or tostring(child.Name):find(tostring(nextStep))) then
                    return child
                end
            end
        end
        return nil
    end

    local function getCurrentWaveNumber()
        local ok, waveNum = pcall(function()
            for _, descendant in ipairs(player_gui:GetDescendants()) do
                if descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
                    local text = descendant.Text
                    if text and text ~= "" then
                        local lowerText = string.lower(text)
                        if string.find(lowerText, "wave") or string.find(string.lower(descendant.Name), "wave") then
                            if string.find(lowerText, "starting") then
                                return 0
                            end
                            local num = string.match(text, "(%d+)")
                            if num then return tonumber(num) end
                        end
                    end
                end
            end
            return 1
        end)
        if ok and waveNum ~= nil then return waveNum end
        return 1
    end

    local function getCurrentWave()
        return tostring(getCurrentWaveNumber())
    end

    local function formatPos(value)
        local p
        if typeof(value) == "CFrame" then p = value.Position
        elseif typeof(value) == "Vector3" then p = value end
        if not p then return "Unknown" end
        return string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z)
    end

    local function isTowerInWorkspace(serverId)
        if not serverId then return false end
        local strId = tostring(serverId)
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") then
                local attrId = obj:GetAttribute("ServerId") or obj:GetAttribute("serverId") or obj:GetAttribute("Id") or obj:GetAttribute("UUID")
                local valId = obj:FindFirstChild("ServerId") or obj:FindFirstChild("serverId") or obj:FindFirstChild("Id")
                if (attrId and tostring(attrId) == strId) or
                   (valId and valId:IsA("ValueBase") and tostring(valId.Value) == strId) or
                   (obj.Name == strId) then
                    return true
                end
            end
        end
        return false
    end

    local function GetReturningTowersInfo()
        local infoList = {}
        pcall(function()
            local maus = GetMausoleumData()
            if maus then
                local playerKey = "#" .. LocalPlayer.Name
                local teamData = maus.teams and maus.teams[playerKey]
                local copies = teamData and teamData.copies or {}

                for key, copy in pairs(copies) do
                    if type(copy) == "table" and copy.state == "waiting" and copy.itemId then
                        local itemId = tostring(copy.itemId)
                        local level = tostring(copy.level or 1)
                        local selectId = tostring(copy.id or copy.uid or key)
                        table.insert(infoList, string.format("• %s (Lv %s) (%s)", itemId, level, selectId))
                    end
                end
            end
        end)

        if #infoList == 0 then return "Returning Towers: None / Room 1 Active" end
        return "Returning Towers:\n" .. table.concat(infoList, "\n")
    end

    -- ============================================================================
    -- RECORDING & PLAYBACK MODULE
    -- ============================================================================

    local SelectRemote = nil
    local function getSelectRemote()
        if not SelectRemote then
            pcall(function()
                SelectRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent:FindFirstChild("MausoleumSelect")
            end)
        end
        return SelectRemote
    end

    local function getBestReturningCopy(itemId)
        local bestId, bestLevel = nil, nil
        if not itemId then return nil, nil end
        pcall(function()
            local maus = GetMausoleumData()
            local teamData = maus and maus.teams and maus.teams["#" .. LocalPlayer.Name]
            local copies = teamData and teamData.copies
            if type(copies) ~= "table" then return end
            for key, copy in pairs(copies) do
                if type(copy) == "table" and copy.state == "waiting" and tostring(copy.itemId) == tostring(itemId) then
                    local level = tonumber(copy.level) or 1
                    if not bestLevel or level > bestLevel then
                        bestLevel = level
                        bestId = tostring(copy.id or copy.uid or key)
                    end
                end
            end
        end)
        return bestId, bestLevel
    end

    local function isCopyWaiting(selectId)
        local waiting = false
        pcall(function()
            local maus = GetMausoleumData()
            local teamData = maus and maus.teams and maus.teams["#" .. LocalPlayer.Name]
            local copies = teamData and teamData.copies
            if type(copies) ~= "table" then return end
            for key, copy in pairs(copies) do
                if type(copy) == "table" and tostring(copy.id or copy.uid or key) == tostring(selectId) and copy.state == "waiting" then
                    waiting = true
                end
            end
        end)
        return waiting
    end

    local SellRemote = nil
    local function sellTower(serverId)
        if not SellRemote then
            pcall(function()
                for _, d in ipairs(ReplicatedStorage.Modules.Remotes:GetDescendants()) do
                    if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and string.find(string.lower(d.Name), "sell") then
                        SellRemote = d
                        break
                    end
                end
            end)
        end
        if not SellRemote then
            warn("[Mausoleum] No sell remote found")
            return false
        end
        local ok = pcall(function()
            if SellRemote:IsA("RemoteFunction") then SellRemote:InvokeServer(serverId)
            else SellRemote:FireServer(serverId) end
        end)
        return ok
    end

    local RecordingStatusUI = { IsRecording = false, IsPlayback = false }
    local recordedActions = {}
    local isRecordingActive = false
    local CurrentStep = 0
    local recordingToMacro = nil
    local liveCurrentStepDescription = "Idle"

    local placedTowersCount = 0
    local activeTowerMap = {}

    -- ============================================================================
    -- AUTO SEQUENTIAL UPGRADE STATE & TRACKING
    -- ============================================================================

    local autoUpgradeState = {
        activeTowers = {},
        upgradeInProgress = {},
        lastUpgradeAttempt = {},
        currentlyUpgrading = nil,
        lastStatusUpdate = 0,
    }

    local UpgradeRemote = nil

    local function getUpgradeRemote()
        if not UpgradeRemote then
            pcall(function()
                UpgradeRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent:FindFirstChild("UpgradeTower")
            end)
        end
        if not UpgradeRemote then
            pcall(function()
                for _, d in ipairs(ReplicatedStorage.Modules.Remotes:GetDescendants()) do
                    if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and string.find(string.lower(d.Name), "upgrade") then
                        UpgradeRemote = d
                        break
                    end
                end
            end)
        end
        return UpgradeRemote
    end

    local function parsePriorityString(priorityStr)
        if type(priorityStr) == "table" then return priorityStr end
        local result = {}
        for num in tostring(priorityStr or "1,2,3,4,5"):gmatch("%d+") do
            local slot = tonumber(num)
            if slot and slot >= 1 and slot <= 5 and not table.find(result, slot) then
                table.insert(result, slot)
            end
        end
        return #result > 0 and result or {1,2,3,4,5}
    end

    local MAX_UPGRADE_LEVEL = 5

    local function getTowerName(itemId)
        local ok, name = pcall(function()
            local dbEntry = TowerDatabase[itemId]
            if dbEntry and type(dbEntry) == "table" and dbEntry.name then
                return dbEntry.name
            end
            return tostring(itemId)
        end)
        return ok and name or tostring(itemId)
    end

    local placedTowers = {}
    local placedTowerBySid = {}
    local placedRoomKey = nil

    local function currentRoomKey()
        local maus = GetMausoleumData()
        if not maus then return nil end
        return tostring(maus.room) .. ":" .. tostring(maus.step)
    end

    local function slotFromUid(uid)
        uid = tostring(uid)
        for slotIndex, hotbarUid in pairs(hotbarData) do
            if tostring(hotbarUid) == uid then return slotIndex end
        end
        return nil
    end

    local function registerPlacedTower(serverId, towerUid)
        local roomKey = currentRoomKey()
        if roomKey ~= placedRoomKey then
            table.clear(placedTowers)
            table.clear(placedTowerBySid)
            placedRoomKey = roomKey
        end

        local sid = tostring(serverId)
        if placedTowerBySid[sid] then return end

        local slot = slotFromUid(towerUid)
        local entry = {
            index = #placedTowers + 1,
            serverId = serverId,
            uid = tostring(towerUid),
            slot = slot,
            itemId = slot and hotbarItemIds[slot] or nil,
            level = 1,
            trackedLevel = 1,
            model = nil,
            seenModel = false,
            alive = true,
            nextScan = 0,
            pendingLevel = nil,
            pendingUntil = 0,
        }
        table.insert(placedTowers, entry)
        placedTowerBySid[sid] = entry
    end

    local function modelServerId(obj)
        local id = obj:GetAttribute("ServerId") or obj:GetAttribute("serverId")
            or obj:GetAttribute("Id") or obj:GetAttribute("UUID")
        if id == nil then
            local v = obj:FindFirstChild("ServerId") or obj:FindFirstChild("serverId") or obj:FindFirstChild("Id")
            if v and v:IsA("ValueBase") then id = v.Value end
        end
        return tostring(id or obj.Name)
    end

    local function scanTowerModels()
        local map = {}
        local function walk(parent, depth)
            for _, obj in ipairs(parent:GetChildren()) do
                if obj:IsA("Folder") then
                    if depth < 3 then walk(obj, depth + 1) end
                elseif obj:IsA("Model") then
                    map[modelServerId(obj)] = obj
                end
            end
        end
        pcall(walk, workspace, 1)
        return map
    end

    local function readModelLevel(model)
        local level = model:GetAttribute("Upgrade") or model:GetAttribute("Level") or model:GetAttribute("Evolution")
        if not level then
            local v = model:FindFirstChild("Upgrade") or model:FindFirstChild("Level") or model:FindFirstChild("Evolution")
            if v and v:IsA("ValueBase") then level = v.Value end
        end
        if not level then
            local LEVEL_NAMES = {
                level = true, lvl = true, upgrade = true, upgrades = true, upgradelevel = true,
                upgradelvl = true, towerlevel = true, currentlevel = true, tier = true, evolution = true,
            }
            local ok, attrs = pcall(function() return model:GetAttributes() end)
            if ok and type(attrs) == "table" then
                for name, value in pairs(attrs) do
                    if type(value) == "number" and LEVEL_NAMES[string.lower(name)] and value >= 0 and value <= 10 then
                        level = value
                        break
                    end
                end
            end
        end
        return tonumber(level)
    end

    local function parseLevelFromText(text)
        if type(text) ~= "string" then return nil end
        text = text:gsub("<[^>]+>", "")
        local n = text:match("%((%d+)%)%s*$") or text:match("%((%d+)%)")
        return tonumber(n)
    end

    local function isLevelLabel(obj)
        return (obj:IsA("TextLabel") or obj:IsA("TextBox")) and parseLevelFromText(obj.Text) ~= nil
    end

    local billboardCache = { time = 0, list = {} }
    local function getAdornedBillboards()
        if tick() - billboardCache.time > 2 then
            billboardCache.time = tick()
            local list = {}
            pcall(function()
                for _, gui in ipairs(player_gui:GetDescendants()) do
                    if gui:IsA("BillboardGui") and gui.Adornee then
                        table.insert(list, gui)
                    end
                end
            end)
            billboardCache.list = list
        end
        return billboardCache.list
    end

    local function findLevelLabel(model, nameLower)
        local first = nil
        local function consider(obj)
            if not isLevelLabel(obj) then return false end
            first = first or obj
            if nameLower and nameLower ~= "" and string.find(string.lower(obj.Text), nameLower, 1, true) then
                return true
            end
            return false
        end

        local ok, best = pcall(function()
            for _, d in ipairs(model:GetDescendants()) do
                if consider(d) then return d end
            end
            for _, gui in ipairs(getAdornedBillboards()) do
                local adornee = gui.Adornee
                if adornee and (adornee == model or adornee:IsDescendantOf(model)) then
                    for _, d in ipairs(gui:GetDescendants()) do
                        if consider(d) then return d end
                    end
                end
            end
            return nil
        end)
        if ok and best then return best end
        return first
    end

    local function refreshEntry(entry, models)
        if not entry.slot then
            entry.slot = slotFromUid(entry.uid)
            entry.itemId = entry.slot and hotbarItemIds[entry.slot] or entry.itemId
        end

        local sid = tostring(entry.serverId)
        local model = entry.model
        if model and not model.Parent then model = nil end

        if not model then
            if models then
                model = models[sid]
            elseif tick() >= entry.nextScan then
                entry.nextScan = tick() + 1
                model = scanTowerModels()[sid]
            end
        end

        if model then
            entry.model = model
            entry.seenModel = true
            entry.alive = true
            local lvl, source = nil, nil

            local label = entry.levelLabel
            if label and not label.Parent then label = nil end
            if not label and tick() >= (entry.nextLabelScan or 0) then
                entry.nextLabelScan = tick() + (entry.labelSeen and 0.5 or 3)
                label = findLevelLabel(model, string.lower(tostring(getTowerName(entry.itemId))))
                entry.levelLabel = label
            end
            if label then
                lvl = parseLevelFromText(label.Text)
                if lvl then
                    entry.labelSeen = true
                    source = "nameplate"
                end
            end

            if not lvl and not entry.labelSeen then
                lvl = readModelLevel(model)
                if lvl then source = "model attribute" end
            end

            if lvl then
                entry.levelReadable = true
                entry.levelSource = source
                entry.level = lvl
                entry.trackedLevel = lvl
            elseif entry.labelSeen then
                entry.levelReadable = true
            else
                entry.levelReadable = false
                entry.levelSource = "tracked"
                entry.level = entry.trackedLevel
            end
        else
            entry.model = nil
            if entry.seenModel then entry.alive = false end
            entry.level = entry.trackedLevel
        end
    end

    local function refreshPlacedTowers()
        local models = scanTowerModels()
        for _, entry in ipairs(placedTowers) do
            refreshEntry(entry, models)
        end
    end

    local function noteUpgradeFired(serverId)
        local entry = placedTowerBySid[tostring(serverId)]
        if not entry then return end
        entry.hookFires = (entry.hookFires or 0) + 1
        if not entry.levelReadable then
            entry.trackedLevel = math.min(MAX_UPGRADE_LEVEL, (entry.trackedLevel or 1) + 1)
            entry.level = entry.trackedLevel
        end
    end

    local function upgradeToNextLevel(serverId)
        if not serverId or autoUpgradeState.upgradeInProgress[tostring(serverId)] then
            return false
        end

        local remote = getUpgradeRemote()
        if not remote then
            return false
        end

        autoUpgradeState.upgradeInProgress[tostring(serverId)] = true
        local success = false
        local id = tonumber(serverId) or serverId

        pcall(function()
            if remote:IsA("RemoteFunction") then
                remote:InvokeServer(id)
            else
                remote:FireServer(id)
            end
            success = true
        end)

        task.wait(0.2)
        autoUpgradeState.upgradeInProgress[tostring(serverId)] = nil
        return success
    end

    local playbackState = {
        IsPlaying = false,
        CurrentStep = 0,
        TotalSteps = 0,
        ActionName = "None",
    }

    local function startRecording()
        recordedActions = {}
        isRecordingActive = true
        CurrentStep = 0
        placedTowersCount = 0
        activeTowerMap = {}
        recordingToMacro = Settings.macro_profile
        liveCurrentStepDescription = "Recording Initialized"
        RecordingStatusUI.IsRecording = true
    end

    local function stopRecording()
        isRecordingActive = false
        liveCurrentStepDescription = "Idle"
        RecordingStatusUI.IsRecording = false
        return recordedActions
    end

    local function deserializeValue(value)
        if type(value) == "table" and value.__type then
            if value.__type == "CFrame" and value.components then
                return CFrame.new(unpack(value.components))
            elseif value.__type == "Vector3" then
                return Vector3.new(value.x, value.y, value.z)
            end
        end
        return value
    end

    local function serializeValue(value)
        if typeof(value) == "CFrame" then
            return { __type = "CFrame", components = {value:GetComponents()} }
        elseif typeof(value) == "Vector3" then
            return { __type = "Vector3", x = value.X, y = value.Y, z = value.Z }
        else
            return value
        end
    end

    local function serializeArgs(args)
        local serialized = {}
        for i, arg in ipairs(args) do serialized[i] = serializeValue(arg) end
        return serialized
    end

    local function saveRecordedMacro(macroName, actions)
        if not writefile or not macroName or macroName == "None available" or #actions == 0 then return false end
        local path = SAVE_FOLDER .. "/" .. macroName .. ".json"
        local ok = pcall(function()
            local actionsToSave = {}
            for _, action in ipairs(actions) do
                table.insert(actionsToSave, {
                    action = action.action,
                    arguments = serializeArgs(action.arguments),
                    time = action.time,
                    wave = action.wave,
                    index = action.index,
                    room = action.room,
                    step = action.step,
                    slot = action.slot
                })
            end
            writefile(path, HttpService:JSONEncode(actionsToSave))
        end)
        return ok
    end

    local function getActiveMacroName(isManualPlayback, notifyFunc)
        local maus = GetMausoleumData()
        local currentRoom = maus and maus.room or "Unknown"
        local selectedMacro = Settings.macro_profile

        if maus and maus.room then
            local mappedMacro = getgenv().MacroMapConfig[maus.room]
            if mappedMacro and mappedMacro ~= "None" and mappedMacro ~= "None available" then
                if isManualPlayback and selectedMacro ~= mappedMacro then
                    if notifyFunc then
                        notifyFunc({
                            title = "Macro Mismatch",
                            content = string.format("Current Macro: %s doesn't match Current Room: %s\nPlaying Macro: %s instead.", selectedMacro, currentRoom, mappedMacro),
                            duration = 4
                        })
                    end
                end
                return mappedMacro
            end
        end
        return selectedMacro
    end

    -- ============================================================================
    -- SAFE NON-RECURSIVE HOOK
    -- ============================================================================

    local RemotesPath = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Remotes")
    local PlaceTowerEvent = RemotesPath:WaitForChild("RemoteFunction"):WaitForChild("PlaceTower")

    local mtHook; mtHook = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()

        if not sessionAlive() then
            return mtHook(self, ...)
        end

        local args = {...}

        if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and self.Name == "UpgradeTower" then
            pcall(noteUpgradeFired, args[1])
        end

        if not isRecordingActive then
            if rawequal(self, PlaceTowerEvent) and method == "InvokeServer" then
                local results = table.pack(mtHook(self, ...))
                if results[1] then
                    pcall(registerPlacedTower, results[1], args[1])
                end
                return table.unpack(results, 1, results.n)
            end
            return mtHook(self, ...)
        end

        if rawequal(self, PlaceTowerEvent) and method == "InvokeServer" then
            local results = table.pack(mtHook(self, ...))

            placedTowersCount = placedTowersCount + 1
            local assignedIndex = placedTowersCount

            local serverTowerId = results[1]
            if serverTowerId then
                activeTowerMap[tostring(serverTowerId)] = assignedIndex
                pcall(registerPlacedTower, serverTowerId, args[1])
            end

            task.spawn(function()
                local ok, err = pcall(function()
                    local slotIndex = getSlotFromTowerUID(args[1])
                    local recordedCFrame = args[2]
                    if typeof(recordedCFrame) == "Vector3" then recordedCFrame = CFrame.new(recordedCFrame) end

                    local localOffset = recordedCFrame
                    if typeof(recordedCFrame) == "CFrame" then
                        localOffset = getActiveRoomAnchorCFrame():ToObjectSpace(recordedCFrame)
                    end

                    local maus = GetMausoleumData()
                    local currentRoom = maus and maus.room or "Unknown"
                    local currentStep = maus and maus.step or 1
                    local currentPhase = maus and maus.phase or "unknown"

                    local actionTime = 0
                    if currentPhase == "fight" and roomFightStart then
                        actionTime = tick() - roomFightStart
                    end

                    CurrentStep = CurrentStep + 1
                    table.insert(recordedActions, {
                        action = "PlaceTower",
                        arguments = { slotIndex, localOffset },
                        time = actionTime,
                        wave = getCurrentWave(),
                        index = assignedIndex,
                        room = currentRoom,
                        step = currentStep,
                        slot = slotIndex
                    })

                    liveCurrentStepDescription = string.format("Placed Slot:%s at %s", tostring(slotIndex), formatPos(recordedCFrame))
                end)
                if not ok then warn("[Mausoleum] Record error:", err) end
            end)

            return table.unpack(results, 1, results.n)
        end

        if method == "FireServer" or method == "InvokeServer" then
            local remoteName = self.Name
            local lowerName = string.lower(remoteName)

            if string.find(lowerName, "upgrade") or string.find(lowerName, "sell") or string.find(lowerName, "skip")
                or string.find(lowerName, "ability") or string.find(lowerName, "target") or string.find(lowerName, "priority") then

                local assignedIndex = nil
                if args[1] then
                    assignedIndex = activeTowerMap[tostring(args[1])] or args[1]
                end

                local results = table.pack(mtHook(self, ...))
                task.spawn(function()
                    local ok, err = pcall(function()
                        local maus = GetMausoleumData()
                        local currentRoom = maus and maus.room or "Unknown"
                        local currentStep = maus and maus.step or 1
                        local currentPhase = maus and maus.phase or "unknown"

                        local actionTime = 0
                        if currentPhase == "fight" and roomFightStart then
                            actionTime = tick() - roomFightStart
                        end

                        CurrentStep = CurrentStep + 1
                        table.insert(recordedActions, {
                            action = remoteName,
                            arguments = args,
                            time = actionTime,
                            wave = getCurrentWave(),
                            index = assignedIndex,
                            room = currentRoom,
                            step = currentStep
                        })

                        liveCurrentStepDescription = string.format("Recorded %s (Tower #%s)", remoteName, tostring(assignedIndex))
                    end)
                    if not ok then warn("[Mausoleum] Record error:", err) end
                end)
                return table.unpack(results, 1, results.n)
            end
        end

        return mtHook(self, ...)
    end)

    print("[Mausoleum] ✓ Safe non-recursive PlaceTower hook applied")

    local function readMacroFile(macroName)
        if not macroName or macroName == "None available" then return nil end
        local filePath = SAVE_FOLDER .. "/" .. macroName .. ".json"
        if readfile and isfile and isfile(filePath) then
            local ok, actions = pcall(function() return HttpService:JSONDecode(readfile(filePath)) end)
            if ok and type(actions) == "table" then return actions end
        end
        return nil
    end

    local function getMacroStepCount(macroName)
        local actions = readMacroFile(macroName)
        return actions and #actions or 0
    end

    -- ============================================================================
    -- PLAYBACK ENGINE
    -- ============================================================================

    local runningMacroName = "None"
    local debugStepTarget = nil
    local currentGatherMarker = nil
    local previousGatherMarker = nil

    local function removeGatherMarkers()
        if currentGatherMarker then pcall(function() currentGatherMarker:Destroy() end); currentGatherMarker = nil end
        if previousGatherMarker then pcall(function() previousGatherMarker:Destroy() end); previousGatherMarker = nil end
    end

    local function updateGatherMarkers()
        pcall(function()
            local gatherObj = getActiveGatherPart()
            local pos = nil
            if gatherObj then
                local cf = gatherObjCFrame(gatherObj)
                if cf then pos = cf.Position end
            end

            if pos then
                local shouldUpdate = false
                if not currentGatherMarker then
                    shouldUpdate = true
                else
                    local curPos = currentGatherMarker.Position
                    if (curPos - pos).Magnitude > 1 then
                        shouldUpdate = true
                    end
                end

                if shouldUpdate then
                    if currentGatherMarker then
                        if previousGatherMarker then previousGatherMarker:Destroy() end
                        previousGatherMarker = currentGatherMarker
                        previousGatherMarker.Color = Color3.fromRGB(255, 60, 60)
                        previousGatherMarker.Name = "PreviousGatherMarker"
                        currentGatherMarker = nil
                    end

                    local p = Instance.new("Part")
                    p.Name = "CurrentGatherMarker"
                    p.Shape = Enum.PartType.Ball
                    p.Size = Vector3.new(1.5, 1.5, 1.5)
                    p.Color = Color3.fromRGB(60, 255, 60)
                    p.Material = Enum.Material.Neon
                    p.Transparency = 0.15
                    p.Anchored = true
                    p.CanCollide = false
                    p.CanQuery = false
                    p.CanTouch = false
                    p.CastShadow = false
                    p.Position = pos
                    p.Parent = workspace
                    currentGatherMarker = p
                end
            end
        end)
    end

    local function createPlacementMarker(target)
        local pos
        if typeof(target) == "CFrame" then pos = target.Position
        elseif typeof(target) == "Vector3" then pos = target end
        if not pos then return nil end
        local ok, part = pcall(function()
            local p = Instance.new("Part")
            p.Name = "MacroPlacementMarker"
            p.Shape = Enum.PartType.Ball
            p.Size = Vector3.new(1.5, 1.5, 1.5)
            p.Color = Color3.fromRGB(255, 221, 0)
            p.Material = Enum.Material.Neon
            p.Transparency = 0.15
            p.Anchored = true
            p.CanCollide = false
            p.CanQuery = false
            p.CanTouch = false
            p.CastShadow = false
            p.Position = pos
            p.Parent = workspace
            return p
        end)
        return ok and part or nil
    end

    local function removePlacementMarker(marker)
        if marker then pcall(function() marker:Destroy() end) end
    end

    local function failPlacementMarker(marker)
        if not marker then return end
        pcall(function()
            marker:SetAttribute("Failed", true)
            marker.Color = Color3.fromRGB(255, 60, 60)
        end)
        task.delay(5, function() removePlacementMarker(marker) end)
    end

    local function dropMarkerUnlessFailed(marker)
        if not marker then return end
        local failed = false
        pcall(function() failed = marker:GetAttribute("Failed") == true end)
        if not failed then removePlacementMarker(marker) end
    end

    local readiedKeys = {}
    local ReadyRemote = nil

    local function fireReady()
        if not ReadyRemote then
            pcall(function()
                ReadyRemote = ReplicatedStorage.Modules.Remotes.RemoteEvent:FindFirstChild("MausoleumReady")
            end)
        end
        if not ReadyRemote then
            warn("[Mausoleum] MausoleumReady remote not found")
            return false
        end
        local ok = pcall(function() ReadyRemote:FireServer() end)
        return ok
    end

    local function requestReady()
        if not Settings.auto_ready then return end
        local maus = GetMausoleumData()
        if not maus then return end
        local key = tostring(maus.room) .. ":" .. tostring(maus.step)
        if readiedKeys[key] then return end
        readiedKeys[key] = true

        task.spawn(function()
            local deadline = tick() + 120
            while _G.is_playing and sessionAlive() and tick() < deadline do
                local m = GetMausoleumData()
                if not m or (tostring(m.room) .. ":" .. tostring(m.step)) ~= key then return end
                if m.phase == "build" then
                    if fireReady() then
                        liveCurrentStepDescription = "Build steps done - readied up"
                    end
                    return
                elseif m.phase ~= "seal" then
                    return
                end
                task.wait(0.25)
            end
        end)
    end

    local function actionRoomMatches(action, maus)
        if not maus then return false end
        if action.room and action.room ~= "" and maus.room ~= action.room then return false end
        return true
    end

    local roomReadyKey, roomReadyAt = nil, 0

    local function waitForRoomAnchor(isActive, label)
        while isActive() do
            updateGatherMarkers()
            local maus = GetMausoleumData()
            if maus and (maus.phase == "build" or maus.phase == "fight") then
                local model = findRoomModelByKey(maus)
                if model then
                    local key = tostring(maus.room) .. ":" .. tostring(maus.step) .. ":" .. model.Name
                    if roomReadyKey ~= key then
                        roomReadyKey = key
                        roomReadyAt = tick()
                    end
                    local remaining = (Settings.room_resolve_delay or 1.5) - (tick() - roomReadyAt)
                    if remaining <= 0 then return true end
                    liveCurrentStepDescription = string.format("%s Syncing room anchor (%s) %.1fs", label, model.Name, remaining)
                elseif isFinalTier(maus) and Settings.final_tier_wait then
                    liveCurrentStepDescription = string.format("%s Final tier: waiting for RoomKey change / %s", label, FINAL_TIER_TARGET_KEY)
                else
                    liveCurrentStepDescription = string.format("%s Waiting for room slot (RoomKey=%s)", label, tostring(maus.room))
                end
            else
                liveCurrentStepDescription = string.format("%s Waiting for build phase (now: %s)", label, tostring(maus and maus.phase))
            end
            task.wait(0.1)
        end
        return false
    end

    local function playbackMacro(actions, delayMultiplier, token)
        delayMultiplier = delayMultiplier or 1
        token = token or playbackToken

        local function active()
            return _G.is_playing and playbackToken == token and sessionAlive()
        end

        if not actions or #actions == 0 then
            if playbackToken == token then
                _G.is_playing = false
                runningMacroName = "None"
                removeGatherMarkers()
            end
            return
        end

        for i = 1, math.min(3, #actions) do
            local a = actions[i]
            print("[Macro]", i, a.action, "room=", a.room, "step=", a.step, "time=", a.time, "wave=", a.wave, "slot=", a.slot)
        end

        if next(hotbarData) == nil then
            liveCurrentStepDescription = "Loading hotbar..."
            initializeHotbar()
        end

        playbackState.IsPlaying = true
        playbackState.TotalSteps = #actions
        playbackState.CurrentStep = 0
        RecordingStatusUI.IsPlayback = true
        table.clear(readiedKeys)
        liveCurrentStepDescription = "Starting playback"

        for idx, action in ipairs(actions) do
            if not active() then break end

            updateGatherMarkers()
            playbackState.CurrentStep = idx
            playbackState.ActionName = action.action or "action"
            local actionNameLower = string.lower(playbackState.ActionName)

            if action.room and action.room ~= "" then
                while active() do
                    updateGatherMarkers()
                    local maus = GetMausoleumData()
                    if actionRoomMatches(action, maus) then break end
                    liveCurrentStepDescription = string.format("[%d/%d] Waiting for room %s (now: %s)",
                        idx, #actions, tostring(action.room), tostring(maus and maus.room))
                    task.wait(0.2)
                end
            end

            if not active() then break end

            if not waitForRoomAnchor(active, string.format("[%d/%d]", idx, #actions)) then break end

            local rawArgs = action.arguments or {}
            local finalArgs = {}
            for i, arg in ipairs(rawArgs) do finalArgs[i] = deserializeValue(arg) end

            local isPlace = actionNameLower:find("place") ~= nil
            local slotIndex = action.slot or finalArgs[1]

            do
                local dbgPos, dbgDesc = nil, nil
                if isPlace then
                    local lcf = finalArgs[2]
                    if typeof(lcf) == "CFrame" then
                        dbgPos = getActiveRoomAnchorCFrame():ToWorldSpace(lcf).Position
                    elseif typeof(lcf) == "Vector3" then
                        dbgPos = lcf
                    end
                    dbgDesc = string.format("Place Slot:%s", tostring(slotIndex))
                elseif finalArgs[1] ~= nil then
                    local model = scanTowerModels()[tostring(finalArgs[1])]
                    if model then
                        local okPivot, pivot = pcall(function() return model:GetPivot() end)
                        if okPivot and pivot then dbgPos = pivot.Position end
                    end
                    dbgDesc = string.format("%s (tower %s)", tostring(action.action), tostring(finalArgs[1]))
                end
                if dbgPos then
                    debugStepTarget = { pos = dbgPos, desc = dbgDesc, idx = idx }
                end
            end

            local pMode = Settings.playback_type or "Time"

            if (action.time or 0) > 0 then requestReady() end

            if (pMode == "Time" or pMode == "Hybrid") and (action.time or 0) > 0 then
                while active() and not roomFightStart do
                    updateGatherMarkers()
                    liveCurrentStepDescription = string.format("[%d/%d] Waiting for fight phase", idx, #actions)
                    task.wait(0.1)
                end
                if roomFightStart then
                    local timeDiff = action.time * delayMultiplier - (tick() - roomFightStart)
                    if timeDiff > 0 then
                        liveCurrentStepDescription = string.format("[%d/%d] Waiting %.1fs (action time %.1f)", idx, #actions, timeDiff, action.time)
                        task.wait(timeDiff)
                    end
                end
            end

            if pMode == "Money + Wave" and action.wave then
                local targetWave = tonumber(action.wave) or 1
                while active() and getCurrentWaveNumber() < targetWave do
                    updateGatherMarkers()
                    liveCurrentStepDescription = string.format("Waiting for Wave %d (Current: %d)", targetWave, getCurrentWaveNumber())
                    task.wait(0.25)
                end
            end

            if isPlace then
                local liveItemUid = hotbarData[slotIndex]
                if liveItemUid then finalArgs[1] = liveItemUid end

                local localCF = finalArgs[2]
                if typeof(localCF) == "CFrame" then
                    local anchorCF = getActiveRoomAnchorCFrame()
                    finalArgs[2] = anchorCF:ToWorldSpace(localCF)
                end
            end

            local placeDesc = isPlace and string.format("Slot:%s at %s", tostring(slotIndex), formatPos(finalArgs[2])) or nil
            local marker = isPlace and createPlacementMarker(finalArgs[2]) or nil

            if pMode == "Hybrid" or pMode == "Money" or pMode == "Money + Wave" then
                local requiredCost = 0
                if isPlace then
                    local returningId = Settings.use_returning_units and getBestReturningCopy(hotbarItemIds[slotIndex]) or nil
                    if returningId then
                        requiredCost = 0
                    else
                        requiredCost = getTowerPlacementCost(slotIndex)
                    end
                end
                if requiredCost > 0 then
                    liveCurrentStepDescription = string.format("[%d/%d] Waiting for $%d cash", idx, #actions, requiredCost)
                    waitForCash(requiredCost, 120, token)
                end
            end

            if not active() then
                removePlacementMarker(marker)
                break
            end

            local remotesFolder = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Remotes")
            if remotesFolder then
                local remote = (remotesFolder:FindFirstChild("RemoteFunction") and remotesFolder.RemoteFunction:FindFirstChild(playbackState.ActionName))
                            or (remotesFolder:FindFirstChild("RemoteEvent") and remotesFolder.RemoteEvent:FindFirstChild(playbackState.ActionName))
                            or remotesFolder:FindFirstChild(playbackState.ActionName, true)

                if remote then
                    local attempts = 0
                    local maxRetries = Settings.retry_on_fail and Settings.max_retries or 1
                    local stepSuccess = false

                    while not stepSuccess and attempts < maxRetries and active() do
                        attempts = attempts + 1
                        if isPlace then
                            liveCurrentStepDescription = string.format("[%d/%d] Placing %s", idx, #actions, placeDesc)
                        else
                            liveCurrentStepDescription = string.format("[%d/%d] Executing %s (Attempt %d/%d)", idx, #actions, playbackState.ActionName, attempts, maxRetries)
                        end

                        local usedSelectId = nil
                        if isPlace and Settings.use_returning_units then
                            local selectRemote = getSelectRemote()
                            local selectId, selLevel = getBestReturningCopy(hotbarItemIds[slotIndex])
                            if selectRemote and selectId then
                                pcall(function() selectRemote:FireServer(selectId) end)
                                usedSelectId = selectId
                                liveCurrentStepDescription = string.format("[%d/%d] Placing %s (returning Lv %s, id %s)", idx, #actions, placeDesc, tostring(selLevel), selectId)
                                task.wait(0.1)
                            end
                        end

                        local resultServerId = nil
                        pcall(function()
                            if remote:IsA("RemoteFunction") or remote.ClassName == "RemoteFunction" then
                                resultServerId = remote:InvokeServer(unpack(finalArgs))
                            elseif remote:IsA("RemoteEvent") or remote.ClassName == "RemoteEvent" then
                                remote:FireServer(unpack(finalArgs))
                                resultServerId = true
                            end
                        end)

                        if isPlace and usedSelectId then
                            local consumed = false
                            local deadline = tick() + 1.5
                            repeat
                                task.wait(0.1)
                                consumed = not isCopyWaiting(usedSelectId)
                            until consumed or tick() >= deadline or not active()

                            if consumed then
                                stepSuccess = true
                            elseif attempts >= maxRetries then
                                stepSuccess = (resultServerId ~= nil)
                                warn("[Mausoleum] Returning unit " .. tostring(usedSelectId) .. " was not consumed. PlaceTower returned: " .. tostring(resultServerId) .. " (nil = placement rejected)")
                            elseif resultServerId and resultServerId ~= true then
                                liveCurrentStepDescription = string.format("[%d/%d] Wrong unit placed, selling and retrying", idx, #actions)
                                sellTower(resultServerId)
                                task.wait(0.5)
                            end
                        elseif isPlace then
                            task.wait(0.3)
                            if resultServerId and resultServerId ~= true then
                                if isTowerInWorkspace(resultServerId) then stepSuccess = true end
                            else
                                stepSuccess = (resultServerId ~= nil)
                            end
                        else
                            stepSuccess = (resultServerId ~= nil)
                        end

                        if not stepSuccess and attempts < maxRetries then
                            task.wait(Settings.retry_delay or 1)
                        end
                    end

                    if isPlace then
                        if not stepSuccess and not active() then
                            removePlacementMarker(marker)
                        elseif stepSuccess then
                            liveCurrentStepDescription = string.format("[%d/%d] Placed Slot:%s Successfully at %s", idx, #actions, tostring(slotIndex), formatPos(finalArgs[2]))
                            removePlacementMarker(marker)
                        else
                            liveCurrentStepDescription = string.format("[%d/%d] Failed to Place Slot:%s at %s", idx, #actions, tostring(slotIndex), formatPos(finalArgs[2]))
                            failPlacementMarker(marker)
                        end
                    end
                else
                    liveCurrentStepDescription = string.format("[%d/%d] Remote not found: %s", idx, #actions, tostring(playbackState.ActionName))
                    warn("[Mausoleum] Remote not found:", playbackState.ActionName)
                end
            end

            do
                local nextAction = actions[idx + 1]
                if not nextAction or (nextAction.room and nextAction.room ~= "" and nextAction.room ~= action.room) then
                    requestReady()
                end
            end

            dropMarkerUnlessFailed(marker)
            task.wait(Settings.auto_fire_delay or 0.25)
        end

        if playbackToken == token then
            liveCurrentStepDescription = "Idle"
            playbackState.IsPlaying = false
            RecordingStatusUI.IsPlayback = false
            runningMacroName = "None"
            _G.is_playing = false
            removeGatherMarkers()
        end
    end

    local function startPlayback(macroName, actions)
        playbackToken = playbackToken + 1
        local token = playbackToken
        runningMacroName = macroName
        _G.is_playing = true
        task.spawn(function() playbackMacro(actions, nil, token) end)
    end

    local function stopPlayback()
        playbackToken = playbackToken + 1
        _G.is_playing = false
        playbackState.IsPlaying = false
        RecordingStatusUI.IsPlayback = false
        runningMacroName = "None"
        liveCurrentStepDescription = "Idle"
        removeGatherMarkers()
    end

    local lastAutoRoom = nil
    local lastBuildPhaseTime = nil

    task.spawn(function()
        while sessionAlive() do
            task.wait(0.5)
            local maus = GetMausoleumData()

            if maus and maus.phase == "over" then
                if _G.is_playing then
                    stopPlayback()
                    liveCurrentStepDescription = "Run over - playback reset (armed)"
                end
                lastAutoRoom = nil
                lastBuildPhaseTime = nil
                removeGatherMarkers()

            elseif Settings.macro_playback and Settings.auto_room_playback and not _G.is_recording then
                if maus and maus.phase == "build" then
                    if not lastBuildPhaseTime then
                        lastBuildPhaseTime = tick()
                        print("[Mausoleum] Build phase detected, waiting 3 seconds before macro swap")
                    end
                elseif maus and maus.phase ~= "build" then
                    lastBuildPhaseTime = nil
                end

                if maus and maus.room and maus.room ~= "" and maus.room ~= "None" then
                    if maus.room ~= lastAutoRoom then
                        local canSwap = false
                        if maus.phase == "fight" then
                            canSwap = true
                        elseif maus.phase == "build" and lastBuildPhaseTime
                            and (tick() - lastBuildPhaseTime >= (Settings.room_resolve_delay or 1.5)) then
                            canSwap = true
                        end

                        if canSwap then
                            lastAutoRoom = maus.room
                            local macroName = getActiveMacroName(false, nil)

                            if macroName and macroName ~= "None available" then
                                if _G.is_playing and runningMacroName == macroName then
                                else
                                    local actions = readMacroFile(macroName)
                                    if actions then
                                        if _G.is_playing then
                                            stopPlayback()
                                        end
                                        Settings.macro_profile = macroName
                                        SaveSettings()
                                        if refreshDropdowns then refreshDropdowns() end
                                        startPlayback(macroName, actions)
                                    else
                                        warn("[Mausoleum] Could not read macro file:", macroName)
                                    end
                                end
                            end
                        end
                    end
                else
                    lastAutoRoom = nil
                end
            end
        end
    end)

    local currentUpgradeTarget = nil
    local upgradeQueue = {}
    local lastQueueBuild = 0

    local function buildUpgradeQueue()
        local list = {}
        if not Settings.auto_sequential_upgrade then return list end

        refreshPlacedTowers()

        for _, slotIndex in ipairs(parsePriorityString(Settings.auto_upgrade_priority)) do
            local group = {}
            for _, entry in ipairs(placedTowers) do
                if entry.alive and entry.slot == slotIndex and (entry.level or 1) < MAX_UPGRADE_LEVEL then
                    table.insert(group, {
                        serverId = entry.serverId,
                        index = entry.index,
                        slot = slotIndex,
                        itemId = entry.itemId,
                        uid = entry.uid,
                        towerName = getTowerName(entry.itemId),
                        level = entry.level or 1,
                    })
                end
            end

            table.sort(group, function(a, b)
                if a.level ~= b.level then return a.level > b.level end
                return a.index < b.index
            end)

            for _, tower in ipairs(group) do
                table.insert(list, tower)
            end
        end

        return list
    end

    local function debugUpgradeQueue()
        local maus = GetMausoleumData()
        print("========== [Mausoleum] Upgrade Queue Debug ==========")
        print("auto_sequential_upgrade:", tostring(Settings.auto_sequential_upgrade), "| is_playing:", tostring(_G.is_playing), "| recording:", tostring(isRecordingActive))
        print("phase:", tostring(maus and maus.phase), "| room:", tostring(maus and maus.room), "| step:", tostring(maus and maus.step), "| roomFightStart set:", tostring(roomFightStart ~= nil))
        print("priority:", tostring(Settings.auto_upgrade_priority))

        local hotbarCount = 0
        for slot, uid in pairs(hotbarData) do
            hotbarCount = hotbarCount + 1
            print(string.format("hotbar slot %s -> uid=%s | itemId=%s | name=%s", tostring(slot), tostring(uid), tostring(hotbarItemIds[slot]), getTowerName(hotbarItemIds[slot])))
        end
        if hotbarCount == 0 then print("hotbar is EMPTY (not loaded?)") end

        refreshPlacedTowers()
        print("registered towers this room:", #placedTowers, "| room key:", tostring(placedRoomKey))
        for _, e in ipairs(placedTowers) do
            print(string.format("tower #%d | serverId=%s | uid=%s | slot=%s | name=%s | level=%s (%s) | tracked=%s | fires=%s | alive=%s | model=%s",
                e.index, tostring(e.serverId), tostring(e.uid), tostring(e.slot), getTowerName(e.itemId),
                tostring(e.level), tostring(e.levelSource or "tracked"), tostring(e.trackedLevel),
                tostring(e.hookFires or 0), tostring(e.alive), tostring(e.model and e.model.Name)))
            print("      nameplate:", e.levelLabel and e.levelLabel.Parent and tostring(e.levelLabel.Text) or "not found")
            if e.model then
                pcall(function()
                    for name, value in pairs(e.model:GetAttributes()) do
                        print("      attr", tostring(name), "=", tostring(value))
                    end
                end)
            end
        end

        local q = buildUpgradeQueue()
        print("queue size:", #q)
        for i, t in ipairs(q) do
            print(string.format("  queue[%d] %s | Lv%d | #%d | slot %s | serverId=%s", i, t.towerName, t.level, t.index, tostring(t.slot), tostring(t.serverId)))
        end
        print("=====================================================")
    end

    task.spawn(function()
        while sessionAlive() do
            task.wait(Settings.auto_upgrade_delay or 0.1)

            if Settings.auto_sequential_upgrade and not isRecordingActive and not _G.is_playing then
                local maus = GetMausoleumData()

                if maus and maus.phase == "fight" and roomFightStart then
                    if not currentUpgradeTarget or tick() - lastQueueBuild > 1 then
                        local previous = currentUpgradeTarget
                        upgradeQueue = buildUpgradeQueue()
                        lastQueueBuild = tick()

                        currentUpgradeTarget = nil
                        if previous then
                            for _, tower in ipairs(upgradeQueue) do
                                if tostring(tower.serverId) == tostring(previous.serverId) then
                                    currentUpgradeTarget = tower
                                    break
                                end
                            end
                        end
                        if not currentUpgradeTarget then
                            currentUpgradeTarget = upgradeQueue[1]
                        end
                    end

                    if currentUpgradeTarget then
                        local entry = placedTowerBySid[tostring(currentUpgradeTarget.serverId)]
                        if not entry then
                            currentUpgradeTarget = nil
                            lastQueueBuild = 0
                        else
                            refreshEntry(entry)
                            local level = entry.level or 1
                            currentUpgradeTarget.level = level

                            if not entry.alive or level >= MAX_UPGRADE_LEVEL then
                                currentUpgradeTarget = nil
                                lastQueueBuild = 0
                                autoUpgradeState.currentlyUpgrading = nil
                                autoUpgradeState.waitingForCash = false
                            else
                                local costs = entry.slot and hotbarCosts[entry.slot]
                                local cost = (costs and costs[level + 1]) or 0
                                local cash = getPlayerCash()
                                local needsCash = cost > 0 and cash < cost

                                autoUpgradeState.currentlyUpgrading = {
                                    serverId = entry.serverId,
                                    towerName = currentUpgradeTarget.towerName,
                                    index = entry.index,
                                    fromLevel = level,
                                    toLevel = level + 1,
                                    cost = cost,
                                    cash = cash,
                                    timestamp = tick(),
                                }
                                autoUpgradeState.waitingForCash = needsCash

                                local waitingForLevel = entry.pendingLevel ~= nil
                                    and level <= entry.pendingLevel
                                    and tick() < entry.pendingUntil

                                if not needsCash and not waitingForLevel then
                                    entry.pendingLevel = nil
                                    local firesBefore = entry.hookFires or 0

                                    if upgradeToNextLevel(entry.serverId) then
                                        entry.pendingLevel = level
                                        entry.pendingUntil = tick() + 1.5
                                        if (entry.hookFires or 0) == firesBefore and not entry.levelReadable then
                                            entry.trackedLevel = math.min(MAX_UPGRADE_LEVEL, level + 1)
                                            entry.level = entry.trackedLevel
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    currentUpgradeTarget = nil
                    upgradeQueue = {}
                    autoUpgradeState.currentlyUpgrading = nil
                    autoUpgradeState.waitingForCash = false
                end
            else
                currentUpgradeTarget = nil
                upgradeQueue = {}
                autoUpgradeState.currentlyUpgrading = nil
                autoUpgradeState.waitingForCash = false
            end
        end
    end)

    local function fileNameFromPath(file)
        local name = file:match("([^/\\]+)$") or file
        name = name:gsub("%.json$", "")
        return name
    end

    local function listMacroFiles()
        local list = {}
        pcall(function()
            if listfiles and isfolder and isfolder(SAVE_FOLDER) then
                for _, file in ipairs(listfiles(SAVE_FOLDER)) do
                    if file:sub(-5) == ".json" then
                        table.insert(list, fileNameFromPath(file))
                    end
                end
            end
        end)
        table.sort(list, function(a, b) return string.lower(a) < string.lower(b) end)
        return list
    end

    local function getSavedMacroList()
        local list = listMacroFiles()
        if #list == 0 then table.insert(list, "None available") end
        return list
    end

    local function getMapMacroList()
        local list = listMacroFiles()
        table.insert(list, 1, "None")
        return list
    end

    local MacroDropdown = nil
    local roomDropdowns = {}

    refreshDropdowns = function()
        local options = getSavedMacroList()
        if MacroDropdown then
            pcall(function()
                MacroDropdown:Refresh(options)
                MacroDropdown:Set({ Settings.macro_profile })
            end)
        end
        local mapOptions = getMapMacroList()
        for roomName, dropdown in pairs(roomDropdowns) do
            if dropdown then
                pcall(function()
                    dropdown:Refresh(mapOptions)
                    local curr = getgenv().MacroMapConfig[roomName]
                    dropdown:Set({ curr or "None" })
                end)
            end
        end
    end

    local Window = Rayfield:CreateWindow({
        name = "Mausoleum Macro Manager",
        subtitle = "Slot-Based Engine",
        configuration = { autoSave = false, autoLoad = false, fileName = "MacroSettings", customFolder = CONFIG_FOLDER },
    })

    local RayfieldWindow = Window
    currentSession.Window = Window
    currentSession.Loading = false

    local UIReady = false
    local function Guard(callback)
        return function(...)
            if not UIReady then return end
            return callback(...)
        end
    end

    local MainTab = Window:CreateTab({ name = "Main", icon = "house" })
    local MacroTab = Window:CreateTab({ name = "Macro", icon = "file-text" })
    local MapsTab = Window:CreateTab({ name = "Macro Maps", icon = "map" })
    local SettingsTab = Window:CreateTab({ name = "Settings", icon = "sliders-horizontal" })

    MacroTab:CreateSection({ name = "Macro Manager" })

    local function ValidateMacroSelection()
        local macroList = getSavedMacroList()
        local found = false
        for _, macro in ipairs(macroList) do
            if macro == Settings.macro_profile then found = true; break end
        end
        if not found then
            Settings.macro_profile = (macroList[1] and macroList[1] ~= "None available") and macroList[1] or "None available"
            SaveSettings()
        end
        return Settings.macro_profile
    end

    ValidateMacroSelection()

    MacroDropdown = MacroTab:CreateDropdown({
        name = "Macro Selector",
        options = getSavedMacroList(),
        value = { Settings.macro_profile },
        flag = "MacroSelector",
        callback = Guard(function(selected)
            local selection = getSelectionString(selected)
            if selection and selection ~= Settings.macro_profile then
                Settings.macro_profile = selection
                SaveSettings()
            end
        end),
    })

    MacroTab:CreateButton({
        name = "Refresh Macro List",
        callback = function()
            refreshDropdowns()
            Window:Notify({title = "Macro Manager", content = "Macro list refreshed.", duration = 2})
        end,
    })

    local StatusLabel = MacroTab:CreateText({ text = "Status: Idle\nCurrent Running Macro: None\nSelected Profile: None | Steps: 0 | Phase: None\nRoom: None\nTier: 0/0\nTime: 0.00s\nCurrentStep: Idle" })
    local ReturningTowersLabel = MacroTab:CreateText({ text = "Returning Towers: Scanning..." })

    local function getPhaseDescription(phaseKey)
        if phaseKey == "seal" then return "seal (difficulty)"
        elseif phaseKey == "build" then return "build (before fight)"
        elseif phaseKey == "fight" then return "fight (fighting)"
        elseif phaseKey == "cleared" then return "cleared (after fight)"
        elseif phaseKey == "vault" then return "vault (drops collection)"
        elseif phaseKey == "over" then return "over (GameEndGui)"
        else return phaseKey and tostring(phaseKey) or "None" end
    end

    task.spawn(function()
        local cachedMacroName, cachedStepCount, lastCountCheck = nil, 0, 0
        while sessionAlive() do
            local maus = GetMausoleumData()
            local currentPhase = maus and maus.phase or "unknown"
            local currentRoom = maus and maus.room or "None"
            local currentStep = maus and maus.step or 0
            local totalSteps = maus and maus.steps or 0
            local phaseDesc = getPhaseDescription(currentPhase)

            local stepCount
            if RecordingStatusUI.IsRecording then
                stepCount = #recordedActions
            else
                if cachedMacroName ~= Settings.macro_profile or tick() - lastCountCheck > 2 then
                    cachedMacroName = Settings.macro_profile
                    cachedStepCount = getMacroStepCount(Settings.macro_profile)
                    lastCountCheck = tick()
                end
                stepCount = cachedStepCount
            end

            local timeElapsed = (roomFightStart and string.format("%.2f", tick() - roomFightStart)) or "0.00"

            local content
            if RecordingStatusUI.IsRecording then
                content = string.format("Status: Recording\nSelected Profile: %s | Steps: %d | Phase: %s\nRoom: %s\nTier: %d/%d\nTime: %ss\nCurrentStep: %s",
                    tostring(recordingToMacro), stepCount, phaseDesc, tostring(currentRoom), currentStep, totalSteps, timeElapsed, tostring(liveCurrentStepDescription))
            elseif playbackState.IsPlaying then
                content = string.format("Status: Playback (%s)\nSelected Profile: %s | Steps: %d | Phase: %s\nRoom: %s\nTier: %d/%d\nTime: %ss\nCurrentStep: %s",
                    tostring(Settings.playback_type), tostring(Settings.macro_profile), stepCount, phaseDesc, tostring(currentRoom), currentStep, totalSteps, timeElapsed, tostring(liveCurrentStepDescription))
            elseif Settings.macro_playback then
                content = string.format("Status: Armed (Waiting for Room)\nSelected Profile: %s | Steps: %d | Phase: %s\nRoom: %s\nTier: %d/%d\nTime: %ss\nCurrentStep: Waiting for room",
                    tostring(Settings.macro_profile), stepCount, phaseDesc, tostring(currentRoom), currentStep, totalSteps, timeElapsed)
            else
                content = string.format("Status: Idle\nSelected Profile: %s | Steps: %d | Phase: %s\nRoom: %s\nTier: %d/%d\nTime: %ss\nCurrentStep: Idle",
                    tostring(Settings.macro_profile), stepCount, phaseDesc, tostring(currentRoom), currentStep, totalSteps, timeElapsed)
            end

            local runningName = "None"
            if RecordingStatusUI.IsRecording then
                runningName = tostring(recordingToMacro)
            elseif playbackState.IsPlaying then
                runningName = tostring(runningMacroName)
            end
            content = (content:gsub("^([^\n]*)\n", function(first)
                return first .. "\nCurrent Running Macro: " .. runningName .. "\n"
            end, 1))

            local gatherPath = "None"
            local gatherPosStr = "Unknown"
            pcall(function()
                local gatherObj = getActiveGatherPart()
                if gatherObj then
                    gatherPath = gatherObj:GetFullName()
                    local cf = gatherObjCFrame(gatherObj)
                    if cf then
                        gatherPosStr = formatPos(cf.Position)
                    end
                end
            end)
            content = content .. string.format("\nCurrent Gather Part: %s (%s)", gatherPath, gatherPosStr)

            local currentRoomKeyVal = "None"
            pcall(function()
                local activeModel = getActiveRoomModel()
                if activeModel then
                    local rk = activeModel:GetAttribute("RoomKey")
                    if rk then
                        currentRoomKeyVal = tostring(rk)
                    else
                        currentRoomKeyVal = activeModel.Name
                    end
                elseif maus and maus.room then
                    currentRoomKeyVal = tostring(maus.room)
                end
            end)
            content = content .. "\nCurrent RoomKey: " .. currentRoomKeyVal

            local currentPlaybackPartVal = "None"
            pcall(function()
                if currentGatherMarker then
                    currentPlaybackPartVal = string.format("CurrentGatherPart (%s)", formatPos(currentGatherMarker.Position))
                elseif previousGatherMarker then
                    currentPlaybackPartVal = string.format("PreviousGatherPart (%s)", formatPos(previousGatherMarker.Position))
                else
                    currentPlaybackPartVal = string.format("%s (%s)", gatherPath, gatherPosStr)
                end
            end)
            content = content .. "\nCurrent Playback Part: " .. currentPlaybackPartVal

            pcall(function()
                StatusLabel:Set(content)
                ReturningTowersLabel:Set(GetReturningTowersInfo())
            end)
            task.wait(0.2)
        end
    end)

    local RecordToggle
    local overwriteConfirmed = false

    RecordToggle = MacroTab:CreateToggle({
        name = "Record Macro",
        value = Settings.macro_record,
        callback = Guard(function(Value)
            _G.is_recording = Value
            Settings.macro_record = Value
            SaveSettings()
            if Value then
                local macroName = Settings.macro_profile
                if not macroName or macroName == "None available" then
                    Window:Notify({ title = "Recording Error", content = "Select or create a macro first!", duration = 3 })
                    _G.is_recording = false
                    Settings.macro_record = false
                    SaveSettings()
                    return
                end
                local existingSteps = getMacroStepCount(macroName)
                if existingSteps > 0 and not overwriteConfirmed then
                    _G.is_recording = false
                    Settings.macro_record = false
                    SaveSettings()
                    pcall(function() RecordToggle:Set(false, true) end)
                    Window:Popup({
                        title = "Overwrite macro?",
                        content = string.format("\"%s\" already has %d steps. Recording will replace them when you stop.", macroName, existingSteps),
                        options = {
                            { text = "Cancel" },
                            { text = "Overwrite", style = "danger", callback = function()
                                overwriteConfirmed = true
                                pcall(function() RecordToggle:Set(true) end)
                            end },
                        },
                    })
                    return
                end
                overwriteConfirmed = false

                pcall(function()
                    if writefile and not isfile(SAVE_FOLDER .. "/" .. macroName .. ".json") then
                        writefile(SAVE_FOLDER .. "/" .. macroName .. ".json", "[]")
                    end
                end)
                startRecording()
            else
                if isRecordingActive then
                    local actions = stopRecording()
                    if #actions > 0 then
                        saveRecordedMacro(Settings.macro_profile, actions)
                        refreshDropdowns()
                        Window:Notify({ title = "Recording Status", content = "✓ Saved " .. #actions .. " actions", duration = 3 })
                    else
                        Window:Notify({ title = "Recording Status", content = "No actions recorded.", duration = 3 })
                    end
                end
            end
        end),
    })

    MacroTab:CreateToggle({
        name = "Playback Macro",
        value = Settings.macro_playback,
        callback = Guard(function(Value)
            print("[Mausoleum] playback toggle", Value)
            Settings.macro_playback = Value
            SaveSettings()
            if Value then
                local maus = GetMausoleumData()
                if not maus or not maus.room or maus.room == "" or maus.room == "None" then
                    lastAutoRoom = nil
                    Window:Notify({ title = "Playback Armed", content = "No active room detected. Playback will start automatically when a room loads.", duration = 4 })
                elseif _G.is_playing then
                    Window:Notify({ title = "Playback", content = "Playback already running.", duration = 3 })
                else
                    local macroName = getActiveMacroName(true, function(notifData)
                        if RayfieldWindow then RayfieldWindow:Notify(notifData) end
                    end)
                    if macroName and macroName ~= "None available" then
                        local actions = readMacroFile(macroName)
                        if actions then
                            Settings.macro_profile = macroName
                            lastAutoRoom = maus.room
                            startPlayback(macroName, actions)
                        else
                            Window:Notify({ title = "Playback Error", content = "Could not read macro: " .. tostring(macroName), duration = 3 })
                        end
                    else
                        Window:Notify({ title = "Playback Error", content = "No macro selected or mapped for this room.", duration = 3 })
                    end
                end
            else
                lastAutoRoom = nil
                stopPlayback()
                Window:Notify({ title = "Playback", content = "Playback halted.", duration = 3 })
            end
        end),
    })

    local function macroExists(name)
        local lowered = string.lower(name)
        local path = SAVE_FOLDER .. "/" .. name .. ".json"
        local found = false

        pcall(function() if isfile and isfile(path) then found = true end end)
        if not found then
            pcall(function() if readfile and readfile(path) ~= nil then found = true end end)
        end
        if not found then
            for _, existing in ipairs(listMacroFiles()) do
                if string.lower(existing) == lowered then found = true break end
            end
        end
        if not found then
            for _, existing in ipairs(getSavedMacroList()) do
                if string.lower(existing) == lowered then found = true break end
            end
        end
        return found
    end

    local newMacroName = ""
    local MacroNameInput = MacroTab:CreateInput({
        name = "Create New Macro",
        placeholder = "Enter macro filename...",
        callback = function(Text) newMacroName = Text end,
    })

    MacroTab:CreateButton({
        name = "Create Macro File",
        callback = function()
            local name = tostring(newMacroName or ""):match("^%s*(.-)%s*$")
            name = (name:gsub("%.[Jj][Ss][Oo][Nn]$", ""))
            name = (name:gsub('[/\\:*?"<>|]', ""))
            newMacroName = name

            if newMacroName ~= "" and writefile then
                local exists = macroExists(newMacroName)
                print("[Mausoleum] Create macro check:", newMacroName, "exists =", exists)

                if exists then
                    Window:Notify({
                        title = "File System",
                        content = string.format('A macro named "%s" already exists. Choose a different name.', newMacroName),
                        duration = 4
                    })
                    return
                end

                pcall(function()
                    writefile(SAVE_FOLDER .. "/" .. newMacroName .. ".json", "[]")
                    Settings.macro_profile = newMacroName
                    SaveSettings()
                    refreshDropdowns()
                    Window:Notify({ title = "File System", content = "✓ Created macro: " .. newMacroName, duration = 3 })
                    newMacroName = ""
                    if MacroNameInput then MacroNameInput:Clear() end
                end)
            else
                Window:Notify({ title = "Error", content = "Invalid filename or writefile unsupported.", duration = 3 })
            end
        end,
    })

    MacroTab:CreateButton({
        name = "Delete Selected Macro",
        callback = function()
            if Settings.macro_profile and Settings.macro_profile ~= "None available" then
                if delfile and isfile then
                    pcall(function()
                        local path = SAVE_FOLDER .. "/" .. Settings.macro_profile .. ".json"
                        if isfile(path) then delfile(path) end
                        Settings.macro_profile = "None available"
                        SaveSettings()
                        refreshDropdowns()
                        Window:Notify({ title = "File System", content = "✓ Deleted macro", duration = 3 })
                    end)
                else
                    Window:Notify({ title = "Error", content = "delfile unsupported.", duration = 3 })
                end
            else
                Window:Notify({ title = "Warning", content = "Select a macro first.", duration = 3 })
            end
        end,
    })

    MacroTab:CreateButton({
        name = "Debug: Print Room Slots (console)",
        callback = function()
            debugRoomSlots()
            Window:Notify({ title = "Room Slot Debug", content = "Printed to console (F9).", duration = 3 })
        end,
    })

    MacroTab:CreateButton({
        name = "Debug: Teleport to Current Step Tower",
        callback = function()
            local target = debugStepTarget
            if not target or not target.pos then
                Window:Notify({
                    title = "Debug Teleport",
                    content = "No step target yet. Start a macro playback first.",
                    duration = 3
                })
                return
            end

            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                Window:Notify({ title = "Debug Teleport", content = "Character not found.", duration = 3 })
                return
            end

            hrp.CFrame = CFrame.new(target.pos + Vector3.new(0, 5, 0))
            print(string.format("[Mausoleum] Debug teleport -> step %s (%s) at %s",
                tostring(target.idx), tostring(target.desc), formatPos(target.pos)))
            Window:Notify({
                title = "Debug Teleport",
                content = string.format("Step %s: %s\n%s", tostring(target.idx), tostring(target.desc), formatPos(target.pos)),
                duration = 4
            })
        end,
    })

    MapsTab:CreateSection({ name = "Room-to-Macro Mappings" })

    local sortedRooms = {}
    for _, r in ipairs(MAUSOLEUM_ROOMS) do table.insert(sortedRooms, r) end
    table.sort(sortedRooms, function(a, b) return string.lower(a) < string.lower(b) end)

    for _, roomName in ipairs(sortedRooms) do
        local currentValue = getgenv().MacroMapConfig[roomName]
        roomDropdowns[roomName] = MapsTab:CreateDropdown({
            name = roomName,
            options = getMapMacroList(),
            value = currentValue and { currentValue } or { "None" },
            flag = "Map_" .. roomName,
            callback = function(selected)
                local chosen = getSelectionString(selected)
                if chosen and chosen ~= "None" then
                    getgenv().MacroMapConfig[roomName] = chosen
                else
                    getgenv().MacroMapConfig[roomName] = nil
                end
                SaveSettings()
            end,
        })
    end

    MainTab:CreateSection({ name = "Auto Sequential Upgrade" })

    MainTab:CreateToggle({
        name = "Auto Sequential Upgrade",
        value = Settings.auto_sequential_upgrade,
        flag = "AutoSequentialUpgrade",
        callback = Guard(function(Value)
            Settings.auto_sequential_upgrade = Value
            SaveSettings()
        end),
    })

    local UpgradeStatusLabel = MainTab:CreateText({
        text = "Auto-Upgrade: Disabled\nQueued: None\nUpgrading: None\nPriority: " .. (Settings.auto_upgrade_priority or "1,2,3,4,5") .. " | Interval: " .. string.format("%.2fs", Settings.auto_upgrade_delay or 0.1)
    })

    local priorityInput = ""
    local PriorityInputBox = MainTab:CreateInput({
        name = "Upgrade Priority (Slots 1-5)",
        placeholder = "e.g., 2,1,3,4,5",
        removeTextAfterFocusLost = false,
        callback = function(Text)
            priorityInput = Text
        end,
    })

    MainTab:CreateButton({
        name = "Set Upgrade Priority",
        callback = function()
            local input = tostring(priorityInput or ""):match("^%s*(.-)%s*$")
            if input == "" then
                input = "1,2,3,4,5"
            end

            local slots = {}
            for num in input:gmatch("%d+") do
                local slot = tonumber(num)
                if slot and slot >= 1 and slot <= 5 then
                    if not table.find(slots, slot) then
                        table.insert(slots, slot)
                    end
                end
            end

            if #slots > 0 then
                Settings.auto_upgrade_priority = table.concat(slots, ",")
                SaveSettings()
                Window:Notify({
                    title = "Upgrade Priority",
                    content = "Priority set to: " .. Settings.auto_upgrade_priority,
                    duration = 3
                })
            else
                Window:Notify({
                    title = "Error",
                    content = "Invalid priority format. Use numbers 1-5 separated by commas.",
                    duration = 3
                })
            end
        end,
    })

    MainTab:CreateSlider({
        name = "Upgrade Check Interval (sec)",
        range = { 0.05, 1 },
        increment = 0.05,
        suffix = "s",
        value = Settings.auto_upgrade_delay or 0.1,
        flag = "UpgradeDelay",
        callback = function(Value)
            Settings.auto_upgrade_delay = Value
            SaveSettings()
        end,
    })

    MainTab:CreateButton({
        name = "Debug Upgrade Queue (prints to console)",
        callback = function()
            debugUpgradeQueue()
            Window:Notify({ title = "Upgrade Debug", content = "Printed to console (F9).", duration = 3 })
        end,
    })

    local function formatMoney(n)
        local str = tostring(math.floor(tonumber(n) or 0))
        local out = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        out = out:gsub("^,", "")
        return out
    end

    local function getQueuedText()
        local parts = {}
        for _, tower in ipairs(upgradeQueue) do
            local isCurrent = currentUpgradeTarget and tostring(tower.serverId) == tostring(currentUpgradeTarget.serverId)
            if not isCurrent then
                table.insert(parts, string.format("%s Lv%d #%d (S%s)", tower.towerName, tower.level or 1, tower.index or 0, tostring(tower.slot)))
            end
        end
        if #parts == 0 then return "None" end

        local maxShown = 5
        if #parts > maxShown then
            local extra = #parts - maxShown
            local shown = {}
            for i = 1, maxShown do shown[i] = parts[i] end
            table.insert(shown, "+" .. extra .. " more")
            parts = shown
        end
        return table.concat(parts, ", ")
    end

    task.spawn(function()
        while sessionAlive() do
            task.wait(0.2)

            local maus = GetMausoleumData()
            local statusText = ""

            if Settings.auto_sequential_upgrade then
                local upgradeStatus = ""
                local upgradingInfo = "Upgrading: None"

                if isRecordingActive then
                    upgradeStatus = "⚪ Paused (Recording)"
                elseif _G.is_playing then
                    upgradeStatus = "🟡 Waiting for Playback to Finish"
                elseif not (maus and maus.phase == "fight") then
                    upgradeStatus = "🟡 Waiting for Fight"
                elseif currentUpgradeTarget then
                    upgradeStatus = "🟢 Upgrading"
                    local upg = autoUpgradeState.currentlyUpgrading
                    if upg then
                        local costText = "cost unknown"
                        if upg.cost and upg.cost > 0 then
                            costText = string.format("$%s / $%s", formatMoney(getPlayerCash()), formatMoney(upg.cost))
                        end
                        upgradingInfo = string.format("Upgrading: %s #%d to Lvl:%d (%s)", upg.towerName, upg.index or 0, upg.toLevel, costText)
                        if autoUpgradeState.waitingForCash then
                            upgradeStatus = "🟡 Waiting for Cash"
                        end
                    end
                else
                    upgradeStatus = "⚪ Queue empty (no matching towers)"
                end

                statusText = "Auto-Upgrade: " .. upgradeStatus .. "\nQueued: " .. getQueuedText() .. "\n" .. upgradingInfo .. "\nPriority: " .. (Settings.auto_upgrade_priority or "1,2,3,4,5") .. " | Interval: " .. string.format("%.2fs", Settings.auto_upgrade_delay or 0.1)
            else
                statusText = "Auto-Upgrade: Disabled\nQueued: None\nUpgrading: None\nPriority: " .. (Settings.auto_upgrade_priority or "1,2,3,4,5") .. " | Interval: " .. string.format("%.2fs", Settings.auto_upgrade_delay or 0.1)
            end

            pcall(function()
                UpgradeStatusLabel:Set(statusText)
            end)
        end
    end)

    local difficultyEntries = {}
    pcall(function()
        local db = require(ReplicatedStorage.Databases.Difficulties)
        if type(db) == "table" then
            for key, d in pairs(db) do
                if type(d) == "table" and d.subtitle then
                    table.insert(difficultyEntries, { key = key, label = d.name or key, order = d.order or 0 })
                end
            end
        end
    end)
    table.sort(difficultyEntries, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.label < b.label
    end)
    if #difficultyEntries == 0 then
        table.insert(difficultyEntries, { key = Settings.difficulty_choice, label = Settings.difficulty_choice, order = 0 })
    end

    local difficultyKeyByLabel, difficultyLabelByKey, difficultyLabels = {}, {}, {}
    for _, entry in ipairs(difficultyEntries) do
        difficultyKeyByLabel[entry.label] = entry.key
        difficultyLabelByKey[entry.key] = entry.label
        table.insert(difficultyLabels, entry.label)
    end

    local function difficultyVoteGuiExists()
        local ok, found = pcall(function()
            local hud = player_gui:FindFirstChild("MainHud")
            return hud ~= nil and hud:FindFirstChild("DifficultyVote") ~= nil
        end)
        return ok and found == true
    end

    local function castDifficultyVote(key)
        local ok, err = pcall(function()
            ReplicatedStorage.Modules.Remotes.RemoteEvent.RespondToQuery:FireServer("difficulties", key)
        end)
        if not ok then
            warn("[Mausoleum] Difficulty vote failed:", err)
        end
        return ok
    end

    task.spawn(function()
        local lastVoteKey, voteAttempts, lastVoteTime = nil, 0, 0
        while sessionAlive() do
            task.wait(0.5)
            if Settings.auto_difficulty then
                local maus = GetMausoleumData()
                local shouldVote, key = false, nil

                if maus and maus.phase then
                    if maus.phase == "seal" then
                        shouldVote = true
                        key = "seal:" .. tostring(maus.room) .. ":" .. tostring(maus.step)
                    end
                elseif difficultyVoteGuiExists() then
                    shouldVote = true
                    key = "gui"
                end

                if shouldVote then
                    if key ~= lastVoteKey then
                        lastVoteKey, voteAttempts, lastVoteTime = key, 0, 0
                    end
                    if voteAttempts < 3 and tick() - lastVoteTime >= 2 then
                        voteAttempts = voteAttempts + 1
                        lastVoteTime = tick()
                        local choice = Settings.difficulty_choice
                        if castDifficultyVote(choice) then
                            Window:Notify({
                                title = "Auto Difficulty",
                                content = "Voted: " .. tostring(difficultyLabelByKey[choice] or choice),
                                duration = 3
                            })
                        end
                    end
                else
                    lastVoteKey = nil
                end
            else
                lastVoteKey = nil
            end
        end
    end)

    MainTab:CreateSection({ name = "Difficulty" })

    MainTab:CreateDropdown({
        name = "Difficulty",
        options = difficultyLabels,
        value = { difficultyLabelByKey[Settings.difficulty_choice] or difficultyLabels[1] },
        flag = "DifficultyChoice",
        callback = function(selected)
            local label = getSelectionString(selected)
            local key = label and difficultyKeyByLabel[label]
            if key then
                Settings.difficulty_choice = key
                SaveSettings()
            end
        end,
    })

    MainTab:CreateToggle({
        name = "Auto Select Difficulty",
        value = Settings.auto_difficulty,
        flag = "AutoDifficulty",
        callback = Guard(function(Value)
            Settings.auto_difficulty = Value
            SaveSettings()
        end),
    })

    MainTab:CreateSection({ name = "Quality of Life" })

    -- AUTO PETRIFY BREAK IMPLEMENTATION
    task.spawn(function()
        local Workspace = game:GetService("Workspace")

        local function autoBreakout(instance)
            if Settings.auto_petrify_break and instance:IsA("ClickDetector") and instance.Name == "PetrifyBreakout" then
                task.spawn(function()
                    while Settings.auto_petrify_break and instance and instance.Parent do
                        pcall(function()
                            fireclickdetector(instance)
                        end)
                        task.wait(0.02)
                    end
                end)
            end
        end

        for _, descendant in ipairs(Workspace:GetDescendants()) do
            autoBreakout(descendant)
        end

        Workspace.DescendantAdded:Connect(function(descendant)
            if Settings.auto_petrify_break then
                autoBreakout(descendant)
            end
        end)
    end)

    MainTab:CreateToggle({
        name = "Auto Petrify Break",
        value = Settings.auto_petrify_break or false,
        flag = "AutoPetrifyBreak",
        callback = Guard(function(Value)
            Settings.auto_petrify_break = Value
            SaveSettings()
            if Value then
                Window:Notify({
                    title = "Auto Petrify Break",
                    content = "Enabled automatic petrify breakout clicking.",
                    duration = 3
                })
            end
        end),
    })

    -- ============================================================================
    -- AUTO REPLAY (fires when phase == "over" and the GameOver GUI exists)
    -- ============================================================================

    local function findDynamicGui(parent, path)
        local current = parent
        for _, name in ipairs(path) do
            current = current and current:FindFirstChild(name)
            if not current then return nil end
        end
        return current
    end

    local GAME_OVER_GUI_PATHS = {
        {"MainHud", "Hud", "RoundHud", "Hud", "GameOver"},
        {"MainHud", "Hud", "RoundHud", "Hud", "Classic", "GameOver"},
    }

    -- Returns the first GameOver GUI found across all known paths
    local function getGameOverGui()
        for _, path in ipairs(GAME_OVER_GUI_PATHS) do
            local gui = findDynamicGui(player_gui, path)
            if gui then return gui, table.concat(path, ".") end
        end
        return nil
    end

    local function fireReplay()
        local ok = pcall(function()
            local respond = ReplicatedStorage.Modules.Remotes.RemoteEvent:FindFirstChild("RespondToQuery")
            if respond then
                respond:FireServer("game_over", true)
            end
        end)
        return ok
    end

    MainTab:CreateToggle({
        name = "Auto Replay",
        value = Settings.auto_replay or false,
        flag = "AutoReplay",
        callback = Guard(function(Value)
            Settings.auto_replay = Value
            SaveSettings()
            if Value then
                Window:Notify({
                    title = "Auto Replay",
                    content = "Will automatically replay when the game over screen appears.",
                    duration = 3
                })
            end
        end),
    })

    task.spawn(function()
        local attempts, lastAttempt = 0, 0
        local MAX_REPLAY_ATTEMPTS = 5
        local REPLAY_INTERVAL = 2

        while sessionAlive() do
            task.wait(0.5)

            if Settings.auto_replay then
                local maus = GetMausoleumData()
                local isOver = maus and maus.phase == "over"
                local gui, guiPath = nil, nil
                if isOver then gui, guiPath = getGameOverGui() end

                if isOver and gui then
                    if attempts < MAX_REPLAY_ATTEMPTS and tick() - lastAttempt >= REPLAY_INTERVAL then
                        attempts = attempts + 1
                        lastAttempt = tick()
                        print(string.format("[Mausoleum] Game over detected via %s, firing replay (%d/%d)", tostring(guiPath), attempts, MAX_REPLAY_ATTEMPTS))
                        liveCurrentStepDescription = "Run over - auto replaying"
                        if fireReplay() then
                            Window:Notify({
                                title = "Auto Replay",
                                content = "Replay requested.",
                                duration = 2
                            })
                        end
                    end
                else
                    -- Reset once the over screen is gone, so the next run can replay again
                    attempts = 0
                    lastAttempt = 0
                end
            else
                attempts = 0
                lastAttempt = 0
            end
        end
    end)

    local autoNextRoomEnabled = Settings.auto_teleport_next_room or false
    local lastClearedRoom = nil

    MainTab:CreateToggle({
        name = "Auto Teleport to Next Room",
        value = Settings.auto_teleport_next_room or false,
        flag = "AutoTeleportNextRoom",
        callback = Guard(function(Value)
            autoNextRoomEnabled = Value
            Settings.auto_teleport_next_room = Value
            SaveSettings()
            if Value then
                Window:Notify({
                    title = "Auto Teleport",
                    content = "Will teleport to next room when cleared phase begins.",
                    duration = 3
                })
            end
        end),
    })

    task.spawn(function()
        local lastDebugPhase = nil
        local vaultPromptActive = false
        while sessionAlive() do
            task.wait(0.5)

            if autoNextRoomEnabled then
                local maus = GetMausoleumData()
                local currentPhase = maus and maus.phase or "none"

                if currentPhase ~= lastDebugPhase then
                    print("[Mausoleum] Teleport Watcher - Phase detected:", currentPhase)
                    lastDebugPhase = currentPhase
                end

                if currentPhase == "vault" and not vaultPromptActive then
                    vaultPromptActive = true
                    print("[Mausoleum] Vault phase detected, starting fireproximityprompt firing")

                    task.spawn(function()
                        while vaultPromptActive and sessionAlive() do
                            local maus = GetMausoleumData()

                            if maus and maus.phase == "over" then
                                print("[Mausoleum] Over phase detected, stopping proximity prompt trigger")
                                vaultPromptActive = false
                                break
                            end

                            pcall(function()
                                local vaultMap = workspace:FindFirstChild("ActiveMap")
                                if not vaultMap then return end

                                local vaultFolder = vaultMap:FindFirstChild("Vault")
                                if not vaultFolder then return end

                                local coffins = vaultFolder:FindFirstChild("Coffins")
                                if not coffins then return end

                                local coffin = coffins:FindFirstChild("Coffin")
                                if not coffin then return end

                                local promptPart = coffin:FindFirstChild("PromptPart")
                                if not promptPart then return end

                                local prompt = promptPart:FindFirstChild("CoffinPrompt")
                                if prompt and prompt:IsA("ProximityPrompt") then
                                    prompt.HoldDuration = 0
                                    fireproximityprompt(prompt)
                                end
                            end)

                            task.wait(0.5)
                        end
                    end)
                elseif currentPhase ~= "vault" and vaultPromptActive then
                    vaultPromptActive = false
                end

                if maus and (maus.phase == "cleared" or maus.phase == "vault") then
                    if lastClearedRoom ~= (tostring(maus.room) .. ":" .. tostring(maus.step)) then
                        lastClearedRoom = tostring(maus.room) .. ":" .. tostring(maus.step)
                        print("[Mausoleum] Attempting teleport from room:", maus.room, "step:", maus.step)

                        local character = LocalPlayer.Character
                        if character and character:FindFirstChild("HumanoidRootPart") then
                            local targetCF = CFrame.new()
                            local teleportType = "next room"

                            if maus.step == 5 and maus.steps == 6 and maus.phase == "cleared" then
                                local slot4 = workspace:FindFirstChild("ActiveMap")
                                    and workspace.ActiveMap:FindFirstChild("Rooms")
                                    and workspace.ActiveMap.Rooms:FindFirstChild("Slot4")

                                local slot4HasTier6 = false
                                if slot4 then
                                    local tierAttr = slot4:GetAttribute("Tier")
                                    if tierAttr == 6 then
                                        slot4HasTier6 = true
                                    else
                                        local tierVal = slot4:FindFirstChild("Tier")
                                        if tierVal and tierVal:IsA("ValueBase") and tierVal.Value == 6 then
                                            slot4HasTier6 = true
                                        end
                                    end
                                end

                                if slot4HasTier6 then
                                    local slot5 = workspace:FindFirstChild("ActiveMap")
                                        and workspace.ActiveMap:FindFirstChild("Rooms")
                                        and workspace.ActiveMap.Rooms:FindFirstChild("Slot5")

                                    if slot5 then
                                        local gatherObj = slot5:FindFirstChild("Gather")

                                        if gatherObj then
                                            if gatherObj:IsA("BasePart") then
                                                targetCF = gatherObj.CFrame + Vector3.new(0, 3, 0)
                                            elseif gatherObj:IsA("Model") and gatherObj.PrimaryPart then
                                                targetCF = gatherObj.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
                                            elseif gatherObj:IsA("Model") then
                                                targetCF = gatherObj:GetPivot() + Vector3.new(0, 3, 0)
                                            end
                                        else
                                            if slot5:IsA("Model") and slot5.PrimaryPart then
                                                targetCF = slot5.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
                                            elseif slot5:IsA("Model") then
                                                targetCF = slot5:GetPivot() + Vector3.new(0, 3, 0)
                                            elseif slot5:IsA("BasePart") then
                                                targetCF = slot5.CFrame + Vector3.new(0, 3, 0)
                                            end
                                        end
                                    end
                                end
                            elseif maus.step == 6 and maus.steps == 6 then
                                teleportType = "vault"
                                local vaultPart = nil
                                pcall(function()
                                    vaultPart = workspace.ActiveMap.Vault.Coffins.Coffin.PromptPart
                                end)

                                if vaultPart and vaultPart:IsA("BasePart") then
                                    targetCF = vaultPart.CFrame + Vector3.new(0, 3, 0)
                                end
                            else
                                local nextRoomModel = getNextRoomModel()
                                if nextRoomModel then
                                    local gatherObj = nextRoomModel:FindFirstChild("Gather")

                                    if gatherObj then
                                        if gatherObj:IsA("BasePart") then
                                            targetCF = gatherObj.CFrame + Vector3.new(0, 3, 0)
                                        elseif gatherObj:IsA("Model") and gatherObj.PrimaryPart then
                                            targetCF = gatherObj.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
                                        elseif gatherObj:IsA("Model") then
                                            targetCF = gatherObj:GetPivot() + Vector3.new(0, 3, 0)
                                        end
                                    else
                                        if nextRoomModel:IsA("Model") and nextRoomModel.PrimaryPart then
                                            targetCF = nextRoomModel.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
                                        elseif nextRoomModel:IsA("Model") then
                                            targetCF = nextRoomModel:GetPivot() + Vector3.new(0, 3, 0)
                                        elseif nextRoomModel:IsA("BasePart") then
                                            targetCF = nextRoomModel.CFrame + Vector3.new(0, 3, 0)
                                        end
                                    end
                                else
                                    local activeRooms = workspace:FindFirstChild("ActiveMap")
                                        and workspace.ActiveMap:FindFirstChild("Rooms")

                                    if activeRooms then
                                        local slotName = "Slot" .. tostring(maus.step)
                                        local slot = activeRooms:FindFirstChild(slotName)

                                        if slot then
                                            local gatherObj = slot:FindFirstChild("Gather")

                                            if gatherObj then
                                                if gatherObj:IsA("BasePart") then
                                                    targetCF = gatherObj.CFrame + Vector3.new(0, 3, 0)
                                                elseif gatherObj:IsA("Model") and gatherObj.PrimaryPart then
                                                    targetCF = gatherObj.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
                                                elseif gatherObj:IsA("Model") then
                                                    targetCF = gatherObj:GetPivot() + Vector3.new(0, 3, 0)
                                                end
                                            else
                                                if slot:IsA("Model") and slot.PrimaryPart then
                                                    targetCF = slot.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
                                                elseif slot:IsA("Model") then
                                                    targetCF = slot:GetPivot() + Vector3.new(0, 3, 0)
                                                elseif slot:IsA("BasePart") then
                                                    targetCF = slot.CFrame + Vector3.new(0, 3, 0)
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            -- FAILSAFE: Validate computed destination CFrame
                            if targetCF == CFrame.new() or targetCF.Position.Magnitude == 0 then
                                warn("[Mausoleum] Teleport failsafe triggered: Target position is invalid/zero. Falling back to current position offset.")
                                local hrp = character:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    targetCF = hrp.CFrame + Vector3.new(0, 5, 0)
                                end
                            end

                            if targetCF ~= CFrame.new() then
                                liveCurrentStepDescription = "Teleporting in 2 seconds to " .. teleportType
                                task.wait(2)

                                if sessionAlive() then
                                    character.HumanoidRootPart.CFrame = targetCF
                                    liveCurrentStepDescription = "Teleported to " .. teleportType
                                    Window:Notify({
                                        title = "Auto Teleport",
                                        content = "Teleported to " .. teleportType .. "!",
                                        duration = 2
                                    })
                                end
                            else
                                Window:Notify({
                                    title = "Auto Teleport Failed",
                                    content = "Could not resolve destination coordinates.",
                                    duration = 3
                                })
                            end
                        end
                    end
                elseif maus and maus.phase ~= "cleared" and maus.phase ~= "vault" then
                    lastClearedRoom = nil
                end
            else
                lastClearedRoom = nil
            end
        end
    end)

    SettingsTab:CreateSection({ name = "Playback & Synchronization Settings" })

    SettingsTab:CreateDropdown({
        name = "Playback Type",
        options = {"Time", "Hybrid", "Money", "Money + Wave"},
        value = { Settings.playback_type or "Time" },
        flag = "PlaybackType",
        callback = function(selected)
            local chosen = getSelectionString(selected)
            if chosen then
                Settings.playback_type = chosen
                SaveSettings()
            end
        end,
    })

    SettingsTab:CreateToggle({
        name = "Auto Play Macro On Room Change",
        value = Settings.auto_room_playback,
        flag = "AutoRoomPlayback",
        callback = function(Value)
            Settings.auto_room_playback = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateToggle({
        name = "Final Tier (6/6): Wait for RoomKey Change",
        value = Settings.final_tier_wait,
        flag = "FinalTierWait",
        callback = function(Value)
            Settings.final_tier_wait = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateToggle({
        name = "Use Closest Gather Part",
        value = Settings.use_closest_gather,
        flag = "UseClosestGather",
        callback = function(Value)
            Settings.use_closest_gather = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateSlider({
        name = "Room Sync Delay (sec)",
        range = { 0.5, 5 },
        increment = 0.25,
        suffix = "s",
        value = Settings.room_resolve_delay or 1.5,
        flag = "RoomResolveDelay",
        callback = function(Value)
            Settings.room_resolve_delay = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateToggle({
        name = "Auto Ready Up",
        value = Settings.auto_ready,
        flag = "AutoReady",
        callback = function(Value)
            Settings.auto_ready = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateToggle({
        name = "Use Returning Units",
        value = Settings.use_returning_units,
        flag = "UseReturningUnits",
        callback = function(Value)
            Settings.use_returning_units = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateSlider({
        name = "Remote Fire Delay (sec)",
        range = { 0.1, 2 },
        increment = 0.05,
        suffix = "s",
        value = Settings.auto_fire_delay,
        flag = "FireDelay",
        callback = function(Value)
            Settings.auto_fire_delay = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateToggle({
        name = "Enable Retry on Fail",
        value = Settings.retry_on_fail,
        flag = "EnableRetry",
        callback = function(Value)
            Settings.retry_on_fail = Value
            SaveSettings()
        end,
    })

    SettingsTab:CreateSlider({
        name = "Max Retry Attempts",
        range = { 1, 10 },
        increment = 1,
        value = Settings.max_retries or 5,
        flag = "MaxRetries",
        callback = function(Value)
            Settings.max_retries = Value
            SaveSettings()
        end,
    })

    task.spawn(function()
        if initializeHotbar() then
            print("[Mausoleum] Hotbar loaded, first slot:", tostring(next(hotbarData)))
            print(logActivePlacementPerks())
        end
    end)

    UIReady = true
    print("[Mausoleum] Macro Manager loaded successfully.")
end)

if not success then
    warn("----------------------------------------")
    warn("[Mausoleum CRITICAL ERROR]:")
    warn(tostring(initError))
    warn("----------------------------------------")
end
