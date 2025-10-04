-- IMMORTAL LUCK • R3–R5 AUTO (Meditate <-> Hunt) • Unified MoveTo (StepTP / TweenTP / Auto)
-- สำหรับทดสอบใน private server เท่านั้น

--== Services ==--
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService") -- ใช้ได้ถ้าเซิร์ฟเวอร์ไม่บล็อค
local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local HRP = Char:WaitForChild("HumanoidRootPart")

--== Config ==--
local ROOT_NAME              = "Resources"
local MAX_SCAN_RANGE         = 6000
local ONLY_THESE             = { [4]=true, [5]=true }      -- โฟกัส R4/R5
local NAME_BLACKLIST         = { Trap=true, Dummy=true }
local COLLECT_RANGE          = 14
local MAX_TARGET_STUCK_TIME  = 10
local MEDITATE_POS           = Vector3.new(-2615.4, 141.752, 1385.9)

-- Move config
local TP_STEP_STUDS          = 120
local SAFE_Y_OFFSET          = 2
local HEIGHT_BOOST           = 30
local DROP_HEIGHT            = 18
local APPROACH_RINGS         = {6, 9, 12, 16}
local APPROACH_STEP_DEG      = 30

-- Movement mode:
-- "Auto" | "StepTP" | "TweenTP"
local MOVEMENT_MODE          = "Auto"

-- Tween speed (studs/sec). ถ้า <=0 แปลว่าไม่ใช้ Tween
-- (แนวคิด tpspeed ที่ขอ: ระยะ/วินาที => เวลา Tween)
local TP_SPEED_STUDS_PER_S   = 250

-- แกนต่อสู้/ดาบ/เก็บ
local COLLECT_WITH_SWORD     = false
local USE_REMOTE_COLLECT     = true
local RAM_INTO_ENABLED       = true
local RAM_OVERSHOOT          = 8
local USE_NOCLIP_FOR_RAM     = true

-- ลูปทำงานอัตโนมัติ
local AUTO_ENABLED           = true
local PRIORITY_MODE          = "Rarity" -- "Rarity" | "Nearest" | "Score"

--== Labels ==--
local RARITY_NAME = { [1]="Common", [2]="Rare", [3]="Legendary", [4]="Tier4", [5]="Tier5" }

--== Helpers ==--
local function getHRP()
    if HRP and HRP.Parent then return HRP end
    if LP.Character then
        HRP = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:WaitForChild("HumanoidRootPart", 5)
    end
    return HRP
end
local function distance(a,b) return (a-b).Magnitude end
local function isNear(a,b,r) return distance(a,b) <= (r or 4) end

-- noclip (ใช้ตอนพุ่งชน)
local __origCollide = nil
local function setCharacterNoClip(on)
    if on then
        if __origCollide then return end
        __origCollide = {}
        for _,p in ipairs((LP.Character or Char):GetDescendants()) do
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

