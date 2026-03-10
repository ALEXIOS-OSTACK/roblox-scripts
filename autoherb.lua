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
-- [ 2. Custom Hidden UI Engine ]
-- ==========================================
local coreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- Clean old instances
for _, v in ipairs(coreGui:GetChildren()) do
    if v.Name == "HiddenCustomHub" then v:Destroy() end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HiddenCustomHub"
ScreenGui.Parent = coreGui
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
MainFrame.Name = "Main"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
MainFrame.BorderSizePixel = 0
MainFrame.Position = UDim2.new(0.5, -300, 0.5, -200)
MainFrame.Size = UDim2.new(0, 600, 0, 400)
MainFrame.ClipsDescendants = true

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(60, 60, 70)
UIStroke.Thickness = 1
UIStroke.Parent = MainFrame

-- Top Bar (Draggable)
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Parent = MainFrame
TopBar.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
TopBar.BorderSizePixel = 0
TopBar.Size = UDim2.new(1, 0, 0, 40)

local TopUICorner = Instance.new("UICorner")
TopUICorner.CornerRadius = UDim.new(0, 8)
TopUICorner.Parent = TopBar

local TopFix = Instance.new("Frame")
TopFix.Parent = TopBar
TopFix.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
TopFix.BorderSizePixel = 0
TopFix.Position = UDim2.new(0, 0, 1, -8)
TopFix.Size = UDim2.new(1, 0, 0, 8)

local Title = Instance.new("TextLabel")
Title.Parent = TopBar
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 15, 0, 0)
Title.Size = UDim2.new(0, 200, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.Text = "Hidden - Fisch v1.02 (Clone)"
Title.TextColor3 = Color3.fromRGB(220, 220, 220)
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left

-- Dragging Logic
local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Parent = MainFrame
Sidebar.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Sidebar.BorderSizePixel = 0
Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.Size = UDim2.new(0, 50, 1, -40)

local ContentArea = Instance.new("Frame")
ContentArea.Name = "Content"
ContentArea.Parent = MainFrame
ContentArea.BackgroundTransparency = 1
ContentArea.Position = UDim2.new(0, 60, 0, 50)
ContentArea.Size = UDim2.new(1, -70, 1, -60)

local function switchTab(tabName)
    for _, child in ipairs(ContentArea:GetChildren()) do
        if child:IsA("ScrollingFrame") then
            child.Visible = (child.Name == tabName)
        end
    end
    for _, child in ipairs(Sidebar:GetChildren()) do
        if child:IsA("TextButton") then
            if child.Name == "Btn_" .. tabName then
                child.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            else
                child.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
            end
        end
    end
end

-- UI Components Generator
local UI = {}

function UI.CreateTab(name, iconId)
    local btn = Instance.new("TextButton")
    btn.Name = "Btn_" .. name
    btn.Parent = Sidebar
    btn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    btn.BorderSizePixel = 0
    btn.Size = UDim2.new(1, 0, 0, 50)
    btn.Position = UDim2.new(0, 0, 0, (#Sidebar:GetChildren() - 1) * 50)
    btn.Text = ""
    
    local icon = Instance.new("ImageLabel")
    icon.Parent = btn
    icon.BackgroundTransparency = 1
    icon.Position = UDim2.new(0.5, -12, 0.5, -12)
    icon.Size = UDim2.new(0, 24, 0, 24)
    icon.Image = iconId
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = name
    scroll.Parent = ContentArea
    scroll.BackgroundTransparency = 1
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 70)
    scroll.Visible = false
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.Parent = scroll
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 8)
    
    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 20)
    end)
    
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    
    return scroll
end

function UI.CreateSection(parent, title)
    local sec = Instance.new("TextLabel")
    sec.Parent = parent
    sec.BackgroundTransparency = 1
    sec.Size = UDim2.new(1, 0, 0, 25)
    sec.Font = Enum.Font.GothamBold
    sec.Text = title
    sec.TextColor3 = Color3.fromRGB(255, 255, 255)
    sec.TextSize = 13
    sec.TextXAlignment = Enum.TextXAlignment.Left
