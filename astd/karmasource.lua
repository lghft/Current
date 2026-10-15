if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 1720936166 then return end
print("hi work pls")
-- Share one running instance across repeated executions in this session.
local sessionEnvironment = (getgenv and getgenv()) or shared
local sessionKey = "KarmaPandaASTD_FacilitySession"
local previousSession = sessionEnvironment[sessionKey]
if previousSession then
    if previousSession.Library then
        pcall(function() previousSession.Library:ToggleUI(true) end)
    end
    warn("[KarmaPanda] Already running or loading; duplicate execution stopped.")
    return
end

-- Reserve before any downloads/yields so simultaneous executions cannot race.
local currentSession = {Loading = true}
sessionEnvironment[sessionKey] = currentSession
local started, startupError = xpcall(function()
local benchmark_time = os.clock()

-- Helper Functions
local function Split(s, delimiter)
    local result = {}
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

local function StringToCFrame(input)
    return CFrame.new(unpack(game:GetService("HttpService"):JSONDecode("[" ..
                                                                           input ..
                                                                           "]")))
end

local function ShallowCopy(original)
    local copy = {}
    for key, value in pairs(original) do copy[key] = value end
    return copy
end

local function DeepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then v = DeepCopy(v) end
        copy[k] = v
    end
    return copy
end

local function TableLength(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function TableConcat(t1, t2)
    for i = 1, #t2 do t1[#t1 + 1] = t2[i] end
    return t1
end

local function get_keys(t)
    local keys = {}
    for key, _ in pairs(t) do table.insert(keys, key) end
    return keys
end

local postfixes = {
    ["n"] = 10 ^ (-6),
    ["m"] = 10 ^ (-3),
    ["k"] = 10 ^ 3,
    ["M"] = 10 ^ 6,
    ["G"] = 10 ^ 9
}

local function convert(n)
    local postfix = n:sub(-1)
    if postfixes[postfix] then
        return tonumber(n:sub(1, -2)) * postfixes[postfix]
    elseif tonumber(n) then
        return tonumber(n)
    else
        error("invalid postfix")
    end
end

local function CompareColor3(base, toCompare)
    local base_colors = {base.R, base.G, base.B}
    local comp_colors = {toCompare.R, toCompare.G, toCompare.B}
    local verdict = {}
    for index, col in ipairs(comp_colors) do
        if base_colors[index] == col then
            table.insert(verdict, true)
        else
            table.insert(verdict, false)
        end
    end
    if table.find(verdict, false) then
        return false
    else
        return true
    end
end

local version = "4.1"

local UpdateLogUrl = "https://raw.githubusercontent.com/Jeikaru/Roblox-1/refs/heads/main/updatelogs.txt"
local Settings
local Macros = {}

benchmark_time = os.clock()

-- Facility UI; existing ASTD settings and macro persistence remain authoritative.
local BASE = "https://raw.githubusercontent.com/FacilityHUB/UI-Facility/refs/heads/main/"
local source = game:HttpGet(BASE .. "main.luau")
local chunk, loadError = loadstring(source)
assert(chunk, "Facility failed to compile: " .. tostring(loadError))
local Library = chunk()
assert(type(Library) == "table", "Facility did not return a library")
currentSession.Library = Library
Library.BaseUrl = BASE
Library:SetToggleKey("K")
local Window = Library:Window({
    Title = string.format("KarmaPanda's ASTD | v%s", version),
    Suffix = " | Facility",
    Width = 760,
    Height = 640,
    TabStyle = "side",
    TabWidth = 155,
    MobileButton = true,
})

-- Startup automation already runs before InitializeUI. Restore toggle visuals
-- silently so Facility's default-true callback does not start duplicate loops.
local function AddToggle(section, options)
    local initial = options.Default == true
    options.Default = false
    local control = section:Toggle(options)
    control:Set(initial, true)
    if options.Flag then Library.Defaults[options.Flag] = initial end
    return control
end

print("[KarmaPanda] Facility Loaded: " .. os.clock() - benchmark_time)
benchmark_time = os.clock()

if not isfolder("KarmaPanda") then makefolder("KarmaPanda") end
if not isfolder("KarmaPanda\\ASTD") then makefolder("KarmaPanda\\ASTD") end
if not isfolder("KarmaPanda\\ASTD\\Settings") then
    makefolder("KarmaPanda\\ASTD\\Settings")
end

local SettingsFile = "KarmaPanda\\ASTD\\Settings\\" ..
                         game.Players.LocalPlayer.UserId .. ".json"

local InfiniteMapTable = {
    ["-1"] = "Regular [1]",
    ["-1.7"] = "Regular [2]",
    ["-1.1"] = "Category",
    ["-1.3"] = "Air",
    ["-1.8"] = "Solo",
    ["-1.9"] = "Random Unit",
    ["-1.5"] = "Double Path",
    ["-97"] = "Gauntlet",
    ["-98"] = "Training",
    ["-99"] = "Farm"
}

local AdventureMapTable = {}

-- Read loaded challenge cards without opening the mission chooser.
local function RefreshAdventureMaps()
    local parent = game:GetService("Players").LocalPlayer
    for _, name in ipairs({"PlayerGui", "HUD", "MissionsV2", "MissionChooser", "Main", "Challenges"}) do
        parent = parent and parent:FindFirstChild(name)
    end

    local detected = {}
    if parent then
        for _, child in ipairs(parent:GetChildren()) do
            if tonumber(child.Name) then
                local title = child:FindFirstChild("MissionTitle")
                if title and (title:IsA("TextLabel") or title:IsA("TextButton")) then
                    local name = title.Text:match("^%s*(.-)%s*$")
                    if name ~= "" then detected[child.Name] = name end
                end
            end
        end
    end

    local changed = false
    for id, name in pairs(detected) do
        if AdventureMapTable[id] ~= name then changed = true end
    end
    for id in pairs(AdventureMapTable) do
        if detected[id] == nil then changed = true end
    end
    if changed then
        table.clear(AdventureMapTable)
        for id, name in pairs(detected) do AdventureMapTable[id] = name end
    end
    return changed
end

RefreshAdventureMaps()

local function GetMapsFromTable(T)
    local maps = {}
    for _, v in pairs(T) do table.insert(maps, v) end
    return maps
end

local DefaultSettings = {
    version = version,
    auto_buff = true,
    auto_buff_units = {
        ["Erwin"] = {["Mode"] = "Box", ["Checks"] = {"attack"}, ["Ability Type"] = "Normal", ["Time"] = 13},
        ["Merlin"] = {["Mode"] = "Pair", ["Checks"] = {"range"}, ["Ability Type"] = "Normal", ["Time"] = 30},
        ["Brook6"] = {["Mode"] = "Box", ["Checks"] = {"attack", "range"}, ["Ability Type"] = "Normal", ["Time"] = 13},
        ["Kisuke6"] = {["Mode"] = "Pair", ["Checks"] = {"attack", "range"}, ["Ability Type"] = "Multiple", ["Ability Name"] = "Buff Ability", ["Time"] = 13},
        ["Rayleigh"] = {["Mode"] = "Box", ["Checks"] = {"attack"}, ["Ability Type"] = "Normal", ["Time"] = 13},
        ["Homura7"] = {["Mode"] = "Cycle", ["Checks"] = {}, ["Ability Type"] = "Normal", ["Cycle Units"] = 4, ["Time"] = 10, ["Delay"] = 1},
        ["Merlin6"] = {["Time"] = 13, ["Checks"] = {"attack", "range"}, ["Mode"] = "Box", ["Ability Type"] = "Normal"},
        ["Gojo7"] = {["Time"] = 9.5, ["Checks"] = {""}, ["Mode"] = "Box", ["Delay"] = 0, ["Ability Type"] = "Normal"},
        ["Metal Cooler"] = {["Time"] = 21, ["Checks"] = {""}, ["Mode"] = "Spam", ["Delay"] = 0.5, ["Ability Type"] = "Normal"},
        ["Satorou Gojou"] = {["Time"] = 10, ["Checks"] = {""}, ["Mode"] = "Box", ["Delay"] = 0, ["Ability Type"] = "Normal"},
        ["Welkin"] = {["Time"] = 15, ["Checks"] = {""}, ["Mode"] = "Spam", ["Delay"] = 0, ["Ability Type"] = "Normal"}
    },
    auto_vote_extreme = false,
    auto_2x = false,
    auto_3x = false,
    macro_profile = "Default Profile",
    macro_record = false,
    macro_playback = false,
    macro_record_time_offset = 0,
    macro_money_tracking = false,
    macro_playback_time_offset = 0,
    macro_magnitude = 1,
    macro_playback_search_attempts = 60,
    macro_playback_search_delay = 1,
    macro_summon = true,
    macro_sell = true,
    macro_upgrade = true,
    macro_ability = true,
    macro_auto_ability = true,
    macro_priority = true,
    macro_skipwave = true,
    macro_autoskipwave = true,
    macro_speedchange = true,
    macro_ability_blacklist = {
        "Erwin", "Merlin", "Brook6", "Kisuke6", "Rayleigh", "Merlin6", "Gojo7",
        "Hoshino", "Metal Cooler","Welkin","Homura7"
    },
    macro_timer_version = "Version 2",
    action_queue_remote_fire_delay = 0.25,
    action_queue_remote_on_fail = true,
    action_queue_remote_on_fail_delay = 1,
    action_queue_remote_on_fail_delay_loop = 0.5,
    auto_join_game = false,
    auto_join_tower = false,
    auto_join_delay = 5,
    auto_join_mode = "Infinite",
    auto_join_story_level = 1,
    auto_join_infinite_level = "-1.7",
    auto_join_trial_level = 1,
    auto_join_raid_level = 1,
    auto_join_challenge_level = 1,
    auto_join_bout_level = 1,
    auto_join_adventure_level = "-1133",
    auto_join_w3_level = 1,
    auto_evolve_exp = true,
    auto_skip_gui = true,
    webhook_url = "",
    webhook_discord_id = "",
    webhook_user_name = true,
    webhook_color = "FF8700",
    webhook_ping_user = false,
    webhook_end_game = false,
    webhook_exp_evolve = false,
    anti_afk = true,
    disable_3d_rendering = false,
    auto_execute = false,
    auto_battle = false,
    auto_battle_gems = 2700,
    fps_boost = false,
    auto_upgrade = false,
    auto_upgrade_money = 100,
    auto_upgrade_wave_stop = 100,
    auto_upgrade_sell = false,
    auto_upgrade_wave = 0,
    auto_upgrade_wave_sell = 100,
    anonymous_mode = true,
    anonymous_mode_name = "Anonymous"
}

if not pcall(function() readfile(SettingsFile) end) then
    writefile(SettingsFile, game:GetService("HttpService"):JSONEncode(DefaultSettings))
end

if not pcall(function()
    Settings = game:GetService("HttpService"):JSONDecode(readfile(SettingsFile))
end) then
    writefile(SettingsFile, game:GetService("HttpService"):JSONEncode(DefaultSettings))
    Settings = DefaultSettings
end

local IndividualMacroDefaultSettings = {
    ["Macro"] = {},
    ["Units"] = {},
    ["Map"] = {},
    ["Settings"] = {}
}

local MacroDefaultSettings = {
    ["Default Profile"] = DeepCopy(IndividualMacroDefaultSettings)
}

local folder_name = "KarmaPanda\\ASTD\\" .. game.Players.LocalPlayer.UserId

if not isfolder(folder_name) then makefolder(folder_name) end

if #listfiles(folder_name) == 0 then
    writefile(folder_name .. "\\" .. "Default Profile.json",
              game:GetService("HttpService"):JSONEncode(MacroDefaultSettings))
end

for _, file in pairs(listfiles(folder_name)) do
    if not pcall(function()
        local json_content = game:GetService("HttpService"):JSONDecode(readfile(file))
        for k, v in pairs(json_content) do
            if Macros[k] ~= nil then
                delfile(file)
            else
                Macros[k] = v
            end
        end
    end) then print("Error reading file: " .. file) end
end

if TableLength(Macros) == 0 then
    writefile(folder_name .. "\\" .. "Default Profile.json",
              game:GetService("HttpService"):JSONEncode(MacroDefaultSettings))
    Macros["Default Profile"] = DeepCopy(IndividualMacroDefaultSettings)
end

local MacroProfileList = {}
for i, _ in pairs(Macros) do table.insert(MacroProfileList, i) end

if Macros[Settings.macro_profile] == nil then
    Settings.macro_profile = MacroProfileList[#MacroProfileList]
end

-- Keep new loadout metadata readable and ahead of Map without changing legacy data.
local function EncodeMacroProfile(profileName, profile)
    local http = game:GetService("HttpService")
    if not profile["Equipped Units:"] then return http:JSONEncode({[profileName]=profile}) end
    local fields, included = {}, {}
    local function add(key)
        if profile[key] == nil then return end
        local encoded
        if key == "Equipped Units:" then
            local rows = {}
            for index=1,6 do
                local slot = "Slot" .. index
                if profile[key][slot] ~= nil then
                    table.insert(rows, "      " .. http:JSONEncode(slot) .. ": " .. http:JSONEncode(profile[key][slot]))
                end
            end
            encoded = "{\n" .. table.concat(rows, ",\n") .. "\n    }"
        else encoded = http:JSONEncode(profile[key]) end
        table.insert(fields, "    " .. http:JSONEncode(key) .. ": " .. encoded)
        included[key] = true
    end
    for _, key in ipairs({"Equipped Units:", "Map", "Macro", "Settings", "Units"}) do add(key) end
    for key in pairs(profile) do if not included[key] then add(key) end end
    return "{\n  " .. http:JSONEncode(profileName) .. ": {\n" .. table.concat(fields, ",\n") .. "\n  }\n}"
end

-- Read the first line as the update key; display only the plain text below it.
local function ShowUpdateLog()
    local fetched, source = pcall(function()
        return game:HttpGet(UpdateLogUrl)
    end)
    if not fetched or type(source) ~= "string" then
        warn("[KarmaPanda] Could not fetch update notes; will retry next run.")
        return
    end
    source = source:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local firstLine, notes = source:match("^([^\n]*)\n(.*)$")
    local updateKey = firstLine and firstLine:match("^%s*Key:%s*(.-)%s*$")
    if not updateKey or updateKey == "" or not notes or not notes:find("%S") then
        warn("[KarmaPanda] Update log requires Key:<update key> on the first line and notes below it.")
        return
    end
    if Settings.UpdateKey == updateKey then return end
    notes = notes:gsub("^\n+", ""):gsub("\n+$", "")

    local updateTab = Window:Tab("Update Log")
    local section = updateTab:Full("Update Log")
    local paragraph = section:Paragraph({Content = notes})
    paragraph.Title.Parent.Visible = false
    paragraph.Body.RichText = false
    Window:SetTab(updateTab)

    -- Remember the key silently after showing the notes and saving successfully.
    local updatedProfile = DeepCopy(Settings)
    updatedProfile.UpdateKey = updateKey
    local saved, saveError = pcall(function()
        writefile(SettingsFile, game:GetService("HttpService"):JSONEncode(updatedProfile))
    end)
    if saved then
        Settings.UpdateKey = updateKey
    else
        warn("[KarmaPanda] Could not save update key: " .. tostring(saveError))
    end
end

function Save()
    writefile(SettingsFile, game:GetService("HttpService"):JSONEncode(Settings))
    for profile_name, macro_table in pairs(Macros) do
        local save_data = {}
        save_data[profile_name] = macro_table
        writefile(folder_name .. "\\" .. profile_name .. ".json",
                  EncodeMacroProfile(profile_name, macro_table))
    end
end

for k, v in pairs(DefaultSettings) do
    if Settings[k] == nil then Settings[k] = v end
end

Settings.version = version
Save()
print("[KarmaPanda] Filesystem Loaded: " .. os.clock() - benchmark_time)
benchmark_time = os.clock()

-- Detect the server's saved story level; use it directly without an offset.
local StoryLevelControl
local function DetectStoryLevel()
    local ok, result = pcall(function()
        local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10)
        local server = remotes and remotes:WaitForChild("Server", 10)
        if not server then error("Story data remote is unavailable") end
        return server:InvokeServer("Data", "StoryLevel")
    end)

    local level = ok and tonumber(result) or nil
    if not level or level ~= level or level == math.huge or level < 1 or level % 1 ~= 0 then
        warn("[KarmaPanda] Could not detect a valid StoryLevel; keeping saved level. Result:", result)
        return false
    end

    Settings.auto_join_story_level = level
    Save()
    if StoryLevelControl then StoryLevelControl:Set(level, true) end
    print("[KarmaPanda] Detected and saved Story Level:", level)
    return true
end

DetectStoryLevel()
-- Game Helper Variables
local Player = game.Players.LocalPlayer
local GUI = Player.PlayerGui

-- Game Helper Functions
local function get_world()
    local worlds = {
        ["14657361824"] = -2,
        ["5552815761"] = -1,
        ["11574204578"] = 0,
        ["4996049426"] = 1,
        ["7785334488"] = 2
    }
    return worlds[tostring(game.PlaceId)]
end

local function get_game_speed()
    return game:GetService("ReplicatedStorage").SpeedUP.Value
end

local function Delay(time, condition)
    local timeElapsed = 0
    local updates = 0.1
    while timeElapsed < time do
        if not condition then break end
        timeElapsed = timeElapsed + (updates * get_game_speed())
        task.wait(updates)
    end
end

local function get_units()
    local units = {}
    local T = game:GetService("Workspace").Unit:GetChildren()
    for k, v in pairs(T) do
        if v:FindFirstChild("Owner") ~= nil and tostring(v.Owner.Value) == Player.Name then
            table.insert(units, v)
        end
    end
    return units
end

local CachedStats, OrbsV2Client, DataFolderClient

if get_world() ~= -1 and get_world() ~= -2 then
    CachedStats = require(Player.Backpack:WaitForChild("Framework"):WaitForChild("CachedStats"))
    OrbsV2Client = require(game:GetService("ReplicatedStorage"):WaitForChild("Framework"):WaitForChild("OrbsV2Client"))
    DataFolderClient = require(game.ReplicatedStorage.Framework.DataFolderClient)
end

local function get_all_storage_items()
    local items = {}
    if get_world() ~= -1 and get_world() ~= -2 then
        local storageItems = game:GetService("ReplicatedStorage").StorageItems
        for _, item in pairs(storageItems:GetChildren()) do
            if item.Name ~= "Disc" then
                table.insert(items, item.Name)
            end
        end
    end
    return items
end

local function get_all_units()
    local units = {}
    if get_world() ~= -1 and get_world() ~= -2 then
        for k, v in pairs(game:GetService("ReplicatedStorage").Unit:GetChildren()) do
            if v.Name ~= "PackageLink" then
                table.insert(units, v.Name)
            end
        end
    end
    return units
end

local function get_stat(unit_name) return CachedStats.getstat(unit_name) end

local function get_unit_from_gui(unit_name)
    local UnitGUI = GUI:FindFirstChild("HUD"):FindFirstChild("BottomFrame"):FindFirstChild("Unit")
    for _, v in pairs(UnitGUI:GetChildren()) do
        if v.ClassName == "Frame" then
            local u = v:FindFirstChild("Unit")
            if u.Value == unit_name then return v end
        end
    end
    return nil
end

local function get_summon_cost(unit_name)
    local cost = get_stat(unit_name)["Cost"]
    local discount = 0
    local unit = get_unit_from_gui(unit_name)
    if unit == nil then
        local orb = OrbsV2Client.GetAssignedOrbForUnit(unit_name)
        if orb ~= nil then
            local orb_stats = CachedStats.getOrbStat(orb)
            if orb_stats ~= nil then
                if orb_stats["InitialCost"] ~= nil then discount = orb_stats["InitialCost"] end
                if orb_stats["InitialPercentageCost"] ~= nil then cost = cost * orb_stats["InitialPercentageCost"] end
            end
        end
        return cost - discount
    else
        local image_label = unit:FindFirstChild("ImageLabel")
        if image_label ~= nil then
            local text_label = image_label:FindFirstChild("TextLabel")
            if text_label ~= nil then cost = convert(text_label.Text) end
        end
        return cost
    end
end

local function get_upgrade_cost(unit_name, level)
    local unit = get_stat(unit_name)
    if unit ~= nil then
        local upgrades = unit["Upgrade"]
        if upgrades[level] == nil then
            return 0
        else
            local cost = upgrades[level]["Cost"]
            local unit = get_unit_from_gui(unit_name)
            if unit ~= nil then
                local id = unit:FindFirstChild("ID")
                if id ~= nil then
                    local orb = OrbsV2Client.GetAssignedOrbForUnit(id.Value)
                    if orb ~= nil then
                        local orb_stats = CachedStats.getOrbStat(orb)
                        if orb_stats ~= nil then
                            if orb_stats["InitialPercentageCost"] ~= nil then
                                cost = cost * orb_stats["InitialPercentageCost"]
                            end
                        end
                    end
                end
            end
            return cost
        end
    else
        return 0
    end
end

local function get_max_upgrade_level(unit_name)
    return #get_stat(unit_name)["Upgrade"]
end

local function get_money() return Player:FindFirstChild("Money").Value end

local function get_wave()
    local WaveValue = game:GetService("ReplicatedStorage"):FindFirstChild("WaveValue")
    local wave = 0
    if WaveValue ~= nil then wave = WaveValue.Value end
    return wave
end

local function get_gems()
    if DataFolderClient ~= nil then return DataFolderClient.Get("Gems") else return nil end
end

local function get_gold()
    if DataFolderClient ~= nil then return DataFolderClient.Get("Gold") else return nil end
end

local function get_stardust()
    if DataFolderClient ~= nil then return DataFolderClient.Get("StardustStone") else return nil end
end

local function get_level()
    if DataFolderClient ~= nil then return DataFolderClient.Get("Level") else return nil end
end

local function get_battle_pass_tier()
    local bp_tier = "nil"
    pcall(function()
        bp_tier = GUI.TowerPassRewards.Main.Page.Main.Top.CurrentTierBox.Tier.Text
    end)
    return bp_tier
end

local function is_lobby()
    if get_world() ~= -1 and get_world() ~= -2 then
        return game.ReplicatedStorage:FindFirstChild("Lobby").Value
    else
        return nil
    end
end

local function get_number_missions()
    if get_world() ~= -1 and get_world() ~= -2 then
        return #game.ReplicatedStorage.Remotes.Server:InvokeServer("Mission")
    else
        return 204
    end
end

local function get_game_status()
    local status = GUI.HUD:WaitForChild("MissionEnd"):WaitForChild("BG")
                       :WaitForChild("Status"):WaitForChild("Status")
    return status.Text
end

local function get_world_teleporter()
    if 1 == get_world() then
        return game:GetService("Workspace").Queue["W2 PERM"].World2.Script115
    elseif 2 == get_world() then
        return game:GetService("Workspace").Script115
    end
end

local function CheckAttackBuff(Units)
    pcall(function()
        for _, v in pairs(Units) do
            local buffs = v:FindFirstChild("Head"):FindFirstChild("EffectBBGUI")
            if buffs ~= nil then
                local attack_buff = buffs:FindFirstChild("Frame"):FindFirstChild("AttackImage")
                if not attack_buff.Visible then return false end
            else
                return false
            end
        end
        return true
    end)
end

local function CheckRangeBuff(Units)
    for _, v in pairs(Units) do
        local buffs = v:FindFirstChild("Head"):FindFirstChild("EffectBBGUI")
        if buffs ~= nil then
            local range_buff = buffs:FindFirstChild("Frame"):FindFirstChild("RangeImage")
            if not range_buff.Visible then return false end
        else
            return false
        end
    end
    return true
end

local function CheckStun(unit)
    local buffs = unit:FindFirstChild("Head"):FindFirstChild("EffectBBGUI")
    if buffs ~= nil then
        local stun = buffs:FindFirstChild("Frame"):FindFirstChild("StunImage")
        if not stun.Visible then return false end
    else
        return false
    end
    return true
end

local function HideSummonGUI()
    while GUI:WaitForChild("HUD"):FindFirstChild("SUMMONGUI") ~= nil do
        local vim = game:GetService('VirtualInputManager')
        vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait()
        vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        task.wait(0.25)
    end
end

local StartTime = 30
local TimeOffset = 0

local function ElapsedTime()
    local wave = get_wave()
    if wave > 0 then
        if Settings.macro_timer_version == "Version 1" then
            return getrenv()["time"]() + TimeOffset
        elseif Settings.macro_timer_version == "Version 2" then
            return (getrenv()["time"]() - StartTime) + TimeOffset
        end
    end
    return 0
end

local function CalculateTimeOffset()
    task.spawn(function()
        repeat task.wait() until get_game_speed() ~= nil and get_wave() > 0
        StartTime = getrenv()["time"]()
        while true do
            if get_game_speed() > 1 then
                TimeOffset = TimeOffset + ((get_game_speed() - 1) * 0.015)
            end
            task.wait(0.015)
        end
    end)
end

local function SendWebhook(fields)
    local status, error_message = pcall(function()
        local request = request or http_request or (http and http.request) or syn.request
        local content = {}
        if Settings.webhook_user_name then
            table.insert(content, {["name"] = "Username", ["value"] = "||" .. Player.Name .. "||"})
        end
        content = TableConcat(content, fields)
        local ping_message = ""
        if Settings.webhook_discord_id ~= "" and Settings.webhook_ping_user then
            ping_message = "<@" .. Settings.webhook_discord_id .. ">"
        end
        request({
            Url = Settings.webhook_url,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode({
                ["content"] = ping_message,
                ["embeds"] = {{
                    ["author"] = {
                        ["name"] = "KarmaPanda",
                        ["url"] = "https://discord.gg/BrnQQGKbvE",
                        ["icon_url"] = "https://avatars.githubusercontent.com/u/10904093?v=4"
                    },
                    ["title"] = "All Star Tower Defense",
                    ["url"] = "https://www.roblox.com/games/4996049426/",
                    ["type"] = "rich",
                    ["color"] = tonumber(Settings.webhook_color, 16),
                    ["fields"] = content
                }}
            })
        })
    end)
    if not status then print("Webhook error:", error_message) end
end

-- Queue implementation
Queue = {}
function Queue.new() return {first = 0, last = -1} end
function Queue.pushleft(list, value) local first = list.first - 1; list.first = first; list[first] = value end
function Queue.pushright(list, value) local last = list.last + 1; list.last = last; list[last] = value end
function Queue.popleft(list)
    local first = list.first
    if first > list.last then error("list is empty") end
    local value = list[first]; list[first] = nil; list.first = first + 1; return value
end
function Queue.popright(list)
    local last = list.last
    if list.first > last then error("list is empty") end
    local value = list[last]; list[last] = nil; list.last = last - 1; return value
end
function Queue.length(list) return (list.last - list.first) + 1 end

local Action_Queue = Queue.new()
local Upgrade_Counter = 0

local function ActionQueueHelper()
    while task.wait() do
        if Queue.length(Action_Queue) > 0 then
            print("Actions in queue:", Queue.length(Action_Queue))
            local current = Queue.popleft(Action_Queue)
            local remote_method = current["Method"]
            local remote_args = current["Args"]
            print("Current Action", remote_method)
            for k, v in pairs(remote_args) do print(k, v) end
            if tostring(remote_method) == "Input" then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack(remote_args))
            end
            if tostring(remote_method) == "Server" then
                game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer(unpack(remote_args))
            end
            task.wait(Settings.action_queue_remote_fire_delay)
            if remote_args[1] == "Upgrade" then Upgrade_Counter = Upgrade_Counter - 1 end
        end
    end
end

local function StartActionQueue()
    local success, error_message = pcall(ActionQueueHelper)
    while not success do
        print("Error with action queue found: " .. error_message)
        success, error_message = pcall(ActionQueueHelper)
        task.wait()
    end
end

local function AddToQueue(remote_method, remote_args)
    Queue.pushright(Action_Queue, {["Method"] = remote_method, ["Args"] = remote_args})
end

local function SummonUnit(rotation, cframe, unit_name)
    local status, err = pcall(function()
        local function CheckUnitExist(unit)
            local owner = unit:FindFirstChild("Owner")
            local hrp = unit:FindFirstChild("HumanoidRootPart")
            if owner ~= nil and hrp ~= nil then
                local magnitude = (cframe.Position - hrp.CFrame.Position).magnitude
                if tostring(owner.Value) == Player.Name and unit.Name == unit_name and magnitude <= Settings.macro_magnitude then
                    return true
                end
            end
            return false
        end
        if type(cframe) == "string" then cframe = StringToCFrame(cframe) end
        if Settings.macro_money_tracking then
            repeat task.wait() until get_money() >= get_summon_cost(unit_name)
        end
        local summoned = false
        local connection = game:GetService("Workspace").Unit.ChildAdded:Connect(function(unit)
            if CheckUnitExist(unit) then summoned = true end
        end)
        AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input, {
            [1] = "Summon",
            [2] = {["Rotation"] = rotation, ["cframe"] = cframe, ["Unit"] = unit_name}
        })
        if Settings.action_queue_remote_on_fail then
            task.spawn(function()
                task.wait(Settings.action_queue_remote_on_fail_delay)
                while not summoned do
                    if Queue.length(Action_Queue) == 0 then
                        for _, unit in pairs(game:GetService("Workspace").Unit:GetChildren()) do
                            if CheckUnitExist(unit, cframe) then summoned = true; break end
                        end
                        if not summoned then
                            AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input, {
                                [1] = "Summon",
                                [2] = {["Rotation"] = rotation, ["cframe"] = cframe, ["Unit"] = unit_name}
                            })
                        end
                    end
                    task.wait(Settings.action_queue_remote_on_fail_delay_loop)
                end
                connection:Disconnect()
            end)
        else
            connection:Disconnect()
        end
    end)
    if not status then print("Error on Summon Unit: " .. err) end
