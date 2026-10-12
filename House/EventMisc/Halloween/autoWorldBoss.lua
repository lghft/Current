-- ============================================================================
-- WorldBoss Auto-Farm - hotbar placement + cash wait + slot 1 auto upgrade
-- + boss presets + ground-based Y + pause placing during loot
-- + walk to loot + walk to snare near tower + loot collection + scythe
-- + walk speed
-- ============================================================================

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)
if game.Players.LocalPlayer.UserId ~= 1588829513 then
    return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- CONFIG
-- ============================================================================

local CONFIG = {
    TowerPlacer = {
        Enabled = true,
        LoopInterval = 0.5,    -- how often the loop checks the slots
        PlaceCooldown = 2,     -- min seconds between placement attempts for a slot
        SlotRadius = 4,        -- a live tower this close (X/Z) to a spot counts as "occupied"
        ReserveTime = 8,       -- seconds a spot stays reserved after a placement starts
        CashTimeout = 30,      -- max seconds to wait for cash before giving up
        PauseWhileLoot = true, -- stop placing while workspace.WorldBossLoot exists
    },

    GroundY = {
        Enabled = true,        -- set spot Y to the Ground's Y
        Offset = 2.45,            -- added on top of the Ground's Y
    },

    TowerUpgrade = {
        Enabled = true,
        Slot = 1,              -- only towers placed from this placement slot get upgraded
        MaxLevel = 3,
        CheckInterval = 0.5,
        CashTimeout = 30,
    },

    LootCollection = {
        Enabled = true,
        ScanInterval = 0.2,
        MaxDistance = 200,
        FarmingMode = true,
        CollectionCooldown = 0.5,
    },

    WalkToLoot = {
        Enabled = true,
        StopDistance = 20,     -- stop walking once this close (horizontal studs)
        ResumeDistance = 22,   -- only start walking again if you drift past this
        RepathInterval = 25,  -- how often MoveTo is re-sent while walking
    },

    SnareWalk = {
        Enabled = true,
        TowerRadius = 5,       -- a snare counts if it's this close (horizontal studs) to a tower
        StopDistance = 3,      -- stop walking once this close to the snare
        RepathInterval = 0.5,  -- how often MoveTo is re-sent while walking
        CheckInterval = 0.25,  -- how often the snare search runs
    },

    AutoScythe = {
        Enabled = true,
        CheckInterval = 0.15,
        SwipeCooldown = 0.6,
        TargetRange = 15,
    },

    WalkSpeed = {
        Enabled = true,
        Value = 44.8,
    },
}

-- Which HOTBAR slot holds the tower for each placement slot.
local TOWER_HOTBAR_SLOT = {
    [1] = 1,
    [2] = 2,
}

-- ============================================================================
-- PRESET TOWER POSITIONS
-- Each slot holds a LIST of spots. The first free spot is used.
-- ============================================================================