end

function UI.CreateToggle(parent, text, default, callback)
    local state = default
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    frame.Size = UDim2.new(1, -10, 0, 45)
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    
    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 15, 0, 0)
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Font = Enum.Font.GothamSemiBold
    label.Text = text
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local btn = Instance.new("TextButton")
    btn.Parent = frame
    btn.BackgroundColor3 = state and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(50, 50, 60)
    btn.Position = UDim2.new(1, -55, 0.5, -12)
    btn.Size = UDim2.new(0, 40, 0, 24)
    btn.Text = ""
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    
    local cir = Instance.new("Frame")
    cir.Parent = btn
    cir.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    cir.Position = state and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)
    cir.Size = UDim2.new(0, 20, 0, 20)
    Instance.new("UICorner", cir).CornerRadius = UDim.new(1, 0)
    
    btn.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = state and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(50, 50, 60)}):Play()
        TweenService:Create(cir, TweenInfo.new(0.2), {Position = state and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)}):Play()
        callback(state)
    end)
    callback(state)
end

function UI.CreateButton(parent, text, callback)
    local btn = Instance.new("TextButton")
    btn.Parent = parent
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    btn.Size = UDim2.new(1, -10, 0, 40)
    btn.Font = Enum.Font.GothamSemiBold
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(220, 220, 220)
    btn.TextSize = 13
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    btn.MouseButton1Click:Connect(callback)
end

