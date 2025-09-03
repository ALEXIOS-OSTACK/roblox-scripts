--[[ 
MINI BOT + MAC-LIKE UI + ESP (Rarity 3–5)
เปิดดาบ -> TP ไปหา -> เก็บ (Remote + Prompt) -> กลับ HOME
• ใช้สำหรับทดสอบใน private server เท่านั้น
• ปลอดภัยต่อ "line 2": helpers อยู่ก่อนใช้งานทั้งหมด + guard ฟังก์ชัน
]]--

--== Services & Base ==--
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local RS                 = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LP   = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local HRP  = Char:WaitForChild("HumanoidRootPart")

--== Helpers (ประกาศก่อนใช้งานเสมอ) ==--
local function safeParent()
	-- บาง executor ไม่มี gethui(): ทำ fallback ให้
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and typeof(hui)=="Instance" then return hui end
	return game:FindFirstChildOfClass("CoreGui") or LP:WaitForChild("PlayerGui")
end

local function mk(c, p, props)
	local i = Instance.new(c); i.Parent = p
	if props then for k,v in pairs(props) do i[k] = v end end
	return i
end

local function hover(btn, base, over)
	btn.MouseEnter:Connect(function() if btn.Active~=false then btn.BackgroundColor3 = over end end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = base end)
	btn.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then btn.BackgroundColor3 = over:lerp(base,0.5) end end)
	btn.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then btn.BackgroundColor3 = over end end)
end

--== Config ==--
local ROOT_NAME             = "Resources"
local HOME_POS              = Vector3.new(-519.435, -5.452, -386.665)
local SPEED_STUDS_PER_S     = 150
local MIN_TWEEN_TIME        = 0.08
local TP_STEP_STUDS         = 90        -- ปรับจากสไลเดอร์ (60..140)
local SAFE_Y_OFFSET         = 1.5
local HEIGHT_BOOST          = 12
local MAX_DROP_PER_HOP      = 10
local MAX_SCAN_RANGE        = 6000
local COLLECT_RANGE         = 14
local MAX_TARGET_STUCK_TIME = 6
local ONLY_THESE            = { [3]=true, [4]=true, [5]=true }
local NAME_BLACKLIST        = { Trap=true, Dummy=true }

--== Runtime Vars ==--
local AUTO_ENABLED   = true
local ROOT           = workspace:WaitForChild(ROOT_NAME)
local targets        = {}   -- [part] = {obj, rarity, bb, hl, lbl}
local currentTween, lastGroundY, lastTP, _tpLock
local RP_BLACKLIST   = RaycastParams.new()
RP_BLACKLIST.FilterType = Enum.RaycastFilterType.Blacklist
RP_BLACKLIST.FilterDescendantsInstances = {LP.Character}

--== Motion / Physics ==--
local function getHRP()
	if HRP and HRP.Parent then return HRP end
	if LP.Character then
		HRP = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:WaitForChild("HumanoidRootPart", 5)
	end
	return HRP
end

local function ensureMobile()
	local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand=false; hum.Sit=false end
	local h=getHRP(); if h then h.Anchored=false end
end

local function zeroVel(h)
	if not h then return end
	h.AssemblyLinearVelocity = Vector3.zero
	h.AssemblyAngularVelocity = Vector3.zero
end

local function hasLineOfSight(fromPos, toPos)
	return workspace:Raycast(fromPos, toPos - fromPos, RP_BLACKLIST) == nil
end

local function snapToFloor(pos, up, down)
	up, down = up or 60, down or 300
	local res = workspace:Raycast(pos + Vector3.new(0,up,0), Vector3.new(0, -up-down, 0), RP_BLACKLIST)
	if res then
		lastGroundY = res.Position.Y + 0.10
		return Vector3.new(pos.X, lastGroundY, pos.Z)
	end
	if lastGroundY then
		return Vector3.new(pos.X, lastGroundY, pos.Z)
	end
	return pos
end

local function losAround(fromPos, center, r)
	r = r or 3
	local offs = {
		Vector3.new(0,0,0), Vector3.new(r,0,0), Vector3.new(-r,0,0),
		Vector3.new(0,0,r), Vector3.new(0,0,-r), Vector3.new(0,r,0)
	}
	for _,o in ipairs(offs) do
		if hasLineOfSight(fromPos, center + o) then return true end
	end
	return false
end