local PRESETS = {
    Devil = {
        [1] = {
            CFrame.new(10046.05078125, -118.54788208007812, -6.52520751953125),
            CFrame.new(10046.2470703125, -118.54788208007812, -3.0180532932281494),
        },
        [2] = { CFrame.new(10036.3515625, -118.26579284667969, -7.5256004333496094) },
    },
    Pumpkin = {
        [1] = {
            CFrame.new(10005, 3, 46),
            CFrame.new(9996, 3, 47),
        },
        [2] = { CFrame.new(9990, 3, 26) },
    },
    Reaper = {
        [1] = {
            CFrame.new(9954, 3, -0),
            CFrame.new(9957, 3, -15),
        },
        [2] = { CFrame.new(9969, 3, -8) },
    },
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function Log(msg)
    print("[AutoFarm] " .. tostring(msg))
end

local function FindRemote(path)
    local obj = ReplicatedStorage
    for _, part in ipairs(string.split(path, ".")) do
        if not obj then break end
        obj = obj:FindFirstChild(part)
    end
    return obj
end

local PlaceTowerRemote = FindRemote("Modules.Remotes.RemoteFunction.PlaceTower")
if not PlaceTowerRemote then
    warn("[AutoFarm] PlaceTower remote not found, script stopped.")
    return
end

local UpgradeTowerRemote = FindRemote("Modules.Remotes.RemoteEvent.UpgradeTower")
if not UpgradeTowerRemote then
    warn("[AutoFarm] UpgradeTower remote not found, auto upgrade disabled.")
end

local ScytheRemote = FindRemote("Modules.Remotes.RemoteEvent.ScytheSwipe")
if not ScytheRemote then
    warn("[AutoFarm] ScytheSwipe remote not found, auto scythe disabled.")
end

local EquippingModule = require(ReplicatedStorage.Modules.Equipping)
local Inventory = require(ReplicatedStorage.Modules.Inventory)

local TowerDatabase
do
    local ok, db = pcall(function()
        return require(ReplicatedStorage.Databases.Items.Tower)
    end)
    if ok then TowerDatabase = db else warn("[AutoFarm] Tower database not found, costs will be 0.") end
end

local CashUtils
do
    local ok, mod = pcall(function()
        return require(ReplicatedStorage.Modules.Round.utils.cash_utils)
    end)
    if ok then CashUtils = mod else warn("[AutoFarm] cash_utils not found, cash waits will fail.") end
end

-- ============================================================================
-- WORLD BOSS ROTATION
-- ============================================================================

local Rotation
do
    local ok, mod = pcall(function()
        return require(FindRemote("Modules.WorldBossRotation"))
    end)
    if ok and mod then
        Rotation = mod
    else
        warn("[AutoFarm] WorldBossRotation module not found, script stopped.")
        return
    end
end

-- Working copy of the presets, so SetSlotPosition can override them at runtime.
-- reserved[i] = time until which spot i is considered taken by a pending placement.
local SLOTS = {}
for _, boss in ipairs(Rotation.ORDER) do
    SLOTS[boss] = {}
    for slotNum = 1, 2 do
        local src = PRESETS[boss] and PRESETS[boss][slotNum] or {}
        local spots = {}
        for i, cf in ipairs(src) do spots[i] = cf end
        SLOTS[boss][slotNum] = { spots = spots, reserved = {}, lastPlace = 0, placing = false }
    end
end

local function GetCurrentBoss()
    return (Rotation.current())
end

local function BossName(boss)
    local info = Rotation.BOSSES[boss]
    return info and info.name or tostring(boss)
end

-- ============================================================================
-- GROUND Y
-- ============================================================================

-- Returns the Y of workspace.ActiveMap.Canvases.Ground, or nil if it isn't there
local function GetGroundY()
    local activeMap = workspace:FindFirstChild("ActiveMap")
    local canvases = activeMap and activeMap:FindFirstChild("Canvases")
    local ground = canvases and canvases:FindFirstChild("Ground")
    if not ground then return nil end

    if ground:IsA("BasePart") then
        return ground.CFrame.Y
    elseif ground:IsA("Model") then
        local ok, pivot = pcall(function() return ground:GetPivot() end)
        if ok and pivot then return pivot.Y end
    end
    return nil
end

-- Returns the spot CFrame with its Y replaced by the Ground Y (+ offset), keeping X/Z and rotation
local function AdjustedCFrame(cf)
    if not CONFIG.GroundY.Enabled then return cf end
    local groundY = GetGroundY()
    if not groundY then return cf end

    local pos = Vector3.new(cf.X, groundY + CONFIG.GroundY.Offset, cf.Z)
    return CFrame.fromMatrix(pos, cf.RightVector, cf.UpVector)
end

-- ============================================================================
-- HOTBAR, CASH, COST
-- ============================================================================

local function GetHotbarUid(hotbarSlot)
    local hotbar = EquippingModule.getHotbar(LocalPlayer)
    local uid = hotbar and hotbar[hotbarSlot]
    return uid and tostring(uid) or nil
end

-- Cost of a tower's given level (level 1 = placement cost)
local function GetTowerCost(uid, level)
    if not uid or not TowerDatabase then return 0 end
    local ok, item = pcall(Inventory.getItem, uid)
    if not ok or not item then return 0 end
    local baseId = item.itemId or item.id
    local entry = baseId and TowerDatabase[baseId]
    local stat = entry and entry.stats and entry.stats[level]
    return (stat and stat.cost) or 0
end

local function GetPlayerCash()
    if CashUtils and CashUtils.getRoundCash then
        local ok, cash = pcall(CashUtils.getRoundCash, LocalPlayer)
        if ok and cash then return cash end
    end
    return 0
end

-- Waits until the player has `amount` cash. Returns false if it times out.
local function WaitForCash(amount, maxWait)
    local startTime = os.clock()
    while GetPlayerCash() < amount do
        if os.clock() - startTime > maxWait then
            return false
        end
        task.wait(0.1)
    end
    return true
end

-- ============================================================================
-- TOWER PLACER
-- ============================================================================

-- Slot 1 towers that the upgrader manages: { serverId, uid, level }
local Slot1Towers = {}

-- True if a live tower sits on this spot (horizontal distance, so height doesn't matter)
local function IsSpotOccupied(cframe)
    local spot = cframe.Position
    local spotFlat = Vector3.new(spot.X, 0, spot.Z)

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:find("Tower") then
            local ok, pivot = pcall(function() return obj:GetPivot().Position end)
            if ok then
                local flat = Vector3.new(pivot.X, 0, pivot.Z)
                if (flat - spotFlat).Magnitude <= CONFIG.TowerPlacer.SlotRadius then
                    local hp = obj:GetAttribute("UnitHP") or obj:GetAttribute("Health")
                    if hp == nil or hp > 0 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Returns the index of the first spot that has no tower and isn't reserved, or nil
local function FindFreeSpot(data, now)
    for i, cf in ipairs(data.spots) do
        local reservedUntil = data.reserved[i] or 0
        if reservedUntil <= now and not IsSpotOccupied(AdjustedCFrame(cf)) then
            return i
        end
    end
    return nil
end

local warnedHotbar = {}

-- Runs in its own thread so the loop keeps going while waiting for cash
local function PlaceInSlot(boss, slotNum, spotIndex)
    local data = SLOTS[boss][slotNum]
    local hotbarSlot = TOWER_HOTBAR_SLOT[slotNum]

    local function release()
        data.reserved[spotIndex] = nil
        data.placing = false
        data.lastPlace = tick()
    end

    local uid = GetHotbarUid(hotbarSlot)
    if not uid then
        if not warnedHotbar[slotNum] then
            warn("[AutoFarm] Hotbar slot " .. tostring(hotbarSlot) .. " is empty (placement slot " .. slotNum .. ").")
            warnedHotbar[slotNum] = true
        end
        release()
        return
    end

    local cost = GetTowerCost(uid, 1)
    if cost > 0 and not WaitForCash(cost, CONFIG.TowerPlacer.CashTimeout) then
        --warn("[AutoFarm] " .. BossName(boss) .. " slot " .. slotNum .. ": timed out waiting for $" .. tostring(cost))
        release()
        return
    end

    local cframe = AdjustedCFrame(data.spots[spotIndex])
    local ok, result = pcall(function()
        return PlaceTowerRemote:InvokeServer(uid, cframe)
    end)

    if ok and result then
        if slotNum == CONFIG.TowerUpgrade.Slot then
            table.insert(Slot1Towers, { serverId = result, uid = uid, level = 1 })
        end
        -- Keep the reservation a bit longer so the tower has time to show up in the workspace
        data.reserved[spotIndex] = tick() + CONFIG.TowerPlacer.ReserveTime
        data.placing = false
        data.lastPlace = tick()
    else
        --warn("[AutoFarm] " .. BossName(boss) .. " slot " .. slotNum .. " placement failed: " .. tostring(result))
        release()
    end
end

local TowerPlacer = { LastCheckTime = 0, LastBoss = nil, Paused = false }

local function LootExists()
    return workspace:FindFirstChild("WorldBossLoot") ~= nil
end

function TowerPlacer:Run()
    if not CONFIG.TowerPlacer.Enabled then return end

    local now = tick()
    if now - self.LastCheckTime < CONFIG.TowerPlacer.LoopInterval then return end
    self.LastCheckTime = now

    -- Pause placement while loot is out, resume once it's gone
    if CONFIG.TowerPlacer.PauseWhileLoot and LootExists() then
        self.Paused = true
        return
    end
    self.Paused = false

    local boss = GetCurrentBoss()
    if not boss or not SLOTS[boss] then return end
    self.LastBoss = boss

    for _, slotNum in ipairs({ 1, 2 }) do
        local data = SLOTS[boss][slotNum]

        if #data.spots > 0 and not data.placing and now - data.lastPlace >= CONFIG.TowerPlacer.PlaceCooldown then
            local spotIndex = FindFreeSpot(data, now)
            if spotIndex then
                -- Reserve before spawning the thread so the next loop can't pick the same spot
                data.reserved[spotIndex] = now + CONFIG.TowerPlacer.ReserveTime
                data.placing = true
                task.spawn(PlaceInSlot, boss, slotNum, spotIndex)
            end
        end
    end
end

-- ============================================================================
-- TOWER UPGRADE (slot 1 towers only, max level 3)
-- ============================================================================

local TowerUpgrader = { LastCheckTime = 0, Busy = false }

function TowerUpgrader:Run()
    if not CONFIG.TowerUpgrade.Enabled or not UpgradeTowerRemote then return end
    if self.Busy then return end

    local now = tick()
    if now - self.LastCheckTime < CONFIG.TowerUpgrade.CheckInterval then return end
    self.LastCheckTime = now

    -- Pick the first slot 1 tower below max level
    local target
    for _, t in ipairs(Slot1Towers) do
        if t.level < CONFIG.TowerUpgrade.MaxLevel then
            target = t
            break
        end
    end
    if not target then return end

    self.Busy = true
    task.spawn(function()
        local nextLevel = target.level + 1
        local cost = GetTowerCost(target.uid, nextLevel)

        if cost > 0 and not WaitForCash(cost, CONFIG.TowerUpgrade.CashTimeout) then
            --warn("[AutoFarm] Upgrade to level " .. nextLevel .. " timed out waiting for $" .. tostring(cost))
            self.Busy = false
            return
        end

        local ok, err = pcall(function()
            UpgradeTowerRemote:FireServer(tonumber(target.serverId) or target.serverId)
        end)

        if ok then
            target.level = nextLevel
        else
            warn("[AutoFarm] Upgrade failed: " .. tostring(err))
        end

        task.wait(0.3)
        self.Busy = false
    end)
end

-- ============================================================================
-- LOOT COLLECTION
-- ============================================================================

local LootCollectionSystem = {
    LastScanTime = 0,
    LootCooldowns = {},
}

function LootCollectionSystem:CollectLoot()
    if not CONFIG.LootCollection.Enabled then return end

    local now = tick()
    if now - self.LastScanTime < CONFIG.LootCollection.ScanInterval then return end
    self.LastScanTime = now

    local playerHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not playerHRP then return end

    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model:HasTag("WorldBossLoot") and model.PrimaryPart then
            local distance = (model:GetPivot().Position - playerHRP.Position).Magnitude

            if distance <= CONFIG.LootCollection.MaxDistance then
                local prompt = model.PrimaryPart:FindFirstChild("ClaimPrompt")
                    or model.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")

                if prompt then
                    local lootId = model.Name .. tostring(model)
                    local lastCollection = self.LootCooldowns[lootId] or 0

                    if CONFIG.LootCollection.FarmingMode then
                        if now - lastCollection >= CONFIG.LootCollection.CollectionCooldown then
                            pcall(fireproximityprompt, prompt)
                            self.LootCooldowns[lootId] = now
                        end
                    elseif lastCollection == 0 then
                        pcall(fireproximityprompt, prompt)
                        self.LootCooldowns[lootId] = now
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- WALK TO WORLD BOSS LOOT
-- ============================================================================

local LootWalker = { LastMove = 0, Walking = false }

-- Position of workspace.WorldBossLoot. It can be a Part, a Model, or a folder
-- of them. For a folder, returns the child closest to the player.
local function GetWorldBossLootPosition(playerPos)
    local loot = workspace:FindFirstChild("WorldBossLoot")
    if not loot then return nil end

    local function posOf(obj)
        if obj:IsA("BasePart") then return obj.Position end
        if obj:IsA("Model") then
            local ok, pivot = pcall(function() return obj:GetPivot().Position end)
            if ok then return pivot end
        end
        return nil
    end

    local direct = posOf(loot)
    if direct then return direct end

    local best, bestDist = nil, math.huge
    for _, child in ipairs(loot:GetChildren()) do
        local p = posOf(child)
        if p then
            local d = playerPos and (p - playerPos).Magnitude or 0
            if d < bestDist then
                best, bestDist = p, d
            end
        end
    end
    return best
end

function LootWalker:Run()
    if not CONFIG.WalkToLoot.Enabled then return end

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp or humanoid.Health <= 0 then
        self.Walking = false
        return
    end

    local target = GetWorldBossLootPosition(hrp.Position)
    if not target then
        if self.Walking then
            humanoid:MoveTo(hrp.Position) -- loot is gone, cancel the walk
            self.Walking = false
        end
        return
    end

    local dist = (Vector3.new(target.X, 0, target.Z)
        - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude

    if self.Walking then
        if dist <= CONFIG.WalkToLoot.StopDistance then
            humanoid:MoveTo(hrp.Position) -- stop walking
            self.Walking = false
            return
        end
    else
        if dist <= CONFIG.WalkToLoot.ResumeDistance then return end
        self.Walking = true
    end

    local now = tick()
    if now - self.LastMove >= CONFIG.WalkToLoot.RepathInterval then
        self.LastMove = now
        humanoid:MoveTo(target)
    end
end

-- ============================================================================
-- WALK TO SNARE NEAR A TOWER
-- ============================================================================

local SnareWalker = { LastMove = 0, LastCheck = 0, Walking = false, Target = nil }

local function FlatDist(a, b)
    return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- Positions of live towers in the workspace
local function GetTowerPositions()
    local positions = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:find("Tower") then
            local hp = obj:GetAttribute("UnitHP") or obj:GetAttribute("Health")
            if hp == nil or hp > 0 then
                local ok, pivot = pcall(function() return obj:GetPivot().Position end)
                if ok then table.insert(positions, pivot) end
            end
        end
    end
    return positions
end

-- Closest snare to the player that sits within TowerRadius of a tower
local function FindSnareNearTower(playerPos)
    local drops = workspace:FindFirstChild("ActiveMap")
        and workspace.ActiveMap:FindFirstChild("WorldBossDrops")
    if not drops then return nil end

    local towers = GetTowerPositions()
    if #towers == 0 then return nil end

    local best, bestDist = nil, math.huge
    for _, obj in ipairs(drops:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name == "Snare" then
            local nearTower = false
            for _, tp in ipairs(towers) do
                if FlatDist(obj.Position, tp) <= CONFIG.SnareWalk.TowerRadius then
                    nearTower = true
                    break
                end
            end
            if nearTower then
                local d = FlatDist(obj.Position, playerPos)
                if d < bestDist then
                    best, bestDist = obj, d
                end
            end
        end
    end
    return best
end

function SnareWalker:Stop(humanoid, hrp)
    if humanoid and hrp then humanoid:MoveTo(hrp.Position) end
    self.Walking = false
    self.Target = nil
end

function SnareWalker:Run()
    if not CONFIG.SnareWalk.Enabled then return end

    local now = tick()
    if now - self.LastCheck < CONFIG.SnareWalk.CheckInterval then return end
    self.LastCheck = now

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp or humanoid.Health <= 0 then
        self.Walking = false
        self.Target = nil
        return
    end

    -- Loot has priority: if loot is out or the loot walker is moving, leave movement to it
    if LootWalker.Walking or workspace:FindFirstChild("WorldBossLoot") then
        if self.Walking then self:Stop(humanoid, hrp) end
        return
    end

    local snare = FindSnareNearTower(hrp.Position)
    if not snare then
        if self.Walking then self:Stop(humanoid, hrp) end
        return
    end

    if FlatDist(snare.Position, hrp.Position) <= CONFIG.SnareWalk.StopDistance then
        if self.Walking then self:Stop(humanoid, hrp) end
        return
    end

    self.Walking = true
    self.Target = snare
    if now - self.LastMove >= CONFIG.SnareWalk.RepathInterval then
        self.LastMove = now
        humanoid:MoveTo(snare.Position)
    end
end

-- ============================================================================
-- AUTO SCYTHE
-- ============================================================================

local AutoScytheSystem = {
    LastCheckTime = 0,
    LastSwipeTime = 0,
}

function AutoScytheSystem:FindNearestTarget(playerHRP)
    local drops = workspace:FindFirstChild("ActiveMap")
        and workspace.ActiveMap:FindFirstChild("WorldBossDrops")
    if not drops then return nil end

    local nearestPos, nearestDist = nil, math.huge
    -- All targets are called "Snare", so just find the nearest one in range
    for _, obj in ipairs(drops:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name == "Snare" then
            local distance = (obj.Position - playerHRP.Position).Magnitude
            if distance <= CONFIG.AutoScythe.TargetRange and distance < nearestDist then
                nearestPos = obj.Position
                nearestDist = distance
            end
        end
    end
    return nearestPos
end

function AutoScytheSystem:Run()
    if not CONFIG.AutoScythe.Enabled or not ScytheRemote then return end

    local now = tick()
    if now - self.LastCheckTime < CONFIG.AutoScythe.CheckInterval then return end
    self.LastCheckTime = now

    local playerHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not playerHRP then return end

    local targetPos = self:FindNearestTarget(playerHRP)
    if targetPos and now - self.LastSwipeTime >= CONFIG.AutoScythe.SwipeCooldown then
        local ok, err = pcall(function()
            ScytheRemote:FireServer(targetPos)
        end)
        if ok then
            self.LastSwipeTime = now
        else
            warn("[AutoFarm] Scythe fire failed: " .. tostring(err))
        end
    end
end

-- ============================================================================
-- WALK SPEED
-- ============================================================================

local function ApplyWalkSpeed()
    if not CONFIG.WalkSpeed.Enabled then return end

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.WalkSpeed ~= CONFIG.WalkSpeed.Value then
        humanoid.WalkSpeed = CONFIG.WalkSpeed.Value
    end
end

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

local function MainLoop()
    while true do
        pcall(function()
            ApplyWalkSpeed()
            TowerPlacer:Run()
            TowerUpgrader:Run()
            LootWalker:Run()
            SnareWalker:Run()
            LootCollectionSystem:CollectLoot()
            AutoScytheSystem:Run()
        end)
        task.wait(0.05)
    end
end

-- ============================================================================
-- CONSOLE COMMANDS
-- ============================================================================

-- Overrides a boss's slot with your current position (replaces the preset for that slot)
--   SetSlotPosition(1)            -- current boss
--   SetSlotPosition(2, "Reaper")  -- specific boss
getgenv().SetSlotPosition = function(slotNum, bossKey)
    local boss = bossKey or GetCurrentBoss()
    if not boss or not SLOTS[boss] then
        warn("[AutoFarm] Unknown boss: " .. tostring(bossKey) .. ". Use Pumpkin, Reaper, or Devil.")
        return
    end
    if slotNum ~= 1 and slotNum ~= 2 then
        warn("[AutoFarm] Slot must be 1 or 2")
        return
    end

    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        warn("[AutoFarm] No character found")
        return
    end

    SLOTS[boss][slotNum].spots = { hrp.CFrame }
    SLOTS[boss][slotNum].reserved = {}
    Log(BossName(boss) .. " slot " .. slotNum .. " position set to " .. tostring(hrp.Position))
end

getgenv().ToggleTowerPlacer = function(enabled)
    CONFIG.TowerPlacer.Enabled = enabled
    Log("Tower placer: " .. tostring(enabled))
end

getgenv().ToggleGroundY = function(enabled)
    CONFIG.GroundY.Enabled = enabled
    Log("Ground Y adjust: " .. tostring(enabled))
end

getgenv().ToggleTowerUpgrade = function(enabled)
    CONFIG.TowerUpgrade.Enabled = enabled
    Log("Tower upgrade: " .. tostring(enabled))
end

getgenv().ToggleLootCollection = function(enabled)
    CONFIG.LootCollection.Enabled = enabled
    Log("Loot collection: " .. tostring(enabled))
end

getgenv().ToggleWalkToLoot = function(enabled)
    CONFIG.WalkToLoot.Enabled = enabled
    Log("Walk to loot: " .. tostring(enabled))
end

getgenv().ToggleSnareWalk = function(enabled)
    CONFIG.SnareWalk.Enabled = enabled
    Log("Snare walk: " .. tostring(enabled))
end

getgenv().ToggleAutoScythe = function(enabled)
    CONFIG.AutoScythe.Enabled = enabled
    Log("Auto scythe: " .. tostring(enabled))
end

getgenv().ToggleWalkSpeed = function(enabled)
    CONFIG.WalkSpeed.Enabled = enabled
    Log("Walk speed: " .. tostring(enabled))
end

getgenv().ToggleFarmingMode = function(enabled)
    CONFIG.LootCollection.FarmingMode = enabled
    Log("Farming mode: " .. tostring(enabled))
end

getgenv().DebugSlots = function()
    local boss = GetCurrentBoss()
    local now = tick()
    Log("Current boss: " .. BossName(boss) .. " (next change in " .. Rotation.format(Rotation.remaining()) .. ")")

    local groundY = GetGroundY()
    Log("Ground Y: " .. (groundY and string.format("%.2f", groundY) or "NOT FOUND")
        .. " (adjust " .. (CONFIG.GroundY.Enabled and "ON" or "OFF") .. ")")
    Log("Placement paused for loot: " .. tostring(TowerPlacer.Paused))

    for _, slotNum in ipairs({ 1, 2 }) do
        local data = SLOTS[boss][slotNum]
        local hotbarSlot = TOWER_HOTBAR_SLOT[slotNum]
        local uid = GetHotbarUid(hotbarSlot)
        local status
        if #data.spots == 0 then
            status = "NO POSITION"
        else
            local parts = {}
            for i, cf in ipairs(data.spots) do
                local s
                if (data.reserved[i] or 0) > now then
                    s = "reserved"
                elseif IsSpotOccupied(AdjustedCFrame(cf)) then
                    s = "occupied"
                else
                    s = "free"
                end
                table.insert(parts, i .. ":" .. s)
            end
            status = table.concat(parts, ", ")
        end
        Log(string.format("  Slot %d (hotbar %d, %s): %s", slotNum, hotbarSlot,
            uid and "tower loaded" or "EMPTY HOTBAR", status))
    end

    Log("Slot 1 towers tracked: " .. #Slot1Towers)
    for i, t in ipairs(Slot1Towers) do
        Log(string.format("  #%d level %d/%d", i, t.level, CONFIG.TowerUpgrade.MaxLevel))
    end
end

-- ============================================================================
-- START
-- ============================================================================

Log("Started. Placement uses hotbar slots " .. TOWER_HOTBAR_SLOT[1] .. " and " .. TOWER_HOTBAR_SLOT[2]
    .. ". Slot 1 towers upgrade to level " .. CONFIG.TowerUpgrade.MaxLevel .. ". Run DebugSlots() to check.")
task.spawn(MainLoop)
