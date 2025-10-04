-- IMMORTAL LUCK • R3–R5 AUTO (Meditate <-> Hunt)
-- Unified MoveTo (StepTP / TweenTP / Auto) + Safety & Robustness Pack
-- Use in private servers for testing only. Use at your own risk.

--== Services ==
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = pcall(function() return game:GetService("TweenService") end) and game:GetService("TweenService") or nil
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local HRP = Char:FindFirstChild("HumanoidRootPart") or Char:WaitForChild("HumanoidRootPart", 5)

--== Config (defaults; validated later) ==
local CONFIG = {
    ROOT_NAME                = "Resources",
    TP_STEP_STUDS            = 120,
    HEIGHT_BOOST             = 30,
    SAFE_Y_OFFSET            = 2,
    MAX_SCAN_RANGE           = 6000,
    ONLY_THESE               = { [4]=true, [5]=true }, -- R4/R5 by default
    NAME_BLACKLIST           = { Trap=true, Dummy=true },
    COLLECT_RANGE            = 14,
    MAX_TARGET_STUCK_TIME    = 10,
    UI_POS                   = UDim2.new(0, 60, 0, 80),
    PRIORITY_MODE            = "Rarity", -- "Rarity","Nearest","Score"
    AUTO_ENABLED             = true,
    MEDITATE_POS             = Vector3.new(-2615.4,141.752,1385.9),

    APPROACH_RINGS           = {6,9,12,16},
    APPROACH_STEP_DEG        = 30,
    DROP_HEIGHT              = 18,

    RAM_INTO_ENABLED         = true,
    RAM_OVERSHOOT            = 8,
    USE_NOCLIP_FOR_RAM       = true,

    USE_REMOTE_COLLECT       = true,

    RARITY_NAME              = { [1]="Common", [2]="Rare", [3]="Legendary", [4]="Tier4", [5]="Tier5" },

    -- Movement mode: "Auto" | "StepTP" | "TweenTP"
    MOVEMENT_MODE            = "Auto",
    TP_SPEED_STUDS_PER_S     = 250, -- if <=0 Tween disabled and Auto chooses StepTP

    -- SafeMode caps (can tune)
    MOVE_MAX_CALLS_PER_S     = 6,
    MOVE_MAX_TOTAL_STUDS_S   = 900,
    MOVE_MIN_STEP_STUDS      = 6,

    -- RemoteGuard
    COLLECT_TOKENS_MAX       = 5,
    COLLECT_REFILL_EVERY     = 1.0,

    -- Rescue / safety
    SAFE_FLOOR_Y             = -1000,
    STUCK_SPEED              = 0.5,
    STUCK_SECS               = 2.0,
    RESCUE_COOLDOWN          = 1.0,
}

-- Validate / clamp config
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
CONFIG.TP_STEP_STUDS = clamp(tonumber(CONFIG.TP_STEP_STUDS or 120), 10, 500)
CONFIG.SAFE_Y_OFFSET = clamp(tonumber(CONFIG.SAFE_Y_OFFSET or 2), 0, 20)
CONFIG.HEIGHT_BOOST = clamp(tonumber(CONFIG.HEIGHT_BOOST or 30), 0, 200)
CONFIG.MAX_SCAN_RANGE = clamp(tonumber(CONFIG.MAX_SCAN_RANGE or 6000), 100, 20000)
CONFIG.COLLECT_RANGE = clamp(tonumber(CONFIG.COLLECT_RANGE or 14), 4, 30)
CONFIG.MAX_TARGET_STUCK_TIME = clamp(tonumber(CONFIG.MAX_TARGET_STUCK_TIME or 10), 2, 60)
if CONFIG.TP_SPEED_STUDS_PER_S < 0 then CONFIG.TP_SPEED_STUDS_PER_S = 0 end
local MOVEMENT_MODE = (CONFIG.MOVEMENT_MODE == "StepTP" or CONFIG.MOVEMENT_MODE == "TweenTP" or CONFIG.MOVEMENT_MODE == "Auto") and CONFIG.MOVEMENT_MODE or "Auto"

-- Short names for convenience
local TP_STEP_STUDS = CONFIG.TP_STEP_STUDS
local HEIGHT_BOOST = CONFIG.HEIGHT_BOOST
local SAFE_Y_OFFSET = CONFIG.SAFE_Y_OFFSET
local COLLECT_RANGE = CONFIG.COLLECT_RANGE
local MAX_SCAN_RANGE = CONFIG.MAX_SCAN_RANGE
local ONLY_THESE = CONFIG.ONLY_THESE
local NAME_BLACKLIST = CONFIG.NAME_BLACKLIST
local MEDITATE_POS = CONFIG.MEDITATE_POS
local TP_SPEED = CONFIG.TP_SPEED_STUDS_PER_S

--== Globals for script ==
local ROOT = workspace:WaitForChild(CONFIG.ROOT_NAME)
local targets = {} -- [part] = {obj=Instance, rarity=num}
local ordered, idx = {}, 1