-- line-of-sight
local function hasLineOfSight(fromPos, toPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    local result = workspace:Raycast(fromPos, toPos - fromPos, params)
    return result == nil
end

--== Remotes: Cultivate / FlyingSword ==--
local CUL_MIN_INTERVAL = 1.2
local CultivateState = { on=false, lastSend=0 }
local function setCultivate(desired)
    local now = os.clock()
    if CultivateState.on == desired and (now - CultivateState.lastSend) < CUL_MIN_INTERVAL then return end
    CultivateState.lastSend = now
    CultivateState.on = desired
    local ev = RS:WaitForChild("Remotes"):WaitForChild("Cultivate")
    pcall(function() ev:FireServer(desired) end)
end
local function startCultivate() setCultivate(true) end
local function stopCultivate()  setCultivate(false) end

local function useFlyingSword()
    pcall(function() RS.Remotes.FlyingSword:FireServer(true) end)
end
local function stopFlyingSword()
    pcall(function() RS.Remotes.FlyingSword:FireServer(false) end)
end

--== Remote Collect ==--
local function _normalizeId(id)
    if not id or type(id)~="string" then return nil end
    id = id:gsub("%s+","")
    if id=="" then return nil end
    if id:sub(1,1)~="{" then id = "{"..id.."}" end
    return id
end
local function _findCollectIdFromInst(inst)
    if not inst or not inst.Parent then return nil end
    local keys = {"CollectId","HerbId","ResourceId","ObjectId","Id","ID","Guid","GUID","UUID","Uid","uid","HerbUUID","RootId"}
    for _,k in ipairs(keys) do
        local v = inst:GetAttribute(k)
        if v and type(v)=="string" and #v>0 then return _normalizeId(v) end
    end
    for _,d in ipairs(inst:GetDescendants()) do
        if d:IsA("StringValue") then
            local n = d.Name:lower()
            if n=="collectid" or n=="herbid" or n=="resourceid" or n=="objectid" or n=="id" or n=="guid" or n=="uuid" or n=="uid" or n=="herbuuid" or n=="rootid" then
                if d.Value and d.Value~="" then return _normalizeId(d.Value) end
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
        if not part or not part.Parent or not info or not info.obj or not info.obj.Parent then return true end
        task.wait(0.05)
    end
    return false
end
local function collectViaRemote(info, part, timeout)
    if not USE_REMOTE_COLLECT then return false end
    local id = _findCollectIdFromInst(info and info.obj)
    if not id then return false end
    local ok,err = pcall(function() RS.Remotes.Collect:FireServer(id) end)
    if not ok then warn("[IL] Collect remote failed:", err) return false end
    return waitGoneOrTimeout(part, info, timeout or 1.2)
end

local function pressPrompt(prompt)
    if not prompt or typeof(fireproximityprompt)~="function" then return false end
    local hd = prompt.HoldDuration or 0
    if hd <= 0 then pcall(function() fireproximityprompt(prompt) end)
    else
        local t0 = os.clock()
        pcall(function() fireproximityprompt(prompt, 1) end)
        while os.clock() - t0 < hd + 0.05 do task.wait() end
    end
    return true
end

local function collectIfNear(info, range)
    range = range or COLLECT_RANGE
    local hrp = getHRP()
    local p = info.obj and (info.obj:IsA("BasePart") and info.obj or info.obj:FindFirstChildWhichIsA("BasePart", true))
    local prompt = info.obj and info.obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if hrp and p and prompt and distance(hrp.Position, p.Position) <= range then
        return pressPrompt(prompt)
    end
    return false
end

--== Movement Core (Unified MoveTo) ==--

-- snap ปลอดภัย (กันจมพื้น)
local function _safeSnap(p)
    local h = getHRP(); if not h then return end
    h.CFrame = CFrame.new(p + Vector3.new(0, SAFE_Y_OFFSET, 0))
end

-- StepTP: เดินเส้นทางด้วยวาร์ปเป็นสเต็ป
local function _stepPath(fromPos, toPos)
    local start = fromPos
    local target = toPos
    if not hasLineOfSight(start, target) then
        target = target + Vector3.new(0, HEIGHT_BOOST, 0)
    end
    local dist  = (target - start).Magnitude
    local step  = math.max(1, TP_STEP_STUDS)
    local steps = math.max(1, math.ceil(dist / step))
    for i=1, steps do
        local p = start:Lerp(target, i/steps)
        _safeSnap(p)
        RunService.Heartbeat:Wait()
    end
end

-- TweenTP: tween ด้วย “ความเร็ว (studs/sec)”
local function _tweenPathBySpeed(fromPos, toPos, speed)
    local h = getHRP(); if not h then return end
    if not TweenService or type(speed)~="number" or speed <= 0 then
        return _stepPath(fromPos, toPos) -- fallback
    end
    local target = toPos
    if not hasLineOfSight(fromPos, target) then
        target = target + Vector3.new(0, HEIGHT_BOOST, 0)
    end
    local dist = (target - fromPos).Magnitude
    local duration = math.max(0.02, dist / speed)

    local tw = nil
    local ok,err = pcall(function()
        tw = TweenService:Create(h, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(target + Vector3.new(0, SAFE_Y_OFFSET, 0))})
        tw:Play()
    end)
    if not ok or not tw then
        warn("[IL] Tween failed, fallback StepTP:", err)
        return _stepPath(fromPos, target)
    end

    local t0 = os.clock()
    tw.Completed:Wait()
    -- fail-safe: ถ้าติดค้างเกิน 2s หลังเวลา ค่อย snap
    if os.clock() - t0 > duration + 2 then
        _safeSnap(target)
    end
