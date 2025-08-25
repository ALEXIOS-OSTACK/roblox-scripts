-- Cultivate Bot (Adaptive Flow • Auto-Rebind UI • Robust • Lite UI)

---------------- Services ----------------
local RS         = game:GetService("ReplicatedStorage")
local Players    = game:GetService("Players")
local UIS        = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pg     = player:WaitForChild("PlayerGui")

---------------- Remote ------------------
local CultivationEvent = RS:WaitForChild("RemoteEvents"):WaitForChild("CultivationEvent")

---------------- Base Config (คงที่) ------------------
local CHECK_INTERVAL       = 0.5      -- ความถี่ loop
local STAND_UP_DELAY       = 0.6
local BREAK_DURATION       = 2.0
local BREAK_DEBOUNCE       = 3.0
local RECOVERY_COOLDOWN    = 6.0
local START_GRACE_TIME     = 8.0
local FAILSAFE_SECONDS     = 180
local STABLE_TICKS         = 8        -- ทั้ง Qi และ Progress ต้องนิ่งอย่างน้อยเท่านี้ทิก

-- Adaptive window
local WINDOW_SIZE          = 20       -- เก็บช่วงเวลาเปลี่ยนล่าสุดกี่ครั้ง
local FLOOR_TIMEOUT        = 12.0     -- ขั้นต่ำสุดของ no-flow time
local MULT_MEAN            = 2.5      -- ตัวคูณเฉลี่ย
local MULT_MEDIAN          = 3.0      -- ตัวคูณมัธยฐาน
local CEIL_TIMEOUT         = 120.0    -- เพดานกันหลุดโลก (เลือกเองได้)

---------------- State ------------------
local running        = false
local isMeditating   = false
local isBreakingNow  = false
local lastBreakTime  = 0
local lastAnyBreakAt = os.clock()
local breakCount     = 0

local lastRecoverTry     = 0
local startOrRecoverAt   = os.clock()

-- สถานะสัญญาณ “ยังมีชีวิต”
local qiLabel, progressLabel = nil, nil
local lastQiText       = ""
local lastProgText     = ""
local sameQiTicks      = 0
local sameProgTicks    = 0
local lastAliveAt      = os.clock()
local strikes          = 0

-- สำหรับ adaptive timeout
local qiLastChangeAt   = nil
local progLastChangeAt = nil
local qiIntervals      = {}  -- queue
local progIntervals    = {}  -- queue

---------------- Utils ------------------

local function pushInterval(arr, dt)
    table.insert(arr, dt)
    if #arr > WINDOW_SIZE then table.remove(arr, 1) end
end

