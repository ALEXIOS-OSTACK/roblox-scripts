-- IMMORTAL LUCK • RARITY 3–5 AUTO FARM (PRO, Cultivate(false) -> FlyingSword(true), Rejoin VIP Same Server)
-- ใช้เพื่อทดสอบใน private server เท่านั้น

--== Services ==--
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local HRP = Char:WaitForChild("HumanoidRootPart")

--== Config ==--
local ROOT_NAME = "Resources"             -- ล็อกเฉพาะ workspace/Resources
local SPEED_STUDS_PER_S = 40              -- tween speed
local SAFE_Y_OFFSET = 2
local MAX_SCAN_RANGE = 6000               -- ระยะสแกน
local ONLY_THESE = { [3]=true, [4]=true, [5]=true }  -- เฉพาะ 3/4/5
local NAME_BLACKLIST = { Trap=true, Dummy=true }
local COLLECT_RANGE = 12
local MAX_TARGET_STUCK_TIME = 10
local UI_POS = UDim2.new(0, 60, 0, 80)

-- Auto/Hop
local AUTO_ENABLED = true
local AUTO_HOP_ENABLED = true
local MAX_HOP = 50
local EMPTY_GRACE_SECONDS = 1.0

-- Priority
local PRIORITY_MODE = "Rarity"            -- "Rarity" | "Nearest" | "Score"

-- Remote usage (สำคัญ: ลำดับ Cultivate(false) -> FlyingSword(true))
local USE_FLYING_SWORD = true
local FLYING_SWORD_ARGS = { true }

-- ชื่อเรียก
local RARITY_NAME = { [1]="Common", [2]="Rare", [3]="Legendary", [4]="Tier4", [5]="Tier5" }

--== Persist ==--
getgenv().IL_STATS = getgenv().IL_STATS or {collected=0, hopped=0}

--== Helpers ==--
local function safeParent()
    local ok,hui = pcall(function() return gethui and gethui() end)
    if ok and typeof(hui)=="Instance" then return hui end
    return game.CoreGui or LP:WaitForChild("PlayerGui")
end

local function getPart(inst)
    if inst:IsA("BasePart") then return inst end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function distance(a, b) return (a - b).Magnitude end

local function gradientFor(num)
    local gFolder = RS:FindFirstChild("RarityGradients")
    return gFolder and gFolder:FindFirstChild(tostring(num)) or nil
end

local function getHRP()
    if HRP and HRP.Parent then return HRP end
    if LP.Character then
        HRP = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:WaitForChild("HumanoidRootPart", 5)
    end
    return HRP
end

-- LoS check (กันติดสิ่งกีดขวาง)
local function hasLineOfSight(fromPos, toPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    local dir = toPos - fromPos
    local result = workspace:Raycast(fromPos, dir, params)
    return result == nil
end

--== Waypoint ==--
local function clearWaypoint()
    local old = workspace:FindFirstChild("IL_Waypoint_Att0")
    if old then old:Destroy() end
end

local function setWaypoint(targetPart)
    clearWaypoint()
    local _hrp = getHRP()
    if not _hrp or not targetPart then return end
    local a = Instance.new("Attachment"); a.Name = "IL_Waypoint_Att0"; a.Parent = _hrp
    local b = Instance.new("Attachment"); b.Parent = targetPart
    local beam = Instance.new("Beam")
    beam.Attachment0, beam.Attachment1 = a, b
    beam.FaceCamera = true
    beam.Segments = 50
    beam.Width0, beam.Width1 = 0.35, 0.35
    beam.Parent = a
end

--== TP (tween + snap fail-safe) ==--
local currentTween
local function snapTP(targetPos)
    local _hrp = getHRP()
    if _hrp then _hrp.CFrame = CFrame.new(targetPos) end
end

local function tweenHop(toPos)
    local _hrp = getHRP()
    if not _hrp then return end
    local dist = (_hrp.Position - toPos).Magnitude
    local t = math.max(0.25, dist / SPEED_STUDS_PER_S)
    if currentTween and currentTween.PlaybackState == Enum.PlaybackState.Playing then
        currentTween:Cancel()
    end
    currentTween = TweenService:Create(_hrp, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = CFrame.new(toPos)})
    currentTween:Play()
    local elapsed = 0
    while currentTween and currentTween.PlaybackState == Enum.PlaybackState.Playing do
        local dt = RunService.Heartbeat:Wait()
        elapsed += dt
        if elapsed > t + 2 then
            currentTween:Cancel()
            snapTP(toPos + Vector3.new(0, SAFE_Y_OFFSET, 0))
            break
        end
    end
