--!nonstrict
--[[
	Бабочки у клумб, листья с деревьев, утки у фонтана, зайчики на полянках,
	карпы в пруду под мостиком, белки на деревьях, воздушные змеи над лугами
	и радуга над парком.
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

-- ===== Карпы в пруду ===============================================================

-- Тело карпа — брусок со сферическим мешем: шар в Roblox не бывает вытянутым.
local function oval(name: string, size: Vector3, color: Color3): BasePart
	local part = ghostPart(name, size, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

type Koi = { pieces: { Piece }, phase: number, speed: number, jumpStart: number? }

local function makeKoi(index: number): Koi
	local colors = LiveWorld.KOI_COLORS[(index - 1) % #LiveWorld.KOI_COLORS + 1]
	local model = Instance.new("Model")
	model.Name = "Koi"
	model.Parent = container()
	local recipe = {
		{ oval("Body", Vector3.new(0.7, 0.4, 1.9), colors[1]), CFrame.new() },
		{ oval("Spot", Vector3.new(0.5, 0.2, 0.7), colors[2]), CFrame.new(0, 0.13, -0.25) },
		{ oval("Tail", Vector3.new(0.12, 0.5, 0.8), colors[1]), CFrame.new(0, 0.05, 1.15) },
		{
			oval("FinL", Vector3.new(0.5, 0.06, 0.3), colors[2]),
			CFrame.new(-0.4, -0.05, -0.3) * CFrame.Angles(0, 0.5, 0),
		},
		{
			oval("FinR", Vector3.new(0.5, 0.06, 0.3), colors[2]),
			CFrame.new(0.4, -0.05, -0.3) * CFrame.Angles(0, -0.5, 0),
		},
	}
	local pieces = {}
	for _, item in recipe do
		item[1].Parent = model
		table.insert(pieces, { part = item[1], offset = item[2] })
	end
	return {
		pieces = pieces,
		phase = (index - 1) / LiveWorld.KOI_PER_POND * math.pi * 2,
		speed = 1 + index * 0.08,
	}
end

-- Кольцо брызг там, где карп ушёл обратно в воду.
local function splash(at: Vector3)
	local ring = ghostPart("Splash", Vector3.new(0.08, 0.6, 0.6), Color3.fromRGB(235, 250, 255))
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.2
	ring.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = container()
	local tween =
		TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.08, 4, 4),
			Transparency = 1,
		})
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
	tween:Play()
end

local function startPond(pond: LiveWorld.Pond): (number) -> ()
	local fish = {}
	for index = 1, LiveWorld.KOI_PER_POND do
		table.insert(fish, makeKoi(index))
	end
	local path = Decor.KOI_PATH
	-- Верх воды на 0.17: спина карпа чуть над ней, как у настоящего у поверхности.
	local surface = 0.2
	local nextJump = os.clock() + random:NextNumber(3, 6)

	return function(now: number)
		if not nearCamera(pond.cframe.Position) then
			return
		end
		if now >= nextJump then
			local jumper = fish[random:NextInteger(1, #fish)]
			if not jumper.jumpStart then
				jumper.jumpStart = now
			end
			nextJump = now + random:NextNumber(LiveWorld.KOI_JUMP_EVERY[1], LiveWorld.KOI_JUMP_EVERY[2])
		end

		for _, koi in fish do
			local angle = now / LiveWorld.KOI_LAP_SECONDS * math.pi * 2 * koi.speed + koi.phase
			local x, z = math.cos(angle) * path.radiusX, math.sin(angle) * path.radiusZ
			local heading =
				Vector3.new(-math.sin(angle) * path.radiusX, 0, math.cos(angle) * path.radiusZ).Unit
			local spot = Vector3.new(x, surface, z)
			-- Хвост виляет: тело чуть поворачивается туда-сюда.
			local frame = CFrame.lookAt(spot, spot + heading)
				* CFrame.Angles(0, math.sin(now * 7 + koi.phase) * 0.18, 0)

			if koi.jumpStart then
				local t = (now - koi.jumpStart) / LiveWorld.KOI_JUMP_SECONDS
				if t >= 1 then
					koi.jumpStart = nil
					splash((pond.cframe * frame).Position)
				else
					-- Дуга вверх, к концу прыжка носом вниз.
					local lift = math.sin(t * math.pi) * LiveWorld.KOI_JUMP_HEIGHT
					frame = frame * CFrame.new(0, lift, 0) * CFrame.Angles(math.rad(50 - 100 * t), 0, 0)
				end
			end

			local world = pond.cframe * frame
			for _, piece in koi.pieces do
				piece.part.CFrame = world * piece.offset
			end
		end
	end
end

-- ===== Воздушные змеи ==============================================================

--[[
	Змей — ромб из двух цветов с крестовиной, привязанный нитью (Beam) к колышку.
	Висит по ветру и ходит восьмёркой; хвост из бантиков догоняет змея с запаздыванием,
	поэтому вьётся, а не висит палкой. Один змей — одна «вещь» в бюджете кадра.
]]
local function startKite(index: number): (number) -> ()
	local spec = LiveWorld.KITES[index]
	local stake = LiveWorld.kiteStake(index)
	local size = LiveWorld.KITE_SIZE
	local model = Instance.new("Model")
	model.Name = "Kite"
	model.Parent = container()

	local post = ghostPart("KiteStake", Vector3.new(0.35, 1.6, 0.35), Color3.fromRGB(150, 110, 70))
	post.CFrame = CFrame.new(stake + Vector3.new(0, 0.8, 0))
	post.Parent = model
	local reel = ghostPart("KiteReel", Vector3.new(0.5, 0.9, 0.9), spec.colors[1])
	reel.Shape = Enum.PartType.Cylinder
	reel.CFrame = CFrame.new(stake + Vector3.new(0, 1.3, 0))
	reel.Parent = model

	-- Ромб: квадрат, повёрнутый на 45°, и на нём ромб поменьше другого цвета.
	local sail =
		ghostPart("KiteSail", Vector3.new(size / math.sqrt(2), size / math.sqrt(2), 0.12), spec.colors[1])
	sail.Parent = model
	local inner = ghostPart("KiteInner", Vector3.new(size * 0.38, size * 0.38, 0.14), spec.colors[2])
	inner.Parent = model
	local spar = ghostPart("KiteSpar", Vector3.new(0.12, size, 0.2), Color3.fromRGB(120, 85, 60))
	spar.Parent = model
	local cross = ghostPart("KiteCross", Vector3.new(size * 0.8, 0.12, 0.2), Color3.fromRGB(120, 85, 60))
	cross.Parent = model

	local bows = {}
	for bow = 1, LiveWorld.KITE_TAIL do
		local part = ghostPart("KiteBow", Vector3.new(0.9, 0.5, 0.2), spec.colors[(bow % 2) + 1])
		part.Parent = model
		table.insert(bows, part)
	end

	local from = Instance.new("Attachment")
	from.Position = Vector3.new(0, 0.5, 0)
	from.Parent = reel
	local to = Instance.new("Attachment")
	to.Parent = spar
	local line = Instance.new("Beam")
	line.Attachment0 = from
	line.Attachment1 = to
	line.Width0 = 0.08
	line.Width1 = 0.08
	line.Color = ColorSequence.new(Color3.fromRGB(250, 250, 250))
	line.FaceCamera = true
	line.Segments = 12
	line.CurveSize0 = -6 -- нить провисает к земле
	line.Parent = reel

	local wind = LiveWorld.WIND.Unit
	local side = Vector3.new(-wind.Z, 0, wind.X)
	local trail: { Vector3 } = {}
	local phase = index * 2.1
	return function(now: number)
		local camera = workspace.CurrentCamera
		if not camera or (camera.CFrame.Position - stake).Magnitude > LiveWorld.KITE_VISIBLE then
			return
		end
		-- Восьмёрка: вбок с одной частотой, вверх-вниз с двойной.
		local t = now * 0.45 + phase
		local center = stake
			+ wind * LiveWorld.KITE_REACH
			+ Vector3.new(0, LiveWorld.KITE_HEIGHT, 0)
			+ side * math.sin(t) * 5
			+ Vector3.new(0, math.sin(t * 2) * 2.2, 0)
		-- Змей смотрит лицом на колышек, чуть наклонён по ветру и качается.
		local face = CFrame.lookAt(center, stake + Vector3.new(0, LiveWorld.KITE_HEIGHT * 0.4, 0))
			* CFrame.Angles(0, 0, math.sin(t) * 0.35)
		sail.CFrame = face * CFrame.Angles(0, 0, math.rad(45))
		inner.CFrame = face * CFrame.new(0, 0.3, -0.05) * CFrame.Angles(0, 0, math.rad(45))
		spar.CFrame = face * CFrame.new(0, 0, -0.12)
		cross.CFrame = face * CFrame.new(0, size * 0.15, -0.12)

		-- Хвост: каждый бантик тянется к предыдущему, на шаг ниже и дальше по ветру.
		local anchor = (face * CFrame.new(0, -size / 2, 0)).Position
		for bow, part in bows do
			local target = anchor
				+ wind * 1.1
				+ Vector3.new(0, -1, 0)
				+ side * math.sin(t * 3 - bow * 0.7) * 0.5
			local previous = trail[bow] or target
			local current = previous:Lerp(target, 0.25)
			trail[bow] = current
			part.CFrame = CFrame.lookAt(current, current + wind)
			anchor = current
		end
	end
end

-- ===== Белки =======================================================================

local SQUIRREL_FUR = Color3.fromRGB(200, 110, 55)

local function squirrelRecipe(): { any }
	local belly = Color3.fromRGB(245, 215, 175)
	return {
		{ "Body", Vector3.new(0.8, 0.9, 1.2), CFrame.new(0, 0.55, 0), SQUIRREL_FUR },
		{ "Belly", Vector3.new(0.55, 0.65, 0.5), CFrame.new(0, 0.55, -0.4), belly },
		{ "Head", Vector3.new(0.7, 0.65, 0.7), CFrame.new(0, 1.05, -0.55), SQUIRREL_FUR },
		{
			"EarL",
			Vector3.new(0.18, 0.35, 0.12),
			CFrame.new(-0.2, 1.45, -0.5),
			SQUIRREL_FUR,
			Enum.PartType.Block,
		},
		{
			"EarR",
			Vector3.new(0.18, 0.35, 0.12),
			CFrame.new(0.2, 1.45, -0.5),
			SQUIRREL_FUR,
			Enum.PartType.Block,
		},
		{ "EyeL", Vector3.one * 0.12, CFrame.new(-0.2, 1.12, -0.86), EYE },
		{ "EyeR", Vector3.one * 0.12, CFrame.new(0.2, 1.12, -0.86), EYE },
		{ "Nose", Vector3.one * 0.1, CFrame.new(0, 1, -0.92), Color3.fromRGB(60, 40, 35) },
		-- Пушистый хвост вопросом: три шара всё выше и дальше назад.
		{ "Tail1", Vector3.new(0.6, 0.8, 0.6), CFrame.new(0, 0.7, 0.7), SQUIRREL_FUR },
		{ "Tail2", Vector3.new(0.75, 0.9, 0.7), CFrame.new(0, 1.35, 0.95), SQUIRREL_FUR },
		{ "Tail3", Vector3.new(0.7, 0.75, 0.65), CFrame.new(0, 1.95, 0.75), Color3.fromRGB(215, 130, 70) },
		{ "Nut", Vector3.new(0.3, 0.36, 0.3), CFrame.new(0, 0.85, -0.85), Color3.fromRGB(150, 100, 55) },
	}
end

--[[
	Белка живёт у нескольких деревьев. Цикл: сидит у ствола и грызёт орех,
	взбегает по стволу спиралью, сидит наверху, сбегает, перебегает к другому
	дереву. Ребёнок подбежал — бросает всё и удирает вверх.
]]
local function startSquirrel(index: number, trees: { LiveWorld.SquirrelTree }): (number) -> ()
	local animal = critter("Squirrel", squirrelRecipe(), 1.3)
	local nut = animal.model:FindFirstChild("Nut") :: BasePart
	local treeIndex = (index - 1) % #trees + 1
	local mode = "sit"
	local modeStart = os.clock() + index
	local modeSeconds = random:NextNumber(2, 4)
	local height = 0 -- на какой высоте ствола сидит
	local angle = random:NextNumber(0, math.pi * 2) -- с какой стороны ствола
	local runFrom, runTo = Vector3.zero, Vector3.zero

	local function tree(): LiveWorld.SquirrelTree
		return trees[treeIndex]
	end

	local function foot(at: LiveWorld.SquirrelTree, a: number): Vector3
		return at.position + Vector3.new(math.cos(a), 0, math.sin(a)) * (at.trunk + 0.5)
	end

	local function setMode(name: string, now: number, seconds: number)
		mode, modeStart, modeSeconds = name, now, seconds
	end

	return function(now: number)
		local here = tree()
		if not nearCamera(here.position) then
			return
		end
		local t = math.clamp((now - modeStart) / modeSeconds, 0, 1)
		local root = localRoot()
		local scared = root ~= nil
			and (root.Position - foot(here, angle)).Magnitude < LiveWorld.SQUIRREL_SCARE_DISTANCE
		if scared and mode == "sit" then
			-- Удирает вверх вдвое быстрее обычного.
			setMode("up", now, here.climb / (LiveWorld.SQUIRREL_CLIMB * 2))
			t = 0
		end

		if t >= 1 then
			if mode == "sit" then
				setMode("up", now, here.climb / LiveWorld.SQUIRREL_CLIMB)
			elseif mode == "up" then
				height = here.climb
				setMode("perch", now, random:NextNumber(3, 6))
			elseif mode == "perch" then
				setMode("down", now, here.climb / (LiveWorld.SQUIRREL_CLIMB * 1.4))
			elseif mode == "down" then
				height = 0
				local next = treeIndex
				while next == treeIndex and #trees > 1 do
					next = random:NextInteger(1, #trees)
				end
				runFrom = foot(here, angle)
				treeIndex = next
				angle = random:NextNumber(0, math.pi * 2)
				runTo = foot(tree(), angle)
				setMode("run", now, math.max(1, (runTo - runFrom).Magnitude / LiveWorld.SQUIRREL_SPEED))
			elseif mode == "run" then
				setMode("sit", now, random:NextNumber(3, 6))
			end
			t = 0
			here = tree()
		end

		nut.Transparency = if mode == "sit" then 0 else 1
		local frame
		if mode == "run" then
			-- Бежит скачками: дуги по полстуда.
			local at = runFrom:Lerp(runTo, t) + Vector3.new(0, math.abs(math.sin(t * 30)) * 0.5, 0)
			local ahead = (runTo - runFrom) * Vector3.new(1, 0, 1)
			frame = CFrame.lookAt(at, at + (if ahead.Magnitude > 0.01 then ahead.Unit else Vector3.zAxis))
		elseif mode == "sit" then
			-- Сидит у ствола спиной к нему и грызёт: голова кивает.
			local at = foot(here, angle)
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			frame = CFrame.lookAt(at, at + out) * CFrame.Angles(math.sin(now * 14) * 0.08, 0, 0)
		else
			-- По стволу: спиралью, головой вверх или вниз, брюшком к стволу.
			local y = if mode == "up"
				then height + (here.climb - height) * t
				elseif mode == "down" then here.climb * (1 - t)
				else here.climb
			if mode == "up" and t >= 1 then
				height = here.climb
			end
			local turn = angle + y * 0.35
			local out = Vector3.new(math.cos(turn), 0, math.sin(turn))
			local at = here.position + out * (here.trunk + 0.35) + Vector3.new(0, y, 0)
			local look = if mode == "down" then -Vector3.yAxis else Vector3.yAxis
			frame = CFrame.lookAt(at, at + look, out)
			if mode == "perch" then
				-- Наверху сидит боком и вертит хвостом.
				frame = CFrame.lookAt(at, at + Vector3.new(-out.Z, 0, out.X))
					* CFrame.Angles(0, math.sin(now * 3) * 0.3, 0)
			end
		end
		place(animal, frame)
	end
end

-- ===== Радуга ======================================================================

local rainbow: { beams: { Beam }, fade: NumberValue }? = nil
local rainbowToken = 0

--[[
	Семь лучей-дуг. Луч изгибается кривой Безье: у обоих концов вектор кривизны
	смотрит вверх, и луч встаёт аркой. Концы у земли прозрачные — радуга
	растворяется, а не упирается в траву.
]]
local function buildRainbow()
	local anchor = ghostPart("Rainbow", Vector3.one, Color3.new(1, 1, 1))
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(LiveWorld.RAINBOW_CENTER)
	anchor.Parent = container()

	local fade = Instance.new("NumberValue")
	fade.Value = 1
	local beams = {}
	-- Ось вложения (X) смотрит вверх: вдоль неё и гнётся луч.
	local up = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	for index, color in LiveWorld.RAINBOW_COLORS do
		local span = LiveWorld.RAINBOW_SPAN - (index - 1) * LiveWorld.RAINBOW_BAND
		local height = LiveWorld.RAINBOW_HEIGHT * span / LiveWorld.RAINBOW_SPAN
		local left = Instance.new("Attachment")
		left.CFrame = CFrame.new(-span, 0, 0) * up
		left.Parent = anchor
		local right = Instance.new("Attachment")
		right.CFrame = CFrame.new(span, 0, 0) * up
		right.Parent = anchor

		local beam = Instance.new("Beam")
		beam.Attachment0 = left
		beam.Attachment1 = right
		-- Вершина кубической кривой — три четверти от кривизны.
		beam.CurveSize0 = height / 0.75
		beam.CurveSize1 = -height / 0.75
		beam.Width0 = LiveWorld.RAINBOW_BAND + 0.4
		beam.Width1 = LiveWorld.RAINBOW_BAND + 0.4
		beam.Segments = 48
		beam.FaceCamera = true
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = 0.4
		beam.Enabled = false
		beam.Parent = anchor
		table.insert(beams, beam)
	end

	local function apply()
		local base = 0.35 + 0.65 * fade.Value
		for _, beam in beams do
			beam.Enabled = fade.Value < 0.99
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.18, base),
				NumberSequenceKeypoint.new(0.82, base),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end
	fade.Changed:Connect(apply)
	apply()
	rainbow = { beams = beams, fade = fade }
end

--[[
	Показать радугу на seconds секунд: проявляется за три секунды, тает за пять.
	Повторный вызов, пока она видна, продлевает её, а не мигает заново.
]]
function LiveWorldController.rainbow(seconds: number?)
	if not rainbow then
		buildRainbow()
	end
	local current = rainbow :: any
	rainbowToken += 1
	local token = rainbowToken
	TweenService:Create(current.fade, TweenInfo.new(3), { Value = 0 }):Play()
	task.delay(seconds or LiveWorld.RAINBOW_SECONDS, function()
		if token == rainbowToken then
			TweenService:Create(current.fade, TweenInfo.new(5), { Value = 1 }):Play()
		end
	end)
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
		for _, pond in LiveWorld.ponds() do
			table.insert(animators, startPond(pond))
		end
		for kite = 1, #LiveWorld.KITES do
			table.insert(animators, startKite(kite))
		end
		local trees = LiveWorld.squirrelTrees()
		if #trees > 0 then
			for squirrel = 1, LiveWorld.SQUIRREL_COUNT do
				table.insert(animators, startSquirrel(squirrel, trees))
			end
		end

		-- Радуга изредка сама по себе; после трёх звёзд её зовёт ChallengeController.
		task.spawn(function()
			while true do
				task.wait(random:NextNumber(LiveWorld.RAINBOW_EVERY[1], LiveWorld.RAINBOW_EVERY[2]))
				LiveWorldController.rainbow()
			end
		end)
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
