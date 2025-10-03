-- IMMORTAL LUCK • RARITY 3–5 AUTO (Meditate <-> Hunt, no hop) • Fast TP + Ram-Into + Remote Collect
-- ใช้เพื่อทดสอบใน private server เท่านั้น

--== Services ==--
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local HRP = Char:WaitForChild("HumanoidRootPart")

--== Config (Fast TP tuned + Options) ==--
local ROOT_NAME            = "Resources"   -- สแกนเฉพาะ workspace/Resources
local SPEED_STUDS_PER_S    = 150           -- ความเร็ว tween (เดิม 40)
local MIN_TWEEN_TIME       = 0.08          -- ขั้นต่ำเวลาต่อช็อต (เดิม 0.25)
local TP_STEP_STUDS        = 120           -- ความยาวก้าวในการ TP (เดิม 20)
local HEIGHT_BOOST         = 30            -- ยกหัวหลบสิ่งกีดขวางเมื่อไม่มี LoS
local SAFE_Y_OFFSET        = 2
local MAX_SCAN_RANGE       = 6000
local ONLY_THESE           = { [4]=true, [5]=true }  -- เฉพาะ R3/4/5
local NAME_BLACKLIST       = { Trap=true, Dummy=true }         -- กันของไม่ต้องการ
local COLLECT_RANGE        = 14            -- เผื่อระยะเก็บนิดหน่อย
local MAX_TARGET_STUCK_TIME= 10
local UI_POS               = UDim2.new(0, 60, 0, 80)
local PRIORITY_MODE        = "Rarity"      -- "Rarity" | "Nearest" | "Score"
local AUTO_ENABLED         = true
local MEDITATE_POS         = Vector3.new(-2615.4, 141.752, 1385.9) -- << อัปเดตจากภาพ

-- == Approach Assist ==
local COLLECT_WITH_SWORD   = false         -- false = ปิดดาบก่อนเก็บเพื่อให้ Prompt ติดง่ายขึ้น
local APPROACH_RINGS       = {6, 9, 12, 16}
local APPROACH_STEP_DEG    = 30
local DROP_HEIGHT          = 18

-- == Ram-into target ==
local RAM_INTO_ENABLED     = true          -- เปิดโหมดชน
local RAM_OVERSHOOT        = 8             -- พุ่งเลยเป้าไปกี่ studs แล้วค่อยวกกลับ
local USE_NOCLIP_FOR_RAM   = true          -- เปิด noclip ชั่วคราวตอนชน

-- == Remote Collect ==
local USE_REMOTE_COLLECT   = true          -- ยิง Remotes.Collect ก่อนเสมอ

--== Labels ==--
local RARITY_NAME = { [1]="Common", [2]="Rare", [3]="Legendary", [4]="Tier4", [5]="Tier5" }

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

local function isNear(pos, target, r) return (pos - target).Magnitude <= (r or 4) end

-- noclip ชั่วคราว (สำหรับ Ram-Into)
local __origCollide = nil
local function setCharacterNoClip(on)
    if on then
        if __origCollide then return end
        __origCollide = {}
        for _,p in ipairs(Char:GetDescendants()) do
            if p:IsA("BasePart") then
                __origCollide[p] = p.CanCollide
                p.CanCollide = false
            end
        end
    else
        if not __origCollide then return end
        for p,can in pairs(__origCollide) do
            if p and p.Parent then p.CanCollide = can end
        end
        __origCollide = nil
    end
end

--== Line-of-sight ==--
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

local function tweenHop(toPos)
    local _hrp = getHRP()
    if not _hrp then return end
    local dist = (_hrp.Position - toPos).Magnitude
    local t = math.max(MIN_TWEEN_TIME, dist / SPEED_STUDS_PER_S)
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
            _hrp.CFrame = CFrame.new(toPos + Vector3.new(0, SAFE_Y_OFFSET, 0))
            break
        end
    end
end

local function tweenTP(targetPos)
    local _hrp = getHRP(); if not _hrp then return end
    local start = _hrp.Position
    if not hasLineOfSight(start, targetPos) then
        targetPos = targetPos + Vector3.new(0, HEIGHT_BOOST, 0)
    end
    local dist  = (targetPos - start).Magnitude
    local step  = TP_STEP_STUDS
    local steps = math.max(1, math.ceil(dist / step))
    for i = 1, steps do
        local p = start:Lerp(targetPos, i/steps)
        p = Vector3.new(p.X, p.Y + SAFE_Y_OFFSET, p.Z)
        tweenHop(p)
        -- เร็วขึ้น: ไม่ต้องหน่วง
    end
end

local function tpTo(vec3)
    tweenTP(vec3 + Vector3.new(0, SAFE_Y_OFFSET, 0))
end