-- Safety variables
local LAST_SAFE_POS = MEDITATE_POS
local _vel_avg = 0
local lastPos = nil
local lastMove = os.clock()
local _G_IL_KILLED = false

-- Janitor & Logging
local Janitor = {}
Janitor.__index = Janitor
function Janitor.new() return setmetatable({__cons={}, __items={}}, Janitor) end
function Janitor:add(obj, method) table.insert(self.__items, {obj=obj, method=method}); return obj end
function Janitor:connect(sig, fn) local c = sig:Connect(fn); table.insert(self.__cons, c); return c end
function Janitor:cleanup()
    for _,c in ipairs(self.__cons) do pcall(function() c:Disconnect() end) end
    for _,it in ipairs(self.__items) do
        pcall(function()
            if typeof(it.obj)=="Instance" then
                if it.method=="Destroy" then it.obj:Destroy()
                elseif it.method and it.obj[it.method] then it.obj[it.method](it.obj) else it.obj:Destroy() end
            elseif type(it.obj)=="function" then it.obj() end
        end)
    end
    self.__cons = {}; self.__items = {}
end
local J = Janitor.new()

local Log = {buf={}, max=80}
function Log:push(s)
    local t = os.date("!%H:%M:%S")
    table.insert(self.buf, string.format("[%s] %s", t, tostring(s)))
    if #self.buf > self.max then table.remove(self.buf, 1) end
end
function Log:dump() return table.concat(self.buf, "\n") end

-- Panic / Stop
_G.IL_KILLED = false
local function StopAll()
    _G.IL_KILLED = true
    pcall(function() AUTO_ENABLED = false end)
    pcall(function() stopFlyingSword() end)
    pcall(function() startCultivate() end)
    Log:push("PANIC: stopped all.")
end

--== Helper utils ==
local function safeParent()
    local ok,hui = pcall(function() return gethui and gethui() end)
    if ok and typeof(hui)=="Instance" then return hui end
    return game.CoreGui or LP:WaitForChild("PlayerGui")
end

local function getHRP()
    if HRP and HRP.Parent then return HRP end
    if LP.Character then
        HRP = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:WaitForChild("HumanoidRootPart", 5)
    end
    return HRP
end

local function distance(a,b) return (a-b).Magnitude end
local function isNear(a,b,r) return distance(a,b) <= (r or 4) end

