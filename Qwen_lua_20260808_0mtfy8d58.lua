--[[
LINKED SWORD AI 2 - IMPROVED COMBAT / A* / CACHE
Full integrated version.
]]

local CONFIG = {
	DETECTION_RADIUS = 200,
	ALLOW_HEALING = true,
	HEALING_BELOW_HEALTH = 50,
	IMMEDIATE_ATTACK_RADIUS = 14,
	SWORD_NAME = "Sword",
	DIST_SWING = 5,
	CHARGE_NO_JUMP_DIST = 6,
	START_COMBAT = 40,
	NODEWALK_SPEED = 50,
	PATHFIND_SPEED = 100,
	PREDICT_PLAYER_HIT = 0.175,
	PREDICT_PLAYER_DIST = 12,
	USE_PREDEFS_ON_NOPATH = false,
	PATCH_HUMANOID_MOVE_QUIRKS = true,
	CURRENT_DIFFICULTY = "EASY",
	DEBUG = true,
	DEBUG_NODEWALKER = true,
	DEBUG_PATHFIND_OPEN = true,
	AGGRESSIVE_MODE = true,
	TALKING = true,
	GRAB_TOOL_MESHES = true,

	-- Improved combat
	MAX_SWING_COOLDOWN = 0.24,
	PREDICT_PING_FACTOR = 0.55,
	PREDICT_MAX_SPEED = 34,
	DODGE_RANGE = 7,

	-- Improved cache
	TARGET_CACHE_TTL = 0.10,
	GROUND_CACHE_TTL = 0.12,
	NODE_COST_TTL = 0.8,
	PATH_CACHE_TTL = 1.2,
	PATH_CACHE_MAX = 96,

	-- Improved A*
	PATH_MAX_EXPANSIONS = 1800,
}

if not replicatesignal then
	replicatesignal = function(sig)
		warn("replicatesignal not supported on this executor")
	end
end

local dynamicSwordName = CONFIG.SWORD_NAME

local CARDINALS = {
	Vector3.xAxis,
	Vector3.zAxis,
	-Vector3.xAxis,
	-Vector3.zAxis,
	Vector3.new(1, 0, 1),
	Vector3.new(-1, 0, 1),
	Vector3.new(-1, 0, -1),
	Vector3.new(1, 0, -1),
}

local VEC3XZ = Vector3.new(1, 0, 1)
local HUM_STATES_SHIFTLOCK = {"Running", "Jumping", "Freefall", "Landed", "Climbing"}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ChatService = game:GetService("Chat")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Player = Players.LocalPlayer

-- PC tier GUI
local function ApplyPCTier(tier)
	if tier == "WEAK" then
		CONFIG.PATHFIND_SPEED = 50
		CONFIG.NODEWALK_SPEED = 20
		CONFIG.DEBUG = false
		CONFIG.DEBUG_NODEWALKER = false
		CONFIG.DEBUG_PATHFIND_OPEN = false
	else
		CONFIG.PATHFIND_SPEED = 200
		CONFIG.NODEWALK_SPEED = 50
		CONFIG.DEBUG = true
		CONFIG.DEBUG_NODEWALKER = true
		CONFIG.DEBUG_PATHFIND_OPEN = true
	end
end

pcall(function()
	local PlayerGui = Player:WaitForChild("PlayerGui")

	local ToggleGui = Instance.new("ScreenGui")
	ToggleGui.Name = "PCTierToggleGui"
	ToggleGui.Parent = PlayerGui
	ToggleGui.ResetOnSpawn = false

	local MainFrame = Instance.new("Frame")
	MainFrame.Size = UDim2.new(0, 130, 0, 70)
	MainFrame.Position = UDim2.new(0, 10, 0.5, -35)
	MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	MainFrame.BorderSizePixel = 0
	MainFrame.Parent = ToggleGui

	local UICorner = Instance.new("UICorner")
	UICorner.CornerRadius = UDim.new(0, 8)
	UICorner.Parent = MainFrame

	local Title = Instance.new("TextLabel")
	Title.Size = UDim2.new(1, 0, 0, 20)
	Title.BackgroundTransparency = 1
	Title.Text = "PC TIER"
	Title.TextColor3 = Color3.new(1, 1, 1)
	Title.Font = Enum.Font.GothamBold
	Title.TextSize = 14
	Title.Parent = MainFrame

	local BeefyBtn = Instance.new("TextButton")
	BeefyBtn.Size = UDim2.new(0.45, 0, 0, 35)
	BeefyBtn.Position = UDim2.new(0.05, 0, 0, 30)
	BeefyBtn.Text = "Beefy"
	BeefyBtn.TextColor3 = Color3.new(1, 1, 1)
	BeefyBtn.Font = Enum.Font.GothamBold
	BeefyBtn.TextSize = 12
	BeefyBtn.Parent = MainFrame

	local b1Corner = Instance.new("UICorner")
	b1Corner.CornerRadius = UDim.new(0, 6)
	b1Corner.Parent = BeefyBtn

	local WeakBtn = Instance.new("TextButton")
	WeakBtn.Size = UDim2.new(0.45, 0, 0, 35)
	WeakBtn.Position = UDim2.new(0.5, 0, 0, 30)
	WeakBtn.Text = "Non-Beefy"
	WeakBtn.TextColor3 = Color3.new(1, 1, 1)
	WeakBtn.Font = Enum.Font.GothamBold
	WeakBtn.TextSize = 12
	WeakBtn.Parent = MainFrame

	local b2Corner = Instance.new("UICorner")
	b2Corner.CornerRadius = UDim.new(0, 6)
	b2Corner.Parent = WeakBtn

	local function UpdateGuiColors()
		if CONFIG.PATHFIND_SPEED > 50 then
			BeefyBtn.BackgroundColor3 = Color3.fromRGB(45, 100, 45)
			WeakBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		else
			BeefyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			WeakBtn.BackgroundColor3 = Color3.fromRGB(100, 80, 40)
		end
	end

	BeefyBtn.MouseButton1Click:Connect(function()
		ApplyPCTier("BEEFY")
		UpdateGuiColors()
	end)

	WeakBtn.MouseButton1Click:Connect(function()
		ApplyPCTier("WEAK")
		UpdateGuiColors()
	end)

	ApplyPCTier("BEEFY")
	UpdateGuiColors()
end)

-- FPS tracker
local currentFPS = 60
local fpsCounter = 0
local fpsTimer = 0

RunService.Heartbeat:Connect(function(dt)
	fpsCounter += 1
	fpsTimer += dt

	if fpsTimer >= 1 then
		currentFPS = fpsCounter
		fpsCounter = 0
		fpsTimer = 0
	end
end)

-- Bubble chat
local function SayBubble(message, color)
	if not CONFIG.TALKING then
		return
	end

	task.spawn(function()
		local char = Player.Character
		if char then
			local head = char:FindFirstChild("Head")
			if head then
				ChatService:Chat(head, message, color or Enum.ChatColor.White)
			end
		end
	end)
end

local function GetMessages(state)
	if CONFIG.AGGRESSIVE_MODE then
		if state == "IDLE" then
			return {"Stop hiding cowards.", "Come out and fight!", "Where are you?", "Don't be scared."}
		elseif state == "WALKING" then
			return {"DUDE I NEED AN OPPONENT", "Looking for someone to destroy.", "Hurry up and fight me.", "Wandering for blood."}
		elseif state == "PURSUING" then
			return {"You can't run!", "Stop running coward!", "I'm coming for you!", "Get back here!"}
		elseif state == "COMBAT" then
			return {"You're dead!", "Get destroyed!", "Don't even try."}
		elseif state == "CHARGING" then
			return {"I'm gonna end you!", "Get recked!", "Say goodbye!"}
		elseif state == "WON" then
			return {"L!", "You're a loser!", "Get good kid!", "Trash!"}
		elseif state == "DEAD" then
			return {"THIS IS BS!", "YOU HACK!", "I WAS LAGGING!", "BULLSH*T!", "I LET YOU WIN!"}
		elseif state == "RESETTING" then
			return {"Brb destroying my PC.", "Gotta reset.", "I'll be back for revenge."}
		end
	else
		if state == "IDLE" then
			return {"Uhh, let's wait.", "I don't see anyone...", "Hello?? GUYS?!", "Where is everyone?", "Is anyone there?"}
		elseif state == "WALKING" then
			return {"I'll explore this.", "Let me walk somewhere.", "Heading this way.", "Wandering off."}
		elseif state == "PURSUING" then
			return {"Chasing target!", "Running!", "After him!", "He can't escape!"}
		elseif state == "COMBAT" then
			return {"Engaging!", "Fighting now!", "Let's fight!"}
		elseif state == "CHARGING" then
			return {"I'm charging!", "Get ready!", "Here I come!", "Take this!"}
		elseif state == "WON" then
			return {"Good fight!", "I won!", "GG!"}
		elseif state == "DEAD" then
			return {"Damn it!", "I lost!", "How?!", "You got lucky!", "That was BS!", "Ouch!"}
		elseif state == "RESETTING" then
			return {"I gotta reset!", "Reset time!", "Ugh, I'm stuck.", "Time to reset."}
		end
	end

	return {}