end

-- API เดียวที่ส่วนอื่นเรียก
local function MoveTo(vec3)
    local h = getHRP(); if not h or not vec3 then return end
    local start = h.Position
    if MOVEMENT_MODE == "StepTP" then
        return _stepPath(start, vec3)
    elseif MOVEMENT_MODE == "TweenTP" then
        return _tweenPathBySpeed(start, vec3, TP_SPEED_STUDS_PER_S)
    else -- Auto
        if TP_SPEED_STUDS_PER_S and TP_SPEED_STUDS_PER_S > 0 then
            return _tweenPathBySpeed(start, vec3, TP_SPEED_STUDS_PER_S)
        else
            return _stepPath(start, vec3)
        end
    end
end

-- สำหรับโหมดทดสอบ manual (กด L): รับทั้ง Vector3/CFrame/Part
local function ManualTweenTo(targetPosOrPart, speedOrDelay)
    local h = getHRP(); if not h then return end
    local target
    if typeof(targetPosOrPart)=="Instance" and targetPosOrPart:IsA("BasePart") then
        target = targetPosOrPart.Position
    elseif typeof(targetPosOrPart)=="CFrame" then
        target = targetPosOrPart.Position
    else
        target = targetPosOrPart
    end
    if typeof(speedOrDelay)=="number" and speedOrDelay >= 1 then
        -- ถ้าอยากใช้ “เวลาแน่นอน (วินาที)” แทน speed
        local duration = speedOrDelay
        local ok,tw = pcall(function()
            local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
            local t = TweenService:Create(h, info, {CFrame = CFrame.new(target + Vector3.new(0, SAFE_Y_OFFSET, 0))})
            t:Play(); return t
        end)
        if ok and tw then tw.Completed:Wait() else _safeSnap(target) end
    else
        -- ใช้แบบความเร็ว studs/sec (tpspeed)
        local start = h.Position
        _tweenPathBySpeed(start, target, math.max(1, TP_SPEED_STUDS_PER_S))
    end
end

--== Approach / Ram-Into ==--
local function closeEnough(hrpPos, targetPos) return distance(hrpPos, targetPos) <= (COLLECT_RANGE + 1) end

local function approachTarget(part)
    local h = getHRP(); if not (h and part and part.Parent) then return false end
    local tpos = part.Position

    -- ตรงดิ่งก่อน
    MoveTo(tpos)
    if closeEnough(getHRP().Position, tpos) then return true end

    -- ยกหัวแล้วลง
    MoveTo(tpos + Vector3.new(0, DROP_HEIGHT, 0))
    MoveTo(tpos)
    if closeEnough(getHRP().Position, tpos) then return true end

    -- ล้อมวง
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    for _,radius in ipairs(APPROACH_RINGS) do
        for deg=0, 360-APPROACH_STEP_DEG, APPROACH_STEP_DEG do
            local r = math.rad(deg)
            local cand = tpos + Vector3.new(math.cos(r)*radius, SAFE_Y_OFFSET, math.sin(r)*radius)
            local hit = workspace:Raycast(h.Position, cand - h.Position, params)
            if not hit then
                MoveTo(cand); MoveTo(tpos)
                if closeEnough(getHRP().Position, tpos) then return true end
            end
        end
    end

    _safeSnap(tpos)
    return closeEnough(getHRP().Position, tpos)
end