--== Tween TP (กันแกว่งขึ้นลงที่เดิม) ==--
local function tweenHop(toPos)
	local h=getHRP(); if not h then return end
	local dist = (h.Position - toPos).Magnitude
	local t = math.max(MIN_TWEEN_TIME, dist / SPEED_STUDS_PER_S)
	if currentTween and currentTween.PlaybackState==Enum.PlaybackState.Playing then currentTween:Cancel() end
	currentTween = TweenService:Create(h, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = CFrame.new(toPos)})
	currentTween:Play()
	local elapsed = 0
	while currentTween and currentTween.PlaybackState==Enum.PlaybackState.Playing do
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
	local h=getHRP(); if not h then return end
	local startPos = h.Position
	if not hasLineOfSight(startPos, targetPos) then
		targetPos = targetPos + Vector3.new(0, HEIGHT_BOOST, 0)
	end
	local dist  = (targetPos - startPos).Magnitude
	local steps = math.max(1, math.ceil(dist / TP_STEP_STUDS))
	for i=1,steps do
		local cur = getHRP().Position
		local raw = startPos:Lerp(targetPos, i/steps)
		local p
		if i < steps then
			p = (losAround(cur, raw, 3) and raw) or (raw + Vector3.new(0, math.min(SAFE_Y_OFFSET,3), 0))
		else
			p = snapToFloor(raw)
		end
		local drop = cur.Y - p.Y
		if drop > MAX_DROP_PER_HOP then
			local mid = Vector3.new(p.X, cur.Y - MAX_DROP_PER_HOP, p.Z)
			tweenHop(mid); zeroVel(getHRP())
		end
		tweenHop(p); zeroVel(getHRP())
	end
end

local function tpTo(vec3)
	if _tpLock then return end
	_tpLock = true
	ensureMobile()
	local h=getHRP()
	if h and lastTP and ((lastTP - vec3).Magnitude < 1.0) and (math.abs(lastTP.Y - vec3.Y) < 0.2) then
		_tpLock=false; return
	end
	tweenTP(vec3); lastTP = vec3
	_tpLock = false
end

--== Remotes / Sword / Collect ==--
local _lastSword=0
local function useFlyingSword() local ev=RS:WaitForChild("Remotes"):WaitForChild("FlyingSword"); pcall(function() ev:FireServer(true) end) end
local function stopFlyingSword() local ev=RS:WaitForChild("Remotes"):WaitForChild("FlyingSword"); pcall(function() ev:FireServer(false) end) end
local function useSwordDebounced() local now=os.clock(); if now-_lastSword>0.4 then _lastSword=now; useFlyingSword() end end

local function _normalizeId(id)
	if not id or type(id)~="string" then return nil end
	id = id:gsub("%s+",""); if id=="" then return nil end
	if id:sub(1,1) ~= "{" then id = "{"..id.."}" end
	return id
end

local function _findCollectIdFromInst(inst)
	if not inst or not inst.Parent then return nil end
	local keys={"CollectId","HerbId","ResourceId","ObjectId","Id","ID","Guid","GUID","UUID","Uid","uid","HerbUUID","RootId"}
	for _,k in ipairs(keys) do local v=inst:GetAttribute(k); if v and type(v)=="string" and #v>0 then return _normalizeId(v) end end
	for _,d in ipairs(inst:GetDescendants()) do
		if d:IsA("StringValue") then
			local n=d.Name:lower()
			if n=="collectid" or n=="herbid" or n=="resourceid" or n=="objectid" or n=="id" or n=="guid" or n=="uuid" or n=="uid" or n=="herbuuid" or n=="rootid" then
				if d.Value and d.Value~="" then return _normalizeId(d.Value) end
			end
		end
	end
	local m = string.match(inst.Name, "{[%x%-]+}"); if m then return m end
	return nil
end

-- บาง executor ไม่มี fireproximityprompt: ทำ fallback ด้วย ProximityPromptService
local function pressPrompt(prompt)
	if not prompt then return false end
	if typeof(fireproximityprompt) == "function" then
		local hd = prompt.HoldDuration or 0
		if hd <= 0 then pcall(function() fireproximityprompt(prompt) end)
		else local t0=os.clock(); pcall(function() fireproximityprompt(prompt,1) end)
			while os.clock()-t0 < hd+0.05 do task.wait() end
		end
		return true
	else
		-- fallback: ส่งสัญญาณเหมือนค้างปุ่ม E
		ProximityPromptService:InputHoldBegin(prompt)
		task.wait(prompt.HoldDuration or 0)
		ProximityPromptService:InputHoldEnd(prompt)
		return true
	end
