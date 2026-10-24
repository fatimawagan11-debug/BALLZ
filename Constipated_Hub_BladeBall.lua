--[[
	Constipated Hub | Blade Ball  v2
	UI: Orion
	Safer parry: Keypress-first, cooldown aware, Blatant / Linear / Humanized
	ESP: chams, box, skeleton, health, names, tracers, ball
]]

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
GENV.__ConstipatedBladeGen = (GENV.__ConstipatedBladeGen or 0) + 1
local GEN = GENV.__ConstipatedBladeGen

local function alive()
	return GENV.__ConstipatedBladeGen == GEN
end

local OrionLib
do
	local urls = {
		"https://raw.githubusercontent.com/jensonhirst/Orion/main/source",
		"https://raw.githubusercontent.com/shlexware/Orion/main/source",
	}
	for _, u in ipairs(urls) do
		local ok, res = pcall(function()
			return loadstring(game:HttpGet(u))()
		end)
		if ok and res then
			OrionLib = res
			break
		end
	end
end
if not OrionLib then
	warn("[Constipated Hub] Orion failed")
	return
end

local CFG = {
	AutoParry = false,
	AutoSpam = false,
	Style = "Humanized",
	Method = "Keypress",

	ParryDistance = 16,
	SpamRange = 14,
	Prediction = 0.75,
	MinBallSpeed = 10,
	MaxBallDist = 140,
	PingComp = true,

	HumanMinDelay = 0.07,
	HumanMaxDelay = 0.16,
	HumanJitter = 0.03,
	RespectCooldown = true,

	EspChams = true,
	EspBox = true,
	EspSkeleton = true,
	EspHealth = true,
	EspNames = true,
	EspTracers = false,
	EspBall = true,
	EspMaxDist = 400,

	WalkSpeedOn = false,
	WalkSpeed = 18,
	InfJump = false,
	Noclip = false,
	AntiAFK = true,
}

local lastParry = 0
local nextAllowedParry = 0
local currentBall = nil
local parryCount = 0

local function getChar(p)
	return (p or LocalPlayer).Character
end

local function getHRP(ch)
	ch = ch or getChar()
	return ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso"))
end

local function getHum(ch)
	ch = ch or getChar()
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function isAlive(p)
	local ch = getChar(p)
	local hum = getHum(ch)
	return ch and hum and hum.Health > 0
end

local function getPing()
	if not CFG.PingComp then return 0 end
	local ok, v = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(v) == "number" then
		return math.clamp(v / 1000, 0, 0.2)
	end
	return 0.04
end

local function isParryOnCooldown()
	if not CFG.RespectCooldown then return false end
	local ok, cooling = pcall(function()
		local gui = LocalPlayer:FindFirstChild("PlayerGui")
		local hotbar = gui and gui:FindFirstChild("Hotbar")
		local block = hotbar and hotbar:FindFirstChild("Block")
		local grad = block and block:FindFirstChild("UIGradient")
		if not grad then return false end
		local off = grad.Offset
		if typeof(off) == "Vector2" and off.X > 0.05 and off.X < 0.95 then
			return true
		end
		return false
	end)
	return ok and cooling
end

local function resolveBallFolder()
	return Workspace:FindFirstChild("Balls") or Workspace:FindFirstChild("TrainingBalls")
end

local function findRealBall(folder)
	if not folder then return nil end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("realBall") == true then
			return child
		end
	end
	local best, bestSpeed
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local spd = child.AssemblyLinearVelocity.Magnitude
			if child:GetAttribute("target") ~= nil or spd > 5 then
				if not bestSpeed or spd > bestSpeed then
					bestSpeed = spd
					best = child
				end
			end
		end
	end
	return best
end

local function getBallVelocity(ball)
	if not ball then return Vector3.zero end
	local zoomies = ball:FindFirstChild("zoomies")
	if zoomies then
		if zoomies:IsA("BodyVelocity") then return zoomies.Velocity end
		if zoomies:IsA("LinearVelocity") then return zoomies.VectorVelocity end
	end
	return ball.AssemblyLinearVelocity