local function getPart(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function gradientFor(num)
    local gFolder = RS:FindFirstChild("RarityGradients")
    return gFolder and gFolder:FindFirstChild(tostring(num)) or nil
end

--== Line-of-sight ==
local function hasLineOfSight(fromPos, toPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    local dir = toPos - fromPos
    local result = workspace:Raycast(fromPos, dir, params)
    return result == nil
end

--== Safety Helpers: rayDown, isGrounded, maybeUpdateLastSafe, velocity average ==
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

local function maybeUpdateLastSafe()
    local h = getHRP(); if not h then return end
    local ok = isGrounded(h.Position)
    if ok then LAST_SAFE_POS = h.Position end
end

RunService.Heartbeat:Connect(function(dt)
    local h = getHRP(); if not h then return end
    local v = (h.AssemblyLinearVelocity or Vector3.zero).Magnitude
    _vel_avg = _vel_avg*0.85 + v*0.15
    if lastPos then if (h.Position - lastPos).Magnitude > 1 then lastMove = os.clock() end end
    lastPos = h.Position
end)

--== Safe Snap (smart): replaced safe snap that checks for floor and prevents NaN/under-map ==
local function isFiniteNumber(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function validateVector3(v)
    if typeof(v) ~= "Vector3" then return false end
    return isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)
end

local function sanitizeTargetPos(pos)
    if not validateVector3(pos) then
        Log:push("[sanitizeTargetPos] invalid target, fallback to LAST_SAFE_POS or MEDITATE_POS")
        return (LAST_SAFE_POS or MEDITATE_POS) + Vector3.new(0, SAFE_Y_OFFSET, 0)
    end
    local minY = CONFIG.SAFE_FLOOR_Y or -1000
    if pos.Y < minY then pos = Vector3.new(pos.X, minY + SAFE_Y_OFFSET, pos.Z) end
    return pos
end

local function _safeSnap(toPos)
    local h = getHRP(); if not h then return end
    local t = sanitizeTargetPos(toPos)
    local grounded, floorPos = isGrounded(t)
    local target = t
    if grounded and floorPos then
        target = Vector3.new(t.X, math.max(t.Y, floorPos.Y + SAFE_Y_OFFSET), t.Z)
    else
        target = t + Vector3.new(0, math.max(SAFE_Y_OFFSET, 6), 0)
    end
    pcall(function() h.CFrame = CFrame.new(target) end)
    maybeUpdateLastSafe()
end

--== Remotes: Cultivate/FlyingSword helpers ==
local CUL_MIN_INTERVAL = 1.2
local CultivateState = { on=false, lastSend=0 }
local function setCultivate(desired)
    local now = os.clock()
    if CultivateState.on == desired and (now - CultivateState.lastSend) < CUL_MIN_INTERVAL then return end
    CultivateState.lastSend = now; CultivateState.on = desired
    local ev = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("Cultivate")
    if ev then pcall(function() ev:FireServer(desired) end) end
end
local function startCultivate() setCultivate(true) end
local function stopCultivate() setCultivate(false) end

local function useFlyingSword()
    local ev = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("FlyingSword")
    if ev then pcall(function() ev:FireServer(true) end) end
end
local function stopFlyingSword()
    local ev = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("FlyingSword")
    if ev then pcall(function() ev:FireServer(false) end) end
end

--== Remote Collect helpers (normalize id, find) ==
local function _normalizeId(id)
    if not id or type(id) ~= "string" then return nil end
    id = id:gsub("%s+", "")
    if id == "" then return nil end
    if id:sub(1,1) ~= "{" then id = "{"..id.."}" end
    return id
end

local function _findCollectIdFromInst(inst)
    if not inst or not inst.Parent then return nil end
    local keys = {
        "CollectId","HerbId","ResourceId","ObjectId","Id","ID",
        "Guid","GUID","UUID","Uid","uid","HerbUUID","RootId"
    }
    for _,k in ipairs(keys) do
        local v = inst:GetAttribute(k)
        if v and type(v)=="string" and #v>0 then
            return _normalizeId(v)
        end
    end
    for _,d in ipairs(inst:GetDescendants()) do
        if d:IsA("StringValue") then
            local name = d.Name:lower()
            if name=="collectid" or name=="herbid" or name=="resourceid" or
               name=="objectid" or name=="id" or name=="guid" or
               name=="uuid" or name=="uid" or name=="herbuuid" or name=="rootid" then
                if d.Value and d.Value ~= "" then return _normalizeId(d.Value) end
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

--== RemoteGuard (token bucket + backoff) ==
local RemoteGuard = {}
RemoteGuard.__index = RemoteGuard
function RemoteGuard.new(maxTokens, refillSec)
    local self = setmetatable({}, RemoteGuard)
    self.maxTokens = maxTokens or CONFIG.COLLECT_TOKENS_MAX
    self.tokens = self.maxTokens
    self.refillSec = refillSec or CONFIG.COLLECT_REFILL_EVERY
    self.lastRefill = os.clock()
    self.backoffs = {} -- key => {tries, until}
    return self
end
function RemoteGuard:refill()
    local now = os.clock()
    local delta = now - (self.lastRefill or 0)
    if delta >= self.refillSec then
        local add = math.floor(delta / self.refillSec)
        self.tokens = math.min(self.maxTokens, (self.tokens or 0) + add)
        self.lastRefill = now
    end
end
function RemoteGuard:allow(key)
    self:refill()
    key = key or "__default__"
    local bo = self.backoffs[key]
    if bo and bo.until and os.clock() < bo.until then return false end
    if (self.tokens or 0) > 0 then
        self.tokens = self.tokens - 1
        return true
    else
        return false
    end
end
function RemoteGuard:penalize(key)
    key = key or "__default__"
    local bo = self.backoffs[key] or {tries=0, until=0}
    bo.tries = bo.tries + 1
    local waitFor = math.min(5, 0.5 * (2 ^ (bo.tries - 1)))
    bo.until = os.clock() + waitFor
    self.backoffs[key] = bo
    Log:push(("RemoteGuard penalize %s -> wait %.2fs (tries=%d)"):format(tostring(key), waitFor, bo.tries))
end
local remoteGuard = RemoteGuard.new(CONFIG.COLLECT_TOKENS_MAX, CONFIG.COLLECT_REFILL_EVERY)

-- wrapper for collect remote (throttle + backoff)
local _collect_via_remote_raw = function(info, part, timeout)
    if not CONFIG.USE_REMOTE_COLLECT then return false end
    local id = _findCollectIdFromInst(info and info.obj)
    if not id then return false end
    local ok, err = pcall(function() RS:WaitForChild("Remotes"):WaitForChild("Collect"):FireServer(id) end)
    if not ok then
        warn("[IL] Collect remote failed:", err)
        return false
    end
    return waitGoneOrTimeout(part, info, timeout or 1.2)
end

local function collectViaRemote(info, part, timeout)
    local key = tostring(info and info.obj and info.obj:GetDebugId and info.obj:GetDebugId() or (info and info.obj and info.obj.Name) or "collect")
    if not remoteGuard:allow(key) then
        return false
    end
    local ok = _collect_via_remote_raw(info, part, timeout)
    if not ok then
        remoteGuard:penalize(key)
    end
    return ok
end

--== Press prompt helper ==
local function pressPrompt(prompt)
    if not prompt then return false end
    if typeof(fireproximityprompt) ~= "function" then return false end
    local hd = prompt.HoldDuration or 0
    if hd <= 0 then
        pcall(function() fireproximityprompt(prompt) end)
        return true
    else
        local t0 = os.clock()
        pcall(function() fireproximityprompt(prompt, 1) end)
        while os.clock() - t0 < hd + 0.05 do task.wait() end
        return true
    end
end

local function collectIfNear(info, range)
    range = range or COLLECT_RANGE
    local prompt = info.obj and info.obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    local hrp = getHRP()
    local p = info.obj and getPart(info.obj)
    if prompt and hrp and p and (hrp.Position - p.Position).Magnitude <= range then
        return pressPrompt(prompt)
    end
    return false
end

--== Movement Core: StepTP / TweenTP / Auto ==
local function _stepPath(fromPos, toPos)
    local start = fromPos
    local target = toPos
    if not hasLineOfSight(start, target) then
        target = target + Vector3.new(0, HEIGHT_BOOST, 0)
    end
    local dist = (target - start).Magnitude
    local step = math.max(1, TP_STEP_STUDS)
    local steps = math.max(1, math.ceil(dist / step))
    for i = 1, steps do
        if _G.IL_KILLED then return end
        local p = start:Lerp(target, i/steps)
        _safeSnap(p)
        RunService.Heartbeat:Wait()
    end
end

local function _tweenPathBySpeed(fromPos, toPos, speed)
    local h = getHRP(); if not h then return end
    if not TweenService or type(speed)~="number" or speed <= 0 then
        return _stepPath(fromPos, toPos)
    end
    local target = toPos
    if not hasLineOfSight(fromPos, target) then
        target = target + Vector3.new(0, HEIGHT_BOOST, 0)
    end
    local dist = (target - fromPos).Magnitude
    local duration = math.max(0.02, dist / speed)
    local ok, tw = pcall(function()
        return TweenService:Create(h, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(target + Vector3.new(0, SAFE_Y_OFFSET, 0))})
    end)
    if not ok or not tw then
        Log:push("[Move] Tween create failed, fallback to StepTP")
        return _stepPath(fromPos, target)
    end
    pcall(function() tw:Play() end)
    local t0 = os.clock()
    local s, e = pcall(function() tw.Completed:Wait() end)
    if not s then
        Log:push("[Move] Tween Completed wait error, fallback Snap")
        _safeSnap(target)
    end
    if os.clock() - t0 > duration + 2 then
        _safeSnap(target)
    end
end

-- MoveTo API (original raw)
local function _MoveTo_raw(vec3)
    local h = getHRP(); if not h or not vec3 then return end
    local start = h.Position
    if MOVEMENT_MODE == "StepTP" then
        return _stepPath(start, vec3)
    elseif MOVEMENT_MODE == "TweenTP" then
        return _tweenPathBySpeed(start, vec3, TP_SPEED)
    else -- Auto
        if TP_SPEED and TP_SPEED > 0 then
            return _tweenPathBySpeed(start, vec3, TP_SPEED)
        else
            return _stepPath(start, vec3)
        end
    end
end

--== SafeMoveTo wrapper: rate-limit, smoothing, jitter, verification, fallback rescue ==
-- window-based rate limiter & budget
local MOVE_WINDOW_SECONDS = 1.0
local MOVE_MAX_CALLS_PER_WINDOW = CONFIG.MOVE_MAX_CALLS_PER_S or 6
local MOVE_MAX_DISTANCE_PER_WINDOW = CONFIG.MOVE_MAX_TOTAL_STUDS_S or 900
local move_window_t0 = os.clock()
local move_calls = 0
local move_distance = 0.0

local function moveWindowResetIfNeeded()
    local now = os.clock()
    if now - move_window_t0 >= MOVE_WINDOW_SECONDS then
        move_window_t0 = now
        move_calls = 0
        move_distance = 0.0
    end
end

local function moveWindowAllow(dist)
    moveWindowResetIfNeeded()
    if move_calls + 1 > MOVE_MAX_CALLS_PER_WINDOW then return false end
    if move_distance + dist > MOVE_MAX_DISTANCE_PER_WINDOW then return false end
    return true
end

local function naturalDelayBase()
    return 0.015 + math.random()*0.03
end

local function arrivedAt(target)
    local h = getHRP(); if not h then return false end
    return (h.Position - target).Magnitude <= (COLLECT_RANGE + 2)
end

local function rescueNow(reason)
    if os.clock() - (rescueNow._last or 0) < (CONFIG.RESCUE_COOLDOWN or 1.0) then return end
    rescueNow._last = os.clock()
    Log:push("rescueNow: "..tostring(reason))
    local h = getHRP(); if not h then return end
    if LAST_SAFE_POS then
        _safeSnap(LAST_SAFE_POS + Vector3.new(0, HEIGHT_BOOST, 0))
        task.wait(0.05)
        _safeSnap(LAST_SAFE_POS)
    else
        _safeSnap(MEDITATE_POS + Vector3.new(0, HEIGHT_BOOST, 0))
        task.wait(0.05)
        _safeSnap(MEDITATE_POS)
    end
    stopFlyingSword()
    startCultivate()
end

local function SafeMoveTo(targetVec3)
    if _G.IL_KILLED then return end
    local h = getHRP(); if not h then return end
    local sanitized = sanitizeTargetPos(targetVec3)
    local dist = (h.Position - sanitized).Magnitude
    if dist < 3 then return end
    if not moveWindowAllow(dist) then
        task.wait(0.08 + math.random()*0.06)
        moveWindowResetIfNeeded()
    end
    move_calls = move_calls + 1
    move_distance = move_distance + dist

    -- if using StepTP and far, break into soft sub-targets for smoother motion
    if MOVEMENT_MODE ~= "TweenTP" and dist > TP_STEP_STUDS * 1.5 then
        local steps = math.max(1, math.ceil(dist / TP_STEP_STUDS))
        for i = 1, steps do
            if _G.IL_KILLED then return end
            local p = h.Position:Lerp(sanitized, i/steps)
            _safeSnap(Vector3.new(p.X, p.Y, p.Z))
            RunService.Heartbeat:Wait()
        end
    else
        task.wait(naturalDelayBase())
        pcall(function() _MoveTo_raw(sanitized) end)
    end

    task.wait(0.05)
    if not arrivedAt(sanitized) then
        _safeSnap(sanitized + Vector3.new(0, HEIGHT_BOOST * 0.6, 0))
        task.wait(0.06)
        pcall(function() _MoveTo_raw(sanitized) end)
        task.wait(0.08)
        if not arrivedAt(sanitized) then
            Log:push("[SafeMoveTo] failed arrival -> rescue")
            rescueNow("failed_arrival")
        end
    end
end

-- Replace MoveTo symbol for rest of script
local MoveTo = SafeMoveTo

--== Approach / Ram-Into (use MoveTo) ==
local function closeEnough(hrpPos, targetPos) return (hrpPos - targetPos).Magnitude <= (COLLECT_RANGE + 1) end

local function approachTarget(part)
    local hrp = getHRP()
    if not (hrp and part and part.Parent) then return false end
    local tpos = part.Position

    MoveTo(tpos)
    if closeEnough(getHRP().Position, tpos) then return true end

    MoveTo(tpos + Vector3.new(0, CONFIG.DROP_HEIGHT or 18, 0))
    MoveTo(tpos)
    if closeEnough(getHRP().Position, tpos) then return true end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}

    for _,radius in ipairs(CONFIG.APPROACH_RINGS or {6,9,12,16}) do
        for deg = 0, 360 - (CONFIG.APPROACH_STEP_DEG or 30), (CONFIG.APPROACH_STEP_DEG or 30) do
            local r = math.rad(deg)
            local candidate = tpos + Vector3.new(math.cos(r)*radius, SAFE_Y_OFFSET, math.sin(r)*radius)
            local hit = workspace:Raycast(hrp.Position, candidate - hrp.Position, params)
            if not hit then
                MoveTo(candidate); MoveTo(tpos)
                if closeEnough(getHRP().Position, tpos) then return true end
            end
        end
    end

    _safeSnap(tpos + Vector3.new(0, SAFE_Y_OFFSET + 1.5, 0))
    return closeEnough(getHRP().Position, tpos)