end

local function tweenTP(targetPos)
    local _hrp = getHRP(); if not _hrp then return end
    local start = _hrp.Position
    if not hasLineOfSight(start, targetPos) then
        targetPos = targetPos + Vector3.new(0, 20, 0)
    end
    local dist = (targetPos - start).Magnitude
    local step = 20
    local steps = math.max(1, math.ceil(dist / step))
    for i = 1, steps do
        local alpha = i/steps
        local p = start:Lerp(targetPos, alpha)
        p = Vector3.new(p.X, p.Y + SAFE_Y_OFFSET, p.Z)
        tweenHop(p)
        task.wait(0.03)
    end
end

--== Remotes (สำคัญ) ==--
local function stopCultivate()
    local rem = RS:WaitForChild("Remotes")
    local ev = rem:WaitForChild("Cultivate")
    local args = { false }
    pcall(function() ev:FireServer(unpack(args)) end)
end

local function useFlyingSword()
    if not USE_FLYING_SWORD then return end
    local rem = RS:WaitForChild("Remotes")
    local ev = rem:WaitForChild("FlyingSword")
    pcall(function() ev:FireServer(unpack( { true } )) end)
end

--== Scan Root ==--
local ROOT = workspace:WaitForChild(ROOT_NAME)

--== Targets + ESP ==--
local targets = {}  -- [part] = {obj=Instance, rarity=number, bb=Billboard, hl=Highlight, lbl=TextLabel}

local function makeESP(part, rarity)
    local bb = Instance.new("BillboardGui")
    bb.Name = "IL_ESP"
    bb.AlwaysOnTop = true
    bb.Size = UDim2.new(0, 220, 0, 48)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.Adornee = part
    bb.Parent = part

    local frame = Instance.new("Frame", bb)
    frame.Size = UDim2.new(1,0,1,0)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)
    local g = gradientFor(rarity)
    if g then g:Clone().Parent = frame end

    local lbl = Instance.new("TextLabel", frame)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1,-10,1,-10)
    lbl.Position = UDim2.new(0,5,0,5)
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextScaled = true
    lbl.TextColor3 = Color3.fromRGB(255,255,255)
    lbl.TextStrokeTransparency = 0.5

    local hl = Instance.new("Highlight")
    hl.Adornee = part
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.7
    hl.OutlineTransparency = 0.1
    hl.Parent = part
    if rarity==5 then hl.OutlineColor = Color3.fromRGB(255,180,255)
    elseif rarity==4 then hl.OutlineColor = Color3.fromRGB(180,120,255)
    elseif rarity==3 then hl.OutlineColor = Color3.fromRGB(120,220,255) end

    return bb, lbl, hl
end

local function forget(part)
    local rec = targets[part]
    if not rec then return end
    pcall(function() if rec.bb then rec.bb:Destroy() end end)
    pcall(function() if rec.hl then rec.hl:Destroy() end end)
    targets[part] = nil
end

local function attach(inst)
    local r = inst:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return end
    if NAME_BLACKLIST[inst.Name] then return end
    local part = getPart(inst)
    if not part or targets[part] then return end
    local bb, lbl, hl = makeESP(part, r)
    targets[part] = {obj=inst, rarity=r, bb=bb, lbl=lbl, hl=hl}
    inst.AncestryChanged:Connect(function(_, parent)
        if not parent then forget(part) end
    end)
