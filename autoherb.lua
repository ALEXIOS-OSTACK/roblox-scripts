--[[
Auto-Detect + Auto Collect Herbs (Roblox Lua)
- ค้นหา RemoteEvent ที่น่าจะเป็น "Collect" อัตโนมัติ
- ค้นหาตำแหน่ง UUID ในโมเดลสมุนไพร (Attributes / StringValue / PrimaryPart.Attribute)
- ทดลองรูปแบบ argument หลายแบบจนกว่าจะสำเร็จ แล้วจำ config ไว้
- UI โชว์สถานะ, remote/arg format ที่ตรวจพบ, เป้าหมาย/ระยะ/จำนวนเก็บ
- Hotkey: H = เปิด/ปิด, R = รีเซ็ต/เรียนรู้ใหม่
]]

---------------- CONFIG (ปรับเพิ่มคำหลักได้) ----------------
local HERB_FOLDER_CANDIDATES = {"Herbs", "Spawns", "Drops"}   -- ชื่อโฟลเดอร์ที่มักเก็บสมุนไพร
local HERB_NAME_KEYWORDS = {"herb","flower","lotus","blossom","plant"} -- คำบ่งชี้ชื่อโมเดล
local UUID_KEY_CANDIDATES = {"UUID","uuid","Guid","GUID","Id","ID"}   -- ชื่อคีย์ UUID ที่พบได้บ่อย
local REMOTE_NAME_CANDIDATES = {"Collect","Pickup","Gather","Harvest","CollectItem"}
local COLLECT_RANGE = 12
local MOVE_TIMEOUT = 6
local SCAN_INTERVAL = 0.25
local SEND_COOLDOWN = 0.35
local SUCCESS_DESPAWN_TIMEOUT = 1.25 -- วินาทีรอดูว่าไอเท็มหายหลังยิง

---------------- Services ----------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

---------------- State ----------------
local AUTO_ON = false
local learningMode = true         -- ครั้งแรกให้ลองหา/ทดสอบก่อน
local lastSend = 0
local collectedCount = 0
local usedUUID = {}               -- กันยิงซ้ำ
local currentTargetName, currentTargetDist, currentTargetUUID = "-", "-", "-"

local detected = {
    remote = nil,                 -- RemoteEvent ที่หาเจอ
    remotePath = "",              -- เส้นทางไว้โชว์ใน UI
    argMode = nil,                -- รูปแบบ argument ที่ผ่าน (1..N)
    uuidKey = nil,                -- ชื่อคีย์ UUID (เผื่อบางเกมใช้ table แบบ keyed)
}

---------------- Utils ----------------
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

local function pathOf(inst)
    local t = {}
    while inst and inst ~= game do
        table.insert(t, 1, inst.Name)
        inst = inst.Parent
    end
    return table.concat(t, "/")
end

---------------- Find Remote ----------------
local function tryFindRemote()
    -- 1) มาตรฐาน: ReplicatedStorage.Remotes.<ชื่อคาดเดา>
    local RemotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if RemotesFolder then
        for _, name in ipairs(REMOTE_NAME_CANDIDATES) do
            local r = RemotesFolder:FindFirstChild(name)
            if r and r:IsA("RemoteEvent") then
                return r, pathOf(r)
            end
        end
        -- เผื่อชื่ออื่น ๆ
        for _, obj in ipairs(RemotesFolder:GetDescendants()) do
            if obj:IsA("RemoteEvent") then
                local n = obj.Name:lower()
                for _, kw in ipairs({"collect","pickup","gather","harvest"}) do
                    if n:find(kw) then
                        return obj, pathOf(obj)
                    end
                end
            end
        end
    end
    -- 2) เผื่ออยู่นอกโฟลเดอร์ Remotes
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local n = obj.Name:lower()
            for _, kw in ipairs({"collect","pickup","gather","harvest"}) do
                if n:find(kw) then
                    return obj, pathOf(obj)
                end
            end
        end
    end
    return nil, ""
end

---------------- Herb scan + UUID ----------------
local HerbsFolder = workspace
for _, cand in ipairs(HERB_FOLDER_CANDIDATES) do
    local f = workspace:FindFirstChild(cand)
    if f then HerbsFolder = f break end
end