end

local function setCharacterNoClip(on)
    if on then
        if _G.__origCollide then return end
        _G.__origCollide = {}
        Char = LP.Character or Char
        for _,p in ipairs(Char:GetDescendants()) do
            if p:IsA("BasePart") then
                _G.__origCollide[p] = p.CanCollide
                p.CanCollide = false
            end
        end
    else
        if not _G.__origCollide then return end
        for p,can in pairs(_G.__origCollide) do
            if p and p.Parent then p.CanCollide = can end
        end
        _G.__origCollide = nil
    end
end

local function ramInto(part)
    if not CONFIG.RAM_INTO_ENABLED then return false end
    local hrp = getHRP(); if not (hrp and part and part.Parent) then return false end
    local tpos = part.Position
    local dir = (tpos - hrp.Position); if dir.Magnitude < 1e-3 then dir = Vector3.new(0,1,0) else dir = dir.Unit end

    if CONFIG.USE_NOCLIP_FOR_RAM then setCharacterNoClip(true) end
    MoveTo(tpos + Vector3.new(0, HEIGHT_BOOST, 0))
    MoveTo(tpos + dir * (CONFIG.RAM_OVERSHOOT or 8))
    MoveTo(tpos)
    if CONFIG.USE_NOCLIP_FOR_RAM then setCharacterNoClip(false) end

    local hrp2 = getHRP()
    return hrp2 and closeEnough(hrp2.Position, tpos)
