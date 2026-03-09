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

local BossList = {"Zanshi Bing Ren", "Zanshi Huo Ren"}

-- ==========================================
-- [ 2. UI Library ]
-- ==========================================
-- บันทึก ScreenGui ที่มีอยู่ก่อน Fluent โหลด (เพื่อหา Fluent GUI ทีหลัง)
local coreGui = game:GetService("CoreGui")
local preExistingGuis = {}
for _, v in ipairs(coreGui:GetChildren()) do
    preExistingGuis[v] = true
end

local Fluent         = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager    = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Soul Cultivation Hub",
    SubTitle = "Auto Farm | v6.0",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Farm     = Window:AddTab({ Title = "Farm",     Icon = "swords" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Misc     = Window:AddTab({ Title = "Misc",     Icon = "box" }),
    Settings = Window:AddTab({ Title = "Config",   Icon = "settings" }),
    Config   = Window:AddTab({ Title = "Setting",  Icon = "save" }),
}

-- ==========================================
-- [ 3. Entity Scanner ]
-- ==========================================
local function GetMonsterList()
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

-- ==========================================
-- [ 4. Farm Tab UI ]
-- ==========================================
Tabs.Farm:AddParagraph({ Title = "Farm Controls", Content = "Pick a target, choose a position, then start." })

local FarmToggle = Tabs.Farm:AddToggle("FarmToggle", { Title = "Auto Farm", Default = false })
FarmToggle:OnChanged(function(v) _G.AutoFarm = v end)

local PriorityToggle = Tabs.Farm:AddToggle("PriorityToggle", { Title = "Boss Priority", Default = false, Description = "Kill bosses before regular mobs." })
PriorityToggle:OnChanged(function(v) _G.BossPriority = v end)

local BossDropdown = Tabs.Farm:AddDropdown("BossDropdown", {
    Title = "Target Boss",
    Values = BossList,
    Multi = true,
    Default = {},
})
BossDropdown:OnChanged(function(v) _G.SelectedBosses = v end)

-- Monster Dropdown
local monsterValues = GetMonsterList()
if #monsterValues == 0 then monsterValues = {"(No Monsters Found)"} end

local MonsterDropdown = Tabs.Farm:AddDropdown("MonsterDropdown", {
    Title = "Target Monster",
    Values = monsterValues,
    Default = 1,
})
MonsterDropdown:OnChanged(function(v)
    if v ~= "(No Monsters Found)" then _G.SelectedMonster = v end
end)
if monsterValues[1] ~= "(No Monsters Found)" then
    _G.SelectedMonster = monsterValues[1]
end

local PositionDropdown = Tabs.Farm:AddDropdown("FarmPosition", {
    Title = "Stand Position",
    Description = "Where to stand while attacking.",
    Values = {"Behind", "On Head", "Under"},
    Default = 1,
})
PositionDropdown:OnChanged(function(v) _G.FarmPosition = v end)

Tabs.Farm:AddButton({
    Title = "Refresh Targets",
    Description = "Re-scan all enemies in the area.",
    Callback = function()
        local newList = GetMonsterList()
        if #newList == 0 then newList = {"(No Monsters Found)"} end
        pcall(function() MonsterDropdown:SetValue(newList[1]) end)
        if newList[1] ~= "(No Monsters Found)" then
            _G.SelectedMonster = newList[1]
        end
        Fluent:Notify({
            Title = "Refreshed",
            Content = "Found " .. #newList .. " monster type(s).\nTarget: " .. _G.SelectedMonster,
            Duration = 3
        })
    end
})

-- ==========================================
-- ==========================================
local FlySlider = Tabs.Settings:AddSlider("FlySpeed", {
    Title = "Fly Speed",
    Default = 150, Min = 50, Max = 500, Rounding = 0
})
FlySlider:OnChanged(function(v) _G.FlySpeed = v end)

local AttackSlider = Tabs.Settings:AddSlider("AttackRate", {
    Title = "Attack Speed (ms)",
    Description = "Higher = slower = safer",
    Default = 18, Min = 10, Max = 100, Rounding = 0
})

local HPSlider = Tabs.Settings:AddSlider("MinHP", {
    Title = "Safety HP (%)",
    Description = "Stop farming below this HP. Set 0 to disable.",
    Default = 30, Min = 0, Max = 90, Rounding = 0
})
HPSlider:OnChanged(function(v) _G.MinHP = v end)

local AntiAFKToggle = Tabs.Misc:AddToggle("AntiAFK", { Title = "Anti-AFK", Default = true })

local AntiPlayerToggle = Tabs.Misc:AddToggle("AntiPlayer", { 
    Title = "Anti-Player", 
    Description = "Auto-kick yourself if anyone else joins the server to avoid admins.",
    Default = false 
})

-- ==========================================
-- [ 6. Teleport Tab ]
-- ==========================================
_G.Teleporting = false

-- สแกน NPC
local function GetNPCList()
    local names = {}
    local npcFolder = workspace:FindFirstChild("NPCs")
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            if npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head") or npc:IsA("BasePart") or npc:IsA("Model") then
                if not table.find(names, npc.Name) then
                    table.insert(names, npc.Name)
                end
            end
        end
    end
    table.sort(names)
    return names
end

-- สแกน Training Zones
local function GetZoneList(subFolder)
    local names = {}
    local tz = workspace:FindFirstChild("Training Zones")
    if tz then
        local folder = tz:FindFirstChild(subFolder)
        if folder then
            for _, zone in ipairs(folder:GetChildren()) do
                if not table.find(names, zone.Name) then
                    table.insert(names, zone.Name)
                end
            end
        end
    end
    table.sort(names)
    return names
end

-- หาตำแหน่งของ object (รองรับ Model และ BasePart)
local function GetPosition(obj)
    if obj:IsA("Model") then
        local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Head")
        if hrp then return hrp.CFrame end
        if obj.PrimaryPart then return obj.PrimaryPart.CFrame end
        -- fallback: หา BasePart แรก
        for _, child in ipairs(obj:GetDescendants()) do
            if child:IsA("BasePart") then return child.CFrame end
        end
    elseif obj:IsA("BasePart") then
        return obj.CFrame
    end
    return nil
end

Tabs.Teleport:AddParagraph({ Title = "Teleport", Content = "เลือกเป้าหมายแล้วกด Teleport เพื่อบินไป" })

-- === NPC Section ===
local npcList = GetNPCList()
if #npcList == 0 then npcList = {"(No NPCs Found)"} end
local selectedNPC = npcList[1]

local NPCDropdown = Tabs.Teleport:AddDropdown("NPCDropdown", {
    Title = "NPC",
    Values = npcList,
    Default = 1,
})
NPCDropdown:OnChanged(function(v) selectedNPC = v end)

Tabs.Teleport:AddButton({
    Title = "Teleport to NPC",
    Callback = function()
        if selectedNPC == "(No NPCs Found)" then return end
        local npcFolder = workspace:FindFirstChild("NPCs")
        if not npcFolder then return end
        local npc = npcFolder:FindFirstChild(selectedNPC)
        if not npc then
            Fluent:Notify({ Title = "Error", Content = "NPC '" .. selectedNPC .. "' not found.", Duration = 3 })
            return
        end
        local targetCF = GetPosition(npc)
        if not targetCF then return end
        -- บินไปใกล้ NPC (offset ด้านหน้า)
        local destination = targetCF * CFrame.new(0, 0, 5)
        _G.Teleporting = true
        Fluent:Notify({ Title = "Teleporting", Content = "Flying to " .. selectedNPC .. "...", Duration = 3 })
        task.spawn(function()
            while _G.Teleporting do
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then break end
                local dist = (hrp.Position - destination.Position).Magnitude
                if dist < 10 then
                    StopPhysicsFly()
                    _G.Teleporting = false
                    Fluent:Notify({ Title = "Arrived", Content = "Reached " .. selectedNPC, Duration = 3 })
                    break
                end
                PhysicsFlyTo(destination)
                task.wait(0.1)
            end
        end)
    end
})

-- === Qi Zone Section ===
local qiList = GetZoneList("Qi")
if #qiList == 0 then qiList = {"(No Qi Zones Found)"} end
local selectedQi = qiList[1]

local QiDropdown = Tabs.Teleport:AddDropdown("QiDropdown", {
    Title = "Qi Zone",
    Values = qiList,
    Default = 1,
})
QiDropdown:OnChanged(function(v) selectedQi = v end)

Tabs.Teleport:AddButton({
    Title = "Teleport to Qi Zone",
    Callback = function()
        if selectedQi == "(No Qi Zones Found)" then return end
        local tz = workspace:FindFirstChild("Training Zones")
        local qiFolder = tz and tz:FindFirstChild("Qi")
        if not qiFolder then return end
        local zone = qiFolder:FindFirstChild(selectedQi)
        if not zone then
            Fluent:Notify({ Title = "Error", Content = "Zone '" .. selectedQi .. "' not found.", Duration = 3 })
            return
        end
        local targetCF = GetPosition(zone)
        if not targetCF then return end
        _G.Teleporting = true
        Fluent:Notify({ Title = "Teleporting", Content = "Flying to Qi: " .. selectedQi .. "...", Duration = 3 })
        task.spawn(function()
            while _G.Teleporting do
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then break end
                local dist = (hrp.Position - targetCF.Position).Magnitude
                if dist < 10 then
                    StopPhysicsFly()
                    _G.Teleporting = false
                    Fluent:Notify({ Title = "Arrived", Content = "Reached Qi: " .. selectedQi, Duration = 3 })
                    break
                end
                PhysicsFlyTo(targetCF)
                task.wait(0.1)
            end
        end)
    end
})

-- === Training Zone Section ===
local trainList = GetZoneList("Training")
if #trainList == 0 then trainList = {"(No Training Zones Found)"} end
local selectedTrain = trainList[1]

local TrainDropdown = Tabs.Teleport:AddDropdown("TrainDropdown", {
    Title = "Training Zone",
    Values = trainList,
    Default = 1,
})
TrainDropdown:OnChanged(function(v) selectedTrain = v end)

Tabs.Teleport:AddButton({
    Title = "Teleport to Training Zone",
    Callback = function()
        if selectedTrain == "(No Training Zones Found)" then return end
        local tz = workspace:FindFirstChild("Training Zones")
        local trainFolder = tz and tz:FindFirstChild("Training")
        if not trainFolder then return end
        local zone = trainFolder:FindFirstChild(selectedTrain)
        if not zone then
            Fluent:Notify({ Title = "Error", Content = "Zone '" .. selectedTrain .. "' not found.", Duration = 3 })
            return
        end
        local targetCF = GetPosition(zone)
        if not targetCF then return end
        _G.Teleporting = true
        Fluent:Notify({ Title = "Teleporting", Content = "Flying to Train: " .. selectedTrain .. "...", Duration = 3 })
        task.spawn(function()
            while _G.Teleporting do
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then break end
                local dist = (hrp.Position - targetCF.Position).Magnitude
                if dist < 10 then
                    StopPhysicsFly()
                    _G.Teleporting = false
                    Fluent:Notify({ Title = "Arrived", Content = "Reached Train: " .. selectedTrain, Duration = 3 })
                    break
                end
                PhysicsFlyTo(targetCF)
                task.wait(0.1)
            end
        end)
    end
})

-- === ปุ่มหยุด Teleport + Refresh ===
Tabs.Teleport:AddButton({
    Title = "Stop Teleport",
    Description = "หยุดบินทันที",
    Callback = function()
        _G.Teleporting = false
        StopPhysicsFly()
        Fluent:Notify({ Title = "Stopped", Content = "Teleport cancelled.", Duration = 2 })
    end
})

Tabs.Teleport:AddButton({
    Title = "Refresh All Lists",
    Description = "สแกนหา NPC และ Zone ใหม่",
    Callback = function()
        local newNPC = GetNPCList()
        if #newNPC == 0 then newNPC = {"(No NPCs Found)"} end
        pcall(function() NPCDropdown:SetValues(newNPC) NPCDropdown:SetValue(newNPC[1]) end)
        selectedNPC = newNPC[1]

        local newQi = GetZoneList("Qi")
        if #newQi == 0 then newQi = {"(No Qi Zones Found)"} end
        pcall(function() QiDropdown:SetValues(newQi) QiDropdown:SetValue(newQi[1]) end)
        selectedQi = newQi[1]

        local newTrain = GetZoneList("Training")
        if #newTrain == 0 then newTrain = {"(No Training Zones Found)"} end
        pcall(function() TrainDropdown:SetValues(newTrain) TrainDropdown:SetValue(newTrain[1]) end)
        selectedTrain = newTrain[1]

        Fluent:Notify({
            Title = "Refreshed",
            Content = "NPCs: " .. #newNPC .. " | Qi: " .. #newQi .. " | Train: " .. #newTrain,
            Duration = 3
        })
    end
})



-- ==========================================
-- [ 7. Anti-Cheat Bypass Engine ]
-- ==========================================
local BASE_COOLDOWN = 0.18
local JITTER_RANGE  = 0.08
AttackSlider:OnChanged(function(v) BASE_COOLDOWN = v / 1000 end)

local function StopPhysicsFly()
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

local function PhysicsFlyTo(targetCFrame)
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
end

local lastAttackTime = 0
local function SafeAttack()
    local now = tick()
    local cooldown = BASE_COOLDOWN + math.random() * JITTER_RANGE
    if now - lastAttackTime < cooldown then return end
    lastAttackTime = now

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hrp then return end

    pcall(function()
        local tool = char:FindFirstChild("Light") or LocalPlayer.Backpack:FindFirstChild("Light")
        if not tool then return end
        LocalPlayer.PlayerGui.Inventory.Manager.Toolbar:FireServer(1, tool)
        ReplicatedStorage.RemoteEvents.Attack:FireServer("Light", { ["RootPart"] = hrp })
    end)
end

-- ==========================================
-- [ 8. Target Finder (Boss Priority Fixed) ]
-- ==========================================
local function GetCurrentTarget()
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    -- Boss Priority: ถ้าเปิด BossPriority จะหาบอสก่อน
    if _G.BossPriority then
        for bossName, enabled in pairs(_G.SelectedBosses) do
            if enabled then
                local b = enemies:FindFirstChild(bossName)
                if b and b:FindFirstChild("Humanoid") and b.Humanoid.Health > 0
                   and b:FindFirstChild("HumanoidRootPart") then
                    return b
                end
            end
        end
        -- ถ้าบอสตาย/ไม่มี ก็ fall through ไปหามอนปกติ
    end

    -- หามอนที่เลือก
    if _G.SelectedMonster == "" then return nil end
    for _, e in ipairs(enemies:GetChildren()) do
        if e.Name == _G.SelectedMonster then
            local hum = e:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 and e:FindFirstChild("HumanoidRootPart") then
                return e
            end
        end
    end
    return nil
end

-- ==========================================
-- [ 9. Kill Detector ]
-- ==========================================
local KillCount = 0
local lastTargetHP = math.huge
task.spawn(function()
    while task.wait(0.2) do
        local target = GetCurrentTarget()
        if target then
            local hum = target:FindFirstChild("Humanoid")
            if hum then
                if hum.Health <= 0 and lastTargetHP > 0 then
                    KillCount = KillCount + 1
                end
                lastTargetHP = hum.Health
            end
        else
            lastTargetHP = math.huge
        end
    end
end)

-- ==========================================
-- [ 10. Main Farm Loop ]
-- ==========================================
task.spawn(function()
    while task.wait(0.1 + math.random() * 0.05) do
        if not _G.AutoFarm then
            StopPhysicsFly()
        else
            -- HP Safety Check
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and _G.MinHP > 0 then
                local hpPct = hum.Health / hum.MaxHealth * 100
                if hpPct < _G.MinHP then
                    StopPhysicsFly()
                    if _G.AutoFarm then
                        _G.AutoFarm = false
                        pcall(function() FarmToggle:SetValue(false) end)
                        Fluent:Notify({
                            Title = "Warning: Low HP!",
                            Content = "HP at " .. math.floor(hpPct) .. "% — Auto Farm stopped for safety.",
                            Duration = 5
                        })
                    end
                    continue
                end
            end

            local target = GetCurrentTarget()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            if target and hrp then
                local targetRoot = target.HumanoidRootPart

                -- คำนวณ standPos ตามตำแหน่งที่เลือก
                local offset
                if _G.FarmPosition == "On Head" then
                    offset = CFrame.new(0, 4, 0)
                elseif _G.FarmPosition == "Under" then
                    offset = CFrame.new(0, -3, 0)
                else
                    offset = CFrame.new(0, 0, 3)  -- Behind (default)
                end
                local standPos = targetRoot.CFrame * offset
                local distToTarget = (hrp.Position - targetRoot.Position).Magnitude

                if distToTarget > 12 then
                    PhysicsFlyTo(standPos)
                else
                    StopPhysicsFly()
                    hrp.CFrame = standPos
                    SafeAttack()
                end
            else
                StopPhysicsFly()
            end
        end
    end
end)

-- ==========================================
-- [ 11. Background Services ]
-- ==========================================
-- Anti-Player (Kick if someone else joins)
game:GetService("Players").PlayerAdded:Connect(function(player)
    if Tabs.Misc:GetToggle("AntiPlayer") and Tabs.Misc:GetToggle("AntiPlayer").Value then
        LocalPlayer:Kick("Anti-Player triggered: " .. player.Name .. " joined the server.")
    end
end)
task.spawn(function()
    while task.wait(5) do
        if Tabs.Misc:GetToggle("AntiPlayer") and Tabs.Misc:GetToggle("AntiPlayer").Value then
            if #game:GetService("Players"):GetPlayers() > 1 then
                LocalPlayer:Kick("Anti-Player triggered: Someone else is in the server.")
            end
        end
    end
end)

-- Safe Noclip (เฉพาะตอน Physics Fly)
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local flying = hrp and hrp:FindFirstChild("BypassPosition") ~= nil
    if _G.AutoFarm and flying and char then
        for _, p in ipairs(char:GetChildren()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
end)

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    if Fluent.Options.AntiAFK and Fluent.Options.AntiAFK.Value then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end
end)