end

local function waitGoneOrTimeout(part, info, timeout)
	local t0=os.clock()
	while os.clock()-t0<(timeout or 1.2) do
		if not part or not part.Parent or not info or not info.obj or not info.obj.Parent then return true end
		task.wait(0.05)
	end
	return false
end

local function collectViaRemote(info, part, timeout)
	local id=_findCollectIdFromInst(info and info.obj); if not id then return false end
	local ok=pcall(function() RS:WaitForChild("Remotes"):WaitForChild("Collect"):FireServer(id) end)
	if not ok then return false end
	return waitGoneOrTimeout(part, info, timeout or 1.2)
end

local function nearestPrompt(inst)
	local h=getHRP(); if not h then return nil end
	local best,dist
	for _,d in ipairs(inst:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Enabled then
			local pos = (d.Parent and d.Parent:IsA("BasePart")) and d.Parent.Position or h.Position
			local dd = (h.Position - pos).Magnitude
			if not dist or dd<dist then best,dist=d,dd end
		end
	end
	return best
end

local function collectIfNear(info, range)
	range = range or COLLECT_RANGE
	local h=getHRP(); if not (h and info and info.obj) then return false end
	local p = nearestPrompt(info.obj); if not p then return false end
	local pos = (p.Parent and p.Parent:IsA("BasePart")) and p.Parent.Position or h.Position
	if (h.Position - pos).Magnitude <= range then zeroVel(h); return pressPrompt(p) end
	return false
end

--== ESP ==--
local RARITY_NAME = { [3]="Legendary", [4]="Tier4", [5]="Tier5" }
local ESP_OUTLINE_ON = true
local function makeESP(part, rarity)
	local bb = mk("BillboardGui", part, {Name="IL_ESP", AlwaysOnTop=true, Size=UDim2.new(0,220,0,48), StudsOffset=Vector3.new(0,3.5,0), Adornee=part})
	local frame = mk("Frame", bb, {Size=UDim2.new(1,0,1,0), BackgroundTransparency=0.15, BorderSizePixel=0})
	mk("UICorner", frame, {CornerRadius=UDim.new(0,8)})
	local lbl = mk("TextLabel", frame, {BackgroundTransparency=1, Size=UDim2.new(1,-10,1,-10), Position=UDim2.new(0,5,0,5),
		Font=Enum.Font.GothamSemibold, TextScaled=true, TextColor3=Color3.fromRGB(255,255,255), TextStrokeTransparency=0.5})

	local hl = Instance.new("Highlight")
	hl.Adornee=part; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency=0.7; hl.OutlineTransparency=ESP_OUTLINE_ON and 0.1 or 1
	if rarity==5 then hl.OutlineColor=Color3.fromRGB(255,180,255)
	elseif rarity==4 then hl.OutlineColor=Color3.fromRGB(180,120,255)
	else hl.OutlineColor=Color3.fromRGB(120,220,255) end
	hl.Parent=part
	return bb,lbl,hl
end

local function updateESPOutline(on)
	ESP_OUTLINE_ON = on
	for _,rec in pairs(targets) do
		if rec.hl and rec.hl.Parent then rec.hl.OutlineTransparency = on and 0.1 or 1 end
	end
end

--== Scan Targets ==--
local function getPart(inst) if inst:IsA("BasePart") then return inst end return inst:FindFirstChildWhichIsA("BasePart", true) end

local function attach(inst)
	local r = inst:GetAttribute("Rarity")
	if not ONLY_THESE[r] or NAME_BLACKLIST[inst.Name] then return end
	local function bindWhenPartReady()
		local part = getPart(inst)
		if not part then
			inst.ChildAdded:Connect(function() bindWhenPartReady() end)
			return
		end
		if targets[part] then return end
		local bb,lbl,hl = makeESP(part, r)
		targets[part] = {obj=inst, rarity=r, bb=bb, lbl=lbl, hl=hl}
		inst.AncestryChanged:Connect(function(_, parent) if not parent then targets[part]=nil end end)
		part.AncestryChanged:Connect(function(_, parent) if not parent then targets[part]=nil end end)
	end
	bindWhenPartReady()
end

for _,d in ipairs(ROOT:GetDescendants()) do if d:GetAttribute("Rarity") ~= nil then attach(d) end end
ROOT.DescendantAdded:Connect(function(d) if d:GetAttribute("Rarity") ~= nil then attach(d) end end)
workspace.ChildAdded:Connect(function(c)
	if c.Name==ROOT_NAME then
		ROOT=c
		for _,rec in pairs(targets) do pcall(function() if rec.bb then rec.bb:Destroy() end end); pcall(function() if rec.hl then rec.hl:Destroy() end end) end
		targets = {}
		for _,d in ipairs(ROOT:GetDescendants()) do if d:GetAttribute("Rarity") ~= nil then attach(d) end end
		ROOT.DescendantAdded:Connect(function(d) if d:GetAttribute("Rarity") ~= nil then attach(d) end end)
	end
end)

-- อัปเดต ESP text
task.spawn(function()
	while true do
		task.wait(0.3)
		local h=getHRP(); if not h then continue end
		for part,info in pairs(targets) do
			if part and part.Parent and info.lbl then
				local dist=(h.Position - part.Position).Magnitude
				local dh = math.floor(part.Position.Y - h.Position.Y)
				local name = RARITY_NAME[info.rarity] or ("R"..tostring(info.rarity))
				info.lbl.Text = string.format("[%s]  %.0f studs (Δh=%d)", name, dist, dh)
				local visible = dist <= MAX_SCAN_RANGE
				if info.bb then info.bb.Enabled = visible end
				if info.hl then info.hl.Enabled = visible end
			end
		end
	end
end)

-- เลือกเป้า
local targetCooldown = {}  -- [part] -> until
local function cooldown(part, sec) targetCooldown[part]=os.clock()+sec end
local function isCooling(part) return (targetCooldown[part] or 0) > os.clock() end

local function nearestTarget()
	local h=getHRP(); if not h then return nil end
	local best, bestDist
	for part,info in pairs(targets) do
		if part and part.Parent and info and info.obj and info.obj.Parent and info.obj:IsDescendantOf(ROOT) and not isCooling(part) then
			local d=(h.Position - part.Position).Magnitude
			if d<=MAX_SCAN_RANGE and (not bestDist or d<bestDist or (d==bestDist and (info.rarity or 0)>(best.info.rarity or 0))) then
				best, bestDist = {part=part, info=info, dist=d}, d
			end
		end
	end
	return best
end

-- HOME ติดพื้น + refresh
HOME_POS = snapToFloor(HOME_POS)
task.spawn(function() while true do task.wait(10) local new=snapToFloor(HOME_POS); if (new - HOME_POS).Magnitude>0.1 then HOME_POS=new end end end)

--== Watchdog กันติด/แกว่ง ==--
local STUCK_RADIUS, STUCK_TIME = 2.0, 1.6
local _stuckOrigin, _stuckSince
task.spawn(function()
	while true do
		task.wait(0.2)
		local h=getHRP(); if not h then continue end
		local p=h.Position
		if not _stuckOrigin then _stuckOrigin, _stuckSince=p, os.clock() end
		local sameSpot = (p - _stuckOrigin).Magnitude <= STUCK_RADIUS
		if sameSpot then
			local vy = math.abs(h.AssemblyLinearVelocity.Y)
			if (os.clock()-_stuckSince) > STUCK_TIME and vy > 0.5 then
				if currentTween and currentTween.PlaybackState==Enum.PlaybackState.Playing then currentTween:Cancel() end
				ensureMobile(); zeroVel(h)
				h.CFrame = CFrame.new(snapToFloor(HOME_POS))
				zeroVel(h); lastTP, lastGroundY = nil, nil
				_stuckOrigin, _stuckSince = h.Position, os.clock()
			end
		else
			_stuckOrigin, _stuckSince = p, os.clock()
		end
	end
end)

--== UI (เหมือนภาพตัวอย่าง) ==--
local color = {
	bg=Color3.fromRGB(24,24,27), header=Color3.fromRGB(36,36,42), side=Color3.fromRGB(34,34,38),
	card=Color3.fromRGB(46,46,54), cardHover=Color3.fromRGB(70,70,78),
	text=Color3.fromRGB(220,220,230), muted=Color3.fromRGB(170,170,180), track=Color3.fromRGB(150,150,160)
}
local gui = mk("ScreenGui", safeParent(), {Name="MacLikeWindow", ResetOnSpawn=false, IgnoreGuiInset=true})
local win = mk("Frame", gui, {Size=UDim2.fromOffset(760,420), Position=UDim2.new(0,60,0,60), BackgroundColor3=color.bg, BorderSizePixel=0})
mk("UICorner", win, {CornerRadius=UDim.new(0,10)}); mk("UIStroke", win, {Color=Color3.fromRGB(0,0,0), Transparency=0.6, Thickness=1})
local header = mk("Frame", win, {Size=UDim2.new(1,0,0,40), BackgroundColor3=color.header, BorderSizePixel=0})
mk("UICorner", header, {CornerRadius=UDim.new(0,10)})
local tlWrap = mk("Frame", header, {Size=UDim2.fromOffset(80,40), BackgroundTransparency=1, Position=UDim2.new(0,12,0,0)})
local function dot(c,x) mk("Frame", tlWrap, {Size=UDim2.fromOffset(12,12), Position=UDim2.new(0,x,0,14), BackgroundColor3=c, BorderSizePixel=0}) end
dot(Color3.fromRGB(255,92,87),0); dot(Color3.fromRGB(255,189,46),20); dot(Color3.fromRGB(39,201,63),40)
mk("TextLabel", header, {Size=UDim2.new(1,-220,1,0), Position=UDim2.new(0,100,0,0), BackgroundTransparency=1, Text="Window",
	Font=Enum.Font.GothamSemibold, TextSize=16, TextColor3=color.text})
local search = mk("TextBox", header, {Size=UDim2.fromOffset(180,26), Position=UDim2.new(1,-196,0.5,-13),
	PlaceholderText="Search", Text="", ClearTextOnFocus=false, BackgroundColor3=Color3.fromRGB(58,58,64),
	TextColor3=color.text, Font=Enum.Font.Gotham, TextSize=14, BorderSizePixel=0})
mk("UICorner", search, {CornerRadius=UDim.new(0,6)}); mk("UIPadding", search, {PaddingLeft=UDim.new(0,10), PaddingRight=UDim.new(0,10)})

local sidebar = mk("Frame", win, {Size=UDim2.new(0,180,1,-40), Position=UDim2.new(0,0,0,40), BackgroundColor3=color.side, BorderSizePixel=0})
mk("UIPadding", sidebar, {PaddingTop=UDim.new(0,12), PaddingLeft=UDim.new(0,14), PaddingRight=UDim.new(0,10)})
mk("UIListLayout", sidebar, {Padding=UDim.new(0,8)})
local function sideItem(text,icon)
	local row=mk("Frame", sidebar, {Size=UDim2.new(1,0,0,28), BackgroundTransparency=1})
	mk("TextLabel", row, {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text=((icon and (icon.."  ")) or "")..text,
		Font=Enum.Font.Gotham, TextSize=14, TextColor3=color.muted, TextXAlignment=Enum.TextXAlignment.Left})
end
sideItem("Library","📚"); sideItem("Playlists","🎵"); sideItem("Favorites","❤")

local content = mk("Frame", win, {Size=UDim2.new(1,-180,1,-40), Position=UDim2.new(0,180,0,40), BackgroundColor3=color.bg, BorderSizePixel=0})
mk("UIPadding", content, {PaddingTop=UDim.new(0,18), PaddingLeft=UDim.new(0,18), PaddingRight=UDim.new(0,18)})
mk("UIListLayout", content, {Padding=UDim.new(0,16)})

local function makeButton(txt)
	local b=mk("TextButton", content, {Size=UDim2.new(0,260,0,44), BackgroundColor3=color.card, Text=txt, BorderSizePixel=0,
		Font=Enum.Font.GothamSemibold, TextSize=18, TextColor3=Color3.fromRGB(235,235,240)})
	mk("UICorner", b, {CornerRadius=UDim.new(0,8)})
	local st=mk("UIStroke", b, {Transparency=1, Thickness=1.4, Color=Color3.fromRGB(140,140,150)})
	hover(b, color.card, color.cardHover)
	return b, st
end

local btnHoverShade, hoverStroke = makeButton("Hover Shade")
local btnOutline,     outlineStroke = makeButton("Outline")

local slider = mk("Frame", content, {Size=UDim2.new(1,0,0,18), BackgroundTransparency=1})
local track  = mk("Frame", slider, {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0),
	Size=UDim2.new(1,0,0,6), BackgroundColor3=color.track, BorderSizePixel=0})