end

for _,d in ipairs(ROOT:GetDescendants()) do
    if d:GetAttribute("Rarity") ~= nil then attach(d) end
end

ROOT.DescendantAdded:Connect(function(d)
    if d:GetAttribute("Rarity") ~= nil then attach(d) end
end)

workspace.ChildAdded:Connect(function(c)
    if c.Name == ROOT_NAME then
        -- ROOT ถูก recreate
        -- ล้างของเก่า
        for part, rec in pairs(targets) do
            pcall(function() if rec.bb then rec.bb:Destroy() end end)
            pcall(function() if rec.hl then rec.hl:Destroy() end end)
            targets[part] = nil
        end
        -- bind ใหม่
        for _,d in ipairs(c:GetDescendants()) do
            if d:GetAttribute("Rarity") ~= nil then attach(d) end
        end
        c.DescendantAdded:Connect(function(d)
            if d:GetAttribute("Rarity") ~= nil then attach(d) end
        end)
        _G.__IL_ROOT = c
    end
end)
_G.__IL_ROOT = ROOT

--== Ordering / Priority ==--
local ordered, idx = {}, 1

local function scoreOf(node) return (node.info.rarity or 0)*1000 - (node.dist or 0) end

local function sortNodes(a,b)
    if PRIORITY_MODE == "Nearest" then
        if a.dist ~= b.dist then return a.dist < b.dist end
        return (a.info.rarity or 0) > (b.info.rarity or 0)
    elseif PRIORITY_MODE == "Score" then
        return scoreOf(a) > scoreOf(b)
    else -- "Rarity"
        if a.info.rarity ~= b.info.rarity then return a.info.rarity > b.info.rarity end
        return a.dist < b.dist
    end
end

local function refreshList()
    ordered = {}
    local _hrp = getHRP(); if not _hrp then return end
    for part,info in pairs(targets) do
        if part and part.Parent and info and info.obj and info.obj.Parent and info.obj:IsDescendantOf(_G.__IL_ROOT) then
            local dist = distance(_hrp.Position, part.Position)
            if dist <= MAX_SCAN_RANGE then
                table.insert(ordered, {part=part, info=info, dist=dist})
            end
        end
    end
    table.sort(ordered, sortNodes)
    if #ordered == 0 then idx = 1 else idx = math.clamp(idx, 1, #ordered) end
end

local function isValidTarget(part, info)
    if not part or not part.Parent then return false end
    if not info or not info.obj or not info.obj.Parent then return false end
    if not info.obj:IsDescendantOf(_G.__IL_ROOT) then return false end
    local r = info.obj:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return false end
    return true
end

local function waitGoneOrTimeout(part, info, timeout)
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or 2.0) do
        if (not isValidTarget(part, info)) or (not targets[part]) then
            return true
        end
        task.wait(0.05)
    end
    return false
end

--== Visual updater ==--
task.spawn(function()
    while true do
        task.wait(0.2)
        local _hrp = getHRP(); if not _hrp then continue end
        for part,info in pairs(targets) do
            if part and part.Parent then
                local dist = distance(_hrp.Position, part.Position)
                if info.lbl then
                    local name = RARITY_NAME[info.rarity] or ("R"..tostring(info.rarity))
                    info.lbl.Text = string.format("[%s:%d]  %.0f studs", name, info.rarity, dist)
                end
                local visible = dist <= MAX_SCAN_RANGE
                if info.bb then info.bb.Enabled = visible end
                if info.hl then info.hl.Enabled = visible end
            end
        end
        refreshList()
    end
end)

