local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- [ 1. Global Config ]
-- ==========================================
_G.AutoFarm      = false
_G.BossPriority  = false
_G.SelectedBosses = {}
_G.SelectedMonster = ""
_G.FarmPosition  = "Behind"
_G.FlySpeed      = 150
_G.MinHP         = 30
_G.Teleporting   = false
_G.AntiAFK       = true
_G.AntiPlayer    = false
_G.AttackDistance = 2

local BossList = {"Zanshi Bing Ren", "Zanshi Huo Ren", "Mount Hua Leader"}

-- ==========================================
-- [ 2. Fluent UI Initialization ]
-- ==========================================
local function HttpGetOrError(url)
    local ok, res = pcall(function()
        return game:HttpGet(url, true)
    end)
    if not ok then
        error(("HttpGet failed for %s\n%s"):format(url, tostring(res)))
    end
    return res
end

local function LoadStringOrError(src, name)
    local fn, err = loadstring(src)
    if not fn then
        error(("loadstring failed for %s\n%s"):format(name or "unknown", tostring(err)))
    end
    return fn()
end

local Fluent = LoadStringOrError(HttpGetOrError("https://github.com/dawid-scripts/Fluent/releases/download/1.1.0/main.lua"), "Fluent/main.lua")
local SaveManager = LoadStringOrError(HttpGetOrError("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/Addons/SaveManager.lua"), "Fluent/SaveManager.lua")
local InterfaceManager = LoadStringOrError(HttpGetOrError("https://cdn.jsdelivr.net/gh/dawid-scripts/Fluent@master/Addons/InterfaceManager.lua"), "Fluent/InterfaceManager.lua")

local Window
do
    local ok, res = pcall(function()
        return Fluent:CreateWindow({
            Title = "Soul Cultivition",
            SubTitle = "by NIGHT",
            TabWidth = 160,
            Size = UDim2.fromOffset(580, 460),
            Acrylic = false,
            Theme = "Dark",
            MinimizeKey = Enum.KeyCode.RightControl
        })
    end)
    if not ok then
        warn("[UI] Fluent:CreateWindow failed: " .. tostring(res))
        error(res)
    end
    Window = res
end

