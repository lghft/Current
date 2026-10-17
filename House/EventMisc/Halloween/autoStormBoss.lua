-- ============================================================================
-- WorldBoss Auto-Farm: STORM v6
-- Hotbar placement (slot 1 priority) + cash wait
-- + per-tower upgrade loops (each tower waits for cash independently)
-- + tower pruning with first-seen grace + charge detection (StormCharged)
-- + tesla: walks to the coil to ground (teleport optional)
-- + scythe walk/teleport (snares + clamps) + breaker pulls (skips Pulled)
-- + loot + candy touch + candy ring patrol + auto scythe
-- + walk speed locked at 44.8 + move arbiter
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
        LoopInterval = 0.5,
        PlaceCooldown = 2,
        SlotRadius = 4,        -- live tower this close (X/Z) to a spot = occupied
        ReserveTime = 8,
        CashTimeout = 30,
        PauseWhileLoot = true,
    },

    GroundY = {
        Enabled = true,
        Offset = 2.45,
    },

    TowerUpgrade = {
        Enabled = true,
        Slot = 1,              -- only towers placed from this slot get upgraded
        MaxLevel = 3,
        CheckInterval = 0.2,   -- how often the upgrader looks for new towers to start loops for
        ConfirmTime = 1.5,     -- seconds after firing before reading the level and releasing reserved cash
        MatchRadius = 6,       -- live tower this close (X/Z) to a queue entry = same tower
        FirstSeenTimeout = 30, -- how long a new entry may wait for its tower to appear
        DeadAfter = 1.5,       -- seconds missing (after being seen) before pruning
    },

    Tesla = {
        Enabled = true,
        CheckInterval = 0.1,
        GroundAtCoil = true,   -- go to the nearest PlasmaGlobe to ground the charge
        UseTeleport = false,   -- false = walk to the target, true = instant teleport
        StopDistance = 3,      -- stop walking once this close (X/Z) to the target
        RepathInterval = 0.5,  -- how often MoveTo is re-sent while walking
        Cooldown = 2,          -- teleport mode only
        TeleportTo = Vector3.new(9941, 6, -57), -- fallback spot when GroundAtCoil is off or no coil found
    },

    LootCollection = {
        Enabled = true,
        ScanInterval = 0.2,
        CollectionCooldown = 0.5,
    },

    WalkToLoot = {
        Enabled = true,
        StopDistance = 20,
        RepathInterval = 0.5,
    },

    ScytheWalk = {             -- walks/teleports to snares and clamps near a tower
        Enabled = true,
        TowerRadius = 5,       -- a target counts if this close (X/Z) to a live tower
        StopDistance = 10,     -- scythe reaches 14 from the player; 10 leaves margin
        UseTeleport = false,   -- true = instant CFrame move instead of walking
        RepathInterval = 0.5,
        CheckInterval = 0.25,
        IncludeClamps = true,  -- also walk to / teleport to WorldBossLocalFx.Clamp
    },

    Breaker = {
        Enabled = true,
        StopDistance = 6,      -- prompt reach is 14, stay well inside it
        PromptCooldown = 1,
        UseTeleport = true,    -- instant move to the breaker
        RepathInterval = 0.5,
        CheckInterval = 0.25,
    },

    Candy = {
        Enabled = true,
        ScanInterval = 0.25,
        TouchCooldown = 0.5,
        TouchRange = 60,       -- firetouch any candy this close (X/Z), like the original script
        DetourRange = 25,      -- walk toward candy this close, otherwise keep patrolling
        DetourStop = 4,        -- stop walking once this close to a detour candy
        WaypointSpacing = 10,  -- studs between waypoints along the circumference
        ArriveDistance = 4,    -- advance to the next waypoint once this close
        Direction = 1,         -- 1 or -1 to flip which way around the circle it walks
    },

    ClampTeleport = {          -- teleports onto the nearest WorldBossLocalFx.Clamp
        Enabled = true,
        CheckInterval = 0.1,
        StopDistance = 5,      -- stop teleporting once this close (X/Z); scythe reaches 14
        Cooldown = 0.5,        -- min seconds between clamp teleports
    },

    AutoScythe = {
        Enabled = true,
        CheckInterval = 0.15,
        SwipeCooldown = 0.6,
        Range = 12,            -- server checks 14 from the player's HumanoidRootPart
    },

    WalkSpeed = {
        Enabled = true,
        Value = 44.8,
    },
}

-- ============================================================================
-- STORM SPOTS
-- ============================================================================

local STORM_SPOTS = {
    [1] = {
        CFrame.new(9980, 3, -48),
        CFrame.new(9992, 3, -53),
    },
    [2] = {
        CFrame.new(9982, 3, -38),
    },
}

-- Which HOTBAR slot holds the tower for each placement slot.
local TOWER_HOTBAR_SLOT = {
    [1] = 1,
    [2] = 2,
}