end

local function refreshBall()
	currentBall = findRealBall(resolveBallFolder())
	return currentBall
end

local function predictImpact(ballPos, ballVel, playerPos)
	local relative = ballPos - playerPos
	local speed = ballVel.Magnitude
	if speed < 0.01 then
		return relative.Magnitude, false, math.huge
	end
	local approaching = relative:Dot(ballVel) < 0
	local eta = relative.Magnitude / speed
	if approaching then
		local closing = -relative.Unit:Dot(ballVel)
		if closing > 0.5 then
			eta = relative.Magnitude / closing
		end
	end
	return relative.Magnitude, approaching, eta
end

local function styleDelay()
	if CFG.Style == "Blatant" then
		return 0.045
	elseif CFG.Style == "Linear" then
		return 0.08
	end
	return CFG.HumanMinDelay + math.random() * (CFG.HumanMaxDelay - CFG.HumanMinDelay)
end

local function fireKeypress()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
		task.wait(0.012 + math.random() * 0.01)
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
	end)
	pcall(function()
		if keypress and keyrelease then
			keypress(0x46)
			task.wait(0.015)
			keyrelease(0x46)
		end
	end)
end

local function fireRemote()
	pcall(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotes then return end
		for _, n in ipairs({ "ParryButtonPress", "ParryAttempt", "Parry" }) do
			local r = remotes:FindFirstChild(n)
			if r and r:IsA("RemoteEvent") then
				r:FireServer()
				return
			end
		end
	end)
end

local function fireParry(force)
	local now = os.clock()
	if not force then
		if now < nextAllowedParry then return false end
		if isParryOnCooldown() then return false end
	end

	local delay = styleDelay()
	if CFG.Style == "Humanized" then
		delay = delay + (math.random() - 0.5) * CFG.HumanJitter
	end
	nextAllowedParry = now + math.max(0.05, delay)
	lastParry = now
	parryCount = parryCount + 1

	if CFG.Method == "Keypress" then
		fireKeypress()
	elseif CFG.Method == "Remote" then
		fireRemote()
	else
		fireKeypress()
		if CFG.Style == "Blatant" or (parryCount % 5 == 0) then
			fireRemote()
		end
	end
	return true
end

local function autoParryStep()
	if not CFG.AutoParry then return end
	local root = getHRP()
	if not root then return end
	if not currentBall or not currentBall.Parent then
		refreshBall()
	end
	local ball = currentBall
	if not ball then return end

	local vel = getBallVelocity(ball)
	local speed = vel.Magnitude
	if speed < CFG.MinBallSpeed then return end

	local dist, approaching, eta = predictImpact(ball.Position, vel, root.Position)
	if dist > CFG.MaxBallDist then return end
	if not approaching and dist > CFG.ParryDistance * 0.6 then return end

	local ping = getPing()
	local pred = CFG.Prediction
	if CFG.Style == "Humanized" then
		pred = pred * (0.9 + math.random() * 0.2)
	elseif CFG.Style == "Blatant" then
		pred = math.min(1.1, pred + 0.15)
	end

	local threshold = styleDelay() * 0.5 + ping + (CFG.ParryDistance / math.max(speed, 1)) * pred

	if CFG.AutoSpam and dist <= CFG.SpamRange and approaching then
		fireParry(false)
		return
	end

	if (approaching and eta <= threshold) or dist <= CFG.ParryDistance then
		fireParry(false)
	end
end

-- ESP
local espFolder
local function ensureESPFolder()
	if espFolder and espFolder.Parent then return espFolder end
	local parent = (typeof(gethui) == "function" and gethui()) or CoreGui
	local old = parent:FindFirstChild("ConstipatedBladeESP")
	if old then old:Destroy() end
	espFolder = Instance.new("Folder")
	espFolder.Name = "ConstipatedBladeESP"
	espFolder.Parent = parent
	return espFolder