-- ==========================================
-- [ 12. Save Manager ]
-- ==========================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("SoulCultivationHub")
SaveManager:SetFolder("SoulCultivationHub/Configs")
InterfaceManager:BuildInterfaceSection(Tabs.Config)
SaveManager:BuildConfigSection(Tabs.Config)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

Fluent:Notify({
    Title = "Soul Cultivation Hub",
    Content = "Loaded successfully! Found " .. #monsterValues .. " monster type(s).",
    Duration = 4
})

-- ==========================================
-- [ Floating Toggle Icon (ใช้ Window:Minimize) ]
-- ==========================================
local iconGui = Instance.new("ScreenGui")
iconGui.Name         = "SCH_Icon"
iconGui.ResetOnSpawn = false
iconGui.DisplayOrder = 9999
iconGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() iconGui.Parent = coreGui end)
if not iconGui.Parent or iconGui.Parent ~= coreGui then
    iconGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local icon = Instance.new("TextButton")
icon.Size             = UDim2.fromOffset(48, 48)
icon.Position         = UDim2.new(0, 16, 0.5, -24)
icon.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
icon.Text             = "HUB"
icon.TextColor3       = Color3.fromRGB(0, 200, 255)
icon.Font             = Enum.Font.GothamBold
icon.TextSize         = 13
icon.BorderSizePixel  = 0
icon.ZIndex           = 9999
icon.Parent           = iconGui
Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

