-- MINIMAL AUTO (เวอร์ชันแก้แกว่ง/ค้างบินขึ้นลง): เปิดดาบ -> TP -> เก็บ -> กลับจุด
-- ใช้เพื่อทดสอบใน private server เท่านั้น

--== Services ==--
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local LP           = Players.LocalPlayer
local Char         = LP.Character or LP.CharacterAdded:Wait()
local HRP          = Char:WaitForChild("HumanoidRootPart")

--== Config ==--
local ROOT_NAME             = "Resources"         -- โฟลเดอร์ทรัพยากรใน workspace
local HOME_POS              = Vector3.new(-519.435, -5.452, -386.665) -- จุดกลับ
local SPEED_STUDS_PER_S     = 150
local MIN_TWEEN_TIME        = 0.08
local TP_STEP_STUDS         = 90
local SAFE_Y_OFFSET         = 1.5                 -- ใช้เฉพาะ "ระหว่างทาง" และเฉพาะตอน LoS ไม่ผ่าน
local HEIGHT_BOOST          = 12                  -- ยกหัวถ้า LoS ไม่ผ่านตอนเริ่ม
local MAX_DROP_PER_HOP      = 10
local MAX_SCAN_RANGE        = 6000
local COLLECT_RANGE         = 14
local MAX_TARGET_STUCK_TIME = 6
local ONLY_THESE            = { [3]=true, [4]=true, [5]=true } -- เอาเฉพาะ R3-5
local NAME_BLACKLIST        = { Trap=true, Dummy=true }         -- กันของไม่ใช่สมุนไพร

--== Runtime ==--
local ROOT = workspace:WaitForChild(ROOT_NAME)
local targets = {}  -- [part] = {obj=Instance, rarity=number}
local currentTween
local lastGroundY
local lastTP

--== Helpers ==--
local function getHRP()
    if HRP and HRP.Parent then return HRP end
    if LP.Character then
        HRP = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:WaitForChild("HumanoidRootPart", 5)
    end
    return HRP
end

local function getPart(inst)
    if inst:IsA("BasePart") then return inst end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function zeroVel(hrp)
    if not hrp then return end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function hasLineOfSight(fromPos, toPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    return workspace:Raycast(fromPos, toPos - fromPos, params) == nil
end

local function snapToFloor(pos, up, down)
    up, down = up or 60, down or 300
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    local res = workspace:Raycast(pos + Vector3.new(0,up,0), Vector3.new(0,-up-down,0), params)
    if res then
        lastGroundY = res.Position.Y + 0.10
        return Vector3.new(pos.X, lastGroundY, pos.Z)
    end
    if lastGroundY then
        return Vector3.new(pos.X, lastGroundY, pos.Z)
    end
    return pos
end

--== Tween TP (เวอร์ชันกันแกว่ง/ค้าง) ==--
local function tweenHop(toPos)
    local h = getHRP(); if not h then return end
    local dist = (h.Position - toPos).Magnitude
    local t = math.max(MIN_TWEEN_TIME, dist / SPEED_STUDS_PER_S)
    if currentTween and currentTween.PlaybackState == Enum.PlaybackState.Playing then
        currentTween:Cancel()
    end
    currentTween = TweenService:Create(h, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = CFrame.new(toPos)})
    currentTween:Play()
    local elapsed = 0
    while currentTween and currentTween.PlaybackState == Enum.PlaybackState.Playing do
        local dt = RunService.Heartbeat:Wait()
        elapsed += dt
        if elapsed > t + 2 then
            currentTween:Cancel()
            h.CFrame = CFrame.new(snapToFloor(toPos))
            break
        end
    end
    zeroVel(h)
end

local function tweenTP(targetPos)
    local h = getHRP(); if not h then return end
    local startPos = h.Position

    if not hasLineOfSight(startPos, targetPos) then
        targetPos = targetPos + Vector3.new(0, HEIGHT_BOOST, 0)
    end

    local dist  = (targetPos - startPos).Magnitude
    local steps = math.max(1, math.ceil(dist / TP_STEP_STUDS))

    for i = 1, steps do
        local cur = getHRP().Position
        local t   = i/steps
        local raw = startPos:Lerp(targetPos, t)
        local p

        if i < steps then
            -- ยกหัวเฉพาะกรณี LoS จากตำแหน่ง "ปัจจุบัน" ไม่ผ่าน
            if not hasLineOfSight(cur, raw) then
                p = raw + Vector3.new(0, math.min(SAFE_Y_OFFSET, 3), 0)
            else
                p = raw
            end
        else
            p = snapToFloor(raw) -- ฮอพสุดท้ายติดพื้นเสมอ
        end

        -- จำกัดการตกต่อฮอพ
        local drop = cur.Y - p.Y
        if drop > MAX_DROP_PER_HOP then
            local mid = Vector3.new(p.X, cur.Y - MAX_DROP_PER_HOP, p.Z)
            tweenHop(mid); zeroVel(getHRP())
        end

        tweenHop(p); zeroVel(getHRP())
    end
end

local function tpTo(vec3)
    local h = getHRP(); if not h then return end
    if lastTP and (lastTP - vec3).Magnitude < 1.0 then return end
    tweenTP(vec3); lastTP = vec3
end

--== FlyingSword & Collect ==--
local function useFlyingSword()
    local ev = RS:WaitForChild("Remotes"):WaitForChild("FlyingSword")
    pcall(function() ev:FireServer(true) end)
