-- IMMORTAL LUCK • R4–R5 AUTO (Meditate <-> Hunt) • Hunt uses TP-only + Return-to-Origin
-- สำหรับทดสอบใน private server เท่านั้น

--== Services ==--
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LP  = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local HRP = Char:WaitForChild("HumanoidRootPart")

--== Config ==--
local ROOT_NAME              = "Resources"
local ONLY_THESE             = { [4]=true, [5]=true } -- เฉพาะ R4/R5
local NAME_BLACKLIST         = { Trap=true, Dummy=true }
local MAX_SCAN_RANGE         = 6000

local COLLECT_RANGE          = 14
local MAX_TARGET_STUCK_TIME  = 10

local TP_STEP_STUDS          = 120
local SAFE_Y_OFFSET          = 2
local HEIGHT_BOOST           = 30
local DROP_HEIGHT            = 18

local MEDITATE_POS           = Vector3.new(-2615.4, 141.752, 1385.9)
local AUTO_ENABLED           = true
local PRIORITY_MODE          = "Rarity" -- "Rarity" | "Nearest" | "Score"

local USE_REMOTE_COLLECT     = true
local COLLECT_WITH_SWORD     = false

-- ★ บังคับ Hunt ใช้ TP ล้วน และ “กลับตำแหน่งเดิม” หลังเก็บ
local FORCE_HUNT_TP          = true
local RETURN_TO_ORIGIN       = true

local RAM_INTO_ENABLED       = false -- ปิดเพื่อให้แน่ใจว่า Hunt ใช้ TP ล้วน

local RARITY_NAME            = { [1]="Common", [2]="Rare", [3]="Legendary", [4]="Tier4", [5]="Tier5" }

--== Helpers ==--
local function safeParent()
    local ok,hui = pcall(function() return gethui and gethui() end)
    if ok and typeof(hui)=="Instance" then return hui end
    return game.CoreGui or LP:WaitForChild("PlayerGui")
end