mk("UICorner", track, {CornerRadius=UDim.new(0,3)})

local knob = mk("Frame", slider, {Size=UDim2.fromOffset(18,18), BackgroundColor3=color.card, BorderSizePixel=0, Position=UDim2.new(0.5,-9,0.5,-9)})
mk("UICorner", knob, {CornerRadius=UDim.new(1,0)})
mk("UIStroke", knob, {Color=Color3.fromRGB(120,120,130), Transparency=0.2, Thickness=1.2})
hover(knob, color.card, color.cardHover)

local chkRow = mk("Frame", content, {Size=UDim2.new(1,0,0,24), BackgroundTransparency=1})
local chk    = mk("TextButton", chkRow, {Size=UDim2.fromOffset(18,18), BackgroundColor3=color.card, BorderSizePixel=0, Text=""})
mk("UICorner", chk, {CornerRadius=UDim.new(0,4)})
local tick   = mk("Frame", chk, {Visible=true, Size=UDim2.new(0,10,0,10), Position=UDim2.new(0.5,-5,0.5,-5),
	BackgroundColor3=Color3.fromRGB(230,230,240), BorderSizePixel=0})
mk("UICorner", tick, {CornerRadius=UDim.new(0,2)})
hover(chk, color.card, color.cardHover)
mk("TextLabel", chkRow, {Position=UDim2.new(0,26,0,0), Size=UDim2.new(1,-26,1,0), BackgroundTransparency=1, Text="check",
	Font=Enum.Font.Gotham, TextSize=14, TextColor3=color.muted, TextXAlignment=Enum.TextXAlignment.Left})

