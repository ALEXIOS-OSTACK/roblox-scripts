local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- [ Global Config ]
-- ==========================================
getgenv().BossHopConfig = {
    AutoFarm = false,
    AutoHop = false,
    SelectedBosses = {},
    FarmPosition = "Behind",
    FlySpeed = 150
}

local BossList = {"Zanshi Bing Ren", "Zanshi Huo Ren", "Mount Hua Leader"}

-- ==========================================
-- [ UI Library ]
-- ==========================================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Private",
    SubTitle = "Boss Hopper Hub",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    BossFarm = Window:AddTab({ Title = "Boss Farm", Icon = "swords" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

-- ==========================================
-- [ Core Functions ]
-- ==========================================
local function StopPhysicsFly()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        for _, name in ipairs({"BypassPosition", "BypassOrientation", "BypassAttachment"}) do
            local p = hrp:FindFirstChild(name)
            if p then p:Destroy() end
        end
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end

local function PhysicsFlyTo(targetCFrame)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local att = hrp:FindFirstChild("BypassAttachment") or Instance.new("Attachment", hrp)
    att.Name = "BypassAttachment"

    local pos = hrp:FindFirstChild("BypassPosition") or Instance.new("AlignPosition", hrp)
    pos.Name = "BypassPosition"; pos.Attachment0 = att
    pos.Mode = Enum.PositionAlignmentMode.OneAttachment
    pos.MaxForce = math.huge; pos.MaxVelocity = getgenv().BossHopConfig.FlySpeed; pos.Responsiveness = 200

    local ori = hrp:FindFirstChild("BypassOrientation") or Instance.new("AlignOrientation", hrp)
    ori.Name = "BypassOrientation"; ori.Attachment0 = att
    ori.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ori.MaxTorque = math.huge; ori.Responsiveness = 200

    pos.Position = targetCFrame.Position
    ori.CFrame = targetCFrame
    
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            p.CanCollide = false
        end
    end
end

local lastAttackTime = 0
local function SafeAttack()
    local now = tick()
    if now - lastAttackTime < 0.18 then return end
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

local function GetTargetBoundingBoxRadius(model)
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if model:IsA("Model") then
        local extents = model:GetExtentsSize()
        return math.max(extents.X, extents.Z) / 2
    elseif root then
        return math.max(root.Size.X, root.Size.Z) / 2
    end
    return 2
end

local function ServerHop()
    if getgenv().Hopping then return end
    getgenv().Hopping = true
    Fluent:Notify({ Title = "Server Hop", Content = "Boss not found/dead. Looking for a new server...", Duration = 5 })
    
    task.spawn(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        pcall(function()
            local req = request or http_request or (syn and syn.request)
            if not req then return end
            
            local response = req({Url = url, Method = "GET"})
            if response.StatusCode == 200 then
                local body = HttpService:JSONDecode(response.Body)
                if body and body.data then
                    for _, v in ipairs(body.data) do
                        if type(v) == "table" and v.playing < v.maxPlayers and v.id ~= game.JobId then
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, v.id, LocalPlayer)
                            task.wait(2)
                        end
                    end
                end
            end
        end)
        getgenv().Hopping = false
    end)
end

local function GetOptimalBoss()
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return nil end
    
    local myPos = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position
    if not myPos then return nil end
    
    local bestBoss = nil
    local bestDist = math.huge
    
    for _, e in ipairs(enemiesFolder:GetChildren()) do
        local hum = e:FindFirstChildOfClass("Humanoid")
        local root = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
        if hum and root and hum.Health > 0.1 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
            if getgenv().BossHopConfig.SelectedBosses[e.Name] then
                local dist = (myPos - root.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestBoss = e
                end
            end
        end
    end
    
    return bestBoss
end

-- ==========================================
-- [ Boss Farm UI ]
-- ==========================================
Tabs.BossFarm:AddParagraph({ Title = "Boss Auto Farm", Content = "Select targets and optionally enable Server Hop." })

local FarmToggle = Tabs.BossFarm:AddToggle("AutoFarmToggle", { Title = "Auto Farm Boss", Default = false })
FarmToggle:OnChanged(function(v) getgenv().BossHopConfig.AutoFarm = v end)

local HopToggle = Tabs.BossFarm:AddToggle("AutoHopToggle", { Title = "Auto Server Hop", Description = "Hop server automatically if no selected boss is alive.", Default = false })
HopToggle:OnChanged(function(v) getgenv().BossHopConfig.AutoHop = v end)

local BossDropdown = Tabs.BossFarm:AddDropdown("BossDropdown", {
    Title = "Target Bosses",
    Values = BossList,
    Multi = true,
    Default = {},
})
BossDropdown:OnChanged(function(v) getgenv().BossHopConfig.SelectedBosses = v end)

local PositionDropdown = Tabs.BossFarm:AddDropdown("FarmPosition", {
    Title = "Stand Position",
    Values = {"Behind", "On Head", "Under"},
    Default = 1,
})
PositionDropdown:OnChanged(function(v) getgenv().BossHopConfig.FarmPosition = v end)

Tabs.BossFarm:AddButton({
    Title = "Manual Server Hop",
    Description = "Skip this server instantly.",
    Callback = function()
        ServerHop()
    end
})

-- ==========================================
-- [ Main Loop ]
-- ==========================================
local FarmState = "IDLE"
local CurrentTarget = nil
local WaitHopDelay = 0

task.spawn(function()
    while task.wait() do
        if not getgenv().BossHopConfig.AutoFarm then
            if FarmState ~= "IDLE" then
                FarmState = "IDLE"
                StopPhysicsFly()
            end
            continue
        end

        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not hum or not hrp then continue end
        
        local isValidTarget = CurrentTarget and CurrentTarget.Parent and CurrentTarget:FindFirstChildOfClass("Humanoid") and CurrentTarget:FindFirstChildOfClass("Humanoid").Health > 0.1
        
        if FarmState == "IDLE" or FarmState == "SEARCHING" or not isValidTarget then
            CurrentTarget = GetOptimalBoss()
            if CurrentTarget then
                FarmState = "MOVING"
                WaitHopDelay = 0
            else
                FarmState = "SEARCHING"
                StopPhysicsFly()
                if getgenv().BossHopConfig.AutoHop then
                    WaitHopDelay = WaitHopDelay + task.wait()
                    if WaitHopDelay > 4 then -- Wait 4 seconds to confirm all bosses are dead before hopping
                        ServerHop()
                        WaitHopDelay = 0
                    end
                end
            end
            
        elseif FarmState == "MOVING" or FarmState == "ATTACKING" then
            local targetRoot = CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget.PrimaryPart
            if not targetRoot then
                FarmState = "SEARCHING"
                continue
            end
            
            local rBox = GetTargetBoundingBoxRadius(CurrentTarget) * 0.6
            local offset
            if getgenv().BossHopConfig.FarmPosition == "On Head" then
                offset = CFrame.new(0, rBox + 2, 0)
            elseif getgenv().BossHopConfig.FarmPosition == "Under" then
                offset = CFrame.new(0, -(rBox + 2), 0)
            else
                offset = CFrame.new(0, 0, rBox + 2)
            end
            
            local standCFrame = targetRoot.CFrame * offset
            local dist = (hrp.Position - standCFrame.Position).Magnitude
            
            if dist > 8 then
                FarmState = "MOVING"
                PhysicsFlyTo(standCFrame)
            else
                FarmState = "ATTACKING"
                hrp.CFrame = standCFrame
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                PhysicsFlyTo(standCFrame)
                SafeAttack()
            end
        end
    end
end)

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.zero)
end)

-- ==========================================
-- [ Save Manager (Settings) ]
-- ==========================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("BossHopperHub")
SaveManager:SetFolder("BossHopperHub/Configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()
Fluent:Notify({ Title = "Loaded", Content = "Boss Hopper is ready!", Duration = 3 })