local function getPart(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function getHRP()
    if HRP and HRP.Parent then return HRP end
    if LP.Character then
        HRP = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:WaitForChild("HumanoidRootPart", 5)
    end
    return HRP
end

local function distance(a, b) return (a - b).Magnitude end
local function isNear(a,b,r) return distance(a,b) <= (r or 4) end

--== Line-of-sight / Ground check ==--
local function hasLineOfSight(fromPos, toPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    local dir = toPos - fromPos
    local result = workspace:Raycast(fromPos, dir, params)
    return result == nil
end

local function rayDown(origin, maxDist)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    return workspace:Raycast(origin, Vector3.new(0, -math.abs(maxDist or 200), 0), params)
end

local function isGrounded(pos)
    local hit = rayDown(pos + Vector3.new(0,2,0), 6)
    return hit ~= nil, hit and hit.Position or nil
end

--== Safe Snap + Step TP ==--
local function _safeSnap(toPos)
    local h = getHRP(); if not h then return end
    local grounded, floorPos = isGrounded(toPos)
    local target = toPos
    if grounded and floorPos then
        target = Vector3.new(toPos.X, math.max(toPos.Y, floorPos.Y + SAFE_Y_OFFSET), toPos.Z)
    else
        target = toPos + Vector3.new(0, math.max(6, SAFE_Y_OFFSET), 0)
    end
    h.CFrame = CFrame.new(target)
end

-- เดินเส้นทางด้วย TP เป็นสเต็ป (ไม่ใช้ Tween)
local function _stepPath(fromPos, toPos)
    local start  = fromPos
    local target = toPos
    if not hasLineOfSight(start, target) then
        target = target + Vector3.new(0, HEIGHT_BOOST, 0)
    end
    local dist  = (target - start).Magnitude
    local step  = math.max(1, TP_STEP_STUDS)
    local steps = math.max(1, math.ceil(dist / step))
    for i = 1, steps do
        local p = start:Lerp(target, i/steps)
        _safeSnap(p)
        RunService.Heartbeat:Wait()
    end
end

local function tpTo(vec3)
    local h = getHRP(); if not h then return end
    _stepPath(h.Position, vec3)
end

--== Remotes (Cultivate / Sword) ==--
local CUL_MIN_INTERVAL = 1.2
local CultivateState = { on = false, lastSend = 0 }
local function setCultivate(desired)
    local now = os.clock()
    if CultivateState.on == desired and (now - CultivateState.lastSend) < CUL_MIN_INTERVAL then return end
    CultivateState.lastSend = now; CultivateState.on = desired
    local ev = RS:FindFirstChild("Remotes") and RS.Remotes:FindChild("Cultivate") or RS.Remotes:FindFirstChild("Cultivate")
    if ev then pcall(function() ev:FireServer(desired) end) end
end
local function startCultivate() setCultivate(true) end
local function stopCultivate()  setCultivate(false) end

local function useFlyingSword()
    local ev = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("FlyingSword")
    if ev then pcall(function() ev:FireServer(true) end) end
end
local function stopFlyingSword()
    local ev = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("FlyingSword")
    if ev then pcall(function() ev:FireServer(false) end) end
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
    local keys = { "CollectId","HerbId","ResourceId","ObjectId","Id","ID","Guid","GUID","UUID","Uid","uid","HerbUUID","RootId" }
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
    return m
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
    local ok, err = pcall(function()
        RS:WaitForChild("Remotes"):WaitForChild("Collect"):FireServer(id)
    end)
    if not ok then warn("[IL] Collect remote failed:", err); return false end
    return waitGoneOrTimeout(part, info, timeout or 1.2)
end

local function pressPrompt(prompt)
    if not prompt or typeof(fireproximityprompt) ~= "function" then return false end
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
    local prompt = info.obj and info.obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    local h = getHRP()
    local p = info.obj and getPart(info.obj)
    if prompt and h and p and (h.Position - p.Position).Magnitude <= range then
        return pressPrompt(prompt)
    end
    return false
end

--== ROOT / Targets / ESP ==--
local ROOT = workspace:WaitForChild(ROOT_NAME)
local targets = {}  -- [part] = {obj=Instance, rarity=number, bb, hl, lbl}

local function makeESP(part, rarity)
    local bb = Instance.new("BillboardGui")
    bb.Name = "IL_ESP"; bb.AlwaysOnTop = true
    bb.Size = UDim2.new(0, 220, 0, 48); bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.Adornee = part; bb.Parent = part

    local frame = Instance.new("Frame", bb)
    frame.Size = UDim2.new(1,0,1,0); frame.BackgroundTransparency = 0.15; frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)

    local lbl = Instance.new("TextLabel", frame)
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1,-10,1,-10); lbl.Position = UDim2.new(0,5,0,5)
    lbl.Font = Enum.Font.GothamSemibold; lbl.TextScaled = true
    lbl.TextColor3 = Color3.fromRGB(255,255,255); lbl.TextStrokeTransparency = 0.5

    local hl = Instance.new("Highlight")
    hl.Adornee = part; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.7; hl.OutlineTransparency = 0.1; hl.Parent = part
    if rarity==5 then hl.OutlineColor = Color3.fromRGB(255,180,255)
    elseif rarity==4 then hl.OutlineColor = Color3.fromRGB(180,120,255)
    elseif rarity==3 then hl.OutlineColor = Color3.fromRGB(120,220,255) end

    return bb, lbl, hl
end

local function forget(part)
    local rec = targets[part]; if not rec then return end
    pcall(function() if rec.bb then rec.bb:Destroy() end end)
    pcall(function() if rec.hl then rec.hl:Destroy() end end)
    targets[part] = nil
end

local function attach(inst)
    local r = inst:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return end
    if NAME_BLACKLIST[inst.Name] then return end
    local part = getPart(inst); if not part or targets[part] then return end
    local bb, lbl, hl = makeESP(part, r)
    targets[part] = {obj=inst, rarity=r, bb=bb, lbl=lbl, hl=hl}
    inst.AncestryChanged:Connect(function(_, parent) if not parent then forget(part) end end)
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

--== Ordering ==--
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
    if #ordered == 0 then idx = 1 else idx = math.clamp(idx, 1, #ordered) end
end

--== HUD ย่อ ==--
local gui = Instance.new("ScreenGui", safeParent())
gui.ResetOnSpawn = false; gui.Name = "IL_HuntTP_Return"

local label = Instance.new("TextLabel", gui)
label.BackgroundTransparency = 0.2
label.BackgroundColor3 = Color3.fromRGB(25,25,30)
label.TextColor3 = Color3.fromRGB(230,230,240)
label.TextSize = 14
label.Font = Enum.Font.GothamSemibold
label.Size = UDim2.new(0, 420, 0, 22)
label.Position = UDim2.new(0, 60, 0, 70)
label.Text = "IL: -"

local function setHUD(txt) label.Text = "IL: "..txt end