local function hasUUIDStringValue(inst)
    for _, child in ipairs(inst:GetChildren()) do
        if child:IsA("StringValue") then
            for _, key in ipairs(UUID_KEY_CANDIDATES) do
                if child.Name == key and #child.Value > 10 then
                    return child.Value, key
                end
            end
            -- เผื่อชื่ออะไรก็ได้แต่เป็น UUID ยาว ๆ
            if #child.Name <= 6 and #child.Value > 30 and child.Value:find("%-") then
                return child.Value, child.Name
            end
        end
    end
end

local function getUUIDFromInstance(inst)
    -- 1) Attributes
    if inst.GetAttributes then
        local attrs = inst:GetAttributes()
        for _, key in ipairs(UUID_KEY_CANDIDATES) do
            if attrs[key] and typeof(attrs[key])=="string" and #attrs[key] > 10 then
                return attrs[key], key
            end
        end
        -- เดาว่ามี attribute ที่ยาวและเป็นรูป UUID
        for k,v in pairs(attrs) do
            if typeof(v)=="string" and #v > 30 and v:find("%-") then
                return v, k
            end
        end
    end
    -- 2) StringValue ลูก
    local sv, key = hasUUIDStringValue(inst)
    if sv then return sv, key end
    -- 3) PrimaryPart attribute
    if inst.PrimaryPart and inst.PrimaryPart.GetAttributes then
        local attrs = inst.PrimaryPart:GetAttributes()
        for _, key2 in ipairs(UUID_KEY_CANDIDATES) do
            if attrs[key2] and typeof(attrs[key2])=="string" and #attrs[key2] > 10 then
                return attrs[key2], key2
            end
        end
        for k,v in pairs(attrs) do
            if typeof(v)=="string" and #v > 30 and v:find("%-") then
                return v, k
            end
        end
    end
    return nil, nil
end

local function looksLikeHerb(inst)
    if inst:IsA("Model") or inst:IsA("BasePart") then
        -- ชื่อบ่งชี้
        local n = (inst.Name or ""):lower()
        for _, kw in ipairs(HERB_NAME_KEYWORDS) do
            if n:find(kw) then return true end
        end
        -- มี UUID ก็ถือว่าใช่
        local u = getUUIDFromInstance(inst)
        if u then return true end
    end
    return false
end

local function collectable(inst)
    local uuid, key = getUUIDFromInstance(inst)
    if not uuid or usedUUID[uuid] then return nil end
    local cf = (inst.GetPivot and inst:GetPivot()) or (inst:IsA("BasePart") and inst.CFrame)
    if not cf then return nil end
    return uuid, key, cf.Position
end

local function findHerbCandidates()
    local out = {}
    local scopes = {}
    if HerbsFolder ~= workspace then table.insert(scopes, HerbsFolder) end
    table.insert(scopes, workspace)

    for _, scope in ipairs(scopes) do
        for _, d in ipairs(scope:GetDescendants()) do
            if looksLikeHerb(d) then table.insert(out, d) end
        end
    end
    return out
end

local function nearestHerb()
    local best, bestD, bestUUID, bestKey, bestPos = nil, math.huge, nil, nil, nil
    for _, inst in ipairs(findHerbCandidates()) do
        local uuid, key, pos = collectable(inst)
        if uuid and pos then
            local d = distanceTo(pos)
            if d < bestD then
                best, bestD, bestUUID, bestKey, bestPos = inst, d, uuid, key, pos
            end
        end
    end
    return best, bestUUID, bestKey, bestPos, bestD
end