end

local function UpgradeUnit(unit, upgrade_level)
    local status, err = pcall(function()
        local unit_upgrade_level = unit:FindFirstChild("UpgradeTag")
        local unit_max_upgrade_level = get_max_upgrade_level(unit.Name)
        local function UnitIsUpgraded()
            if unit_upgrade_level.Value >= upgrade_level or unit_upgrade_level.Value >= unit_max_upgrade_level then
                return true
            else
                return false
            end
        end
        local total_upgrade_cost = 0
        for i = unit_upgrade_level.Value + 1, upgrade_level do
            total_upgrade_cost = total_upgrade_cost + get_upgrade_cost(unit.Name, i)
        end
        repeat
            task.wait()
            print(string.format("Macro money tracking, current money %s. Upgrade cost %s.", get_money(), total_upgrade_cost))
            if UnitIsUpgraded() then return end
        until get_money() >= total_upgrade_cost
        local upgraded = false
        local connection = unit_upgrade_level:GetPropertyChangedSignal("Value"):Connect(function()
            if UnitIsUpgraded() then upgraded = true end
        end)
        for i = unit_upgrade_level.Value + 1, upgrade_level do
            game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Upgrade", unit)
        end
        task.spawn(function()
            task.wait(1)
            while not upgraded do
                if Queue.length(Action_Queue) == 0 then
                    if UnitIsUpgraded() then break end
                    if not upgraded then
                        game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Upgrade", unit)
                    end
                end
                task.wait(1)
            end
            connection:Disconnect()
        end)
    end)
    if not status then print("Error on Upgrade Unit: " .. err) end
end

local function UseAbilityUnit(unit, ability_string)
    task.spawn(function()
        local status, err = pcall(function()
            local special_move = unit:FindFirstChild("SpecialMove")
            local special_move_enabled = special_move:FindFirstChild("Special_Enabled2")
            repeat task.wait() until not CheckStun(unit) and not special_move_enabled.Value
            local ability_used = false
            local connection = special_move_enabled:GetPropertyChangedSignal("Value"):Connect(function()
                ability_used = true
            end)
            AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input, {
                [1] = "UseSpecialMove", [2] = unit, [3] = ability_string
            })
            if Settings.action_queue_remote_on_fail then
                task.spawn(function()
                    task.wait(Settings.action_queue_remote_on_fail_delay)
                    while not ability_used do
                        if Queue.length(Action_Queue) == 0 then
                            if special_move_enabled.Value then break end
                            if not ability_used then
                                AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input, {
                                    [1] = "UseSpecialMove", [2] = unit, [3] = ability_string
                                })
                            end
                        end
                        task.wait(Settings.action_queue_remote_on_fail_delay_loop)
                    end
                    connection:Disconnect()
                end)
            else
                connection:Disconnect()
            end
        end)
        if not status then print("Error on Use Unit Ability: " .. err) end
    end)
end

local function UseMultipleAbilitiesGUI(ability_name)
    task.spawn(function()
        local gui = GUI:WaitForChild("MultipleAbilities")
        for k, v in pairs(gui:WaitForChild("Frame"):GetChildren()) do
            if v.Name == "ImageButton" then
                local text = v:WaitForChild("TextLabel")
                if text.Text == ability_name then firesignal(v.Activated); break end
            end
        end
    end)
end

local function UseKilluaWishesGUI(ability_name)
    task.spawn(function()
        local gui = GUI:WaitForChild("KilluaWishes")
        local Options = gui:WaitForChild("TextBackground"):WaitForChild("OptionsContainer")
        for k, v in pairs(Options:GetChildren()) do
            if v.Name == "Option" then
                if v.Text == ability_name then
                    print("Attempting to activate!")
                    pcall(function() firesignal(v.MouseButton1Click) end)
                    gui:Destroy()
                    break
                end
            end
        end
    end)
end

local function UseMultipleAbilitiesUnit(unit, ability_string, ability_name)
    UseAbilityUnit(unit, ability_string)
    UseMultipleAbilitiesGUI(ability_name)
end

local function ActivateAutoAbilityUnit(unit, ability_string, toggled)
    AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input,
               {[1] = "AutoToggle", [2] = unit, [3] = toggled})
    UseAbilityUnit(unit, ability_string)
end

local function ChangePriorityUnit(unit)
    AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input,
               {[1] = "ChangePriority", [2] = unit})
end

local function SellUnit(unit)
    AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input,
               {[1] = "Sell", [2] = unit})
end

local function SkipWave(wave)
    task.spawn(function()
        repeat task.wait() until GUI.HUD.NextWaveVote.Visible
        while get_wave() == wave and GUI.HUD.NextWaveVote.Visible do
            AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input, {[1] = "VoteWaveConfirm"})
            task.wait(1)
        end
    end)
end

local function AutoSkipWaveToggle(wave, status)
    task.spawn(function()
        repeat task.wait() until get_wave() >= wave
        local CategoryName = GUI:WaitForChild("HUD"):WaitForChild("Setting")
                                 :WaitForChild("Page"):WaitForChild("Main")
                                 :WaitForChild("Scroll"):WaitForChild("SettingV2")
                                 :WaitForChild("AutoSkip"):WaitForChild("Options")
                                 :WaitForChild("Toggle"):WaitForChild("CategoryName")
        if CategoryName.Text ~= status then
            AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input, {[1] = "AutoSkipWaves_CHANGE"})
        end
    end)
end

local record_connections = {}

local function GetUnitIndex(unit)
    if Macros[Settings.macro_profile]["Units"][unit.Name] == nil then
        Macros[Settings.macro_profile]["Units"][unit.Name] = {}
    end
    local index = nil
    local exists = false
    for i, v in ipairs(Macros[Settings.macro_profile]["Units"][unit.Name]) do
        local hrp = unit:WaitForChild("HumanoidRootPart", 1)
        if hrp ~= nil then
            local magnitude = (StringToCFrame(v["Position"]).Position - hrp.CFrame.Position).magnitude
            if magnitude <= Settings.macro_magnitude then
                exists = true; index = i; break
            end
        end
    end
    if index == nil then
        local rotation = 0
        table.insert(Macros[Settings.macro_profile]["Units"][unit.Name], {
            ["Rotation"] = rotation,
            ["Position"] = tostring(unit.HumanoidRootPart.CFrame)
        })
        index = #Macros[Settings.macro_profile]["Units"][unit.Name]
    end
    return index
end

local function GetUnitByTargetInfo(Target)
    local unit_name = Target["Name"]
    local index = Target["Index"]
    local unit_info = Macros[Settings.macro_profile]["Units"][unit_name][index]
    local rotation = unit_info["Rotation"]
    local cframe = StringToCFrame(unit_info["Position"])
    local unit = nil
    for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
        local hrp = v:WaitForChild("HumanoidRootPart", 1)
        if hrp ~= nil then
            local magnitude = (cframe.Position - hrp.CFrame.Position).magnitude
            if magnitude <= Settings.macro_magnitude then unit = v; break end
        end
    end
    return unit, cframe, rotation
end

local function MacroRecordElapsedTime()
    return ElapsedTime() + Settings.macro_record_time_offset
end

local CurrentStep = nil

local function InsertToMacro(action)
    table.insert(Macros[Settings.macro_profile]["Macro"], action)
    Save()
    if CurrentStep ~= nil then
        CurrentStep = CurrentStep + 1
    else
        CurrentStep = 1
    end
end

local function HookUpgrade(unit, index)
    local upgrade_level = unit:WaitForChild("UpgradeTag", 60)
    if upgrade_level ~= nil then
        return upgrade_level:GetPropertyChangedSignal("Value"):Connect(function()
            if Settings.macro_record and Settings.macro_upgrade then
                InsertToMacro({
                    ["Time"] = MacroRecordElapsedTime(),
                    ["Target"] = {["Name"] = unit.Name, ["Index"] = index},
                    ["Remote"] = {[1] = "Upgrade", [2] = "Target"},
                    ["Parameter"] = {["Level"] = upgrade_level.Value}
                })
            end
        end)
    else
        return nil
    end
