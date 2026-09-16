--!nonstrict
--[[
	Бабочки у клумб, листья с деревьев, утки у фонтана и зайчики на полянках.
	Места, количество и бюджет — Config/LiveWorld.

	Всё движется твинами (TweenService) по закреплённым деталям, без физики —
	docs/18-CONTENT-BACKLOG.md § 7 и docs/07-TECH-ARCH.md § 8. Ни одна бабочка
	и ни один лист ничего не задевают: у всех CanCollide, CanTouch и CanQuery
	выключены, сквозь них проходят, и по ним нельзя случайно «нажать».

	Бабочка — три детали: тельце и два крыла. Их положение хранит CFrameValue,
	а взмах крыльев — NumberValue; оба твинятся, и детали расставляются по их
	значениям. Так одна бабочка стоит два твина, а не твин на каждую деталь.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LiveWorld = require(Shared.Config.LiveWorld)
local Decor = require(Shared.Config.Decor)

local LiveWorldController = {}

local FOLDER_NAME = "AlphabetFallLiveWorld"
local WING_SIZE = Vector3.new(0.55, 0.05, 0.45)
local FLAP_ANGLE = math.rad(55)

local random = Random.new()
local folder: Folder? = nil
local activeLeaves = 0

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace
	folder = created
	return created
end

local function ghostPart(name: string, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function nearCamera(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < LiveWorld.VISIBLE_DISTANCE
end

-- ===== Бабочки ===================================================================

local function spawnButterfly(home: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Butterfly"
	local body = ghostPart("Body", Vector3.new(0.12, 0.12, 0.45), Color3.fromRGB(60, 45, 40))
	body.Parent = model
	local wings = {}
	for _, side in { -1, 1 } do
		local wing = ghostPart(`Wing_{side}`, WING_SIZE, color)
		wing.Parent = model
		wings[side] = wing
	end
	model.Parent = container()

	local where = Instance.new("CFrameValue")
	local flap = Instance.new("NumberValue")
	where.Parent = model
	flap.Parent = model

	local function layout()
		local at = where.Value
		body.CFrame = at
		local angle = flap.Value * FLAP_ANGLE
		for side, wing in wings do
			wing.CFrame = at
				* CFrame.new(side * 0.06, 0, 0)
				* CFrame.Angles(0, 0, side * angle)
				* CFrame.new(side * WING_SIZE.X / 2, 0, 0)
		end
	end
	where.Changed:Connect(layout)
	flap.Changed:Connect(layout)

	local function pointNearHome(): Vector3
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(1, LiveWorld.BUTTERFLY_RADIUS)
		local low, high = LiveWorld.BUTTERFLY_HEIGHT[1], LiveWorld.BUTTERFLY_HEIGHT[2]
		return home
			+ Vector3.new(math.cos(angle) * radius, random:NextNumber(low, high), math.sin(angle) * radius)
	end

	local start = pointNearHome()
	where.Value = CFrame.new(start)

	-- Крылья машут всегда: бесконечный твин туда-обратно.
	TweenService:Create(
		flap,
		TweenInfo.new(
			random:NextNumber(0.12, 0.18),
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		{ Value = 1 }
	):Play()

	task.spawn(function()
		while model.Parent do
			local from = where.Value.Position
			local target = pointNearHome()
			local seconds = random:NextNumber(1.8, 3.5)
			-- Смотрит туда, куда летит; тихо висит на месте, если камера далеко.
			if nearCamera(from) and (target - from).Magnitude > 0.1 then
				local goal = CFrame.lookAt(target, target + (target - from).Unit)
				TweenService:Create(where, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Value = goal })
					:Play()
			end
			task.wait(seconds + random:NextNumber(0.2, 1.2))
		end
	end)
end

-- ===== Листья ====================================================================

local function dropLeaf(sources: { LiveWorld.LeafSource })
	if activeLeaves >= LiveWorld.LEAVES_AT_ONCE or #sources == 0 then
		return
	end
	local source = sources[random:NextInteger(1, #sources)]
	if not nearCamera(source.position) then
		return
	end

	local angle = random:NextNumber(0, math.pi * 2)
	local radius = random:NextNumber(0, source.spread)
	local top = source.position
		+ Vector3.new(math.cos(angle) * radius, source.height, math.sin(angle) * radius)
	local drift = Vector3.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3))
	local ground = Vector3.new(top.X, source.position.Y + 0.1, top.Z) + drift

	local colors = LiveWorld.LEAF_COLORS
	local leaf = ghostPart("Leaf", Vector3.new(0.5, 0.05, 0.35), colors[random:NextInteger(1, #colors)])
	leaf.CFrame = CFrame.new(top) * CFrame.Angles(random:NextNumber(0, 3), random:NextNumber(0, 3), 0)
	leaf.Parent = container()
	activeLeaves += 1

	local low, high = LiveWorld.LEAF_FALL_SECONDS[1], LiveWorld.LEAF_FALL_SECONDS[2]
	local seconds = random:NextNumber(low, high)
	-- Лист ложится плашмя и поворачивается по пути вниз, а не падает камнем.
	local landed = CFrame.new(ground) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local fall = TweenService:Create(leaf, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { CFrame = landed })
	fall:Play()
	fall.Completed:Once(function()
		local fade = TweenService:Create(leaf, TweenInfo.new(1.5), { Transparency = 1 })
		fade:Play()
		fade.Completed:Once(function()
			leaf:Destroy()
			activeLeaves -= 1
		end)
	end)
end

-- ===== Зверьки ===================================================================

--[[
	Зверёк — набор деталей со смещениями от «корня». Каждый кадр корень
	считается заново, и детали ставятся по нему: восемь зверьков — это
	несколько десятков присвоений CFrame, дешевле любого твина.
]]
type Piece = { part: BasePart, offset: CFrame }
type Critter = { model: Model, pieces: { Piece } }

local function critter(name: string, recipe: { any }, scale: number): Critter
	local model = Instance.new("Model")
	model.Name = name
	local pieces = {}
	for _, item in recipe do
		local part = ghostPart(item[1], item[2] * scale, item[4])
		part.Shape = item[5] or Enum.PartType.Ball
		part.Parent = model
		local offset = item[3]
		table.insert(pieces, { part = part, offset = offset.Rotation + offset.Position * scale })
	end
	model.Parent = container()
	return { model = model, pieces = pieces }
end

local function place(animal: Critter, root: CFrame)
	for _, piece in animal.pieces do
		piece.part.CFrame = root * piece.offset
	end
end

local EYE = Color3.fromRGB(30, 30, 40)

local function duckRecipe(body: Color3): { any }
	return {
		{ "Body", Vector3.new(1.4, 1.1, 1.9), CFrame.new(0, 0.55, 0), body },
		{ "Tail", Vector3.new(0.6, 0.5, 0.6), CFrame.new(0, 0.8, 0.9), body },
		{ "Head", Vector3.new(0.85, 0.85, 0.85), CFrame.new(0, 1.35, -0.75), body },
		{
			"Beak",
			Vector3.new(0.45, 0.16, 0.45),
			CFrame.new(0, 1.25, -1.25),
			Color3.fromRGB(250, 160, 50),
			Enum.PartType.Block,
		},
		{ "EyeL", Vector3.one * 0.14, CFrame.new(-0.3, 1.45, -1.05), EYE },
		{ "EyeR", Vector3.one * 0.14, CFrame.new(0.3, 1.45, -1.05), EYE },
	}
end

local BUNNY_COATS = {
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(190, 160, 130),
	Color3.fromRGB(170, 170, 180),
	Color3.fromRGB(225, 200, 170),
}

local function bunnyRecipe(coat: Color3): { any }
	return {
		{ "Body", Vector3.new(1.3, 1.2, 1.6), CFrame.new(0, 0.6, 0), coat },
		{ "Head", Vector3.new(1, 1, 1), CFrame.new(0, 1.2, -0.75), coat },
		{ "EarL", Vector3.new(0.25, 1, 0.15), CFrame.new(-0.22, 2, -0.65) * CFrame.Angles(0, 0, 0.12), coat },
		{ "EarR", Vector3.new(0.25, 1, 0.15), CFrame.new(0.22, 2, -0.65) * CFrame.Angles(0, 0, -0.12), coat },
		{ "Tail", Vector3.one * 0.45, CFrame.new(0, 0.7, 0.8), Color3.fromRGB(255, 255, 255) },
		{ "Nose", Vector3.one * 0.14, CFrame.new(0, 1.15, -1.25), Color3.fromRGB(240, 140, 160) },
		{ "EyeL", Vector3.one * 0.14, CFrame.new(-0.28, 1.35, -1.15), EYE },
		{ "EyeR", Vector3.one * 0.14, CFrame.new(0.28, 1.35, -1.15), EYE },
	}
end

local function localRoot(): BasePart?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Утиная семья ходит гуськом вокруг фонтана; подбежал близко — все подпрыгивают.
local function startDucks(): (number) -> ()
	local loop = LiveWorld.DUCK_LOOP
	local ground = Decor.groundY(loop.center.X, loop.center.Y)
	local ducks = {}
	for index = 1, LiveWorld.DUCK_COUNT do
		local mother = index == 1
		table.insert(
			ducks,
			critter(
				if mother then "Duck" else "Duckling",
				duckRecipe(if mother then Color3.fromRGB(250, 250, 245) else Color3.fromRGB(255, 225, 90)),
				if mother then 1 else 0.55
			)
		)
	end

	local startedAt = os.clock()
	local flutterUntil = 0
	return function(now: number)
		local center = Vector3.new(loop.center.X, ground, loop.center.Y)
		if not nearCamera(center) then
			return
		end
		local root = localRoot()
		if root and (root.Position - center).Magnitude < loop.radius + 4 and now > flutterUntil + 3 then
			flutterUntil = now + 0.8
		end
		local lead = (now - startedAt) / LiveWorld.DUCK_LAP_SECONDS * math.pi * 2
		for index, duck in ducks do
			local angle = lead - (index - 1) * LiveWorld.DUCK_GAP
			local at = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * loop.radius
			local ahead = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			local waddle = math.sin(now * 9 + index) * 0.12
			local hop = if now < flutterUntil then math.abs(math.sin((now + index * 0.2) * 12)) * 0.8 else 0
			place(duck, CFrame.lookAt(at, at + ahead) * CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, waddle))
		end
	end
end

-- Зайчик пасётся у своей полянки короткими прыжками; подбежал — отпрыгивает.
local function startBunny(index: number): (number) -> ()
	local home = LiveWorld.bunnyHome(index)
	local animal = critter("Bunny", bunnyRecipe(BUNNY_COATS[(index - 1) % #BUNNY_COATS + 1]), 1)
	local from = home
	local to = home
	local hopStart, hopSeconds = 0, 0.4
	local facing = Vector3.new(0, 0, -1)
	local restUntil = os.clock() + random:NextNumber(0.5, 3)
	local hopsLeft = 0

	local function clampToHome(point: Vector3): Vector3
		local offset = Vector3.new(point.X - home.X, 0, point.Z - home.Z)
		if offset.Magnitude > LiveWorld.BUNNY_RADIUS then
			offset = offset.Unit * LiveWorld.BUNNY_RADIUS
		end
		return home + offset
	end

	local function hopToward(target: Vector3, now: number, seconds: number)
		from = to
		local step = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
		if step.Magnitude > 2.5 then
			step = step.Unit * 2.5
		end
		to = clampToHome(from + step)
		if step.Magnitude > 0.05 then
			facing = step.Unit
		end
		hopStart, hopSeconds = now, seconds
	end

	local goal = home
	return function(now: number)
		if not nearCamera(home) then
			return
		end
		local t = math.clamp((now - hopStart) / hopSeconds, 0, 1)
		if t >= 1 then
			local root = localRoot()
			local scared = root ~= nil and (root.Position - to).Magnitude < LiveWorld.BUNNY_SCARE_DISTANCE
			if scared then
				local away = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
				if away.Magnitude < 0.1 then
					away = Vector3.new(1, 0, 0)
				end
				hopToward(to + away.Unit * 3, now, 0.28)
			elseif hopsLeft > 0 then
				hopsLeft -= 1
				hopToward(goal, now, 0.4)
			elseif now > restUntil then
				local angle = random:NextNumber(0, math.pi * 2)
				goal = home
					+ Vector3.new(math.cos(angle), 0, math.sin(angle))
						* random:NextNumber(0, LiveWorld.BUNNY_RADIUS)
				hopsLeft = random:NextInteger(2, 4)
				restUntil = now + random:NextNumber(2, 5)
			end
			t = math.clamp((now - hopStart) / hopSeconds, 0, 1)
		end
		local position = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 1.1, 0)
		-- Ушами шевелит и в покое: видно, что живой.
		local twitch = math.sin(now * 3 + index) * 0.03
		place(animal, CFrame.lookAt(position, position + facing) * CFrame.Angles(twitch, 0, 0))
	end
end

function LiveWorldController.init()
	--[[
		Ждём декор: расстановка общая, но деревья и клумбы приедут не сразу.
		Координаты при этом из конфига, так что ждать нужно только саму площадь.
	]]
	task.spawn(function()
		workspace:WaitForChild("Hub", 60)

		local colors = LiveWorld.BUTTERFLY_COLORS
		local index = 0
		for _, home in LiveWorld.butterflyHomes() do
			for _ = 1, LiveWorld.BUTTERFLIES_PER_BED do
				index += 1
				spawnButterfly(home, colors[(index - 1) % #colors + 1])
			end
		end

		-- Зверьки: утки у фонтана и зайчики на полянках, один общий кадровый цикл.
		local animators = { startDucks() }
		for bunny = 1, #LiveWorld.BUNNY_HOMES do
			table.insert(animators, startBunny(bunny))
		end
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			for _, animate in animators do
				animate(now)
			end
		end)

		local sources = LiveWorld.leafSources()
		while true do
			task.wait(LiveWorld.LEAF_INTERVAL)
			dropLeaf(sources)
		end
	end)
end

return LiveWorldController