end

--== Targets scanning & attach/ESP minimal ==
local function makeESP(part, rarity)
    local bb = Instance.new("BillboardGui"); bb.Name="IL_ESP"; bb.AlwaysOnTop=true; bb.Size=UDim2.new(0,220,0,48); bb.StudsOffset=Vector3.new(0,3.5,0); bb.Adornee=part; bb.Parent=part
    local frame = Instance.new("Frame", bb); frame.Size=UDim2.new(1,0,1,0); frame.BackgroundTransparency=0.15; frame.BorderSizePixel=0; Instance.new("UICorner", frame).CornerRadius=UDim.new(0,8)
    local g = gradientFor(rarity); if g then pcall(function() g:Clone().Parent = frame end) end
    local lbl = Instance.new("TextLabel", frame); lbl.BackgroundTransparency=1; lbl.Size=UDim2.new(1,-10,1,-10); lbl.Position=UDim2.new(0,5,0,5); lbl.Font=Enum.Font.GothamSemibold; lbl.TextScaled=true; lbl.TextColor3=Color3.fromRGB(255,255,255); lbl.TextStrokeTransparency=0.5
    local hl = Instance.new("Highlight"); hl.Adornee = part; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.FillTransparency=0.7; hl.OutlineTransparency=0.1; hl.Parent=part
    if rarity==5 then hl.OutlineColor = Color3.fromRGB(255,180,255)
    elseif rarity==4 then hl.OutlineColor = Color3.fromRGB(180,120,255)
    elseif rarity==3 then hl.OutlineColor = Color3.fromRGB(120,220,255) end
    return bb, lbl, hl
