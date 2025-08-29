--[[
Auto Herb (Confirmed Arg) — Immortal Luck
- ใช้ Remote: ReplicatedStorage.Remotes.Collect
- ส่งอาร์กิวเมนต์เดียว "{"..UUID.."}" (string ครอบด้วยวงเล็บปีกกา)
- หา UUID จาก Attributes / StringValue / PrimaryPart.Attributes (เฉพาะ Model)
- กัน error PrimaryPart บน Part/SpawnLocation ด้วยการเช็กชนิด + pcall
- รองรับ ProximityPrompt: ถ้าเจอจะกดให้ก่อน
- UI แสดงสถานะ/เป้าหมาย/ระยะ/จำนวนเก็บ ลากได้
Keys: H=Toggle, R=Reset counter
]]


---------------- CONFIG ----------------
local HERB_FOLDER_CANDIDATES = {"Herbs","Spawns","Drops"} -- ถ้าเกมไม่มี โค้ดจะสแกนทั้ง workspace
local UUID_KEYS              = {"UUID","uuid","Guid","GUID","Id","ID"} -- ชื่อคีย์ยอดฮิต
local NAME_HINTS             = {"herb","flower","lotus","blossom","plant"} -- แค่ช่วยคัดกรองเบื้องต้น

local COLLECT_RANGE   = 18    -- ระยะที่ถือว่าใกล้พอ
local MOVE_TIMEOUT    = 6
local SCAN_INTERVAL   = 0.25
local SEND_COOLDOWN   = 0.25
local SUCCESS_WAIT    = 1.2   -- เวลารอดูว่า item หาย (บางเกมไม่ลบ ก็จะถือว่าสำเร็จด้วย cooldown flag)

-- ตัดคลาสที่ไม่ใช่เป้าหมาย
local CLASS_BLACKLIST = { "SpawnLocation", "Camera", "Terrain", "Tool", "Accessory", "Hat" }


---------------- Services ----------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- Remote ตามสปาย
local CollectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Collect")


---------------- State ----------------
local AUTO_ON = false
local lastSend = 0
local collected = 0
local usedUUID = {}

local currentName, currentDist, currentUUID = "-", "-", "-"


---------------- Helpers ----------------
local function isBlacklisted(inst)
    for _, c in ipairs(CLASS_BLACKLIST) do
        if inst:IsA(c) then return true end
    end
    return false
end

local function getRoot(c)
    c = c or player.Character
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

local function distanceTo(pos)
    local root = getRoot()
    if not root then return math.huge end
    return (root.Position - pos).Magnitude
end

local function safeGetAttributes(inst)
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if ok and typeof(attrs)=="table" then return attrs end
    return {}
end

local function getPrimaryPart(inst)
    if not inst:IsA("Model") then return nil end
    local ok, pp = pcall(function() return inst.PrimaryPart end)
    if ok then return pp end
    return nil
end

local function hasUUIDStringValue(inst)
    for _, ch in ipairs(inst:GetChildren()) do
        if ch:IsA("StringValue") then
            for _, k in ipairs(UUID_KEYS) do
                if ch.Name == k and typeof(ch.Value)=="string" and #ch.Value>10 then
                    return ch.Value, k
                end
            end
            if typeof(ch.Value)=="string" and #ch.Value>30 and ch.Value:find("%-") then
                return ch.Value, ch.Name
            end
        end
    end
end

local function getUUID(inst)
    if isBlacklisted(inst) then return nil,nil end
    if not (inst:IsA("Model") or inst:IsA("BasePart")) then return nil,nil end

    -- 1) Attributes บนตัว inst
    local attrs = safeGetAttributes(inst)
    for _, k in ipairs(UUID_KEYS) do
        local v = attrs[k]
        if typeof(v)=="string" and #v>10 then return v,k end
    end
    for k,v in pairs(attrs) do
        if typeof(v)=="string" and #v>30 and v:find("%-") then
            return v,k
        end
    end

    -- 2) StringValue ลูก
    local sv, key = hasUUIDStringValue(inst)
    if sv then return sv, key end

    -- 3) PrimaryPart.Attributes (เฉพาะ Model)
    local pp = getPrimaryPart(inst)
    if pp then
        local ppAttrs = safeGetAttributes(pp)
        for _, k2 in ipairs(UUID_KEYS) do
            local v = ppAttrs[k2]
            if typeof(v)=="string" and #v>10 then return v,k2 end
        end
        for k2,v2 in pairs(ppAttrs) do
            if typeof(v2)=="string" and #v2>30 and v2:find("%-") then
                return v2,k2
            end
        end
    end

    return nil,nil
