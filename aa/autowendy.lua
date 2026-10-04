-- Wendy ability timer GUI: manual fire buttons, cooldown display, press log

local UNIT_NAME = "wendy"      -- internal unit name in workspace._UNITS
local DEFAULT_COOLDOWN = 60    -- seconds; editable in the GUI
local INITIAL_GAP = 8          -- auto mode: seconds between unit 1 and unit 2 in the opening
local LOOP_AFTER_OPENING = true   -- true: keep looping after the opening; false: stop so the game's auto ability can take over
local AUTO_START = true           -- start Auto by itself whenever 4 Wendys are placed
local SETTLE = 0.5             -- auto mode: seconds to wait after a fire before checking buffs again

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

local unitsFolder = workspace:WaitForChild("_UNITS")
local remote = RS:WaitForChild("endpoints"):WaitForChild("client_to_server"):WaitForChild("use_active_attack")

-- parent the GUI somewhere safe
local guiParent
pcall(function() guiParent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not guiParent then guiParent = localPlayer:WaitForChild("PlayerGui") end
local old = guiParent:FindFirstChild("WendyTimerGui")
if old then old:Destroy() end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, r) new("UICorner", {CornerRadius = UDim.new(0, r or 6)}, o) end

local GREEN = Color3.fromRGB(80, 200, 120)
local ORANGE = Color3.fromRGB(240, 170, 60)
local RED = Color3.fromRGB(230, 80, 80)

----------------------------------------------------------------- UI
local gui = new("ScreenGui", {Name = "WendyTimerGui", ResetOnSpawn = false}, guiParent)
local main = new("Frame", {
    Size = UDim2.fromOffset(330, 470), Position = UDim2.fromOffset(20, 100),
    BackgroundColor3 = Color3.fromRGB(24, 24, 28), BorderSizePixel = 0,
}, gui)
corner(main, 8)

local title = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(36, 36, 42),
    BorderSizePixel = 0, Text = "  Wendy Timer", TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
}, main)
corner(title, 8)

local closeBtn = new("TextButton", {
    Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -30, 0, 4),
    BackgroundColor3 = RED, Text = "X", TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold, TextSize = 12, BorderSizePixel = 0,
}, main)
corner(closeBtn, 4)

-- dragging
do
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, main.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- cooldown setting
new("TextLabel", {
    Size = UDim2.fromOffset(120, 24), Position = UDim2.fromOffset(10, 36),
    BackgroundTransparency = 1, Text = "Fallback cd (s):", TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
}, main)
local cdBox = new("TextBox", {
    Size = UDim2.fromOffset(60, 24), Position = UDim2.fromOffset(130, 36),
    BackgroundColor3 = Color3.fromRGB(44, 44, 52), Text = tostring(DEFAULT_COOLDOWN),
    TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.Gotham, TextSize = 13,
    ClearTextOnFocus = false, BorderSizePixel = 0,
}, main)
corner(cdBox, 4)

local autoBtn = new("TextButton", {
    Size = UDim2.fromOffset(110, 24), Position = UDim2.fromOffset(210, 36),
    BackgroundColor3 = Color3.fromRGB(52, 52, 62), Text = "Auto: OFF", TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold, TextSize = 12, BorderSizePixel = 0,
}, main)
corner(autoBtn, 4)

-- unit list
local list = new("ScrollingFrame", {
    Size = UDim2.new(1, -20, 0, 160), Position = UDim2.fromOffset(10, 68),
    BackgroundColor3 = Color3.fromRGB(30, 30, 36), BorderSizePixel = 0,
    ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(), 
}, main)
corner(list)
new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)
new("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4)}, list)

-- control buttons
local function smallButton(text, x, w)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(w, 26), Position = UDim2.fromOffset(x, 236),
        BackgroundColor3 = Color3.fromRGB(52, 52, 62), Text = text, TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamMedium, TextSize = 12, BorderSizePixel = 0,
    }, main)
    corner(b, 4)
    return b