--== UI ==--
local gui = Instance.new("ScreenGui", safeParent())
gui.Name = "IL_AutoFarm_Pro"
gui.ResetOnSpawn = false

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.new(0, 400, 0, 190)
frame.Position = UI_POS
frame.BackgroundColor3 = Color3.fromRGB(25,25,30)
frame.BorderSizePixel = 0
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel", frame)
title.BackgroundTransparency = 1
title.Position = UDim2.new(0,10,0,6)
title.Size = UDim2.new(1,-20,0,20)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(240,240,240)
title.Text = "Rarity 3–5 Auto Farm (Resources / PRO)"

local status = Instance.new("TextLabel", frame)
status.BackgroundTransparency = 1
status.Position = UDim2.new(0,10,0,34)
status.Size = UDim2.new(1,-20,0,18)
status.Font = Enum.Font.Gotham
status.TextSize = 13
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(200,200,210)
status.Text = "Target: -"

local toggleBtn = Instance.new("TextButton", frame)
toggleBtn.Size = UDim2.new(0, 90, 0, 26)
toggleBtn.Position = UDim2.new(0,10,0,60)
toggleBtn.Text = "Pause"
toggleBtn.Font = Enum.Font.GothamSemibold
toggleBtn.TextSize = 14
toggleBtn.BackgroundColor3 = Color3.fromRGB(40,40,50)
toggleBtn.TextColor3 = Color3.fromRGB(220,220,255)
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,8)

local tpBtn = Instance.new("TextButton", frame)
tpBtn.Size = UDim2.new(0, 90, 0, 26)
tpBtn.Position = UDim2.new(0,110,0,60)
tpBtn.Text = "TP Now"
tpBtn.Font = Enum.Font.GothamSemibold
tpBtn.TextSize = 14
tpBtn.BackgroundColor3 = Color3.fromRGB(40,60,70)
tpBtn.TextColor3 = Color3.fromRGB(120,255,150)
Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0,8)

local collectBtn = Instance.new("TextButton", frame)
collectBtn.Size = UDim2.new(0, 110, 0, 26)
collectBtn.Position = UDim2.new(0,210,0,60)
collectBtn.Text = "Collect Now"
collectBtn.Font = Enum.Font.GothamSemibold
collectBtn.TextSize = 14
collectBtn.BackgroundColor3 = Color3.fromRGB(70,60,40)
collectBtn.TextColor3 = Color3.fromRGB(255,240,170)
Instance.new("UICorner", collectBtn).CornerRadius = UDim.new(0,8)

local hopBtn = Instance.new("TextButton", frame)
hopBtn.Size = UDim2.new(0, 380, 0, 28)
hopBtn.Position = UDim2.new(0,10,0,100)
hopBtn.Text = "Rejoin VIP (Same Server)"
hopBtn.Font = Enum.Font.GothamSemibold
hopBtn.TextSize = 14
hopBtn.BackgroundColor3 = Color3.fromRGB(55,40,40)
hopBtn.TextColor3 = Color3.fromRGB(255,180,180)
Instance.new("UICorner", hopBtn).CornerRadius = UDim.new(0,8)

local footer = Instance.new("TextLabel", frame)
footer.BackgroundTransparency = 1
footer.Position = UDim2.new(0,10,0,134)
footer.Size = UDim2.new(0, 200, 0, 24)
footer.Font = Enum.Font.Gotham
footer.TextSize = 12
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextColor3 = Color3.fromRGB(180,180,190)
footer.Text = "State: Auto=ON • Hop=ON • Mode=Rarity"

local remainingLbl = Instance.new("TextLabel", frame)
remainingLbl.BackgroundTransparency = 1
remainingLbl.Position = UDim2.new(0,210,0,134)
remainingLbl.Size = UDim2.new(0,180,0,24)
remainingLbl.Font = Enum.Font.Gotham
remainingLbl.TextSize = 12
remainingLbl.TextXAlignment = Enum.TextXAlignment.Right
remainingLbl.TextColor3 = Color3.fromRGB(180,180,190)
remainingLbl.Text = "Left: -"