end

local function getCF(inst)
    if inst:IsA("Model") and inst.GetPivot then
        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and typeof(cf)=="CFrame" then return cf end
    elseif inst:IsA("BasePart") then
        return inst.CFrame
    end
    return nil
end

local function nameHint(inst)
    local n = (inst.Name or ""):lower()
    for _, w in ipairs(NAME_HINTS) do
        if n:find(w) then return true end
    end
    return false
end

-- โฟลเดอร์หลัก (ถ้ามี)
local HerbsFolder = workspace
for _, cand in ipairs(HERB_FOLDER_CANDIDATES) do
    local f = workspace:FindFirstChild(cand)
    if f then HerbsFolder = f break end
end

local function findCandidates()
    local out, scopes = {}, {}
    if HerbsFolder ~= workspace then table.insert(scopes, HerbsFolder) end
    table.insert(scopes, workspace)
    for _, scope in ipairs(scopes) do
        for _, d in ipairs(scope:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and not isBlacklisted(d) then
                if getUUID(d) or nameHint(d) then
                    table.insert(out, d)
                end
            end
        end
    end
    return out
end

local function collectable(inst)
    local uuid, key = getUUID(inst)
    if not uuid or usedUUID[uuid] then return nil end
    local cf = getCF(inst)
    if not cf then return nil end
    return uuid, key, cf.Position
end

local function nearestHerb()
    local best, bestD, bestUUID, bestPos, bestKey
    for _, inst in ipairs(findCandidates()) do
        local uuid, key, pos = collectable(inst)
        if uuid and pos then
            local d = distanceTo(pos)
            if not best or d < bestD then
                best, bestD, bestUUID, bestPos, bestKey = inst, d, uuid, pos, key
            end
        end
    end
    return best, bestUUID, bestKey, bestPos, bestD
end

-- ProximityPrompt helper (บางเกมวาง prompt ไว้กับต้นไม้)
local function activatePrompt(prompt)
    if typeof(prompt)=="Instance" and prompt:IsA("ProximityPrompt") then
        prompt:InputHoldBegin()
        task.delay((prompt.HoldDuration or 0)+0.05, function()
            prompt:InputHoldEnd()
        end)
        return true
    end
    return false
end

local function tryPrompt(inst)
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            return activatePrompt(d)
        end
    end
    if inst:IsA("BasePart") then
        local p = inst:FindFirstChildOfClass("ProximityPrompt")
        if p then return activatePrompt(p) end
    end
    return false
end

-- wrap เป็น "{UUID}" ตามสปาย
local function wrapBraces(u)
    if not u then return nil end
    if not u:match("^%b{}$") then return "{"..u.."}" end
    return u
end

local function sendCollect(uuid)
    local now = time()
    if now - lastSend < SEND_COOLDOWN then return false end
    lastSend = now
    local arg = wrapBraces(uuid)
    if not arg then return false end
    local ok = pcall(function() CollectRemote:FireServer(arg) end)
    return ok
end

local function waitSuccess(inst, uuid)
    -- 1) รอ despawn
    local t0 = time()
    while time() - t0 < SUCCESS_WAIT do
        if not inst.Parent then return true end
        RunService.Heartbeat:Wait()
    end
    -- 2) บางเกมไม่ลบโมเดล: mark ว่าเก็บแล้ว กันยิงซ้ำช่วงหนึ่ง
    usedUUID[uuid] = true
    return true
end

local function safeMoveTo(pos, timeout)
    local root = getRoot()
    if not root or not humanoid or humanoid.Health <= 0 then return false end
    humanoid:MoveTo(pos)
    local start, reached = time(), false
    local conn = humanoid.MoveToFinished:Connect(function(ok) reached = ok end)
    while time() - start < (timeout or MOVE_TIMEOUT) do
        RunService.Heartbeat:Wait()
        if reached then break end
        if (root.Position - pos).Magnitude <= COLLECT_RANGE then
            reached = true
            break
        end
    end
    if conn then conn:Disconnect() end
    return reached
end


