--== World-Class Immortal Collector ==--
-- UI Dashboard • ESP Filter • Telemetry • Adaptive Timeout • Watchdog++

--== Services ==--
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local HRP = Char:WaitForChild("HumanoidRootPart")

--== Config ==--
local ROOT_NAME = "Resources"
local HOME_POS = Vector3.new(-519,-5,-386)
local SCAN_RANGE = 6000
local STEP_STUDS = 90
local SPEED = 150
local SAFE_Y = 2
local HEIGHT_BOOST = 15
local STUCK_TIME = 1.5
local MAX_TARGET_TIME = 6

--== Runtime ==--
local AUTO_ENABLED = false
local ROOT = workspace:WaitForChild(ROOT_NAME)
local targets = {}
local telemetry = {}
local latency = 0.2
local ESP_FILTER = { [3]=true, [4]=true, [5]=true }

--== Helpers ==--
local function getHRP()
	if HRP and HRP.Parent then return HRP end
	if LP.Character then
		HRP = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:WaitForChild("HumanoidRootPart",5)
	end
	return HRP
end

local function zeroVel(h)
	if not h then return end
	h.AssemblyLinearVelocity = Vector3.zero
	h.AssemblyAngularVelocity = Vector3.zero
end

local function snapToFloor(pos)
	local ray = workspace:Raycast(pos + Vector3.new(0,50,0), Vector3.new(0,-300,0))
	if ray then return Vector3.new(pos.X, ray.Position.Y+1, pos.Z) end
	return pos
end

--== ESP ==--
local RARITY_NAME = { [3]="Legendary", [4]="Tier4", [5]="Tier5" }
local function makeESP(part, rarity)
	local bb = Instance.new("BillboardGui", part)
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0,180,0,40)
	bb.StudsOffset = Vector3.new(0,3,0)
	local lbl = Instance.new("TextLabel", bb)
	lbl.Size = UDim2.new(1,0,1,0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255,255,255)
	lbl.TextStrokeTransparency = 0.3
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.Text = string.format("[%s]",RARITY_NAME[rarity] or rarity)
	return lbl
end

local function attach(inst)
	local r = inst:GetAttribute("Rarity")
	if not r or not ESP_FILTER[r] then return end
	local part = inst:FindFirstChildWhichIsA("BasePart") or inst
	if not part or targets[part] then return end
	local lbl = makeESP(part,r)
	targets[part] = {obj=inst, rarity=r, lbl=lbl}
	inst.AncestryChanged:Connect(function(_,p) if not p then targets[part]=nil end end)
end

for _,d in ipairs(ROOT:GetDescendants()) do if d:GetAttribute("Rarity") then attach(d) end end
ROOT.DescendantAdded:Connect(function(d) if d:GetAttribute("Rarity") then attach(d) end end)

--== Tween TP ==--
local function tweenHop(toPos)
	local h=getHRP(); if not h then return end
	local dist=(h.Position-toPos).Magnitude
	local t=math.max(0.05, dist/SPEED)
	local tw=TweenService:Create(h,TweenInfo.new(t,Enum.EasingStyle.Linear),{CFrame=CFrame.new(toPos)})
	tw:Play()
	tw.Completed:Wait()
	zeroVel(h)
end

local function tpTo(pos)
	local h=getHRP(); if not h then return end
	pos = snapToFloor(pos)
	local dist=(h.Position-pos).Magnitude
	local steps=math.max(1,math.ceil(dist/STEP_STUDS))
	for i=1,steps do
		local p=h.Position:Lerp(pos,i/steps)
		if i==steps then p=snapToFloor(p) end
		tweenHop(p)
	end
end

--== Collect ==--
local function findUUID(inst)
	if not inst then return nil end
	local keys={"CollectId","HerbId","ResourceId","ObjectId","Id","GUID","UUID","Uid","uid"}
	for _,k in ipairs(keys) do
		local v=inst:GetAttribute(k)
		if v and #tostring(v)>0 then return tostring(v) end
	end
	return nil
end

local function collectFast(info, part)
	local uuid=findUUID(info.obj)
	if not uuid then return false end
	local ok=pcall(function() RS.Remotes.Collect:FireServer(uuid) end)
	if not ok then return false end
	local t0=os.clock()
	while os.clock()-t0 < latency+1 do
		if not part.Parent or not info.obj.Parent then return true end
		task.wait(0.05)
	end
	return false