local stroke = Instance.new("UIStroke", icon)
stroke.Color     = Color3.fromRGB(0, 200, 255)
stroke.Thickness = 2

local isDragging = false
local dragStart, iconStartPos

icon.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        isDragging   = false
        dragStart    = input.Position
        iconStartPos = icon.Position

        local conn
        conn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                if conn then conn:Disconnect() end
                dragStart = nil
                return
            end
            if dragStart then
                local delta = input.Position - dragStart
                if delta.Magnitude > 6 then
                    isDragging = true
                    icon.Position = UDim2.new(
                        iconStartPos.X.Scale, iconStartPos.X.Offset + delta.X,
                        iconStartPos.Y.Scale, iconStartPos.Y.Offset + delta.Y
                    )
                end
            end
        end)
    end
end)

local function ToggleUI()
    if isDragging then
        isDragging = false
        return
    end

    -- ใช้ Fluent built-in API โดยตรง
    -- Window:Minimize() จะ toggle Window.Minimized และ Window.Root.Visible
    Window:Minimize()

    -- อัพเดต icon color ตามสถานะ
    local isOpen = not Window.Minimized
    local activeColor = Color3.fromRGB(0, 200, 255)
    local dimColor    = Color3.fromRGB(80, 80, 80)
    stroke.Color    = isOpen and activeColor or dimColor
    icon.TextColor3 = isOpen and activeColor or dimColor
end

icon.MouseButton1Up:Connect(ToggleUI)
icon.TouchTap:Connect(ToggleUI)