local modeBtn = Instance.new("TextButton", frame)
modeBtn.Size = UDim2.new(0, 120, 0, 26)
modeBtn.Position = UDim2.new(0,10,0,160)
modeBtn.Text = "Mode: Rarity"
modeBtn.Font = Enum.Font.GothamSemibold
modeBtn.TextSize = 14
modeBtn.BackgroundColor3 = Color3.fromRGB(40,40,50)
modeBtn.TextColor3 = Color3.fromRGB(220,220,255)
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0,8)

-- draggable
do
    local dragging=false; local startPos; local startInput
    frame.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; startPos=frame.Position; startInput=input.Position
            input.Changed:Connect(function()
                if input.UserInputState==Enum.UserInputState.End then dragging=false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            local d = input.Position - startInput
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
        end
    end)
end

-- UI helpers
local function orderedIdx() return ordered[idx] end

local function updateStatus()
    refreshList()
    remainingLbl.Text = ("Left: %d"):format(#ordered)
    if #ordered == 0 then
        status.Text = "Target: -"
        clearWaypoint()
        return
    end
    local node = orderedIdx()
    local r = node.info.rarity
    local name = RARITY_NAME[r] or ("R"..tostring(r))
    status.Text = string.format("Target: %s (R%d) • %.0f studs", name, r, node.dist)
    setWaypoint(node.part)
end

toggleBtn.MouseButton1Click:Connect(function()
    AUTO_ENABLED = not AUTO_ENABLED
    toggleBtn.Text = AUTO_ENABLED and "Pause" or "Resume"
    footer.Text = string.format("State: Auto=%s • Hop=%s • Mode=%s", AUTO_ENABLED and "ON" or "OFF", AUTO_HOP_ENABLED and "ON" or "OFF", PRIORITY_MODE)
end)

tpBtn.MouseButton1Click:Connect(function()
    if #ordered == 0 then return end
    local part = orderedIdx().part
    if part and part.Parent then
        tweenTP(part.Position + Vector3.new(0, SAFE_Y_OFFSET, 0))
    end
end)

collectBtn.MouseButton1Click:Connect(function()
    if #ordered == 0 then return end
    local info = orderedIdx().info
    local part = orderedIdx().part
    if not (part and part.Parent) then return end
    local prompt = info.obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    local hrp = getHRP()
    local p = getPart(info.obj)
    if prompt and hrp and p and (hrp.Position - p.Position).Magnitude <= COLLECT_RANGE then
        if typeof(fireproximityprompt) == "function" then
            local hd = prompt.HoldDuration or 0
            if hd <= 0 then pcall(function() fireproximityprompt(prompt) end)
            else
                local t0 = os.clock()
                pcall(function() fireproximityprompt(prompt, 1) end)
                while os.clock() - t0 < hd + 0.05 do task.wait() end
            end
        end
    end
end)

modeBtn.MouseButton1Click:Connect(function()
    if PRIORITY_MODE == "Rarity" then PRIORITY_MODE = "Nearest"
    elseif PRIORITY_MODE == "Nearest" then PRIORITY_MODE = "Score"
    else PRIORITY_MODE = "Rarity" end
    modeBtn.Text = "Mode: "..PRIORITY_MODE
    footer.Text = string.format("State: Auto=%s • Hop=%s • Mode=%s", AUTO_ENABLED and "ON" or "OFF", AUTO_HOP_ENABLED and "ON" or "OFF", PRIORITY_MODE)
end)

-- Rejoin VIP ปุ่ม
local function rejoinSameServer()
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)
    if not ok then
        warn("Rejoin same server failed:", err)
        TeleportService:Teleport(game.PlaceId, LP)
    end
end

hopBtn.MouseButton1Click:Connect(function()
    getgenv().IL_STATS.hopped += 1
    rejoinSameServer()
end)

task.spawn(function()
    while true do
        task.wait(0.25)
        updateStatus()
    end
end)

