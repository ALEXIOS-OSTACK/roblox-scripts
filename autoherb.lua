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
-- [ 2. UI Library ]
-- ==========================================
local coreGui = game:GetService("CoreGui")
local preExistingGuis = {}
for _, v in ipairs(coreGui:GetChildren()) do
    preExistingGuis[v] = true
end

local MacLib = loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.lua"))()

local Window = MacLib:Window({
	Title = "Private Auto Farm",
	Subtitle = "v6.0",
	Size = UDim2.fromOffset(868, 650),
	DragStyle = 1,
	DisabledWindowControls = {},
	ShowUserInfo = true,
	Keybind = Enum.KeyCode.RightControl,
	AcrylicBlur = true,
})

local TabGroup1 = Window:TabGroup()
local Tabs = {
    Farm     = TabGroup1:Tab({ Name = "Farm",     Icon = "rbxassetid://11963332463" }),
    Teleport = TabGroup1:Tab({ Name = "Teleport", Icon = "rbxassetid://11963332463" }),
    Settings = TabGroup1:Tab({ Name = "Settings", Icon = "rbxassetid://11963332463" }),
    Misc     = TabGroup1:Tab({ Name = "Misc",     Icon = "rbxassetid://11963332463" }),
}

-- ==========================================
-- [ 3. Entity Scanner ]
-- ==========================================
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

-- ==========================================
-- [ 4. Physics Fly Engine ]
-- ==========================================
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
    
    -- บังคับปิดชนกำแพงทันทีในจังหวะบิน
    for _, p in ipairs(LocalPlayer.Character:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            p.CanCollide = false
        end
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
            if tool.Parent ~= char then
                char.Humanoid:EquipTool(tool)
            end
            tool:Activate()
            
            -- Normal single target attack
            if tool:IsA("Tool") and ReplicatedStorage:FindFirstChild("RemoteEvents") then
                ReplicatedStorage.RemoteEvents.Attack:FireServer("Light", { ["RootPart"] = hrp })
            end
        end
    end)
end

-- ==========================================
-- [ 5. Farm Tab UI ]
-- ==========================================
local FarmSection = Tabs.Farm:Section({ Name = "🔥 การโจมตี (Combat)" })

FarmSection:Toggle({ 
    Name = "เริ่มฟาร์มอัตโนมัติ (Start Auto Farm)", 
    Description = "เปิด/ปิด ระบบโจมตีอัตโนมัติ",
    Default = false,
    Callback = function(v) _G.AutoFarm = v end 
})

FarmSection:Toggle({ 
    Name = "ตีบอสก่อนเป็นอันดับแรก (Priority Boss)", 
    Description = "ถ้ามีบอสเกิด สคริปต์จะพุ่งไปตีบอสก่อนมอนสเตอร์ปกติเสมอ", 
    Default = false,
    Callback = function(v) _G.BossPriority = v end 
})

FarmSection:Dropdown({
    Name = "เลือกบอสที่ต้องการฟาร์ม (Select Bosses)",
    Options = BossList,
    Multi = true,
    Default = {},
    Callback = function(v) _G.SelectedBosses = v end
})

-- Monster Dropdown
local monsterValues = ScanMonsters()
if #monsterValues == 0 then monsterValues = {"(ไม่มีมอนสเตอร์โผล่มา)"} end

local TargetMobDrop = FarmSection:Dropdown({
    Name = "เลือกมอนสเตอร์ (Select Monster)",
    Options = monsterValues,
    Default = monsterValues[1],
    Callback = function(v)
        if v ~= "(ไม่มีมอนสเตอร์โผล่มา)" then _G.SelectedMonster = v end
    end
})

FarmSection:Dropdown({
    Name = "จุดยืนตอนโจมตี (Stand Position)",
    Description = "ตำแหน่งที่คุณจะยืนเกาะมอนสเตอร์เวลาฟาร์ม (แนะนำ: ด้านหลัง)",
    Options = {"Behind", "On Head", "Under"},
    Default = "Behind",
    Callback = function(v) _G.FarmPosition = v end
})