-- Drag window
do local dragging,startPos,startInput
	header.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 then
			dragging=true; startPos=win.Position; startInput=input.Position
			input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
			local d=input.Position - startInput
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
		end
	end)
end

-- UI -> Logic hooks
local shadeEnabled=true
btnHoverShade.MouseButton1Click:Connect(function() shadeEnabled = not shadeEnabled end)

local outlineEnabled=false
local function setOutline(on)
	outlineEnabled=on
	outlineStroke.Transparency = on and 0.15 or 1
	hoverStroke.Transparency   = on and 0.15 or 1
	updateESPOutline(on)
end
btnOutline.MouseButton1Click:Connect(function() setOutline(not outlineEnabled) end)

-- Slider 0..1 -> 60..140
local dragging=false; local sliderValue=0.5
local function setSlider(alpha)
	alpha = math.clamp(alpha,0,1)
	sliderValue = alpha
	knob.Position = UDim2.new(alpha, -9, 0.5, -9)
	TP_STEP_STUDS = math.floor(60 + alpha*(140-60))
end
setSlider((TP_STEP_STUDS-60)/(140-60))
knob.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true end end)
UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
UserInputService.InputChanged:Connect(function(i)
	if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
		local x=(i.Position.X - track.AbsolutePosition.X)/track.AbsoluteSize.X
		setSlider(x)
	end
end)