end

local function clearESP()
	if espFolder then espFolder:ClearAllChildren() end
end

local SKELETON_LINKS = {
	{ "Head", "UpperTorso" }, { "Head", "Torso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "UpperTorso", "RightUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" }, { "RightUpperArm", "RightLowerArm" },
	{ "LeftLowerArm", "LeftHand" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LowerTorso", "RightUpperLeg" },
	{ "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
	{ "LeftUpperLeg", "LeftLowerLeg" }, { "RightUpperLeg", "RightLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" }, { "RightLowerLeg", "RightFoot" },
}

local function makeHighlight(adornee, color)
	local h = Instance.new("Highlight")
	h.Adornee = adornee
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.55
	h.OutlineTransparency = 0.15
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = ensureESPFolder()
	return h
end

local function makeBillboard(adornee, text, color, y)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(140, 36)
	bb.StudsOffset = Vector3.new(0, y or 3.2, 0)
	bb.AlwaysOnTop = true
	bb.Parent = ensureESPFolder()
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Font = Enum.Font.GothamBold
	tl.TextSize = 12
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0.4
	tl.Text = text
	tl.Parent = bb
	return bb
end

local function makeSkeleton(ch, color)
	local folder = ensureESPFolder()
	for _, link in ipairs(SKELETON_LINKS) do
		local a = ch:FindFirstChild(link[1])
		local b = ch:FindFirstChild(link[2])
		if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
			local att0 = Instance.new("Attachment")
			att0.Parent = a
			local att1 = Instance.new("Attachment")
			att1.Parent = b
			local beam = Instance.new("Beam")
			beam.Attachment0 = att0
			beam.Attachment1 = att1
			beam.Width0 = 0.08
			beam.Width1 = 0.08
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(color)
			beam.Transparency = NumberSequence.new(0.25)
			beam.Parent = folder
		end
	end
end

local function healthColor(pct)
	if pct > 0.6 then return Color3.fromRGB(80, 255, 120) end
	if pct > 0.3 then return Color3.fromRGB(255, 200, 60) end
	return Color3.fromRGB(255, 70, 70)
end

local function refreshPlayerESP()
	clearESP()
	local myRoot = getHRP()
	if not myRoot then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isAlive(plr) then
			local ch = plr.Character
			local hrp = getHRP(ch)
			local hum = getHum(ch)
			if hrp and hum then
				local dist = (hrp.Position - myRoot.Position).Magnitude
				if not (CFG.EspMaxDist > 0 and dist > CFG.EspMaxDist) then
					local col = Color3.fromRGB(100, 180, 255)
					if CFG.EspChams or CFG.EspBox then
						makeHighlight(ch, col)
					end
					if CFG.EspSkeleton then
						makeSkeleton(ch, col)
					end
					local lines = {}
					if CFG.EspNames then table.insert(lines, plr.Name) end
					if CFG.EspHealth then
						local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						table.insert(lines, string.format("%.0f / %.0f", hum.Health, hum.MaxHealth))
						col = healthColor(pct)
					end
					if #lines > 0 then
						makeBillboard(hrp, table.concat(lines, "\n"), col, 3.4)
					end
				end
			end
		end
	end

	if CFG.EspBall and currentBall then
		makeHighlight(currentBall, Color3.fromRGB(255, 80, 80))
		local vel = getBallVelocity(currentBall)
		makeBillboard(currentBall, string.format("BALL  %.0f sps", vel.Magnitude), Color3.fromRGB(255, 220, 80), 2.5)
	end
end

local tracerLines = {}
local function clearTracers()
	for _, l in ipairs(tracerLines) do
		pcall(function() l:Remove() end)
	end
	table.clear(tracerLines)
end

local function updateTracers()
	clearTracers()
	if not CFG.EspTracers then return end
	if not (typeof(Drawing) == "table" or typeof(Drawing) == "userdata") then return end
	local myRoot = getHRP()
	if not myRoot then return end
	local from = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isAlive(plr) then
			local hrp = getHRP(plr.Character)
			if hrp then
				local sp, on = Camera:WorldToViewportPoint(hrp.Position)
				if on and sp.Z > 0 then
					local line = Drawing.new("Line")
					line.From = from
					line.To = Vector2.new(sp.X, sp.Y)
					line.Color = Color3.fromRGB(100, 180, 255)
					line.Thickness = 1
					line.Transparency = 0.4
					line.Visible = true
					table.insert(tracerLines, line)
				end
			end
		end
	end
end

RunService.Stepped:Connect(function()
	if not alive() or not CFG.Noclip then return end
	local c = getChar()
	if c then
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	if not alive() then return end
	local hum = getHum()
	if hum and CFG.WalkSpeedOn then
		hum.WalkSpeed = CFG.WalkSpeed
	end
end)

UserInputService.JumpRequest:Connect(function()
	if CFG.InfJump and alive() then
		local hum = getHum()
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

LocalPlayer.Idled:Connect(function()
	if CFG.AntiAFK then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end
end)

task.spawn(function()
	while alive() do
		refreshBall()
		pcall(autoParryStep)
		if CFG.Style == "Blatant" then
			task.wait()
		elseif CFG.Style == "Linear" then
			task.wait(0.02)
		else
			task.wait(0.03 + math.random() * 0.025)
		end
	end
end)

task.spawn(function()
	while alive() do
		if CFG.EspChams or CFG.EspBox or CFG.EspSkeleton or CFG.EspHealth or CFG.EspNames or CFG.EspBall then
			pcall(refreshPlayerESP)
		else
			clearESP()
		end
		pcall(updateTracers)
		task.wait(0.55)
	end
	clearESP()
	clearTracers()
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Balls" or child.Name == "TrainingBalls" then
		task.wait(0.15)
		refreshBall()
	end
end)

local Window = OrionLib:MakeWindow({
	Name = "Constipated Hub | Blade Ball",
	HidePremium = true,
	SaveConfig = false,
	IntroEnabled = false,
})

local TabParry = Window:MakeTab({ Name = "Parry", Icon = "rbxassetid://4483362748", PremiumOnly = false })
local TabESP = Window:MakeTab({ Name = "ESP", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local TabPlayer = Window:MakeTab({ Name = "Player", Icon = "rbxassetid://4483342657", PremiumOnly = false })
local TabMisc = Window:MakeTab({ Name = "Misc", Icon = "rbxassetid://4483362458", PremiumOnly = false })

TabParry:AddToggle({
	Name = "Auto Parry",
	Default = false,
	Callback = function(v)
		CFG.AutoParry = v
		OrionLib:MakeNotification({
			Name = "Constipated Hub",
			Content = v and ("Auto Parry ON · " .. CFG.Style) or "Auto Parry OFF",
			Time = 2,
		})
	end,
})

TabParry:AddToggle({
	Name = "Auto Spam (close)",
	Default = false,
	Callback = function(v) CFG.AutoSpam = v end,
})

TabParry:AddDropdown({
	Name = "Parry Style",
	Default = "Humanized",
	Options = { "Humanized", "Linear", "Blatant" },
	Callback = function(v) CFG.Style = v end,
})

TabParry:AddDropdown({
	Name = "Parry Method (Keypress = safer)",
	Default = "Keypress",
	Options = { "Keypress", "Remote", "Both" },
	Callback = function(v) CFG.Method = v end,
})

TabParry:AddToggle({
	Name = "Respect Parry Cooldown UI",
	Default = true,
	Callback = function(v) CFG.RespectCooldown = v end,
})

TabParry:AddSlider({
	Name = "Parry Distance",
	Min = 8, Max = 28, Default = 16, Increment = 1,
	Callback = function(v) CFG.ParryDistance = v end,
})

TabParry:AddSlider({
	Name = "Spam Range",
	Min = 6, Max = 28, Default = 14, Increment = 1,
	Callback = function(v) CFG.SpamRange = v end,
})

TabParry:AddSlider({
	Name = "Prediction",
	Min = 0.4, Max = 1.1, Default = 0.75, Increment = 0.05,
	Callback = function(v) CFG.Prediction = v end,
})

TabParry:AddSlider({
	Name = "Min Ball Speed",
	Min = 0, Max = 40, Default = 10, Increment = 1,
	Callback = function(v) CFG.MinBallSpeed = v end,
})

TabParry:AddToggle({
	Name = "Ping Compensation",
	Default = true,
	Callback = function(v) CFG.PingComp = v end,
})

TabParry:AddButton({
	Name = "Manual Parry",
	Callback = function() fireParry(true) end,
})

TabESP:AddToggle({ Name = "Chams", Default = true, Callback = function(v) CFG.EspChams = v end })
TabESP:AddToggle({ Name = "Box / Highlight", Default = true, Callback = function(v) CFG.EspBox = v end })
TabESP:AddToggle({ Name = "Skeleton", Default = true, Callback = function(v) CFG.EspSkeleton = v end })
TabESP:AddToggle({ Name = "Health", Default = true, Callback = function(v) CFG.EspHealth = v end })
TabESP:AddToggle({ Name = "Names", Default = true, Callback = function(v) CFG.EspNames = v end })
TabESP:AddToggle({
	Name = "Tracers",
	Default = false,
	Callback = function(v)
		CFG.EspTracers = v
		if not v then clearTracers() end
	end,
})
TabESP:AddToggle({ Name = "Ball ESP", Default = true, Callback = function(v) CFG.EspBall = v end })
TabESP:AddSlider({
	Name = "Max ESP Distance",
	Min = 100, Max = 1000, Default = 400, Increment = 25,
	Callback = function(v) CFG.EspMaxDist = v end,
})

TabPlayer:AddToggle({ Name = "WalkSpeed", Default = false, Callback = function(v) CFG.WalkSpeedOn = v end })
TabPlayer:AddSlider({
	Name = "WalkSpeed Value",
	Min = 16, Max = 28, Default = 18, Increment = 1,
	Callback = function(v) CFG.WalkSpeed = v end,
})
TabPlayer:AddToggle({ Name = "Infinite Jump", Default = false, Callback = function(v) CFG.InfJump = v end })
TabPlayer:AddToggle({ Name = "Noclip", Default = false, Callback = function(v) CFG.Noclip = v end })

TabMisc:AddToggle({
	Name = "Fullbright",
	Default = false,
	Callback = function(v)
		if v then
			Lighting.Brightness = 2
			Lighting.ClockTime = 14
			Lighting.FogEnd = 1e6
			Lighting.GlobalShadows = false
		else
			Lighting.Brightness = 1
			Lighting.GlobalShadows = true
		end
	end,
})
TabMisc:AddToggle({ Name = "Anti AFK", Default = true, Callback = function(v) CFG.AntiAFK = v end })
TabMisc:AddButton({
	Name = "Unload Hub",
	Callback = function()
		GENV.__ConstipatedBladeGen = GEN + 1
		clearESP()
		clearTracers()
		pcall(function() OrionLib:Destroy() end)
	end,
})
TabMisc:AddParagraph(
	"Anti-kick tips",
	"Style=Humanized + Method=Keypress\nRespect Cooldown ON\nAvoid Blatant + Remote spam"
)

OrionLib:MakeNotification({
	Name = "Constipated Hub",
	Content = "Blade Ball v2 — Humanized + Keypress default",
	Time = 4,
})

print("[Constipated Hub] Blade Ball v2 ready")