end

local function HookAbility(unit, index)
    local special_move = unit:WaitForChild("SpecialMove", 15)
    if special_move ~= nil then
        local ability_2 = special_move:WaitForChild("Special_Enabled2", 15)
        if ability_2 == nil then return nil end
        local ability_1 = special_move:WaitForChild("Special_Enabled", 1)
        local ability_string = ""
        if ability_1 ~= nil then
            local special_enabled_string = ability_1:WaitForChild("Special_Enabled_String", 1)
            if special_enabled_string ~= nil then ability_string = special_enabled_string.Value end
        end
        return ability_2.ChildAdded:Connect(function(c)
            local status, err = pcall(function()
                if special_move:GetAttribute("Auto") then return end
                if Settings.macro_record and Settings.macro_ability and
                    table.find(Settings.macro_ability_blacklist, unit.Name) == nil then
                    if c.Name == "SpecialStart" then
                        InsertToMacro({
                            ["Time"] = MacroRecordElapsedTime(),
                            ["Target"] = {["Name"] = unit.Name, ["Index"] = index},
                            ["Remote"] = {[1] = "UseSpecialMove", [2] = "Target", [3] = ability_string}
                        })
                    end
                end
            end)
            if not status then print("Error on use ability hook: " .. err) end
        end)
    end
    return nil
end

local function HookAutoAbility(unit, index)
    local special_move = unit:WaitForChild("SpecialMove", 15)
    if special_move ~= nil then
        local special_enabled = special_move:WaitForChild("Special_Enabled", 1)
        local ability_string = ""
        if special_enabled ~= nil then
            local special_enabled_string = special_enabled:WaitForChild("Special_Enabled_String", 1)
            if special_enabled_string ~= nil then ability_string = special_enabled_string.Value end
        end
        return special_move:GetAttributeChangedSignal("Auto"):Connect(function()
            if Settings.macro_record and Settings.macro_auto_ability then
                InsertToMacro({
                    ["Time"] = MacroRecordElapsedTime(),
                    ["Target"] = {["Name"] = unit.Name, ["Index"] = index},
                    ["Remote"] = {[1] = "AutoToggle", [2] = "Target", [3] = special_move:GetAttribute("Auto")},
                    ["Parameter"] = {["Ability String"] = ability_string}
                })
            end
        end)
    end
    return nil
end

local function HookNextWave()
    local HUD = GUI:WaitForChild("HUD", 15)
    if HUD ~= nil then
        local next_wave_gui = HUD:WaitForChild("NextWaveVote", 15)
        if next_wave_gui == nil then return nil end
        local yes_button = next_wave_gui:WaitForChild("YesButton", 15)
        if yes_button ~= nil then
            return yes_button.MouseButton1Click:Connect(function()
                if Settings.macro_record and Settings.macro_skipwave then
                    InsertToMacro({
                        ["Time"] = MacroRecordElapsedTime(),
                        ["Remote"] = {[1] = "VoteWaveConfirm"},
                        ["Parameter"] = {["Wave"] = get_wave()}
                    })
                end
            end)
        end
    end
    return nil
end

local function HookAutoSkipWave()
    local Toggle = GUI:WaitForChild("HUD"):WaitForChild("Setting"):WaitForChild("Page")
                       :WaitForChild("Main"):WaitForChild("Scroll"):WaitForChild("SettingV2")
                       :WaitForChild("AutoSkip"):WaitForChild("Options"):WaitForChild("Toggle")
    local CategoryName = Toggle:WaitForChild("CategoryName")
    local Button = Toggle:WaitForChild("TextButton")
    if Button ~= nil then
        return Button.MouseButton1Click:Connect(function()
            if Settings.macro_record and Settings.macro_autoskipwave then
                InsertToMacro({
                    ["Time"] = MacroRecordElapsedTime(),
                    ["Remote"] = {[1] = "AutoSkipWaves_CHANGE"},
                    ["Parameter"] = {["Wave"] = get_wave(), ["Status"] = CategoryName.Text}
                })
            end
        end)
    else
        return nil
    end
end

local function HookMultipleAbilitiesGUI()
    local function Hook(c)
        if c.Name == "MultipleAbilities" then
            local Frame = c:WaitForChild("Frame")
            repeat task.wait() until #Frame:GetChildren() > 1
            for k, v in pairs(Frame:GetChildren()) do
                if v.Name == "ImageButton" then
                    local connection = v.MouseButton1Click:Connect(function()
                        local text = v:WaitForChild("TextLabel")
                        if Settings.macro_record and Settings.macro_ability then
                            InsertToMacro({
                                ["Time"] = MacroRecordElapsedTime(),
                                ["Remote"] = {[1] = "MultipleAbilities"},
                                ["Parameter"] = {["Ability Name"] = text.Text}
                            })
                        end
                    end)
                end
            end
        end
        if c.Name == "KilluaWishes" then
            local Options = c:WaitForChild("TextBackground"):WaitForChild("OptionsContainer")
            for k, v in pairs(Options:GetChildren()) do
                if v.Name == "Option" then
                    local connection = v.MouseButton1Click:Connect(function()
                        if Settings.macro_record and Settings.macro_ability then
                            InsertToMacro({
                                ["Time"] = MacroRecordElapsedTime(),
                                ["Remote"] = {[1] = "KilluaWishes"},
                                ["Parameter"] = {["Ability Name"] = v.Text}
                            })
                        end
                    end)
                end
            end
        end
    end
    for _, v in pairs(GUI:GetChildren()) do Hook(v) end
    return GUI.ChildAdded:Connect(function(c) Hook(c) end)
end

local function HookSpeedChanges()
    return game:GetService("ReplicatedStorage"):WaitForChild("SpeedUP").Changed:Connect(function(v)
        if Settings.macro_record and Settings.macro_speedchange then
            InsertToMacro({
                ["Time"] = MacroRecordElapsedTime(),
                ["Remote"] = {[1] = "SpeedChange"},
                ["Parameter"] = {["Speed"] = v}
            })
        end
    end)
end

local function AddHooks(unit, index)
    table.insert(record_connections, HookUpgrade(unit, index))
    table.insert(record_connections, HookAbility(unit, index))
    table.insert(record_connections, HookAutoAbility(unit, index))
end

-- Priority hook via metatable
local game_metatable = getrawmetatable(game)
local namecall_original = game_metatable.__namecall
setreadonly(game_metatable, false)
game_metatable.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local Args = {...}
    if Settings.macro_record and Settings.macro_priority then
        if Args ~= nil and #Args > 1 and (method == "FireServer" or method == "InvokeServer") then
            if Args[1] == "ChangePriority" then
                task.spawn(function()
                    InsertToMacro({
                        ["Time"] = MacroRecordElapsedTime(),
                        ["Target"] = {["Name"] = Args[2].Name, ["Index"] = GetUnitIndex(Args[2])},
                        ["Remote"] = {[1] = "ChangePriority", [2] = "Target"}
                    })
                end)
            end
        end
    end
    return namecall_original(self, ...)
end)

-- Macro loadout metadata and explicit preparation; independent of playback.
local MacroLoadout = {Busy = false, Slots = {"One", "Two", "Three", "Four", "Five", "Six"}}

function MacroLoadout.Notify(message)
    Library:Notify({Title="Macro Loadout", Text=message, Duration=8, Icon="info"})
end

function MacroLoadout.Data(key)
    return game.ReplicatedStorage.Remotes.Server:InvokeServer("Data", key)
end

function MacroLoadout.Equipped()
    local data = MacroLoadout.Data("Unit_Equip")
    assert(type(data) == "table", "Could not read equipped units.")
    local slots = {}
    for _, unit in pairs(data) do
        if type(unit) == "table" and unit.Spot and unit.Name then slots[unit.Spot] = unit end
    end
    return slots
end

function MacroLoadout.GetCurrentMap()
    local folder = workspace:FindFirstChild("Don't Care")
    local children = folder and folder:GetChildren() or {}
    return children[1] and children[1].Name or "Unknown"
end

function MacroLoadout.Capture(profile)
    -- Only first recordings: never backfill metadata into a recorded legacy macro.
    if profile["Equipped Units:"] or next(profile.Macro or {}) or next(profile.Units or {}) then return end
    local entries, unknown = {}, {}
    profile.Map = type(profile.Map) == "table" and profile.Map or {}
    profile.Map.Name = MacroLoadout.GetCurrentMap()
    local ok, slots = pcall(MacroLoadout.Equipped)
    if not ok then
        Save()
        MacroLoadout.Notify("Recording will continue, but loadout capture failed: " .. tostring(slots))
        return
    end
    for index, spot in ipairs(MacroLoadout.Slots) do
        local unit = slots[spot]
        local entry = {Name=unit and unit.Name or "", Orb=""}
        if unit then
            -- The ID-based call is already used by this source's upgrade-cost helper.
            -- Missing data is unknown, not proof of an orb-free unit.
            local orb = unit.Orb
            if type(orb) ~= "string" or orb == "" then
                local found, value = pcall(function()
                    return OrbsV2Client.GetAssignedOrbForUnit(unit.ID)
                end)
                if found and type(value) == "string" and value ~= "" then orb = value end
            end
            if type(orb) == "string" and orb ~= "" then
                entry.Orb = orb
            else
                entry.OrbUnconfirmed = true
                table.insert(unknown, unit.Name)
            end
        end
        entries["Slot" .. index] = entry
    end
    profile["Equipped Units:"] = entries
    Save()
    if #unknown > 0 then
        MacroLoadout.Notify("Loadout saved. Review empty Orb fields for " .. table.concat(unknown, ", ")
            .. ". Set OrbUnconfirmed to false after confirming an empty orb.")
    end
end

function MacroLoadout.Status(color, text)
    MacroLoadout.Color = color
    if MacroLoadout.Button then
        MacroLoadout.Button.Instance.BackgroundColor3 = color
    end
    if MacroLoadout.Description then
        MacroLoadout.Description:Set({Content="Equip Current Macro Units and Orbs\n" .. text})
    end
end

function MacroLoadout.Wait(check)
    local deadline = os.clock() + 12
    repeat
        if check() then return end
        task.wait(0.5)
    until os.clock() >= deadline
    error("The game did not confirm the expected unit slots. Setup stopped.")
end

function MacroLoadout.Plan(profile)
    local saved = profile["Equipped Units:"]
    assert(type(saved) == "table", "This macro has no saved loadout.")
    local current = MacroLoadout.Equipped()
    local ok, inventory = pcall(MacroLoadout.Data, "Units")
    local inventoryKnown = ok and type(inventory) == "table"
    local candidates, seen = {}, {}
    local function add(unit)
        if type(unit) == "table" and type(unit.Name) == "string" and unit.ID ~= nil and not seen[unit.ID] then
            seen[unit.ID] = true
            table.insert(candidates, unit)
        end
    end
    for _, unit in pairs(current) do add(unit) end
    if inventoryKnown then for _, unit in pairs(inventory) do add(unit) end end
    local plan = {Rows={}, Issues={}, Rebuild=true, Current=current}
    local used, required = {}, 0
    for index, spot in ipairs(MacroLoadout.Slots) do
        local entry = saved["Slot" .. index]
        assert(type(entry) == "table" and type(entry.Name) == "string" and type(entry.Orb) == "string",
            "Invalid Slot" .. index .. ": use separate Name and Orb string fields.")
        local row = {Spot=spot, Name=entry.Name, Orb=entry.Orb, OrbUnconfirmed=entry.OrbUnconfirmed == true}
        if row.Name ~= "" then
            required = required + 1
            -- Prefer an already matching copy, then an owned inventory copy.
            local matching = current[spot]
            if matching and matching.Name == row.Name and not used[matching.ID] then row.Unit = matching end
            if not row.Unit then
                for _, unit in ipairs(candidates) do
                    if unit.Name == row.Name and not used[unit.ID] then row.Unit = unit; break end
                end
            end
            if row.Unit then
                used[row.Unit.ID] = true
                if not tonumber(row.Unit.Level) then
                    plan.Rebuild = false
                    table.insert(plan.Issues, "Could not read level for " .. row.Name)
                end
            else
                plan.Rebuild = false
                table.insert(plan.Issues, (inventoryKnown and "Unit not found: " or "Could not check unit availability: ") .. row.Name)
            end
            if row.Orb ~= "" then
                -- The inventory orb API's argument/return format is not established.
                -- Do not mislabel an unverified count as a missing orb.
                table.insert(plan.Issues, "Could not check orb availability: " .. row.Orb .. " (" .. row.Name .. ")")
            elseif row.OrbUnconfirmed then
                table.insert(plan.Issues, "Orb was not captured for " .. row.Name .. "; its orb will be left unchanged.")
            end
        end
        plan.Rows[index] = row
    end
    assert(required > 0, "This macro has no saved units to equip.")
    -- The known Equip request has no slot argument. Never compact an interior hole.
    local emptySeen = false
    for _, row in ipairs(plan.Rows) do
        if row.Name == "" then emptySeen = true
        elseif emptySeen then
            plan.Rebuild = false
            table.insert(plan.Issues, "This loadout contains an empty interior slot; automatic rebuilding cannot preserve it.")
            break
        end
    end
    return plan
end

function MacroLoadout.Execute(plan, profileName)
    local function guard()
        assert(Settings.macro_profile == profileName, "Selected macro changed. Setup stopped.")
        assert(not Settings.macro_record and not Settings.macro_playback, "Stop recording and playback before equipping a loadout.")
    end
    guard()
    MacroLoadout.Status(Color3.fromRGB(230,180,35), "Equipping units...")
    local input = game.ReplicatedStorage.Remotes.Input
    local server = game.ReplicatedStorage.Remotes.Server
    local function matches(slots)
        for _, row in ipairs(plan.Rows) do
            local unit = slots[row.Spot]
            if row.Name == "" then if unit then return false end
            elseif not unit or unit.Name ~= row.Name then return false end
        end
        return true
    end
    local slots = MacroLoadout.Equipped()
    if not matches(slots) and plan.Rebuild then
        for _, unit in pairs(slots) do
            guard()
            input:FireServer("Unequip", {Stats=unit.Name})
            task.wait(0.3)
        end
        MacroLoadout.Wait(function() guard(); return next(MacroLoadout.Equipped()) == nil end)
        for _, row in ipairs(plan.Rows) do
            if row.Name ~= "" then
                guard()
                local unit = row.Unit
                server:InvokeServer("Equip", {Stats=game.HttpService:JSONEncode({Name=unit.Name, ID=unit.ID, Level=unit.Level})})
                MacroLoadout.Wait(function()
                    guard()
                    local actual = MacroLoadout.Equipped()[row.Spot]
                    return actual and actual.Name == row.Name and actual.ID == unit.ID
                end)
            end
        end
        slots = MacroLoadout.Equipped()
        assert(matches(slots), "Final unit order check failed.")
    end
    local targets, partial = {}, not matches(slots)
    for _, row in ipairs(plan.Rows) do
        local unit = slots[row.Spot]
        if row.Name ~= "" and unit and unit.Name == row.Name then
            if row.Orb ~= "" or not row.OrbUnconfirmed then
                table.insert(targets, {ID=unit.ID, Name=unit.Name, Spot=row.Spot, Orb=row.Orb})
            else partial = true end
        end
    end
    local function checkTargets()
        guard()
        local actual = MacroLoadout.Equipped()
        for _, target in ipairs(targets) do
            local unit = actual[target.Spot]
            assert(unit and unit.ID == target.ID and unit.Name == target.Name, "Team changed during orb setup.")
        end
    end
    MacroLoadout.Status(Color3.fromRGB(230,180,35), "Sending orb requests...")
    for _, target in ipairs(targets) do
        checkTargets()
        input:FireServer("UnattuneOrb", target.ID)
        task.wait(0.5)
    end
    task.wait(1)
    for _, target in ipairs(targets) do
        if target.Orb ~= "" then
            checkTargets()
            input:FireServer("Orb", target.ID, target.Orb)
            task.wait(1)
        end
    end
    checkTargets()
    if partial then
        MacroLoadout.Status(Color3.fromRGB(210,65,65), "Partial setup: unresolved slots/orbs left unchanged. Orb requests were not verified.")
    else
        MacroLoadout.Status(Color3.fromRGB(65,180,100), "Finished: unit order checked; orb requests sent, not verified.")
    end
end

function MacroLoadout.Start()
    if MacroLoadout.Busy then return end
    if Settings.macro_record or Settings.macro_playback then
        MacroLoadout.Notify("Stop recording and playback before equipping a loadout."); return
    end
    MacroLoadout.Busy = true
    MacroLoadout.Button:SetEnabled(false)
    local profileName = Settings.macro_profile
    local function finish()
        MacroLoadout.Busy = false
        MacroLoadout.Button:SetEnabled(true)
    end
    MacroLoadout.Status(Color3.fromRGB(230,180,35), "Checking saved loadout and inventory...")
    local ok, plan = pcall(function() return MacroLoadout.Plan(Macros[profileName] or {}) end)
    if not ok then
        MacroLoadout.Status(Color3.fromRGB(210,65,65), tostring(plan))
        MacroLoadout.Notify(tostring(plan)); finish(); return
    end
    local function run()
        task.spawn(function()
            local success, message = pcall(MacroLoadout.Execute, plan, profileName)
            if not success then
                MacroLoadout.Status(Color3.fromRGB(210,65,65), tostring(message))
                MacroLoadout.Notify(tostring(message))
            end
            finish()
        end)
    end
    if #plan.Issues == 0 then run(); return end
    MacroLoadout.Status(Color3.fromRGB(210,65,65), "Missing items or availability checks need attention.")
    Window:Confirm({
        Title="Continue using this loadout?", Width=540, Height=390,
        Text=table.concat(plan.Issues, "\n")
            .. "\n\nMissing units or orbs mean the macro maker's results—and a 100% win rate—aren't guaranteed."
            .. "\n\nTo replace a missing unit, open the macro's JSON file in JSON Editor Online (jsoneditoronline.org) and change its saved unit name to the unit you want to use."
            .. (not plan.Rebuild and "\n\nContinue will preserve your current team and only send orb requests for units already in their required slots." or ""),
        Confirm="Continue Anyway", Cancel="Cancel", OnConfirm=run,
        OnCancel=finish, OnDismiss=finish,
    })
end

function MacroLoadout.BuildUI(section)
    MacroLoadout.Button = section:Button({Text="Equip Macro Loadout", Callback=MacroLoadout.Start})
    MacroLoadout.Description = section:Paragraph({Title="", Content="Equip Current Macro Units and Orbs"})
    local button = MacroLoadout.Button.Instance
    -- Facility hover changes the fill; keep the status color persistent.
    button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
        if MacroLoadout.Color and button.BackgroundColor3 ~= MacroLoadout.Color then
            button.BackgroundColor3 = MacroLoadout.Color
        end
    end)
end