local function mean(arr)
    local s=0; for _,v in ipairs(arr) do s+=v end
    return (#arr>0) and (s/#arr) or 0
end

local function median(arr)
    local n = #arr
    if n==0 then return 0 end
    local tmp = table.clone(arr)
    table.sort(tmp)
    if n%2==1 then return tmp[(n+1)//2] else return 0.5*(tmp[n//2]+tmp[n//2+1]) end
end

local function adaptiveTimeout()
    local m1 = mean(qiIntervals)
    local d1 = median(qiIntervals)
    local m2 = mean(progIntervals)
    local d2 = median(progIntervals)

    -- รวมสองสัญญาณ: ใช้ค่ามากสุดของแต่ละฝั่งหลังคูณ
    local cand = math.max(m1*MULT_MEAN, d1*MULT_MEDIAN, m2*MULT_MEAN, d2*MULT_MEDIAN, FLOOR_TIMEOUT)
    return math.clamp(cand, FLOOR_TIMEOUT, CEIL_TIMEOUT)
end

local function safeText(o)
    return (o and o.Text) or ""
end

-- ค้นหา TextLabel โดยชื่อ/ข้อความที่สื่อความ (เผื่อ path เปลี่ยน)
local function findLabelByKeywords(root, nameKeys, textKeys)
    local queue = {root}
    while #queue>0 do
        local node = table.remove(queue, 1)
        if node:IsA("TextLabel") then
            local n = string.lower(node.Name)
            local t = string.lower(node.Text or "")
            local ok = false
            for _,k in ipairs(nameKeys) do if n:find(k,1,true) then ok=true break end end
            if not ok then
                for _,k in ipairs(textKeys) do if t:find(k,1,true) then ok=true break end end
            end
            if ok then return node end
        end
        for _,ch in ipairs(node:GetChildren()) do table.insert(queue, ch) end
    end
    return nil
end

local function rebindLabels()
    -- พยายาม path ตรงก่อน (ของเดิม)
    local ok, screen = pcall(function() return pg:WaitForChild("ScreenGui", 1) end)
    if not ok or not screen then
        -- fallback: ใช้ทั้ง pg
        screen = pg
    end
    -- Progress
    local prog = nil
    -- try exact path
    pcall(function()
        prog = pg.ScreenGui.Sidebar.Stats.StatsFrame.LowerStats.Percentage
    end)
    if not (prog and prog:IsA("TextLabel")) then
        prog = findLabelByKeywords(screen, {"percentage","progress"}, {"progress", "%"})
    end

    -- Qi
    local qi = nil
    pcall(function()
        qi = pg.ScreenGui.Sidebar.Stats.StatsFrame.UpperStats.Qi
    end)
    if not (qi and qi:IsA("TextLabel")) then
        qi = findLabelByKeywords(screen, {"qi"}, {"qi"})
    end

    progressLabel, qiLabel = prog, qi

    if progressLabel then lastProgText = safeText(progressLabel) end
    if qiLabel then lastQiText = safeText(qiLabel):gsub("%s","") end

    -- bind change signals
    if progressLabel then
        progressLabel:GetPropertyChangedSignal("Text"):Connect(function()
            local nowT = safeText(progressLabel)
            if nowT ~= lastProgText then
                local now = os.clock()
                if progLastChangeAt then pushInterval(progIntervals, now - progLastChangeAt) end
                progLastChangeAt = now
                lastProgText = nowT
                lastAliveAt  = now
                sameProgTicks = 0
            end
        end)
    end
    if qiLabel then
        qiLabel:GetPropertyChangedSignal("Text"):Connect(function()
            local raw = safeText(qiLabel)
            local nowT = (raw:match("Qi%s*:%s*(.+)$") or raw):gsub("%s+",""):gsub(",","")
            if nowT ~= lastQiText then
                local now = os.clock()
                if qiLastChangeAt then pushInterval(qiIntervals, now - qiLastChangeAt) end
                qiLastChangeAt = now
                lastQiText  = nowT
                lastAliveAt = now
                sameQiTicks = 0
            end
        end)
    end
end

---------------- Actions ------------------
local function fire(action) pcall(function() CultivationEvent:FireServer(action) end) end

local function startMeditate()
    if not isMeditating and not isBreakingNow then
        fire("Cultivate"); isMeditating = true
        startOrRecoverAt = os.clock()
    end
end

local function stopMeditate()
    if isMeditating then
        fire("Cultivate"); isMeditating = false
    end
end

local function doBreakthroughCycle()
    if isBreakingNow then return end
    if os.clock() - lastBreakTime <= BREAK_DEBOUNCE then return end
    isBreakingNow = true
    stopMeditate()
    task.wait(STAND_UP_DELAY)
    fire("Breakthrough")
    lastBreakTime  = os.clock()
    lastAnyBreakAt = os.clock()
    task.wait(BREAK_DURATION)
    startMeditate()
    isBreakingNow = false
    breakCount += 1
end

---------------- UI (Lite / Draggable / Toggle) ----------------
local UI = {}
do
    local gui = Instance.new("ScreenGui")
    gui.Name = "CultivateBotLite"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 1000
    gui.Parent = pg

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(480, 250)
    main.Position = UDim2.new(0.5, -240, 0.18, 0)
    main.BackgroundColor3 = Color3.fromRGB(250,245,235)
    main.BorderSizePixel = 0
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", main) stroke.Color = Color3.fromRGB(200,180,150) stroke.Thickness = 2

    local title = Instance.new("TextLabel", main)
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -40, 0, 40)
    title.Position = UDim2.fromOffset(16, 10)
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 22
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(80,50,20)
    title.Text = "🌿 Cultivate Bot (Adaptive)"

    local closeBtn = Instance.new("TextButton", main)
    closeBtn.Size = UDim2.fromOffset(30, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(220,80,80)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 18
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

    local btn = Instance.new("TextButton", main)
    btn.Size = UDim2.fromOffset(150, 48)
    btn.Position = UDim2.new(1, -170, 0, 56)
    btn.BackgroundColor3 = Color3.fromRGB(240,120,100)
    btn.Text = "Start"
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 20
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    local status = Instance.new("TextLabel", main)
    status.BackgroundTransparency = 1
    status.Size = UDim2.new(1, -32, 0, 26)
    status.Position = UDim2.fromOffset(20, 108)
    status.Font = Enum.Font.Gotham
    status.TextSize = 18
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextColor3 = Color3.fromRGB(60,60,60)
    status.Text = "🟡 Status: Waiting..."

    local pText = Instance.new("TextLabel", main)
    pText.BackgroundTransparency = 1
    pText.Size = UDim2.new(1, -32, 0, 22)
    pText.Position = UDim2.fromOffset(20, 136)
    pText.Font = Enum.Font.Gotham
    pText.TextSize = 16
    pText.TextXAlignment = Enum.TextXAlignment.Left
    pText.TextColor3 = Color3.fromRGB(60,60,60)
    pText.Text = "Progress: —"

    local qiLine = Instance.new("TextLabel", main)
    qiLine.BackgroundTransparency = 1
    qiLine.Size = UDim2.new(1, -32, 0, 22)
    qiLine.Position = UDim2.fromOffset(20, 160)
    qiLine.Font = Enum.Font.Gotham
    qiLine.TextSize = 16
    qiLine.TextXAlignment = Enum.TextXAlignment.Left
    qiLine.TextColor3 = Color3.fromRGB(60,60,60)
    qiLine.Text = "Qi: —"

    local flowLbl = Instance.new("TextLabel", main)
    flowLbl.BackgroundTransparency = 1
    flowLbl.Size = UDim2.new(1, -32, 0, 22)
    flowLbl.Position = UDim2.fromOffset(20, 184)
    flowLbl.Font = Enum.Font.Gotham
    flowLbl.TextSize = 16
    flowLbl.TextXAlignment = Enum.TextXAlignment.Left
    flowLbl.TextColor3 = Color3.fromRGB(60,60,60)
    flowLbl.Text = "Flow: — (timeout ~ — s)"

    local breaksLbl = Instance.new("TextLabel", main)
    breaksLbl.BackgroundTransparency = 1
    breaksLbl.Size = UDim2.new(1, -32, 0, 22)
    breaksLbl.Position = UDim2.fromOffset(20, 208)
    breaksLbl.Font = Enum.Font.Gotham
    breaksLbl.TextSize = 16
    breaksLbl.TextXAlignment = Enum.TextXAlignment.Left
    breaksLbl.TextColor3 = Color3.fromRGB(60,60,60)
    breaksLbl.Text = "⚡ Breaks: 0"

    -- Dragging
    local dragging, dragStart, startPos
    main.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = i.Position; startPos = main.Position
        end
    end)
    main.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement and dragging then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                      startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    local function setBtn()
        if running then btn.Text="Stop"; btn.BackgroundColor3=Color3.fromRGB(100,180,120)
        else btn.Text="Start"; btn.BackgroundColor3=Color3.fromRGB(240,120,100) end
    end

    function UI.updateHUD(pctText, qiText, dynTimeout)
        -- สถานะ
        if isBreakingNow then status.Text = "🟠 Status: Breaking..."
        elseif isMeditating then status.Text = "🟢 Status: Meditating..."
        elseif running then status.Text = "🟡 Status: Running..."
        else status.Text = "🔴 Status: Stopped" end

        pText.Text   = "Progress: " .. (pctText or "—")
        qiLine.Text  = "Qi: " .. (qiText or "—")

        local sinceAlive = math.min(os.clock() - lastAliveAt, 9999)
        flowLbl.Text = string.format("Flow: %.1fs ago  (timeout ~ %.1fs)", sinceAlive, dynTimeout or 0)

        breaksLbl.Text = ("⚡ Breaks: %d"):format(breakCount)
    end

    function UI.toggleRun()
        running = not running
        setBtn()
        StarterGui:SetCore("SendNotification", {Title="CultivateBot", Text=(running and "Started" or "Stopped"), Duration=2})
        startOrRecoverAt = os.clock()
        lastAliveAt      = os.clock()
        strikes          = 0
        sameQiTicks, sameProgTicks = 0, 0
    end

    btn.MouseButton1Click:Connect(UI.toggleRun)
    closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)
    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.F8 then UI.toggleRun() end
        if input.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
    end)

    setBtn()