-- Circle the candy patrol walks around (points are from your measurement)
local CANDY_RING_CENTER = Vector3.new(10001, 0, -1)
local CANDY_RING_OUTER  = Vector3.new(10024, 0, 24)

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

if not firetouchinterest then
    warn("[AutoFarm] firetouchinterest not available, candy collection disabled.")
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

local function FlatDist(a, b)
    return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- Position of a BasePart or Model (nil otherwise)
local function PosOf(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        local ok, pivot = pcall(function() return obj:GetPivot().Position end)
        if ok then return pivot end
    end
    return nil
end

local function DropsFolder()
    local active = workspace:FindFirstChild("ActiveMap")
    return active and active:FindFirstChild("WorldBossDrops")
end

-- Returns humanoid, hrp if the character is alive, otherwise nil
local function GetCharacterParts()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp or humanoid.Health <= 0 then return nil end
    return humanoid, hrp
end

-- Ground-level Y from the map, or nil
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

local function AdjustedCFrame(cf)
    if not CONFIG.GroundY.Enabled then return cf end
    local groundY = GetGroundY()
    if not groundY then return cf end
    local pos = Vector3.new(cf.X, groundY + CONFIG.GroundY.Offset, cf.Z)
    return CFrame.fromMatrix(pos, cf.RightVector, cf.UpVector)
end

-- Point at the same X/Z as pos, at ground height (for walking targets)
local function GroundPoint(pos, fallbackY)
    return Vector3.new(pos.X, GetGroundY() or fallbackY or pos.Y, pos.Z)
end

-- Teleports the character to (X/Z of pos) at the ground height
local function TeleportOnGround(hrp, pos)
    local y = GetGroundY() or hrp.Position.Y
    hrp.CFrame = CFrame.new(pos.X, y + 3, pos.Z)
end

-- ============================================================================
-- SLOTS
-- ============================================================================

local SLOTS = {}
for slotNum = 1, 2 do
    local spots = {}
    for i, cf in ipairs(STORM_SPOTS[slotNum]) do spots[i] = cf end
    SLOTS[slotNum] = { spots = spots, reserved = {}, lastPlace = 0, placing = false }
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

-- Placements currently waiting on cash. Upgrades yield to placements.
local PlacementsWaiting = 0

local function WaitForCash(amount, maxWait)
    local startTime = os.clock()
    while GetPlayerCash() < amount do
        if os.clock() - startTime > maxWait then return false end
        task.wait(0.1)
    end
    return true
end

-- ============================================================================
-- TOWER CACHE
-- ============================================================================

local TowerCache = { time = 0, list = {} }

-- Live towers as { model, pos }, refreshed at most every 0.2s
local function GetLiveTowers()
    local now = tick()
    if now - TowerCache.time < 0.2 then return TowerCache.list end
    TowerCache.time = now

    local list = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:find("Tower") then
            local hp = obj:GetAttribute("UnitHP") or obj:GetAttribute("Health")
            if hp == nil or hp > 0 then
                local pos = PosOf(obj)
                if pos then table.insert(list, { model = obj, pos = pos }) end
            end
        end
    end
    TowerCache.list = list
    return list
end

-- First live tower within radius (X/Z) of pos, or nil
local function TowerNear(pos, radius)
    for _, t in ipairs(GetLiveTowers()) do
        if FlatDist(t.pos, pos) <= radius then return t end
    end
    return nil
end

local function IsSpotOccupied(cframe)
    return TowerNear(cframe.Position, CONFIG.TowerPlacer.SlotRadius) ~= nil
end

-- ============================================================================
-- LOOT LOOKUP (WorldBossLoot.Body.ClaimPrompt)
-- ============================================================================

local function FindLoot()
    local loot = workspace:FindFirstChild("WorldBossLoot")
    if not loot then return nil end

    local body = loot:FindFirstChild("Body") or loot
    local prompt = body:FindFirstChild("ClaimPrompt") or loot:FindFirstChild("ClaimPrompt", true)
    local pos = PosOf(body) or PosOf(loot)
    if not pos then
        local part = loot:FindFirstChildWhichIsA("BasePart", true)
        pos = part and part.Position
    end
    return { prompt = prompt, pos = pos }
end

-- ============================================================================
-- MOVE ARBITER
-- Only one walker or teleporter controls the character at a time.
-- ============================================================================

local Move = { owner = nil, priority = 0, expires = 0 }

local PRIORITY = {
    Tesla = 100,
    Loot = 90,
    Breaker = 60,
    Scythe = 50,
    Clamp = 95,
    Candy = 10,
}

local function ClaimMove(name)
    local now = tick()
    local p = PRIORITY[name] or 0
    if Move.owner and Move.owner ~= name and now < Move.expires and Move.priority > p then
        return false
    end
    Move.owner = name
    Move.priority = p
    Move.expires = now + 0.5
    return true
end

local function ReleaseMove(name, humanoid, hrp)
    if Move.owner == name then
        Move.owner = nil
        Move.priority = 0
        Move.expires = 0
        if humanoid and hrp then humanoid:MoveTo(hrp.Position) end
    end
end

-- ============================================================================
-- UPGRADE QUEUE
-- One entry per slot 1 tower. Each entry gets its own upgrade loop.
-- ============================================================================

local UpgradeQueue = {}

local function AddToQueue(serverId, uid, pos)
    local now = tick()
    table.insert(UpgradeQueue, {
        serverId = serverId,
        uid = uid,
        pos = pos,
        model = nil,
        level = 1,
        placedAt = now,
        lastSeen = now,
        seen = false,      -- true once a live tower has been matched to this entry
        removed = false,   -- set when pruned; its upgrade loop exits
        upgrading = false, -- true while this entry's upgrade loop is running
    })
end

-- ============================================================================
-- TOWER PLACER
-- Slot 1 always gets the first attempt. Slot 2 only starts when slot 1
-- has nothing in flight and no free spot ready.
-- ============================================================================

local warnedHotbar = {}

local function FindFreeSpot(data, now)
    for i, cf in ipairs(data.spots) do
        local reservedUntil = data.reserved[i] or 0
        if reservedUntil <= now and not IsSpotOccupied(AdjustedCFrame(cf)) then
            return i
        end
    end
    return nil
end

local function PlaceInSlot(slotNum, spotIndex)
    local data = SLOTS[slotNum]
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
    if cost > 0 then
        PlacementsWaiting += 1
        local ok = WaitForCash(cost, CONFIG.TowerPlacer.CashTimeout)
        PlacementsWaiting -= 1
        if not ok then
            release()
            return
        end
    end

    local cframe = AdjustedCFrame(data.spots[spotIndex])
    local ok, result = pcall(function()
        return PlaceTowerRemote:InvokeServer(uid, cframe)
    end)

    if ok and result then
        if slotNum == CONFIG.TowerUpgrade.Slot then
            AddToQueue(result, uid, cframe.Position)
        end
        data.reserved[spotIndex] = tick() + CONFIG.TowerPlacer.ReserveTime
        data.placing = false
        data.lastPlace = tick()
    else
        release()
    end
end

local TowerPlacer = { LastCheckTime = 0, Paused = false }

function TowerPlacer:Run()
    if not CONFIG.TowerPlacer.Enabled then return end

    local now = tick()
    if now - self.LastCheckTime < CONFIG.TowerPlacer.LoopInterval then return end
    self.LastCheckTime = now

    if CONFIG.TowerPlacer.PauseWhileLoot and workspace:FindFirstChild("WorldBossLoot") then
        self.Paused = true
        return
    end
    self.Paused = false

    -- Slot 1 first
    local slot1 = SLOTS[1]
    local slot1Busy = slot1.placing
    if not slot1Busy and #slot1.spots > 0 and now - slot1.lastPlace >= CONFIG.TowerPlacer.PlaceCooldown then
        local spotIndex = FindFreeSpot(slot1, now)
        if spotIndex then
            slot1.reserved[spotIndex] = now + CONFIG.TowerPlacer.ReserveTime
            slot1.placing = true
            task.spawn(PlaceInSlot, 1, spotIndex)
            slot1Busy = true
        end
    end

    -- Slot 1 still busy, so slot 2 waits
    if slot1Busy then return end

    -- Slot 2 only when slot 1 has nothing to do
    local slot2 = SLOTS[2]
    if #slot2.spots > 0 and not slot2.placing and now - slot2.lastPlace >= CONFIG.TowerPlacer.PlaceCooldown then
        local spotIndex = FindFreeSpot(slot2, now)
        if spotIndex then
            slot2.reserved[spotIndex] = now + CONFIG.TowerPlacer.ReserveTime
            slot2.placing = true
            task.spawn(PlaceInSlot, 2, spotIndex)
        end
    end
end

-- ============================================================================
-- TOWER UPGRADER
--
-- Each tower gets its own upgrade loop, started as soon as it's in the queue.
-- A loop waits until there's cash for its next level (minus cash already
-- reserved by other loops), fires the upgrade, then waits ConfirmTime before
-- starting the next level. Loops run in parallel, so a tower waiting on cash
-- never blocks another tower from upgrading. Placements waiting on cash take
-- priority over upgrades.
--
-- The level is taken from the tower's level attribute when the game exposes
-- one, otherwise it's assumed to go up by one after each fire.
-- ============================================================================