---------------- Try FireServer formats ----------------
-- ลำดับการลองส่ง (จะจำแบบที่สำเร็จ)
-- mode 1: FireServer(uuid)                 -- string ตรง ๆ
-- mode 2: FireServer({uuid})               -- table single
-- mode 3: FireServer({UUID=uuid})          -- keyed table (uuidKey จากที่ตรวจพบ)
-- mode 4: FireServer({id=uuid})            -- เผื่อ server ใช้ "id"
local function trySend(remote, uuid, uuidKey)
    local now = time()
    if (now - lastSend) < SEND_COOLDOWN then return false, "cooldown" end
    lastSend = now

    local ok, err
    if not detected.argMode or detected.argMode == 1 then
        ok = pcall(function() remote:FireServer(uuid) end)
        if ok then return true, 1 end
    end
    if not detected.argMode or detected.argMode == 2 then
        ok = pcall(function() remote:FireServer({uuid}) end)
        if ok then return true, 2 end
    end
    if not detected.argMode or detected.argMode == 3 then
        local key = detected.uuidKey or uuidKey or "UUID"
        ok = pcall(function() remote:FireServer({[key]=uuid}) end)
        if ok then
            return true, 3, key
        end
    end
    if not detected.argMode or detected.argMode == 4 then
        ok = pcall(function() remote:FireServer({id=uuid}) end)
        if ok then return true, 4 end
    end
    return false, "pcall_failed"
end

local function waitDespawn(inst)
    -- รอดูว่าหายไป (หรือ Parent กลายเป็น nil) ภายในเวลาหนึ่ง
    local t0 = time()
    while time() - t0 < SUCCESS_DESPAWN_TIMEOUT do
        if not inst.Parent then return true end
        RunService.Heartbeat:Wait()
    end
    return false
end

local function sendAndConfirm(inst, uuid, uuidKey)
    if not detected.remote then return false, "no_remote" end
    local ok, mode, maybeKey = trySend(detected.remote, uuid, uuidKey)
    if not ok then return false, mode end

    -- ถ้าหลังยิงแล้วไอเท็มหาย/ถูกทำลาย → ถือว่าสำเร็จ
    if waitDespawn(inst) then
        if not detected.argMode then
            detected.argMode = mode
            if mode == 3 and maybeKey then detected.uuidKey = maybeKey end
        end
        usedUUID[uuid] = true
        collectedCount += 1
        return true, "despawned"
    end

    -- ถ้าไม่หาย อาจเป็นเพราะอยู่ไกล/เงื่อนไขอื่น ลองถือว่าไม่สำเร็จ
    return false, "no_despawn"
end

---------------- Movement ----------------
local function safeMoveTo(targetPos, timeout)
    local root = getRoot()
    if not root or not humanoid or humanoid.Health <= 0 then return false end
    humanoid:MoveTo(targetPos)
    local start, reached = time(), false
    local conn = humanoid.MoveToFinished:Connect(function(ok) reached = ok end)
    while time() - start < (timeout or MOVE_TIMEOUT) do
        RunService.Heartbeat:Wait()
        if reached then break end
        if (root.Position - targetPos).Magnitude <= COLLECT_RANGE then
            reached = true
            break
        end
    end
    if conn then conn:Disconnect() end
    return reached
end

---------------- UI ----------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoHerbDetectUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(310, 190)
frame.Position = UDim2.fromOffset(60, 120)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
frame.BorderSizePixel = 0
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,14)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(70,70,80); stroke.Thickness = 1

local padding = Instance.new("UIPadding", frame)
padding.PaddingLeft = UDim.new(0,12)
padding.PaddingRight = UDim.new(0,12)
padding.PaddingTop = UDim.new(0,10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 22)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235,235,240)
title.Text = "🌿 Auto Herb (Detect)"
title.Parent = frame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.fromOffset(80,28)
toggleBtn.Position = UDim2.new(1, -92, 0, 4)
toggleBtn.BackgroundColor3 = Color3.fromRGB(120,40,40)
toggleBtn.TextColor3 = Color3.new(1,1,1)
toggleBtn.Font = Enum.Font.GothamSemibold
toggleBtn.TextSize = 14
toggleBtn.Text = "OFF"
toggleBtn.Parent = frame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,10)

local line = Instance.new("Frame", frame)
line.Size = UDim2.new(1, -8, 0, 1)
line.Position = UDim2.fromOffset(4, 36)
line.BackgroundColor3 = Color3.fromRGB(60,60,70)
line.BorderSizePixel = 0

local list = Instance.new("Frame", frame)
list.Size = UDim2.new(1, -4, 1, -44)
list.Position = UDim2.fromOffset(2, 40)
list.BackgroundTransparency = 1