function StartMacroRecord()
    if MacroLoadout.Busy then MacroLoadout.Notify("Wait for loadout setup to finish."); return end
    if Macros[Settings.macro_profile]["Macro"] == nil then Macros[Settings.macro_profile]["Macro"] = {} end
    if Macros[Settings.macro_profile]["Settings"] == nil then Macros[Settings.macro_profile]["Settings"] = {} end
    if Macros[Settings.macro_profile]["Map"] == nil then Macros[Settings.macro_profile]["Map"] = {} end
    if Macros[Settings.macro_profile]["Units"] == nil then Macros[Settings.macro_profile]["Units"] = {} end
    if is_lobby() then return end
    MacroLoadout.Capture(Macros[Settings.macro_profile])
    local Units = game:GetService("Workspace"):WaitForChild("Unit")
    for _, unit in pairs(get_units()) do AddHooks(unit, GetUnitIndex(unit)) end
    print("Hooked Units In Workspace...")
    task.spawn(function()
        table.insert(record_connections, Units.ChildAdded:Connect(function(unit)
            local owner = unit:WaitForChild("Owner")
            if tostring(owner.Value) == Player.Name then
                local index = GetUnitIndex(unit)
                if Settings.macro_record and Settings.macro_summon then
                    InsertToMacro({
                        ["Time"] = MacroRecordElapsedTime(),
                        ["Target"] = {["Name"] = unit.Name, ["Index"] = index},
                        ["Remote"] = {[1] = "Summon", [2] = "Target"}
                    })
                end
                AddHooks(unit, index)
            end
        end))
        print("Hooked Unit Summoning...")
    end)
    task.spawn(function()
        table.insert(record_connections, Units.ChildRemoved:Connect(function(unit)
            if Settings.macro_record and Settings.macro_sell then
                local owner = unit:WaitForChild("Owner")
                if tostring(owner.Value) == Player.Name then
                    local index = GetUnitIndex(unit)
                    InsertToMacro({
                        ["Time"] = MacroRecordElapsedTime(),
                        ["Target"] = {["Name"] = unit.Name, ["Index"] = index},
                        ["Remote"] = {[1] = "Sell", [2] = "Target"}
                    })
                    Save()
                end
            end
        end))
        print("Hooked Units Selling...")
    end)
    task.spawn(function() table.insert(record_connections, HookNextWave()); print("Hooked Next Wave...") end)
    task.spawn(function() table.insert(record_connections, HookMultipleAbilitiesGUI()); print("Hooked Multiple Abilities GUI...") end)
    task.spawn(function() table.insert(record_connections, HookAutoSkipWave()); print("Hooked Auto Skip Wave...") end)
    task.spawn(function() table.insert(record_connections, HookSpeedChanges()); print("Hooked Speed Changes...") end)
    Library:Notify({Title = "Macro Recording", Text = "Started Macro Recording...", Duration = 6.5, Icon = "info"})
end

function StopMacroRecord()
    for _, v in pairs(record_connections) do v:Disconnect() end
    record_connections = {}
    Library:Notify({Title = "Macro Recording", Text = "Stopped Macro Recording...", Duration = 6.5, Icon = "info"})
end

function StartMacroPlayback()
    if MacroLoadout.Busy then MacroLoadout.Notify("Wait for loadout setup to finish."); return end
    if is_lobby() then return end
    table.sort(Macros[Settings.macro_profile]["Macro"], function(a, b) return a["Time"] < b["Time"] end)
    CurrentStep, _ = next(Macros[Settings.macro_profile]["Macro"], CurrentStep)
    while CurrentStep do
        local Current = Macros[Settings.macro_profile]["Macro"][CurrentStep]
        repeat task.wait() until ElapsedTime() + Settings.macro_playback_time_offset >= Current["Time"] or not Settings.macro_playback
        if not Settings.macro_playback then break end
        local Remote = Current["Remote"]
        if Current["Target"] == nil then
            if Remote[1] == "VoteWaveConfirm" then
                SkipWave(Current["Parameter"]["Wave"])
            elseif Remote[1] == "AutoSkipWaves_CHANGE" then
                AutoSkipWaveToggle(Current["Parameter"]["Wave"], Current["Parameter"]["Status"])
            elseif Remote[1] == "MultipleAbilities" then
                UseMultipleAbilitiesGUI(Current["Parameter"]["Ability Name"])
            elseif Remote[1] == "KilluaWishes" then
                UseKilluaWishesGUI(Current["Parameter"]["Ability Name"])
            elseif Remote[1] == "SpeedChange" then
                ChangeSpeed(Current["Parameter"]["Speed"])
            else
                print(string.format("Macro error! Invalid target found for remote %s at step %s", Remote[1], CurrentStep))
            end
        else
            local unit, position, rotation = GetUnitByTargetInfo(Current["Target"])
            if unit == nil and position and rotation then
                if Remote[1] == "Summon" and Settings.macro_summon then
                    SummonUnit(rotation, position, Current["Target"]["Name"])
                else
                    local attempts = 0
                    repeat
                        task.wait(Settings.macro_playback_search_delay)
                        unit, position, rotation = GetUnitByTargetInfo(Current["Target"])
                        print(string.format("Macro is attempting to find the unit for %s.", Remote[1]))
                        attempts = attempts + 1
                    until unit ~= nil or attempts >= Settings.macro_playback_search_attempts or not Settings.macro_playback
                    if attempts >= Settings.macro_playback_search_attempts then
                        print(string.format("Macro skipped step %s for action %s, target %s, time %s.", CurrentStep, Remote[1], Current["Target"]["Name"], Current["Time"]))
                    end
                end
            end
            if unit ~= nil then
                if Remote[1] == "Upgrade" and Settings.macro_upgrade then
                    UpgradeUnit(unit, Current["Parameter"]["Level"])
                elseif Remote[1] == "UseSpecialMove" and Settings.macro_ability and table.find(Settings.macro_ability_blacklist, unit.Name) == nil then
                    UseAbilityUnit(unit, Remote[3])
                elseif Remote[1] == "AutoToggle" and Settings.macro_auto_ability then
                    ActivateAutoAbilityUnit(unit, Current["Parameter"]["Ability String"], Remote[3])
                elseif Remote[1] == "ChangePriority" and Settings.macro_priority then
                    ChangePriorityUnit(unit)
                elseif Remote[1] == "Sell" and Settings.macro_sell then
                    SellUnit(unit)
                elseif Remote[1] == "Summon" then
                    print("Macro attempting to summon a unit that already exists!")
                else
                    print("Macro error! Remote %s is not a valid for ASTD.")
                end
            elseif unit ~= nil and Remote[1] ~= "Summon" then
                print(string.format("Macro error! Cannot find unit for remote %s at step %s", Remote[1], CurrentStep))
            end
        end
        CurrentStep, _ = next(Macros[Settings.macro_profile]["Macro"], CurrentStep)
        task.wait()
    end
end

function StopMacroPlayback() if is_lobby() then return end end

function AutoVoteExtreme()
    repeat task.wait() until GUI.HUD.ModeVoteFrame.Visible
    repeat
        game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = "VoteGameMode", [2] = "Extreme"}))
        task.wait(1)
    until not GUI.HUD.ModeVoteFrame.Visible
end

function AutoBattle()
    repeat task.wait() until GUI.HUD.FastForward.Autoplay.Visible
    if get_gems() < Settings.auto_battle_gems then
        Settings.auto_battle = false
        Library:Notify({Title = "You have no gems to run Auto Battle!", Text = "Auto battle paused until you have more gems!", Duration = 6.5, Icon = "info"})
        return
    end
    if game.ReplicatedStorage:FindFirstChild("Autoplay") then
        if not game.ReplicatedStorage.Autoplay.Value then
            game.ReplicatedStorage.Remotes.Input:FireServer("BuyAutoBattle")
        end
    else
        game.ReplicatedStorage.Remotes.Input:FireServer("BuyAutoBattle")
        local success = game.ReplicatedStorage:WaitForChild("Autoplay", 5)
        if not success then warn("AutoBattle purchase failed — not enough gems?"); return end
    end
    print("AutoBattle is active!")
end

local function ManualUpgrade()
    if GUI.HUD.UpgradeV2.Actions.Upgrade.Visible then
        firesignal(GUI.HUD.UpgradeV2.Actions.Upgrade.MouseButton1Click)
    end
end

local function ManualSell()
    if GUI.HUD.UpgradeV2.Actions.Sell.Visible then
        firesignal(GUI.HUD.UpgradeV2.Actions.Sell.MouseButton1Click)
    end
end

game:GetService("UserInputService").InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.E then ManualUpgrade()
    elseif input.KeyCode == Enum.KeyCode.Q then ManualSell() end
end)

function ChangeSpeed(speed)
    task.spawn(function()
        while get_game_speed() ~= tonumber(speed) do
            local args = {[1] = "SpeedChange", [2] = true}
            if get_game_speed() < tonumber(speed) then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack(args))
            elseif get_game_speed() > tonumber(speed) then
                args[2] = false
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack(args))
            end
            task.wait(1)
        end
    end)
end

function AutoChangeSpeed()
    repeat task.wait(1) until get_game_speed() ~= nil
    while Settings.auto_2x or Settings.auto_3x do
        local args = {[1] = "SpeedChange", [2] = true}
        if (Settings.auto_3x and get_game_speed() < 3) or (Settings.auto_2x and get_game_speed() < 2) then
            game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack(args))
        elseif (Settings.auto_2x and get_game_speed() > 2) then
            args[2] = false
            game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack(args))
        end
        task.wait(1)
    end
end

function OnGameEnd()
    if not is_lobby() then
        local end_gui = GUI.HUD:WaitForChild("MissionEnd")
        repeat task.wait() until end_gui.Visible
        if Settings.webhook_end_game then
            local webhook_args = {}
            local bg = end_gui:FindFirstChild("BG")
            if bg ~= nil then
                if bg:FindFirstChild("Times") ~= nil then
                    local GameTimeElapsed = Split(Split(bg:FindFirstChild("Times").Text, '\n')[2], "seconds")[1]
                    local time_elapsed = tostring(math.round(tonumber(GameTimeElapsed)))
                    table.insert(webhook_args, {["name"] = "Game Time Elapsed", ["value"] = ":timer: " .. time_elapsed, ["inline"] = true})
                end
            end
            table.insert(webhook_args, {["name"] = "Macro Time Elapsed", ["value"] = ":timer: " .. tostring(math.round(ElapsedTime())), ["inline"] = true})
            table.insert(webhook_args, {["name"] = "Macro Time Elapsed (1x)", ["value"] = ":timer: " .. tostring(math.round(ElapsedTime() - TimeOffset)), ["inline"] = true})
            local GameStatus = get_game_status()
            local GameStatusEmoji = ""
            if GameStatus == "Success!" then GameStatusEmoji = ":green_square: "
            elseif GameStatus == "Failed!" then GameStatusEmoji = ":red_square: " end
            table.insert(webhook_args, {["name"] = "Status", ["value"] = GameStatusEmoji .. get_game_status(), ["inline"] = true})
            table.insert(webhook_args, {["name"] = "Waves", ["value"] = ":ocean: " .. get_wave(), ["inline"] = true})
            table.insert(webhook_args, {["name"] = "Current Level", ["value"] = ":star2: " .. get_level(), ["inline"] = true})
            table.insert(webhook_args, {["name"] = "Current Gems", ["value"] = ":gem: " .. get_gems(), ["inline"] = true})
            table.insert(webhook_args, {["name"] = "Current Gold", ["value"] = ":coin: " .. get_gold(), ["inline"] = true})
            table.insert(webhook_args, {["name"] = "Current Stardust", ["value"] = ":star: " .. get_stardust(), ["inline"] = true})
            table.insert(webhook_args, {["name"] = "Battle Pass Tier", ["value"] = ":signal_strength: " .. get_battle_pass_tier(), ["inline"] = true})
            SendWebhook(webhook_args)
        end
    end
end

function FpsBoost()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Jeikaru/Roblox/main/FpsBoost"))()
end

local linkport = ""
local linkport2 = ""

local function extractFileName(url)
    local nameWithParams = url:match("^.+/(.+)$")
    return nameWithParams:match("^[^?]+")
end

local function importMacro(url)
    local fileName = extractFileName(url)
    local savePath = folder_name .. "\\" .. fileName
    local success, response = pcall(function() return game:HttpGet(url) end)
    if success then
        writefile(savePath, response)
        local jsonData
        success, jsonData = pcall(function() return game:GetService("HttpService"):JSONDecode(response) end)
        if success then
            Library:Notify({Title = "Macro Imported!", Text = "Macro Import Success!", Duration = 4, Icon = "info"})
        else
            warn("Error parsing JSON: " .. jsonData)
        end
    else
        warn("Error downloading JSON: " .. response)
    end
end

local function importSettings(url)
    local fileName = extractFileName(url)
    local tempSavePath = "KarmaPanda\\ASTD\\Settings\\" .. fileName
    local success, response = pcall(function() return game:HttpGet(url) end)
    if success then
        writefile(tempSavePath, response)
        local success, jsonData = pcall(function() return game:GetService("HttpService"):JSONDecode(response) end)
        writefile(SettingsFile, response)
        delfile(tempSavePath)
        if success then
            Library:Notify({Title = "Settings Imported!", Text = "Settings Imported Rejoin to See the changes!", Duration = 4, Icon = "info"})
        else
            warn("Error parsing JSON: " .. jsonData)
        end
    else
        warn("Error downloading JSON: " .. response)
    end
end

function AutoReplay()
    local end_gui = GUI.HUD:WaitForChild("MissionEnd")
    repeat task.wait() until end_gui.Visible
    local replay_button = end_gui:WaitForChild("BG"):WaitForChild("Actions"):WaitForChild("Replay")
    local next_button = end_gui:WaitForChild("BG"):WaitForChild("Actions"):WaitForChild("Next")
    while Settings.auto_replay do
        if Settings.auto_next_story and next_button.Visible then break end
        if replay_button.Visible then firesignal(replay_button.Activated) end
        task.wait(1)
    end
end

function AutoNextStory()
    local end_gui = GUI.HUD:WaitForChild("MissionEnd")
    repeat task.wait() until end_gui.Visible
    local next_button = end_gui:WaitForChild("BG"):WaitForChild("Actions"):WaitForChild("Next")
    while Settings.auto_next_story do
        if next_button.Visible then firesignal(next_button.Activated) end
        task.wait(1)
    end
end

function AutoUpgrade()
    while true do
        while get_money() >= Settings.auto_upgrade_money and get_wave() >= Settings.auto_upgrade_wave
            and Settings.auto_upgrade and get_wave() < Settings.auto_upgrade_wave_stop do
            local units = get_units()
            for _, unit in ipairs(units) do
                local unit_name = unit.Name
                if get_current_upgrade_level(unit) < get_max_upgrade_level(unit_name) then
                    local args = {[1] = "Upgrade", [2] = unit}
                    game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer(unpack(args))
                    wait(0.1)
                end
            end
            wait(1)
        end
        if get_wave() >= Settings.auto_upgrade_wave_stop then
            warn("Auto-upgrade stopped at wave", Settings.auto_upgrade_wave_stop)
            Settings.auto_upgrade = false
            break
        end
        wait(1)
    end
end

function AutoSell()
    local function units()
        local unitNames = {}
        for _, child in ipairs(workspace:GetChildren()) do
            if child.Name == "Unit" then
                local childNames = {}
                for _, unitChild in ipairs(child:GetChildren()) do
                    table.insert(childNames, unitChild.Name)
                end
                unitNames["unit"] = childNames
            end
        end
        return unitNames
    end
    local function SellUnitLocal(unit)
        task.spawn(function()
            local has_sold = false
            local attempts = 0
            workspace.Unit.ChildRemoved:Connect(function(x)
                if unit == x then has_sold = true end
            end)
            repeat
                if not has_sold then
                    local args = {[1] = "Sell", [2] = unit}
                    game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack(args))
                    has_sold = true
                end
                attempts = attempts + 1
                task.wait(0.6)
            until has_sold or attempts >= 3
        end)
    end
    if get_wave() >= Settings.auto_upgrade_wave_sell then
        while Settings.auto_upgrade.auto_upgrade_sell do
            local unitList = units()["unit"]
            if unitList then
                for _, unitName in ipairs(unitList) do
                    local unit = workspace.Unit[unitName]
                    if unit then SellUnitLocal(unit); task.wait(0.6) end
                end
            else
                break
            end
            task.wait(1)
        end
    end
end

-- Auto-buff scheduling: independent group clocks and exact upgrade-stage filtering.
local BuffEngine = {Generation=0, MultipleBusy=false, IDs=setmetatable({}, {__mode="k"}), NextID=0}

function BuffEngine.Effect(unit, name)
    local head = unit:FindFirstChild("Head")
    local gui = head and head:FindFirstChild("EffectBBGUI")
    local frame = gui and gui:FindFirstChild("Frame")
    local icon = frame and frame:FindFirstChild(name)
    return icon ~= nil and icon.Visible == true
end

function BuffEngine.Matches(unit, name, config)
    local owner = unit:FindFirstChild("Owner")
    local move = unit:FindFirstChild("SpecialMove")
    local wanted = config["Special Move Name"] or ""
    return unit.Parent ~= nil and owner and tostring(owner.Value) == Player.Name
        and unit.Name == name and move and move.Value ~= ""
        and (wanted == "" or move.Value == wanted)
end

function BuffEngine.Units(name, config)
    local result = {}
    local folder = workspace:FindFirstChild("Unit")
    for _, unit in ipairs(folder and folder:GetChildren() or {}) do
        if BuffEngine.Matches(unit, name, config) then
            if not BuffEngine.IDs[unit] then
                BuffEngine.NextID = BuffEngine.NextID + 1
                BuffEngine.IDs[unit] = BuffEngine.NextID
            end
            table.insert(result, unit)
        end
    end
    table.sort(result, function(a,b) return BuffEngine.IDs[a] < BuffEngine.IDs[b] end)
    return result
end

function BuffEngine.Ready(unit, group, name, config)
    for _, member in ipairs(group) do
        if not BuffEngine.Matches(member, name, config) then return false end
    end
    local move = unit:FindFirstChild("SpecialMove")
    local cooldown = move and move:FindFirstChild("Special_Enabled2")
    if not cooldown or cooldown.Value or BuffEngine.Effect(unit, "StunImage") then return false end
    for _, check in ipairs(config.Checks or {}) do
        local effect = check == "attack" and "AttackImage" or check == "range" and "RangeImage"
        if effect then
            local all = true
            for _, member in ipairs(group) do
                if not BuffEngine.Effect(member, effect) then all = false; break end
            end
            if all then return false end
        end
    end
    return true
end

function BuffEngine.Size(config)
    if config.Mode == "Box" then return 4 end
    if config.Mode == "Pair" then return 2 end
    if config.Mode == "Cycle" then return math.clamp(math.floor(tonumber(config["Cycle Units"]) or 8),1,8) end
    return 1