local LEVEL_ATTRIBUTES = { "Level", "level", "Tier", "UpgradeLevel" }

local function ReadTowerLevel(model)
    if not model then return nil end
    for _, name in ipairs(LEVEL_ATTRIBUTES) do
        local v = model:GetAttribute(name)
        if type(v) == "number" then return v end
    end
    return nil
end

-- Cash claimed by upgrades that fired but haven't shown up in cash yet
local UpgradeReserved = 0

local function UpgradeLoop(r)
    local cfg = CONFIG.TowerUpgrade

    while not r.removed and r.level < cfg.MaxLevel do
        local nextLevel = r.level + 1
        local cost = GetTowerCost(r.uid, nextLevel)

        -- Wait for cash: placements first, then this tower's cost after other reservations
        while not r.removed and (PlacementsWaiting > 0 or GetPlayerCash() - UpgradeReserved < cost) do
            task.wait(0.1)
        end
        if r.removed then break end

        UpgradeReserved += cost
        local ok, err = pcall(function()
            UpgradeTowerRemote:FireServer(tonumber(r.serverId) or r.serverId)
        end)

        if ok then
            r.level = nextLevel -- optimistic, corrected below if the game exposes the level
        else
            warn("[AutoFarm] Upgrade fire failed: " .. tostring(err))
        end

        -- Give the server time to take the cash and update the tower
        task.wait(cfg.ConfirmTime)
        UpgradeReserved = math.max(0, UpgradeReserved - cost)

        local lvl = ReadTowerLevel(r.model)
        if lvl then r.level = lvl end
    end

    r.upgrading = false
