--!strict
--[[
	Строит катания парка (Config/Rides): эстакаду с паровозиком и станцией
	и колесо обозрения. Сервер ставит детали на исходные места — поезд у станции,
	колесо с первой кабиной внизу — и вешает метки. Едут они на клиенте
	(Controllers/RideController), по серверным часам.

	Паровозик — деревянная игрушка из кубиков: красные колёса, синий котёл,
	жёлтая будка, дым из трубы, в вагончиках кубики с буквами А, Б, В.
	Модели из Creator Store не подошли: игрушечный поезд там был размером
	с ладонь, а его корпус из цельных деталей в файл не записывается.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rides = require(Shared.Config.Rides)

local RidesBuilder = {}

local WOOD = Color3.fromRGB(205, 160, 105)
local WOOD_DARK = Color3.fromRGB(150, 105, 70)
local RED = Color3.fromRGB(225, 70, 65)
local BLUE = Color3.fromRGB(70, 130, 220)
local YELLOW = Color3.fromRGB(250, 205, 70)
local GREEN = Color3.fromRGB(90, 190, 110)
local CREAM = Color3.fromRGB(250, 243, 225)

local WAGON_COLORS = { GREEN, Color3.fromRGB(240, 140, 60), Color3.fromRGB(170, 110, 220) }
local WAGON_LETTERS = { "А", "Б", "В" }
local CABIN_COLORS = {
	Color3.fromRGB(240, 90, 90),
	Color3.fromRGB(245, 150, 70),
	Color3.fromRGB(250, 210, 80),
	Color3.fromRGB(120, 205, 110),
	Color3.fromRGB(80, 190, 220),
	Color3.fromRGB(90, 130, 230),
	Color3.fromRGB(160, 110, 220),
	Color3.fromRGB(230, 120, 190),
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = parent
	return p
end

-- Цилиндр вдоль оси X кадра at.
local function cylinder(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	at: CFrame,
	color: Color3
): Part
	local p = part(parent, name, Vector3.new(length, diameter, diameter), at, color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Брус от точки до точки: ноги колеса, столбы, спицы.
local function beam(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	thickness: number,
	color: Color3
): Part
	local length = (to - from).Magnitude
	return part(
		parent,
		name,
		Vector3.new(thickness, thickness, length),
		CFrame.lookAt((from + to) / 2, to),
		color
	)
end

local function letterFace(target: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.3
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.Parent = gui
end

-- ===== Паровозик =====

-- Колёсная пара: два красных колеса по бокам на высоте полотна.
local function wheels(car: Model, frame: CFrame, count: number, length: number)
	for index = 1, count do
		local z = (index - (count + 1) / 2) * (length / count)
		for _, side in { -1, 1 } do
			cylinder(car, "Wheel", 0.6, 2.1, frame * CFrame.new(side * 2.3, 1.05, z), RED).CanCollide = false
			cylinder(car, "Hub", 0.7, 0.7, frame * CFrame.new(side * 2.35, 1.05, z), YELLOW).CanCollide =
				false
		end
	end
end

local function locomotive(car: Model, frame: CFrame)
	part(car, "Chassis", Vector3.new(4.4, 0.8, 8), frame * CFrame.new(0, 1.6, 0), WOOD)
	wheels(car, frame, 3, 7)
	-- Котёл вперёд по ходу: вперёд — это -Z кадра.
	cylinder(
		car,
		"Boiler",
		5,
		3.2,
		frame * CFrame.new(0, 3.6, -1.4) * CFrame.Angles(0, math.rad(90), 0),
		BLUE
	)
	cylinder(
		car,
		"BoilerFront",
		0.4,
		3.4,
		frame * CFrame.new(0, 3.6, -4) * CFrame.Angles(0, math.rad(90), 0),
		RED
	)
	part(car, "Cab", Vector3.new(4.2, 3.6, 3), frame * CFrame.new(0, 3.8, 2.4), YELLOW)
	part(car, "CabRoof", Vector3.new(4.8, 0.5, 3.6), frame * CFrame.new(0, 5.85, 2.4), RED)
	local chimney = cylinder(
		car,
		"Chimney",
		2.2,
		1.3,
		frame * CFrame.new(0, 6.1, -2.8) * CFrame.Angles(0, 0, math.rad(90)),
		WOOD_DARK
	)
	cylinder(
		car,
		"ChimneyCap",
		0.5,
		1.9,
		frame * CFrame.new(0, 7.3, -2.8) * CFrame.Angles(0, 0, math.rad(90)),
		RED
	)
	part(car, "Bumper", Vector3.new(4.6, 0.8, 0.6), frame * CFrame.new(0, 1.6, -4.2), RED)

	-- Дым: белые клубы из трубы. Один излучатель на весь поезд — дёшево.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.4, 2)
	smoke.Rate = 6
	smoke.Speed = NumberRange.new(4, 6)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.EmissionDirection = Enum.NormalId.Right -- ось X цилиндра смотрит вверх
	smoke.Parent = chimney
end

local function wagon(car: Model, frame: CFrame, index: number)
	local color = WAGON_COLORS[(index - 1) % #WAGON_COLORS + 1]
	part(car, "Chassis", Vector3.new(4.4, 0.8, 6.6), frame * CFrame.new(0, 1.6, 0), WOOD)
	wheels(car, frame, 2, 5)
	-- Кузов-корытце: дно и четыре бортика, сесть внутрь можно.
	part(car, "Floor", Vector3.new(4.2, 0.4, 6.2), frame * CFrame.new(0, 2.2, 0), color)
	for _, side in { -1, 1 } do
		local wall =
			part(car, "Side", Vector3.new(0.4, 1.8, 6.2), frame * CFrame.new(side * 2, 3.1, 0), color)
		letterFace(
			wall,
			if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left,
			WAGON_LETTERS[index] or "",
			CREAM
		)
		part(car, "End", Vector3.new(4.2, 1.8, 0.4), frame * CFrame.new(0, 3.1, side * 2.9), color)
	end
	-- Кубик с буквой на заднем бортике: игрушка из набора «Азбука».
	local cube = part(car, "LetterCube", Vector3.new(1.8, 1.8, 1.8), frame * CFrame.new(1, 3.4, 2), CREAM)
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Top, Enum.NormalId.Right } do
		letterFace(cube, face, WAGON_LETTERS[index] or "", color)
	end
	part(car, "Coupler", Vector3.new(0.5, 0.5, 2.2), frame * CFrame.new(0, 1.6, -4.2), WOOD_DARK)
end

local function buildTrain(parent: Instance)
	--[[
		Поезд едет по всему кольцу, а у места включён стриминг: без Persistent
		клиент получил бы поезд, только стоя у станции, и видел бы его пустое
		место везде, куда тот уехал.
	]]
	local train = Instance.new("Model")
	train.Name = "Train"
	train.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	train.Parent = parent
	local head = Rides.trainAt(0)
	for index = 1, Rides.TRAIN.cars do
		local car = Instance.new("Model")
		car.Name = `Car_{index}`
		car.Parent = train
		local frame = Rides.trackFrame(Rides.carAngle(head, index))
		if index == 1 then
			locomotive(car, frame)
		else
			wagon(car, frame, index - 1)
		end
		-- Опорная точка вагона: от неё клиент считает смещения деталей.
		car:SetAttribute("Home", frame)
		for _, descendant in car:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
			end
		end
	end
	CollectionService:AddTag(train, "AF_Train")
end

local function buildTrack(parent: Instance)
	local track = Instance.new("Model")
	track.Name = "Track"
	track.Parent = parent
	local spec = Rides.TRAIN
	for index = 1, spec.segments do
		local a = (index - 1) / spec.segments * math.pi * 2
		local b = index / spec.segments * math.pi * 2
		local from = Vector3.new(math.cos(a) * spec.radius, spec.height, math.sin(a) * spec.radius)
		local to = Vector3.new(math.cos(b) * spec.radius, spec.height, math.sin(b) * spec.radius)
		local length = (to - from).Magnitude + 0.4
		local at = CFrame.lookAt((from + to) / 2, to)
		--[[
			Полотно: твёрдая деревянная балка — по ней можно пройтись, и голова
			в неё не проваливается, — поверх два тёмных рельса. Поезд едет
			сквозь того, кто стоит на пути: вагоны без столкновений.
		]]
		part(track, "Beam", Vector3.new(5.2, 1.2, length), at * CFrame.new(0, -0.6, 0), WOOD)
		for _, side in { -1, 1 } do
			part(
				track,
				"Rail",
				Vector3.new(0.4, 0.3, length),
				at * CFrame.new(side * 1.6, 0.15, 0),
				WOOD_DARK
			).CanCollide =
				false
		end
	end

	--[[
		Столбы через pillarStep, кроме мест, где эстакада идёт над дорожкой к домам:
		там столб встал бы посреди дорожки. Над дорожкой — пролёт-арка.
	]]
	local circumference = 2 * math.pi * spec.radius
	local count = math.floor(circumference / spec.pillarStep)
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local nearestPath = math.abs(((angle + math.pi / 4) % (math.pi / 2)) - math.pi / 4) * spec.radius
		if nearestPath > 9 then
			local foot = Vector3.new(math.cos(angle) * spec.radius, 0, math.sin(angle) * spec.radius)
			local pillar = part(
				track,
				"Pillar",
				Vector3.new(1.6, spec.height - 1.2, 1.6),
				CFrame.new(foot + Vector3.new(0, (spec.height - 1.2) / 2, 0)),
				RED
			)
			pillar.CanCollide = true
		end
	end
	for pathIndex = 0, 3 do
		local angle = pathIndex * math.pi / 2
		local center =
			Vector3.new(math.cos(angle) * spec.radius, spec.height - 1.5, math.sin(angle) * spec.radius)
		local along = CFrame.lookAt(center, center + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
		part(track, "PathArch", Vector3.new(5.6, 0.6, 16), along, YELLOW).CanCollide = false
	end
end

local function buildStation(parent: Instance, index: number)
	local station = Instance.new("Model")
	station.Name = `Station_{index}`
	station.Parent = parent
	local spec = Rides.STATION
	local frame = Rides.stationFrame(index)
	local top = Rides.TRAIN.height + 0.4
	local base = CFrame.new(frame.Position.X, 0, frame.Position.Z) * frame.Rotation

	-- Платформа на ножках вровень с полом вагончиков.
	part(
		station,
		"Platform",
		Vector3.new(spec.platformWidth, 1, spec.platformLength),
		base * CFrame.new(0, top - 0.5, 0),
		CREAM
	)
	part(
		station,
		"Edge",
		Vector3.new(0.6, 0.2, spec.platformLength),
		base * CFrame.new(-spec.platformWidth / 2 + 0.3, top + 0.1, 0),
		YELLOW
	).CanCollide =
		false
	for _, z in { -1, 1 } do
		for _, x in { -1, 1 } do
			local leg = CFrame.new(
				x * (spec.platformWidth / 2 - 0.8),
				(top - 1) / 2,
				z * (spec.platformLength / 2 - 1)
			)
			part(station, "Leg", Vector3.new(1.2, top - 1, 1.2), base * leg, WOOD_DARK)
		end
	end
	-- Пандус с земли на платформу вдоль пути, с перилами.
	local rampRise = top
	local rampLength = spec.rampLength
	local slope = math.atan2(rampRise, rampLength)
	local rampAt = base
		* CFrame.new(0, rampRise / 2, spec.platformLength / 2 + rampLength / 2)
		* CFrame.Angles(slope, 0, 0)
	part(
		station,
		"Ramp",
		Vector3.new(spec.platformWidth - 1, 0.8, math.sqrt(rampRise ^ 2 + rampLength ^ 2) + 0.6),
		rampAt,
		WOOD
	)
	-- Навес: столбики по дальнему от пути краю и крыша в полоску.
	for _, z in { -1, 1 } do
		part(
			station,
			"Post",
			Vector3.new(0.5, spec.roofHeight, 0.5),
			base
				* CFrame.new(
					spec.platformWidth / 2 - 0.6,
					top + spec.roofHeight / 2,
					z * (spec.platformLength / 2 - 3)
				),
			WOOD_DARK
		).CanCollide =
			false
	end
	for stripe = 1, 5 do
		local z = (stripe - 3) * (spec.platformLength - 6) / 5
		part(
			station,
			"Roof",
			Vector3.new(spec.platformWidth + 1, 0.4, (spec.platformLength - 6) / 5),
			base * CFrame.new(0, top + spec.roofHeight + 0.2, z),
			if stripe % 2 == 0 then CREAM else RED
		).CanCollide =
			false
	end

	-- Посадочный круг: встал — сел в вагончик, как только поезд у платформы.
	local pad = part(
		station,
		"BoardPad",
		Vector3.new(0.3, 5, 5),
		base * CFrame.new(0, top + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		YELLOW
	)
	pad.Shape = Enum.PartType.Cylinder
	pad.Material = Enum.Material.Neon
	pad.CanCollide = false
	pad:SetAttribute("Station", index)
	CollectionService:AddTag(pad, "AF_TrainBoard")
	-- Табло над кругом: «Садись!» или через сколько секунд придёт поезд (пишет клиент).
	local anchor =
		part(station, "TimerAnchor", Vector3.new(0.2, 0.2, 0.2), base * CFrame.new(0, top + 6.5, 0), CREAM)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Parent = pad
	local board = Instance.new("BillboardGui")
	board.Name = "Timer"
	board.Size = UDim2.fromScale(9, 2.2)
	board.MaxDistance = 80
	board.LightInfluence = 0
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = "🚂"
	label.Parent = board

	local sign = part(
		station,
		"Sign",
		Vector3.new(0.4, 2, 8),
		base * CFrame.new(spec.platformWidth / 2, top + spec.roofHeight - 1.2, 0),
		CREAM
	)
	sign.CanCollide = false
	letterFace(sign, Enum.NormalId.Left, "🚂 Паровозик", Color3.fromRGB(70, 60, 50))
	letterFace(sign, Enum.NormalId.Right, "🚂 Паровозик", Color3.fromRGB(70, 60, 50))
end

function RidesBuilder.buildRailway(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Railway"
	folder.Parent = parent
	buildTrack(folder)
	for index = 1, Rides.TRAIN.stations do
		buildStation(folder, index)
	end
	buildTrain(folder)
end

-- ===== Колесо обозрения =====

--[[
	Колесо в месте парка origin (на земле, лицом к площади). Плоскость колеса
	смотрит на площадь: с точки появления оно видно круглым, а не ребром.
	Ось колеса — ось X кадра axle (Config/Rides.cabinOffset).
]]
function RidesBuilder.buildWheel(model: Model, origin: CFrame)
	local spec = Rides.WHEEL
	local r = spec.diameter / 2
	local axle = origin * CFrame.new(0, spec.axle, 0) * CFrame.Angles(0, math.rad(90), 0)
	model:SetAttribute("Axle", axle)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Опоры: по два бруса с каждой стороны колеса, от земли к оси.
	for _, side in { -1, 1 } do
		for _, spread in { -1, 1 } do
			local foot = (axle * CFrame.new(side * 3.2, 0, spread * 11)).Position
			foot = Vector3.new(foot.X, origin.Position.Y, foot.Z)
			beam(model, "Leg", foot, (axle * CFrame.new(side * 3.2, 0, 0)).Position, 1.4, CREAM)
		end
	end
	cylinder(model, "Hub", 8, 2.6, axle, RED)
	cylinder(model, "HubCap", 8.4, 1.4, axle, YELLOW)

	-- Обод, спицы и перекладины крутятся вместе: папка Rotor.
	local rotor = Instance.new("Model")
	rotor.Name = "Rotor"
	rotor.Parent = model
	local rimSegments = 20
	for _, side in { -1, 1 } do
		for index = 1, rimSegments do
			local a = (index - 1) / rimSegments * math.pi * 2
			local b = index / rimSegments * math.pi * 2
			local from = (axle * CFrame.new(side * 1.3, -math.cos(a) * r, math.sin(a) * r)).Position
			local to = (axle * CFrame.new(side * 1.3, -math.cos(b) * r, math.sin(b) * r)).Position
			beam(rotor, "Rim", from, to, 0.8, CABIN_COLORS[(index - 1) % #CABIN_COLORS + 1]).CanCollide =
				false
		end
		for index = 1, spec.cabins do
			local a = (index - 1) / spec.cabins * math.pi * 2
			local to = (axle * CFrame.new(side * 1.3, -math.cos(a) * r, math.sin(a) * r)).Position
			beam(rotor, "Spoke", (axle * CFrame.new(side * 1.3, 0, 0)).Position, to, 0.4, CREAM).CanCollide =
				false
		end
	end
	for index = 1, spec.cabins do
		local a = (index - 1) / spec.cabins * math.pi * 2
		local at = axle * CFrame.new(0, -math.cos(a) * r, math.sin(a) * r)
		cylinder(rotor, "Pin", 3.2, 0.5, at, WOOD_DARK).CanCollide = false
	end

	-- Кабинки: всегда вертикальны, каждая своя модель со своей опорной точкой.
	local size = spec.cabinSize
	for index = 1, spec.cabins do
		local cabin = Instance.new("Model")
		cabin.Name = `Cabin_{index}`
		cabin.Parent = model
		local center = axle * CFrame.new(Rides.cabinOffset(index, 0))
		cabin:SetAttribute("Index", index)
		local color = CABIN_COLORS[(index - 1) % #CABIN_COLORS + 1]
		part(
			cabin,
			"Floor",
			Vector3.new(size.X, 0.4, size.Z),
			center * CFrame.new(0, -size.Y / 2 + 0.2, 0),
			color
		)
		for _, x in { -1, 1 } do
			part(
				cabin,
				"Wall",
				Vector3.new(0.3, 1.6, size.Z),
				center * CFrame.new(x * (size.X / 2 - 0.15), -size.Y / 2 + 1.2, 0),
				color
			)
			part(
				cabin,
				"Wall",
				Vector3.new(size.X, 1.6, 0.3),
				center * CFrame.new(0, -size.Y / 2 + 1.2, x * (size.Z / 2 - 0.15)),
				color
			)
		end
		for _, corner in { Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(1, 1) } do
			part(
				cabin,
				"Post",
				Vector3.new(0.25, size.Y - 0.6, 0.25),
				center * CFrame.new(corner.X * (size.X / 2 - 0.2), 0.1, corner.Y * (size.Z / 2 - 0.2)),
				CREAM
			)
		end
		part(
			cabin,
			"Roof",
			Vector3.new(size.X + 0.6, 0.4, size.Z + 0.6),
			center * CFrame.new(0, size.Y / 2, 0),
			color
		)
		part(
			cabin,
			"Hanger",
			Vector3.new(0.4, 0.6, 0.4),
			center * CFrame.new(0, size.Y / 2 + 0.4, 0),
			WOOD_DARK
		)
		for _, descendant in cabin:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
			end
		end
	end

	-- Посадочный круг у нижней кабинки, со стороны площади.
	local padAt = origin * CFrame.new(0, 0.15, -spec.cabinSize.Z / 2 - 3.5)
	local pad =
		part(model, "BoardPad", Vector3.new(0.3, 5, 5), padAt * CFrame.Angles(0, 0, math.rad(90)), YELLOW)
	pad.Shape = Enum.PartType.Cylinder
	pad.Material = Enum.Material.Neon
	pad.CanCollide = false
	CollectionService:AddTag(pad, "AF_WheelBoard")
	CollectionService:AddTag(model, "AF_Wheel")
end

-- Вертикальный цилиндр: ось вдоль Y кадра at.
local function column(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	at: CFrame,
	color: Color3
): Part
	return cylinder(parent, name, height, diameter, at * CFrame.Angles(0, 0, math.rad(90)), color)
end

local function ball(parent: Instance, name: string, diameter: number, at: CFrame, color: Color3): Part
	local p = part(parent, name, Vector3.new(diameter, diameter, diameter), at, color)
	p.Shape = Enum.PartType.Ball
	return p
end

local function boardPad(model: Instance, at: CFrame, tag: string): Part
	local pad =
		part(model, "BoardPad", Vector3.new(0.3, 5, 5), at * CFrame.Angles(0, 0, math.rad(90)), YELLOW)
	pad.Shape = Enum.PartType.Cylinder
	pad.Material = Enum.Material.Neon
	pad.CanCollide = false
	CollectionService:AddTag(pad, tag)
	return pad
end

-- ===== Карусель =====

local HORSE_COATS = {
	{ coat = Color3.fromRGB(250, 248, 240), mane = Color3.fromRGB(240, 120, 170) },
	{ coat = Color3.fromRGB(170, 115, 80), mane = Color3.fromRGB(80, 55, 40) },
	{ coat = Color3.fromRGB(250, 205, 225), mane = Color3.fromRGB(150, 110, 220) },
	{ coat = Color3.fromRGB(200, 205, 215), mane = Color3.fromRGB(70, 130, 220) },
	{ coat = Color3.fromRGB(252, 230, 160), mane = Color3.fromRGB(245, 150, 70) },
	{ coat = Color3.fromRGB(190, 225, 250), mane = Color3.fromRGB(255, 255, 255) },
}
local SADDLES = { RED, BLUE, GREEN, Color3.fromRGB(240, 140, 60), Color3.fromRGB(170, 110, 220), YELLOW }

-- Лошадка в кадре frame: смотрит вперёд (LookVector), спина на высоте frame, шест сквозь неё.
local function horse(parent: Model, frame: CFrame, index: number)
	local look = HORSE_COATS[(index - 1) % #HORSE_COATS + 1]
	cylinder(parent, "Body", 3.6, 1.9, frame * CFrame.Angles(0, math.rad(90), 0), look.coat)
	part(parent, "Chest", Vector3.new(1.5, 1.7, 1.2), frame * CFrame.new(0, 0.1, -1.5), look.coat)
	part(
		parent,
		"Neck",
		Vector3.new(0.95, 2.2, 1),
		frame * CFrame.new(0, 1.2, -1.75) * CFrame.Angles(math.rad(-25), 0, 0),
		look.coat
	)
	part(
		parent,
		"Head",
		Vector3.new(0.9, 0.95, 1.9),
		frame * CFrame.new(0, 2.3, -2.55) * CFrame.Angles(math.rad(15), 0, 0),
		look.coat
	)
	part(parent, "Muzzle", Vector3.new(0.8, 0.7, 0.5), frame * CFrame.new(0, 2.05, -3.4), look.coat)
	for _, side in { -1, 1 } do
		part(
			parent,
			"Ear",
			Vector3.new(0.25, 0.55, 0.25),
			frame * CFrame.new(side * 0.3, 2.95, -2.1),
			look.coat
		)
		ball(parent, "Eye", 0.28, frame * CFrame.new(side * 0.46, 2.45, -2.9), Color3.fromRGB(40, 35, 35))
	end
	-- Грива гребнем по шее и хвост.
	for step = 0, 3 do
		part(
			parent,
			"Mane",
			Vector3.new(0.4, 0.7, 0.55),
			frame * CFrame.new(0, 0.7 + step * 0.55, -1.2 - step * 0.3) * CFrame.Angles(math.rad(-25), 0, 0),
			look.mane
		)
	end
	part(
		parent,
		"Tail",
		Vector3.new(0.45, 1.8, 0.5),
		frame * CFrame.new(0, -0.1, 2.05) * CFrame.Angles(math.rad(35), 0, 0),
		look.mane
	)
	-- Ноги вскачь: передние вперёд, задние назад.
	for _, side in { -1, 1 } do
		part(
			parent,
			"Leg",
			Vector3.new(0.35, 1.7, 0.35),
			frame * CFrame.new(side * 0.5, -1.2, -1.3) * CFrame.Angles(math.rad(-35), 0, 0),
			look.coat
		)
		part(
			parent,
			"Leg",
			Vector3.new(0.35, 1.7, 0.35),
			frame * CFrame.new(side * 0.5, -1.2, 1.3) * CFrame.Angles(math.rad(30), 0, 0),
			look.coat
		)
	end
	part(
		parent,
		"Saddle",
		Vector3.new(1.95, 0.3, 1.5),
		frame * CFrame.new(0, 0.95, 0.1),
		SADDLES[(index - 1) % #SADDLES + 1]
	)
	part(parent, "Blanket", Vector3.new(2.05, 1, 1.2), frame * CFrame.new(0, 0.5, 0.1), YELLOW)
	-- Шест от помоста до шатра: едет вместе с лошадкой.
	local fromY, toY = 1.2 - 2.6, Rides.CAROUSEL.roof - 0.4 - 2.6
	local pole = column(
		parent,
		"Pole",
		toY - fromY,
		0.35,
		frame * CFrame.new(0, (fromY + toY) / 2, 0),
		Color3.fromRGB(255, 215, 90)
	)
	pole.Material = Enum.Material.Metal
end

--[[
	Карусель в месте парка origin. Опорная точка всего, что крутится, — центр
	помоста на земле (атрибут Center); лошадки — отдельные модели со своей
	опорной точкой Rides.horseFrame(i, 0, 0), их двигает RideController.
]]
function RidesBuilder.buildCarousel(model: Model, origin: CFrame)
	local spec = Rides.CAROUSEL
	local center = origin
	model:SetAttribute("Center", center)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Неподвижное: круглый цоколь.
	local plinth = column(model, "Plinth", 0.8, spec.platform + 1.6, center * CFrame.new(0, 0.4, 0), CREAM)
	plinth.Material = Enum.Material.Marble

	local rotor = Instance.new("Model")
	rotor.Name = "Rotor"
	rotor.Parent = model
	local deck = column(rotor, "Deck", 0.4, spec.platform, center * CFrame.new(0, 1, 0), WOOD)
	deck.Material = Enum.Material.WoodPlanks
	column(rotor, "DeckRim", 0.5, spec.platform + 0.4, center * CFrame.new(0, 0.95, 0), RED)
	column(rotor, "Core", spec.roof, 3, center * CFrame.new(0, spec.roof / 2 + 1, 0), CREAM)
	-- Зеркальные полосы на столбе: блестят, когда карусель крутится.
	for index = 1, 8 do
		local mirror = part(
			rotor,
			"Mirror",
			Vector3.new(0.2, 4, 0.9),
			center * CFrame.Angles(0, index / 8 * math.pi * 2, 0) * CFrame.new(1.45, 5, 0),
			Color3.fromRGB(220, 235, 250)
		)
		mirror.Material = Enum.Material.Glass
		mirror.Reflectance = 0.4
	end

	-- Шатёр: ярусы-кольца, чем выше, тем уже, красные и белые через один.
	local tiers = 7
	for tier = 0, tiers - 1 do
		local diameter = (spec.platform + 2) * (1 - tier / tiers) + 1
		column(
			rotor,
			"Canopy",
			0.9,
			diameter,
			center * CFrame.new(0, spec.roof + 1 + tier * 0.8, 0),
			if tier % 2 == 0 then RED else CREAM
		)
	end
	local peak = spec.roof + 1 + tiers * 0.8
	ball(rotor, "Top", 1.6, center * CFrame.new(0, peak + 0.5, 0), YELLOW)
	column(rotor, "FlagPole", 3, 0.2, center * CFrame.new(0, peak + 2, 0), CREAM)
	part(rotor, "Flag", Vector3.new(0.1, 1, 1.8), center * CFrame.new(0, peak + 2.9, 0.9), BLUE)
	-- Бахрома по краю шатра: шарики-фестоны и лампочки.
	local fringe = 24
	local edge = (spec.platform + 2) / 2 + 0.3
	for index = 1, fringe do
		local at = center
			* CFrame.Angles(0, index / fringe * math.pi * 2, 0)
			* CFrame.new(edge, spec.roof + 0.4, 0)
		ball(rotor, "Scallop", 1.1, at, CABIN_COLORS[(index - 1) % #CABIN_COLORS + 1])
		local bulb = ball(rotor, "Bulb", 0.45, at * CFrame.new(0.2, -0.75, 0), Color3.fromRGB(255, 240, 180))
		bulb.Material = Enum.Material.Neon
	end

	for index = 1, spec.horses do
		local steed = Instance.new("Model")
		steed.Name = `Horse_{index}`
		steed.Parent = model
		horse(steed, center * Rides.horseFrame(index, 0, 0), index)
	end
	-- Твёрдые только цоколь и помост: по помосту можно ходить между лошадками.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = descendant == deck or descendant == plinth
		end
	end

	boardPad(model, origin * CFrame.new(0, 0.15, -(spec.platform / 2 + 4)), "AF_CarouselBoard")
	CollectionService:AddTag(model, "AF_Carousel")
end

-- ===== Лодочки-лебеди =====

local SWAN_WHITE = Color3.fromRGB(252, 252, 255)
local SWAN_SEATS = {
	Color3.fromRGB(250, 150, 190),
	Color3.fromRGB(120, 180, 250),
	Color3.fromRGB(250, 210, 90),
}

-- Эллипсоид: шар, растянутый мешем. Столкновений нет — это облик, а не опора.
local function ellipsoid(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = part(parent, name, size, cframe, color)
	p.CanCollide = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Лодочка-лебедь в кадре frame (ватерлиния, клювом по LookVector).
local function swan(parent: Model, frame: CFrame, index: number)
	ellipsoid(parent, "Hull", Vector3.new(4.4, 2.4, 6.6), frame * CFrame.new(0, 0.3, 0.3), SWAN_WHITE)
	part(parent, "Seat", Vector3.new(2.6, 0.5, 2.4), frame * CFrame.new(0, 1.15, 0.9), SWAN_SEATS[index]).CanCollide =
		false
	part(parent, "SeatBack", Vector3.new(2.6, 1.3, 0.4), frame * CFrame.new(0, 1.7, 2.1), SWAN_SEATS[index]).CanCollide =
		false
	ellipsoid(
		parent,
		"Tail",
		Vector3.new(1.6, 1.6, 2.2),
		frame * CFrame.new(0, 1.3, 3.3) * CFrame.Angles(math.rad(30), 0, 0),
		SWAN_WHITE
	)
	for _, side in { -1, 1 } do
		ellipsoid(
			parent,
			"Wing",
			Vector3.new(0.7, 1.9, 4.2),
			frame * CFrame.new(side * 2.05, 1.25, 0.8) * CFrame.Angles(math.rad(-12), 0, side * math.rad(-12)),
			Color3.fromRGB(240, 242, 250)
		)
	end
	-- Шея изгибом: шарики от груди к голове.
	local neck = {
		Vector3.new(0, 1.2, -2.5),
		Vector3.new(0, 2.0, -2.95),
		Vector3.new(0, 2.85, -3.05),
		Vector3.new(0, 3.65, -2.85),
		Vector3.new(0, 4.3, -2.9),
	}
	for link, at in neck do
		ball(parent, `Neck_{link}`, 1.25 - link * 0.07, frame * CFrame.new(at), SWAN_WHITE).CanCollide = false
	end
	ball(parent, "Head", 1.35, frame * CFrame.new(0, 4.75, -3.25), SWAN_WHITE).CanCollide = false
	local beak = part(
		parent,
		"Beak",
		Vector3.new(0.5, 0.5, 1.2),
		frame * CFrame.new(0, 4.6, -4.1) * CFrame.Angles(math.rad(-90), 0, 0),
		Color3.fromRGB(255, 150, 50)
	)
	beak.CanCollide = false
	local cone = Instance.new("SpecialMesh")
	cone.MeshType = Enum.MeshType.FileMesh
	cone.MeshId = "rbxassetid://1033714" -- конус из библиотеки Roblox
	cone.Scale = Vector3.new(0.35, 1, 0.35)
	cone.Parent = beak
	for _, side in { -1, 1 } do
		ball(parent, "Eye", 0.3, frame * CFrame.new(side * 0.5, 4.95, -3.6), Color3.fromRGB(30, 30, 40)).CanCollide =
			false
	end
	-- У одной лодочки корона: её хочется догнать.
	if index == 1 then
		local crown = column(parent, "Crown", 0.5, 0.9, frame * CFrame.new(0, 5.55, -3.2), YELLOW)
		crown.Material = Enum.Material.Neon
		crown.CanCollide = false
	end
end

--[[
	Озеро с лодочками-лебедями (Config/Rides.SWANS). Вода по щиколотку
	поверх травы: в неё можно зайти, утонуть нельзя. Мостки с кругом посадки
	со стороны площади (-Z). Лодочки — отдельные модели со своей опорной
	точкой Rides.swanFrame(i, 0, 0), плывут у клиента (RideController).
	Островок с деревом посередине ставит PlaygroundService: деревья — его.
]]
function RidesBuilder.buildSwans(model: Model, origin: CFrame)
	local spec = Rides.SWANS
	local waterTop = 0.25
	local center = origin * CFrame.new(0, waterTop, 0)
	model:SetAttribute("Center", center)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local shore = column(
		model,
		"Shore",
		0.2,
		spec.lake * 2 + 4,
		origin * CFrame.new(0, 0.1, 0),
		Color3.fromRGB(235, 215, 160)
	)
	shore.Material = Enum.Material.Sand
	local water = column(
		model,
		"LakeWater",
		0.3,
		spec.lake * 2,
		origin * CFrame.new(0, 0.1, 0),
		Color3.fromRGB(70, 160, 225)
	)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.2
	water.Reflectance = 0.15
	water.CanCollide = false
	local island = column(model, "Island", 0.8, spec.island * 2, origin * CFrame.new(0, 0.4, 0), GREEN)
	island.Material = Enum.Material.Grass

	-- Мостки со стороны площади: доски на сваях, в конце круг посадки.
	local from, to = spec.lake + 3, spec.loop + 3.2
	local length = from - to
	local deckY = 1.1
	local deck = part(
		model,
		"Pier",
		Vector3.new(4, 0.4, length),
		origin * CFrame.new(0, deckY, -(from + to) / 2),
		WOOD
	)
	deck.Material = Enum.Material.WoodPlanks
	for step = 0, 2 do
		for _, side in { -1, 1 } do
			local z = -(to + step * length / 2)
			column(model, "PierPost", 1.6, 0.5, origin * CFrame.new(side * 1.8, deckY - 0.6, z), WOOD_DARK)
		end
	end
	-- Ступенька с берега на мостки.
	part(model, "PierStep", Vector3.new(4, 0.4, 1.5), origin * CFrame.new(0, 0.55, -(from + 0.7)), WOOD_DARK).Material =
		Enum.Material.WoodPlanks

	for index = 1, spec.boats do
		local boat = Instance.new("Model")
		boat.Name = `Swan_{index}`
		boat.Parent = model
		swan(boat, center * Rides.swanFrame(index, 0, 0), index)
	end

	boardPad(model, origin * CFrame.new(0, deckY + 0.35, -(to + 1)), "AF_SwanBoard")
	CollectionService:AddTag(model, "AF_Swans")
end

-- Размеры озера для того, кто ставит берег (PlaygroundService).
RidesBuilder.SWAN_LAKE = Rides.SWANS

-- ===== Горка-спираль =====

--[[
	Горка в месте парка origin: столб-башня, площадка наверху под шатром,
	лестница-сетка (TrussPart: по ней лазают сами) и полтора витка жёлоба.
	Жёлоб неподвижный и твёрдый — по нему можно и забраться, это тоже игра.
	Едет ребёнок на клиенте (RideController): встал на круг наверху — поехал.
]]
function RidesBuilder.buildSlide(model: Model, origin: CFrame)
	local spec = Rides.SLIDE
	local base = origin
	model:SetAttribute("Base", base)

	local tower = column(model, "Tower", spec.height, 4, base * CFrame.new(0, spec.height / 2, 0), CREAM)
	tower.CanCollide = true
	for band = 1, 5 do
		column(
			model,
			"TowerBand",
			0.6,
			4.3,
			base * CFrame.new(0, band * spec.height / 6, 0),
			CABIN_COLORS[band]
		).CanCollide =
			false
	end
	local deck =
		column(model, "Deck", 0.6, spec.platform * 2, base * CFrame.new(0, spec.height - 0.3, 0), WOOD)
	deck.CanCollide = true
	deck.Material = Enum.Material.WoodPlanks

	-- Мостик от площадки к началу жёлоба: жёлоб начинается на угле 0, вдоль оси X.
	local start = Rides.slidePoint(0)
	local bridgeFrom = spec.platform - 0.5
	local bridgeLength = start.X - bridgeFrom + 1
	local bridge = part(
		model,
		"StartDeck",
		Vector3.new(bridgeLength, 0.6, spec.width),
		base * CFrame.new(bridgeFrom + bridgeLength / 2, spec.height - 0.3, 0),
		WOOD
	)
	bridge.CanCollide = true
	bridge.Material = Enum.Material.WoodPlanks
	for _, side in { -1, 1 } do
		part(
			model,
			"StartRail",
			Vector3.new(bridgeLength - 1, 1.4, 0.3),
			base * CFrame.new(bridgeFrom + bridgeLength / 2 - 0.5, spec.height + 0.7, side * spec.width / 2),
			RED
		).CanCollide =
			true
	end

	-- Перила площадки по кругу, кроме выхода на мостик и места лестницы.
	local ladder = math.rad(spec.ladderAngle)
	local rails = 16
	local function apart(a: number, b: number): number
		return math.abs(math.atan2(math.sin(a - b), math.cos(a - b)))
	end
	for index = 1, rails do
		local a = (index - 0.5) / rails * math.pi * 2
		if apart(a, 0) > math.rad(28) and apart(a, ladder) > math.rad(28) then
			local r = spec.platform - 0.2
			local at = base * CFrame.new(math.cos(a) * r, spec.height + 0.7, math.sin(a) * r)
			-- Поперёк радиуса: CFrame.Angles(0, -a, 0) смотрит осью X наружу, длина по Z.
			part(
				model,
				"Rail",
				Vector3.new(0.3, 1.4, spec.platform * 2 * math.pi / rails + 0.2),
				at * CFrame.Angles(0, -a, 0),
				CABIN_COLORS[(index - 1) % #CABIN_COLORS + 1]
			).CanCollide =
				true
		end
	end

	-- Шатёр над площадкой на четырёх столбиках.
	for index = 0, 3 do
		local a = math.rad(45 + index * 90)
		local r = spec.platform - 0.4
		column(
			model,
			"RoofPost",
			5,
			0.35,
			base * CFrame.new(math.cos(a) * r, spec.height + 2.5, math.sin(a) * r),
			CREAM
		).CanCollide =
			false
	end
	for tier = 0, 4 do
		column(
			model,
			"Roof",
			0.8,
			(spec.platform * 2 + 1.5) * (1 - tier / 5) + 0.6,
			base * CFrame.new(0, spec.height + 5.2 + tier * 0.7, 0),
			if tier % 2 == 0 then BLUE else CREAM
		).CanCollide =
			false
	end
	ball(model, "RoofTop", 1.2, base * CFrame.new(0, spec.height + 8.9, 0), YELLOW).CanCollide = false

	-- Лестница-сетка снаружи площадки: по ней лезут сами.
	local ladderRadius = spec.platform + 1
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Size = Vector3.new(2, spec.height + 1, 2)
	truss.CFrame = base
		* CFrame.new(math.cos(ladder) * ladderRadius, (spec.height + 1) / 2, math.sin(ladder) * ladderRadius)
		* CFrame.Angles(0, -ladder, 0)
	truss.Anchored = true
	truss.Color = Color3.fromRGB(240, 140, 60)
	truss.Parent = model

	-- Жёлоб: отрезки по спирали, у каждого дно и два бортика, цвета радугой.
	local segments = 45
	for index = 1, segments do
		local u0, u1 = (index - 1) / segments, index / segments
		local p0 = (base * CFrame.new(Rides.slidePoint(u0))).Position
		local p1 = (base * CFrame.new(Rides.slidePoint(u1))).Position
		local frame = CFrame.lookAt((p0 + p1) / 2, p1)
		local length = (p1 - p0).Magnitude + 0.35
		local color = CABIN_COLORS[math.floor((index - 1) / segments * #CABIN_COLORS) + 1]
		local floor =
			part(model, "Chute", Vector3.new(spec.width, 0.4, length), frame * CFrame.new(0, -0.2, 0), color)
		floor.CanCollide = true
		for _, side in { -1, 1 } do
			part(
				model,
				"ChuteWall",
				Vector3.new(0.35, 1.3, length),
				frame * CFrame.new(side * spec.width / 2, 0.45, 0),
				CREAM
			).CanCollide =
				true
		end
		-- Опоры реже и не там, где идут к лестнице.
		local angle = math.deg(u0 * spec.turns * math.pi * 2) % 360
		local nearLadder = math.abs((angle - spec.ladderAngle + 180) % 360 - 180) < 35
		local foot = (frame * CFrame.new(0, -0.4, 0)).Position
		local ground = base.Position.Y
		if index % 5 == 0 and not nearLadder and foot.Y - ground > 1 then
			column(
				model,
				"ChutePost",
				foot.Y - ground,
				0.6,
				CFrame.new(foot.X, (foot.Y + ground) / 2, foot.Z),
				CREAM
			).CanCollide =
				false
		end
	end

	-- Внизу — мягкий коврик, куда вылетают.
	local finish = (base * CFrame.new(Rides.slidePoint(1))).Position
	local before = (base * CFrame.new(Rides.slidePoint(0.98))).Position
	local ahead = ((finish - before) * Vector3.new(1, 0, 1)).Unit
	local matAt = Vector3.new(finish.X, base.Position.Y + 0.15, finish.Z) + ahead * 4
	part(
		model,
		"Mat",
		Vector3.new(6, 0.3, 8),
		CFrame.lookAt(matAt, matAt + ahead),
		Color3.fromRGB(120, 205, 110)
	).CanCollide =
		false

	boardPad(model, base * CFrame.new(start.X - 1.5, spec.height + 0.15, 0), "AF_SlideBoard")
	CollectionService:AddTag(model, "AF_Slide")
end

-- ===== Воздушный шар =====

-- Профиль купола снизу вверх: доля поперечника на каждой полосе (капля: узко внизу, шар сверху).
local ENVELOPE = { 0.28, 0.42, 0.56, 0.7, 0.82, 0.92, 0.98, 1, 0.98, 0.93, 0.84, 0.7, 0.5 }
local BALLOON_STRIPES = { RED, YELLOW, Color3.fromRGB(80, 190, 220), CREAM }

--[[
	Шар в месте парка origin: корзинка на лужайке, над ней купол из полос.
	Весь шар — одна модель Balloon с опорной точкой Home (центр дна корзины),
	её двигает RideController по Rides.balloonAt. Пламя горелки — деталь Flame
	внутри: клиент зажигает её на подъёме и на круге.
]]
function RidesBuilder.buildBalloon(model: Model, origin: CFrame)
	local spec = Rides.BALLOON
	local home = origin
	-- Стоянка: круг утоптанной травы с колышками.
	column(model, "Field", 0.2, 16, home * CFrame.new(0, 0.1, 0), Color3.fromRGB(215, 235, 170)).CanCollide =
		false
	for index = 1, 8 do
		local a = index / 8 * math.pi * 2
		column(model, "Peg", 1.4, 0.25, home * CFrame.new(math.cos(a) * 8, 0.7, math.sin(a) * 8), CREAM).CanCollide =
			false
	end

	local balloon = Instance.new("Model")
	balloon.Name = "Balloon"
	balloon.Parent = model
	balloon:SetAttribute("Home", home)
	model:SetAttribute("Inward", (-home.Position * Vector3.new(1, 0, 1)).Unit)
	-- Шар летает далеко от ребёнка: стриминг не должен его прятать.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- Корзинка: плетёный пол и стенки по пояс.
	local basket = 4.4
	part(balloon, "BasketFloor", Vector3.new(basket, 0.4, basket), home * CFrame.new(0, 0.2, 0), WOOD_DARK)
	for _, side in { -1, 1 } do
		part(
			balloon,
			"BasketWall",
			Vector3.new(0.35, 2.4, basket),
			home * CFrame.new(side * (basket / 2 - 0.17), 1.4, 0),
			WOOD
		).Material =
			Enum.Material.Fabric
		part(
			balloon,
			"BasketWall",
			Vector3.new(basket, 2.4, 0.35),
			home * CFrame.new(0, 1.4, side * (basket / 2 - 0.17)),
			WOOD
		).Material =
			Enum.Material.Fabric
	end
	part(
		balloon,
		"BasketRim",
		Vector3.new(basket + 0.3, 0.35, basket + 0.3),
		home * CFrame.new(0, 2.6, 0),
		WOOD_DARK
	)

	-- Горелка над корзиной и её пламя.
	local burnerY = 7
	part(
		balloon,
		"Burner",
		Vector3.new(1.2, 0.8, 1.2),
		home * CFrame.new(0, burnerY, 0),
		Color3.fromRGB(120, 125, 135)
	).Material =
		Enum.Material.Metal
	local flame = part(
		balloon,
		"Flame",
		Vector3.new(0.8, 2.2, 0.8),
		home * CFrame.new(0, burnerY + 1.5, 0),
		Color3.fromRGB(255, 150, 50)
	)
	flame.Material = Enum.Material.Neon
	flame.Transparency = 1
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 150, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 230, 120)
	fire.Enabled = false
	fire.Parent = flame

	-- Стропы от углов корзины к нижнему краю купола.
	local envelopeBottom = burnerY + 2.5
	local band = 1.6
	local d = spec.envelope
	for _, corner in { Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(1, 1) } do
		local from = (home * CFrame.new(corner.X * (basket / 2 - 0.2), 2.6, corner.Y * (basket / 2 - 0.2))).Position
		local to = (home * CFrame.new(
			corner.X * d * ENVELOPE[1] / 2.2,
			envelopeBottom,
			corner.Y * d * ENVELOPE[1] / 2.2
		)).Position
		beam(balloon, "Rope", from, to, 0.18, Color3.fromRGB(235, 220, 180))
	end
	for index, share in ENVELOPE do
		column(
			balloon,
			"Envelope",
			band + 0.05,
			d * share,
			home * CFrame.new(0, envelopeBottom + (index - 0.5) * band, 0),
			BALLOON_STRIPES[(index - 1) % #BALLOON_STRIPES + 1]
		)
	end
	ball(
		balloon,
		"Crown",
		d * 0.42,
		home * CFrame.new(0, envelopeBottom + #ENVELOPE * band - 0.2, 0),
		BALLOON_STRIPES[#ENVELOPE % #BALLOON_STRIPES + 1]
	)
	-- Флажок на макушке — видно, где шар, и с другого конца парка.
	local top = envelopeBottom + #ENVELOPE * band + 1.5
	column(balloon, "Mast", 3, 0.2, home * CFrame.new(0, top + 1, 0), CREAM)
	part(balloon, "Pennant", Vector3.new(0.1, 1.2, 2.2), home * CFrame.new(0, top + 2, 1.1), RED)

	-- Твёрдое только дно корзины: остальное ни за что не цепляется в полёте.
	for _, descendant in balloon:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = descendant.Name == "BasketFloor"
		end
	end

	boardPad(model, origin * CFrame.new(0, 0.15, -(basket / 2 + 4)), "AF_BalloonBoard")
	CollectionService:AddTag(model, "AF_Balloon")
end

-- ===== Корабль-качели =====

local HULL = Color3.fromRGB(175, 95, 55)
local GOLD = Color3.fromRGB(255, 200, 70)
local SEA = Color3.fromRGB(70, 165, 225)
local SAIL = Color3.fromRGB(252, 248, 236)

--[[
	Кораблик в кадре deck (середина палубы, нос — к −X): пузатый корпус,
	жёлтая полоса с иллюминаторами, корма и нос приподняты, четыре синие
	скамейки поперёк, мачта с парусом «⚓» и флажком, бушприт. Всё без
	столкновений: ребёнка на скамейку сажает клиент, а под качающимся
	корпусом не должно ничего застревать.
]]
local function ship(parent: Model, deck: CFrame)
	local spec = Rides.SHIP
	local half = spec.length / 2
	ellipsoid(
		parent,
		"Keel",
		Vector3.new(spec.length + 1, 4.2, spec.width + 0.6),
		deck * CFrame.new(0, -1.6, 0),
		HULL
	)
	local body = part(
		parent,
		"Hull",
		Vector3.new(spec.length - 2, 2.2, spec.width),
		deck * CFrame.new(0, -0.9, 0),
		HULL
	)
	body.Material = Enum.Material.WoodPlanks
	part(
		parent,
		"Deck",
		Vector3.new(spec.length - 2.4, 0.3, spec.width - 0.6),
		deck * CFrame.new(0, 0.1, 0),
		WOOD
	).Material =
		Enum.Material.WoodPlanks
	-- Корма и нос повыше: силуэт корабля узнаётся издалека.
	for _, side in { -1, 1 } do
		local castle = part(
			parent,
			"Castle",
			Vector3.new(2.6, 2.4, spec.width),
			deck * CFrame.new(side * (half - 1.6), 0.4, 0) * CFrame.Angles(0, 0, side * math.rad(-12)),
			HULL
		)
		castle.Material = Enum.Material.WoodPlanks
	end
	for _, z in { -1, 1 } do
		local zSide = z * (spec.width / 2 + 0.05)
		part(
			parent,
			"Stripe",
			Vector3.new(spec.length - 2.5, 0.55, 0.1),
			deck * CFrame.new(0, -0.5, zSide),
			GOLD
		)
		for hole = 1, 4 do
			local porthole = cylinder(
				parent,
				"Porthole",
				0.12,
				0.8,
				deck * CFrame.new(-4.5 + (hole - 1) * 3, -1.4, zSide) * CFrame.Angles(0, math.rad(90), 0),
				Color3.fromRGB(160, 215, 250)
			)
			porthole.Material = Enum.Material.Glass
		end
		-- Перила вдоль борта: золотой брус на столбиках.
		part(
			parent,
			"Rail",
			Vector3.new(spec.length - 3, 0.25, 0.25),
			deck * CFrame.new(0, 1.3, z * (spec.width / 2 - 0.2)),
			GOLD
		)
		for post = -2, 2 do
			part(
				parent,
				"RailPost",
				Vector3.new(0.2, 1.2, 0.2),
				deck * CFrame.new(post * 3, 0.7, z * (spec.width / 2 - 0.2)),
				GOLD
			)
		end
	end
	for index, x in spec.benches do
		part(parent, "Bench", Vector3.new(1.1, 0.5, spec.width - 1), deck * CFrame.new(x, 0.6, 0), BLUE)
		-- Спинка со стороны ближнего края: сидят лицом к середине корабля.
		local back = if x < 0 then -1 else 1
		part(
			parent,
			"BenchBack",
			Vector3.new(0.3, 1.3, spec.width - 1),
			deck * CFrame.new(x + back * 0.5, 1.2, 0),
			if index % 2 == 0 then RED else BLUE
		)
	end
	-- Мачта, рея, парус с якорем и флажок на макушке.
	column(parent, "Mast", 9, 0.55, deck * CFrame.new(0, 4.6, 0), WOOD_DARK)
	cylinder(
		parent,
		"Yard",
		spec.width + 0.6,
		0.3,
		deck * CFrame.new(0.3, 7.4, 0) * CFrame.Angles(0, math.rad(90), 0),
		WOOD_DARK
	)
	local sail =
		part(parent, "Sail", Vector3.new(0.15, 4.2, spec.width), deck * CFrame.new(0.35, 5.2, 0), SAIL)
	sail.Material = Enum.Material.Fabric
	letterFace(sail, Enum.NormalId.Right, "⚓", Color3.fromRGB(60, 90, 160))
	letterFace(sail, Enum.NormalId.Left, "⚓", Color3.fromRGB(60, 90, 160))
	local flag = part(parent, "Flag", Vector3.new(1.8, 1.1, 0.1), deck * CFrame.new(-0.9, 8.7, 0), RED)
	letterFace(flag, Enum.NormalId.Front, "⭐", YELLOW)
	letterFace(flag, Enum.NormalId.Back, "⭐", YELLOW)
	ball(parent, "MastTop", 0.7, deck * CFrame.new(0, 9.2, 0), GOLD)
	-- Бушприт и золотой шарик на носу.
	cylinder(
		parent,
		"Bowsprit",
		3.2,
		0.3,
		deck * CFrame.new(-half - 0.6, 1.4, 0) * CFrame.Angles(0, 0, math.rad(-20)),
		WOOD_DARK
	)
	ball(parent, "BowBall", 0.8, deck * CFrame.new(-half - 2.1, 1.95, 0), GOLD)
	for _, descendant in parent:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
end

--[[
	Корабль-качели в месте парка origin (−Z — к площади). Неподвижное: синее
	«море» с барашками, две опоры-«А» в синюю и белую полоску, ось. Качается
	модель Ship вместе с плечами — её опорная точка — ось (атрибут Pivot),
	двигает её RideController по Rides.shipAt.
]]
function RidesBuilder.buildShip(model: Model, origin: CFrame)
	local spec = Rides.SHIP
	local pivot = origin * CFrame.new(0, spec.pivot, 0)
	model:SetAttribute("Pivot", pivot)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local sea = column(model, "Sea", 0.25, 30, origin * CFrame.new(0, 0.12, 0), SEA)
	sea.Material = Enum.Material.Glass
	sea.Transparency = 0.1
	sea.Reflectance = 0.2
	local shore =
		column(model, "SeaShore", 0.2, 32, origin * CFrame.new(0, 0.08, 0), Color3.fromRGB(235, 215, 160))
	shore.Material = Enum.Material.Sand
	local random = Random.new(30)
	for index = 1, 14 do
		local a = index / 14 * math.pi * 2 + random:NextNumber(0, 0.3)
		local r = random:NextNumber(4, 13.5)
		local cap = ball(
			model,
			"WaveCap",
			random:NextNumber(0.6, 1.1),
			origin * CFrame.new(math.cos(a) * r, 0.25, math.sin(a) * r),
			Color3.fromRGB(245, 250, 255)
		)
		cap.Size = Vector3.new(cap.Size.X * 2.2, cap.Size.Y * 0.4, cap.Size.Z)
		cap.CanCollide = false
	end

	-- Опоры: две «А» по бокам, ноги в синюю и белую полоску, ось между ними.
	local spread = spec.pivot * 0.62
	for _, z in { -1, 1 } do
		local zSide = z * (spec.width / 2 + 2)
		for _, x in { -1, 1 } do
			local from = (origin * CFrame.new(x * spread, 0, zSide)).Position
			local to = (pivot * CFrame.new(0, 0, zSide)).Position
			local leg = beam(model, "Leg", from, to, 1, BLUE)
			for band = 1, 3 do
				local at = from:Lerp(to, band / 4)
				part(model, "LegBand", Vector3.new(1.08, 1.08, 1.2), CFrame.lookAt(at, to), CREAM)
			end
			leg.CanCollide = true
		end
		part(
			model,
			"Brace",
			Vector3.new(spread * 1.1, 0.6, 0.6),
			origin * CFrame.new(0, spec.pivot * 0.45, zSide),
			BLUE
		)
		ball(model, "Hub", 1.8, pivot * CFrame.new(0, 0, zSide), GOLD)
	end
	cylinder(
		model,
		"Axle",
		spec.width + 4.4,
		0.7,
		pivot * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(200, 205, 215)
	).Material =
		Enum.Material.Metal

	local swing = Instance.new("Model")
	swing.Name = "Ship"
	swing.Parent = model
	-- Плечи: от оси к палубе по два с каждого борта, качаются с кораблём.
	local deck = pivot * Rides.shipFrame(0)
	for _, z in { -1, 1 } do
		for _, x in { -1, 1 } do
			local arm = beam(
				swing,
				"Arm",
				(pivot * CFrame.new(0, 0, z * (spec.width / 2 + 0.9))).Position,
				(deck * CFrame.new(x * 3.2, 0.6, z * (spec.width / 2 + 0.2))).Position,
				0.5,
				GOLD
			)
			arm.Material = Enum.Material.Metal
			arm.CanCollide = false
		end
	end
	ship(swing, deck)
	local creak = Instance.new("Sound")
	creak.Name = "Creak"
	creak.Looped = true
	creak.RollOffMinDistance = 12
	creak.RollOffMaxDistance = 70
	creak.Parent = swing:FindFirstChild("Hull")

	boardPad(model, origin * CFrame.new(0, 0.3, -(spec.width / 2 + 5)), "AF_ShipBoard")
	CollectionService:AddTag(model, "AF_Ship")
end

-- ===== Домик на дереве и тарзанка =====

local BARK = Color3.fromRGB(125, 85, 55)
local LEAVES = {
	Color3.fromRGB(90, 175, 85),
	Color3.fromRGB(110, 195, 90),
	Color3.fromRGB(70, 150, 75),
}
local ROPE = Color3.fromRGB(215, 190, 140)

--[[
	Дерево-великан: ствол с корнями и крона из шаров разной зелени на высоте
	crownY. Если ствол ниже кроны (у большого дерева он держит площадку),
	крону несут четыре ветки от углов площадки — домик стоит между ними.
]]
local function giantTree(
	parent: Instance,
	name: string,
	foot: CFrame,
	trunk: number,
	height: number,
	crownY: number,
	crown: number,
	spread: number
)
	local stem = column(parent, `{name}Trunk`, height, trunk, foot * CFrame.new(0, height / 2, 0), BARK)
	stem.Material = Enum.Material.Wood
	for root = 1, 5 do
		local a = root / 5 * math.pi * 2 + 0.4
		local out = foot * CFrame.new(math.cos(a) * trunk * 0.55, 0.6, math.sin(a) * trunk * 0.55)
		local spur = part(
			parent,
			`{name}Root`,
			Vector3.new(trunk * 0.45, 1.6, trunk * 0.9),
			out * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(-25), 0, 0),
			BARK
		)
		spur.Material = Enum.Material.Wood
	end
	if crownY > height + 2 then
		for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
			local from = (foot * CFrame.new(corner.X * spread, height - 1, corner.Y * spread)).Position
			local to = (foot * CFrame.new(corner.X * spread * 0.8, crownY - 1, corner.Y * spread * 0.8)).Position
			local branch = beam(parent, `{name}Branch`, from, to, trunk * 0.3, BARK)
			branch.Material = Enum.Material.Wood
			branch.CanCollide = false
		end
	end
	local random = Random.new(#name + height)
	for puff = 1, 9 do
		local a = puff / 9 * math.pi * 2
		local r = if puff % 3 == 0 then 0 else crown * 0.55
		local size = crown * random:NextNumber(0.75, 1.05)
		local leaf = ball(
			parent,
			`{name}Leaves`,
			size,
			foot * CFrame.new(math.cos(a) * r, crownY + random:NextNumber(-1.5, 2.5), math.sin(a) * r),
			LEAVES[puff % #LEAVES + 1]
		)
		leaf.Material = Enum.Material.Grass
		leaf.CanCollide = false
	end
end

-- Перила вдоль отрезка палубы: столбики и брус, твёрдые — с площадки не свалиться.
local function railing(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local posts = math.max(2, math.floor(length / 2.5) + 1)
	for index = 0, posts - 1 do
		local at = from:Lerp(to, index / (posts - 1))
		part(
			parent,
			"RailPost",
			Vector3.new(0.35, 2.6, 0.35),
			CFrame.new(at + Vector3.new(0, 1.3, 0)),
			WOOD_DARK
		)
	end
	beam(parent, "Rail", from + Vector3.new(0, 2.6, 0), to + Vector3.new(0, 2.6, 0), 0.35, WOOD)
	-- Невидимая стенка по перилам: ребёнок не протиснется между столбиками.
	local wall =
		beam(parent, "RailGuard", from + Vector3.new(0, 1.5, 0), to + Vector3.new(0, 1.5, 0), 3, WOOD)
	wall.Transparency = 1
	wall.Size = Vector3.new(0.3, 3, length)
end

--[[
	Ролик тарзанки с верёвкой и круглым сиденьем, как во дворе. Стоит вверху
	троса; на катании его двигает клиент (RideController) вместе с ребёнком.
	Опорная точка группы — точка троса (атрибут Home).
]]
local function zipTrolley(parent: Instance, at: Vector3, heading: Vector3): Model
	local spec = Rides.TREEHOUSE
	local home = CFrame.lookAt(at, at + heading)
	local trolley = Instance.new("Model")
	trolley.Name = "ZipTrolley"
	trolley:SetAttribute("Home", home)
	trolley.Parent = parent
	part(trolley, "Pulley", Vector3.new(0.9, 0.9, 1.4), home, RED)
	cylinder(trolley, "Wheel", 0.5, 1.1, home * CFrame.new(0, 0.1, 0), Color3.fromRGB(70, 70, 80))
	local drop = spec.hang + 1.5
	part(trolley, "ZipRope", Vector3.new(0.18, drop, 0.18), home * CFrame.new(0, -drop / 2, 0), ROPE)
	column(trolley, "ZipSeat", 0.4, 1.9, home * CFrame.new(0, -drop - 0.2, 0), YELLOW)
	column(trolley, "ZipSeatRim", 0.3, 2.1, home * CFrame.new(0, -drop - 0.35, 0), RED)
	for _, descendant in trolley:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
	return trolley
end

function RidesBuilder.buildTreehouse(model: Model, origin: CFrame)
	local spec = Rides.TREEHOUSE
	local deck = spec.deck
	model:SetAttribute("Origin", origin)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local function world(local_: Vector3): Vector3
		return (origin * CFrame.new(local_)).Position
	end

	giantTree(
		model,
		"Big",
		origin * CFrame.new(spec.big),
		4.2,
		deck - 1,
		deck + 12,
		10,
		spec.bigDeck / 2 - 0.8
	)
	giantTree(model, "Small", origin * CFrame.new(spec.small), 3, deck + 9, deck + 10, 7, 0)

	-- Площадка большого дерева и домик на ней: дверь к мостику, круглое окошко к площади.
	local bigHalf = spec.bigDeck / 2
	local bigFloor = part(
		model,
		"BigDeck",
		Vector3.new(spec.bigDeck, 1, spec.bigDeck),
		origin * CFrame.new(spec.big + Vector3.new(0, deck - 0.5, 0)),
		WOOD
	)
	bigFloor.Material = Enum.Material.WoodPlanks
	local house = origin * CFrame.new(spec.big + Vector3.new(0, deck, 0))
	local wallColor = Color3.fromRGB(255, 225, 150)
	local size, height = 7, 5.5
	-- Задняя и боковые стены целые, в передней (к мостику, +X) — дверной проём.
	part(
		model,
		"HouseWall",
		Vector3.new(0.5, height, size),
		house * CFrame.new(-size / 2, height / 2, 0),
		wallColor
	)
	part(
		model,
		"HouseWall",
		Vector3.new(size, height, 0.5),
		house * CFrame.new(0, height / 2, -size / 2),
		wallColor
	)
	part(
		model,
		"HouseWall",
		Vector3.new(size, height, 0.5),
		house * CFrame.new(0, height / 2, size / 2),
		wallColor
	)
	for _, z in { -1, 1 } do
		part(
			model,
			"HouseWall",
			Vector3.new(0.5, height, 2.25),
			house * CFrame.new(size / 2, height / 2, z * 2.375),
			wallColor
		)
	end
	part(
		model,
		"HouseLintel",
		Vector3.new(0.5, 1.5, 2.5),
		house * CFrame.new(size / 2, height - 0.75, 0),
		wallColor
	)
	-- Круглое окошко на площадь в деревянной раме.
	local window = cylinder(
		model,
		"HouseWindow",
		0.6,
		2.4,
		house * CFrame.new(0, 3, -size / 2) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(160, 215, 250)
	)
	window.Material = Enum.Material.Glass
	window.Transparency = 0.3
	cylinder(
		model,
		"HouseWindowRim",
		0.5,
		2.9,
		house * CFrame.new(0, 3, -size / 2 - 0.05) * CFrame.Angles(0, math.rad(90), 0),
		WOOD_DARK
	)
	-- Крыша-домиком: два ската красной черепицы.
	for _, side in { -1, 1 } do
		local slope = part(
			model,
			"HouseRoof",
			Vector3.new(size / 2 / math.cos(math.rad(35)) + 0.8, 0.4, size + 1.2),
			house
				* CFrame.new(side * size / 4, height + size / 4 * math.tan(math.rad(35)), 0)
				* CFrame.Angles(0, 0, side * math.rad(-35)),
			RED
		)
		slope.Material = Enum.Material.Slate
	end
	part(
		model,
		"HouseGable",
		Vector3.new(size - 0.4, 2.2, 0.4),
		house * CFrame.new(0, height + 1, -size / 2),
		wallColor
	)
	part(
		model,
		"HouseGable",
		Vector3.new(size - 0.4, 2.2, 0.4),
		house * CFrame.new(0, height + 1, size / 2),
		wallColor
	)
	-- Внутри: скамейка и лампа-шарик (без света: бюджет кадра), на стене азбука.
	part(model, "HouseBench", Vector3.new(1.2, 1, 4), house * CFrame.new(-size / 2 + 1, 0.5, 0), BLUE)
	local lamp =
		ball(model, "HouseLamp", 0.8, house * CFrame.new(0, height - 0.8, 0), Color3.fromRGB(255, 235, 170))
	lamp.Material = Enum.Material.Neon
	lamp.CanCollide = false
	local poster = part(
		model,
		"HousePoster",
		Vector3.new(0.1, 1.6, 3.2),
		house * CFrame.new(-size / 2 + 0.3, 3, 0),
		CREAM
	)
	letterFace(poster, Enum.NormalId.Right, "А Б В", RED)

	-- Перила большой площадки: проём у лестницы (−Z) и у мостика (+X).
	local b = spec.big
	railing(
		model,
		world(b + Vector3.new(-bigHalf, deck, -bigHalf)),
		world(b + Vector3.new(-bigHalf, deck, bigHalf))
	)
	railing(
		model,
		world(b + Vector3.new(-bigHalf, deck, bigHalf)),
		world(b + Vector3.new(bigHalf, deck, bigHalf))
	)
	railing(
		model,
		world(b + Vector3.new(-bigHalf, deck, -bigHalf)),
		world(b + Vector3.new(-1.5, deck, -bigHalf))
	)
	railing(
		model,
		world(b + Vector3.new(1.5, deck, -bigHalf)),
		world(b + Vector3.new(bigHalf, deck, -bigHalf))
	)
	railing(model, world(b + Vector3.new(bigHalf, deck, bigHalf)), world(b + Vector3.new(bigHalf, deck, 1.8)))
	railing(
		model,
		world(b + Vector3.new(bigHalf, deck, -1.8)),
		world(b + Vector3.new(bigHalf, deck, -bigHalf))
	)

	-- Верёвочная лестница: по TrussPart ребёнок лезет сам.
	local ladder = Instance.new("TrussPart")
	ladder.Name = "Ladder"
	ladder.Size = Vector3.new(2, 14, 2)
	ladder.CFrame = origin * CFrame.new(b + Vector3.new(0, 7, -bigHalf - 1))
	ladder.Color = ROPE
	ladder.Anchored = true
	ladder.Parent = model

	-- Площадка малого дерева: проём к мостику (−X) и к тарзанке (−Z).
	local smallHalf = spec.smallDeck / 2
	local sm = spec.small
	local smallFloor = part(
		model,
		"SmallDeck",
		Vector3.new(spec.smallDeck, 1, spec.smallDeck),
		origin * CFrame.new(sm + Vector3.new(0, deck - 0.5, 0)),
		WOOD
	)
	smallFloor.Material = Enum.Material.WoodPlanks
	railing(
		model,
		world(sm + Vector3.new(smallHalf, deck, -smallHalf)),
		world(sm + Vector3.new(smallHalf, deck, smallHalf))
	)
	railing(
		model,
		world(sm + Vector3.new(-smallHalf, deck, smallHalf)),
		world(sm + Vector3.new(smallHalf, deck, smallHalf))
	)
	railing(
		model,
		world(sm + Vector3.new(-smallHalf, deck, smallHalf)),
		world(sm + Vector3.new(-smallHalf, deck, 1.8))
	)
	railing(
		model,
		world(sm + Vector3.new(-smallHalf, deck, -1.8)),
		world(sm + Vector3.new(-smallHalf, deck, -smallHalf))
	)
	railing(
		model,
		world(sm + Vector3.new(-smallHalf, deck, -smallHalf)),
		world(sm + Vector3.new(-1.6, deck, -smallHalf))
	)
	railing(
		model,
		world(sm + Vector3.new(1.6, deck, -smallHalf)),
		world(sm + Vector3.new(smallHalf, deck, -smallHalf))
	)

	--[[
		Подвесной мостик: доски со щелями, провисают дугой, по бокам верёвочные
		поручни. Доски твёрдые, щели — нет: оступиться можно, но щель узкая.
	]]
	local from = b.X + bigHalf
	local to = sm.X - smallHalf
	local step = (to - from) / spec.planks
	for index = 1, spec.planks do
		local x = from + step * (index - 0.5)
		local dip = Rides.bridgeDip(index)
		local plank = part(
			model,
			"BridgePlank",
			Vector3.new(step - 0.35, 0.35, 3.2),
			origin * CFrame.new(x, deck - 0.18 - dip, b.Z),
			if index % 2 == 0 then WOOD else WOOD_DARK
		)
		plank.Material = Enum.Material.WoodPlanks
	end
	for _, z in { -1.7, 1.7 } do
		local previous = world(Vector3.new(from, deck + 2.4, b.Z + z))
		for index = 1, spec.planks do
			local x = from + step * index
			local dip = if index == spec.planks then 0 else Rides.bridgeDip(index + 0.5)
			local point = world(Vector3.new(x, deck + 2.4 - dip * 0.8, b.Z + z))
			beam(model, "BridgeRope", previous, point, 0.22, ROPE).CanCollide = false
			beam(model, "BridgeHanger", point, point - Vector3.new(0, 2.4 - dip * 0.2, 0), 0.12, ROPE).CanCollide =
				false
			previous = point
		end
		-- Невидимый бортик мостика: вбок не свалиться, только сквозь щель вниз.
		local guard = part(
			model,
			"BridgeGuard",
			Vector3.new(to - from, 3, 0.3),
			origin * CFrame.new((from + to) / 2, deck + 1, b.Z + z * 1.05),
			WOOD
		)
		guard.Transparency = 1
	end

	-- Тарзанка: рама над краем малой площадки, трос дугой к столбу у песочной ямы.
	local top = spec.zipFrom
	for _, x in { -2, 2 } do
		column(
			model,
			"ZipFramePost",
			top.Y - deck + 1.5,
			0.6,
			origin * CFrame.new(top.X + x, (top.Y + deck + 1.5) / 2, top.Z + 1.3),
			WOOD_DARK
		)
	end
	part(
		model,
		"ZipFrameBeam",
		Vector3.new(4.6, 0.6, 0.6),
		origin * CFrame.new(top.X, top.Y + 1.5, top.Z + 1.3),
		WOOD_DARK
	)
	beam(
		model,
		"ZipCable",
		world(top + Vector3.new(0, 1.2, 1.3)),
		world(top),
		0.18,
		Color3.fromRGB(60, 60, 70)
	).CanCollide =
		false
	local previous = world(Rides.zipPoint(0))
	for index = 1, 12 do
		local point = world(Rides.zipPoint(index / 12))
		beam(model, "ZipCable", previous, point, 0.18, Color3.fromRGB(60, 60, 70)).CanCollide = false
		previous = point
	end
	-- Столб — за концом пути: у конца ребёнок спрыгивает, и столб ему не мешает.
	local post = Rides.zipLanding() + Rides.zipHeading() * 3
	column(
		model,
		"ZipPost",
		spec.zipTo.Y + 1.6,
		0.9,
		origin * CFrame.new(post.X, (spec.zipTo.Y + 1.6) / 2, post.Z),
		WOOD_DARK
	)
	beam(
		model,
		"ZipCable",
		world(spec.zipTo),
		world(Vector3.new(post.X, spec.zipTo.Y + 1.2, post.Z)),
		0.18,
		Color3.fromRGB(60, 60, 70)
	).CanCollide =
		false
	-- Шина-отбойник на тросе перед столбом.
	local stop = Vector3.new(post.X, spec.zipTo.Y + 1, post.Z) - Rides.zipHeading() * 1.2
	cylinder(
		model,
		"ZipBumper",
		0.9,
		2,
		origin * CFrame.lookAt(stop, stop + Rides.zipHeading()) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(45, 45, 50)
	).CanCollide =
		false
	-- Песочная яма там, куда приземляются, отпустив сиденье.
	local land = Rides.zipLanding()
	local pit = column(
		model,
		"ZipSand",
		0.3,
		9,
		origin * CFrame.new(land.X, 0.15, land.Z),
		Color3.fromRGB(240, 215, 150)
	)
	pit.Material = Enum.Material.Sand
	column(model, "ZipSandRim", 0.5, 10, origin * CFrame.new(land.X, 0.1, land.Z), WOOD_DARK)

	local heading = (spec.zipTo - spec.zipFrom) * Vector3.new(1, 0, 1)
	zipTrolley(model, world(Rides.zipPoint(0)), origin:VectorToWorldSpace(heading.Unit))
	boardPad(model, origin * CFrame.new(sm + Vector3.new(0, deck + 0.15, -smallHalf + 1.2)), "AF_ZipBoard")
	CollectionService:AddTag(model, "AF_Zip")
end

return RidesBuilder