function UI.CreateSlider(parent, text, min, max, default, callback)
    local val = default
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    frame.Size = UDim2.new(1, -10, 0, 55)
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    
    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 15, 0, 5)
    label.Size = UDim2.new(0.8, 0, 0, 20)
    label.Font = Enum.Font.GothamSemiBold
    label.Text = text
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local valLbl = Instance.new("TextLabel")
    valLbl.Parent = frame
    valLbl.BackgroundTransparency = 1
    valLbl.Position = UDim2.new(1, -50, 0, 5)
    valLbl.Size = UDim2.new(0, 40, 0, 20)
    valLbl.Font = Enum.Font.Gotham
    valLbl.Text = tostring(default)
    valLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
    valLbl.TextSize = 12
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    
    local sliderBg = Instance.new("TextButton")
    sliderBg.Parent = frame
    sliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    sliderBg.Position = UDim2.new(0, 15, 0, 35)
    sliderBg.Size = UDim2.new(1, -30, 0, 6)
    sliderBg.Text = ""
    Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1, 0)
    
    local sliderFill = Instance.new("Frame")
    sliderFill.Parent = sliderBg
    sliderFill.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
    sliderFill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1, 0)
    
    local function update(input)
        local pos = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
        val = math.floor(min + (max - min) * pos)
        sliderFill.Size = UDim2.new(pos, 0, 1, 0)
        valLbl.Text = tostring(val)
        callback(val)
    end
    
    local draggingS = false
    sliderBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingS = true
            update(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingS = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if draggingS and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
    callback(val)
end

function UI.CreateDropdown(parent, text, options, default, callback)
    local selected = default
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    frame.Size = UDim2.new(1, -10, 0, 45)
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    
    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 15, 0, 0)
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Font = Enum.Font.GothamSemiBold
    label.Text = text
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local dropBtn = Instance.new("TextButton")
    dropBtn.Parent = frame
    dropBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    dropBtn.Position = UDim2.new(1, -150, 0.5, -12)
    dropBtn.Size = UDim2.new(0, 140, 0, 24)
    dropBtn.Font = Enum.Font.Gotham
    dropBtn.Text = tostring(selected)
    dropBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
    dropBtn.TextSize = 12
    Instance.new("UICorner", dropBtn).CornerRadius = UDim.new(0, 4)
    
    local isDropOpen = false
    local dropScroll = Instance.new("ScrollingFrame")
    dropScroll.Parent = frame
    dropScroll.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    dropScroll.Position = UDim2.new(1, -150, 1, 0)
    dropScroll.Size = UDim2.new(0, 140, 0, 100)
    dropScroll.Visible = false
    dropScroll.ZIndex = 10
    dropScroll.CanvasSize = UDim2.new(0, 0, 0, #options * 25)
    dropScroll.ScrollBarThickness = 2
    Instance.new("UICorner", dropScroll).CornerRadius = UDim.new(0, 4)
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = dropScroll
    
    local function initOptions(ops)
        for _, v in ipairs(dropScroll:GetChildren()) do
            if v:IsA("TextButton") then v:Destroy() end
        end
        layout.Padding = UDim.new(0, 0)
        dropScroll.CanvasSize = UDim2.new(0, 0, 0, #ops * 30)
        for _, opt in ipairs(ops) do
            local oBtn = Instance.new("TextButton")
            oBtn.Parent = dropScroll
            oBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
            oBtn.BorderSizePixel = 0
            oBtn.Size = UDim2.new(1, 0, 0, 30)
            oBtn.Font = Enum.Font.Gotham
            oBtn.Text = tostring(opt)
            oBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
            oBtn.TextSize = 12
            oBtn.ZIndex = 11
            
            oBtn.MouseButton1Click:Connect(function()
                selected = opt
                dropBtn.Text = tostring(opt)
                dropScroll.Visible = false
                isDropOpen = false
                callback(opt)
            end)
        end
    end
    initOptions(options)
    
    dropBtn.MouseButton1Click:Connect(function()
        isDropOpen = not isDropOpen
        dropScroll.Visible = isDropOpen
    end)
    callback(selected)
    
    return {
        SetOptions = function(newOps)
            initOptions(newOps)
            if not table.find(newOps, selected) then
                selected = newOps[1] or ""
                dropBtn.Text = tostring(selected)
                callback(selected)
            end
        end
    }
end

function UI.Notify(title, desc)
    local notif = Instance.new("Frame")
    notif.Parent = ScreenGui
    notif.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    notif.Size = UDim2.new(0, 250, 0, 70)
    notif.Position = UDim2.new(1, 10, 1, -100)
    Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 8)
    
    local tLbl = Instance.new("TextLabel")
    tLbl.Parent = notif
    tLbl.BackgroundTransparency = 1
    tLbl.Position = UDim2.new(0, 10, 0, 10)
    tLbl.Size = UDim2.new(1, -20, 0, 20)
    tLbl.Font = Enum.Font.GothamBold
    tLbl.Text = title
    tLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    tLbl.TextSize = 14
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local dLbl = Instance.new("TextLabel")
    dLbl.Parent = notif
    dLbl.BackgroundTransparency = 1
    dLbl.Position = UDim2.new(0, 10, 0, 30)
    dLbl.Size = UDim2.new(1, -20, 1, -35)
    dLbl.Font = Enum.Font.Gotham
    dLbl.Text = desc
    dLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
    dLbl.TextSize = 12
    dLbl.TextXAlignment = Enum.TextXAlignment.Left
    dLbl.TextWrapped = true
    
    TweenService:Create(notif, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(1, -270, 1, -100)}):Play()
    task.delay(3, function()
        local t = TweenService:Create(notif, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(1, 10, 1, -100)})
        t:Play()
        t.Completed:Connect(function() notif:Destroy() end)
    end)
end

