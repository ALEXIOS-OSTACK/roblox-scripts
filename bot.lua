---------------- UI (Fluent-first / Fallback Lite) ----------------
local UI = {}
do
    -- ลองโหลด Fluent จาก repo ที่ให้มา (ถ้าเปลี่ยน path ได้ ให้แก้ URL ตรงนี้)
    local useFluent, Fluent, Window, Tabs = false, nil, nil, nil
    local loaded, err = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/ApelsinkaFr/Fluent/main/Fluent.lua"))()
    end)

    if loaded then
        Fluent = err  -- err ใน pcall ด้านบนคือค่าที่ return
        if type(Fluent) == "table" and (Fluent.CreateWindow or Fluent.create_window or Fluent.New) then
            useFluent = true
        end
    end

    if useFluent then
        -- สร้างหน้าต่างหลัก
        local create = Fluent.CreateWindow or Fluent.create_window or Fluent.New
        Window = create(Fluent, {
            Title = "🌿 Cultivate Bot",
            SubTitle = "Adaptive Flow • Auto-Rebind UI",
            Size = UDim2.fromOffset(600, 420),
            MinimizeKey = Enum.KeyCode.RightShift, -- ย่อ/โชว์ด้วย RightShift
            TabWidth = 160,
            Acrylic = true,   -- เบลอหรู ๆ ถ้า GPU ไหว
            Theme = "Darker",
        })

        -- 탭หลัก/ตั้งค่า
        Tabs = {
            Main = Window:AddTab({ Title = "Main",     Icon = "home" }),
            Stats = Window:AddTab({ Title = "Stats",    Icon = "bar-chart-2" }),
            Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
        }

        -- Toggle คุม Start/Stop
        local AutoToggle = Tabs.Main:AddToggle("AutoRun", {
            Title = "Enable Cultivate Bot  (F8)",
            Default = false,
        })

        -- ปุ่ม Breakthrough ทันที (เผื่ออยากกดเอง)
        Tabs.Main:AddButton({
            Title = "Force Breakthrough",
            Description = "Stops, sends Breakthrough, then continues meditation",
            Callback = function()
                task.spawn(function()
                    doBreakthroughCycle()
                end)
            end
        })

        -- Labels/Paragraphs สำหรับสถานะ
        local statusP   = Tabs.Main:AddParagraph({ Title = "Status",   Content = "🟡 Waiting..." })
        local progP     = Tabs.Stats:AddParagraph({ Title = "Progress", Content = "—" })
        local qiP       = Tabs.Stats:AddParagraph({ Title = "Qi",       Content = "—" })
        local flowP     = Tabs.Stats:AddParagraph({ Title = "Flow",     Content = "—" })
        local breaksLbl = Tabs.Stats:AddParagraph({ Title = "Breaks",   Content = "0" })

        -- notification helper
        local function notify(t)
            -- Fluent บางเวอร์ชันใช้ Fluent:Notify
            local ok = pcall(function()
                Fluent:Notify({
                    Title = t.Title or "Cultivate Bot",
                    Content = t.Text or t.Content or "",
                    Duration = t.Duration or 2
                })
            end)
            if not ok then
                -- เงียบไว้ถ้าเวอร์ชันนี้ไม่มี Notify
            end
        end

        -- toggle handlers
        AutoToggle:OnChanged(function(v)
            running = v
            startOrRecoverAt = os.clock()
            lastAliveAt      = os.clock()
            strikes = 0
            sameQiTicks, sameProgTicks = 0, 0
            notify({Content = v and "Started" or "Stopped"})
        end)

        -- ปุ่มสลับกับคีย์ลัด (ให้เหมือนเดิม)
        function UI.toggleRun()
            local ok = pcall(function() AutoToggle:SetValue(not AutoToggle.Value) end)
            if not ok then
                running = not running
                startOrRecoverAt = os.clock()
                lastAliveAt      = os.clock()
                strikes = 0
                sameQiTicks, sameProgTicks = 0, 0
                notify({Content = running and "Started" or "Stopped"})
            end
        end

        -- อัปเดต HUD จากลูปหลัก
        function UI.updateHUD(pctText, qiText, dynTimeout)
            -- สถานะ
            local s
            if isBreakingNow then s = "🟠 Breaking..."
            elseif isMeditating then s = "🟢 Meditating..."
            elseif running then s = "🟡 Running..."
            else s = "🔴 Stopped" end

            pcall(function() statusP:SetDesc(s) end)

            pcall(function() progP:SetDesc(tostring(pctText or "—")) end)
            pcall(function() qiP:SetDesc(tostring(qiText or "—")) end)

            local sinceAlive = math.min(os.clock() - lastAliveAt, 9999)
            local flowText = string.format("Flow: %.1fs ago  (timeout ~ %.1fs)", sinceAlive, dynTimeout or 0)
            pcall(function() flowP:SetDesc(flowText) end)

            pcall(function() breaksLbl:SetDesc(tostring(breakCount or 0)) end)
        end

        -- คีย์ลัด (เหมือนเดิม)
        UIS.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.KeyCode == Enum.KeyCode.F8 then UI.toggleRun() end
            -- การย่อ/โชว์ ใช้ RightShift ผ่าน MinimizeKey แล้ว
        end)

        -- init
        UI.updateHUD("—", "—", FLOOR_TIMEOUT)

    else
        -- ---------------- Fallback: Lite UI เดิม ----------------
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
        UI.updateHUD("—", "—", FLOOR_TIMEOUT)
    end
end