--== Remotes: Cultivate/FlyingSword (มี debounce กันสแปม) ==--
local CUL_MIN_INTERVAL = 1.2
local CultivateState = { on = false, lastSend = 0 }
local function setCultivate(desired)
    local now = os.clock()
    if CultivateState.on == desired and (now - CultivateState.lastSend) < CUL_MIN_INTERVAL then
        return
    end
    CultivateState.lastSend = now
    CultivateState.on = desired
    local ev = RS:WaitForChild("Remotes"):WaitForChild("Cultivate")
    pcall(function() ev:FireServer(desired) end)
end
local function startCultivate() setCultivate(true) end
local function stopCultivate()  setCultivate(false) end

local function useFlyingSword()
    local ev = RS:WaitForChild("Remotes"):WaitForChild("FlyingSword")
    pcall(function() ev:FireServer(true) end)
end
local function stopFlyingSword()
    local ev = RS:WaitForChild("Remotes"):WaitForChild("FlyingSword")
    pcall(function() ev:FireServer(false) end)
end

--== Remote Collect Helpers ==--
local function _normalizeId(id)
    if not id or type(id) ~= "string" then return nil end
    id = id:gsub("%s+", "")
    if id == "" then return nil end
    if id:sub(1,1) ~= "{" then id = "{"..id.."}" end
    return id
end

local function _findCollectIdFromInst(inst)
    if not inst or not inst.Parent then return nil end
    local keys = {
        "CollectId","HerbId","ResourceId","ObjectId","Id","ID",
        "Guid","GUID","UUID","Uid","uid","HerbUUID","RootId"
    }
    for _,k in ipairs(keys) do
        local v = inst:GetAttribute(k)
        if v and type(v)=="string" and #v>0 then
            return _normalizeId(v)
        end
    end
    for _,d in ipairs(inst:GetDescendants()) do
        if d:IsA("StringValue") then
            local name = d.Name:lower()
            if name=="collectid" or name=="herbid" or name=="resourceid" or
               name=="objectid" or name=="id" or name=="guid" or
               name=="uuid" or name=="uid" or name=="herbuuid" or name=="rootid" then
                if d.Value and d.Value ~= "" then
                    return _normalizeId(d.Value)
                end
            end
        end
    end
    local m = string.match(inst.Name, "{[%x%-]+}")
    if m then return m end
    return nil
end

local function waitGoneOrTimeout(part, info, timeout)
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or 1.2) do
        if not part or not part.Parent or not info or not info.obj or not info.obj.Parent then
            return true
        end
        task.wait(0.05)
    end
    return false
end

local function collectViaRemote(info, part, timeout)
    if not USE_REMOTE_COLLECT then return false end
    local id = _findCollectIdFromInst(info and info.obj)
    if not id then return false end
    local ok, err = pcall(function()
        RS:WaitForChild("Remotes"):WaitForChild("Collect"):FireServer(id)
    end)
    if not ok then
        warn("[IL] Collect remote failed:", err)
        return false
    end
    return waitGoneOrTimeout(part, info, timeout or 1.2)
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
        ROOT = c
        for part, rec in pairs(targets) do
            pcall(function() if rec.bb then rec.bb:Destroy() end end)
            pcall(function() if rec.hl then rec.hl:Destroy() end end)
            targets[part] = nil
        end
        for _,d in ipairs(ROOT:GetDescendants()) do
            if d:GetAttribute("Rarity") ~= nil then attach(d) end
        end
        ROOT.DescendantAdded:Connect(function(d)
            if d:GetAttribute("Rarity") ~= nil then attach(d) end
        end)
    end
end)

--== Ordering / Priority ==--
local ordered, idx = {}, 1
local function scoreOf(node) return (node.info.rarity or 0)*1000 - (node.dist or 0) end
local function sortNodes(a,b)
    if PRIORITY_MODE == "Nearest" then
        if a.dist ~= b.dist then return a.dist < b.dist end
        return (a.info.rarity or 0) > (b.info.rarity or 0)
    elseif PRIORITY_MODE == "Score" then
        return scoreOf(a) > scoreOf(b)
    else
        if a.info.rarity ~= b.info.rarity then return a.info.rarity > b.info.rarity end
        return a.dist < b.dist
    end
end

local function refreshList()
    ordered = {}
    local _hrp = getHRP(); if not _hrp then return end
    for part,info in pairs(targets) do
        if part and part.Parent and info and info.obj and info.obj.Parent and info.obj:IsDescendantOf(ROOT) then
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
    if not info.obj:IsDescendantOf(ROOT) then return false end
    local r = info.obj:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return false end
    return true
end

--== Approach Helpers ==--
local function closeEnough(hrpPos, targetPos)
    return (hrpPos - targetPos).Magnitude <= (COLLECT_RANGE + 1)