LP.CharacterAdded:Connect(function(c)
    Char = c
    HRP = c:WaitForChild("HumanoidRootPart")
    task.delay(0.5, function()
        -- กันตอนเข้ามาใหม่แล้วยังคัลติอยู่
        stopCultivate()
    end)
end)

--== Prompt helpers ==--
local function pressPrompt(prompt)
    if not prompt then return false end
    if typeof(fireproximityprompt) ~= "function" then return false end
    local hd = prompt.HoldDuration or 0
    if hd <= 0 then
        pcall(function() fireproximityprompt(prompt) end)
        return true
    else
        local t0 = os.clock()
        pcall(function() fireproximityprompt(prompt, 1) end)
        while os.clock() - t0 < hd + 0.05 do task.wait() end
        return true
    end
end

local function collectIfNear(info, range)
    range = range or COLLECT_RANGE
    local prompt = info.obj and info.obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    local hrp = getHRP()
    local p = info.obj and getPart(info.obj)
    if prompt and hrp and p then
        if (hrp.Position - p.Position).Magnitude <= range then
            return pressPrompt(prompt)
        end
    end
    return false
end

--== Hop control (Rejoin VIP เดิมเสมอ) ==--
local hopCount = 0
local function hopNow()
    if AUTO_HOP_ENABLED and hopCount < MAX_HOP then
        hopCount += 1
        getgenv().IL_STATS.hopped += 1
        rejoinSameServer()
    end
end

--== Load-aware ==--
local fps, alpha = 60, 0.05
RunService.Heartbeat:Connect(function(dt)
    local nowFps = 1/dt
    fps = fps*(1-alpha) + nowFps*alpha
end)
local function dynamicWait()
    if fps > 80 then return 0.10
    elseif fps > 50 then return 0.15
    elseif fps > 30 then return 0.22
    else return 0.30 end
end

--== Anti-freeze watchdog ==--
local lastPos = nil
local lastMove = os.clock()
RunService.Heartbeat:Connect(function()
    local h = getHRP()
    if not h then return end
    if lastPos then
        if (h.Position - lastPos).Magnitude > 1 then
            lastMove = os.clock()
        end
    end
    lastPos = h.Position
end)

task.spawn(function()
    while task.wait(1.0) do
        if os.clock() - lastMove > 8 then
            clearWaypoint()
            refreshList()
        end
    end
end)

--== HOTKEYS ==--
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.P then toggleBtn:Activate() end
    if input.KeyCode == Enum.KeyCode.H then hopBtn:Activate() end
end)

--== AUTO LOOP (เก็บให้หมดก่อนฮอป + เช็ค despawn) ==--
task.spawn(function()
    while task.wait(dynamicWait()) do
        if not AUTO_ENABLED then continue end

        refreshList()
        if #ordered == 0 then
            hopNow()
        else
            for i,node in ipairs(ordered) do
                if not node or not isValidTarget(node.part, node.info) then continue end

                -- ลำดับสำคัญ: Cultivate(false) -> FlyingSword(true)
                stopCultivate()
                task.wait(0.2)
                useFlyingSword()
                task.wait(0.2)

                -- ไปหาเป้า
                setWaypoint(node.part)
                local targetPos = node.part.Position + Vector3.new(0, SAFE_Y_OFFSET, 0)
                tweenTP(targetPos)

                -- Collect (hold-aware) พร้อมกัน despawn
                local started = os.clock()
                while os.clock() - started < MAX_TARGET_STUCK_TIME do
                    if not isValidTarget(node.part, node.info) then break end
                    if collectIfNear(node.info) then
                        getgenv().IL_STATS.collected += 1
                        waitGoneOrTimeout(node.part, node.info, 1.5)
                        break
                    end
                    task.wait(0.1)
                end
            end

            -- เก็บครบ “รอบนี้” แล้วถ้าไม่เหลือจริง ๆ → hop
            refreshList()
            if #ordered == 0 then hopNow() end
        end
    end
end)