local function ramInto(part)
    if not RAM_INTO_ENABLED then return false end
    local h = getHRP(); if not (h and part and part.Parent) then return false end
    local tpos = part.Position
    local dir = (tpos - h.Position); dir = (dir.Magnitude < 1e-3) and Vector3.new(0,1,0) or dir.Unit

    if USE_NOCLIP_FOR_RAM then setCharacterNoClip(true) end
    MoveTo(tpos + Vector3.new(0, HEIGHT_BOOST, 0))
    MoveTo(tpos + dir * RAM_OVERSHOOT)
    MoveTo(tpos)
    if USE_NOCLIP_FOR_RAM then setCharacterNoClip(false) end

    return closeEnough(getHRP().Position, tpos)
end

--== Scan/Track targets + ordering ==--
local ROOT = workspace:WaitForChild(ROOT_NAME)
local targets = {}  -- [part] = {obj=Instance, rarity=number}
local ordered, idx = {}, 1

local function getPart(inst)
    if inst:IsA("BasePart") then return inst end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end
local function attach(inst)
    local r = inst:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return end
    if NAME_BLACKLIST[inst.Name] then return end
    local part = getPart(inst); if not part or targets[part] then return end
    targets[part] = {obj=inst, rarity=r}
    inst.AncestryChanged:Connect(function(_, parent)
        if not parent then targets[part]=nil end
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
        targets = {}
        for _,d in ipairs(ROOT:GetDescendants()) do
            if d:GetAttribute("Rarity") ~= nil then attach(d) end
        end
        ROOT.DescendantAdded:Connect(function(d)
            if d:GetAttribute("Rarity") ~= nil then attach(d) end
        end)
    end
end)

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
local function isValidTarget(part, info)
    if not part or not part.Parent then return false end
    if not info or not info.obj or not info.obj.Parent then return false end
    if not info.obj:IsDescendantOf(ROOT) then return false end
    local r = info.obj:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return false end
    return true
end
local function refreshList()
    ordered = {}
    local h = getHRP(); if not h then return end
    for part,info in pairs(targets) do
        if isValidTarget(part, info) then
            local dist = distance(h.Position, part.Position)
            if dist <= MAX_SCAN_RANGE then
                table.insert(ordered, {part=part, info=info, dist=dist})
            end
        end
    end
    table.sort(ordered, sortNodes)
    if #ordered==0 then idx=1 else idx = math.clamp(idx,1,#ordered) end
end

--== HUD แบบย่อ (TextLabel) ==--
local gui = Instance.new("ScreenGui")
gui.Name = "IL_AutoCore"
gui.ResetOnSpawn = false
gui.Parent = (pcall(function() return gethui and gethui() end) and gethui()) or game.CoreGui or LP:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 0.2
label.BackgroundColor3 = Color3.fromRGB(25,25,30)
label.TextColor3 = Color3.fromRGB(230,230,240)
label.TextSize = 14
label.Font = Enum.Font.GothamSemibold
label.Size = UDim2.new(0, 360, 0, 22)
label.Position = UDim2.new(0, 60, 0, 70)
label.Text = "IL: -"
label.Parent = gui

local function setHUD(txt) label.Text = "IL: "..txt end

