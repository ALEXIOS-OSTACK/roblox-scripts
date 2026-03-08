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
_G.AutoCollect   = false

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
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    Config   = Window:AddTab({ Title = "Save",     Icon = "save" }),
    Misc     = Window:AddTab({ Title = "Misc",     Icon = "box" }),
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

-- Auto Collect Treasure Toggle
local CollectToggle = Tabs.Farm:AddToggle("CollectToggle", {
    Title = "Auto Collect Treasure",
    Description = "Auto-collect all treasures in workspace.Treasures.",
    Default = false
})
CollectToggle:OnChanged(function(v) _G.AutoCollect = v end)

-- ==========================================
-- [ 5. Auto Collect Loop ]
-- ==========================================
task.spawn(function()
    while task.wait(0.5) do
        if not _G.AutoCollect then continue end

        local treasuresFolder = workspace:FindFirstChild("Treasures")
        if not treasuresFolder then continue end

        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        for _, treasure in ipairs(treasuresFolder:GetChildren()) do
            if not _G.AutoCollect then break end

            -- หา ProximityPrompt ใน treasure แบบ recursive (ชื่อจริงคือ "OpenPrompt")
            local pp = treasure:FindFirstChildWhichIsA("ProximityPrompt", true)

            if not pp then continue end

            -- หา root part ของ treasure เพื่อเดินไป
            local targetPart = treasure.PrimaryPart
                or treasure:FindFirstChildOfClass("BasePart")
            if not targetPart then continue end

            -- Teleport ไปใกล้ๆ (3 studs)
            hrp.CFrame = targetPart.CFrame * CFrame.new(0, 0, 3)
            task.wait(0.15)

            -- Trigger ProximityPrompt
            local triggered = false
            -- วิธี 1: fireproximityprompt (executor built-in)
            pcall(function()
                fireproximityprompt(pp)
                triggered = true
            end)
            -- วิธี 2: InputHoldBegin/End (fallback)
            if not triggered then
                pcall(function()
                    pp:InputHoldBegin()
                    task.wait(pp.HoldDuration + 0.1)
                    pp:InputHoldEnd()
                end)
            end

            task.wait(0.3)
        end
    end
end)


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

-- หา Fluent ScreenGui (GUI ใหม่ที่เพิ่มหลัง Fluent โหลด)
local fluentGui = nil
for _, v in ipairs(coreGui:GetChildren()) do
    if v:IsA("ScreenGui") and not preExistingGuis[v] then
        fluentGui = v
        break
    end
end

Fluent:Notify({
    Title = "Soul Cultivation Hub",
    Content = "Loaded successfully! Found " .. #monsterValues .. " monster type(s).",
    Duration = 4
})

-- ==========================================
-- [ Floating Toggle Icon ]
-- ==========================================
local iconGui = Instance.new("ScreenGui")
iconGui.Name         = "SCH_Icon"
iconGui.ResetOnSpawn = false
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
icon.Parent           = iconGui
Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

local stroke = Instance.new("UIStroke", icon)
stroke.Color     = Color3.fromRGB(0, 200, 255)
stroke.Thickness = 2

local uiVisible  = true
local isDragging = false
local dragStart, iconStartPos

icon.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isDragging    = false
        dragStart     = input.Position
        iconStartPos  = icon.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
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

icon.MouseButton1Up:Connect(function()
    if not isDragging then
        uiVisible = not uiVisible
        if fluentGui then
            -- Toggle เฉพาะ Fluent window
            fluentGui.Enabled = uiVisible
        else
            -- Fallback: หา GUI ใหม่อีกครั้ง
            for _, v in ipairs(coreGui:GetChildren()) do
                if v:IsA("ScreenGui") and v.Name ~= "SCH_Icon" and not preExistingGuis[v] then
                    fluentGui = v
                    fluentGui.Enabled = uiVisible
                end
            end
        end
        -- เปลี่ยนสี icon
        local activeColor = Color3.fromRGB(0, 200, 255)
        local dimColor    = Color3.fromRGB(80, 80, 80)
        stroke.Color      = uiVisible and activeColor or dimColor
        icon.TextColor3   = uiVisible and activeColor or dimColor
    end
    isDragging = false
    dragStart  = nil
end)