end

local TowerUpgrader = { LastRun = 0 }

function TowerUpgrader:Run()
    local cfg = CONFIG.TowerUpgrade
    if not cfg.Enabled or not UpgradeTowerRemote then return end

    local now = tick()
    if now - self.LastRun < cfg.CheckInterval then return end
    self.LastRun = now

    -- 1. Match queue entries to live towers, prune only towers truly gone
    for i = #UpgradeQueue, 1, -1 do
        local r = UpgradeQueue[i]
        local match = TowerNear(r.pos, cfg.MatchRadius)
        if match then
            r.model = match.model
            r.pos = match.pos
            r.lastSeen = now
            r.seen = true
        else
            r.model = nil
            local gone
            if r.seen then
                gone = now - r.lastSeen > cfg.DeadAfter
            else
                gone = now - r.placedAt > cfg.FirstSeenTimeout
            end

            if gone then
                Log(string.format("Tower removed from upgrade queue (level %d, seen: %s)",
                    r.level, tostring(r.seen)))
                r.removed = true
                table.remove(UpgradeQueue, i)
            end
        end
    end

    -- 2. Start an upgrade loop for every tower that doesn't have one yet
    for _, r in ipairs(UpgradeQueue) do
        if not r.upgrading and not r.removed and r.level < cfg.MaxLevel then
            r.upgrading = true
            task.spawn(UpgradeLoop, r)
        end
    end
end

-- ============================================================================
-- CHARGE + TESLA
-- The server sets the StormCharged player attribute while a player is charged,
-- and discharges centered on that player when the timer ends.
-- Grounding: get to a PlasmaGlobe while charged. Walks by default.
-- ============================================================================

local function IsCharged()
    return LocalPlayer:GetAttribute("StormCharged") ~= nil
end