end

local function approachTarget(part)
    local hrp = getHRP()
    if not (hrp and part and part.Parent) then return false end
    local tpos = part.Position

    -- ตรงดิ่งก่อน
    tpTo(tpos)
    if closeEnough(hrp.Position, tpos) then return true end

    -- ยกหัวแล้วลง
    tpTo(tpos + Vector3.new(0, DROP_HEIGHT, 0))
    tpTo(tpos)
    if closeEnough(getHRP().Position, tpos) then return true end

    -- ล้อมวงตามรัศมีและมุม
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}

    for _,radius in ipairs(APPROACH_RINGS) do
        for deg = 0, 360-APPROACH_STEP_DEG, APPROACH_STEP_DEG do
            local r = math.rad(deg)
            local candidate = tpos + Vector3.new(math.cos(r)*radius, SAFE_Y_OFFSET, math.sin(r)*radius)
            local dir = candidate - hrp.Position
            local hit = workspace:Raycast(hrp.Position, dir, params)
            if not hit then
                tpTo(candidate)
                tpTo(tpos)
                if closeEnough(getHRP().Position, tpos) then
                    return true
                end
            end
        end
    end

    -- สุดท้าย: snap ใกล้เป้า
    local _hrp = getHRP()
    if _hrp then _hrp.CFrame = CFrame.new(tpos + Vector3.new(0, SAFE_Y_OFFSET + 1.5, 0)) end
    return closeEnough(getHRP().Position, tpos)
end

local function ramInto(part)
    if not RAM_INTO_ENABLED then return false end
    local hrp = getHRP()
    if not (hrp and part and part.Parent) then return false end
    local tpos = part.Position
    local dir  = (tpos - hrp.Position)
    if dir.Magnitude < 1e-3 then dir = Vector3.new(0,1,0) else dir = dir.Unit end

    if USE_NOCLIP_FOR_RAM then setCharacterNoClip(true) end
    tweenTP(tpos + Vector3.new(0, HEIGHT_BOOST, 0)) -- ยกหัว
    tweenTP(tpos + dir * RAM_OVERSHOOT)             -- พุ่งเลย
    tweenTP(tpos)                                   -- วกกลับ
    if USE_NOCLIP_FOR_RAM then setCharacterNoClip(false) end

    local hrp2 = getHRP()
    return hrp2 and closeEnough(hrp2.Position, tpos)
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
gui.Name = "IL_MeditateHunt"
gui.ResetOnSpawn = false

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.new(0, 400, 0, 170)
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
title.Text = "Rarity 3–5 Auto (Meditate ↔ Hunt)"

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
tpBtn.Size = UDim2.new(0, 110, 0, 26)
tpBtn.Position = UDim2.new(0,110,0,60)
tpBtn.Text = "TP & Meditate"
tpBtn.Font = Enum.Font.GothamSemibold
tpBtn.TextSize = 14
tpBtn.BackgroundColor3 = Color3.fromRGB(40,60,70)
tpBtn.TextColor3 = Color3.fromRGB(120,255,150)
Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0,8)

local collectBtn = Instance.new("TextButton", frame)
collectBtn.Size = UDim2.new(0, 110, 0, 26)
collectBtn.Position = UDim2.new(0,230,0,60)
collectBtn.Text = "Collect Now"
collectBtn.Font = Enum.Font.GothamSemibold
collectBtn.TextSize = 14
collectBtn.BackgroundColor3 = Color3.fromRGB(70,60,40)
collectBtn.TextColor3 = Color3.fromRGB(255,240,170)
Instance.new("UICorner", collectBtn).CornerRadius = UDim.new(0,8)

local footer = Instance.new("TextLabel", frame)
footer.BackgroundTransparency = 1
footer.Position = UDim2.new(0,10,0,110)
footer.Size = UDim2.new(1,-20,0,24)
footer.Font = Enum.Font.Gotham
footer.TextSize = 12
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextColor3 = Color3.fromRGB(180,180,190)
footer.Text = "State: Auto=ON • Mode=Rarity"

local remainingLbl = Instance.new("TextLabel", frame)
remainingLbl.BackgroundTransparency = 1
remainingLbl.Position = UDim2.new(0,10,0,134)
remainingLbl.Size = UDim2.new(1,-20,0,24)
remainingLbl.Font = Enum.Font.Gotham
remainingLbl.TextSize = 12
remainingLbl.TextXAlignment = Enum.TextXAlignment.Right
remainingLbl.TextColor3 = Color3.fromRGB(180,180,190)
remainingLbl.Text = "Left: -"

local modeBtn = Instance.new("TextButton", frame)
modeBtn.Size = UDim2.new(0, 120, 0, 26)
modeBtn.Position = UDim2.new(0,10,0,140)
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
    footer.Text = string.format("State: Auto=%s • Mode=%s", AUTO_ENABLED and "ON" or "OFF", PRIORITY_MODE)