end
local function stopFlyingSword()
    local ev = RS:WaitForChild("Remotes"):WaitForChild("FlyingSword")
    pcall(function() ev:FireServer(false) end)
end

local function _normalizeId(id)
    if not id or type(id) ~= "string" then return nil end
    id = id:gsub("%s+", "")
    if id == "" then return nil end
    if id:sub(1,1) ~= "{" then id = "{"..id.."}" end
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
            local name = d.Name:lower()
            if name=="collectid" or name=="herbid" or name=="resourceid" or
               name=="objectid" or name=="id" or name=="guid" or
               name=="uuid" or name=="uid" or name=="herbuuid" or name=="rootid" then
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
        if not part or not part.Parent or not info or not info.obj or not info.obj.Parent then
            return true
        end
        task.wait(0.05)
    end
    return false
end

local function collectViaRemote(info, part, timeout)
    local id = _findCollectIdFromInst(info and info.obj)
    if not id then return false end
    local ok = pcall(function()
        RS:WaitForChild("Remotes"):WaitForChild("Collect"):FireServer(id)
    end)
    if not ok then return false end
    return waitGoneOrTimeout(part, info, timeout or 1.2)
end

local function pressPrompt(prompt)
    if not prompt or typeof(fireproximityprompt) ~= "function" then return false end
    local hd = prompt.HoldDuration or 0
    if hd <= 0 then
        pcall(function() fireproximityprompt(prompt) end)
    else
        local t0 = os.clock()
        pcall(function() fireproximityprompt(prompt, 1) end)
        while os.clock() - t0 < hd + 0.05 do task.wait() end
    end
    return true
end

local function collectIfNear(info, range)
    range = range or COLLECT_RANGE
    local prompt = info.obj and info.obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    local h = getHRP()
    local p = info.obj and getPart(info.obj)
    if prompt and h and p and (h.Position - p.Position).Magnitude <= range then
        zeroVel(h)
        return pressPrompt(prompt)
    end
    return false
end

--== Target Tracking (เฉพาะมี Rarity 3–5) ==--
local function isHerbLike(inst) return true end

local function attach(inst)
    local r = inst:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return end
    if NAME_BLACKLIST[inst.Name] then return end
    if not isHerbLike(inst) then return end
    local part = getPart(inst); if not part or targets[part] then return end
    targets[part] = {obj=inst, rarity=r}
    inst.AncestryChanged:Connect(function(_, parent)
        if not parent then targets[part] = nil end
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

local function nearestTarget()
    local h = getHRP(); if not h then return nil end
    local best, bestDist
    for part,info in pairs(targets) do
        if part and part.Parent and info and info.obj and info.obj.Parent and info.obj:IsDescendantOf(ROOT) then
            local d = (h.Position - part.Position).Magnitude
            if d <= MAX_SCAN_RANGE then
                if not bestDist or d < bestDist or (d==bestDist and (info.rarity or 0) > (best.rarity or 0)) then
                    best, bestDist = {part=part, info=info, dist=d}, d
                end
            end
        end
    end
    return best
end

-- ทำให้ HOME_POS ติดพื้นตั้งแต่ต้น
HOME_POS = snapToFloor(HOME_POS)

--== Watchdog กันค้าง/แกว่งขึ้นลงกับที่ ==--
local STUCK_RADIUS = 2.0
local STUCK_TIME   = 1.6
local _stuckOrigin, _stuckSince

task.spawn(function()
    while true do
        task.wait(0.2)
        local h = getHRP(); if not h then continue end
        local p = h.Position

        if not _stuckOrigin then
            _stuckOrigin, _stuckSince = p, os.clock()
        end

        local sameSpot = (p - _stuckOrigin).Magnitude <= STUCK_RADIUS
        if sameSpot then
            local vy = math.abs(h.AssemblyLinearVelocity.Y)
            if (os.clock() - _stuckSince) > STUCK_TIME and vy > 0.5 then
                -- กู้คืน
                if currentTween and currentTween.PlaybackState == Enum.PlaybackState.Playing then
                    currentTween:Cancel()
                end
                local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
                h.Anchored = false
                zeroVel(h)
                h.CFrame = CFrame.new(snapToFloor(HOME_POS))
                zeroVel(h)
                lastTP, lastGroundY = nil, nil
                _stuckOrigin, _stuckSince = h.Position, os.clock()
            end
        else
            _stuckOrigin, _stuckSince = p, os.clock()
        end
    end
end)

--== Main Minimal Loop ==--
task.spawn(function()
    useFlyingSword()
    while true do
        task.wait(0.15)

        local node = nearestTarget()
        if not node then
            tpTo(HOME_POS)
        else
            useFlyingSword()
            tpTo(node.part.Position)

            if not collectViaRemote(node.info, node.part, 1.2) then
                local t0 = os.clock()
                while os.clock() - t0 < MAX_TARGET_STUCK_TIME do
                    if not node.part or not node.part.Parent or not node.info or not node.info.obj or not node.info.obj.Parent then
                        break
                    end
                    if collectIfNear(node.info) then
                        waitGoneOrTimeout(node.part, node.info, 1.0)
                        break
                    end
                    task.wait(0.08)
                end
            end

            tpTo(HOME_POS)
        end
    end
end)

-- กันรีสปอนแล้วค่า HRP หาย
LP.CharacterAdded:Connect(function(c)
    Char = c
    HRP = c:WaitForChild("HumanoidRootPart")
    task.delay(0.2, function()
        useFlyingSword()
    end)
end)