end
local roundBtn = smallButton("New round", 10, 100)
local clearBtn = smallButton("Clear log", 116, 90)
local copyBtn = smallButton("Copy log", 212, 108)

-- log
local logFrame = new("ScrollingFrame", {
    Size = UDim2.new(1, -20, 1, -278), Position = UDim2.fromOffset(10, 268),
    BackgroundColor3 = Color3.fromRGB(18, 18, 22), BorderSizePixel = 0,
    ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, main)
corner(logFrame)
new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, logFrame)
new("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 2)}, logFrame)

----------------------------------------------------------------- state
local alive = true
local cooldown = DEFAULT_COOLDOWN
local rows = {}          -- [unit] = row table
local counter = 0
local roundStart, lastPress
local logLines = {}
local logOrder = 0

cdBox.FocusLost:Connect(function()
    local n = tonumber(cdBox.Text)
    if n and n > 0 then cooldown = n else cdBox.Text = tostring(cooldown) end
end)

local function log(text)
    logOrder += 1
    table.insert(logLines, text)
    print("[Wendy] " .. text)
    new("TextLabel", {
        Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
        BackgroundTransparency = 1, Text = text,
        TextColor3 = Color3.fromRGB(210, 210, 220), Font = Enum.Font.Code, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = logOrder,
    }, logFrame)
    task.defer(function()
        logFrame.CanvasPosition = Vector2.new(0, logFrame.AbsoluteCanvasSize.Y)
    end)
end

-- buff helpers: damage_buff__magic is 1 when the buff is on
local function isOn(unit)
    local b = unit:FindFirstChild("_buffs")
    local v = b and b:FindFirstChild("damage_buff__magic")
    return v ~= nil and v.Value ~= 0
end

local function isStunned(unit)
    local s = false
    pcall(function() s = unit._stats.unit_stunned.Value ~= 0 end)
    return s
end

-- real cooldown from the unit (stored as a string); falls back to the box value
local function getCooldown(unit)
    local n
    pcall(function() n = tonumber(unit._stats.active_attack_cooldown.Value) end)
    return (n and n > 0) and n or cooldown
end

local function ordered()
    local t = {}
    for unit, row in pairs(rows) do table.insert(t, {unit = unit, row = row}) end
    table.sort(t, function(a, b) return a.row.index < b.row.index end)
    return t
end

local function buffString()
    local s = {}
    for _, e in ipairs(ordered()) do s[#s + 1] = isOn(e.unit) and "1" or "0" end
    return table.concat(s)
end

local function fire(unit, row)
    local now = os.clock()
    if not roundStart then roundStart = now end
    local sinceStart = now - roundStart
    local gap = lastPress and (now - lastPress) or 0
    local sameUnit = row.prev and string.format(" | same unit %.1fs", now - row.prev) or ""
    lastPress, row.prev, row.lastFired = now, now, now

    log(string.format("%s %s | +%.1fs | gap %.1fs%s | buffs %s | cd %.1f",
        os.date("%H:%M:%S"), row.name, sinceStart, gap, sameUnit, buffString(), getCooldown(unit)))

    task.spawn(function()
        local ok, err = pcall(function() remote:InvokeServer(unit) end)
        if not ok then log("ERROR firing " .. row.name .. ": " .. tostring(err)) end
    end)
end

-- true = Auto may start itself once 4 Wendys exist (re-armed whenever one is sold)
local autoArmed = AUTO_START

local function removeRow(unit)
    local row = rows[unit]
    if not row then return end
    rows[unit] = nil
    autoArmed = AUTO_START
    row.frame:Destroy()
    log(row.name .. " removed (sold)")
end

local function addRow(unit)
    -- reuse the lowest free number so a replacement keeps slots 1-4
    local used = {}
    for _, r in pairs(rows) do used[r.index] = true end
    counter = 1
    while used[counter] do counter += 1 end
    local row = {name = "Wendy " .. counter, index = counter}
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(40, 40, 48),
        BorderSizePixel = 0, LayoutOrder = counter,
    }, list)
    corner(f, 5)
    new("TextLabel", {
        Size = UDim2.fromOffset(90, 22), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1,
        Text = row.name, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
        TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    row.status = new("TextLabel", {
        Size = UDim2.fromOffset(100, 16), Position = UDim2.fromOffset(8, 22), BackgroundTransparency = 1,
        Text = "Ready", TextColor3 = GREEN, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    row.buff = new("TextLabel", {
        Size = UDim2.fromOffset(80, 16), Position = UDim2.fromOffset(105, 22), BackgroundTransparency = 1,
        Text = "Buff: OFF", TextColor3 = Color3.fromRGB(150, 150, 160), Font = Enum.Font.Gotham,
        TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    local btn = new("TextButton", {
        Size = UDim2.fromOffset(90, 28), Position = UDim2.new(1, -98, 0, 6),
        BackgroundColor3 = Color3.fromRGB(70, 110, 220), Text = "Fire", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold, TextSize = 13, BorderSizePixel = 0,
    }, f)
    corner(btn, 5)
    local barBg = new("Frame", {
        Size = UDim2.new(1, -16, 0, 3), Position = UDim2.new(0, 8, 1, -5),
        BackgroundColor3 = Color3.fromRGB(60, 60, 70), BorderSizePixel = 0,
    }, f)
    row.bar = new("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ORANGE, BorderSizePixel = 0}, barBg)
    row.frame = f
    btn.MouseButton1Click:Connect(function() fire(unit, row) end)
    rows[unit] = row
    unit.AncestryChanged:Connect(function()
        if not unit:IsDescendantOf(unitsFolder) then removeRow(unit) end
    end)
end

roundBtn.MouseButton1Click:Connect(function()
    roundStart, lastPress = nil, nil
    log("--- new round ---")
end)
clearBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(logFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    table.clear(logLines)
end)
copyBtn.MouseButton1Click:Connect(function()
    local text = table.concat(logLines, "\n")
    if setclipboard then
        setclipboard(text)
        print("[Wendy] Log copied to clipboard")
    else
        print("[Wendy] setclipboard not available; log:\n" .. text)
    end
end)
closeBtn.MouseButton1Click:Connect(function()
    alive = false
    gui:Destroy()
end)

----------------------------------------------------------------- auto mode
local autoOn = false
local autoToken = 0

local function setAutoVisual()
    autoBtn.Text = autoOn and "Auto: ON" or "Auto: OFF"
    autoBtn.BackgroundColor3 = autoOn and Color3.fromRGB(60, 150, 90) or Color3.fromRGB(52, 52, 62)
end

local function autoCore(token)
    local u = ordered()
    if #u < 4 then
        log("Auto: need 4 Wendys, found " .. #u)
        return
    end
    while #u > 4 do table.remove(u) end

    local function active()
        if not (alive and autoOn and token == autoToken) then return false end
        for _, e in ipairs(u) do
            if not e.unit.Parent then return false end
        end
        return true
    end
    -- true when every listed unit's buff is off
    local function off(...)
        for _, i in ipairs({...}) do
            if isOn(u[i].unit) then return false end
        end
        return true
    end
    local function waitUntil(cond)
        while active() and not cond() do task.wait(0.1) end
        return active()
    end
    local function go(i)
        if not waitUntil(function() return not isStunned(u[i].unit) end) then return false end
        fire(u[i].unit, u[i].row)
        task.wait(SETTLE)
        return active()
    end

    -- the opening needs a clean start: no buffs, nobody stunned, nothing on cooldown
    local function clean()
        for _, e in ipairs(u) do
            if isOn(e.unit) or isStunned(e.unit) then return false end
            if e.row.lastFired and (os.clock() - e.row.lastFired) < getCooldown(e.unit) then return false end
        end
        return true
    end
    if not clean() then log("Auto: waiting for a clean start (no buffs, cooldowns ready)") end
    if not waitUntil(clean) then return end

    roundStart, lastPress = nil, nil
    log("Auto: started")

    -- opening
    if not go(1) then return end
    task.wait(INITIAL_GAP)
    if not go(2) then return end
    if not (waitUntil(function() return off(2, 3, 4) end) and go(3)) then return end
    if not (waitUntil(function() return off(1) end) and go(4)) then return end

    if not LOOP_AFTER_OPENING then
        log("Auto: opening done - turn on the game's auto ability now")
        return "done"
    end

    -- steady state: fire unit i when its two neighbours in the ring are off
    local i = 1
    while active() do
        local prev, nxt = (i - 2) % 4 + 1, i % 4 + 1
        local unit, row = u[i].unit, u[i].row
        local readyAt, warned
        local reached = waitUntil(function()
            -- never fire before this unit's own cooldown is up
            if row.lastFired and (os.clock() - row.lastFired) < getCooldown(unit) then return false end
            readyAt = readyAt or os.clock()
            if not warned and os.clock() - readyAt > 15 then
                warned = true
                log(string.format("Auto: %s ready but buffs not clear (buffs %s)", row.name, buffString()))
            end
            return off(prev, nxt)
        end)
        if not (reached and go(i)) then break end
        i = nxt
    end
end

local function autoRun(token)
    local ok, res = pcall(autoCore, token)
    if not ok then log("Auto error: " .. tostring(res)) end
    if token == autoToken and autoOn then
        autoOn = false
        setAutoVisual()
        if ok and res ~= "done" then log("Auto: stopped (a Wendy was sold or an error occurred) - place it again, then turn Auto back on") end
    end
end

local function setAuto(on)
    autoToken += 1
    autoOn = on
    autoArmed = false   -- consumed; a sale re-arms it, and a manual OFF keeps it off
    setAutoVisual()
    if on then
        task.spawn(autoRun, autoToken)
    else
        log("Auto: stopped")
    end
end

autoBtn.MouseButton1Click:Connect(function() setAuto(not autoOn) end)

----------------------------------------------------------------- loops
-- find your Wendys / drop sold ones
task.spawn(function()
    while alive do
        for _, unit in ipairs(unitsFolder:GetChildren()) do
            if unit.Name == UNIT_NAME and not rows[unit] then
                local stats = unit:FindFirstChild("_stats")
                local owner = stats and stats:FindFirstChild("player")
                if owner and owner.Value == localPlayer then addRow(unit) end
            end
        end
        for unit in pairs(rows) do
            if not unit.Parent then removeRow(unit) end
        end

        local n = 0
        for _ in pairs(rows) do n += 1 end
        if autoArmed and not autoOn and n >= 4 then
            log("4 Wendys placed - starting Auto")
            setAuto(true)
        end
        task.wait(1)
    end
end)

-- cooldown display
task.spawn(function()
    while alive do
        local now = os.clock()
        for unit, row in pairs(rows) do
            local stunned = false
            pcall(function() stunned = unit._stats.unit_stunned.Value ~= 0 end)
            local cd = getCooldown(unit)
            local remaining = row.lastFired and (cd - (now - row.lastFired)) or 0
            if stunned then
                row.status.Text, row.status.TextColor3 = "Stunned", RED
            elseif remaining > 0 then
                row.status.Text, row.status.TextColor3 = string.format("%.1fs", remaining), ORANGE
            else
                row.status.Text, row.status.TextColor3 = "Ready", GREEN
            end
            row.bar.Size = UDim2.new(math.clamp(remaining / cd, 0, 1), 0, 1, 0)
            local on = isOn(unit)
            row.buff.Text = on and "Buff: ON" or "Buff: OFF"
            row.buff.TextColor3 = on and ORANGE or Color3.fromRGB(150, 150, 160)
        end
        task.wait(0.1)
    end
end)

print("[Wendy] GUI loaded")