end

function BuffEngine.Timing(config, index)
    local override = config.Mode == "Box" and type(config["Box Timings"]) == "table" and config["Box Timings"][index]
    local time = tonumber(override and override.Time) or tonumber(config.Time) or 15
    local delay = tonumber(override and override.Delay) or tonumber(config.Delay) or 0
    return math.max(0.1,time), math.max(0,delay)
end

function BuffEngine.Send(unit, group, name, config, valid)
    if not valid() or not BuffEngine.Ready(unit, group, name, config) then return false end
    local input = game.ReplicatedStorage.Remotes.Input
    -- Preserve the main source's default activation argument.
    -- Special Move Name is only a filter; it is never sent as this argument.
    local argument = ""
    if config["Ability Type"] ~= "Multiple" then
        input:FireServer("UseSpecialMove", unit, argument)
        return true
    end
    if BuffEngine.MultipleBusy then return false end
    local existing = GUI:FindFirstChild("MultipleAbilities")
    -- Do not select an option from another unit's already-open menu.
    if existing and existing.Enabled then return false end
    BuffEngine.MultipleBusy = true
    local success, sent = pcall(function()
        input:FireServer("UseSpecialMove", unit, argument)
        local deadline = os.clock() + 4
        repeat
            if not valid() or not BuffEngine.Matches(unit,name,config) then return false end
            local menu = GUI:FindFirstChild("MultipleAbilities")
            local frame = menu and menu:FindFirstChild("Frame")
            if menu and menu.Enabled and frame and frame.Visible then
                for _, button in ipairs(frame:GetChildren()) do
                    local label = button:FindFirstChild("TextLabel")
                    if button:IsA("GuiButton") and label and label.Text == config["Ability Name"] then
                        if valid() and BuffEngine.Matches(unit,name,config) then
                            firesignal(button.Activated)
                            return true
                        end
                    end
                end
            end
            task.wait(0.1)
        until os.clock() >= deadline
        return false
    end)
    BuffEngine.MultipleBusy = false
    if not success then warn("[Auto Buff] Multiple ability: " .. tostring(sent)) end
    return success and sent
end

function AutoBuff()
    BuffEngine.Generation = BuffEngine.Generation + 1
    local generation = BuffEngine.Generation
    local states = {}
    local clock, last = 0, os.clock()
    local function active() return Settings.auto_buff and generation == BuffEngine.Generation end
    while active() do
        local now = os.clock()
        local speed = game.ReplicatedStorage:FindFirstChild("SpeedUP")
        clock = clock + (now-last) * math.max(0,tonumber(speed and speed.Value) or 1)
        last = now
        local live = {}
        for name, config in pairs(Settings.auto_buff_units) do
            if type(config) == "table" then
                local units = BuffEngine.Units(name,config)
                local size = BuffEngine.Size(config)
                local fingerprint = game:GetService("HttpService"):JSONEncode(config)
                for index=1,math.floor(#units/size) do
                    local group, ids = {}, {}
                    for offset=1,size do
                        local unit = units[(index-1)*size+offset]
                        group[offset] = unit
                        ids[offset] = tostring(BuffEngine.IDs[unit])
                    end
                    local key = name .. ":" .. index
                    local signature = fingerprint .. ":" .. table.concat(ids,",")
                    live[key] = true
                    local state = states[key]
                    if not state or state.Signature ~= signature then
                        state = {Signature=signature, Cursor=1, Next=clock, Busy=false}
                        states[key] = state
                    end
                    if not state.Busy and clock >= state.Next then
                        local unit = group[state.Cursor]
                        local function valid()
                            return active() and states[key] == state
                                and Settings.auto_buff_units[name] == config
                                and game:GetService("HttpService"):JSONEncode(config) == fingerprint
                        end
                        if BuffEngine.Ready(unit,group,name,config) then
                            state.Busy = true
                            task.spawn(function()
                                local ok, sent = pcall(BuffEngine.Send,unit,group,name,config,valid)
                                if valid() then
                                    if ok and sent then
                                        local time, delay = BuffEngine.Timing(config,index)
                                        state.Cursor = state.Cursor % #group + 1
                                        state.Next = clock + time + (state.Cursor == 1 and delay or 0)
                                    else state.Next = clock + 0.5 end
                                end
                                state.Busy = false
                                if not ok then warn("[Auto Buff] " .. tostring(sent)) end
                            end)
                        end
                    end
                end
            end
        end
        for key in pairs(states) do if not live[key] then states[key] = nil end end
        task.wait(0.1)
    end
end


local isEvolvingEXP = false

function AutoEvolveEXP()
    local function GetInventory()
        return game.ReplicatedStorage.Remotes.Server:InvokeServer("Data", "Units")
    end
    local function CountEXP()
        local inventory = GetInventory()
        local exp1, exp2, exp3, exp4 = 0, 0, 0, 0
        for _, v in pairs(inventory) do
            if v.Name == "EXP IV" then exp4 = exp4 + 1 end
            if v.Name == "EXP III" then exp3 = exp3 + 1 end
            if v.Name == "EXP II" then exp2 = exp2 + 1 end
            if v.Name == "EXP I" then exp1 = exp1 + 1 end
        end
        return exp1, exp2, exp3, exp4
    end
    local function GetEXPUnitID(name)
        local inventory = GetInventory()
        for _, v in pairs(inventory) do if v.Name == name then return v.ID end end
        return nil
    end
    local function EvolveHelper(unit_name)
        local unit_id = GetEXPUnitID(unit_name)
        if unit_id ~= nil then
            local args = {[1] = "UpgradeUnit", [2] = unit_name, [3] = unit_id}
            game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack(args))
            task.wait(0.25)
        end
        return CountEXP()
    end
    local exp1, exp2, exp3, exp4 = CountEXP()
    if exp3 >= 3 or exp2 >= 3 or exp1 >= 2 then
        isEvolvingEXP = true
        while exp3 >= 3 or exp2 >= 3 or exp1 >= 2 do
            if exp3 >= 3 then exp1, exp2, exp3, exp4 = EvolveHelper("EXP III") end
            if exp2 >= 3 then exp1, exp2, exp3, exp4 = EvolveHelper("EXP II") end
            if exp3 >= 3 or exp2 >= 3 then isEvolvingEXP = true
            elseif exp1 >= 2 then exp1, exp2, exp3, exp4 = EvolveHelper("EXP I")
            else break end
        end
        if Settings.webhook_exp_evolve then
            SendWebhook({
                {["name"] = "EXP IV", ["value"] = exp4, ["inline"] = true},
                {["name"] = "EXP III", ["value"] = exp3, ["inline"] = true},
                {["name"] = "EXP II", ["value"] = exp2, ["inline"] = true},
                {["name"] = "EXP I", ["value"] = exp1, ["inline"] = true}
            })
        end
    end
    HideSummonGUI()
    isEvolvingEXP = false
end

function AutoTower()
    while MacroLoadout.Busy do task.wait(0.2) end
    local player = game:GetService("Players").LocalPlayer
    local towerteleporter = workspace.Queue.InteractionsV2:FindFirstChild("Script633")
    local function UseTeleporter(teleporter)
        if teleporter ~= nil then
            firetouchinterest(player.Character.HumanoidRootPart, teleporter, 0)
            task.wait()
            firetouchinterest(player.Character.HumanoidRootPart, teleporter, 1)
            task.wait(1)
        end
    end
    local function pressKey(keyCode)
        game:GetService("VirtualInputManager"):SendKeyEvent(true, keyCode, false, game)
        task.wait(0.1)
        game:GetService("VirtualInputManager"):SendKeyEvent(false, keyCode, false, game)
    end
    UseTeleporter(towerteleporter)
    if player.PlayerGui.HUD.TowerLevelSelector.StoryModeChooser.StoryModeChooser.Visible then
        pressKey(Enum.KeyCode.BackSlash); task.wait(0.5)
        pressKey(Enum.KeyCode.Right); task.wait(0.5)
        pressKey(Enum.KeyCode.Return); task.wait(0.5)
        pressKey(Enum.KeyCode.BackSlash)
        game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = towerteleporter.Name .. "Start"}))
    end
end

function AutoJoinGame()
    while MacroLoadout.Busy do task.wait(0.2) end
    if Settings.auto_join_mode == "Story" then DetectStoryLevel() end
    local function UseTeleporter(teleporter)
        if teleporter ~= nil then
            firetouchinterest(Player.Character.HumanoidRootPart, teleporter, 0)
            task.wait()
            firetouchinterest(Player.Character.HumanoidRootPart, teleporter, 1)
            task.wait(1)
        end
    end
    local function QuickStartTeleporter(teleporter)
        task.wait(1)
        Player.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").SpawnLocation.CFrame
        task.wait(1)
        if teleporter ~= nil then
            game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = teleporter.Name .. "Start"}))
        end
    end
    if Settings.auto_evolve_exp then
        repeat task.wait() until not isEvolvingEXP or not Settings.auto_evolve_exp
    end
    if not Settings.auto_join_game then return end
    task.wait(Settings.auto_join_delay)
    local teleporter = nil
    if get_world() == 1 then
        local function FindTeleporter(Teleporters)
            local Found = false
            while not Found do
                for _, v in pairs(Teleporters) do
                    if v.ClassName == "Part" and v.SurfaceGui.Frame.TextLabel.Text == "Empty" then
                        Found = true; return v
                    end
                end
                task.wait()
            end
            return nil
        end
        local function GetStoryTeleporters()
            local Teleporters = {}
            local TeleporterNames = {"Script170","Script158","Script395","Script408","Script523","Script539","Script573","Script600","Script624","Script958"}
            for _, v in pairs(game:GetService("Workspace").Queue.InteractionsV2:GetChildren()) do
                if table.find(TeleporterNames, v.Name) ~= nil then table.insert(Teleporters, v) end
            end
            return Teleporters
        end
        local function GetInfiniteTeleporters()
            local Teleporters = {}
            local TeleporterNames = {"Script209","Script222","Script381","Script405","Script448","Script58","Script647","Script716"}
            for _, v in pairs(game:GetService("Workspace").Queue.InteractionsV2:GetChildren()) do
                if table.find(TeleporterNames, v.Name) ~= nil then table.insert(Teleporters, v) end
            end
            return Teleporters
        end
        local function SetStoryMap(teleporter)
            if teleporter ~= nil then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = teleporter.Name .. "Level", [2] = tostring(Settings.auto_join_story_level), [3] = false}))
            end
        end
        local function SetInfiniteMap(teleporter)
            if teleporter ~= nil then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = teleporter.Name .. "Level", [2] = Settings.auto_join_infinite_level, [3] = false}))
            end
        end
        local function TeleportToWorld2() UseTeleporter(get_world_teleporter()) end
        if Settings.auto_join_mode == "Story" then
            if Settings.auto_join_story_level > 120 then TeleportToWorld2(); return end
            teleporter = FindTeleporter(GetStoryTeleporters())
            UseTeleporter(teleporter); SetStoryMap(teleporter)
        elseif Settings.auto_join_mode == "Infinite" then
            if InfiniteMapTable[Settings.auto_join_infinite_level] == "Gauntlet" or InfiniteMapTable[Settings.auto_join_infinite_level] == "Training" then
                TeleportToWorld2(); return
            end
            teleporter = FindTeleporter(GetInfiniteTeleporters())
            UseTeleporter(teleporter); SetInfiniteMap(teleporter)
        elseif Settings.auto_join_mode == "Adventure" then TeleportToWorld2(); return
        elseif Settings.auto_join_mode == "Time Chamber" then
            UseTeleporter(game:GetService("Workspace").Queue.Interactions.Script548)
        elseif Settings.auto_join_mode == "Team Event" then
            for _, v in pairs(game:GetService("Workspace").Queue:GetChildren()) do
                if v.Name == "Model" and v:FindFirstChild("PortalPart") ~= nil then
                    UseTeleporter(v:FindFirstChild("PortalPart")); break
                end
            end
        elseif Settings.auto_join_mode == "Bakugan Event" then
            UseTeleporter(game:GetService("Workspace").Queue.BakuganEventArea.Script412)
        end
        QuickStartTeleporter(teleporter)
    elseif get_world() == 2 then
        local function FindTeleporter(Teleporters, Mode)
            local Found = false
            while not Found do
                for _, v in pairs(Teleporters) do
                    if (Mode == nil or v.Name == Mode) and v.ClassName == "Part" and v.SurfaceGui.Frame.TextLabel.Text == "Empty" then
                        Found = true; return v
                    end
                end
                task.wait()
            end
            return nil
        end
        local function SetStoryMap(teleporter)
            if teleporter ~= nil then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = "StoryModeLevel", [2] = tostring(Settings.auto_join_story_level), [3] = true}))
            end
        end
        local function SetInfiniteMap(teleporter)
            if teleporter ~= nil then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = "InfiniteModeLevel", [2] = Settings.auto_join_infinite_level, [3] = false}))
            end
        end
        local function SetAdventureMap(teleporter)
            if teleporter ~= nil then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({[1] = "AdventureModeLevel", [2] = Settings.auto_join_adventure_level, [3] = false}))
            end
        end
        local function TeleportToWorld1() UseTeleporter(get_world_teleporter()) end
        local teleporter = nil
        if Settings.auto_join_mode == "Story" then
            if Settings.auto_join_story_level < 121 then TeleportToWorld1(); return end
            repeat task.wait() until #game:GetService("Workspace").Joinables:GetChildren() > 0
            teleporter = FindTeleporter(game:GetService("Workspace").Joinables:GetChildren(), "StoryMode")
            UseTeleporter(teleporter); SetStoryMap(teleporter)
        elseif Settings.auto_join_mode == "Infinite" then
            if InfiniteMapTable[Settings.auto_join_infinite_level] == "Farm" then TeleportToWorld1(); return end
            repeat task.wait() until #game:GetService("Workspace").Joinables:GetChildren() > 0
            teleporter = FindTeleporter(game:GetService("Workspace").Joinables:GetChildren(), "InfiniteMode")
            UseTeleporter(teleporter); SetInfiniteMap(teleporter)
        elseif Settings.auto_join_mode == "Adventure" then
            repeat task.wait() until #game:GetService("Workspace").Joinables:GetChildren() > 0
            teleporter = FindTeleporter(game:GetService("Workspace").Joinables:GetChildren(), "AdventureMode")
            UseTeleporter(teleporter); SetAdventureMap(teleporter)
        elseif Settings.auto_join_mode == "Time Chamber" then TeleportToWorld1(); return
        elseif Settings.auto_join_mode == "Team Event" then TeleportToWorld1(); return
        elseif Settings.auto_join_mode == "Bakugan Event" then TeleportToWorld1(); return
        end
        QuickStartTeleporter(teleporter)
    end
end

function AutoSkipGUI()
    local SummonGUI = GUI:WaitForChild("Summon")
    while Settings.auto_skip_gui do
        local status, err = pcall(function()
            if SummonGUI:FindFirstChild('Skip').Visible then
                game:GetService('VirtualUser'):ClickButton1(Vector2.new(
                    workspace.CurrentCamera.ViewportSize.X / 2,
                    workspace.CurrentCamera.ViewportSize.Y / 2))
            end
        end)
        if not status then print("Error on Auto Skip GUI: " .. err) end
        task.wait()
    end
end

local function AnonMode()
    local player = game.Players.LocalPlayer
    local userId = "p_" .. tostring(player.UserId)
    local success, err = pcall(function()
        local playerName = game:GetService("CoreGui").PlayerList.PlayerListMaster
                               .OffsetFrame.PlayerScrollList.SizeOffsetFrame
                               .ScrollingFrameContainer.ScrollingFrameClippingFrame
                               .ScollingFrame.OffsetUndoFrame[userId].ChildrenFrame
                               .NameFrame.BGFrame.OverlayFrame.PlayerName.PlayerName
        playerName.Text = Settings.anonymous_mode_name
    end)
    if not success then warn("Failed to change name in leaderboard: " .. err) end
    local nameLabel = game:GetService("Workspace").Camera:WaitForChild(Player.Name)
                          .Head:WaitForChild("NameLevelBBGUI"):WaitForChild("NameFrame")
                          :WaitForChild("TextLabel")
    nameLabel.Text = Settings.anonymous_mode_name
end

if get_world() ~= -1 and get_world() ~= -2 then
    repeat task.wait() until not GUI:WaitForChild("LoadingScreen").Frame.Visible
    if not is_lobby() then
        CalculateTimeOffset()
        task.spawn(StartActionQueue)
        if Settings.auto_buff then task.spawn(AutoBuff) end
        if Settings.auto_vote_extreme then task.spawn(AutoVoteExtreme) end
        if Settings.auto_2x or Settings.auto_3x then task.spawn(AutoChangeSpeed) end
        if Settings.auto_battle then task.spawn(AutoBattle) end
        if Settings.auto_replay then task.spawn(AutoReplay) end
        if Settings.auto_next_story then task.spawn(AutoNextStory) end
        if Settings.macro_record then task.spawn(StartMacroRecord) end
        if Settings.macro_playback then task.spawn(StartMacroPlayback) end
        if Settings.auto_upgrade then task.spawn(AutoUpgrade) end
        if Settings.auto_upgrade_sell then task.spawn(AutoSell) end
        task.spawn(OnGameEnd)
    else
        if Settings.auto_evolve_exp then task.spawn(AutoEvolveEXP) end
        task.wait(1)
        if Settings.auto_join_game then task.spawn(AutoJoinGame) end
        if Settings.auto_join_tower then task.spawn(AutoTower) end
    end
    if Settings.auto_skip_gui then task.spawn(AutoSkipGUI) end
    if Settings.FPSBoost then task.spawn(FpsBoost) end
    if Settings.anonymous_mode then task.spawn(AnonMode) end
end

if get_world() == -2 and Settings.auto_join_game then task.spawn(AutoJoinGame) end

task.spawn(function()
    if Settings.disable_3d_rendering then
        game:GetService("RunService"):Set3dRenderingEnabled(not Settings.disable_3d_rendering)
    end
    if Settings.anti_afk then
        for _, v in pairs(getconnections(game.Players.LocalPlayer.Idled)) do v:Disable() end
    end
end)

print("[KarmaPanda] Functions Loaded: " .. os.clock() - benchmark_time)
benchmark_time = os.clock()

local function CreateHideButtonGUI()
    Library:SetMobileButtonVisible(true)
end

