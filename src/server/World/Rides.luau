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
		-- Полотно: деревянная балка, поверх — тёмная колея. Край колеи виден снизу.
		part(track, "Beam", Vector3.new(5.2, 1.2, length), at * CFrame.new(0, -0.6, 0), WOOD).CanCollide =
			false
		part(track, "Rail", Vector3.new(4.2, 0.2, length), at * CFrame.new(0, 0.1, 0), WOOD_DARK).CanCollide =
			false
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

local function buildStation(parent: Instance)
	local station = Instance.new("Model")
	station.Name = "Station"
	station.Parent = parent
	local spec = Rides.STATION
	local frame = Rides.stationFrame()
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
	-- Навес: четыре столбика и крыша в полоску.
	for _, z in { -1, 1 } do
		for _, x in { 1 } do
			part(
				station,
				"Post",
				Vector3.new(0.5, 6, 0.5),
				base
					* CFrame.new(
						x * (spec.platformWidth / 2 - 0.6),
						top + 3,
						z * (spec.platformLength / 2 - 3)
					),
				WOOD_DARK
			).CanCollide =
				false
		end
	end
	for stripe = 1, 5 do
		local z = (stripe - 3) * (spec.platformLength - 6) / 5
		part(
			station,
			"Roof",
			Vector3.new(spec.platformWidth + 1, 0.4, (spec.platformLength - 6) / 5),
			base * CFrame.new(0, top + 6.2, z),
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
	CollectionService:AddTag(pad, "AF_TrainBoard")

	local sign = part(
		station,
		"Sign",
		Vector3.new(0.4, 2, 8),
		base * CFrame.new(spec.platformWidth / 2, top + 5, 0),
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
	buildStation(folder)
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

return RidesBuilder