end

---------------- Rebind & Respawn Safety ----------------
local function getProgressText()
    if not progressLabel then return "—" end
    local t = progressLabel.Text or ""
    -- เก็บตัวเลขหรือ % ถ้ามี
    local num = t:match("([%d%.]+%%%s*)") or t:match("([%d%.]+)") or t
    return num
end

local function getQiText()
    if not qiLabel then return "—" end
    local raw = qiLabel.Text or ""
    local body = raw:match("Qi%s*:%s*(.+)$") or raw
    body = body:gsub("%s+",""):gsub(",","")
    return (body ~= "" and body) or "—"
end

local function doRebindAll()
    rebindLabels()
end

-- rebind ตอนเริ่ม และเมื่อ PlayerGui เปลี่ยน
doRebindAll()
pg.ChildAdded:Connect(function() task.defer(doRebindAll) end)
player.CharacterAdded:Connect(function() task.delay(1.0, doRebindAll) end)

---------------- Main Loop ----------------
task.spawn(function()
    while true do
        if running then
            -- อ่านข้อความปัจจุบัน
            local progText = getProgressText()
            local qiTextNow = getQiText()

            -- นับนิ่ง/เปลี่ยน (กรณี signal บางเกมไม่ยิง)
            local curProgFull = safeText(progressLabel)
            if curProgFull ~= lastProgText then
                local now = os.clock()
                if progLastChangeAt then pushInterval(progIntervals, now - progLastChangeAt) end
                progLastChangeAt = now
                lastProgText = curProgFull
                lastAliveAt  = now
                sameProgTicks = 0
            else
                sameProgTicks += 1
            end

            local rawQi = safeText(qiLabel)
            local qiOnly = (rawQi:match("Qi%s*:%s*(.+)$") or rawQi):gsub("%s+",""):gsub(",","")
            if qiOnly ~= lastQiText then
                local now = os.clock()
                if qiLastChangeAt then pushInterval(qiIntervals, now - qiLastChangeAt) end
                qiLastChangeAt = now
                lastQiText  = qiOnly
                lastAliveAt = now
                sameQiTicks = 0
            else
                sameQiTicks += 1
            end

            -- คำนวณ timeout แบบ adaptive
            local dynTimeout = adaptiveTimeout()

            -- ตรวจ no-flow: ต้องผ่าน grace, ต้องนิ่งทั้งสองสัญญาณ และเกินเวลา adaptive
            local pastGrace  = (os.clock() - startOrRecoverAt) > START_GRACE_TIME
            local ticksQuiet = (sameQiTicks >= STABLE_TICKS) and (sameProgTicks >= STABLE_TICKS)
            local timeQuiet  = (os.clock() - lastAliveAt) > dynTimeout

            if pastGrace and ticksQuiet and timeQuiet and not isBreakingNow then
                strikes += 1
                if strikes >= 3 and (os.clock() - lastRecoverTry) > RECOVERY_COOLDOWN then
                    fire("Cultivate")                  -- recover: นั่งใหม่
                    isMeditating     = true
                    lastRecoverTry   = os.clock()
                    startOrRecoverAt = os.clock()
                    lastAliveAt      = os.clock()
                    sameQiTicks, sameProgTicks, strikes = 0, 0, 0
                end
            else
                if (os.clock() - lastAliveAt) <= dynTimeout then
                    strikes = 0
                end
            end

            -- Break ถ้า Progress เต็ม (ดูจากข้อความมี "100" หรือ "%")
            local pctNumber = tonumber((progText:gsub("%%","")))
            if pctNumber and pctNumber >= 100 then
                doBreakthroughCycle()
            else
                startMeditate()
            end

            -- Failsafe
            if os.clock() - lastAnyBreakAt > FAILSAFE_SECONDS then
                running = false; task.wait(0.3); running = true
                lastAnyBreakAt   = os.clock()
                startOrRecoverAt = os.clock()
                lastAliveAt      = os.clock()
                sameQiTicks, sameProgTicks, strikes = 0, 0, 0
            end

            UI.updateHUD(progText, qiTextNow, math.floor(dynTimeout*10+0.5)/10)
        end
        task.wait(CHECK_INTERVAL)
    end
end)

-- init HUD
UI.updateHUD("—", getQiText(), FLOOR_TIMEOUT)