end

local function forget(part)
    if not part then return end
    local rec = targets[part]
    if not rec then return end
    pcall(function() if rec.bb then rec.bb:Destroy() end end)
    pcall(function() if rec.hl then rec.hl:Destroy() end end)
    targets[part] = nil
end

local function attach(inst)
    local r = inst:GetAttribute and inst:GetAttribute("Rarity")
    if not r then return end
    if not ONLY_THESE[r] then return end
    if NAME_BLACKLIST[inst.Name] then return end
    local part = getPart(inst)
    if not part or targets[part] then return end
    local bb, lbl, hl = makeESP(part, r)
    targets[part] = {obj=inst, rarity=r, bb=bb, lbl=lbl, hl=hl}
    inst.AncestryChanged:Connect(function(_, parent) if not parent then forget(part) end end)
end

for _,d in ipairs(ROOT:GetDescendants()) do
    if d:GetAttribute and d:GetAttribute("Rarity") ~= nil then attach(d) end
end
ROOT.DescendantAdded:Connect(function(d) if d:GetAttribute and d:GetAttribute("Rarity") ~= nil then attach(d) end end)

workspace.ChildAdded:Connect(function(c)
    if c.Name == CONFIG.ROOT_NAME then
        ROOT = c
        for part, rec in pairs(targets) do
            pcall(function() if rec.bb then rec.bb:Destroy() end end)
            pcall(function() if rec.hl then rec.hl:Destroy() end end)
            targets[part] = nil
        end
        for _,d in ipairs(ROOT:GetDescendants()) do
            if d:GetAttribute and d:GetAttribute("Rarity") ~= nil then attach(d) end
        end
        ROOT.DescendantAdded:Connect(function(d) if d:GetAttribute and d:GetAttribute("Rarity") ~= nil then attach(d) end end)
    end
end)

--== Ordering / Priority ==
local function scoreOf(node) return (node.info.rarity or 0) * 1000 - (node.dist or 0) end
local function sortNodes(a,b)
    if CONFIG.PRIORITY_MODE == "Nearest" then
        if a.dist ~= b.dist then return a.dist < b.dist end
        return (a.info.rarity or 0) > (b.info.rarity or 0)
    elseif CONFIG.PRIORITY_MODE == "Score" then
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
    local r = info.obj:GetAttribute and info.obj:GetAttribute("Rarity")
    if not ONLY_THESE[r] then return false end
    return true
end

local function refreshList()
    ordered = {}
    local h = getHRP(); if not h then return end
    for part, info in pairs(targets) do
        if isValidTarget(part, info) then
            local dist = distance(h.Position, part.Position)
            if dist <= MAX_SCAN_RANGE then
                table.insert(ordered, {part=part, info=info, dist=dist})
            end
        end
    end
    table.sort(ordered, sortNodes)
    if #ordered == 0 then idx = 1 else idx = math.clamp(idx,1,#ordered) end
end

--== Visual updater / HUD minimal ==
local gui = Instance.new("ScreenGui")
gui.Name = "IL_AutoCore"
gui.ResetOnSpawn = false
gui.Parent = (pcall(function() return gethui and gethui() end) and gethui()) or game.CoreGui or LP:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel", gui)
label.BackgroundTransparency = 0.2
label.BackgroundColor3 = Color3.fromRGB(25,25,30)
label.TextColor3 = Color3.fromRGB(230,230,240)
label.TextSize = 14
label.Font = Enum.Font.GothamSemibold
label.Size = UDim2.new(0, 420, 0, 22)
label.Position = CONFIG.UI_POS or UDim2.new(0,60,0,70)
label.Text = "IL: -"

local function setHUD(txt) pcall(function() label.Text = "IL: "..txt end) end