local function mkRow(y, text)
    local r = Instance.new("TextLabel")
    r.Size = UDim2.new(1, -4, 0, 22)
    r.Position = UDim2.fromOffset(2, y)
    r.BackgroundTransparency = 1
    r.TextXAlignment = Enum.TextXAlignment.Left
    r.Font = Enum.Font.Gotham
    r.TextSize = 14
    r.TextColor3 = Color3.fromRGB(210,210,220)
    r.Text = text
    r.Parent = list
    return r
end

local statusLbl  = mkRow(0,  "สถานะ: OFF (H=Toggle, R=Reset)")
local remoteLbl  = mkRow(24, "Remote: -")
local argLbl     = mkRow(48, "Arg Mode: -")
local uuidLbl    = mkRow(72, "UUID Key: -")
local targetLbl  = mkRow(96, "เป้าหมาย: -")
local distLbl    = mkRow(120,"ระยะ: -")
local countLbl   = mkRow(144,"เก็บแล้ว: 0")

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
    statusLbl.Text = ("สถานะ: %s (H=Toggle, R=Reset)"):format(AUTO_ON and (learningMode and "LEARN+ON" or "ON") or "OFF")
    remoteLbl.Text = ("Remote: %s"):format(detected.remote and detected.remotePath or "-")
    argLbl.Text    = ("Arg Mode: %s"):format(detected.argMode and tostring(detected.argMode) or "-")
    uuidLbl.Text   = ("UUID Key: %s"):format(detected.uuidKey or "-")
    targetLbl.Text = ("เป้าหมาย: %s (%s)"):format(currentTargetName or "-", shortUUID(currentTargetUUID or "-"))
    distLbl.Text   = ("ระยะ: %s"):format(currentTargetDist or "-")
    countLbl.Text  = ("เก็บแล้ว: %d"):format(collectedCount)

    toggleBtn.Text = AUTO_ON and "ON" or "OFF"
    toggleBtn.BackgroundColor3 = AUTO_ON and Color3.fromRGB(40,160,80) or Color3.fromRGB(120,40,40)
end
updateUI()

local function resetLearning()
    learningMode = true
    detected.argMode = nil
    detected.uuidKey = nil
    usedUUID = {}
    updateUI()
    print("[AUTO HERB] reset learning")
end

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
        resetLearning()
    end
end)

---------------- Boot: หา Remote หนึ่งครั้ง ----------------
task.defer(function()
    local r, p = tryFindRemote()
    detected.remote, detected.remotePath = r, p
    updateUI()
end)

---------------- Main Loop ----------------
task.defer(function()
    while true do
        if AUTO_ON then
            if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
                character = player.Character or player.CharacterAdded:Wait()
                humanoid = character:WaitForChild("Humanoid")
            end

            -- ถ้ายังไม่มี remote ให้รอ
            if not detected.remote then
                task.wait(SCAN_INTERVAL)
            else
                local inst, uuid, uuidKey, pos, dist = nearestHerb()
                if inst and uuid and pos then
                    currentTargetName = inst.Name
                    currentTargetUUID = uuid
                    currentTargetDist = string.format("%.1f", dist)
                    updateUI()

                    if dist > COLLECT_RANGE then
                        safeMoveTo(pos, MOVE_TIMEOUT)
                        local root = getRoot()
                        if root then
                            currentTargetDist = string.format("%.1f", (root.Position - pos).Magnitude)
                            updateUI()
                        end
                    end

                    -- ยิง + ยืนยันความสำเร็จด้วยการ despawn
                    local ok, reason = sendAndConfirm(inst, uuid, uuidKey)
                    if ok then
                        learningMode = detected.argMode == nil  -- ถ้าเพิ่งค้นพบ argMode จะถูกตั้งค่าแล้ว
                        updateUI()
                        task.wait(0.2)
                    else
                        -- ถ้ายิงไม่สำเร็จในโหมดเรียนรู้ ให้ลองรูปแบบถัดไปในรอบหน้า (trySend จะจัดการเอง)
                        task.wait(SCAN_INTERVAL)
                    end
                else
                    currentTargetName, currentTargetUUID, currentTargetDist = "-", "-", "-"
                    updateUI()
                    task.wait(SCAN_INTERVAL)
                end
            end
        else
            task.wait(0.25)
        end
    end
end)

print("[AUTO HERB] H=Toggle, R=Reset — เริ่มโหมดเรียนรู้อัตโนมัติ")