--== Auto loop ==--
local MODE = "Meditate"
local function updateHUD()
    refreshList()
    if #ordered == 0 then setHUD(("Mode=%s | Left=0"):format(MODE)); return end
    local n = ordered[idx]
    local rname = RARITY_NAME[n.info.rarity] or ("R"..tostring(n.info.rarity))
    setHUD(("Mode=%s | Target=%s (R%d) • %.0f studs | Left=%d | Move=%s%s")
        :format(MODE, rname, n.info.rarity, n.dist, #ordered, MOVEMENT_MODE, (MOVEMENT_MODE=="TweenTP" and ("@"..tostring(TP_SPEED_STUDS_PER_S).."s/s")) or ""))
end

-- โหลด-aware (พักตาม FPS)
local fps, alpha = 60, 0.05
RunService.Heartbeat:Connect(function(dt) fps = fps*(1-alpha) + (1/dt)*alpha end)
local function dynamicWait()
    if fps > 80 then return 0.10 elseif fps > 50 then return 0.15 elseif fps > 30 then return 0.22 else return 0.30 end
end

-- Anti-freeze
local lastPos, lastMove = nil, os.clock()
RunService.Heartbeat:Connect(function()
    local h = getHRP(); if not h then return end
    if lastPos and distance(h.Position, lastPos) > 1 then lastMove = os.clock() end
    lastPos = h.Position
end)
task.spawn(function()
    while task.wait(1.0) do
        if os.clock() - lastMove > 8 then refreshList() end
    end
end)

-- ตัวหลัก
task.spawn(function()
    while task.wait(dynamicWait()) do
        if not AUTO_ENABLED then updateHUD(); continue end
        refreshList()

        if MODE == "Meditate" then
            if #ordered == 0 then
                local h = getHRP()
                if h and not isNear(h.Position, MEDITATE_POS, 6) then
                    stopFlyingSword()
                    MoveTo(MEDITATE_POS)
                end
                if not CultivateState.on then startCultivate() end
            else
                stopCultivate()
                MODE = "Hunt"
            end

        else -- Hunt
            if #ordered == 0 then
                stopFlyingSword(); MoveTo(MEDITATE_POS); task.wait(0.05); startCultivate(); MODE = "Meditate"
            else
                for _,node in ipairs(ordered) do
                    if not isValidTarget(node.part, node.info) then continue end

                    stopCultivate(); task.wait(0.10)
                    useFlyingSword(); task.wait(0.10)

                    local ok = false
                    if RAM_INTO_ENABLED then ok = ramInto(node.part) end
                    if not ok then
                        ok = approachTarget(node.part)
                        if not ok then MoveTo(node.part.Position) end
                    end

                    if not COLLECT_WITH_SWORD then stopFlyingSword(); task.wait(0.05) end

                    local done = false
                    if collectViaRemote(node.info, node.part, 1.2) then
                        done = true
                    else
                        local t0 = os.clock()
                        while os.clock() - t0 < MAX_TARGET_STUCK_TIME do
                            if not isValidTarget(node.part, node.info) then break end
                            if collectIfNear(node.info) then waitGoneOrTimeout(node.part, node.info, 1.2); done = true; break end
                            task.wait(0.08)
                        end
                    end

                    if not COLLECT_WITH_SWORD then task.wait(0.05); useFlyingSword() end
                end
                refreshList()
                if #ordered == 0 then stopFlyingSword(); MoveTo(MEDITATE_POS); task.wait(0.05); startCultivate(); MODE="Meditate" end
            end
        end

        updateHUD()
    end
end)

--== Hotkeys / Controls ==--

-- L = Manual Tween Test (แนวคิด "pos + delay/tpspeed")
local TEST_POS   = Vector3.new(0,0,0)  -- ใส่ตำแหน่งทดสอบที่อยากไป
local TEST_DELAY = 0                   -- >0 จะบังคับใช้ "เวลา" แทนความเร็ว; =0 ใช้ความเร็ว TP_SPEED_STUDS_PER_S
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.L then
        if TEST_DELAY > 0 then
            ManualTweenTo(TEST_POS, TEST_DELAY) -- ใช้เวลาแน่นอน (วินาที)
        else
            ManualTweenTo(TEST_POS)             -- ใช้ความเร็ว studs/sec (tpspeed)
        end
    elseif input.KeyCode == Enum.KeyCode.K then
        -- สลับโหมดเคลื่อนที่
        MOVEMENT_MODE = (MOVEMENT_MODE=="Auto" and "StepTP") or (MOVEMENT_MODE=="StepTP" and "TweenTP") or "Auto"
        setHUD(("Switch Move=%s"):format(MOVEMENT_MODE))
    end
end)

-- รองรับ respawn
LP.CharacterAdded:Connect(function(c)
    Char = c
    HRP = c:WaitForChild("HumanoidRootPart")
    task.delay(0.5, function() stopCultivate() end)
end)