end)

tpBtn.MouseButton1Click:Connect(function()
    stopFlyingSword()         -- ปิดดาบก่อนทุกครั้งที่กลับมานั่ง
    tpTo(MEDITATE_POS)
    task.wait(0.05)
    startCultivate()          -- ไม่สแปม เพราะมี debounce
end)

collectBtn.MouseButton1Click:Connect(function()
    if #ordered == 0 then return end
    local node = orderedIdx()
    local info, part = node.info, node.part
    if not (part and part.Parent) then return end

    -- ยิง Remote ก่อน
    if collectViaRemote(info, part, 1.2) then return end

    -- ไม่ได้ -> fallback prompt
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
    footer.Text = string.format("State: Auto=%s • Mode=%s", AUTO_ENABLED and "ON" or "OFF", PRIORITY_MODE)
end)

-- update UI periodically
task.spawn(function()
    while true do
        task.wait(0.25)
        updateStatus()
    end
end)

-- keep HRP on respawn
LP.CharacterAdded:Connect(function(c)
    Char = c
    HRP = c:WaitForChild("HumanoidRootPart")
    task.delay(0.5, function()
        stopCultivate() -- กันติดสถานะคัลติ
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

--== AUTO LOOP: Meditate <-> Hunt (ไม่มี hop) ==--
local MODE = "Meditate"
local EMPTY_GRACE = 0.5

task.spawn(function()
    while task.wait(dynamicWait()) do
        if not AUTO_ENABLED then continue end
        refreshList()

        if MODE == "Meditate" then
            if #ordered == 0 then
                local hrp = getHRP()
                if hrp and not isNear(hrp.Position, MEDITATE_POS, 6) then
                    stopFlyingSword()
                    tpTo(MEDITATE_POS)
                end
                if not CultivateState.on then
                    startCultivate()
                end
                task.wait(EMPTY_GRACE)
                refreshList()
                if #ordered > 0 then
                    stopCultivate()
                    MODE = "Hunt"
                end
            else
                stopCultivate()
                MODE = "Hunt"
            end

        else -- MODE == "Hunt"
            if #ordered == 0 then
                -- เก็บ/หายหมด -> ปิดดาบก่อน แล้วกลับไปนั่ง
                stopFlyingSword()
                tpTo(MEDITATE_POS)
                task.wait(0.05)
                startCultivate()
                MODE = "Meditate"
            else
                for i, node in ipairs(ordered) do
                    if not node or not isValidTarget(node.part, node.info) then continue end

                    -- ลำดับบังคับ: Cultivate(false) -> FlyingSword(true)
                    stopCultivate()
                    task.wait(0.12)
                    useFlyingSword()
                    task.wait(0.12)

                    setWaypoint(node.part)

                    -- ★ พุ่งชนเข้าเป้า (ram-into) ก่อน
                    local ok = ramInto(node.part)
                    if not ok then
                        -- ถ้าไม่เข้าเขต -> ใช้ approach assist ล้อมมุม
                        ok = approachTarget(node.part)
                        if not ok then
                            -- ยังไม่ถึงจริง ๆ ก็ลองตรง ๆ อีกครั้ง
                            tpTo(node.part.Position)
                        end
                    end

                    -- ★ ปิดดาบชั่วคราวก่อนเก็บ (ถ้าตั้งค่า)
                    if not COLLECT_WITH_SWORD then
                        stopFlyingSword()
                        task.wait(0.05)
                    end

                    -- ★ ยิง Remote Collect ก่อน
                    local done = false
                    if collectViaRemote(node.info, node.part, 1.2) then
                        done = true
                    else
                        -- Fallback: Prompt (hold-aware)
                        local t0 = os.clock()
                        while os.clock() - t0 < MAX_TARGET_STUCK_TIME do
                            if not isValidTarget(node.part, node.info) then break end
                            if collectIfNear(node.info) then
                                waitGoneOrTimeout(node.part, node.info, 1.2)
                                done = true
                                break
                            end
                            task.wait(0.08)
                        end
                    end

                    -- เปิดดาบกลับถ้าปิดไว้
                    if not COLLECT_WITH_SWORD then
                        task.wait(0.05)
                        useFlyingSword()
                    end
                end

                -- เช็คอีกรอบ -> ถ้าไม่เหลือค่อยกลับไปนั่ง (ปิดดาบก่อน)
                refreshList()
                if #ordered == 0 then
                    stopFlyingSword()
                    tpTo(MEDITATE_POS)
                    task.wait(0.05)
                    startCultivate()
                    MODE = "Meditate"
                end
            end
        end
    end
end)