FarmSection:Button({
    Name = "อัปเดตรายชื่อมอนสเตอร์ (Refresh List)",
    Callback = function()
        local newList = ScanMonsters()
        if #newList == 0 then newList = {"(ไม่มีมอนสเตอร์โผล่มา)"} end
        if newList[1] ~= "(ไม่มีมอนสเตอร์โผล่มา)" then
            _G.SelectedMonster = newList[1]
        end
        pcall(function() TargetMobDrop:SetOptions(newList) end)
        MacLib:Notify({
            Title = "อัปเดตเรียบร้อย!",
            Description = "พบมอนสเตอร์ " .. #newList .. " ตัว (โปรดเลือกในเมนูด้านบนใหม่)",
            Time = 3
        })
    end
})

-- ==========================================
-- [ 6. Teleport Tab ]
-- ==========================================
-- Scan NPCs
local function ScanNPCs()
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

-- Scan Training Zones
local function ScanZones(subFolder)
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

-- Get position of object (supports Model and BasePart)
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

local TeleportSection = Tabs.Teleport:Section({ Name = "📍 จุดวาร์ป (Teleporting)" })

TargetDropdown = TeleportSection:Dropdown({
    Name = "รายชื่อปลายทาง (Target)",
    Options = initTargets,
    Default = initTargets[1],
    Callback = function(v) selectedTarget = v end,
})

TeleportSection:Dropdown({
    Name = "หมวดหมู่การวาร์ป (Category)",
    Description = "เลือกประเภทของสิ่งที่คุณอยากวาร์ปไปหา",
    Options = {"NPC", "Qi", "Training"},
    Default = "NPC",
    Callback = function(v)
        selectedCategory = v
        RefreshTargetList()
    end,
})

TeleportSection:Button({
    Name = "🚀 วาร์ปเลย (Start Teleport)",
    Callback = function()
        if selectedTarget == "(None Found)" or selectedTarget == "" then
            MacLib:Notify({ Title = "ข้อผิดพลาด", Description = "โปรดเลือกเป้าหมายก่อนครับ!", Time = 2 })
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

        if not targetObj then
            MacLib:Notify({ Title = "Error", Description = "'" .. selectedTarget .. "' not found.", Time = 3 })
            return
        end

        local targetCF = FindPosition(targetObj)
        if not targetCF then
            MacLib:Notify({ Title = "Error", Description = "Can't get position.", Time = 3 })
            return
        end

        local destination = selectedCategory == "NPC"
            and targetCF * CFrame.new(0, 0, 5)
            or targetCF

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            if _G.AutoFarm then
                _G.AutoFarm = false
            end
            StopFlying()
            
            _G.Teleporting = true
            MacLib:Notify({
                Title = "Teleporting",
                Description = "Flying to " .. selectedTarget .. "...",
                Time = 3
            })

            task.spawn(function()
                while _G.Teleporting do
                    local currentHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not currentHrp then break end
                    local dist = (currentHrp.Position - destination.Position).Magnitude
                    if dist < 10 then
                        StopFlying()
                        _G.Teleporting = false
                        MacLib:Notify({ Title = "Arrived", Description = "Reached " .. selectedTarget, Time = 3 })
                        break
                    end
                    FlyToTarget(destination)
                    task.wait(0.1)
                end
            end)
        end
    end
})

-- Stop Teleport
TeleportSection:Button({
    Name = "🛑 หยุดวาร์ป (Cancel)",
    Callback = function()
        _G.Teleporting = false
        StopFlying()
        MacLib:Notify({ Title = "หยุดเรียบร้อย", Description = "ยกเลิกการวาร์ปแล้วครับ", Time = 2 })
    end
})

-- Refresh Targets
TeleportSection:Button({
    Name = "Refresh Targets",
    Callback = function()
        RefreshTargetList()
        local targets = FetchTargetsByCategory(selectedCategory)
        pcall(function() TargetDropdown:SetOptions(targets) end)
        MacLib:Notify({
            Title = "Refreshed",
            Description = selectedCategory .. ": " .. #targets .. " target(s) found.",
            Time = 3
        })
    end
})