-- ==========================================
-- [ 3. Setup Tabs ]
-- ==========================================
local Tabs = {
    Farm = Window:AddTab({ Title = "Farm", Icon = "swords" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})

InterfaceManager:SetFolder("FluentSettings")
SaveManager:SetFolder("FluentSettings/FischAutoFarm")

Window:SelectTab(1)

-- (Farm Entities)
local function ScanMonsters()
    local names = {}
    local seen = {}
    local e = workspace:FindFirstChild("Enemies")
    if e then
        for _, obj in ipairs(e:GetChildren()) do
            if obj:FindFirstChild("Humanoid") and not obj.Name:lower():find("zanshi") then
                if not seen[obj.Name] then 
                    seen[obj.Name] = true
                    table.insert(names, obj.Name) 
                end
            end
        end
    end
    table.sort(names)
    return names
end

local function ScanNPCs()
    local names = {}
    local seen = {}
    local npcFolder = workspace:FindFirstChild("NPCs")
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            if npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head") or npc:IsA("BasePart") or npc:IsA("Model") then
                if not seen[npc.Name] then 
                    seen[npc.Name] = true
                    table.insert(names, npc.Name) 
                end
            end
        end
    end
    table.sort(names)
    return names
end

local function ScanZones(subFolder)
    local names = {}
    local seen = {}
    local tz = workspace:FindFirstChild("Training Zones")
    if tz then
        local folder = tz:FindFirstChild(subFolder)
        if folder then
            for _, zone in ipairs(folder:GetChildren()) do
                if not seen[zone.Name] then 
                    seen[zone.Name] = true
                    table.insert(names, zone.Name) 
                end
            end
        end
    end
    table.sort(names)
    return names
end

local initTargets = ScanNPCs()
if #initTargets == 0 then initTargets = {"(None Found)"} end
local selectedTarget = initTargets[1]
local selectedCategory = "NPC"
local TargetDropdown

local function FetchTargetsByCategory(cat)
    local t = {}
    if cat == "NPC" then t = ScanNPCs()
    elseif cat == "Qi" then t = ScanZones("Qi")
    elseif cat == "Training" then t = ScanZones("Training")
    end
    if #t == 0 then t = {"(None Found)"} end
    return t
end
local function RefreshTargetList()
    local targets = FetchTargetsByCategory(selectedCategory)
    if TargetDropdown then TargetDropdown.SetOptions(targets) end
end

local function FindPosition(obj)
    if obj:IsA("Model") then
        local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Head")
        if hrp then return hrp.CFrame end
        if obj.PrimaryPart then return obj.PrimaryPart.CFrame end
        for _, child in ipairs(obj:GetDescendants()) do
            if child:IsA("BasePart") then return child.CFrame end
        end
    elseif obj:IsA("BasePart") then
        return obj.CFrame
    end
    return nil
end

local BASE_COOLDOWN = 0.18
local JITTER_RANGE  = 0.08
local function StopFlying()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        for _, name in ipairs({"BypassPosition", "BypassOrientation", "BypassAttachment"}) do
            local p = hrp:FindFirstChild(name)
            if p then p:Destroy() end
        end
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end
local function FlyToTarget(targetCFrame)
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local att = hrp:FindFirstChild("BypassAttachment") or Instance.new("Attachment", hrp)
    att.Name = "BypassAttachment"

    local pos = hrp:FindFirstChild("BypassPosition") or Instance.new("AlignPosition", hrp)
    pos.Name = "BypassPosition"; pos.Attachment0 = att
    pos.Mode = Enum.PositionAlignmentMode.OneAttachment
    pos.MaxForce = math.huge; pos.MaxVelocity = _G.FlySpeed; pos.Responsiveness = 200

    local ori = hrp:FindFirstChild("BypassOrientation") or Instance.new("AlignOrientation", hrp)
    ori.Name = "BypassOrientation"; ori.Attachment0 = att
    ori.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ori.MaxTorque = math.huge; ori.Responsiveness = 200

    pos.Position = targetCFrame.Position
    ori.CFrame   = targetCFrame
    
    for _, p in ipairs(LocalPlayer.Character:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end

local lastAttackTime = 0
local function AutoHit()
    local now = tick()
    local cooldown = BASE_COOLDOWN + math.random() * JITTER_RANGE
    if now - lastAttackTime < cooldown then return end
    lastAttackTime = now

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hrp then return end

    pcall(function()
        local tool = char:FindFirstChildOfClass("Tool") or LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
        if tool then
            if tool.Parent ~= char then char.Humanoid:EquipTool(tool) end
            tool:Activate()
            if ReplicatedStorage:FindFirstChild("RemoteEvents") and ReplicatedStorage.RemoteEvents:FindFirstChild("Attack") then
                ReplicatedStorage.RemoteEvents.Attack:FireServer(tool.Name, { ["RootPart"] = hrp })
            end
        end
    end)
end

-- ==========================================
-- [ 4. Build Components in UI ]
-- ==========================================

-- ------------------------------------------
-- FARM TAB
-- ------------------------------------------
Tabs.Farm:AddParagraph({Title = "⚙️ Main Controls", Content = "Toggle auto-farming behavior."})

local TogFarm = Tabs.Farm:AddToggle("TogAutoFarm", {
    Title = "Start Auto Farm",
    Default = false,
    Callback = function(v) _G.AutoFarm = v end
})

Tabs.Farm:AddParagraph({Title = "🎯 Targeting & Position", Content = "Setup target selection and your position."})

local mVals = ScanMonsters()
if #mVals == 0 then mVals = {"(None)"} end

local DropMonster = Tabs.Farm:AddDropdown("DropMonster", {
    Title = "Select Monster",
    Values = mVals,
    Multi = false,
    Default = 1,
    Callback = function(v) _G.SelectedMonster = v end
})

Tabs.Farm:AddButton({
    Title = "Refresh Monsters",
    Callback = function()
        local nm = ScanMonsters()
        if #nm == 0 then nm = {"(None)"} end
        DropMonster:SetValues(nm)
        DropMonster:SetValue(nm[1])
        Fluent:Notify({ Title = "Refreshed", Content = "Monster list updated.", Duration = 3 })
    end
})

Tabs.Farm:AddDropdown("DropStandPos", {
    Title = "Stand Position",
    Values = {"Behind", "On Head", "Under"},
    Multi = false,
    Default = 1,
    Callback = function(v) _G.FarmPosition = v end
})

Tabs.Farm:AddParagraph({Title = "👑 Boss Farming", Content = "Prioritize specific bosses over normal monsters."})

Tabs.Farm:AddToggle("TogPriorityBoss", {
    Title = "Priority Boss",
    Default = false,
    Callback = function(v) _G.BossPriority = v end
})

local DropBosses = Tabs.Farm:AddDropdown("DropPriorityBosses", {
    Title = "Select Bosses",
    Description = "Select bosses to prioritize",
    Values = BossList,
    Multi = true,
    Default = {},
    Callback = function(v) _G.SelectedBosses = v end
})


-- ------------------------------------------
-- TELEPORT TAB
-- ------------------------------------------
Tabs.Teleport:AddParagraph({Title = "📍 Teleport Actions", Content = "Instantly move to specific NPCs or zones."})

Tabs.Teleport:AddDropdown("DropCategory", {
    Title = "Filter Category",
    Values = {"NPC", "Qi", "Training"},
    Multi = false,
    Default = 1,
    Callback = function(v)
        selectedCategory = v
        local tVals = FetchTargetsByCategory(selectedCategory)
        DropTarget:SetValues(tVals)
        DropTarget:SetValue(tVals[1])
    end
})

local DropTarget = Tabs.Teleport:AddDropdown("DropTarget", {
    Title = "Select Target",
    Values = initTargets,
    Multi = false,
    Default = 1,
    Callback = function(v) selectedTarget = v end
})

Tabs.Teleport:AddButton({
    Title = "🚀 Start Teleport",
    Callback = function()
        if _G.Teleporting then
            return Fluent:Notify({ Title = "Warning", Content = "Already teleporting in progress!", Duration = 3 })
        end
        if selectedTarget == "(None Found)" or selectedTarget == "" then
            return Fluent:Notify({ Title = "Error", Content = "Please select a target!", Duration = 3 })
        end

        local targetObj = nil
        if selectedCategory == "NPC" then
            local folder = workspace:FindFirstChild("NPCs")
            if folder then targetObj = folder:FindFirstChild(selectedTarget) end
        elseif selectedCategory == "Qi" then
            local tz = workspace:FindFirstChild("Training Zones")
            local folder = tz and tz:FindFirstChild("Qi")
            if folder then targetObj = folder:FindFirstChild(selectedTarget) end
        elseif selectedCategory == "Training" then
            local tz = workspace:FindFirstChild("Training Zones")
            local folder = tz and tz:FindFirstChild("Training")
            if folder then targetObj = folder:FindFirstChild(selectedTarget) end
        end

        if not targetObj then return Fluent:Notify({ Title = "Error", Content = "Target not found.", Duration = 3 }) end
        local targetCF = FindPosition(targetObj)
        if not targetCF then return Fluent:Notify({ Title = "Error", Content = "Can't get position.", Duration = 3 }) end

        local destination = selectedCategory == "NPC" and targetCF * CFrame.new(0, 0, 5) or targetCF
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            _G.AutoFarm = false
            StopFlying()
            _G.Teleporting = true
            Fluent:Notify({ Title = "Teleporting", Content = "Flying to " .. selectedTarget, Duration = 3 })
            task.spawn(function()
                while _G.Teleporting do
                    local chrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not chrp then break end
                    if (chrp.Position - destination.Position).Magnitude < 10 then
                        StopFlying()
                        _G.Teleporting = false
                        Fluent:Notify({ Title = "Arrived", Content = "Reached " .. selectedTarget, Duration = 3 })
                        break
                    end
                    FlyToTarget(destination)
                    task.wait(0.1)
                end
            end)
        end
    end
})

Tabs.Teleport:AddButton({
    Title = "🛑 Cancel Teleport",
    Callback = function()
        _G.Teleporting = false
        StopFlying()
        Fluent:Notify({ Title = "Cancelled", Content = "Teleport stopped.", Duration = 3 })
    end
})


-- SETTINGS TAB
Tabs.Settings:AddParagraph({Title = "⚙️ Adjustments", Content = "Tweak combat logic and server protections."})

Tabs.Settings:AddSlider("SldDistance", {
    Title = "Attack Distance",
    Description = "Offset distance from target",
    Default = 2,
    Min = -5,
    Max = 15,
    Rounding = 1,
    Callback = function(v) _G.AttackDistance = v end
})

Tabs.Settings:AddSlider("SldSpeed", {
    Title = "Fly Speed",
    Description = "Velocity across map",
    Default = 150,
    Min = 50,
    Max = 500,
    Rounding = 0,
    Callback = function(v) _G.FlySpeed = v end
})

Tabs.Settings:AddSlider("SldCooldown", {
    Title = "Attack Cooldown (ms)",
    Description = "Delay between hits based on weapon",
    Default = 18,
    Min = 10,
    Max = 100,
    Rounding = 0,
    Callback = function(v) BASE_COOLDOWN = v / 1000 end
})

Tabs.Settings:AddSlider("SldSafetyHP", {
    Title = "Safety HP %",
    Description = "Auto-stops farm if health is low",
    Default = 30,
    Min = 0,
    Max = 90,
    Rounding = 0,
    Callback = function(v) _G.MinHP = v end
})

Tabs.Settings:AddToggle("TogAntiAFK", { Title = "Anti-AFK", Default = true, Callback = function(v) _G.AntiAFK = v end })
Tabs.Settings:AddToggle("TogAntiPlayer", { Title = "Anti-Player", Default = false, Callback = function(v) _G.AntiPlayer = v end })

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ==========================================
-- [ 5. Target Finder & State Machine ]
-- ==========================================
local FarmState = "IDLE"
local CurrentTarget = nil

local function CalculateHitboxRadius(model)
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if root then return math.max(root.Size.X, root.Size.Z) / 2 end
    return 2 
end

local function FindBestEnemy()
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return nil end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local myPos = hrp.Position
    local bestMob = nil
    local bestMobScore = math.huge
    for _, e in ipairs(enemiesFolder:GetChildren()) do
        local hum = e:FindFirstChildOfClass("Humanoid")
        local root = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
        if hum and root and hum.Health > 0.1 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
            local dist = (myPos - root.Position).Magnitude
            
            local isSelectedBoss = _G.SelectedBosses and _G.SelectedBosses[e.Name]
            if _G.BossPriority and isSelectedBoss then
                if dist < bestMobScore then
                    bestMobScore = dist
                    bestMob = e
                end
            elseif not bestMob or not _G.BossPriority then
                if e.Name == _G.SelectedMonster and dist < bestMobScore then
                    bestMobScore = dist
                    bestMob = e
                end
            end
        end
    end
    return bestMob
end

local AntiFallPart = Instance.new("Part")
AntiFallPart.Name = "AutoFarmAntiFall"
AntiFallPart.Size = Vector3.new(500, 5, 500)
AntiFallPart.Anchored = true
AntiFallPart.Transparency = 1
AntiFallPart.CanCollide = true

task.spawn(function()
    while task.wait() do
        if not _G.AutoFarm then
            if FarmState ~= "IDLE" then
                FarmState = "IDLE"
                StopFlying()
                if AntiFallPart.Parent then AntiFallPart.Parent = nil end
            end
            continue
        end

        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not hum or not hrp then continue end
        
        if _G.MinHP > 0 then
            if hum.MaxHealth and hum.MaxHealth > 0 then
                local hpPct = (hum.Health / hum.MaxHealth) * 100
                if hpPct < _G.MinHP then
                    StopFlying()
                    _G.AutoFarm = false
                    if TogFarm then TogFarm:SetValue(false) end
                    Fluent:Notify({ Title = "Low HP!", Content = "Auto Farm stopped for safety.", Duration = 4 })
                    continue
                end
            end
        end

        local isValidTarget = CurrentTarget and CurrentTarget.Parent and CurrentTarget:FindFirstChildOfClass("Humanoid") and CurrentTarget:FindFirstChildOfClass("Humanoid").Health > 0.1
        
        if FarmState == "IDLE" or FarmState == "SEARCHING" or not isValidTarget then
            CurrentTarget = FindBestEnemy()
            if CurrentTarget then
                FarmState = "MOVING"
                if AntiFallPart.Parent then AntiFallPart.Parent = nil end
            else
                FarmState = "SEARCHING"
                StopFlying()
                if not AntiFallPart.Parent then AntiFallPart.Parent = workspace end
                AntiFallPart.CFrame = hrp.CFrame * CFrame.new(0, -5, 0)
            end
        elseif FarmState == "MOVING" or FarmState == "ATTACKING" then
            if AntiFallPart.Parent then AntiFallPart.Parent = nil end
            local targetRoot = CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget.PrimaryPart
            local targetHum = CurrentTarget:FindFirstChildOfClass("Humanoid")
            if not targetRoot or not targetHum then
                FarmState = "SEARCHING"
                continue
            end
            
            local rBox = math.clamp(CalculateHitboxRadius(CurrentTarget) * 0.6, 0, 8)
            local totalDist = rBox + _G.AttackDistance
            local offset
            if _G.FarmPosition == "On Head" then offset = CFrame.new(0, totalDist, 0)
            elseif _G.FarmPosition == "Under" then offset = CFrame.new(0, -totalDist, 0)
            else offset = CFrame.new(0, 0, totalDist) end
            
            local standCFrame = targetRoot.CFrame * offset
            local dist = (hrp.Position - standCFrame.Position).Magnitude
            
            if dist > 12 then
                FarmState = "MOVING"
                FlyToTarget(standCFrame)
            else
                FarmState = "ATTACKING"
                hrp.CFrame = standCFrame
                hrp.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
                hrp.AssemblyAngularVelocity = Vector3.zero
                FlyToTarget(standCFrame)
                AutoHit()
            end
        end
    end
end)

-- Background Services
game:GetService("Players").PlayerAdded:Connect(function(player)
    if _G.AntiPlayer then LocalPlayer:Kick("Anti-Player kick.") end
end)
task.spawn(function()
    while task.wait(5) do
        if _G.AntiPlayer and #game:GetService("Players"):GetPlayers() > 1 then
            LocalPlayer:Kick("Anti-Player kick.")
        end
    end
end)
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local flying = hrp and hrp:FindFirstChild("BypassPosition") ~= nil
    if (_G.AutoFarm or _G.Teleporting) and flying and char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end
end)
LocalPlayer.Idled:Connect(function()
    if _G.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end
end)

Fluent:Notify({ Title = "Inject Success", Content = "Fluent UI restored.", Duration = 3 })
SaveManager:LoadAutoloadConfig()
