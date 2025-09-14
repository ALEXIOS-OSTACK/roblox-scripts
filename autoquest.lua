

-- ตั้งค่าตัวแปร
local farming = false
local npcList = {"FallenDisciple","SectElder"}
local skillID = 3
local fightTime = 15  -- เวลาสู้แต่ละ NPC (วินาที)
local waitTime = 5 -- เวลาพักหลังครบ 4 ตัว

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ฟังก์ชันต่อสู้
local function startBattle(npcName)
    local args = {npcName}
    Remotes:WaitForChild("StartBattle"):FireServer(unpack(args))
end

local function useSkill(id)
    local args = {id}
    Remotes:WaitForChild("Skill"):FireServer(unpack(args))
end

local function fightNPC(npcName, statusLabel)
    statusLabel.Text = "⚔ กำลังสู้: " .. npcName
    startBattle(npcName)
    for i = 1, fightTime do
        if not farming then break end
        useSkill(skillID)
        task.wait(1)
    end
    statusLabel.Text = "✅ ฆ่า " .. npcName
end

-- ==============================
-- 🌟 UI
-- ==============================
local ScreenGui = Instance.new("ScreenGui", game.Players.LocalPlayer:WaitForChild("PlayerGui"))
local Frame = Instance.new("Frame", ScreenGui)
Frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
Frame.Position = UDim2.new(0.7,0,0.3,0)
Frame.Size = UDim2.new(0,240,0,150)

-- มุมโค้ง + เส้นขอบ
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0,12)
local stroke = Instance.new("UIStroke", Frame)
stroke.Color = Color3.fromRGB(80,80,80)
stroke.Thickness = 2

-- Title
local Title = Instance.new("TextLabel", Frame)
Title.BackgroundTransparency = 1
Title.Size = UDim2.new(1,0,0,30)
Title.Text = "⚔ Auto Farm NPC"
Title.TextColor3 = Color3.fromRGB(255,255,255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18

-- สถานะ
local Status = Instance.new("TextLabel", Frame)
Status.BackgroundTransparency = 1
Status.Position = UDim2.new(0,0,0.25,0)
Status.Size = UDim2.new(1,0,0,25)
Status.Text = "⏸ รอเริ่ม..."
Status.TextColor3 = Color3.fromRGB(200,200,200)
Status.Font = Enum.Font.Gotham
Status.TextSize = 14

-- ปุ่ม Start
local StartButton = Instance.new("TextButton", Frame)
StartButton.Position = UDim2.new(0.1,0,0.55,0)
StartButton.Size = UDim2.new(0.35,0,0,40)
StartButton.Text = "▶ Start"
StartButton.BackgroundColor3 = Color3.fromRGB(0,170,80)
StartButton.TextColor3 = Color3.fromRGB(255,255,255)
StartButton.Font = Enum.Font.GothamBold
StartButton.TextSize = 16
Instance.new("UICorner", StartButton).CornerRadius = UDim.new(0,10)

-- ปุ่ม Stop
local StopButton = Instance.new("TextButton", Frame)
StopButton.Position = UDim2.new(0.55,0,0.55,0)
StopButton.Size = UDim2.new(0.35,0,0,40)
StopButton.Text = "⛔ Stop"
StopButton.BackgroundColor3 = Color3.fromRGB(170,50,50)
StopButton.TextColor3 = Color3.fromRGB(255,255,255)
StopButton.Font = Enum.Font.GothamBold
StopButton.TextSize = 16
Instance.new("UICorner", StopButton).CornerRadius = UDim.new(0,10)

-- ให้ Frame ลากได้
Frame.Active = true
Frame.Draggable = true

-- ==============================
-- 🔧 Logic ทำงานกับปุ่ม
-- ==============================

StartButton.MouseButton1Click:Connect(function()
    if not farming then
        farming = true
        Status.Text = "▶ Auto Farm เริ่มทำงาน"
        while farming do
            -- ไล่สู้ครบ 4 ตัว
            for _, npc in ipairs(npcList) do
                if farming then
                    fightNPC(npc, Status)
                else
                    break
                end
            end
            -- รอ cooldown รวม
            if farming then
                for t = waitTime,1,-1 do
                    Status.Text = "⏳ รอ "..t.." วิ"
                    task.wait(1)
                    if not farming then break end
                end
            end
        end
    end
end)

StopButton.MouseButton1Click:Connect(function()
    farming = false
    Status.Text = "⏸ หยุดแล้ว"
end)