local function CreateMiniGUI()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Parent = GUI
    local MiniFrame = Instance.new("Frame")
    MiniFrame.Size = UDim2.new(0, 150, 0, 30)
    MiniFrame.Position = UDim2.new(1, -150, 0, 0)
    MiniFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    MiniFrame.BorderSizePixel = 0
    MiniFrame.Active = true
    MiniFrame.Draggable = true
    MiniFrame.Parent = ScreenGui
    local miniLabel = Instance.new("TextLabel")
    miniLabel.Size = UDim2.new(1, 0, 1, 0)
    miniLabel.Position = UDim2.new(0, 0, 0, 0)
    miniLabel.BackgroundTransparency = 1
    miniLabel.Text = "Playback UI"
    miniLabel.Font = Enum.Font.SourceSansBold
    miniLabel.TextSize = 18
    miniLabel.TextColor3 = Color3.new(1, 1, 1)
    miniLabel.Parent = MiniFrame
    local miniArrowButton = Instance.new("TextButton")
    miniArrowButton.Size = UDim2.new(0, 20, 0, 20)
    miniArrowButton.Position = UDim2.new(1, -25, 0, 5)
    miniArrowButton.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    miniArrowButton.Text = "v"
    miniArrowButton.Font = Enum.Font.SourceSans
    miniArrowButton.TextSize = 14
    miniArrowButton.TextColor3 = Color3.new(1, 1, 1)
    miniArrowButton.Parent = MiniFrame
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, 150, 0, 150)
    Frame.Position = UDim2.new(0, 0, 1, 0)
    Frame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    Frame.BorderSizePixel = 0
    Frame.Active = true
    Frame.Visible = false
    Frame.Parent = MiniFrame
    local borderThickness = 6
    local function createBorder(parent, color, size, position)
        local border = Instance.new("Frame")
        border.Size = size; border.Position = position
        border.BackgroundColor3 = color; border.BorderSizePixel = 0; border.Parent = parent
    end
    createBorder(Frame, Color3.fromRGB(55,55,55), UDim2.new(1,0,0,borderThickness), UDim2.new(0,0,0,0))
    createBorder(Frame, Color3.fromRGB(55,55,55), UDim2.new(1,0,0,borderThickness), UDim2.new(0,0,1,-borderThickness))
    createBorder(Frame, Color3.fromRGB(55,55,55), UDim2.new(0,borderThickness,1,0), UDim2.new(0,0,0,0))
    createBorder(Frame, Color3.fromRGB(55,55,55), UDim2.new(0,borderThickness,1,0), UDim2.new(1,-borderThickness,0,0))
    local timerLabel = Instance.new("TextLabel")
    timerLabel.Size = UDim2.new(1, -borderThickness*2, 0, 20)
    timerLabel.Position = UDim2.new(0, borderThickness, 0, borderThickness)
    timerLabel.BackgroundTransparency = 1; timerLabel.Text = "Game Time: nil"
    timerLabel.Font = Enum.Font.SourceSans; timerLabel.TextSize = 14
    timerLabel.TextColor3 = Color3.new(1,1,1); timerLabel.Parent = Frame
    local playbackLabel = Instance.new("TextLabel")
    playbackLabel.Size = UDim2.new(1, -borderThickness*2, 1, -borderThickness*3-20)
    playbackLabel.Position = UDim2.new(0, borderThickness, 0, borderThickness*2+20)
    playbackLabel.BackgroundTransparency = 1; playbackLabel.Text = "Loading..."
    playbackLabel.Font = Enum.Font.SourceSans; playbackLabel.TextSize = 14
    playbackLabel.TextColor3 = Color3.new(1,1,1); playbackLabel.TextWrapped = true
    playbackLabel.TextYAlignment = Enum.TextYAlignment.Top; playbackLabel.Parent = Frame
    local isOpen = false
    local function toggleGUI()
        isOpen = not isOpen; Frame.Visible = isOpen
        miniArrowButton.Text = isOpen and "^" or "v"
    end
    miniArrowButton.MouseButton1Click:Connect(toggleGUI)
    local lastUpdateTime = 0
    local updateInterval = 0.5
    local function Update()
        if not isOpen then return end
        local currentTime = tick()
        if currentTime - lastUpdateTime >= updateInterval then
            local elapsed = ElapsedTime()
            local mins = math.floor(elapsed / 60)
            local secs = elapsed % 60
            timerLabel.Text = string.format("Game Time: %d:%02d", mins, secs)
            if CurrentStep ~= nil then
                local MacroCurrentStep = Macros[Settings.macro_profile]["Macro"][CurrentStep]
                if MacroCurrentStep then
                    local Target = MacroCurrentStep["Target"]
                    local TargetName = Target and Target["Name"] or "Unknown"
                    local TargetIndex = Target and Target["Index"] or "N/A"
                    local Time = MacroCurrentStep["Time"] or "N/A"
                    local Remote = MacroCurrentStep["Remote"] and MacroCurrentStep["Remote"][1] or "N/A"
                    local Parameters = MacroCurrentStep["Parameter"]
                    local parameterString = ""
                    if Parameters then
                        for k, v in pairs(Parameters) do
                            parameterString = parameterString .. tostring(k) .. ": " .. tostring(v) .. "; "
                        end
                    end
                    playbackLabel.Text = string.format(
                        "Current Step: %s\nTarget: %s[%s]\nTime: %s\nAction: %s\nParameters: %s",
                        tostring(CurrentStep), tostring(TargetName), tostring(TargetIndex),
                        tostring(Time), tostring(Remote), tostring(parameterString))
                end
            end
            lastUpdateTime = currentTime
        end
    end
    if Settings.macro_playback then
        game:GetService("RunService").Heartbeat:Connect(Update)
    end
end