-- Checkbox -> AUTO
local function setChecked(on) AUTO_ENABLED=on; tick.Visible=on end
chk.MouseButton1Click:Connect(function() setChecked(not AUTO_ENABLED) end)
setChecked(true)

--== Main Loop ==--
task.spawn(function()
	useSwordDebounced()
	while true do
		task.wait(0.15)
		if not AUTO_ENABLED then continue end

		local node = nearestTarget()
		if not node then
			tpTo(HOME_POS)
		else
			useSwordDebounced()
			tpTo(node.part.Position)

			-- Collect: Remote ก่อน แล้วค่อย Prompt
			if not collectViaRemote(node.info, node.part, 1.2) then
				local t0=os.clock()
				local done=false
				while os.clock()-t0 < MAX_TARGET_STUCK_TIME do
					if not node.part or not node.part.Parent or not node.info or not node.info.obj or not node.info.obj.Parent then break end
					if collectIfNear(node.info) then waitGoneOrTimeout(node.part, node.info, 1.0); done=true; break end
					task.wait(0.08)
				end
				if not done then
					-- เป้าดื้อ: คูลดาวน์ 3s กันวน
					local part=node.part; if part then targetCooldown[part]=os.clock()+3.0 end
				end
			end

			tpTo(HOME_POS)
		end
	end
end)

-- Respawn safe
LP.CharacterAdded:Connect(function(c)
	Char = c
	HRP  = c:WaitForChild("HumanoidRootPart")
	task.delay(0.2, function() useSwordDebounced() end)
end)