local function GetCoils()
    local out = {}
    local active = workspace:FindFirstChild("ActiveMap")
    if not active then return out end
    for _, obj in ipairs(active:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name == "PlasmaGlobe" then
            table.insert(out, obj.Position)
        end
    end
    return out
end

local function NearestCoil(pos)
    local best, bestDist
    for _, c in ipairs(GetCoils()) do
        local d = FlatDist(c, pos)
        if not bestDist or d < bestDist then
            best, bestDist = c, d
        end
    end
    return best
end

local TeslaSystem = { LastCheck = 0, LastTeleport = 0, LastMove = 0, Walking = false }

-- Where the charged player should go: nearest coil, or the fallback spot
local function TeslaTarget(hrp)
    local cfg = CONFIG.Tesla
    if cfg.GroundAtCoil then
        local coil = NearestCoil(hrp.Position)
        if coil then return coil end
    end
    return cfg.TeleportTo
end

function TeslaSystem:Stop(humanoid, hrp)
    if self.Walking then
        ReleaseMove("Tesla", humanoid, hrp)
        self.Walking = false
    end
end

function TeslaSystem:Run()
    local cfg = CONFIG.Tesla
    if not cfg.Enabled then return end

    local now = tick()
    if now - self.LastCheck < cfg.CheckInterval then return end
    self.LastCheck = now

    local humanoid, hrp = GetCharacterParts()
    if not humanoid then
        self.Walking = false
        return
    end

    if not IsCharged() then
        self:Stop(humanoid, hrp)
        return
    end

    local target = TeslaTarget(hrp)

    -- Teleport mode: instant move, on cooldown
    if cfg.UseTeleport then
        if now - self.LastTeleport < cfg.Cooldown then return end
        if not ClaimMove("Tesla") then return end
        if target == cfg.TeleportTo then
            hrp.CFrame = CFrame.new(cfg.TeleportTo)
        else
            TeleportOnGround(hrp, target)
        end
        self.LastTeleport = now
        return
    end

    -- Walk mode: go to the target at ground height and stay on it
    local walkTo = GroundPoint(target, hrp.Position.Y)
    if FlatDist(walkTo, hrp.Position) <= cfg.StopDistance then
        self:Stop(humanoid, hrp)
        return
    end

    if not ClaimMove("Tesla") then return end
    self.Walking = true
    if now - self.LastMove >= cfg.RepathInterval then
        self.LastMove = now
        humanoid:MoveTo(walkTo)
    end
end

-- ============================================================================
-- LOOT (collect + walk)
-- ============================================================================

local LootSystem = { LastScan = 0, LastPrompt = 0, LastMove = 0, Walking = false }

function LootSystem:Run()
    local collect = CONFIG.LootCollection.Enabled
    local walk = CONFIG.WalkToLoot.Enabled
    if not collect and not walk then return end

    local now = tick()
    if now - self.LastScan < CONFIG.LootCollection.ScanInterval then return end
    self.LastScan = now

    local humanoid, hrp = GetCharacterParts()
    if not humanoid then
        self.Walking = false
        return
    end

    local loot = FindLoot()
    if not loot then
        if self.Walking then
            ReleaseMove("Loot", humanoid, hrp)
            self.Walking = false
        end
        return
    end

    if collect and loot.prompt and now - self.LastPrompt >= CONFIG.LootCollection.CollectionCooldown then
        self.LastPrompt = now
        pcall(fireproximityprompt, loot.prompt)
    end

    if walk and loot.pos then
        if FlatDist(loot.pos, hrp.Position) <= CONFIG.WalkToLoot.StopDistance then
            if self.Walking then
                ReleaseMove("Loot", humanoid, hrp)
                self.Walking = false
            end
        elseif ClaimMove("Loot") then
            self.Walking = true
            if now - self.LastMove >= CONFIG.WalkToLoot.RepathInterval then
                self.LastMove = now
                humanoid:MoveTo(loot.pos)
            end
        end
    end
end

-- ============================================================================
-- TARGETS
-- Snare parts in WorldBossDrops (server-freeable) and, when enabled,
-- Clamp parts in WorldBossLocalFx (the cables).
-- ============================================================================

local TARGET_NAMES = { Snare = true, Clamp = true }

local function FindTargets()
    local out = {}
    local roots = {}

    local drops = DropsFolder()
    if drops then table.insert(roots, drops) end

    local fx = workspace:FindFirstChild("WorldBossLocalFx")
    if fx and CONFIG.ScytheWalk.IncludeClamps then table.insert(roots, fx) end

    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if TARGET_NAMES[obj.Name] and (obj:IsA("BasePart") or obj:IsA("Model")) then
                local p = PosOf(obj)
                if p then table.insert(out, { obj = obj, pos = p }) end
            end
        end
    end
    return out
end

-- Snares within TowerRadius of a live tower (clamps are handled by ClampSystem)
local function SnaresNearTowers()
    local towers = GetLiveTowers()
    if #towers == 0 then return {} end

    local out = {}
    for _, s in ipairs(FindTargets()) do
        if s.obj.Name ~= "Snare" then continue end
        for _, t in ipairs(towers) do
            if FlatDist(s.pos, t.pos) <= CONFIG.ScytheWalk.TowerRadius then
                table.insert(out, s)
                break
            end
        end
    end
    return out
end

-- ============================================================================
-- SCYTHE WALK / TELEPORT
-- Moves to the target closest to the player that is near a tower,
-- until it is within scythe range.
-- ============================================================================

local ScytheWalker = { LastCheck = 0, LastMove = 0, Walking = false }

function ScytheWalker:Stop(humanoid, hrp)
    ReleaseMove("Scythe", humanoid, hrp)
    self.Walking = false
end

function ScytheWalker:Run()
    local cfg = CONFIG.ScytheWalk
    if not cfg.Enabled then return end

    local now = tick()
    if now - self.LastCheck < cfg.CheckInterval then return end
    self.LastCheck = now

    local humanoid, hrp = GetCharacterParts()
    if not humanoid then
        self.Walking = false
        return
    end

    if FindLoot() then
        if self.Walking then self:Stop(humanoid, hrp) end
        return
    end

    local best, bestDist
    for _, s in ipairs(SnaresNearTowers()) do
        local d = FlatDist(s.pos, hrp.Position)
        if not bestDist or d < bestDist then
            best, bestDist = s, d
        end
    end

    if not best or bestDist <= cfg.StopDistance then
        if self.Walking then self:Stop(humanoid, hrp) end
        return
    end

    if not ClaimMove("Scythe") then return end

    if cfg.UseTeleport then
        TeleportOnGround(hrp, best.pos)
        return
    end

    self.Walking = true
    if now - self.LastMove >= cfg.RepathInterval then
        self.LastMove = now
        humanoid:MoveTo(best.pos)
    end
end

-- ============================================================================
-- BREAKER
-- Walks or teleports to the unpulled breaker closest to any tower, then fires
-- its PullPrompt. Breakers with Pulled == true are skipped.
-- ============================================================================

local BreakerWalker = { LastCheck = 0, LastMove = 0, LastPrompt = 0, Walking = false }

local function FindBreakers()
    local out = {}
    local drops = DropsFolder()
    if not drops then return out end

    for _, obj in ipairs(drops:GetDescendants()) do
        if obj.Name == "Breaker" and (obj:IsA("BasePart") or obj:IsA("Model")) then
            if obj:GetAttribute("Pulled") ~= true then
                local prompt = obj:FindFirstChild("PullPrompt", true)
                local pos = PosOf(obj)
                if prompt and pos then
                    table.insert(out, { prompt = prompt, pos = pos, obj = obj })
                end
            end
        end
    end
    return out
end

function BreakerWalker:Stop(humanoid, hrp)
    ReleaseMove("Breaker", humanoid, hrp)
    self.Walking = false
end

function BreakerWalker:Run()
    local cfg = CONFIG.Breaker
    if not cfg.Enabled then return end

    local now = tick()
    if now - self.LastCheck < cfg.CheckInterval then return end
    self.LastCheck = now

    local humanoid, hrp = GetCharacterParts()
    if not humanoid then
        self.Walking = false
        return
    end

    if FindLoot() then
        if self.Walking then self:Stop(humanoid, hrp) end
        return
    end

    local breakers = FindBreakers()
    if #breakers == 0 then
        if self.Walking then self:Stop(humanoid, hrp) end
        return
    end

    -- Rank by distance to the nearest tower (player distance if no towers)
    local towers = GetLiveTowers()
    local best, bestScore
    for _, b in ipairs(breakers) do
        local score = FlatDist(b.pos, hrp.Position)
        if #towers > 0 then
            score = math.huge
            for _, t in ipairs(towers) do
                score = math.min(score, FlatDist(b.pos, t.pos))
            end
        end
        if not bestScore or score < bestScore then
            best, bestScore = b, score
        end
    end

    if FlatDist(best.pos, hrp.Position) <= cfg.StopDistance then
        if self.Walking then self:Stop(humanoid, hrp) end
        if now - self.LastPrompt >= cfg.PromptCooldown then
            self.LastPrompt = now
            pcall(fireproximityprompt, best.prompt)
        end
        return
    end

    if not ClaimMove("Breaker") then return end

    if cfg.UseTeleport then
        TeleportOnGround(hrp, best.pos)
        return
    end

    self.Walking = true
    if now - self.LastMove >= cfg.RepathInterval then
        self.LastMove = now
        humanoid:MoveTo(best.pos)
    end
end

-- ============================================================================
-- CLAMPS (cables)
-- Teleports the player onto the nearest WorldBossLocalFx.Clamp until it is
-- within StopDistance, so the AutoScythe can free it. While any clamp exists,
-- the candy circle walk is paused (see CandySystem).
-- ============================================================================

local function FindClamps()
    local out = {}
    local fx = workspace:FindFirstChild("WorldBossLocalFx")
    if not fx then return out end
    for _, obj in ipairs(fx:GetDescendants()) do
        if obj.Name == "Clamp" and (obj:IsA("BasePart") or obj:IsA("Model")) then
            local p = PosOf(obj)
            if p then table.insert(out, { obj = obj, pos = p }) end
        end
    end
    return out
end

local ClampSystem = { LastCheck = 0, LastTeleport = 0 }

function ClampSystem:Run()
    local cfg = CONFIG.ClampTeleport
    if not cfg.Enabled then return end

    local now = tick()
    if now - self.LastCheck < cfg.CheckInterval then return end
    self.LastCheck = now

    local humanoid, hrp = GetCharacterParts()
    if not humanoid then return end

    local best, bestDist
    for _, c in ipairs(FindClamps()) do
        local d = FlatDist(c.pos, hrp.Position)
        if not bestDist or d < bestDist then
            best, bestDist = c, d
        end
    end

    if not best or bestDist <= cfg.StopDistance then return end
    if now - self.LastTeleport < cfg.Cooldown then return end
    if not ClaimMove("Clamp") then return end

    hrp.CFrame = CFrame.new(best.pos + Vector3.new(0, 3, 0))
    -- Cancel any MoveTo still in flight so the character doesn't walk back
    humanoid:MoveTo(hrp.Position)
    self.LastTeleport = now
end

-- ============================================================================
-- CANDY
-- Two parts:
--   1. Touch: every candy within TouchRange gets firetouchinterest, same as
--      the original script. No movement needed.
--   2. Patrol: walk around the candy ring at a fixed spacing, detouring to
--      candy within DetourRange. Lowest priority for movement.
-- ============================================================================

local CANDY_RADIUS = FlatDist(CANDY_RING_OUTER, CANDY_RING_CENTER)
local TWO_PI = math.pi * 2

local CandySystem = { LastScan = 0, LastTouch = {}, Angle = nil }

local function CandyPart(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function FindCandies()
    local out = {}
    local drops = DropsFolder()
    if not drops then return out end
    for _, obj in ipairs(drops:GetDescendants()) do
        if obj.Name == "Candy" then
            local part = CandyPart(obj)
            local interest = part and (part:FindFirstChild("TouchInterest") or obj:FindFirstChild("TouchInterest", true))
            if part and interest then
                table.insert(out, { part = part, pos = part.Position })
            end
        end
    end
    return out
end

-- Angle of a point around the candy circle center (matches PointOnRing)
local function RingAngle(pos)
    return math.atan2(pos.X - CANDY_RING_CENTER.X, pos.Z - CANDY_RING_CENTER.Z)
end

local function PointOnRing(angle)
    return Vector3.new(
        CANDY_RING_CENTER.X + math.sin(angle) * CANDY_RADIUS,
        0,
        CANDY_RING_CENTER.Z + math.cos(angle) * CANDY_RADIUS
    )
end

function CandySystem:Run()
    local cfg = CONFIG.Candy
    if not cfg.Enabled or not firetouchinterest then return end

    local now = tick()
    if now - self.LastScan < cfg.ScanInterval then return end
    self.LastScan = now

    local humanoid, hrp = GetCharacterParts()
    if not humanoid then return end

    -- 1. Touch everything in range, and find the nearest candy for the detour
    local nearest, nearestDist
    for _, c in ipairs(FindCandies()) do
        local d = FlatDist(c.pos, hrp.Position)
        if not nearestDist or d < nearestDist then
            nearest, nearestDist = c, d
        end
        if d <= cfg.TouchRange then
            local last = self.LastTouch[c.part] or 0
            if now - last >= cfg.TouchCooldown then
                self.LastTouch[c.part] = now
                pcall(function()
                    firetouchinterest(c.part, hrp, 0)
                    firetouchinterest(c.part, hrp, 1)
                end)
            end
        end
    end

    -- 2. While charged, the Tesla walk owns movement. Drop any candy movement
    -- and re-sync the circle position when the charge ends. Touching still runs above.
    -- Circle walk pauses while charged, clamps are up, loot is out, or breakers are unpulled
    if IsCharged() or #FindClamps() > 0 or FindLoot() ~= nil or #FindBreakers() > 0 then
        ReleaseMove("Candy", humanoid, hrp)
        self.Angle = nil
        return
    end

    -- 3. Movement needs the arbiter. If something higher holds it, keep our place.
    if not ClaimMove("Candy") then return end

    -- Detour toward candy that is close but not yet at DetourStop
    if nearest and nearestDist <= cfg.DetourRange and nearestDist > cfg.DetourStop then
        humanoid:MoveTo(nearest.pos)
        return
    end

    -- Otherwise patrol the circumference
    if not self.Angle then
        self.Angle = RingAngle(hrp.Position)
    end

    local step = cfg.WaypointSpacing / CANDY_RADIUS
    local waypoint = PointOnRing(self.Angle)
    if FlatDist(waypoint, hrp.Position) <= cfg.ArriveDistance then
        self.Angle = (self.Angle + cfg.Direction * step) % TWO_PI
        waypoint = PointOnRing(self.Angle)
    end
    humanoid:MoveTo(waypoint)
end

-- ============================================================================
-- AUTO SCYTHE (snares + clamps, range 12)
-- ============================================================================

local AutoScytheSystem = { LastCheck = 0, LastSwipe = 0 }

function AutoScytheSystem:Run()
    local cfg = CONFIG.AutoScythe
    if not cfg.Enabled or not ScytheRemote then return end

    local now = tick()
    if now - self.LastCheck < cfg.CheckInterval then return end
    self.LastCheck = now

    local _, hrp = GetCharacterParts()
    if not hrp then return end

    local bestPos, bestDist
    for _, s in ipairs(FindTargets()) do
        local d = FlatDist(s.pos, hrp.Position)
        if d <= cfg.Range and (not bestDist or d < bestDist) then
            bestPos, bestDist = s.pos, d
        end
    end

    if bestPos and now - self.LastSwipe >= cfg.SwipeCooldown then
        local ok, err = pcall(function()
            ScytheRemote:FireServer(bestPos)
        end)
        if ok then
            self.LastSwipe = now
        else
            warn("[AutoFarm] Scythe fire failed: " .. tostring(err))
        end
    end
end

-- ============================================================================
-- WALK SPEED
-- Locked at CONFIG.WalkSpeed.Value. A property watcher resets WalkSpeed the
-- moment the game changes it, and the watcher is rebound on every new
-- character/humanoid so respawns stay locked too.
-- ============================================================================

local WalkSpeedWatch = { humanoid = nil, conn = nil }

local function EnforceWalkSpeed(humanoid)
    if CONFIG.WalkSpeed.Enabled and humanoid.WalkSpeed ~= CONFIG.WalkSpeed.Value then
        humanoid.WalkSpeed = CONFIG.WalkSpeed.Value
    end
end

local function BindWalkSpeed(humanoid)
    if WalkSpeedWatch.conn then
        WalkSpeedWatch.conn:Disconnect()
        WalkSpeedWatch.conn = nil
    end
    WalkSpeedWatch.humanoid = humanoid
    WalkSpeedWatch.conn = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        EnforceWalkSpeed(humanoid)
    end)
    EnforceWalkSpeed(humanoid)
end

local function ApplyWalkSpeed()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if humanoid ~= WalkSpeedWatch.humanoid then
        BindWalkSpeed(humanoid)
    else
        EnforceWalkSpeed(humanoid)
    end
end

-- ============================================================================
-- MAIN LOOP
-- Each system runs in its own pcall so one error doesn't stop the rest.
-- ============================================================================

local Systems = {
    ApplyWalkSpeed,
    function() TeslaSystem:Run() end,
    function() TowerPlacer:Run() end,
    function() TowerUpgrader:Run() end,
    function() LootSystem:Run() end,
    function() BreakerWalker:Run() end,
    function() ScytheWalker:Run() end,
    function() ClampSystem:Run() end,
    function() AutoScytheSystem:Run() end,
    function() CandySystem:Run() end,
}

local erroredSystems = {}

local function MainLoop()
    while true do
        for i, fn in ipairs(Systems) do
            local ok, err = pcall(fn)
            if not ok and not erroredSystems[i] then
                erroredSystems[i] = true
                warn("[AutoFarm] System " .. i .. " error: " .. tostring(err))
            end
        end
        task.wait(0.05)
    end
end

-- ============================================================================
-- CONSOLE COMMANDS
-- ============================================================================

-- Overrides a slot's spot with your current position
--   SetSlotPosition(1)  or  SetSlotPosition(2)
getgenv().SetSlotPosition = function(slotNum)
    if slotNum ~= 1 and slotNum ~= 2 then
        warn("[AutoFarm] Slot must be 1 or 2")
        return
    end

    local _, hrp = GetCharacterParts()
    if not hrp then
        warn("[AutoFarm] No character found")
        return
    end

    SLOTS[slotNum].spots = { hrp.CFrame }
    SLOTS[slotNum].reserved = {}
    Log("Storm slot " .. slotNum .. " position set to " .. tostring(hrp.Position))
end

-- ToggleTowerPlacer(true), ToggleTesla(false), ToggleCandy(...), etc.
for key, cfg in pairs(CONFIG) do
    getgenv()["Toggle" .. key] = function(enabled)
        cfg.Enabled = enabled
        Log(key .. ": " .. tostring(enabled))
    end
end

getgenv().DebugCharge = function()
    local _, hrp = GetCharacterParts()
    Log("Charged: " .. tostring(IsCharged()))
    if hrp then
        local coil = NearestCoil(hrp.Position)
        Log("Nearest coil: " .. (coil and tostring(coil) or "NONE"))
    end
    Log("Coils found: " .. #GetCoils())
end

getgenv().DebugSlots = function()
    local now = tick()
    local groundY = GetGroundY()
    Log("Ground Y: " .. (groundY and string.format("%.2f", groundY) or "NOT FOUND")
        .. " (adjust " .. (CONFIG.GroundY.Enabled and "ON" or "OFF") .. ")")
    Log("Placement paused for loot: " .. tostring(TowerPlacer.Paused))
    Log("Placements waiting on cash: " .. PlacementsWaiting)

    for slotNum = 1, 2 do
        local data = SLOTS[slotNum]
        local uid = GetHotbarUid(TOWER_HOTBAR_SLOT[slotNum])
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
        Log(string.format("  Slot %d (hotbar %d, %s): %s", slotNum, TOWER_HOTBAR_SLOT[slotNum],
            uid and "tower loaded" or "EMPTY HOTBAR",
            #parts > 0 and table.concat(parts, ", ") or "NO POSITION"))
    end
end

getgenv().DebugUpgrades = function()
    Log(string.format("Cash: %d | Reserved for upgrades: %d | Queue size: %d",
        GetPlayerCash(), UpgradeReserved, #UpgradeQueue))
    for i, r in ipairs(UpgradeQueue) do
        local state
        if r.level >= CONFIG.TowerUpgrade.MaxLevel then
            state = "MAX"
        elseif not r.model then
            state = r.seen and "NO LIVE TOWER (was seen)" or "WAITING FOR TOWER TO APPEAR"
        elseif r.upgrading then
            state = "upgrading, next $" .. GetTowerCost(r.uid, r.level + 1)
        else
            state = "idle"
        end
        Log(string.format("  #%d level %d/%d: %s", i, r.level, CONFIG.TowerUpgrade.MaxLevel, state))
    end
end

-- ============================================================================
-- START
-- ============================================================================

Log("Storm farm v6 started. Placement uses hotbar slots " .. TOWER_HOTBAR_SLOT[1]
    .. " and " .. TOWER_HOTBAR_SLOT[2] .. " (slot 1 first). Slot 1 towers upgrade to level "
    .. CONFIG.TowerUpgrade.MaxLevel .. ". Run DebugSlots(), DebugUpgrades(), or DebugCharge().")
task.spawn(MainLoop)