task.spawn(function()
    while true do
        task.wait(0.25)
        local h = getHRP(); if not h then continue end
        for part,info in pairs(targets) do
            if part and part.Parent and info and info.obj and info.obj.Parent then
                local dist = distance(h.Position, part.Position)
                if info.lbl then
                    local name = CONFIG.RARITY_NAME[info.rarity] or ("R"..tostring(info.rarity))
                    info.lbl.Text = string.format("[%s:%d]  %.0f studs", name, info.rarity, dist)
                end
                local visible = dist <= MAX_SCAN_RANGE
                if info.bb then info.bb.Enabled = visible end
                if info.hl then info.hl.Enabled = visible end
            end
        end
        refreshList()
    end
end)

--== Load-aware FPS dynamic wait ==
local fps, alpha = 60, 0.05
RunService.Heartbeat:Connect(function(dt) local nowFps = 1/dt; fps = fps*(1-alpha) + nowFps*alpha end)
local function dynamicWait()
    if fps > 80 then return 0.10
    elseif fps > 50 then return 0.15
    elseif fps > 30 then return 0.22
    else return 0.30 end
end

--== Anti-freeze watchdog & Rescue loop ==
task.spawn(function()
    while task.wait(1.0) do
        local h = getHRP(); if not h then continue end
        if os.clock() - lastMove > 8 then
            refreshList()
        end
    end
end)

task.spawn(function()
    while task.wait(0.25) do
        local h = getHRP(); if not h then continue end
        local pos = h.Position
        -- void detection
        if pos.Y < CONFIG.SAFE_FLOOR_Y then
            rescueNow("void")
        end
        -- stuck detection
        if not CultivateState.on and _vel_avg < CONFIG.STUCK_SPEED then
            local hitDown = rayDown(pos + Vector3.new(0,2,0), 10)
            if hitDown then _safeSnap(pos + Vector3.new(0, HEIGHT_BOOST, 0)); task.wait(0.05) end
            if _vel_avg < CONFIG.STUCK_SPEED then
                rescueNow("stuck")
            end
        end
        maybeUpdateLastSafe()
    end
end)