--== Hunt: TP-only helper (ยกหัวแล้วลง) ==--
local function Hunt_TP_ToPart(part)
    local h = getHRP(); if not (h and part and part.Parent) then return false end
    local tpos = part.Position
    -- ยกหัวก่อน แล้วลงตรงเป้า
    _stepPath(h.Position, tpos + Vector3.new(0, HEIGHT_BOOST, 0))
    _stepPath(getHRP().Position, tpos)
    -- สำรอง snap ใกล้ ๆ
    if (getHRP().Position - tpos).Magnitude > (COLLECT_RANGE + 1) then
        _safeSnap(tpos + Vector3.new(0, SAFE_Y_OFFSET + 1.5, 0))
    end
    return (getHRP().Position - tpos).Magnitude <= (COLLECT_RANGE + 1)
end

--== Loop ตัวหลัก: Meditate <-> Hunt (TP-only + return to origin) ==--
local MODE = "Meditate"
local function dynamicWait()
    local fps=60; -- แบบง่าย ๆ
    return 0.15
end

task.spawn(function()
    while task.wait(dynamicWait()) do
        if not AUTO_ENABLED then setHUD("Paused"); continue end
        refreshList()

        if MODE == "Meditate" then
            if #ordered == 0 then
                local h = getHRP()
                if h and not isNear(h.Position, MEDITATE_POS, 6) then
                    stopFlyingSword()
                    tpTo(MEDITATE_POS)
                end
                if not CultivateState.on then startCultivate() end
                task.wait(0.5)
                refreshList()
                if #ordered > 0 then stopCultivate(); MODE = "Hunt" end
            else
                stopCultivate(); MODE = "Hunt"
            end

        else -- MODE == "Hunt"
            if #ordered == 0 then
                stopFlyingSword(); tpTo(MEDITATE_POS); task.wait(0.05); startCultivate(); MODE = "Meditate"
            else
                for i, node in ipairs(ordered) do
                    if not node or not isValidTarget(node.part, node.info) then continue end

                    -- ★ 1) Bookmark ตำแหน่งก่อนออกล่า
                    local beforePos = getHRP() and getHRP().Position

                    -- 2) เตรียมสถานะ
                    stopCultivate(); task.wait(0.12)
                    useFlyingSword(); task.wait(0.12)

                    -- 3) เข้าเป้าด้วย TP เท่านั้น
                    local ok = false
                    if FORCE_HUNT_TP then
                        -- ปิดดาบชั่วคราวก่อนเก็บเพื่อให้ Prompt ติดง่าย (ถ้าตั้งค่า)
                        if not COLLECT_WITH_SWORD then stopFlyingSword(); task.wait(0.05) end
                        ok = Hunt_TP_ToPart(node.part)
                    else
                        -- เผื่ออนาคต: ถ้าอยากเปิดโหมดวิธีอื่นก็มาใส่ตรงนี้ได้
                        ok = Hunt_TP_ToPart(node.part)
                    end

                    -- 4) Collect
                    local done = false
                    if collectViaRemote(node.info, node.part, 1.2) then
                        done = true
                    else
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

                    -- 5) เปิดดาบกลับ (ถ้าปิดไว้)
                    if not COLLECT_WITH_SWORD then task.wait(0.05); useFlyingSword() end

                    -- 6) ★ กลับตำแหน่งเดิม (ถ้าเปิด RETURN_TO_ORIGIN)
                    if RETURN_TO_ORIGIN and beforePos then
                        tpTo(beforePos)
                    end
                end

                -- จบรอบ: ถ้าไม่มีเป้าแล้ว -> กลับไปนั่ง
                refreshList()
                if #ordered == 0 then
                    stopFlyingSword(); tpTo(MEDITATE_POS); task.wait(0.05); startCultivate(); MODE = "Meditate"
                end
            end
        end

        -- HUD
        if #ordered == 0 then
            setHUD(("Mode=%s | Left=0"):format(MODE))
        else
            local n = ordered[1]
            local r = n.info.rarity
            local name = RARITY_NAME[r] or ("R"..tostring(r))
            setHUD(("Mode=%s | Target=%s(R%d) • %.0f studs | Left=%d | Hunt=TP-only+Return")
                    :format(MODE, name, r, n.dist, #ordered))
        end
    end
end)

--== Respawn safety ==--
LP.CharacterAdded:Connect(function(c)
    Char = c
    HRP = c:WaitForChild("HumanoidRootPart")
    task.delay(0.5, function() stopCultivate() end)
end)