end

local ChatState = "NONE"
local LagTimer = 0

local function ChangeChatState(newState, customMessages, color)
	if not CONFIG.TALKING then
		return
	end

	if ChatState ~= newState then
		ChatState = newState

		local messages = customMessages or GetMessages(newState)
		if messages and #messages > 0 then
			SayBubble(messages[math.random(#messages)], color or Enum.ChatColor.White)
		end
	end
end

local function GetTool(char, back, name)
	if char and back then
		for _, v in char:GetChildren() do
			if v:IsA("Tool") then
				local lowerName = string.lower(v.Name)
				if lowerName == "linkedsword" or string.find(lowerName, "sword") or v.Name == name then
					return v
				end
			end
		end

		for _, v in back:GetChildren() do
			if v:IsA("Tool") then
				local lowerName = string.lower(v.Name)
				if lowerName == "linkedsword" or string.find(lowerName, "sword") or v.Name == name then
					return v
				end
			end
		end
	end

	return nil
end

-- Debug visuals
local DebugPart = Instance.new("Part")
DebugPart.Anchored = true
DebugPart.CanCollide = false
DebugPart.CanQuery = false
DebugPart.CanTouch = false
DebugPart.Transparency = 1
DebugPart.Size = Vector3.one
DebugPart.Name = "wireframe_debugging"
DebugPart.Parent = workspace.Terrain
DebugPart.CFrame = CFrame.identity

local DebugWireframe = Instance.new("WireframeHandleAdornment")
DebugWireframe.Color3 = Color3.new(1, 1, 1)
DebugWireframe.Adornee = DebugPart
DebugWireframe.AlwaysOnTop = true
DebugWireframe.Parent = DebugPart

local DebugNodewalker = Instance.new("WireframeHandleAdornment")
DebugNodewalker.Color3 = Color3.new(1, 0, 1)
DebugNodewalker.Adornee = DebugPart
DebugNodewalker.AlwaysOnTop = true
DebugNodewalker.Parent = DebugPart

local DebugPathfinder = Instance.new("WireframeHandleAdornment")
DebugPathfinder.Color3 = Color3.new(0.7, 0.7, 0)
DebugPathfinder.Adornee = DebugPart
DebugPathfinder.AlwaysOnTop = true
DebugPathfinder.Parent = DebugPart

local DebugController = Instance.new("WireframeHandleAdornment")
DebugController.Color3 = Color3.new(0, 1, 0)
DebugController.Adornee = DebugPart
DebugController.AlwaysOnTop = true
DebugController.Parent = DebugPart

local DebugBrain = Instance.new("WireframeHandleAdornment")
DebugBrain.Color3 = Color3.new(0, 0.5, 1)
DebugBrain.Adornee = DebugPart
DebugBrain.AlwaysOnTop = true
DebugBrain.Parent = DebugPart

local ToolMeshHighlight = Instance.new("Highlight")
if ToolMeshHighlight then
	ToolMeshHighlight.Name = "ToolMeshHighlight"
	ToolMeshHighlight.FillColor = Color3.fromRGB(0, 255, 0)
	ToolMeshHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	ToolMeshHighlight.FillTransparency = 0.5
	ToolMeshHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	ToolMeshHighlight.Enabled = false
	ToolMeshHighlight.Parent = workspace.Terrain
end

local function DebugClear(wf)
	if not CONFIG.DEBUG then
		return
	end
	wf:Clear()
end

local function CreateDot(wf, pos)
	if not CONFIG.DEBUG then
		return
	end

	local p = {}
	local seg = 8
	local r = 0.4 + math.sin(os.clock() * 2 + (pos.X + pos.Y + pos.Z) * 0.2) * 0.2

	for i = 1, seg do
		local a = (i / seg) * math.pi * 2
		p[#p + 1] = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end

	wf:AddPath(p, true)
end

local function CreateCircle(wf, pos, r)
	if not CONFIG.DEBUG then
		return
	end

	local p = {}
	local seg = math.min(6 + math.floor(r / 4), 32)

	for i = 1, seg do
		local a = (i / seg) * math.pi * 2
		p[#p + 1] = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end

	wf:AddPath(p, true)
end

local function CreateLocator(wf, pos)
	if not CONFIG.DEBUG then
		return
	end

	local seg = 8
	local h = 0.25 + math.sin(os.clock() * 2) * 0.25
	pos += Vector3.yAxis * h

	for i = 1, seg do
		local a = (i / seg) * math.pi * 2
		local b = ((i + 1) / seg) * math.pi * 2

		wf:AddLine(
			pos + Vector3.new(math.cos(a) * 0.5, 1, math.sin(a) * 0.5),
			pos + Vector3.new(math.cos(b) * 0.5, 1, math.sin(b) * 0.5)
		)

		wf:AddLine(
			pos + Vector3.new(math.cos(a) * 0.5, 1, math.sin(a) * 0.5),
			pos
		)
	end
end

local function CreateLine(wf, a, b)
	if not CONFIG.DEBUG then
		return
	end
	wf:AddLine(a, b)
end

local function CreateText(wf, pos, txt)
	if not CONFIG.DEBUG then
		return
	end
	wf:AddText(pos, txt, 10)
end

local DebugLines = {
	"LINKED SWORD AI IMPROVED",
	"PATHFINDER ... WAITING FOR CALLS",
	"CONTROLLER - SWORD ... LOADING",
	"             MOVE METHOD ... LOADING",
	"             JUMP ... LOADING",
	"BRAIN - STATE ... LOADING",
	"        PLAYSTYLE ... LOADING",
	"        CHARGING ... LOADING",
	"NO PREDEF ACTS RAN YET",
	"",
}

RunService.PreRender:Connect(function()
	if not workspace.CurrentCamera then
		return
	end

	DebugWireframe:Clear()
	DebugWireframe:AddText(workspace.CurrentCamera.Focus.Position, table.concat(DebugLines, "\n"), 10)
end)

task.wait(0.5)

-- Character tracking / anti-fling
local Characters = {}
local CharactersFF = {}

do
	local AntiflingHumanoids = {}
	local AntiflingBaseParts = {}

	RunService.PreAnimation:Connect(function()
		for i = #Characters, 1, -1 do
			local v = Characters[i]

			if not v:IsDescendantOf(workspace) then
				table.remove(Characters, i)

				local j = table.find(CharactersFF, v)
				if j then
					table.remove(CharactersFF, j)
				end
			else
				if v:FindFirstChildOfClass("ForceField") then
					if not table.find(CharactersFF, v) then
						table.insert(CharactersFF, v)
					end
				else
					local j = table.find(CharactersFF, v)
					if j then
						table.remove(CharactersFF, j)
					end
				end
			end
		end

		for i = #AntiflingBaseParts, 1, -1 do
			local v = AntiflingBaseParts[i]
			if v:IsDescendantOf(workspace) then
				v.CanCollide = false
			else
				table.remove(AntiflingBaseParts, i)
			end
		end

		for i = #AntiflingHumanoids, 1, -1 do
			local v = AntiflingHumanoids[i]
			if v:IsDescendantOf(workspace) then
				v.EvaluateStateMachine = false
			else
				table.remove(AntiflingHumanoids, i)
			end
		end
	end)

	local function OnBasePart(v)
		if v:IsA("BasePart") then
			v.CanCollide = false
			if not table.find(AntiflingBaseParts, v) then
				table.insert(AntiflingBaseParts, v)
			end
		end

		if v:IsA("Humanoid") then
			v.EvaluateStateMachine = false
			if not table.find(AntiflingHumanoids, v) then
				table.insert(AntiflingHumanoids, v)
			end
		end
	end

	local function OnCharacter(character)
		table.insert(Characters, character)
		character.DescendantAdded:Connect(OnBasePart)

		for _, v in character:GetDescendants() do
			OnBasePart(v)
		end
	end

	local function OnPlayer(player)
		if player == Player then
			player.CharacterAdded:Connect(function(character)
				table.insert(Characters, character)
			end)

			if player.Character then
				table.insert(Characters, player.Character)
			end

			return
		end

		player.CharacterAdded:Connect(OnCharacter)

		if player.Character then
			OnCharacter(player.Character)
		end
	end

	Players.PlayerAdded:Connect(OnPlayer)

	for _, player in Players:GetPlayers() do
		OnPlayer(player)
	end
end

local function IsSafe(value)
	if not value then
		return false
	end

	if value ~= value then
		return false
	end

	if typeof(value) == "Vector3" then
		if value.Magnitude > 65536 then
			return false
		end
	end

	return true
end

local CollideForcers = {}

for _, v in workspace:GetChildren() do
	if v.Name == "PhantomPlate" and v:IsA("BasePart") then
		local w = v:Clone()
		w.Parent = v
		w.Name ..= "_CollideCopy"
		w.CanCollide = true
		w.Transparency = 1
		table.insert(CollideForcers, w)
	end
end

local RCP = RaycastParams.new()
RCP.FilterType = Enum.RaycastFilterType.Exclude
RCP.RespectCanCollide = true
RCP.IgnoreWater = true

local OVP = OverlapParams.new()
OVP.FilterType = Enum.RaycastFilterType.Exclude
OVP.RespectCanCollide = true

RunService.PreAnimation:Connect(function()
	RCP.FilterDescendantsInstances = Characters
	OVP.FilterDescendantsInstances = Characters
end)

local function PhysicsRaycast(origin, direction)
	return workspace:Raycast(origin, direction, RCP)
end

local function PhysicsBoxcast(origin, size, direction)
	return workspace:Blockcast(CFrame.new(origin), size, direction, RCP)
end

local function PhysicsSpherecast(origin, radius, direction)
	return workspace:Spherecast(origin, radius, direction, RCP)
end

local function PhysicsGetPartBoundsInBox(cf, size)
	return workspace:GetPartBoundsInBox(cf, size, OVP)
end

local function PhysicsCheckArea(cf, size)
	return #PhysicsGetPartBoundsInBox(cf, size) > 0
end

local function PhysicsCheckLine(origin, boxsize, direction)
	if direction.Magnitude < 0.01 then
		return false
	end

	local cf = CFrame.lookAlong(origin, direction) * CFrame.new(0, 0, -direction.Magnitude / 2)
	local size = Vector3.new(boxsize * 2, boxsize * 2, direction.Magnitude)

	return #PhysicsGetPartBoundsInBox(cf, size) > 0
end

-- General TTL cache
local PathCacheVersion = 0

local Cache = {
	store = {},
	count = 0,
}

local function CacheClearExpired()
	local now = os.clock()

	for key, entry in next, Cache.store do
		if now - entry.t > entry.ttl then
			Cache.store[key] = nil
			Cache.count -= 1
		end
	end
end

local function CacheGet(key, ttl, makeFunction)
	local entry = Cache.store[key]
	local now = os.clock()

	if entry then
		if now - entry.t <= entry.ttl then
			return entry.v
		end

		Cache.store[key] = nil
		Cache.count -= 1
	end

	if not makeFunction then
		return nil
	end

	local value = makeFunction()

	if value ~= nil then
		Cache.store[key] = {
			v = value,
			t = now,
			ttl = ttl,
		}

		Cache.count += 1

		if Cache.count > 5000 then
			CacheClearExpired()
		end
	end

	return value
end

local function CacheSet(key, value, ttl)
	if not Cache.store[key] then
		Cache.count += 1
	end

	Cache.store[key] = {
		v = value,
		t = os.clock(),
		ttl = ttl,
	}
end

local function QuantizeVec3(v, step)
	return Vector3.new(
		math.floor(v.X / step) * step,
		math.floor(v.Y / step) * step,
		math.floor(v.Z / step) * step
	)
end

local function GetPathCacheKey(start, goal)
	local s = QuantizeVec3(start, 2)
	local g = QuantizeVec3(goal, 2)

	return string.format(
		"PATH:%.0f:%.0f:%.0f|%.0f:%.0f:%.0f|v%d",
		s.X, s.Y, s.Z,
		g.X, g.Y, g.Z,
		PathCacheVersion
	)
end

local function EnsureGround(position, downwarped)
	local radius = 1.1
	local direction = Vector3.new(0, -5, 0)

	if downwarped then
		direction *= 100
	end

	position += Vector3.new(0, 0.2 + radius, 0)

	local cast = PhysicsSpherecast(position, radius, direction)
	if cast then
		return position + direction.Unit * (cast.Distance + radius), cast.Instance
	end

	return nil
end

local function EnsureGroundRay(position, downwarped)
	local direction = Vector3.new(0, -6, 0)

	if downwarped then
		direction *= 100
	end

	position += Vector3.new(0, 1, 0)

	local cast = PhysicsRaycast(position, direction)
	if cast then
		return cast.Position, cast.Instance
	end

	return nil
end

local function CheckGround(pos, dir)
	return PhysicsCheckLine(pos, 0.6, dir or Vector3.new(0, -5, 0))
end

local function CheckGroundCached(pos, dir)
	dir = dir or Vector3.new(0, -5, 0)

	local key = string.format(
		"CG:%.1f:%.1f:%.1f:%.1f:%.1f:%.1f",
		pos.X, pos.Y, pos.Z,
		dir.X, dir.Y, dir.Z
	)

	return CacheGet(key, CONFIG.GROUND_CACHE_TTL, function()
		return CheckGround(pos, dir)
	end)
end

local function CheckWalkable(a, b)
	a = EnsureGround(a)
	if not a then
		return false
	end

	b = EnsureGround(b)
	if not b then
		return false
	end

	if math.abs(a.Y - b.Y) > 1.5 then
		return false
	end

	local diff = b - a
	if diff == Vector3.zero then
		return true
	end

	local dist = diff.Magnitude
	if dist > 50 then
		return false
	end

	if not CheckGround(b) then
		return false
	end

	if PhysicsCheckLine(a + Vector3.new(0, 3, 0), 1.2, diff) then
		return false
	end

	local dir = diff.Unit
	local step = 2

	for i = 0, dist, step do
		if not CheckGround(a + dir * i) then
			return false
		end
	end

	return true
end

local function IsTruss(part)
	if not part then
		return false
	end

	if part:IsA("TrussPart") then
		return true
	end

	local name = string.lower(part.Name)
	if string.find(name, "truss") or string.find(name, "climb") or string.find(name, "ladder") then
		return true
	end

	return false
end

local function GetNearestToolMesh(pos)
	local meshesFolder = workspace:FindFirstChild("Tool Meshes")
	if not meshesFolder then
		return nil, nil
	end

	local nearestPart = nil
	local nearestDist = math.huge

	for _, part in ipairs(meshesFolder:GetDescendants()) do
		if part:IsA("BasePart") then
			local dist = ((part.Position - pos) * VEC3XZ).Magnitude

			if dist < nearestDist then
				nearestDist = dist
				nearestPart = part
			end
		end
	end

	if nearestPart then
		return nearestPart, nearestPart.Position
	end

	return nil, nil
end

local function GetNearestHealingPad(pos)
	local padsFolder = workspace:FindFirstChild("Healing Pads")
	if not padsFolder then
		return nil, math.huge
	end

	local nearestPad = nil
	local nearestDist = math.huge

	for _, part in ipairs(padsFolder:GetDescendants()) do
		if part:IsA("BasePart") and part:FindFirstChild("TouchInterest") then
			local dist = ((part.Position - pos) * VEC3XZ).Magnitude

			if dist < nearestDist then
				nearestDist = dist
				nearestPad = part
			end
		end
	end

	return nearestPad, nearestDist
end

-- AI node graph
local AINodes = {}
local AINodesMap = {}
local AINodesDyn = {}
local AINodesCount = 0
local AINodesDynCount = 0

local function SnapToGrid(pos)
	return Vector3.new(
		math.floor(pos.X) + 0.5,
		pos.Y,
		math.floor(pos.Z) + 0.5
	)
end

local GetNodeCost_cache = {}

local function GetNodeCost(node)
	local now = os.clock()
	local entry = GetNodeCost_cache[node]

	local ttl = CONFIG.NODE_COST_TTL
	if node.Dynamic then
		ttl = 0.25
	end

	if entry and now - entry.t < ttl then
		return entry.cost
	end

	local cost = 1

	local result = PhysicsRaycast(node.Position, Vector3.new(0, -5, 0))
	if result then
		if result.Instance.Transparency > 0 then
			cost = 20
		end
	else
		cost = 600
	end

	result = PhysicsRaycast(node.Position, Vector3.new(0, 6, 0))
	if result then
		cost /= math.max(0.01, result.Distance / 6)
	end

	GetNodeCost_cache[node] = {
		cost = cost,
		t = now,
	}

	return cost
end

local function GetDistance(a, b)
	return ((b.Position - a.Position) * VEC3XZ).Magnitude
end

local function NodesAreVeryNear(a, b)
	if not table.find(a.Nearby, b) then
		table.insert(a.Nearby, b)
	end

	if not table.find(b.Nearby, a) then
		table.insert(b.Nearby, a)
	end
end

local function EnsureNodesLinked(a, b)
	if not table.find(a.Links, b) then
		table.insert(a.Links, b)
	end

	if not table.find(b.BackLinks, a) then
		table.insert(b.BackLinks, a)
	end
end

local function BreakLinks(a, b)
	local i = table.find(a.Links, b)
	if i then
		table.remove(a.Links, i)
	end

	i = table.find(b.Links, a)
	if i then
		table.remove(b.Links, i)
	end

	i = table.find(a.BackLinks, b)
	if i then
		table.remove(a.BackLinks, i)
	end

	i = table.find(b.BackLinks, a)
	if i then
		table.remove(b.BackLinks, i)
	end
end

local function BreakAllLinks(node)
	for _, v in node.Links do
		BreakLinks(node, v)
	end

	for _, v in node.BackLinks do
		BreakLinks(node, v)
	end
end

local function HasNodeInXZ(x, z)
	x, z = math.floor(x), math.floor(z)

	if not AINodes[x] then
		return false
	end

	if not AINodes[x][z] then
		return false
	end

	return true
end

local function GetNode(pos)
	local fx, fz = math.floor(pos.X), math.floor(pos.Z)

	if not AINodes[fx] then
		AINodes[fx] = {}
	end

	if not AINodes[fx][fz] then
		AINodes[fx][fz] = {}
	end

	local y = math.floor(pos.Y)

	if not AINodes[fx][fz][y] then
		local node2 = {}

		AINodes[fx][fz][y] = node2

		node2.Explored = false
		node2.Known = false
		node2.Dynamic = true
		node2.Links = {}
		node2.BackLinks = {}
		node2.Index = #AINodesMap + 1
		node2.Nearby = {}

		pos = SnapToGrid(pos)

		for x = fx - 4, fx + 4 do
			for z = fz - 4, fz + 4 do
				if x == fx and z == fz then
					continue
				end

				if HasNodeInXZ(x, z) then
					for _, node3 in pairs(AINodes[x][z]) do
						NodesAreVeryNear(node2, node3)
					end
				end
			end
		end

		local groundY = y
		local poz, ground = EnsureGroundRay(pos)

		if poz then
			groundY = poz.Y + 0.5

			if ground and ground:IsA("BasePart") and ground:IsGrounded() then
				node2.Dynamic = false
			end
		end

		node2.YLevel = pos.Y
		node2.Position = Vector3.new(pos.X, groundY, pos.Z)
		node2.Ground = ground

		table.insert(AINodesMap, node2)
		AINodesCount += 1

		if node2.Dynamic then
			table.insert(AINodesDyn, node2)
			AINodesDynCount += 1
		end
	end

	return AINodes[fx][fz][y]
end

local function ClosestNode(pos)
	local best = nil
	local bestD = 20

	local fx = math.floor(pos.X)
	local fz = math.floor(pos.Z)

	for radius = 0, 5 do
		for x = fx - radius, fx + radius do
			for z = fz - radius, fz + radius do
				if math.max(math.abs(x - fx), math.abs(z - fz)) == radius then
					local xLayer = AINodes[x]
					local zLayer = xLayer and xLayer[z]

					if zLayer then
						for _, node in pairs(zLayer) do
							local d = (pos - node.Position).Magnitude

							if d < bestD then
								bestD = d
								best = node
							end
						end
					end
				end
			end
		end

		if best and bestD <= radius + 2 then
			break
		end
	end

	if best then
		return best
	end

	for _, node in ipairs(AINodesMap) do
		local d = (pos - node.Position).Magnitude

		if d < bestD then
			bestD = d
			best = node
		end
	end

	return best
end

local function IsNodeValid(pos)
	if not pos then
		return false
	end

	pos = SnapToGrid(pos)

	if PhysicsCheckArea(CFrame.new(pos + Vector3.new(0, 2.5, 0)), Vector3.new(2, 1, 2)) then
		return false
	end

	if PhysicsCheckArea(CFrame.new(pos + Vector3.new(0, -0.5, 0)), Vector3.new(0.8, 1, 0.8)) then
		return true
	end

	return false
end

local AINodeWalkers = {}

local function NodeStep(pos)
	local result = PhysicsRaycast(SnapToGrid(pos + Vector3.new(0, 6, 0)), Vector3.new(0, -2048, 0))

	if result then
		return result.Position, result.Distance > 12
	end

	return nil, true
end

local function SummonNodeWalk(pos, dir, node)
	dir = dir or Vector3.zero

	local poz = pos + dir

	if node and node.Dynamic then
		if HasNodeInXZ(poz.X, poz.Z) then
			return false
		end
	end

	local newpos, oneway = NodeStep(poz)

	if IsNodeValid(newpos) then
		local cangoto = not PhysicsCheckLine(pos + Vector3.new(0, 4, 0), 0.4, (newpos - pos) * VEC3XZ)

		if cangoto then
			local newnode = GetNode(newpos)

			if node then
				EnsureNodesLinked(node, newnode)

				if not oneway then
					EnsureNodesLinked(newnode, node)
				end
			end

			if not newnode.Known then
				newnode.Known = true
				table.insert(AINodeWalkers, newnode)
			end
		end

		return true
	end

	return false
end

local function CheckTruss(node, dir)
	local origin = node.Position + Vector3.new(0, 3, 0)
	local cast = PhysicsRaycast(origin, dir * 5)

	if cast and cast.Instance and IsTruss(cast.Instance) then
		local truss = cast.Instance
		local trussTopY = truss.Position.Y + truss.Size.Y / 2

		local topCast = PhysicsRaycast(truss.Position + Vector3.new(0, truss.Size.Y / 2 + 5, 0), Vector3.new(0, -10, 0))

		if topCast and topCast.Position.Y >= trussTopY - 1 then
			local topNode = GetNode(topCast.Position + Vector3.new(0, 0.5, 0))
			EnsureNodesLinked(node, topNode)
			EnsureNodesLinked(topNode, node)

			local otherSideCast = PhysicsRaycast(truss.Position + dir * 10 + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0))

			if otherSideCast and otherSideCast.Position.Y >= trussTopY - 2 then
				local otherNode = GetNode(otherSideCast.Position + Vector3.new(0, 0.5, 0))
				EnsureNodesLinked(topNode, otherNode)
				EnsureNodesLinked(otherNode, topNode)
			end
		end
	end
end

local function NodeWalkWalk(node)
	if CONFIG.DEBUG_NODEWALKER then
		CreateDot(DebugNodewalker, node.Position)
	end

	for _, dir in CARDINALS do
		if SummonNodeWalk(node.Position, dir, node) then
			continue
		end

		if SummonNodeWalk(node.Position, dir * 2, node) then
			continue
		end

		SummonNodeWalk(node.Position, dir * 5, node)
		CheckTruss(node, dir)
	end
end

local function NodeWalk(node)
	if node.Explored then
		return
	end

	NodeWalkWalk(node)
	node.Explored = true
end

SummonNodeWalk(Vector3.new(0, 247, 0))

-- Improved priority queue
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
	return setmetatable({
		data = {},
	}, PriorityQueue)
end

function PriorityQueue:push(node, priority)
	table.insert(self.data, {
		node = node,
		priority = priority,
	})

	local i = #self.data

	while i > 1 do
		local parent = math.floor(i / 2)

		if self.data[parent].priority <= self.data[i].priority then
			break
		end

		self.data[i], self.data[parent] = self.data[parent], self.data[i]
		i = parent
	end
end

function PriorityQueue:pop()
	if #self.data == 0 then
		return nil, nil
	end

	local root = self.data[1]
	local last = table.remove(self.data)

	if #self.data > 0 then
		self.data[1] = last

		local i = 1

		while true do
			local left = i * 2
			local right = left + 1
			local smallest = i

			if left <= #self.data and self.data[left].priority < self.data[smallest].priority then
				smallest = left
			end

			if right <= #self.data and self.data[right].priority < self.data[smallest].priority then
				smallest = right
			end

			if smallest == i then
				break
			end

			self.data[i], self.data[smallest] = self.data[smallest], self.data[i]
			i = smallest
		end
	end

	return root.node, root.priority
end

function PriorityQueue:isEmpty()
	return #self.data == 0
end

local function OptimisePath(path)
	local i = 1

	while i <= #path - 2 do
		local a = path[i].Position
		local c = path[i + 2].Position

		local flat = (c - a) * VEC3XZ
		local canSkip = false

		if flat.Magnitude < 45 and math.abs(a.Y - c.Y) <= 2.5 then
			local blocked = PhysicsCheckLine(a + Vector3.new(0, 3, 0), 1.0, flat)
			local mid = (a + c) * 0.5
			local midGround = CheckGroundCached(mid)

			canSkip = (not blocked) and midGround
		end

		if canSkip then
			table.remove(path, i + 1)
		else
			i += 1
		end
	end
end

local function Pathfind(start, goal)
	local cacheKey = GetPathCacheKey(start, goal)

	local cached = CacheGet(cacheKey, CONFIG.PATH_CACHE_TTL, nil)
	if cached then
		DebugLines[2] = "PATHFOUND CACHED " .. #cached .. " WPS"
		return cached
	end

	local startnode = ClosestNode(start)
	if not startnode then
		SummonNodeWalk(start)
		return nil
	end

	local goalnode = ClosestNode(goal)
	if not goalnode then
		SummonNodeWalk(goal)
		return nil
	end

	DebugPathfinder.Color3 = Color3.new(1, 0, 0)

	local cameFrom = {}
	local gScore = {}
	local fScore = {}
	local costScan = {}
	local closed = {}

	gScore[startnode] = 0
	fScore[startnode] = GetDistance(startnode, goalnode)
	costScan[startnode] = GetNodeCost(startnode)

	local open = PriorityQueue.new()
	open:push(startnode, fScore[startnode])

	local expansions = 0

	while not open:isEmpty() do
		local current, priority = open:pop()

		if current and not closed[current] then
			if priority == fScore[current] then
				closed[current] = true

				if current == goalnode then
					local path = {}

					while current do
						table.insert(path, 1, {
							Position = current.Position,
							Cost = costScan[current] or GetNodeCost(current),
							Node = current,
						})

						current = cameFrom[current]
					end

					OptimisePath(path)
					CacheSet(cacheKey, path, CONFIG.PATH_CACHE_TTL)

					DebugLines[2] = "PATHFOUND " .. #path .. " WPS"
					DebugPathfinder.Color3 = Color3.new(1, 1, 0)

					return path
				end

				expansions += 1

				if expansions > CONFIG.PATH_MAX_EXPANSIONS then
					break
				end

				for _, neighbor in current.Links do
					if not closed[neighbor] then
						local cost = GetNodeCost(neighbor)

						if cost > 0 then
							local tentative = gScore[current] + cost * GetDistance(current, neighbor)

							if not gScore[neighbor] or tentative < gScore[neighbor] then
								cameFrom[neighbor] = current
								gScore[neighbor] = tentative
								fScore[neighbor] = tentative + GetDistance(neighbor, goalnode)
								costScan[neighbor] = cost

								open:push(neighbor, fScore[neighbor])
							end
						end
					end
				end

				if expansions % CONFIG.PATHFIND_SPEED == 0 then
					task.wait()
				end
			end
		end
	end

	DebugLines[2] = "PATHFOUND NO PATH"
	DebugPathfinder.Color3 = Color3.new(1, 0, 0)

	return nil
end

-- Node exploration thread
task.spawn(function()
	local iter = 0

	while true do
		local node = AINodeWalkers[1]

		if node then
			DebugLines[1] = "WALKING " .. #AINodeWalkers .. " NODES, CURRENT: " .. AINodesCount

			iter += 1

			if iter >= CONFIG.NODEWALK_SPEED then
				task.wait()
				DebugClear(DebugNodewalker)
				iter = 0
			end

			for _, v in CollideForcers do
				v.CanCollide = true
			end

			NodeWalk(node)
			table.remove(AINodeWalkers, 1)
		else
			DebugClear(DebugNodewalker)
			DebugLines[1] = "WALKED " .. AINodesCount .. " NODES, " .. AINodesDynCount .. " ARE DYNAMIC"

			for _, v in CollideForcers do
				v.CanCollide = false
			end

			task.wait()
		end
	end
end)

-- Dynamic node updater
task.spawn(function()
	local dyn = 1

	while task.wait(0.2) do
		RunService.PreSimulation:Wait()

		for _, node in AINodesDyn do
			local ceiling = node.Position * VEC3XZ + Vector3.yAxis * (node.YLevel + 32)
			local downward = PhysicsRaycast(ceiling, Vector3.new(0, -1024, 0))

			if downward and downward.Normal.Y > 0.25 then
				local newPos = SnapToGrid(downward.Position + Vector3.new(0, 0.5, 0))

				if (newPos - node.Position).Magnitude > 0.75 then
					PathCacheVersion += 1
				end

				node.Position = newPos
				node.Ground = downward.Instance
			else
				if node.Ground ~= nil then
					PathCacheVersion += 1
				end

				node.Ground = nil
			end
		end

		if AINodesDynCount > 0 then
			local node = AINodesDyn[dyn]
			dyn = (dyn % AINodesDynCount) + 1

			NodeWalkWalk(node)
			BreakAllLinks(node)

			for _, node2 in ipairs(node.Nearby) do
				if node.Position.Y > node2.Position.Y - 6 then
					EnsureNodesLinked(node, node2)
				end

				if node2.Position.Y > node.Position.Y - 6 then
					EnsureNodesLinked(node2, node)
				end
			end
		end
	end
end)

Player.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
Player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable

-- Cached nearest character
local GetNearestCharacter_cache = {
	t = 0,
	pos = nil,
	radius = nil,
	root = nil,
	dist = nil,
}

local function GetNearestCharacter(pos, dist)
	local now = os.clock()
	local cached = GetNearestCharacter_cache

	if cached.root and now - cached.t < CONFIG.TARGET_CACHE_TTL then
		if cached.root:IsDescendantOf(workspace) and cached.pos and (cached.pos - pos).Magnitude < 2 then
			if dist <= (cached.radius or 20) then
				return cached.root, cached.dist
			end
		end
	end

	local nearest = nil
	local nearestdist = dist or 20

	for _, char in Characters do
		if char ~= Player.Character and not char:FindFirstChildOfClass("ForceField") then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")

			if root and hum and hum.Health > 0 and IsSafe(root.Position) then
				local vel = Vector3.zero

				if IsSafe(root.Velocity) then
					vel = root.Velocity
				end

				local predicted = root.Position + vel * CONFIG.PREDICT_PLAYER_HIT

				if IsSafe(predicted) then
					local d = ((predicted - pos) * VEC3XZ).Magnitude

					if d <= nearestdist then
						nearest = root
						nearestdist = d
					end
				end
			end
		end
	end

	GetNearestCharacter_cache = {
		t = now,
		pos = pos,
		radius = dist,
		root = nearest,
		dist = nearestdist,
	}

	return nearest, nearestdist
end

-- Tool pickup detection
local lastToolCount = 0

task.spawn(function()
	while true do
		task.wait(1)

		local back = Player:FindFirstChildOfClass("Backpack")
		local char = Player.Character

		if back and char then
			local tools = {}

			for _, v in ipairs(back:GetChildren()) do
				if v:IsA("Tool") then
					table.insert(tools, v)
				end
			end

			for _, v in ipairs(char:GetChildren()) do
				if v:IsA("Tool") then
					table.insert(tools, v)
				end
			end

			if #tools > lastToolCount then
				if CONFIG.GRAB_TOOL_MESHES then
					local newTool = tools[#tools]

					if newTool then
						local lowerName = string.lower(newTool.Name)

						if lowerName ~= "linkedsword" and lowerName ~= string.lower(CONFIG.SWORD_NAME) then
							dynamicSwordName = newTool.Name
							SayBubble("Got a new tool!", Enum.ChatColor.Green)
						else
							dynamicSwordName = CONFIG.SWORD_NAME
						end
					end
				end
			end

			lastToolCount = #tools
		else
			lastToolCount = 0
		end
	end
end)

local isResetting = false

local function Essentials()
	local char = Player.Character
	local back = Player:FindFirstChildOfClass("Backpack")

	if char and back then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")

		if hum and root and hum:GetState().Name ~= "Dead" then
			local pos = root.Position
			local vel = root.AssemblyLinearVelocity
			local angVel = root.AssemblyAngularVelocity
			local isFlinged = false

			if not IsSafe(pos) or not IsSafe(vel) or not IsSafe(angVel) then
				isFlinged = true
			elseif vel.Magnitude > 2500 or angVel.Magnitude > 2500 then
				isFlinged = true
			end

			if not isFlinged then
				return char, back, hum, root
			else
				isResetting = true

				pcall(function()
					if hum.ServerBreakJoints then
						replicatesignal(hum.ServerBreakJoints)
					else
						hum.Health = 0
					end
				end)
			end
		end
	end

	return nil
end

-- Shared bot state
local idlePosition = nil
local targetMove = idlePosition
local targetLook = Vector3.zero
local targetLookY = 0
local targetJump = false
local haveSword = false
local useSword = false
local overrideController = false
local noPathEvent = nil
local hasDied = false

local currentVictim = nil
local currentPlaystyle = nil
local currentPlaystyleName = "NULL"
local currentPlaystyleIndex = 0

local charge = false
local strafe = 2
local strafe2 = 2
local backoff = 19

local cachedVictim = nil
local cachedDist = nil
local cacheTimer = 0

local Hacking = {}

noPathEvent = function(goal)
	if not CONFIG.USE_PREDEFS_ON_NOPATH then
		return
	end

	if #Hacking == 0 then
		return
	end

	if currentVictim and targetMove and IsSafe(targetMove) and IsSafe(goal) and (targetMove - goal).Magnitude < 4 then
		local char, back, root, hum = Essentials()
		local sword = GetTool(char, back, dynamicSwordName)

		if char and sword then
			overrideController = true
			Hacking[math.random(#Hacking)](char, back, root, hum, sword, currentVictim)
			overrideController = false
		end
	end
end

-- Sword equip thread
task.spawn(function()
	while true do
		task.wait(1)

		local char = Player.Character
		local back = Player:FindFirstChildOfClass("Backpack")

		if char and back then
			local sword = GetTool(char, back, dynamicSwordName)

			if sword then
				if haveSword and sword.Parent == back then
					sword.Parent = char
				end
			end
		end
	end
end)

-- Controller thread
task.spawn(function()
	local function PfThread(pf)
		local path = Pathfind(pf.Start, pf.Goal)

		pf.Done = true
		pf.Path = path or {}

		if not path and noPathEvent then
			noPathEvent(pf.Goal)
		end
	end

	local pathfinding = nil
	local pathfinding2 = nil
	local moveToward = nil

	while true do
		local dt = task.wait()

		DebugClear(DebugController)

		if overrideController then
			DebugLines[3] = "PREDEF IS OVERRIDING"
			DebugLines[4] = "PREDEF IS OVERRIDING"
			DebugLines[5] = "PREDEF IS OVERRIDING"
		end

		local char, back, hum, root = Essentials()

		if char then
			local lleg = char:FindFirstChild("Left Leg") or char:FindFirstChild("LeftFoot") or char:FindFirstChild("LeftLowerLeg")
			local rleg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightFoot") or char:FindFirstChild("RightLowerLeg")

			if lleg then
				lleg.CanCollide = false
			end

			if rleg then
				rleg.CanCollide = false
			end

			local rightArm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")

			if rightArm then
				local sword = GetTool(char, back, dynamicSwordName)

				if sword then
					if haveSword then
						DebugLines[3] = "SWORD EQUIPPED"

						if sword.Parent == back then
							sword.Parent = char
						end

						if useSword then
							DebugLines[3] = "SWORD ACTIVATED"
							sword.Enabled = true
							sword:Activate()
						end
					else
						DebugLines[3] = "SWORD SHEATHED"

						if sword.Parent == char then
							sword.Parent = back
						end
					end
				else
					DebugLines[3] = "NO SWORD FOUND"
				end
			else
				DebugLines[3] = "NO RIGHT ARM/HAND FOUND, NO GRIP"
			end

			if targetLook and table.find(HUM_STATES_SHIFTLOCK, hum:GetState().Name) then
				local diff = (targetLook - root.Position) * VEC3XZ

				if not IsSafe(diff) then
					diff = Vector3.zero
				end

				if diff.Magnitude > 0 then
					root.CFrame = CFrame.lookAlong(root.CFrame.Position, diff) * CFrame.Angles(0, targetLookY, 0)
					root.RotVelocity = Vector3.zero
				end
			end

			local onLadder = hum:GetState() == Enum.HumanoidStateType.Climbing
			local onGround = hum:GetState() == Enum.HumanoidStateType.Running or onLadder

			local groundPos, groundPart = EnsureGround(root.Position, true)
			local mePos = groundPos or root.Position

			local groundVel = Vector3.zero
			local onMovingGround = false

			if groundPart and groundPart:IsA("BasePart") and not groundPart.Anchored then
				groundVel = groundPart.AssemblyLinearVelocity

				if (groundVel * VEC3XZ).Magnitude > 2 then
					onMovingGround = true
				end
			end

			local moveDir = Vector3.zero
			local safeTargetMove = IsSafe(targetMove) and (EnsureGround(targetMove, true) or targetMove) or nil

			if mePos and safeTargetMove then
				CreateLocator(DebugController, mePos)
				CreateLocator(DebugController, safeTargetMove)

				local distToTarget = (safeTargetMove - mePos).Magnitude

				if distToTarget < 15 or CheckWalkable(mePos, safeTargetMove) then
					DebugLines[4] = "MOVE METHOD: MOVETO"
					pathfinding2 = nil
					moveToward = safeTargetMove
				else
					DebugLines[4] = "MOVE METHOD: PATHFIND, IDLE"

					if pathfinding and pathfinding ~= "FORCE" then
						if pathfinding.Done then
							pathfinding2 = pathfinding
							pathfinding = nil

							if moveToward then
								local path = pathfinding2.Path
								local closestDist = math.huge

								for i = 1, #path do
									local dist = (moveToward - path[i].Position).Magnitude

									if dist < closestDist then
										closestDist = dist
										pathfinding2.Index = i
									end
								end
							end
						else
							DebugLines[4] = "MOVE METHOD: PATHFIND, RUNNING"
						end
					elseif pathfinding == "FORCE" or not pathfinding2 then
						local pf = {}
						pf.Start = mePos
						pf.Goal = safeTargetMove
						pf.Index = 1
						pf.Path = {}
						pf.Done = false

						task.spawn(PfThread, pf)

						pathfinding = pf
						DebugLines[4] = "MOVE METHOD: PATHFIND, STARTING"
					end

					local pf = pathfinding2

					if pf and #pf.Path >= pf.Index then
						local path = pathfinding2.Path

						for i = 0, 16 do
							local wp = path[pf.Index + i]
							local nwp = path[pf.Index + i + 1]

							if wp then
								CreateDot(DebugController, wp.Position)

								if GetNodeCost(wp.Node) ~= wp.Cost then
									pathfinding = pathfinding or "FORCE"
									break
								end

								if nwp and not CheckGround((nwp.Position + wp.Position) / 2) then
									if not onGround then
										continue
									end
								end

								if ((wp.Position - mePos) * VEC3XZ).Magnitude < 0.5 then
									pf.Index += i + 1
									break
								end
							else
								break
							end
						end

						if (pathfinding2.Goal - safeTargetMove).Magnitude > 4 then
							pathfinding = pathfinding or "FORCE"
						end

						if path[pf.Index] and CheckGround(path[pf.Index].Position) then
							DebugLines[4] = "METHOD: PATHFIND, PATHING, IDX = " .. pf.Index

							moveToward = path[pf.Index].Position

							if moveToward.Y > mePos.Y + 6 and pf.Index > 1 then
								local isTrussInWay = false
								local horizontalDir = (moveToward - root.Position) * VEC3XZ

								if horizontalDir.Magnitude > 0.1 then
									local castToWp = PhysicsRaycast(root.Position + Vector3.new(0, 3, 0), horizontalDir.Unit * 5)

									if castToWp and castToWp.Instance and IsTruss(castToWp.Instance) then
										isTrussInWay = true
									end
								end

								if not onLadder and not isTrussInWay then
									pf.Index -= 1
								end
							end
						end
					else
						pathfinding2 = nil
					end
				end

				if moveToward then
					CreateLocator(DebugController, moveToward + Vector3.new(0, 1, 0))

					local diff = (moveToward - mePos) * VEC3XZ

					if not IsSafe(diff) then
						diff = Vector3.zero
					end

					if onGround then
						diff *= 2
					else
						diff *= 0.8
					end

					if diff.Magnitude > 1 then
						moveDir = diff.Unit
					else
						moveDir = diff
					end
				end
			else
				DebugLines[4] = "MOVE METHOD: I HAVE FALLEN AND I CANT GET UP"
			end

			local mustJump = targetJump

			if onGround and not onLadder then
				DebugLines[5] = "JUMP STATE: FUH NAW!"

				local dir = root.Velocity * VEC3XZ

				if mustJump then
					DebugLines[5] = "JUMP STATE: YES! (BRAIN SAID SO)"
				elseif onMovingGround then
					mustJump = false
					DebugLines[5] = "JUMP STATE: SUPPRESSED (ON RAMP/MOVING GROUND)"
				else
					if dir.Magnitude > 0.2 and PhysicsCheckArea(root.CFrame, Vector3.new(4.5, 3, 3.5)) then
						local cast = PhysicsRaycast(root.Position + Vector3.new(0, 3, 0), dir.Unit * 5)

						if not (cast and cast.Instance and IsTruss(cast.Instance)) then
							mustJump = true
							DebugLines[5] = "JUMP STATE: YES! (WE WILL HIT AN OBSTACLE)"
						end
					end

					if not mustJump then
						if dir.Magnitude > 0.2 then
							local check1 = PhysicsCheckArea(root.CFrame + dir.Unit * 0.5 + Vector3.new(0, -3, 0), Vector3.new(1, 3, 0.25))
							local check2 = PhysicsCheckArea(root.CFrame + dir.Unit * 1 + Vector3.new(0, -3, 0), Vector3.new(1, 3, 1))
							local check3 = PhysicsCheckArea(root.CFrame + dir.Unit * 2.5 + Vector3.new(0, -506, 0), Vector3.new(1.5, 1024, 5))

							if not check1 and not check2 then
								if check3 then
									mustJump = true
									DebugLines[5] = "JUMP STATE: YES! (MOVEMENT NEEDS TO JUMP OVER LEDGE)"
								else
									moveDir = Vector3.zero
									pathfinding2 = nil
									DebugLines[5] = "JUMP STATE: AW HAIL NAW! (MOVEMENT LEADS TO A VOID)"
								end
							end
						end
					end
				end
			end

			if not IsSafe(moveDir) then
				moveDir = Vector3.zero
			end

			CreateLine(DebugController, root.Position, root.Position + moveDir * 4)

			hum:Move(moveDir)

			if CONFIG.PATCH_HUMANOID_MOVE_QUIRKS and not onLadder then
				local vel = root.Velocity
				local tvel = (moveDir * VEC3XZ * hum.WalkSpeed) + (groundVel * VEC3XZ) + Vector3.yAxis * vel.Y

				if onGround then
					vel = tvel:Lerp(vel, math.exp(-16 * dt))
				else
					vel = tvel:Lerp(vel, math.exp(-2 * dt))
				end

				if IsSafe(vel) then
					root.Velocity = vel
				end
			end

			if mustJump and onGround then
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		else
			DebugLines[3] = "ALAS MY SWORD"
			DebugLines[4] = "INVALID CHARACTER"
			DebugLines[5] = "YOU ARE HERE --> t"

			moveToward = nil
			pathfinding = nil
			pathfinding2 = nil
		end
	end
end)

-- Random combat modifiers
task.spawn(function()
	while true do
		task.wait(math.random() * 5)
		charge = not charge
	end
end)

task.spawn(function()
	while true do
		strafe2 = math.random(-2, 2)

		if math.random() < 0.89 then
			strafe = -strafe
		else
			for _ = 1, math.random(4) * 2 do
				strafe = -strafe
				task.wait(1 / 9)
			end
		end

		task.wait(math.random() * 2)
	end
end)

task.spawn(function()
	while true do
		task.wait(math.random() * 2)
		backoff = math.random(16, 20)
	end
end)

-- Limb targeting
local LIMB_NAMES = {
	"Right Arm",
	"Left Arm",
	"Right Leg",
	"Left Leg",
	"RightHand",
	"LeftHand",
	"RightFoot",
	"LeftFoot",
	"RightLowerArm",
	"LeftLowerArm",
	"RightLowerLeg",
	"LeftLowerLeg",
	"Torso",
	"UpperTorso",
	"LowerTorso",
	"HumanoidRootPart",
}

local function GetClosestLimbPos(victim, mePos)
	local char = victim.Parent

	if not char then
		return victim.Position
	end

	local closestDist = math.huge
	local bestPos = victim.Position

	for _, name in ipairs(LIMB_NAMES) do
		local part = char:FindFirstChild(name)

		if part and part:IsA("BasePart") then
			local d = (part.Position - mePos).Magnitude

			if d < closestDist then
				closestDist = d
				bestPos = part.Position
			end
		end
	end

	return bestPos
end

-- Improved combat helpers
local nextSwingTime = 0
local nextDodgeTime = 0

local lastLimbCache = {
	t = 0,
	victim = nil,
	pos = nil,
}

local function GetClosestLimbPosCached(victim, mePos)
	local now = os.clock()

	if lastLimbCache.victim == victim and lastLimbCache.pos and now - lastLimbCache.t < 0.08 then
		return lastLimbCache.pos
	end

	local p = GetClosestLimbPos(victim, mePos)

	lastLimbCache = {
		t = now,
		victim = victim,
		pos = p,
	}

	return p
end

local function ClampNumber(value, min, max)
	return math.max(min, math.min(max, value))
end

local function GetPredictedCombatPoint(victim, mePos, dist)
	local limb = GetClosestLimbPosCached(victim, mePos)

	local vel = Vector3.zero

	if IsSafe(victim.Velocity) then
		vel = victim.Velocity * VEC3XZ
	end

	if vel.Magnitude > CONFIG.PREDICT_MAX_SPEED then
		vel = vel.Unit * CONFIG.PREDICT_MAX_SPEED
	end

	local ping = Player:GetNetworkPing() or 0
	local lead = CONFIG.PREDICT_PLAYER_HIT + ping * CONFIG.PREDICT_PING_FACTOR

	if dist < 8 then
		lead *= 0.35
	end

	return limb + vel * lead, limb
end

local function MakeSafeMoveTarget(mePosGround, desired, fallback)
	if desired and CheckGroundCached(desired) then
		return desired
	end

	local base = desired or fallback

	if base then
		for _, dir in ipairs(CARDINALS) do
			local p = base + dir * 2

			if CheckGroundCached(p) then
				return p
			end
		end
	end

	if fallback and fallback ~= desired and CheckGroundCached(fallback) then
		return fallback
	end

	return mePosGround
end

local function CombatJumpDecision(victim, mePos, dist, humState)
	if dist > CONFIG.CHARGE_NO_JUMP_DIST * 2 then
		return false
	end

	if humState ~= Enum.HumanoidStateType.Running and humState ~= Enum.HumanoidStateType.Landed then
		return false
	end

	if not IsSafe(victim.Position) or not IsSafe(victim.Velocity) then
		return false
	end

	local char = victim.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	local victimJumping = victim.Velocity.Y > 6
		or (
			hum and (
				hum:GetState() == Enum.HumanoidStateType.Jumping
				or hum:GetState() == Enum.HumanoidStateType.Freefall
			)
		)

	local victimAbove = victim.Position.Y > mePos.Y + 2

	return victimJumping or victimAbove
end

local function ShouldSwing(hum, root, targetPos, dist, hitDist)
	local now = os.clock()

	if now < nextSwingTime then
		return false
	end

	if not IsSafe(root.Position) or not IsSafe(targetPos) then
		return false
	end

	local state = hum:GetState()

	local validState = state == Enum.HumanoidStateType.Running
		or state == Enum.HumanoidStateType.Landed
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall

	local inRange = dist <= CONFIG.DIST_SWING + 0.75 or hitDist <= 3.0

	local flat = (targetPos - root.Position) * VEC3XZ
	local facing = true

	if flat.Magnitude > 0.1 then
		facing = root.CFrame.LookVector:Dot(flat.Unit) > 0.25
	end

	if validState and inRange and facing then
		nextSwingTime = now + CONFIG.MAX_SWING_COOLDOWN
		return true
	end

	return false
end

local function GetNearestHealingPadCached(pos)
	local key = string.format(
		"HEAL:%.0f:%.0f:%.0f",
		pos.X, pos.Y, pos.Z
	)

	local data = CacheGet(key, 0.5, function()
		local pad, dist = GetNearestHealingPad(pos)

		return {
			pad = pad,
			dist = dist,
		}
	end)

	if data then
		return data.pad, data.dist
	end

	return nil, math.huge
end

local function ImprovedCombatPlaystyle(dt, hum, root, victim, dist, hitDist, mePos, mePosGround, victimPos, victimCF)
	local now = os.clock()

	local predicted, limb = GetPredictedCombatPoint(victim, mePos, dist)

	local aimDir = (predicted - mePos) * VEC3XZ

	if aimDir.Magnitude < 0.1 then
		aimDir = Vector3.xAxis
	end

	local aimCF = CFrame.lookAlong(Vector3.zero, aimDir)

	local victimChar = victim.Parent
	local victimHum = victimChar and victimChar:FindFirstChildOfClass("Humanoid")

	local victimHasTool = false

	if victimChar then
		victimHasTool = victimChar:FindFirstChildOfClass("Tool") ~= nil
	end

	local toMe = mePos - victimPos
	local victimLookingAtMe = false

	if toMe.Magnitude > 0.1 then
		victimLookingAtMe = victimCF.LookVector:Dot(toMe.Unit) > 0.3
	end

	local victimSpeed = 0

	if IsSafe(victim.Velocity) then
		victimSpeed = (victim.Velocity * VEC3XZ).Magnitude
	end

	if dist < CONFIG.IMMEDIATE_ATTACK_RADIUS then
		charge = true
	end

	targetLook = predicted

	local lookDist = (predicted - mePos).Magnitude

	if lookDist > 1.5 then
		targetLookY = math.atan(1.5 / lookDist)
	else
		targetLookY = math.pi * 0.5
	end

	local desiredMove

	if CONFIG.ALLOW_HEALING and hum.Health < CONFIG.HEALING_BELOW_HEALTH then
		local healpad, healdist = GetNearestHealingPadCached(mePos)

		if healpad and healdist < 120 then
			desiredMove = healpad.Position
		else
			desiredMove = mePosGround - aimCF.LookVector * 10
		end

		DebugLines[7] = "PLAYSTYLE: LOW HEALTH SURVIVAL"
	elseif dist < CONFIG.DODGE_RANGE and victimHasTool and victimLookingAtMe and now > nextDodgeTime and math.random() < 0.25 then
		nextDodgeTime = now + 0.55

		local side = 1

		if math.random() > 0.5 then
			side = -1
		end

		desiredMove = mePosGround - aimCF.LookVector * 2.5 + aimCF.RightVector * (side * math.random(4, 6))

		DebugLines[7] = "PLAYSTYLE: DODGE"
	elseif victimSpeed > 1 and CheckWalkable(mePosGround, victimPos) then
		if charge then
			desiredMove = predicted
			DebugLines[7] = "PLAYSTYLE: CHASE"
		else
			local orbit = aimCF.RightVector * (strafe * 3.2)
			local spacing = aimCF.LookVector * ClampNumber(dist - CONFIG.DIST_SWING, -2.5, 7.0)

			desiredMove = predicted + orbit + spacing

			DebugLines[7] = "PLAYSTYLE: STRAFE"
		end
	else
		local spacing = aimCF.LookVector * ClampNumber(dist - 3.2, -2.0, 5.0)
		local side = aimCF.RightVector * (strafe2 * 0.9)

		desiredMove = predicted + spacing + side

		DebugLines[7] = "PLAYSTYLE: PRESSURE"
	end

	targetMove = MakeSafeMoveTarget(mePosGround, desiredMove, victimPos)

	targetJump = CombatJumpDecision(victim, mePos, dist, hum:GetState())

	if dist < CONFIG.CHARGE_NO_JUMP_DIST then
		targetJump = targetJump and (victim.Position.Y > mePos.Y + 1.5 or victim.Velocity.Y > 8)
	end

	if ShouldSwing(hum, root, predicted, dist, hitDist) then
		useSword = true
		targetLookY += math.pi * 0.12 * (math.random() - 0.5)
	end
end

local Playstyles = {
	ImprovedCombatPlaystyle,
	ImprovedCombatPlaystyle,
	ImprovedCombatPlaystyle,
}

local PlaystylesNames = {
	"IMPROVED CONTROL",
	"IMPROVED CONTROL",
	"IMPROVED CONTROL",
}

local PlaystylesDeaths = {}

for _ in ipairs(PlaystylesNames) do
	table.insert(PlaystylesDeaths, 0)
end

local function Determination()
	local low, lowv, high, highv = nil, math.huge, nil, 0

	for i, v in PlaystylesDeaths do
		if v <= lowv then
			low, lowv = i, v
		end

		if v >= highv then
			high, highv = i, v
		end
	end

	if low and high then
		local diff = highv - lowv

		if diff > 16 then
			if math.random() > 16 / diff then
				return low
			end
		end
	end

	return math.random(#Playstyles)
end

local function Determined(i)
	PlaystylesDeaths[i] += 1
end

-- Main brain
while true do
	local dt = task.wait()

	if currentFPS < 15 then
		if ChatState == "LAGGING" then
			LagTimer += dt

			if LagTimer > 3 then
				local aggressiveLagMessages = {
					"NO! WHY ISNT IT FIXED!",
					"GOD DAMN IT I HATE MY PC",
					"THIS IS WHY I AM TOO POOR TO GET A GOOD PC",
					"I HATE THIS LAG!",
				}

				SayBubble(aggressiveLagMessages[math.random(#aggressiveLagMessages)], Enum.ChatColor.Red)
				LagTimer = 0
			end
		else
			local initialLagMessages = {
				"OH MY PCCC",
				"HELP MEE",
				"LAGGING SO HARD",
				"WHY IS MY PC DYING",
			}

			ChangeChatState("LAGGING", initialLagMessages, Enum.ChatColor.Red)
			LagTimer = 0
		end
	else
		if ChatState == "LAGGING" then
			ChangeChatState("IDLE", nil)
		end
	end

	if charge then
		DebugLines[8] = "CHARGING? YES"
	else
		DebugLines[8] = "CHARGING? NO"
	end

	DebugClear(DebugBrain)

	local char, back, hum, root = Essentials()

	if char then
		hasDied = false

		DebugLines[6] = "BRAIN: NO TARGETS, IDLING"
		DebugLines[7] = "PLAYSTYLE: NO THOUGHTS"

		targetMove = nil
		targetLook = nil
		targetLookY = 0
		targetJump = false
		haveSword = false
		useSword = false

		if overrideController then
			DebugLines[6] = "BRAIN: IN OVERRIDE"
			continue
		end

		if math.random() < 0.3 * dt then
			idlePosition = nil
		end

		local mePos = root.Position

		if not idlePosition then
			local toolMeshPart, toolMeshPos = nil, nil

			if CONFIG.GRAB_TOOL_MESHES then
				toolMeshPart, toolMeshPos = GetNearestToolMesh(mePos)
			end

			if toolMeshPos then
				idlePosition = toolMeshPos
			else
				local dir = CFrame.Angles(0, math.random() * math.pi * 2, 0).LookVector * math.random(10, 100)
				local hit = PhysicsRaycast(mePos + dir + Vector3.new(0, 512, 0), Vector3.new(0, -1024, 0))

				if hit then
					idlePosition = hit.Position
				end
			end
		end

		targetMove = idlePosition

		local distanceToEngage = CONFIG.DETECTION_RADIUS

		if CONFIG.ALLOW_HEALING then
			if hum.Health < CONFIG.HEALING_BELOW_HEALTH then
				distanceToEngage = CONFIG.START_COMBAT

				local healpad, healdist = GetNearestHealingPad(mePos)

				if healpad then
					targetMove = healpad.Position
					targetJump = false
					DebugLines[6] = "BRAIN: I BETTER HEAL UP"
				else
					DebugLines[6] = "BRAIN: I AM LOW AND I CANT HEAL UP"
				end
			end
		end

		if currentVictim then
			local vChar = currentVictim.Parent
			local vHum = vChar and vChar:FindFirstChildOfClass("Humanoid")

			if not vChar or not vHum or vHum.Health <= 0 then
				if ChatState ~= "LAGGING" then
					ChangeChatState("WON", nil, Enum.ChatColor.Red)
				end

				currentVictim = nil
				currentPlaystyle = nil
				currentPlaystyleName = "NULL"
				currentPlaystyleIndex = 0
			end
		end

		local mePosGround = EnsureGround(mePos, true) or mePos

		cacheTimer += dt

		if cacheTimer > 0.2 or not currentVictim then
			cacheTimer = 0
			cachedVictim, cachedDist = GetNearestCharacter(mePos, distanceToEngage)
		end

		local victim = cachedVictim
		local dist = cachedDist

		if currentVictim and currentVictim:IsDescendantOf(workspace) then
			local currentDist = (currentVictim.Position - mePos).Magnitude

			if currentDist <= distanceToEngage then
				if not victim or currentDist <= (dist or math.huge) + 6 then
					victim = currentVictim
					dist = currentDist
				end
			end
		end

		if not victim then
			currentVictim = nil
			currentPlaystyle = nil
			charge = false
		elseif not currentVictim or dist < CONFIG.START_COMBAT then
			if currentVictim ~= victim then
				currentPlaystyle = nil
				charge = false
			end

			currentVictim = victim
		end

		if currentVictim then
			victim = currentVictim
			dist = (currentVictim.Position - mePos).Magnitude
		end

		local isAttacking = victim and dist and dist < CONFIG.START_COMBAT
		local sawOpponent = currentVictim ~= nil

		if sawOpponent and not isAttacking and ToolMeshHighlight then
			local nearestTool, nearestToolPos = GetNearestToolMesh(mePos)

			if nearestTool then
				ToolMeshHighlight.Adornee = nearestTool
				ToolMeshHighlight.Enabled = true

				local toolNode = ClosestNode(nearestToolPos)

				if toolNode then
					ToolMeshHighlight.FillColor = Color3.fromRGB(0, 255, 0)
				else
					ToolMeshHighlight.FillColor = Color3.fromRGB(255, 0, 0)
				end
			else
				ToolMeshHighlight.Enabled = false
			end
		else
			if ToolMeshHighlight then
				ToolMeshHighlight.Enabled = false
			end
		end

		if victim and dist then
			DebugLines[6] = "BRAIN: RED ALERT RED ALERT"
			idlePosition = nil

			CreateLine(DebugBrain, mePos, victim.Position)

			local victimCF = victim.CFrame
			local victimPos = EnsureGround(victim.Position, true) or victim.Position

			if dist < CONFIG.START_COMBAT then
				haveSword = true

				CreateCircle(DebugBrain, victimPos, CONFIG.IMMEDIATE_ATTACK_RADIUS)
				CreateLine(DebugBrain, root.CFrame * Vector3.new(1.5, 0.5, 0.5), root.CFrame * Vector3.new(1.5, 0.5, -CONFIG.START_COMBAT))

				local hitPos = root.CFrame * Vector3.new(0, 0, -1)

				CreateCircle(DebugBrain, hitPos, 2)

				local hitDist = ((hitPos - victimPos) * VEC3XZ).Magnitude

				if not currentPlaystyle then
					local i = Determination()
					currentPlaystyle = Playstyles[i]
					currentPlaystyleName = PlaystylesNames[i]
					currentPlaystyleIndex = i
				end

				DebugLines[6] = "BRAIN: IN COMBAT, PLAYSTYLE " .. currentPlaystyleName

				currentPlaystyle(dt, hum, root, victim, dist, hitDist, mePos, mePosGround, victimPos, victimCF)

				if ChatState ~= "LAGGING" then
					if charge then
						ChangeChatState("CHARGING", nil, Enum.ChatColor.Red)
					else
						ChangeChatState("COMBAT", nil, Enum.ChatColor.Red)
					end
				end
			else
				targetMove = victimPos

				if ChatState ~= "LAGGING" then
					ChangeChatState("PURSUING", nil, Enum.ChatColor.Green)
				end
			end
		else
			if ChatState ~= "LAGGING" and ChatState ~= "WON" then
				if idlePosition then
					ChangeChatState("WALKING", nil, Enum.ChatColor.Green)
				else
					ChangeChatState("IDLE", nil, Enum.ChatColor.White)
				end
			end
		end
	else
		DebugLines[6] = "BRAIN: POW! YOU ARE DEAD! PLAYSTYLE " .. currentPlaystyleName
		DebugLines[7] = "PLAYSTYLE: NO THOUGHTS CUZ DED LOL"

		idlePosition = nil

		if currentPlaystyleIndex > 0 then
			Determined(currentPlaystyleIndex)
		end

		if not hasDied then
			hasDied = true
			dynamicSwordName = CONFIG.SWORD_NAME

			if ChatState ~= "LAGGING" then
				if isResetting then
					ChangeChatState("RESETTING", nil, Enum.ChatColor.White)
					isResetting = false
				elseif currentVictim then
					ChangeChatState("DEAD", nil, Enum.ChatColor.Red)
				end
			end
		end

		currentVictim = nil
		cachedVictim = nil
		currentPlaystyle = nil
		currentPlaystyleName = "NULL"
		currentPlaystyleIndex = 0
	end

	local wos = ""

	for i, name in ipairs(PlaystylesNames) do
		wos ..= name .. " WOS IS " .. PlaystylesDeaths[i] .. "\n"
	end

	DebugLines[10] = wos
end