--== AUTO LOOP: Meditate <-> Hunt ==
local MODE = "Meditate"
task.spawn(function()
    while task.wait(dynamicWait()) do
        if _G.IL_KILLED then break end
        if not CONFIG.AUTO_ENABLED then setHUD("Paused"); continue end
        refreshList()

        if MODE == "Meditate" then
            if #ordered == 0 then
                local hrp = getHRP()
                if hrp and not isNear(hrp.Position, MEDITATE_POS, 6) then
                    stopFlyingSword()
                    MoveTo(MEDITATE_POS)
                end
                if not CultivateState.on then startCultivate() end
                task.wait(0.5)
                refreshList()
                if #ordered > 0 then stopCultivate(); MODE = "Hunt" end
            else
                stopCultivate()
                MODE = "Hunt"
            end

        else -- Hunt
            if #ordered == 0 then
                stopFlyingSword(); MoveTo(MEDITATE_POS); task.wait(0.05); startCultivate(); MODE = "Meditate"
            else
                for i, node in ipairs(ordered) do
                    if not node or not isValidTarget(node.part, node.info) then continue end

                    stopCultivate(); task.wait(0.12)
                    useFlyingSword(); task.wait(0.12)

                    setHUD(("Hunt: %d left | Move=%s"):format(#ordered, MOVEMENT_MODE))

                    -- Ram Into
                    local ok = false
                    if CONFIG.RAM_INTO_ENABLED then ok = ramInto(node.part) end
                    if not ok then
                        ok = approachTarget(node.part)
                        if not ok then
                            MoveTo(node.part.Position)
                        end
                    end

                    if not CONFIG.COLLECT_WITH_SWORD then stopFlyingSword(); task.wait(0.05) end

                    local done = false
                    if collectViaRemote(node.info, node.part, 1.2) then
                        done = true
                    else
                        local t0 = os.clock()
                        while os.clock() - t0 < CONFIG.MAX_TARGET_STUCK_TIME do
                            if not isValidTarget(node.part, node.info) then break end
                            if collectIfNear(node.info) then waitGoneOrTimeout(node.part, node.info, 1.2); done = true; break end
                            task.wait(0.08)
                        end
                    end

                    if not CONFIG.COLLECT_WITH_SWORD then task.wait(0.05); useFlyingSword() end
                end

                refreshList()
                if #ordered == 0 then stopFlyingSword(); MoveTo(MEDITATE_POS); task.wait(0.05); startCultivate(); MODE = "Meditate" end
            end
        end

        -- HUD update
        if #ordered == 0 then setHUD(("Mode=%s | Left=0"):format(MODE))
        else
            local node = ordered[idx]
            local r = node.info.rarity
            local name = CONFIG.RARITY_NAME[r] or ("R"..tostring(r))
            setHUD(("Mode=%s | Target=%s(R%d) %.0f studs | Left=%d | Move=%s@%s")
                :format(MODE, name, r, node.dist, #ordered, MOVEMENT_MODE, (MOVEMENT_MODE=="TweenTP" and ("@"..tostring(TP_SPEED).."s/s") or "")))
        end
    end
end)

--== Manual Tween Test + Speed-based Tween Test (hotkeys) ==
local TEST_POS = Vector3.new(0,0,0) -- set to desired test pos
local TEST_DELAY = 0 -- if >0 uses fixed time; if 0 uses TP_SPEED studs/sec
local TP_SPEED_OVERRIDE = TP_SPEED

local function ManualTweenTo(targetPosOrPart, speedOrDelay)
    local h = getHRP(); if not h then return end
    local target
    if typeof(targetPosOrPart) == "Instance" and targetPosOrPart:IsA("BasePart") then
        target = targetPosOrPart.Position
    elseif typeof(targetPosOrPart) == "CFrame" then
        target = targetPosOrPart.Position
    else
        target = targetPosOrPart
    end
    if not validateVector3(target) then
        Log:push("[ManualTweenTo] invalid target")
        return
    end
    if type(speedOrDelay) == "number" and speedOrDelay > 0 then
        local duration = speedOrDelay
        if TweenService then
            local ok, tw = pcall(function()
                local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
                return TweenService:Create(h, info, {CFrame = CFrame.new(target + Vector3.new(0, SAFE_Y_OFFSET, 0))})
            end)
            if ok and tw then pcall(function() tw:Play(); tw.Completed:Wait() end) else _safeSnap(target) end
        else
            _safeSnap(target)
        end
    else
        local speed = TP_SPEED_OVERRIDE or TP_SPEED or 200
        if speed <= 0 or not TweenService then
            _stepPath(h.Position, target)
        else
            _tweenPathBySpeed(h.Position, target, speed)
        end
    end
end

-- Hotkeys: L = manual test, K = toggle movement mode, RightShift+P = Panic
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.L then
        if TEST_DELAY > 0 then ManualTweenTo(TEST_POS, TEST_DELAY) else ManualTweenTo(TEST_POS) end
    elseif input.KeyCode == Enum.KeyCode.K then
        MOVEMENT_MODE = (MOVEMENT_MODE == "Auto" and "StepTP") or (MOVEMENT_MODE == "StepTP" and "TweenTP") or "Auto"
        Log:push("Switched MOVEMENT_MODE -> "..tostring(MOVEMENT_MODE))
        setHUD(("Switch Move=%s"):format(MOVEMENT_MODE))
    elseif UserInputService:IsKeyDown(Enum.KeyCode.RightShift) and input.KeyCode == Enum.KeyCode.P then
        StopAll()
    end
end)

-- Panic overlay (small) and safety overlay (toggle)
local function createMiniOverlay()
    local parent = safeParent()
    local sg = Instance.new("ScreenGui"); sg.Name = "IL_SafetyOverlay"; sg.ResetOnSpawn=false; sg.Parent = parent
    J:add(sg, "Destroy")
    local f = Instance.new("Frame", sg); f.Size=UDim2.new(0,420,0,160); f.Position=UDim2.new(0,60,0,50); f.BackgroundColor3=Color3.fromRGB(20,20,24); f.BorderSizePixel=0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,12)
    local title = Instance.new("TextLabel", f); title.Size=UDim2.new(1,-12,0,22); title.Position=UDim2.new(0,6,0,6); title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=14; title.TextColor3=Color3.fromRGB(235,235,245)
    title.Text = "IL • Safety Overlay (RightShift+P = Panic)"
    local body = Instance.new("TextLabel", f); body.Size=UDim2.new(1,-12,1,-36); body.Position=UDim2.new(0,6,0,28); body.BackgroundTransparency=1; body.Font=Enum.Font.Code; body.TextXAlignment=Enum.TextXAlignment.Left; body.TextYAlignment=Enum.TextYAlignment.Top; body.TextSize=13; body.TextColor3=Color3.fromRGB(210,210,220); body.TextWrapped=true
    body.Text = "..."
    J:connect(RunService.Heartbeat, function() -- update text occasionally
        local mv = tostring(MOVEMENT_MODE)
        local speed = tostring(TP_SPEED)
        local mode = (_G_IL_KILLED and "STOPPED" or (CONFIG.AUTO_ENABLED and "AUTO" or "PAUSE"))
        body.Text = string.format("FPS(avg): ~%.0f\nMode: %s | Move: %s@%s\nLogs (latest %d):\n%s", fps, mode, mv, speed, #Log.buf, Log:dump())
    end)
end
createMiniOverlay()

--== Respawn handling ==
LP.CharacterAdded:Connect(function(c)
    Char = c
    HRP = c:WaitForChild("HumanoidRootPart")
    task.delay(0.5, function() stopCultivate() end)
end)

-- Final log
Log:push("IL script loaded. MOVEMENT_MODE="..tostring(MOVEMENT_MODE).." TP_SPEED="..tostring(TP_SPEED))

-- Expose some useful helpers
_G.IL_JANITOR = J
_G.IL_LOG = Log
_G.IL_StopAll = StopAll
_G.IL_RescueNow = rescueNow
_G.IL_MoveTo = MoveTo
_G.IL_SAFE_SNAP = _safeSnap

-- Done