---------------- UI ----------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoHerbUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(320, 190)
frame.Position = UDim2.fromOffset(60, 120)
frame.BackgroundColor3 = Color3.fromRGB(22,22,26)
frame.BorderSizePixel = 0
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,14)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(70,70,80); stroke.Thickness = 1
local pad = Instance.new("UIPadding", frame)
pad.PaddingLeft = UDim.new(0,12); pad.PaddingRight = UDim.new(0,12); pad.PaddingTop = UDim.new(0,10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-24,0,22)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235,235,240)
title.Text = "🌿 Auto Herb (Collect \"{UUID}\")"
title.Parent = frame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.fromOffset(80,28)
toggleBtn.Position = UDim2.new(1,-92,0,4)
toggleBtn.BackgroundColor3 = Color3.fromRGB(120,40,40)
toggleBtn.TextColor3 = Color3.new(1,1,1)
toggleBtn.Font = Enum.Font.GothamSemibold
toggleBtn.TextSize = 14
toggleBtn.Text = "OFF"
toggleBtn.Parent = frame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,10)

local line = Instance.new("Frame", frame)
line.Size = UDim2.new(1,-8,0,1)
line.Position = UDim2.fromOffset(4,36)
line.BackgroundColor3 = Color3.fromRGB(60,60,70)
line.BorderSizePixel = 0

local list = Instance.new("Frame", frame)
list.Size = UDim2.new(1,-4,1,-44)
list.Position = UDim2.fromOffset(2,40)
list.BackgroundTransparency = 1

local function mk(y, t)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,-4,0,22)
    l.Position = UDim2.fromOffset(2,y)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = Color3.fromRGB(210,210,220)
    l.Text = t
    l.Parent = list
    return l
end

local statusLbl = mk(0,  "สถานะ: OFF (H=Toggle, R=Reset)")
local remoteLbl = mk(24, "Remote: ReplicatedStorage/Remotes/Collect")
local targetLbl = mk(48, "เป้าหมาย: -")
local distLbl   = mk(72, "ระยะ: -")
local countLbl  = mk(96, "เก็บแล้ว: 0")

-- ลากได้
local dragging, dragStart, startPos = false, nil, nil
frame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = i.Position; startPos = frame.Position
    end
end)
frame.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging=false end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local function shortUUID(u) if not u or #u<8 then return tostring(u or "-") end return u:sub(1,8).."... end" end

local function updateUI()
    statusLbl.Text = ("สถานะ: %s (H=Toggle, R=Reset)"):format(AUTO_ON and "ON" or "OFF")
    targetLbl.Text = ("เป้าหมาย: %s (%s)"):format(currentName or "-", shortUUID(currentUUID or "-"))
    distLbl.Text   = ("ระยะ: %s"):format(currentDist or "-")
    countLbl.Text  = ("เก็บแล้ว: %d"):format(collected)
    toggleBtn.Text = AUTO_ON and "ON" or "OFF"
    toggleBtn.BackgroundColor3 = AUTO_ON and Color3.fromRGB(40,160,80) or Color3.fromRGB(120,40,40)
end
updateUI()

toggleBtn.MouseButton1Click:Connect(function()
    AUTO_ON = not AUTO_ON
    updateUI()
end)
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.H then
        AUTO_ON = not AUTO_ON
        updateUI()
    elseif input.KeyCode == Enum.KeyCode.R then
        collected = 0
        usedUUID = {}
        updateUI()
    end
end)


---------------- Main Loop ----------------
task.defer(function()
    while true do
        if AUTO_ON then
            if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
                character = player.Character or player.CharacterAdded:Wait()
                humanoid = character:WaitForChild("Humanoid")
            end

            local inst, uuid, _key, pos, dist = nearestHerb()
            if inst and uuid and pos then
                currentName, currentUUID = inst.Name, uuid
                currentDist = string.format("%.1f", dist)
                updateUI()

                if dist > COLLECT_RANGE then
                    safeMoveTo(pos, MOVE_TIMEOUT)
                    local root = getRoot()
                    if root then
                        currentDist = string.format("%.1f", (root.Position - pos).Magnitude)
                        updateUI()
                    end
                end

                -- ลองกด ProximityPrompt ก่อน (ถ้ามี)
                if tryPrompt(inst) then
                    if waitSuccess(inst, uuid) then
                        collected += 1
                        updateUI()
                        task.wait(0.2)
                    end
                else
                    -- ยิง Collect("{UUID}")
                    if sendCollect(uuid) then
                        if waitSuccess(inst, uuid) then
                            collected += 1
                            updateUI()
                            task.wait(0.2)
                        end
                    else
                        task.wait(SCAN_INTERVAL)
                    end
                end
            else
                currentName, currentUUID, currentDist = "-", "-", "-"
                updateUI()
                task.wait(SCAN_INTERVAL)
            end
        else
            task.wait(0.25)
        end
    end
end)

print("[AUTO HERB] Ready — Collect Remote with \"{UUID}\" | H=Toggle, R=Reset")