-- ==========================================
-- [ 7. Settings Tab ]
-- ==========================================
local SettingsSection = Tabs.Settings:Section({ Name = "⏱️ ความเร็วและเกราะป้องกัน" })

SettingsSection:Slider({
    Name = "ระยะเข้าทำ (Attack Distance)",
    Description = "ถ้าตีบอสไม่โดนหรือบินห่างเกินไป ให้ปรับลดเลขลงมา (หน่วย: Studs)",
    Default = 2,
    Minimum = -5,
    Maximum = 15,
    DisplayMethod = "Value",
    Callback = function(v) _G.AttackDistance = v end
})

SettingsSection:Slider({
    Name = "ความเร็วการบิน (Fly Speed)",
    Default = 150,
    Minimum = 50,
    Maximum = 500,
    DisplayMethod = "Value",
    Callback = function(v) _G.FlySpeed = v end
})

SettingsSection:Slider({
    Name = "ความเร็วการโจมตี (Attack Cooldown Delay)",
    Description = "ยิ่งเลขเยอะยิ่งตีช้า แต่จะเนียนตา ลดโอกาสโดนเกมแบน (หน่วย: มิลลิวินาที)",
    Default = 18,
    Minimum = 10,
    Maximum = 100,
    DisplayMethod = "Value",
    Callback = function(v) BASE_COOLDOWN = v / 1000 end
})

SettingsSection:Slider({
    Name = "เลือดฉุกเฉิน Safety HP (%)",
    Description = "ถ้าเลือดต่ำกว่าเปอร์เซ็นต์นี้ บอทจะหยุดฟาร์มทันทีเพื่อป้องกันตาย (ปรับเป็น 0 เพื่อปิด)",
    Default = 30,
    Minimum = 0,
    Maximum = 90,
    DisplayMethod = "Value",
    Callback = function(v) _G.MinHP = v end
})

-- ==========================================
-- [ 8. Misc Tab ]
-- ==========================================
local MiscSection = Tabs.Misc:Section({ Name = "🛡️ ฟังก์ชันป้องกันเซิฟเวอร์" })

MiscSection:Toggle({ 
    Name = "ป้องกันการ AFK (Anti-AFK)", 
    Description = "คลิกเมาส์อัตโนมัติป้องกันเซิร์ฟเวอร์เตะคุณออก",
    Default = true, 
    Callback = function(v) _G.AntiAFK = v end 
})

MiscSection:Toggle({ 
    Name = "ระบบเตะผู้เล่นอื่น (Anti-Player)", 
    Description = "เตะตัวเองออกจากเซิฟเวอร์ทันทีถ้ามีคนอื่นจอยเข้ามา (เหมาะสำหรับฟาร์มเซิฟ V แบบลับๆ)",
    Default = false,
    Callback = function(v) _G.AntiPlayer = v end
})

-- ==========================================
-- [ 9. Target Finder & State Machine (Premium) ]
-- ==========================================
local FarmState = "IDLE" -- IDLE, SEARCHING, MOVING, ATTACKING
local CurrentTarget = nil

local function CalculateHitboxRadius(model)
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if root then
        return math.max(root.Size.X, root.Size.Z) / 2
    end
    return 2 -- fallback
end

local function FindBestEnemy()
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return nil end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local myPos = hrp.Position
    local bestBoss = nil
    local bestBossScore = math.huge
    local bestMob = nil
    local bestMobScore = math.huge
    
    for _, e in ipairs(enemiesFolder:GetChildren()) do
        local hum = e:FindFirstChildOfClass("Humanoid")
        local root = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
        if hum and root and hum.Health > 0.1 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
            local dist = (myPos - root.Position).Magnitude
            if _G.BossPriority and _G.SelectedBosses[e.Name] then
                if dist < bestBossScore then
                    bestBossScore = dist
                    bestBoss = e
                end
            elseif e.Name == _G.SelectedMonster then
                if dist < bestMobScore then
                    bestMobScore = dist
                    bestMob = e
                end
            end
        end
    end
    
    return bestBoss or bestMob
