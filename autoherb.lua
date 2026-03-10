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
-- [ 2. Compact UI Initialization ]
-- ==========================================
local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/cueshut/saves/main/compact"))()
local Window = library.init("Private Auto Farm", "v6.0", "AutoFarmConfig", nil, UDim2.new(0, 600, 0, 400))

local function Notify(title, desc)
    -- Compact UI doesn't have a built in notify we saw, but we can print or use Roblox StarterGui
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = title;
        Text = desc;
        Duration = 5;
    })
end

-- ==========================================
-- [ 3. Setup Tabs & Panels ]
-- ==========================================
local TabFarm = Window:AddTab("Farm")
local FarmPanelCombat = TabFarm:AddPanel("Combat")

local TabTeleport = Window:AddTab("Teleport")
local TeleportPanelTargets = TabTeleport:AddPanel("Targets")
local TeleportPanelActions = TabTeleport:AddPanel("Actions")

local TabSettings = Window:AddTab("Settings")
local SettingsPanelAdjust = TabSettings:AddPanel("Adjustments")
local SettingsPanelProtect = TabSettings:AddPanel("Protection")

-- (Tabs are initialized above)

-- (Farm Entities)
local function ScanMonsters()
    local names = {}
    local e = workspace:FindFirstChild("Enemies")
    if e then
        for _, obj in ipairs(e:GetChildren()) do
            if obj:FindFirstChild("Humanoid") and not obj.Name:lower():find("zanshi") then
                if not table.find(names, obj.Name) then table.insert(names, obj.Name) end
            end
        end
    end
    table.sort(names)
    return names
end

local function ScanNPCs()
    local names = {}
    local npcFolder = workspace:FindFirstChild("NPCs")
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            if npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head") or npc:IsA("BasePart") or npc:IsA("Model") then
                if not table.find(names, npc.Name) then table.insert(names, npc.Name) end
            end
        end
    end
    table.sort(names)
    return names
end

local function ScanZones(subFolder)
    local names = {}
    local tz = workspace:FindFirstChild("Training Zones")
    if tz then
        local folder = tz:FindFirstChild(subFolder)
        if folder then
            for _, zone in ipairs(folder:GetChildren()) do
                if not table.find(names, zone.Name) then table.insert(names, zone.Name) end
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
        local tool = char:FindFirstChild("Light") or LocalPlayer.Backpack:FindFirstChild("Light")
        if tool then
            if tool.Parent ~= char then char.Humanoid:EquipTool(tool) end
            tool:Activate()
            if tool:IsA("Tool") and ReplicatedStorage:FindFirstChild("RemoteEvents") then
                ReplicatedStorage.RemoteEvents.Attack:FireServer("Light", { ["RootPart"] = hrp })
            end
        end
    end)
end

-- ==========================================
-- [ 4. Build Components in UI ]
-- ==========================================
-- FARM TAB
FarmPanelCombat:AddToggle({title = "Start Auto Farm", checked = false, callback = function(v) _G.AutoFarm = v end})
FarmPanelCombat:AddToggle({title = "Priority Boss", checked = false, callback = function(v) _G.BossPriority = v end})

FarmPanelCombat:AddDropdown({title = "Stand Position", options = {"Behind", "On Head", "Under"}, default = "Behind", callback = function(v) _G.FarmPosition = v end})

local mVals = ScanMonsters()
if #mVals == 0 then mVals = {"(None)"} end

local mobDropdownData = {title = "Select Monster", options = mVals, default = mVals[1], callback = function(v) _G.SelectedMonster = v end}
FarmPanelCombat:AddDropdown(mobDropdownData) -- We cannot dynamically update options in this library easily without destroying it, so we rely on script restarts for new mobs or static lists.

FarmPanelCombat:AddButton({title = "Refresh Monsters (Check Console)", callback = function()
    local nm = ScanMonsters()
    if #nm == 0 then nm = {"(None)"} end
    print("New monsters found:", table.concat(nm, ", "))
    Notify("Look in F9", "Cannot update dropdown dynamically, please restart script or check F9 log.")
end})


-- TELEPORT TAB
local targetDropdownData = {title = "Target", options = initTargets, default = initTargets[1], callback = function(v) selectedTarget = v end}
TeleportPanelTargets:AddDropdown(targetDropdownData)

-- We cannot update options dynamically in Compact UI easily, so category switching is disabled.
TeleportPanelTargets:AddDropdown({title = "Category", options = {"NPC", "Qi", "Training"}, default = "NPC", callback = function(v)
    selectedCategory = v
    Notify("Note", "Category updated. Re-execute script to update visual target list.")
end})

TeleportPanelActions:AddButton({title = "🚀 Start Teleport", callback = function()
    if selectedTarget == "(None Found)" or selectedTarget == "" then
        Notify("Error", "Please select a target!")
        return
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

    if not targetObj then return Notify("Error", "Target not found.") end
    local targetCF = FindPosition(targetObj)
    if not targetCF then return Notify("Error", "Can't get position.") end

    local destination = selectedCategory == "NPC" and targetCF * CFrame.new(0, 0, 5) or targetCF
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        _G.AutoFarm = false
        StopFlying()
        _G.Teleporting = true
        Notify("Teleporting", "Flying to " .. selectedTarget)
        task.spawn(function()
            while _G.Teleporting do
                local chrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not chrp then break end
                if (chrp.Position - destination.Position).Magnitude < 10 then
                    StopFlying()
                    _G.Teleporting = false
                    Notify("Arrived", "Reached " .. selectedTarget)
                    break
                end
                FlyToTarget(destination)
                task.wait(0.1)
            end
        end)
    end
end})

TeleportPanelActions:AddButton({title = "🛑 Cancel Teleport", callback = function()
    _G.Teleporting = false
    StopFlying()
    Notify("Cancelled", "Teleport stopped.")
end})


-- SETTINGS TAB
SettingsPanelAdjust:AddSlider({title = "Attack Distance", min = -5, max = 15, default = 2, callback = function(v) _G.AttackDistance = v end})
SettingsPanelAdjust:AddSlider({title = "Fly Speed", min = 50, max = 500, default = 150, callback = function(v) _G.FlySpeed = v end})
SettingsPanelAdjust:AddSlider({title = "Attack Cooldown (ms)", min = 10, max = 100, default = 18, callback = function(v) BASE_COOLDOWN = v / 1000 end})
SettingsPanelAdjust:AddSlider({title = "Safety HP %", min = 0, max = 90, default = 30, callback = function(v) _G.MinHP = v end})

SettingsPanelProtect:AddToggle({title = "Anti-AFK", checked = true, callback = function(v) _G.AntiAFK = v end})
SettingsPanelProtect:AddToggle({title = "Anti-Player", checked = false, callback = function(v) _G.AntiPlayer = v end})

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
            if e.Name == _G.SelectedMonster then
                if dist < bestMobScore then
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
            local hpPct = (hum.Health / hum.MaxHealth) * 100
            if hpPct < _G.MinHP then
                StopFlying()
                _G.AutoFarm = false
                FarmState = "IDLE"
                UI.Notify("Low HP!", "Auto Farm stopped.")
                continue
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

Notify("Inject Success", "Compact UI loaded.")