-- ============================================================
-- UI: Facility native tabs, sections, and controls.
function InitializeUI()
    local UnitList = get_all_units()

    local function MainSettings()
        local Main = Window:Tab("Main")
        local MainSection
        MainSection = Main:Section("Gameplay Scripts", 1)
        local AutoBuffToggle = AddToggle(MainSection, {
            Text = "Auto Unit Buffing",
            Default = Settings.auto_buff,
            Flag = "auto_buff",
            Callback = function(value)
                Settings.auto_buff = value; Save()
                if not value then BuffEngine.Generation = BuffEngine.Generation + 1 end
                if not is_lobby() and value then AutoBuff() end
            end
        })
        local AutoUpgradeToggle = AddToggle(MainSection, {
            Text = "Auto Upgrade",
            Default = Settings.auto_upgrade,
            Flag = "auto_upgrade",
            Callback = function(value)
                Settings.auto_upgrade = value; Save()
                if not is_lobby() and value then AutoUpgrade() end
            end
        })
        local AutoSellToggle = AddToggle(MainSection, {
            Text = "Auto Sell",
            Default = Settings.auto_upgrade_sell,
            Flag = "auto_upgrade_sell",
            Callback = function(value)
                Settings.auto_upgrade_sell = value; Save()
                if not is_lobby() and value then AutoSell() end
            end
        })
        MainSection = Main:Section("GUI Scripts", 2)
        local AutoVoteExtremeToggle = AddToggle(MainSection, {
            Text = "Auto Vote Extreme Mode",
            Default = Settings.auto_vote_extreme,
            Flag = "auto_vote_extreme",
            Callback = function(value)
                Settings.auto_vote_extreme = value; Save()
                if not is_lobby() and value then AutoVoteExtreme() end
            end
        })
        local Auto2XToggle = AddToggle(MainSection, {
            Text = "Auto 2x Speedup",
            Default = Settings.auto_2x,
            Flag = "auto_2x",
            Callback = function(value)
                Settings.auto_2x = value; Save()
                if not is_lobby() and value then AutoChangeSpeed() end
            end
        })
        local Auto3XToggle = AddToggle(MainSection, {
            Text = "Auto 3x Speedup",
            Default = Settings.auto_3x,
            Flag = "auto_3x",
            Callback = function(value)
                Settings.auto_3x = value; Save()
                if not is_lobby() and value then AutoChangeSpeed() end
            end
        })
        local AutoBattleToggle = AddToggle(MainSection, {
            Text = "Auto Battle",
            Default = Settings.auto_battle,
            Flag = "auto_battle",
            Callback = function(value)
                Settings.auto_battle = value; Save()
                if not is_lobby() and value then AutoBattle() end
            end
        })
        MainSection = Main:Section("Game End Scripts", 1)
        local AutoReplayToggle = AddToggle(MainSection, {
            Text = "Auto Replay",
            Default = Settings.auto_replay,
            Flag = "auto_replay",
            Callback = function(value)
                Settings.auto_replay = value; Save()
                if not is_lobby() and value then AutoReplay() end
            end
        })
        local AutoNextStoryToggle = AddToggle(MainSection, {
            Text = "Auto Next Story",
            Default = Settings.auto_next_story,
            Flag = "auto_next_story",
            Callback = function(value)
                Settings.auto_next_story = value; Save()
                if not is_lobby() and value then AutoNextStory() end
            end
        })
        local function AutomationSettings()
            MainSection = Main:Section("Automation", 2)
            MainSection:Paragraph({
                Title = "Automation",
                Content = "Automatically upgrades/sells units and turns on autobattle."
            })
            MainSection:Input({Text = "Auto Battle Gems", Placeholder = tostring(Settings.auto_battle_gems), Flag = "auto_battle_gems", Callback = function(text) Settings.auto_battle_gems = text; Save() end})
            MainSection:Input({Text = "Auto Upgrade Money", Placeholder = tostring(Settings.auto_upgrade_money), Flag = "auto_upgrade_money", Callback = function(text) Settings.auto_upgrade_money = text; Save() end})
            MainSection:Input({Text = "Auto Upgrade Wave", Placeholder = tostring(Settings.auto_upgrade_wave), Flag = "auto_upgrade_wave", Callback = function(text) Settings.auto_upgrade_wave = text; Save() end})
            MainSection:Input({Text = "Stop Auto Upgrade At Wave", Placeholder = tostring(Settings.auto_upgrade_wave_stop), Flag = "auto_upgrade_wave_stop", Callback = function(text) Settings.auto_upgrade_wave_stop = text; Save() end})
            MainSection:Input({Text = "Auto Sell At Wave", Placeholder = tostring(Settings.auto_upgrade_wave_sell), Flag = "auto_upgrade_wave_sell", Callback = function(text) Settings.auto_upgrade_wave_sell = text; Save() end})
        end

        AutomationSettings()
    end

    local function MacroSettings()
        local Macro = Window:Tab("Macro")
        local MacroSection
        MacroSection = Macro:Section("Macros", 1)

        local MacroProfileDropdown = MacroSection:Dropdown({
            Text = "Selected Profile",
            Options = MacroProfileList,
            Default = Settings.macro_profile,
            Multi = false,
            Flag = "macro_profile_dd",
            Callback = function(options)
                local value = options
                Settings.macro_profile = value
                if Macros[Settings.macro_profile] == nil then Macros[Settings.macro_profile] = {} end
                Save()
            end
        })

        MacroLoadout.BuildUI(MacroSection)

        local MacroProfileInfo = MacroSection:Paragraph({
            Title = "Current Profile Info",
            Content = "Waiting for information...\n"
        })
        task.spawn(function()
            while MacroProfileInfo ~= nil do
                if Macros[Settings.macro_profile]["Macro"] ~= nil and Macros[Settings.macro_profile]["Units"] ~= nil then
                    MacroProfileInfo:Set({
                        Title = "Current Profile Info",
                        Content = string.format("Total Steps: %s\nUnits: %s",
                            tostring(#Macros[Settings.macro_profile]["Macro"]),
                            table.concat(get_keys(Macros[Settings.macro_profile]["Units"]), ", "))
                    })
                end
                task.wait()
            end
        end)

        MacroSection = Macro:Section("Controls", 2)
        local RecordMacroToggle
        RecordMacroToggle = AddToggle(MacroSection, {
            Text = "Record Macro",
            Default = Settings.macro_record,
            Flag = "macro_record",
            Callback = function(value)
                if MacroLoadout.Busy then
                    if RecordMacroToggle then RecordMacroToggle:Set(Settings.macro_record, true) end
                    MacroLoadout.Notify("Wait for loadout setup to finish before recording.")
                    return
                end
                Settings.macro_record = value; Save()
                if not is_lobby() then
                    if value then StartMacroRecord() else StopMacroRecord() end
                end
            end
        })
        local PlaybackMacroToggle
        PlaybackMacroToggle = AddToggle(MacroSection, {
            Text = "Playback Macro",
            Default = Settings.macro_playback,
            Flag = "macro_playback",
            Callback = function(value)
                if MacroLoadout.Busy then
                    if PlaybackMacroToggle then PlaybackMacroToggle:Set(Settings.macro_playback, true) end
                    MacroLoadout.Notify("Wait for loadout setup to finish before playback.")
                    return
                end
                Settings.macro_playback = value; Save()
                if not is_lobby() then
                    if value then
                        Library:Notify({Title = "Macro Playback", Text = "Starting Macro Playback...", Duration = 6.5, Icon = "info"})
                        StartMacroPlayback()
                    else
                        Library:Notify({Title = "Macro Playback", Text = "Stopping Macro Playback...", Duration = 6.5, Icon = "info"})
                        StopMacroPlayback()
                    end
                end
            end
        })
        local MacroStatus = MacroSection:Paragraph({Title = "Status", Content = "Waiting for status...\n\n\n\n\n\n"})
        task.spawn(function()
            while MacroStatus ~= nil do
                if CurrentStep ~= nil then
                    local MacroCurrentStep = Macros[Settings.macro_profile]["Macro"][CurrentStep]
                    if MacroCurrentStep ~= nil then
                        local Target, TargetName, TargetIndex = nil, nil, nil
                        local Time = MacroCurrentStep["Time"]
                        local Remote, Parameters = nil, nil
                        if MacroCurrentStep["Target"] ~= nil then
                            Target = MacroCurrentStep["Target"]
                            if Target ~= nil then TargetName = Target["Name"]; TargetIndex = Target["Index"] end
                        end
                        if MacroCurrentStep["Remote"] ~= nil then Remote = MacroCurrentStep["Remote"][1] end
                        if MacroCurrentStep["Parameter"] ~= nil then
                            Parameters = ""
                            for k, v in pairs(MacroCurrentStep["Parameter"]) do
                                Parameters = Parameters .. tostring(k) .. ": " .. tostring(v) .. "; "
                            end
                        end
                        MacroStatus:Set({
                            Title = "Status",
                            Content = string.format(
                                "Current Step: %s\nTarget: %s[%s]\nTime: %s\nGame Elapsed Time: %s\nAction: %s\nParameters: %s",
                                tostring(CurrentStep), tostring(TargetName), tostring(TargetIndex),
                                tostring(Time), tostring(ElapsedTime()), tostring(Remote), tostring(Parameters))
                        })
                    else
                        MacroStatus:Set({Title = "Status", Content = string.format("Error at step %s!\nGame Elapsed Time: %s", tostring(CurrentStep), tostring(ElapsedTime()))})
                    end
                else
                    MacroStatus:Set({Title = "Status", Content = string.format("Idle...\nGame Elapsed Time: %s", tostring(ElapsedTime()))})
                end
                task.wait()
            end
        end)
        MacroSection:Button({
            Text = "Previous Macro Step",
            Callback = function()
                if CurrentStep ~= nil and CurrentStep > 0 then CurrentStep = CurrentStep - 1
                else CurrentStep = 1 end
            end
        })
        MacroSection:Button({
            Text = "Next Macro Step",
            Callback = function()
                if (CurrentStep == nil or CurrentStep < 0) and #Macros[Settings.macro_profile]["Macro"] > 0 then
                    CurrentStep = 1
                elseif CurrentStep ~= nil and CurrentStep > 0 and CurrentStep < #Macros[Settings.macro_profile]["Macro"] then
                    CurrentStep = CurrentStep + 1
                end
            end
        })
        MacroSection:Button({
            Text = "Reset Macro Step",
            Callback = function() if CurrentStep ~= nil then CurrentStep = nil end end
        })

        MacroSection = Macro:Section("Profile Management", 1)
        local ProfileNameInput = ""
        MacroSection:Input({
            Text = "New macro profile name",
            Placeholder = "Default Profile",
            Flag = "new_profile_name",
            Callback = function(text) ProfileNameInput = text end
        })
        MacroSection:Button({
            Text = "Create new macro profile",
            Callback = function()
                local profile_name = ProfileNameInput
                if string.match(profile_name, '[^%w%s]') ~= nil then
                    Library:Notify({Title = "Macro", Text = string.format("%s contains illegal characters!", profile_name), Duration = 6.5, Icon = "info"})
                elseif Macros[profile_name] ~= nil then
                    Library:Notify({Title = "Macro", Text = string.format("Macro %s already exists!", profile_name), Duration = 6.5, Icon = "info"})
                else
                    Macros[profile_name] = DeepCopy(IndividualMacroDefaultSettings)
                    Settings.macro_profile = profile_name
                    Save()
                    table.insert(MacroProfileList, profile_name)

                    MacroProfileDropdown:SetOptions(MacroProfileList)
                    MacroProfileDropdown:Set(Settings.macro_profile)
                    Library:Notify({Title = "Macro", Text = string.format("Created macro %s!", profile_name), Duration = 6.5, Icon = "info"})
                end
            end
        })
        MacroSection:Input({
            Text = "Import Macro",
            Placeholder = "Place Link Here",
            Flag = "import_macro_url",
            Callback = function(text) linkport = text end
        })
        MacroSection:Button({Text = "Import Start", Callback = function() importMacro(linkport) end})
        MacroSection:Button({
            Text = "Delete selected profile",
            Callback = function()
                if #MacroProfileList == 1 then
                    Library:Notify({Title = "Macro", Text = "Cannot remove last macro in list!", Duration = 6.5, Icon = "info"})
                    return
                end
                -- Remove the selected profile and update the Facility dropdown.
                local removed_profile_name = Settings.macro_profile
                delfile(folder_name .. "\\" .. Settings.macro_profile .. ".json")
                Macros[Settings.macro_profile] = nil
                table.remove(MacroProfileList, table.find(MacroProfileList, removed_profile_name))
                for _, v in pairs(MacroProfileList) do
                    if v ~= nil then Settings.macro_profile = v; break end
                end
                Save()
                MacroProfileDropdown:SetOptions(MacroProfileList)
                MacroProfileDropdown:Set(Settings.macro_profile)
                Library:Notify({Title = "Macro", Text = string.format("Successfully removed macro profile %s!", removed_profile_name), Duration = 6.5, Icon = "info"})
            end
        })
        MacroSection:Input({
            Text = "Import Settings",
            Placeholder = "Place Link Here",
            Flag = "import_settings_url",
            Callback = function(text) linkport2 = text end
        })
        MacroSection:Button({Text = "Import Start", Callback = function() importSettings(linkport2) end})
        MacroSection:Button({
            Text = "Clear all macro data on selected profile",
            Callback = function()
                Macros[Settings.macro_profile] = DeepCopy(IndividualMacroDefaultSettings)
                CurrentStep = nil; Save()
                Library:Notify({Title = "Macro", Text = "Selected profile has been cleared.", Duration = 6.5, Icon = "info"})
            end
        })

        MacroSection = Macro:Section("Recording Options", 2)
        MacroSection:Paragraph({
            Title = "Recording Options",
            Content = "These settings will affect any recorded macro and should not be changed unless you have any issues with macro recording. Check if you have any issues using playback offset first before playing with recording offset."
        })
        MacroSection:Slider({
            Text = "Time Offset",
            Min = -10, Max = 10,
            Step = 0.1, Decimals = 1,
            Default = Settings.macro_record_time_offset,
            Flag = "macro_record_time_offset",
            Callback = function(value) Settings.macro_record_time_offset = value; Save() end
        })

        MacroSection = Macro:Section("Playback Options", 1)
        MacroSection:Paragraph({
            Title = "Playback Options",
            Content = "These settings will only apply during macro playback and will not affect any previously recorded macros."
        })
        AddToggle(MacroSection, {
            Text = "Money Tracking",
            Default = Settings.macro_money_tracking,
            Flag = "macro_money_tracking",
            Callback = function(value) Settings.macro_money_tracking = value; Save() end
        })
        MacroSection:Slider({
            Text = "Time Offset",
            Min = -10, Max = 10,
            Step = 0.1, Decimals = 1,
            Default = Settings.macro_playback_time_offset,
            Flag = "macro_playback_time_offset",
            Callback = function(value) Settings.macro_playback_time_offset = value; Save() end
        })
        MacroSection:Slider({
            Text = "Magnitude",
            Min = 0, Max = 2,
            Step = 0.01, Decimals = 2,
            Default = Settings.macro_magnitude,
            Flag = "macro_magnitude",
            Callback = function(value) Settings.macro_magnitude = value; Save() end
        })
        MacroSection:Slider({
            Text = "Attempts before action skip",
            Min = 0, Max = 120,
            Step = 1, Decimals = 0,
            Default = Settings.macro_playback_search_attempts,
            Flag = "macro_playback_search_attempts",
            Callback = function(value) Settings.macro_playback_search_attempts = value; Save() end
        })
        MacroSection:Slider({
            Text = "Action skip search delay",
            Min = 0, Max = 1,
            Step = 0.01, Decimals = 2,
            Default = Settings.macro_playback_search_delay,
            Flag = "macro_playback_search_delay",
            Callback = function(value) Settings.macro_playback_search_delay = value; Save() end
        })

        MacroSection = Macro:Section("Macro Options", 2)
        MacroSection:Paragraph({
            Title = "Macro Options",
            Content = "You should leave all of these toggles on, otherwise your macro will not work properly."
        })
        MacroSection:Dropdown({
            Text = "Elapsed Time Mode",
            Options = {"Version 2", "Version 1"},
            Default = Settings.macro_timer_version,
            Multi = false,
            Flag = "macro_timer_version",
            Callback = function(options)
                Settings.macro_timer_version = options; Save()
            end
        })
        AddToggle(MacroSection, {Text = "Summon Unit", Default = Settings.macro_summon, Flag = "macro_summon", Callback = function(v) Settings.macro_summon = v; Save() end})
        AddToggle(MacroSection, {Text = "Sell Unit", Default = Settings.macro_sell, Flag = "macro_sell", Callback = function(v) Settings.macro_sell = v; Save() end})
        AddToggle(MacroSection, {Text = "Upgrade Unit", Default = Settings.macro_upgrade, Flag = "macro_upgrade", Callback = function(v) Settings.macro_upgrade = v; Save() end})
        AddToggle(MacroSection, {Text = "Change Unit Priority", Default = Settings.macro_priority, Flag = "macro_priority", Callback = function(v) Settings.macro_priority = v; Save() end})
        AddToggle(MacroSection, {Text = "Unit Ability", Default = Settings.macro_ability, Flag = "macro_ability", Callback = function(v) Settings.macro_ability = v; Save() end})
        AddToggle(MacroSection, {Text = "Unit Auto Ability", Default = Settings.macro_auto_ability, Flag = "macro_auto_ability", Callback = function(v) Settings.macro_auto_ability = v; Save() end})
        AddToggle(MacroSection, {Text = "Skip Wave", Default = Settings.macro_skipwave, Flag = "macro_skipwave", Callback = function(v) Settings.macro_skipwave = v; Save() end})
        AddToggle(MacroSection, {Text = "Auto Skip Wave", Default = Settings.macro_autoskipwave, Flag = "macro_autoskipwave", Callback = function(v) Settings.macro_autoskipwave = v; Save() end})
        AddToggle(MacroSection, {Text = "Speed Change", Default = Settings.macro_speedchange, Flag = "macro_speedchange", Callback = function(v) Settings.macro_speedchange = v; Save() end})

        MacroSection = Macro:Section("Ability Blacklist Configuration", 1)
        MacroSection:Paragraph({
            Title = "Ability Blacklist",
            Content = "The ability blacklist allows you to filter out which characters you want to not have the macro record and/or playback."
        })

        local blacklistOptions = #Settings.macro_ability_blacklist > 0 and Settings.macro_ability_blacklist or {"None"}
        local AbilityBlacklistDropdown = MacroSection:Dropdown({
            Text = "Blacklisted Units",
            Options = blacklistOptions,
            Default = blacklistOptions[#blacklistOptions],
            Multi = false,
            Search = true,
            Flag = "ability_blacklist_selected",
            Callback = function(options) end
        })

        local unitListOptions = #UnitList > 0 and UnitList or {"None"}
        local AbilityBlacklistUnitListDropdown = MacroSection:Dropdown({
            Text = "Unit List",
            Options = unitListOptions,
            Default = unitListOptions[1],
            Multi = false,
            Search = true,
            Flag = "ability_blacklist_unitlist",
            Callback = function(options) end
        })

        MacroSection:Button({
            Text = "Add selected unit from unit list to ability blacklist",
            Callback = function()
                local v = AbilityBlacklistUnitListDropdown:Get()
                if type(v) == "table" then v = v[1] end
                    if type(v) ~= "string" or not table.find(UnitList, v) then return end
                if table.find(Settings.macro_ability_blacklist, v) == nil then
                    table.insert(Settings.macro_ability_blacklist, v)
                    Save()
                    AbilityBlacklistDropdown:SetOptions(Settings.macro_ability_blacklist)
                    AbilityBlacklistDropdown:Set(v)
                    Library:Notify({Title = "Ability Blacklist", Text = string.format("Unit %s added to ability blacklist", v), Duration = 6.5, Icon = "info"})
                else
                    Library:Notify({Title = "Ability Blacklist", Text = "Unit already exists in ability blacklist", Duration = 6.5, Icon = "info"})
                end
            end
        })
        MacroSection:Button({
            Text = "Delete selected blacklisted unit from ability blacklist",
            Callback = function()
                local v = AbilityBlacklistDropdown:Get()
                if type(v) == "table" then v = v[1] end
                local idx = table.find(Settings.macro_ability_blacklist, v)
                if idx ~= nil then
                    table.remove(Settings.macro_ability_blacklist, idx)
                    Save()
                    local newList = #Settings.macro_ability_blacklist > 0 and Settings.macro_ability_blacklist or {"None"}
                    AbilityBlacklistDropdown:SetOptions(newList)
                    AbilityBlacklistDropdown:Set(newList[#newList])
                    Library:Notify({Title = "Ability Blacklist", Text = string.format("Unit %s removed from ability blacklist", v), Duration = 6.5, Icon = "info"})
                else
                    Library:Notify({Title = "Ability Blacklist", Text = string.format("Unit %s does not exist in ability blacklist", v), Duration = 6.5, Icon = "info"})
                end
            end
        })

        if not is_lobby() then
            MacroSection = Macro:Section("Offset Settings", 2)
            MacroSection:Paragraph({
                Title = "CAUTION",
                Content = "This is an experimental feature. All changes are irreversible, so please use with caution."
            })
            MacroSection:Button({
                Text = "Save current spawn position to selected macro profile",
                Callback = function()
                    Macros[Settings.macro_profile]["Map"] = {["SpawnLocation"] = tostring(game:GetService("Workspace").SpawnLocation.CFrame)}
                    Save()
                    Library:Notify({Title = "Macro", Text = "Current map has been set to macro profile.", Duration = 6.5, Icon = "info"})
                end
            })
            MacroSection:Button({
                Text = "Update placement locations, if game shifted map positions.",
                Callback = function()
                    if Macros[Settings.macro_profile]["Map"] ~= nil then
                        local SpawnLocation = Macros[Settings.macro_profile]["Map"]["SpawnLocation"]
                        if SpawnLocation ~= nil then
                            local offset = game:GetService("Workspace").SpawnLocation.CFrame * StringToCFrame(SpawnLocation):Inverse()
                            for _, v in pairs(Macros[Settings.macro_profile]["Units"]) do
                                v["Position"] = v["Position"] * offset
                            end
                        end
                    end
                    Macros[Settings.macro_profile]["Map"] = {["SpawnLocation"] = tostring(game:GetService("Workspace").SpawnLocation.CFrame)}
                    Save()
                end
            })
        end
    end

    local function AdvancedSettings()
        local AdvancedSettingsTab = Window:Tab("Advanced Settings")
        local AdvancedSettingsTabSection

        local function AutoUnitBuffingSettings()
            AdvancedSettingsTabSection = AdvancedSettingsTab:Section("Auto Unit Buffing Settings", 1)
            AdvancedSettingsTabSection:Paragraph({
                Title = "Auto Unit Buffing Settings",
                Content = "Select a configured unit under Units, click Edit Auto Unit Buffing Settings, change the fields, then Save Auto Unit Buffing Settings. Existing units read edits on a subsequent buff loop; newly added units require a rejoin and script execution."
            })
            local AutoBuffUnitList = get_keys(Settings.auto_buff_units)
            local AutoBuffSelectedUnitInformation = AdvancedSettingsTabSection:Paragraph({Title = "Selected Unit Information", Content = "Waiting for selected unit...\n"})

            local function AutoBuffDropdownCallback(options)
                local value = type(options) == "table" and options[1] or options
                if AutoBuffSelectedUnitInformation ~= nil and Settings.auto_buff_units[value] ~= nil then
                    local content = ""
                    for k, v in pairs(Settings.auto_buff_units[value]) do
                        if type(v) == "table" then
                            local parts = {}
                            for i, item in ipairs(v) do
                                if type(item)=="table" then
                                    table.insert(parts, "Box " .. i .. " (time " .. tostring(item.Time) .. ", delay " .. tostring(item.Delay) .. ")")
                                else table.insert(parts,tostring(item)) end
                            end
                            content = content .. string.format("%s: %s\n", tostring(k), table.concat(parts, "; "))
                        else
                            content = content .. string.format("%s: %s\n", tostring(k), tostring(v))
                        end
                    end
                    AutoBuffSelectedUnitInformation:Set({Title = "Selected Unit Information", Content = content})
                end
            end

            local autoBuffListOptions = #AutoBuffUnitList > 0 and AutoBuffUnitList or {"None"}
            local AutoBuffDropdown = AdvancedSettingsTabSection:Dropdown({
                Text = "Units",
                Options = autoBuffListOptions,
                Default = autoBuffListOptions[#autoBuffListOptions],
                Multi = false,
                Search = true,
            Flag = "autobuff_selected",
                Callback = AutoBuffDropdownCallback
            })

            if #AutoBuffUnitList > 0 then
                local firstUnit = AutoBuffUnitList[#AutoBuffUnitList]
                AutoBuffSelectedUnitInformation:Set({
                    Title = "Selected Unit Information",
                    Content = string.format(
                        "Mode: %s\nChecks: %s\nAbility Type: %s\nAbility Name: %s\nTime: %s",
                        Settings.auto_buff_units[firstUnit]["Mode"],
                        table.concat(Settings.auto_buff_units[firstUnit]["Checks"], ", "),
                        Settings.auto_buff_units[firstUnit]["Ability Type"],
                        tostring(Settings.auto_buff_units[firstUnit]["Ability Name"]),
                        tostring(Settings.auto_buff_units[firstUnit]["Time"]))
                })
            end

            local unitListOpts = #UnitList > 0 and UnitList or {"None"}
            local AutoBuffUnitListDropdown = AdvancedSettingsTabSection:Dropdown({
                Text = "Unit List",
                Options = unitListOpts,
                Default = unitListOpts[1],
                Multi = false,
                Search = true,
            Flag = "autobuff_unitlist",
                Callback = function(options) end
            })

            local AutoBuffModeDropdown = AdvancedSettingsTabSection:Dropdown({
                Text = "Buffing Mode",
                Options = {"Box", "Pair", "Cycle", "Spam"},
                Default = "Box",
                Multi = false,
                Flag = "autobuff_mode",
                Callback = function(options) end
            })

            -- Multi-select for buff checks
            local AutoBuffChecks = AdvancedSettingsTabSection:Dropdown({
                Text = "Auto Buff Checks",
                Options = {"Attack Buff", "Range Buff"},
                Default = {"Attack Buff", "Range Buff"},
                Multi = true,
                Flag = "autobuff_checks",
                Callback = function(options) end
            })

            local AutoBuffTypeControl = AdvancedSettingsTabSection:Dropdown({
                Text="Ability Type", Options={"Normal", "Multiple"}, Default="Normal",
                Multi=false, Flag="autobuff_ability_type", Callback=function() end,
            })
            local AnyMove = "Any available ability (legacy)"
            local AutoBuffMoveControl = AdvancedSettingsTabSection:Dropdown({
                Text="Normal / Primary Ability", Options={AnyMove}, Default=AnyMove,
                Multi=false, Flag="autobuff_special_move", Callback=function() end,
            })
            local AutoBuffExactControl = AdvancedSettingsTabSection:Input({
                Text="Exact Ability Name (optional override)", Default="",
                Placeholder="Exact SpecialMove name", Flag="autobuff_exact_move", Callback=function() end,
            })
            AdvancedSettingsTabSection:Button({
                Text="Refresh Detected Abilities",
                Callback=function()
                    local options, seen = {AnyMove}, {[AnyMove]=true}
                    for _, unit in ipairs(get_units()) do
                        local move = unit:FindFirstChild("SpecialMove")
                        if move and type(move.Value)=="string" and move.Value~="" and not seen[move.Value] then
                            seen[move.Value]=true; table.insert(options,move.Value)
                        end
                    end
                    local selected=AutoBuffMoveControl:Get()
                    if type(selected)=="table" then selected=selected[1] end
                    if selected and not seen[selected] then table.insert(options,selected) end
                    AutoBuffMoveControl:SetOptions(options)
                    AutoBuffMoveControl:Set(selected or AnyMove,true)
                end,
            })
            AdvancedSettingsTabSection:Paragraph({Title="Ability matching and boxes",
                Content="An exact primary ability name only runs while SpecialMove matches it, including after upgrades. Multiple selects the named menu option. Box uses independent groups of four in detection order; each box has its own timer. Incomplete groups wait. These groups are not based on map geometry."})
            local AutoBuffMultipleAbilitiesNameInput
            local AutoBuffAbilityNameControl = AdvancedSettingsTabSection:Input({
                Text = "Multiple Abilities: Menu Option Name",
                Placeholder = "Buff Ability",
                Flag = "autobuff_ability_name",
                Callback = function(text) AutoBuffMultipleAbilitiesNameInput = text end
            })

            local AutoBuffAbilityTime = 15
            local AutoBuffTimeControl = AdvancedSettingsTabSection:Input({
                Text = "Ability Time",
                Default = "15",
                Placeholder = "15",
                Flag = "autobuff_ability_time",
                Callback = function(text) AutoBuffAbilityTime = tonumber(text) end
            })

            local CycleUnits = 8
            local AutoBuffCycleControl = AdvancedSettingsTabSection:Slider({
                Text = "Cycle Units",
                Min = 1, Max = 8,
                Step = 1, Decimals = 0,
                Default = CycleUnits,
                Flag = "autobuff_cycle_units",
                Callback = function(value) CycleUnits = value end
            })

            local AutoBuffDelay = 0
            local AutoBuffDelayControl = AdvancedSettingsTabSection:Slider({
                Text = "Post Loop Delay",
                Min = 0, Max = 60,
                Step = 0.1, Decimals = 1,
                Default = AutoBuffDelay,
                Flag = "autobuff_delay",
                Callback = function(value) AutoBuffDelay = value end
            })

            local AutoBuffBox2Time = AdvancedSettingsTabSection:Input({
                Text="Box 2 Ability Time", Default="", Placeholder="Blank = Ability Time",
                Flag="autobuff_box2_time", Callback=function() end,
            })
            local AutoBuffBox2Delay = AdvancedSettingsTabSection:Input({
                Text="Box 2 Post Loop Delay", Default="", Placeholder="Blank = Post Loop Delay",
                Flag="autobuff_box2_delay", Callback=function() end,
            })
            local editingUnit
            local EditStatus = AdvancedSettingsTabSection:Paragraph({
                Title = "Edit Auto Unit Buffing Settings",
                Content = "Select a unit under Units, then click Edit to load its saved settings."
            })

            local function BuffNotice(message)
                Library:Notify({Title = "Auto Buff", Text = message, Duration = 6.5, Icon = "info"})
            end

            local function ReadBuffFields()
                local mode = AutoBuffModeDropdown:Get()
                if type(mode) == "table" then mode = mode[1] end
                if not table.find({"Box", "Pair", "Cycle", "Spam"}, mode) then
                    BuffNotice("Choose a valid buffing mode."); return nil
                end
                -- Read controls directly so saving includes text still being edited.
                local time = tonumber(AutoBuffTimeControl:Get())
                if not time or time ~= time or time == math.huge or time <= 0 then
                    BuffNotice("Ability Time must be a finite number greater than zero."); return nil
                end
                local checks = {}
                local abilityType = AutoBuffTypeControl:Get()
                if type(abilityType)=="table" then abilityType=abilityType[1] end
                if abilityType~="Normal" and abilityType~="Multiple" then
                    BuffNotice("Choose Normal or Multiple."); return nil
                end
                local chosen = AutoBuffChecks:Get()
                if type(chosen) ~= "table" then chosen = {chosen} end
                for _, check in ipairs(chosen) do
                    if check == "Attack Buff" then table.insert(checks, "attack")
                    elseif check == "Range Buff" then table.insert(checks, "range") end
                end
                local abilityName = AutoBuffAbilityNameControl:Get():match("^%s*(.-)%s*$")
                if abilityType == "Multiple" and abilityName == "" then
                    BuffNotice("Enter an ability name when Multiple Abilities is selected."); return nil
                end
                local move = AutoBuffExactControl:Get():match("^%s*(.-)%s*$")
                if move=="" then
                    move=AutoBuffMoveControl:Get()
                    if type(move)=="table" then move=move[1] end
                    if move==AnyMove then move="" end
                end
                local boxTimeText=AutoBuffBox2Time:Get():match("^%s*(.-)%s*$")
                local boxDelayText=AutoBuffBox2Delay:Get():match("^%s*(.-)%s*$")
                local boxTime, boxDelay=time, AutoBuffDelayControl.Value
                if boxTimeText~="" then boxTime=tonumber(boxTimeText) end
                if boxDelayText~="" then boxDelay=tonumber(boxDelayText) end
                if not boxTime or boxTime~=boxTime or boxTime==math.huge or boxTime<=0
                    or not boxDelay or boxDelay~=boxDelay or boxDelay==math.huge or boxDelay<0 then
                    BuffNotice("Box 2 time must be positive and its delay nonnegative; both must be finite."); return nil
                end
                return {
                    ["Special Move Name"] = move or "",
                    ["Box Timings"] = {{Time=time, Delay=AutoBuffDelayControl.Value}, {Time=boxTime, Delay=boxDelay}},
                    ["Mode"] = mode,
                    ["Checks"] = checks,
                    ["Ability Type"] = abilityType,
                    ["Ability Name"] = abilityType == "Multiple" and abilityName or nil,
                    ["Time"] = time,
                    ["Cycle Units"] = AutoBuffCycleControl.Value,
                    ["Delay"] = AutoBuffDelayControl.Value
                }
            end

            AdvancedSettingsTabSection:Button({
                Text = "Edit Auto Unit Buffing Settings",
                Callback = function()
                    local unit = AutoBuffDropdown:Get()
                    if type(unit) == "table" then unit = unit[1] end
                    local config = unit and Settings.auto_buff_units[unit]
                    if not config then BuffNotice("Select an existing auto-buff unit under Units."); return end
                    editingUnit = unit
                    local checks = {}
                    for _, check in ipairs(config["Checks"] or {}) do
                        if check == "attack" then table.insert(checks, "Attack Buff")
                        elseif check == "range" then table.insert(checks, "Range Buff") end
                    end
                    AutoBuffTypeControl:Set(config["Ability Type"] or "Normal",true)
                    local selectedMove=config["Special Move Name"] or ""
                    AutoBuffMoveControl:SetOptions(selectedMove~="" and {AnyMove,selectedMove} or {AnyMove})
                    AutoBuffMoveControl:Set(selectedMove~="" and selectedMove or AnyMove,true)
                    AutoBuffExactControl:Set("",true)
                    local box2=type(config["Box Timings"])=="table" and config["Box Timings"][2]
                    AutoBuffBox2Time:Set(box2 and tostring(box2.Time or "") or "",true)
                    AutoBuffBox2Delay:Set(box2 and tostring(box2.Delay or "") or "",true)
                    AutoBuffModeDropdown:Set(config["Mode"] or "Box", true)
                    AutoBuffChecks:Set(checks, true)
                    AutoBuffAbilityNameControl:Set(config["Ability Name"] or "", true)
                    AutoBuffTimeControl:Set(tostring(config["Time"] or 15), true)
                    AutoBuffCycleControl:Set(config["Cycle Units"] or 8, true)
                    AutoBuffDelayControl:Set(config["Delay"] or 0, true)
                    EditStatus:Set({Title = "Editing: " .. unit, Content = "Change the fields above, then click Save Auto Unit Buffing Settings."})
                end
            })

            AdvancedSettingsTabSection:Button({
                Text = "Save Auto Unit Buffing Settings",
                Callback = function()
                    local selected = AutoBuffDropdown:Get()
                    if type(selected) == "table" then selected = selected[1] end
                    if not editingUnit or selected ~= editingUnit then
                        BuffNotice("Click Edit for the selected unit before saving."); return
                    end
                    local config = Settings.auto_buff_units[editingUnit]
                    if not config then BuffNotice("This unit was removed. Select a unit and click Edit again."); return end
                    local updated = ReadBuffFields()
                    if not updated then return end
                    -- Keep the table reference used by the running buff loop.
                    for key, value in pairs(updated) do config[key] = value end
                    config["Ability Name"] = updated["Ability Name"]
                    Save()
                    AutoBuffDropdownCallback(editingUnit)
                    EditStatus:Set({Title = "Editing: " .. editingUnit, Content = "Changes saved."})
                    BuffNotice("Saved auto-buff settings for " .. editingUnit .. ".")
                end
            })

            AdvancedSettingsTabSection:Button({
                Text = "Add selected unit from unit list to auto buff",
                Callback = function()
                    local v = AutoBuffUnitListDropdown:Get()
                    if type(v) == "table" then v = v[1] end
                    if type(v) ~= "string" or not table.find(UnitList, v) then return end
                    if Settings.auto_buff_units[v] == nil then
                        local updated = ReadBuffFields()
                        if not updated then return end
                        Settings.auto_buff_units[v] = updated
                        Save()
                        local newList = get_keys(Settings.auto_buff_units)
                        AutoBuffDropdown:SetOptions(newList)
                        AutoBuffDropdown:Set(v)
                        Library:Notify({Title = "Auto Buff", Text = string.format("Unit %s added to auto buff unit list", v), Duration = 6.5, Icon = "info"})
                    else
                        Library:Notify({Title = "Auto Buff", Text = "Unit already exists in auto buff list", Duration = 6.5, Icon = "info"})
                    end
                end
            })

            AdvancedSettingsTabSection:Button({
                Text = "Delete selected auto buff unit from auto buff",
                Callback = function()
                    local v = AutoBuffDropdown:Get()
                    if type(v) == "table" then v = v[1] end
                    if Settings.auto_buff_units[v] ~= nil then
                        Settings.auto_buff_units[v] = nil
                        Save()
                        local newList = get_keys(Settings.auto_buff_units)
                        if #newList == 0 then newList = {"None"} end
                        AutoBuffDropdown:SetOptions(newList)
                        AutoBuffDropdown:Set(newList[#newList])
                        Library:Notify({Title = "Auto Buff", Text = string.format("Unit %s removed from auto buff list", v), Duration = 6.5, Icon = "info"})
                    else
                        Library:Notify({Title = "Auto Buff", Text = string.format("Unit %s does not exist in auto buff list", v), Duration = 6.5, Icon = "info"})
                    end
                end
            })
        end

        local function ActionQueueSettings()
            AdvancedSettingsTabSection = AdvancedSettingsTab:Section("Action Queue Settings", 2)
            AdvancedSettingsTabSection:Paragraph({
                Title = "Action Queue",
                Content = "The action queue ensures remotes are executed successfully despite lag or insufficient resources."
            })
            AdvancedSettingsTabSection:Slider({
                Text = "Remote Action Delay",
                Min = 0, Max = 1,
                Step = 0.01, Decimals = 2,
                Default = Settings.action_queue_remote_fire_delay,
                Flag = "action_queue_remote_fire_delay",
                Callback = function(value) Settings.action_queue_remote_fire_delay = value; Save() end
            })
            AdvancedSettingsTabSection = AdvancedSettingsTab:Section("Remote Refiring", 2)
            AdvancedSettingsTabSection:Paragraph({
                Title = "What is remote refiring?",
                Content = "Remote refiring calls the remote repeatedly until the action succeeds."
            })
            AddToggle(AdvancedSettingsTabSection, {
                Text = "Refire Remote",
                Default = Settings.action_queue_remote_on_fail,
                Flag = "action_queue_remote_on_fail",
                Callback = function(value) Settings.action_queue_remote_on_fail = value; Save() end
            })
            AdvancedSettingsTabSection:Slider({
                Text = "Pre Loop Delay",
                Min = 0, Max = 1,
                Step = 0.01, Decimals = 2,
                Default = Settings.action_queue_remote_on_fail_delay,
                Flag = "action_queue_remote_on_fail_delay",
                Callback = function(value) Settings.action_queue_remote_on_fail_delay = value; Save() end
            })
            AdvancedSettingsTabSection:Slider({
                Text = "Loop Delay",
                Min = 0, Max = 1,
                Step = 0.01, Decimals = 2,
                Default = Settings.action_queue_remote_on_fail_delay_loop,
                Flag = "action_queue_remote_on_fail_delay_loop",
                Callback = function(value) Settings.action_queue_remote_on_fail_delay = value; Save() end
            })
        end

        AutoUnitBuffingSettings()
        ActionQueueSettings()
    end

    local function LobbySettings()
        local Lobby = Window:Tab("Lobby")
        local LobbySection
        LobbySection = Lobby:Section("Lobby Scripts", 1)
        AddToggle(LobbySection, {Text = "Auto Join Game", Default = Settings.auto_join_game, Flag = "auto_join_game", Callback = function(value) Settings.auto_join_game = value; Save(); if value and is_lobby() then task.spawn(AutoJoinGame) end end})
        AddToggle(LobbySection, {Text = "Auto Join Tower", Default = Settings.auto_join_tower, Flag = "auto_join_tower", Callback = function(value) Settings.auto_join_tower = value; Save(); if value and is_lobby() then task.spawn(AutoTower) end end})
        AddToggle(LobbySection, {Text = "Auto Evolve EXP", Default = Settings.auto_evolve_exp, Flag = "auto_evolve_exp", Callback = function(value) Settings.auto_evolve_exp = value; Save(); if value and is_lobby() then task.spawn(AutoEvolveEXP) end end})
        AddToggle(LobbySection, {Text = "Auto Click Popup", Default = Settings.auto_skip_gui, Flag = "auto_skip_gui", Callback = function(value) Settings.auto_skip_gui = value; Save(); if value then task.spawn(AutoSkipGUI) end end})

        LobbySection = Lobby:Section("Auto Join Settings", 2)
        LobbySection:Slider({Text = "Delay", Min = 0, Max = 60, Step = 1, Decimals = 0, Default = Settings.auto_join_delay, Flag = "auto_join_delay", Callback = function(value) Settings.auto_join_delay = value; Save() end})
        LobbySection:Dropdown({
            Text = "Mode",
            Options = {"Story", "Infinite", "Adventure", "Time Chamber", "Team Event", "Bakugan Event"},
            Default = Settings.auto_join_mode,
            Multi = false,
            Flag = "auto_join_mode",
            Callback = function(options) Settings.auto_join_mode = options; Save() end
        })
        StoryLevelControl = LobbySection:Slider({Text = "Story Level", Min = 1, Max = math.max(get_number_missions(), Settings.auto_join_story_level), Step = 1, Decimals = 0, Default = Settings.auto_join_story_level, Flag = "auto_join_story_level", Callback = function(value) Settings.auto_join_story_level = value; Save() end})

        if InfiniteMapTable[Settings.auto_join_infinite_level] == nil then
            Settings.auto_join_infinite_level = "-1"; Save()
        end
        LobbySection:Dropdown({
            Text = "Infinite Map Selection",
            Options = GetMapsFromTable(InfiniteMapTable),
            Default = InfiniteMapTable[Settings.auto_join_infinite_level],
            Multi = false,
            Flag = "auto_join_infinite_level",
            Callback = function(options)
                local option = options
                for k, v in pairs(InfiniteMapTable) do
                    if v == option then Settings.auto_join_infinite_level = k; Save(); break end
                end
            end
        })

        RefreshAdventureMaps()
        local adventureLabelsToIds = {}
        local adventureIdsToLabels = {}
        local function BuildAdventureOptions()
            table.clear(adventureLabelsToIds)
            table.clear(adventureIdsToLabels)
            local counts, options = {}, {}
            for _, name in pairs(AdventureMapTable) do
                counts[name] = (counts[name] or 0) + 1
            end
            for id, name in pairs(AdventureMapTable) do
                local label = counts[name] > 1 and (name .. " [" .. id .. "]") or name
                adventureLabelsToIds[label] = id
                adventureIdsToLabels[id] = label
                table.insert(options, label)
            end
            table.sort(options)
            local selected = adventureIdsToLabels[tostring(Settings.auto_join_adventure_level)]
            if not selected then
                selected = #options == 0 and "Waiting for Adventure maps..." or "Select an Adventure map..."
                table.insert(options, 1, selected)
            end
            return options, selected
        end

        local adventureOptions, adventureSelected = BuildAdventureOptions()
        local AdventureMapDropdown = LobbySection:Dropdown({
            Text = "Adventure Map Selection",
            Options = adventureOptions,
            Default = adventureSelected,
            Multi = false,
            Search = true,
            Flag = "auto_join_adventure_level",
            Callback = function(option)
                if type(option) == "table" then option = option[1] end
                local id = adventureLabelsToIds[option]
                if id then Settings.auto_join_adventure_level = id; Save() end
            end
        })

        -- Also handles delayed card creation, title changes and replaced HUDs.
        -- Preserve the saved map ID while the game's list is unavailable.
        task.spawn(function()
            while AdventureMapDropdown.Instance and AdventureMapDropdown.Instance.Parent do
                if RefreshAdventureMaps() then
                    local options, selected = BuildAdventureOptions()
                    AdventureMapDropdown:SetOptions(options)
                    AdventureMapDropdown:Set(selected, true)
                end
                task.wait(2)
            end
        end)

        if get_world() ~= -1 and get_world() ~= -2 then
            LobbySection = Lobby:Section("World Teleports", 1)
            local function UseWorldTeleporter(Teleporter)
                firetouchinterest(Player.Character.HumanoidRootPart, Teleporter, 0)
                task.wait()
                firetouchinterest(Player.Character.HumanoidRootPart, Teleporter, 1)
            end
            if get_world() == 1 then
                LobbySection:Button({Text = "Teleport to World 2", Callback = function() UseWorldTeleporter(get_world_teleporter()) end})
            elseif get_world() == 2 then
                LobbySection:Button({Text = "Teleport to World 1", Callback = function() UseWorldTeleporter(get_world_teleporter()) end})
            end
        end
    end

    local function WebhookSettings()
        local Webhook = Window:Tab("Webhooks")
        local WebhookSection
        WebhookSection = Webhook:Section("Settings", 1)
        WebhookSection:Input({Text = "URL", Placeholder = Settings.webhook_url, Flag = "webhook_url", Callback = function(text) Settings.webhook_url = text; Save() end})
        WebhookSection:Input({Text = "Discord ID", Placeholder = Settings.webhook_discord_id, Flag = "webhook_discord_id", Callback = function(text) Settings.webhook_discord_id = text; Save() end})
        AddToggle(WebhookSection, {Text = "Ping User", Default = Settings.webhook_ping_user, Flag = "webhook_ping_user", Callback = function(value) Settings.webhook_ping_user = value; Save() end})
        WebhookSection:Button({Text = "Test Webhook", Callback = function() SendWebhook({{["name"] = "Webhook Test", ["value"] = "Webhook sent successfully!"}}) end})
        WebhookSection:ColorPicker({
            Text = "Webhook color",
            Default = Color3.fromHex(Settings.webhook_color), Alpha = false,
            Flag = "webhook_color",
            Callback = function(value) Settings.webhook_color = value:ToHex(); Save() end
        })
        WebhookSection = Webhook:Section("Toggles", 2)
        AddToggle(WebhookSection, {Text = "Send webhook on game end", Default = Settings.webhook_end_game, Flag = "webhook_end_game", Callback = function(value) Settings.webhook_end_game = value; Save() end})
        AddToggle(WebhookSection, {Text = "Send webhook after exp evolve", Default = Settings.webhook_exp_evolve, Flag = "webhook_exp_evolve", Callback = function(value) Settings.webhook_exp_evolve = value; Save() end})
    end

    local function MiscellaneousSettings()
        local Miscellaneous = Window:Tab("Miscellaneous")
        local MiscellaneousSection
        MiscellaneousSection = Miscellaneous:Section("Game Settings", 1)
        AddToggle(MiscellaneousSection, {Text = "FPS Boost", Default = Settings.fps_boost, Flag = "fps_boost", Callback = function(value) Settings.fps_boost = value; Save() end})
        AddToggle(MiscellaneousSection, {
            Text = "Anti-AFK",
            Default = Settings.anti_afk,
            Flag = "anti_afk",
            Callback = function(value)
                Settings.anti_afk = value; Save()
                for _, v in pairs(getconnections(game.Players.LocalPlayer.Idled)) do v:Disable() end
            end
        })
        AddToggle(MiscellaneousSection, {
            Text = "Disable 3D Rendering",
            Default = Settings.disable_3d_rendering,
            Flag = "disable_3d_rendering",
            Callback = function(value)
                Settings.disable_3d_rendering = value; Save()
                game:GetService("RunService"):Set3dRenderingEnabled(not value)
            end
        })
        AddToggle(MiscellaneousSection, {
            Text = "Auto Execute",
            Default = Settings.auto_execute,
            Flag = "auto_execute",
            Callback = function(value)
                Settings.auto_execute = value; Save()
                if value then library.AutoExecute() end
            end
        })
        if get_world() ~= -1 and get_world() ~= -2 then
            AddToggle(MiscellaneousSection, {
                Text = "Anonymous Mode",
                Default = Settings.anonymous_mode,
                Flag = "anonymous_mode",
                Callback = function(value)
                    Settings.anonymous_mode = value; Save()
                    if value then AnonMode() end
                end
            })
            MiscellaneousSection:Input({
                Text = "Change Name",
                Placeholder = Settings.anonymous_mode_name,
                Flag = "anonymous_mode_name",
                Callback = function(text)
                    Settings.anonymous_mode_name = text; Save()
                    if Settings.anonymous_mode then AnonMode() end
                end
            })
        end
        MiscellaneousSection = Miscellaneous:Section("Reset", 2)
        MiscellaneousSection:Button({
            Text = "Reset settings to default",
            Callback = function()
                local resetSettings = DeepCopy(DefaultSettings)
                resetSettings.UpdateKey = Settings.UpdateKey
                resetSettings.UpdateShownAt = Settings.UpdateShownAt
                resetSettings.UpdateLog = Settings.UpdateLog
                Settings = resetSettings; Save()
                Library:Notify({Title = "Reset", Text = "Settings restored to default! Rejoin or re-execute to apply.", Duration = 6.5, Icon = "info"})
            end
        })
    end

    local function CreditsSettings()
        local Credits = Window:Tab("Credits")
        local CreditsSection
        CreditsSection = Credits:Full("Credits")
        CreditsSection:Paragraph({
            Title = "Made by KarmaPanda & Maintained by Jeikaru",
            Content = "UI powered by Facility (NEW UI). Thanks to all the supporters and donators! Join our Discord: https://discord.gg/BrnQQGKbvE"
        })
    end

    MainSettings()
    MacroSettings()
    LobbySettings()
    WebhookSettings()
    AdvancedSettings()
    MiscellaneousSettings()
    CreditsSettings()
    CreateMiniGUI()
    CreateHideButtonGUI()
    Library:ClearDirty()
    ShowUpdateLog()
end

InitializeUI()

print("[KarmaPanda] UI Loaded: " .. os.clock() - benchmark_time)
benchmark_time = os.clock()

end, function(err)
    return debug.traceback(tostring(err), 2)
end)
currentSession.Loading = false
print("yes work:>")
if not started then

    if not currentSession.Library and sessionEnvironment[sessionKey] == currentSession then
        sessionEnvironment[sessionKey] = nil
    end
    warn("[KarmaPanda] Startup failed: " .. tostring(startupError))
    if currentSession.Library then
        warn("[KarmaPanda] Rejoin before retrying to clear the partial session.")
    end
end