end

local FarmState = "IDLE"
local CurrentTarget = nil

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
                StopPhysicsFly()
                if AntiFallPart.Parent then AntiFallPart.Parent = nil end
            end
            continue
        end

        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not hum or not hrp then continue end
        
        -- HP Safety Check
        if _G.MinHP > 0 then
            local hpPct = (hum.Health / hum.MaxHealth) * 100
            if hpPct < _G.MinHP then
                StopFlying()
                _G.AutoFarm = false
                FarmState = "IDLE"
                MacLib:Notify({ Title = "Warning: Low HP!", Description = "Auto Farm stopped.", Time = 5 })
                continue
            end
        end

        local isValidTarget = CurrentTarget and CurrentTarget.Parent and CurrentTarget:FindFirstChildOfClass("Humanoid") and CurrentTarget:FindFirstChildOfClass("Humanoid").Health > 0.1
        
        if FarmState == "IDLE" or FarmState == "SEARCHING" or not isValidTarget then
            CurrentTarget = FindBestEnemy()
            if CurrentTarget then
                FarmState = "MOVING"
                if AntiFallPart.Parent then AntiFallPart.Parent = nil end
                if CurrentTarget ~= _G.LastNotifiedTarget then
                    _G.LastNotifiedTarget = CurrentTarget
                    MacLib:Notify({ Title = "Target Locked", Description = "Now engaging: " .. CurrentTarget.Name, Time = 2 })
                end
            else
                FarmState = "SEARCHING"
                StopFlying()
                
                -- Anti-Fall mechanism
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
            
            -- Dynamic BoundingBox Distance
            -- จำกัดขนาดไม่ให้กว้างเกินไปเวลาเจอบอสที่โมเดลใหญ่
            local rBox = math.clamp(CalculateHitboxRadius(CurrentTarget) * 0.6, 0, 8)
            local totalDist = rBox + _G.AttackDistance
            
            local offset
            if _G.FarmPosition == "On Head" then
                offset = CFrame.new(0, totalDist, 0)
            elseif _G.FarmPosition == "Under" then
                offset = CFrame.new(0, -totalDist, 0)
            else
                -- default Behind
                offset = CFrame.new(0, 0, totalDist)
            end
            
            local standCFrame = targetRoot.CFrame * offset
            local dist = (hrp.Position - standCFrame.Position).Magnitude
            
            if dist > 12 then
                FarmState = "MOVING"
                FlyToTarget(standCFrame)
            else
                FarmState = "ATTACKING"
                
                -- Hard lock velocity when attacking & push down slightly to prevent floating
                hrp.CFrame = standCFrame
                hrp.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
                hrp.AssemblyAngularVelocity = Vector3.zero
                
                FlyToTarget(standCFrame) -- Maintain bypass anchor
                AutoHit()
            end
        end
    end
end)

-- ==========================================
-- [ 12. Background Services ]
-- ==========================================
-- Anti-Player (Kick if someone else joins)
game:GetService("Players").PlayerAdded:Connect(function(player)
    if _G.AntiPlayer then
        LocalPlayer:Kick("Anti-Player triggered: " .. player.Name .. " joined the server.")
    end
end)
task.spawn(function()
    while task.wait(5) do
        if _G.AntiPlayer then
            if #game:GetService("Players"):GetPlayers() > 1 then
                LocalPlayer:Kick("Anti-Player triggered: Someone else is in the server.")
            end
        end
    end
end)

-- Safe Noclip (only during Physics Fly)
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local flying = hrp and hrp:FindFirstChild("BypassPosition") ~= nil
    
    if (_G.AutoFarm or _G.Teleporting) and flying and char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                p.CanCollide = false
            end
        end
    end
end)

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    if _G.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end
end)

-- ==========================================
-- [ Finish Execution ]
-- ==========================================
MacLib:Notify({
    Title = "Soul Cultivation Hub",
    Description = "Loaded successfully! Maclib injected.",
    Time = 4
})