-- ==========================================
-- [ 3. Setup Logic & Hooks ]
-- ==========================================
local TabFarm = UI.CreateTab("Farm", "rbxassetid://6034066621")
local TabTeleport = UI.CreateTab("Teleport", "rbxassetid://6031265976")
local TabSettings = UI.CreateTab("Settings", "rbxassetid://6031280882")
switchTab("Farm") -- open default

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
UI.CreateSection(TabFarm, "  🔥 Combat")
UI.CreateToggle(TabFarm, "Start Auto Farm", false, function(v) _G.AutoFarm = v end)
UI.CreateToggle(TabFarm, "Priority Boss", false, function(v) _G.BossPriority = v end)
-- Simplified Boss dropdown since custom multiselect is tricky, just assume all bosses for now if toggled.
UI.CreateDropdown(TabFarm, "Stand Position", {"Behind", "On Head", "Under"}, "Behind", function(v) _G.FarmPosition = v end)

local mVals = ScanMonsters()
if #mVals == 0 then mVals = {"(None)"} end
local MobDrop = UI.CreateDropdown(TabFarm, "Select Monster", mVals, mVals[1], function(v) _G.SelectedMonster = v end)

UI.CreateButton(TabFarm, "Refresh Monsters", function()
    local nm = ScanMonsters()
    if #nm == 0 then nm = {"(None)"} end
    MobDrop.SetOptions(nm)
    UI.Notify("Refreshed", "Found " .. #nm .. " monsters.")
end)

-- TELEPORT TAB
UI.CreateSection(TabTeleport, "  📍 Target Teleport")
TargetDropdown = UI.CreateDropdown(TabTeleport, "Target", initTargets, initTargets[1], function(v) selectedTarget = v end)
UI.CreateDropdown(TabTeleport, "Category", {"NPC", "Qi", "Training"}, "NPC", function(v)
    selectedCategory = v
    RefreshTargetList()
end)

UI.CreateButton(TabTeleport, "🚀 Start Teleport", function()
    if selectedTarget == "(None Found)" or selectedTarget == "" then
        UI.Notify("Error", "Please select a target!")
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

    if not targetObj then return UI.Notify("Error", "Target not found.") end
    local targetCF = FindPosition(targetObj)
    if not targetCF then return UI.Notify("Error", "Can't get position.") end

    local destination = selectedCategory == "NPC" and targetCF * CFrame.new(0, 0, 5) or targetCF
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        _G.AutoFarm = false
        StopFlying()
        _G.Teleporting = true
        UI.Notify("Teleporting", "Flying to " .. selectedTarget)
        task.spawn(function()
            while _G.Teleporting do
                local chrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not chrp then break end
                if (chrp.Position - destination.Position).Magnitude < 10 then
                    StopFlying()
                    _G.Teleporting = false
                    UI.Notify("Arrived", "Reached " .. selectedTarget)
                    break
                end
                FlyToTarget(destination)
                task.wait(0.1)
            end
        end)
    end
end)
UI.CreateButton(TabTeleport, "🛑 Cancel Teleport", function()
    _G.Teleporting = false
    StopFlying()
    UI.Notify("Cancelled", "Teleport stopped.")
end)

-- SETTINGS TAB
UI.CreateSection(TabSettings, "  ⚙️ Adjustments")
UI.CreateSlider(TabSettings, "Attack Distance", -5, 15, 2, function(v) _G.AttackDistance = v end)
UI.CreateSlider(TabSettings, "Fly Speed", 50, 500, 150, function(v) _G.FlySpeed = v end)
UI.CreateSlider(TabSettings, "Attack Cooldown (ms)", 10, 100, 18, function(v) BASE_COOLDOWN = v / 1000 end)
UI.CreateSlider(TabSettings, "Safety HP %", 0, 90, 30, function(v) _G.MinHP = v end)

UI.CreateSection(TabSettings, "  🛡️ Server Protection")
UI.CreateToggle(TabSettings, "Anti-AFK", true, function(v) _G.AntiAFK = v end)
UI.CreateToggle(TabSettings, "Anti-Player", false, function(v) _G.AntiPlayer = v end)

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

UI.Notify("Inject Success", "Hidden UI Clone loaded.")