end

--== Watchdog++ ==--
local stuckPos, stuckSince
task.spawn(function()
	while true do
		task.wait(0.2)
		local h=getHRP(); if not h then continue end
		if not stuckPos then stuckPos, stuckSince=h.Position, os.clock() end
		if (h.Position-stuckPos).Magnitude<2 then
			if os.clock()-stuckSince > STUCK_TIME then
				tpTo(HOME_POS)
				stuckPos, stuckSince=nil,nil
			end
		else
			stuckPos, stuckSince=h.Position, os.clock()
		end
	end
end)

--== Telemetry ==--
local function logEvent(rarity, success, t)
	table.insert(telemetry,{rarity=rarity,success=success,time=t})
	local sum, n=0,0
	for _,d in ipairs(telemetry) do if d.success then sum+=d.time n+=1 end end
	if n>0 then latency = math.clamp(sum/n,0.2,2.0) end
end

local function stats()
	local total, succ, sumTime=0,0,0
	for _,d in ipairs(telemetry) do
		total+=1
		if d.success then succ+=1 sumTime+=d.time end
	end
	local rate = total>0 and math.floor((succ/total)*100) or 0
	local avg = succ>0 and (sumTime/succ) or 0
	return total,succ,rate,avg,latency
end

--== UI Dashboard ==--
local gui = Instance.new("ScreenGui", LP.PlayerGui)
gui.ResetOnSpawn=false

local frame = Instance.new("Frame", gui)
frame.Size=UDim2.new(0,220,0,120)
frame.Position=UDim2.new(0,50,0,50)
frame.BackgroundColor3=Color3.fromRGB(30,30,40)
frame.BorderSizePixel=0
local title = Instance.new("TextLabel", frame)
title.Size=UDim2.new(1,0,0,24)
title.BackgroundTransparency=1
title.Text="World-Class Collector"
title.Font=Enum.Font.GothamBold
title.TextSize=14
title.TextColor3=Color3.fromRGB(255,255,255)

local btn = Instance.new("TextButton", frame)
btn.Size=UDim2.new(0,100,0,30)
btn.Position=UDim2.new(0,10,0,30)
btn.Text="Auto: OFF"
btn.Font=Enum.Font.GothamBold
btn.TextSize=14
btn.BackgroundColor3=Color3.fromRGB(50,50,70)
btn.TextColor3=Color3.fromRGB(220,220,240)
btn.MouseButton1Click:Connect(function()
	AUTO_ENABLED=not AUTO_ENABLED
	btn.Text=AUTO_ENABLED and "Auto: ON" or "Auto: OFF"
end)

local statsLbl = Instance.new("TextLabel", frame)
statsLbl.Size=UDim2.new(1,-20,0,60)
statsLbl.Position=UDim2.new(0,10,0,70)
statsLbl.BackgroundTransparency=1
statsLbl.TextColor3=Color3.fromRGB(200,200,220)
statsLbl.Font=Enum.Font.Gotham
statsLbl.TextSize=13
statsLbl.TextXAlignment=Enum.TextXAlignment.Left
statsLbl.TextYAlignment=Enum.TextYAlignment.Top

task.spawn(function()
	while true do
		task.wait(1)
		local total,succ,rate,avg,lat = stats()
		statsLbl.Text=string.format(
			"Total: %d\nSuccess: %d (%d%%)\nAvgTime: %.2fs\nLatency: %.2fs",
			total,succ,rate,avg,lat
		)
	end
end)

--== Main Loop ==--
task.spawn(function()
	while true do
		task.wait(0.2)
		if not AUTO_ENABLED then continue end
		local h=getHRP(); if not h then continue end

		-- หาเป้าที่ใกล้สุด
		local best,dist
		for part,info in pairs(targets) do
			if part and part.Parent and ESP_FILTER[info.rarity] then
				local d=(h.Position-part.Position).Magnitude
				if d<SCAN_RANGE and (not dist or d<dist) then
					best,dist={part=part,info=info},d
				end
			end
		end

		if not best then
			tpTo(HOME_POS)
		else
			local start=os.clock()
			tpTo(best.part.Position)
			local ok=collectFast(best.info,best.part)
			local t=os.clock()-start
			logEvent(best.info.rarity,ok,t)
			tpTo(HOME_POS)
		end
	end
end)
