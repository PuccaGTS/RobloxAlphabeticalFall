--!nonstrict
--[[
	Строит игровые места парка (Config/Playground): батуты, музыкальную дорожку,
	классики, песочницу с мячами и горкой, шарики и лабиринт.

	Сервер только ставит детали и вешает метки CollectionService. Что происходит
	при касании — подпрыгнуть, звякнуть, лопнуть, — решает клиент
	(Controllers/PlaygroundController): награды здесь нет, проверять нечего.

	Единственное, что живёт на сервере, — мячи: они физические и общие для всех,
	и если мяч укатился за бортик, вернуть его должен кто-то один.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Playground = require(Shared.Config.Playground)
local Decor = require(Shared.Config.Decor)
local Rental = require(Shared.Config.Rental)
local RidesBuilder = require(script.Parent.Parent.World.Rides)
local RentalVehicles = require(script.Parent.Parent.World.RentalVehicles)
local Letter3D = require(script.Parent.Parent.World.Letter3D)
local Letters = require(Shared.Config.Letters)

local PlaygroundService = {}

local RAINBOW = {
	Color3.fromRGB(240, 90, 90),
	Color3.fromRGB(245, 150, 70),
	Color3.fromRGB(250, 210, 80),
	Color3.fromRGB(120, 205, 110),
	Color3.fromRGB(80, 190, 220),
	Color3.fromRGB(90, 130, 230),
	Color3.fromRGB(160, 110, 220),
	Color3.fromRGB(230, 120, 190),
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.Parent = parent
	return p
end

local function cylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	at: CFrame,
	color: Color3
)
	local p = part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		at * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function sign(parent: Instance, at: CFrame, text: string)
	local post = part(
		parent,
		"SignPost",
		Vector3.new(0.4, 5, 0.4),
		at * CFrame.new(0, 2.5, 0),
		Color3.fromRGB(150, 110, 70)
	)
	post.CanCollide = false
	local board = part(
		parent,
		"SignBoard",
		Vector3.new(6, 2, 0.4),
		at * CFrame.new(0, 5.5, 0),
		Color3.fromRGB(250, 240, 215)
	)
	board.CanCollide = false

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(70, 60, 50)
	label.Parent = gui
end

-- Точка места на земле, «лицом» к центру площади: так табличку видно с площади.
local function frameOf(spot): CFrame
	local position = Playground.position(spot)
	local ground = Decor.groundY(position.X, position.Z)
	local at = Vector3.new(position.X, ground, position.Z)
	return CFrame.lookAt(at, Vector3.new(0, ground, 0))
end

local BUILDERS = {}

-- Три батута разного размера: чем больше, тем выше подбрасывает.
function BUILDERS.trampolines(model: Model, origin: CFrame)
	local layout = { { -8, 4, 6 }, { 1, -5, 8 }, { 9, 5, 10 } }
	for index, spec in layout do
		local at = origin * CFrame.new(spec[1], 0, spec[2])
		local diameter = spec[3]
		cylinder(
			model,
			`TrampolineFrame_{index}`,
			1.6,
			diameter + 1.2,
			at * CFrame.new(0, 0.8, 0),
			Color3.fromRGB(70, 90, 140)
		)
		for leg = 1, 4 do
			local angle = leg / 4 * math.pi * 2
			part(
				model,
				`TrampolineLeg_{index}_{leg}`,
				Vector3.new(0.4, 1, 0.4),
				at * CFrame.new(math.cos(angle) * diameter / 2, 0.3, math.sin(angle) * diameter / 2),
				Color3.fromRGB(60, 60, 70)
			).CanCollide =
				false
		end
		local top = cylinder(
			model,
			`Trampoline_{index}`,
			0.3,
			diameter,
			at * CFrame.new(0, 1.75, 0),
			RAINBOW[index * 2]
		)
		top.Material = Enum.Material.Fabric
		top:SetAttribute("Power", Playground.TRAMPOLINE_POWER[index])
		CollectionService:AddTag(top, "AF_Trampoline")
	end
	sign(model, origin * CFrame.new(-12, 0, -8), "🤸")
end

-- Восемь клавиш дугой: наступил — нота. Слева низкие, справа высокие.
function BUILDERS.xylophone(model: Model, origin: CFrame)
	for index = 1, #Playground.NOTE_SPEEDS do
		local t = (index - 4.5) / 8
		local at = origin * CFrame.new(t * 22, 0, math.cos(t * 2) * -4) * CFrame.Angles(0, -t * 0.8, 0)
		local length = 7 - index * 0.35
		local key = part(
			model,
			`Note_{index}`,
			Vector3.new(2.3, 0.5, length),
			at * CFrame.new(0, 0.25, 0),
			RAINBOW[index]
		)
		key.Material = Enum.Material.Neon
		key:SetAttribute("Note", index)
		CollectionService:AddTag(key, "AF_Note")
		part(
			model,
			`NoteBase_{index}`,
			Vector3.new(2.7, 0.3, length + 0.4),
			at * CFrame.new(0, 0.1, 0),
			Color3.fromRGB(240, 240, 235)
		).CanCollide =
			false
	end
	sign(model, origin * CFrame.new(0, 0, 8), "🎵")
end

-- Классики: одна клетка, две рядом, одна, две... Каждая клетка называет своё число.
function BUILDERS.hopscotch(model: Model, origin: CFrame)
	local rows = { { 1 }, { 2, 3 }, { 4 }, { 5, 6 }, { 7 }, { 8, 9 }, { 10 } }
	for row, numbers in rows do
		for column, number in numbers do
			local x = if #numbers == 1 then 0 else (column - 1.5) * 4.4
			local at = origin * CFrame.new(x, 0.15, (row - 4) * 4.2)
			local tile =
				part(model, `Hop_{number}`, Vector3.new(4, 0.3, 4), at, RAINBOW[(number - 1) % #RAINBOW + 1])
			tile:SetAttribute("Number", number)
			CollectionService:AddTag(tile, "AF_Number")

			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 30
			gui.Parent = tile
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = tostring(number)
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
		end
	end
	sign(model, origin * CFrame.new(-6, 0, 14), "🔢")
end

-- Песочница с бортиком, мячами и горкой в углу.
function BUILDERS.sandbox(model: Model, origin: CFrame)
	local size = 26
	local sand = part(
		model,
		"Sand",
		Vector3.new(size, 0.4, size),
		origin * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(235, 215, 160)
	)
	sand.Material = Enum.Material.Sand
	for _, side in { -1, 1 } do
		for _, axis in { "x", "z" } do
			local along = if axis == "x" then Vector3.new(1, 1.6, size + 1) else Vector3.new(size + 1, 1.6, 1)
			local offset = if axis == "x"
				then Vector3.new(side * size / 2, 0.8, 0)
				else Vector3.new(0, 0.8, side * size / 2)
			local rim = part(
				model,
				`SandRim_{axis}_{side}`,
				along,
				origin * CFrame.new(offset),
				Color3.fromRGB(190, 140, 90)
			)
			rim.Material = Enum.Material.WoodPlanks
		end
	end

	-- Горка: лесенка сзади, площадка и скат вперёд.
	local slide = origin * CFrame.new(7, 0, -6)
	for step = 1, 5 do
		part(
			model,
			`SlideStep_{step}`,
			Vector3.new(3, 0.5, 1.2),
			slide * CFrame.new(0, step * 1.2, 4 + (5 - step) * 1.2),
			Color3.fromRGB(250, 200, 80)
		)
	end
	part(
		model,
		"SlideTop",
		Vector3.new(3.4, 0.6, 3),
		slide * CFrame.new(0, 6.3, 2),
		Color3.fromRGB(90, 150, 230)
	)
	local ramp = Instance.new("WedgePart")
	ramp.Name = "SlideRamp"
	ramp.Size = Vector3.new(3, 6, 9)
	-- Клин у Roblox высокий сзади (+Z): там и площадка, поворачивать не нужно.
	ramp.CFrame = slide * CFrame.new(0, 3.3, -4)
	ramp.Color = Color3.fromRGB(240, 100, 100)
	ramp.Material = Enum.Material.SmoothPlastic
	ramp.Anchored = true
	ramp.Parent = model

	for index = 1, Playground.BALL_COUNT do
		local ball = part(
			model,
			`Ball_{index}`,
			Vector3.one * 3.2,
			origin * CFrame.new(-6 + (index % 2) * 5, 3, -4 + index * 3),
			RAINBOW[index * 2 - 1]
		)
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = false
		ball.CustomPhysicalProperties = PhysicalProperties.new(0.25, 0.4, 0.6, 1, 1)
		ball:SetAttribute("Home", ball.CFrame)
		CollectionService:AddTag(ball, "AF_Ball")
	end
	sign(model, origin * CFrame.new(-14, 0, 12), "⚽")
end

-- Шарики на ниточках: коснулся — лопнул (у каждого ребёнка свой), потом вырос снова.
function BUILDERS.balloons(model: Model, origin: CFrame)
	local stake = part(
		model,
		"BalloonStake",
		Vector3.new(0.6, 1.2, 0.6),
		origin * CFrame.new(0, 0.6, 0),
		Color3.fromRGB(150, 110, 70)
	)
	stake.CanCollide = false
	for index = 1, Playground.BALLOON_COUNT do
		local angle = index / Playground.BALLOON_COUNT * math.pi * 2
		local height = 5 + (index % 3) * 1.4
		local at = origin * CFrame.new(math.cos(angle) * 3.5, height, math.sin(angle) * 3.5)
		local balloon = part(model, `Balloon_{index}`, Vector3.new(2.4, 2.9, 2.4), at, RAINBOW[index])
		balloon.Shape = Enum.PartType.Ball
		balloon.Material = Enum.Material.Glass
		balloon.Transparency = 0.1
		balloon.CanCollide = false
		CollectionService:AddTag(balloon, "AF_Balloon")

		-- Ниточка от колышка к низу шарика: деталь вытянута по Y, поэтому поворот на четверть.
		local bottom = origin.Position + Vector3.new(0, 1.2, 0)
		local top = at.Position - Vector3.new(0, 1.4, 0)
		local rope = part(
			model,
			`BalloonString_{index}`,
			Vector3.new(0.08, (top - bottom).Magnitude, 0.08),
			CFrame.lookAt((bottom + top) / 2, top) * CFrame.Angles(math.rad(90), 0, 0),
			Color3.fromRGB(240, 240, 240)
		)
		rope.CanCollide = false
		rope.CanTouch = false
		rope.Parent = balloon
	end
	sign(model, origin * CFrame.new(0, 0, 7), "🎈")
end

--[[
	Паркур-гора. Платформы идут спиралью вокруг столба, каждая на полтора студа
	выше предыдущей, между ними шаг меньше двух студов: прыжок простой,
	промахнулся — упал в траву и начал снова, ничего не потеряно. Батут у подножия
	забрасывает на середину спирали. Наверху площадка с перилами и колокольчик —
	дошёл, он звенит и искрит (тот же обработчик, что у флажка в лабиринте).
	Вниз — по скату, а не прыжком с высоты.
]]
local OBBY_STEPS = 10
local OBBY_RADIUS = 10
local OBBY_RISE = 1.5
local OBBY_TOP = 2 + (OBBY_STEPS + 1) * OBBY_RISE

function BUILDERS.obby(model: Model, origin: CFrame)
	local center = origin * CFrame.new(0, 0, 6)
	cylinder(
		model,
		"ObbyPole",
		OBBY_TOP,
		3,
		center * CFrame.new(0, OBBY_TOP / 2, 0),
		Color3.fromRGB(250, 245, 235)
	)

	-- Три ступеньки к первой платформе: начать можно без прыжка.
	local firstAngle = math.rad(200)
	for step = 1, 3 do
		local r = OBBY_RADIUS + 3 + (3 - step) * 2.2
		part(
			model,
			`ObbyStart_{step}`,
			Vector3.new(3.4, step * 0.9, 3.4),
			center * CFrame.new(math.cos(firstAngle - 0.35) * r, step * 0.45, math.sin(firstAngle - 0.35) * r),
			RAINBOW[step]
		)
	end

	for index = 1, OBBY_STEPS do
		local angle = firstAngle + index * math.rad(32)
		local y = 2 + index * OBBY_RISE
		local pad = part(
			model,
			`ObbyStep_{index}`,
			Vector3.new(3.6, 1, 3.6),
			center * CFrame.new(math.cos(angle) * OBBY_RADIUS, y - 0.5, math.sin(angle) * OBBY_RADIUS),
			RAINBOW[(index - 1) % #RAINBOW + 1]
		)
		pad.Material = Enum.Material.SmoothPlastic
		-- Ножка до земли: платформа не висит в воздухе, а стоит на тонкой опоре.
		local leg = part(
			model,
			`ObbyLeg_{index}`,
			Vector3.new(0.5, y - 1, 0.5),
			center * CFrame.new(math.cos(angle) * OBBY_RADIUS, (y - 1) / 2, math.sin(angle) * OBBY_RADIUS),
			Color3.fromRGB(240, 240, 245)
		)
		leg.CanCollide = false
	end

	local top = cylinder(
		model,
		"ObbyTop",
		1,
		14,
		center * CFrame.new(0, OBBY_TOP - 0.5, 0),
		Color3.fromRGB(120, 200, 255)
	)
	top.Material = Enum.Material.SmoothPlastic
	for post = 1, 10 do
		local angle = post / 10 * math.pi * 2
		if math.abs(math.sin(angle) - 1) > 0.1 then -- проём над скатом
			part(
				model,
				`ObbyRail_{post}`,
				Vector3.new(0.5, 2.2, 0.5),
				center * CFrame.new(math.cos(angle) * 6.6, OBBY_TOP + 1.1, math.sin(angle) * 6.6),
				RAINBOW[(post - 1) % #RAINBOW + 1]
			)
		end
	end

	local bell = part(
		model,
		"ObbyBell",
		Vector3.new(2.4, 2.4, 2.4),
		center * CFrame.new(0, OBBY_TOP + 3.2, 0),
		Color3.fromRGB(255, 210, 70)
	)
	bell.Shape = Enum.PartType.Ball
	bell.Material = Enum.Material.Neon
	bell.CanCollide = false
	CollectionService:AddTag(bell, "AF_MazeFlag")
	cylinder(
		model,
		"ObbyBellStand",
		2,
		0.4,
		center * CFrame.new(0, OBBY_TOP + 1, 0),
		Color3.fromRGB(240, 240, 245)
	)

	-- Скат от края площадки наружу, прочь от площади.
	local from = Vector3.new(0, OBBY_TOP, 6.5)
	local to = Vector3.new(0, 0.3, 6.5 + 22)
	local length = (to - from).Magnitude
	local tilt = math.atan2(from.Y - to.Y, to.Z - from.Z)
	local slide = part(
		model,
		"ObbySlide",
		Vector3.new(3.4, 0.4, length),
		center * CFrame.new((from + to) / 2) * CFrame.Angles(tilt, 0, 0),
		Color3.fromRGB(255, 140, 90)
	)
	slide.Material = Enum.Material.SmoothPlastic
	for _, side in { -1, 1 } do
		part(
			model,
			`ObbySlideRail_{side}`,
			Vector3.new(0.4, 1.4, length),
			center * CFrame.new((from + to) / 2 + Vector3.new(side * 1.9, 0.6, 0)) * CFrame.Angles(tilt, 0, 0),
			Color3.fromRGB(255, 220, 90)
		)
	end

	-- Батут с внешней стороны спирали, под пятой-шестой платформами.
	local trampolineAngle = firstAngle + 5.5 * math.rad(32)
	local tramp = center
		* CFrame.new(
			math.cos(trampolineAngle) * (OBBY_RADIUS + 5.5),
			0,
			math.sin(trampolineAngle) * (OBBY_RADIUS + 5.5)
		)
	cylinder(model, "ObbyTrampolineFrame", 1.2, 6, tramp * CFrame.new(0, 0.6, 0), Color3.fromRGB(70, 90, 140))
	local mat = cylinder(
		model,
		"ObbyTrampoline",
		0.3,
		5,
		tramp * CFrame.new(0, 1.35, 0),
		Color3.fromRGB(255, 120, 170)
	)
	mat.Material = Enum.Material.Fabric
	mat:SetAttribute("Power", 80)
	CollectionService:AddTag(mat, "AF_Trampoline")

	sign(model, origin * CFrame.new(-8, 0, -14), "🧗")
end

-- Лабиринт из кустов с флажком в середине.
function BUILDERS.maze(model: Model, origin: CFrame)
	local rows = Playground.MAZE
	local cell = Playground.MAZE_CELL
	local half = (#rows + 1) / 2
	for row, line in rows do
		for column = 1, #line do
			local char = string.sub(line, column, column)
			local at = origin * CFrame.new((column - half) * cell, 0, (row - half) * cell)
			if char == "#" then
				local hedge = part(
					model,
					`Hedge_{row}_{column}`,
					Vector3.new(cell, 5, cell),
					at * CFrame.new(0, 2.5, 0),
					Color3.fromRGB(95, 160, 95)
				)
				hedge.Material = Enum.Material.Grass
			elseif char == "*" then
				part(
					model,
					"MazePole",
					Vector3.new(0.4, 7, 0.4),
					at * CFrame.new(0, 3.5, 0),
					Color3.fromRGB(245, 245, 250)
				).CanCollide =
					false
				local flag = part(
					model,
					"MazeFlag",
					Vector3.new(2.4, 1.5, 0.2),
					at * CFrame.new(1.3, 6.2, 0),
					Color3.fromRGB(245, 120, 90)
				)
				flag.CanCollide = false
				CollectionService:AddTag(flag, "AF_MazeFlag")
			end
		end
	end
	sign(model, origin * CFrame.new(0, 0, (half + 1) * cell), "🌿")
end

-- Колесо обозрения: строит World/Rides, крутит и катает RideController.
function BUILDERS.ferris(model: Model, origin: CFrame)
	RidesBuilder.buildWheel(model, origin)
	sign(model, origin * CFrame.new(9, 0, -9), "🎡")
end

-- Карусель, горка и воздушный шар: строит World/Rides, катает RideController.
function BUILDERS.carousel(model: Model, origin: CFrame)
	RidesBuilder.buildCarousel(model, origin)
	sign(model, origin * CFrame.new(11, 0, -12), "🎠")
end

--[[
	Грот с кристаллами: каменный холм с круглой пещерой внутри. Вход смотрит
	на площадь, и на него льётся водопад с каменного козырька — сквозь завесу
	проходишь насквозь (она не твёрдая). Внутри полумрак, каменный пол, сосульки
	сталактитов, по стенам светятся друзы кристаллов: тронул — кристалл
	вспыхивает и звенит своей нотой (PlaygroundController, метка AF_Crystal).
	У дальней стены шестой сундук (Config/Chests, chest_grotto).
]]
local ROCK = Color3.fromRGB(125, 130, 150)
local ROCK_DARK = Color3.fromRGB(95, 100, 120)
local MOSS = Color3.fromRGB(100, 160, 85)
local CRYSTALS = {
	Color3.fromRGB(255, 70, 170),
	Color3.fromRGB(150, 80, 255),
	Color3.fromRGB(40, 160, 255),
	Color3.fromRGB(30, 220, 190),
	Color3.fromRGB(110, 230, 60),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(255, 120, 40),
	Color3.fromRGB(90, 110, 255),
}

function BUILDERS.grotto(model: Model, origin: CFrame)
	local spec = Playground.GROTTO
	local radius = spec.radius
	local height = spec.height
	local door = -math.pi / 2 -- к площади
	local function around(a: number, r: number, y: number): CFrame
		return origin * CFrame.new(math.cos(a) * r, y, math.sin(a) * r)
	end
	local function fromDoor(a: number): number
		return math.abs(math.atan2(math.sin(a - door), math.cos(a - door)))
	end

	-- Стены: каменные плиты по кругу, у входа проём шириной doorway.
	local segments = 24
	local halfDoor = spec.doorway / 2 / radius
	for index = 0, segments - 1 do
		local a = (index + 0.5) / segments * math.pi * 2
		if fromDoor(a) < halfDoor + 0.05 then
			continue
		end
		local width = 2 * math.pi * (radius + 1.5) / segments + 0.9
		local slab = part(
			model,
			"GrottoWall",
			Vector3.new(3, height + 1, width),
			around(a, radius + 1.5, (height + 1) / 2)
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, math.rad(-6)),
			if index % 3 == 0 then ROCK_DARK else ROCK
		)
		slab.Material = Enum.Material.Slate
	end
	-- Косяки входа: два валуна по бокам проёма.
	for _, side in { -1, 1 } do
		local a = door + side * (halfDoor + 0.2)
		local boulder = part(
			model,
			"GrottoDoorRock",
			Vector3.new(5, height + 2, 5),
			around(a, radius + 1.8, (height + 2) / 2) * CFrame.Angles(0, side * 0.5, side * math.rad(4)),
			ROCK_DARK
		)
		boulder.Material = Enum.Material.Slate
	end

	-- Потолок и холм сверху: камень, мох и цветы — снаружи это просто холмик.
	local roof =
		cylinder(model, "GrottoRoof", 2.5, (radius + 3) * 2, origin * CFrame.new(0, height + 1.25, 0), ROCK)
	roof.Material = Enum.Material.Slate
	local random = Random.new(320)
	for index = 1, 8 do
		local a = index / 8 * math.pi * 2
		local r = if index % 4 == 0 then 0 else random:NextNumber(4, 8)
		local size = random:NextNumber(8, 12)
		local lump = part(
			model,
			"GrottoHill",
			Vector3.new(size, size * 0.6, size),
			origin * CFrame.new(math.cos(a) * r, height + 2 + size * 0.15, math.sin(a) * r),
			if index % 2 == 0 then MOSS else ROCK
		)
		lump.Shape = Enum.PartType.Ball
		lump.Material = if index % 2 == 0 then Enum.Material.Grass else Enum.Material.Slate
		lump.CanCollide = false
	end
	for index = 1, 6 do
		local a = random:NextNumber(0, math.pi * 2)
		local bloom = part(
			model,
			"GrottoFlower",
			Vector3.new(0.9, 0.9, 0.9),
			origin * CFrame.new(math.cos(a) * 5, height + 5.2, math.sin(a) * 5),
			RAINBOW[index]
		)
		bloom.Shape = Enum.PartType.Ball
		bloom.CanCollide = false
	end

	-- Снаружи холм обложен валунами, по ним мох: издали — каменная горка, а не короб.
	for index = 0, 17 do
		local a = (index + 0.3) / 18 * math.pi * 2
		if fromDoor(a) < halfDoor + 0.35 then
			continue
		end
		local size = random:NextNumber(5.5, 8.5)
		local rock = part(
			model,
			"GrottoBoulder",
			Vector3.new(size, size * random:NextNumber(0.8, 1.3), size),
			around(a, radius + 3.8, size * 0.35)
				* CFrame.Angles(random:NextNumber(-0.4, 0.4), a, random:NextNumber(-0.4, 0.4)),
			if index % 3 == 0 then ROCK_DARK else ROCK
		)
		rock.Material = Enum.Material.Slate
		if index % 2 == 0 then
			local moss = part(
				model,
				"GrottoMoss",
				Vector3.new(size * 0.8, size * 0.35, size * 0.8),
				around(a, radius + 3.8, size * 0.35 + size * 0.45),
				MOSS
			)
			moss.Shape = Enum.PartType.Ball
			moss.Material = Enum.Material.Grass
			moss.CanCollide = false
		end
	end
	for index = 0, 9 do
		local a = (index + 0.5) / 10 * math.pi * 2
		if fromDoor(a) < halfDoor + 0.2 then
			continue
		end
		local size = random:NextNumber(6, 9)
		local shoulder = part(
			model,
			"GrottoShoulder",
			Vector3.new(size, size * 0.7, size),
			around(a, radius + 2, height + 2.5 + size * 0.1),
			if index % 2 == 0 then MOSS else ROCK
		)
		shoulder.Shape = Enum.PartType.Ball
		shoulder.Material = if index % 2 == 0 then Enum.Material.Grass else Enum.Material.Slate
		shoulder.CanCollide = false
	end

	-- Пол пещеры и сталактиты с потолка.
	local floor =
		cylinder(model, "GrottoFloor", 0.3, radius * 2 + 1, origin * CFrame.new(0, 0.15, 0), ROCK_DARK)
	floor.Material = Enum.Material.Slate
	for index = 1, 7 do
		local a = index / 7 * math.pi * 2 + 0.3
		local r = random:NextNumber(3, radius - 2)
		local long = random:NextNumber(1.5, 3)
		local drip = cylinder(
			model,
			"Stalactite",
			long,
			random:NextNumber(0.5, 0.9),
			origin * CFrame.new(math.cos(a) * r, height - long / 2, math.sin(a) * r),
			ROCK
		)
		drip.Material = Enum.Material.Slate
		drip.CanCollide = false
	end

	-- Друзы кристаллов по стенам: главный кристалл звенит, два поменьше рядом.
	for index, degrees in spec.crystals do
		local a = math.rad(degrees)
		local base = around(a, spec.crystalRing, 0) * CFrame.Angles(0, -a, 0)
		local color = CRYSTALS[(index - 1) % #CRYSTALS + 1]
		local sizes = { Vector3.new(1.4, 4.2, 1.4), Vector3.new(1, 2.8, 1), Vector3.new(0.9, 2.2, 0.9) }
		local offsets = {
			CFrame.new(0, 2, 0) * CFrame.Angles(0, math.rad(45), math.rad(12)),
			CFrame.new(0.5, 1.3, 1.1) * CFrame.Angles(math.rad(-20), math.rad(20), math.rad(25)),
			CFrame.new(0.4, 1.1, -1.1) * CFrame.Angles(math.rad(22), math.rad(-15), math.rad(18)),
		}
		for piece = 1, 3 do
			local shard = part(
				model,
				if piece == 1 then `Crystal_{index}` else "CrystalShard",
				sizes[piece],
				base * offsets[piece],
				color
			)
			shard.Material = Enum.Material.Neon
			shard.Transparency = 0.05
			shard.CanCollide = piece == 1
			if piece == 1 then
				shard:SetAttribute("Note", (index - 1) % #Playground.NOTE_SPEEDS + 1)
				CollectionService:AddTag(shard, "AF_Crystal")
			end
		end
	end

	-- Козырёк над входом и водопад с него: завеса воды, сквозь которую проходишь.
	local lip = part(
		model,
		"GrottoLip",
		Vector3.new(spec.doorway + 3, 1.6, 4),
		origin * CFrame.new(0, height + 0.4, -(radius + 2.2)),
		ROCK
	)
	lip.Material = Enum.Material.Slate
	local curtain = part(
		model,
		"WaterCurtain",
		Vector3.new(spec.doorway + 1, height, 0.4),
		origin * CFrame.new(0, height / 2, -(radius + 3.6)),
		Color3.fromRGB(150, 210, 250)
	)
	curtain.Material = Enum.Material.Glass
	curtain.Transparency = 0.45
	curtain.Reflectance = 0.2
	curtain.CanCollide = false
	curtain.CanQuery = false
	-- Струи: белые полосы бегут вниз по завесе, у земли — брызги.
	local streams = Instance.new("ParticleEmitter")
	streams.Name = "Streams"
	streams.Texture = "rbxasset://textures/particles/smoke_main.dds"
	streams.EmissionDirection = Enum.NormalId.Bottom
	streams.Orientation = Enum.ParticleOrientation.VelocityParallel
	streams.Squash = NumberSequence.new(2.5)
	streams.Speed = NumberRange.new(16, 22)
	streams.Lifetime = NumberRange.new(0.45, 0.6)
	streams.Rate = 40
	streams.SpreadAngle = Vector2.new(2, 2)
	streams.Size = NumberSequence.new(0.9)
	streams.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.8) })
	streams.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255))
	local source = part(
		model,
		"WaterSource",
		Vector3.new(spec.doorway + 1, 0.2, 0.3),
		origin * CFrame.new(0, height - 0.3, -(radius + 3.6)),
		Color3.new(1, 1, 1)
	)
	source.Transparency = 1
	source.CanCollide = false
	source.CanQuery = false
	source.CanTouch = false
	streams.Parent = source
	local pool = cylinder(
		model,
		"GrottoPool",
		0.2,
		9,
		origin * CFrame.new(0, 0.2, -(radius + 4.5)),
		Color3.fromRGB(80, 170, 230)
	)
	pool.Material = Enum.Material.Glass
	pool.Transparency = 0.2
	pool.CanCollide = false
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Speed = NumberRange.new(3, 6)
	spray.Lifetime = NumberRange.new(0.6, 1)
	spray.Rate = 14
	spray.SpreadAngle = Vector2.new(60, 60)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.5) })
	spray.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	spray.Parent = pool

	sign(model, origin * CFrame.new(spec.doorway + 2, 0, -(radius + 6)), "💎")
end

--[[
	Азбука-дорожка: плитки А…Я змейкой по белым бордюрам, на каждой — буква
	крупно, цвет — по ступени алфавита (как на Башне). У А флажок «старт»,
	у Я — золотая звезда на столбике. Звучит и загорается всё у ребёнка
	(PlaygroundController, метка AF_AbcTile).
]]
function BUILDERS.abcpath(model: Model, origin: CFrame)
	local spec = Playground.ABC
	local ordered = Letters.ordered()
	for order, id in ordered do
		local letter = Letters.expect(id)
		local at = origin * CFrame.new(Playground.abcTile(order))
		local color = RAINBOW[(letter.stage - 1) % #RAINBOW + 1]
		part(
			model,
			`AbcBorder_{order}`,
			Vector3.new(spec.tile + 0.6, 0.3, spec.tile + 0.6),
			at * CFrame.new(0, 0.15, 0),
			Color3.fromRGB(250, 248, 240)
		).CanCollide =
			false
		local tile = part(
			model,
			`Abc_{order}`,
			Vector3.new(spec.tile, 0.4, spec.tile),
			at * CFrame.new(0, 0.3, 0),
			color
		)
		tile:SetAttribute("Order", order)
		tile:SetAttribute("Letter", id)
		CollectionService:AddTag(tile, "AF_AbcTile")
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = tile
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = letter.glyph
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.fromRGB(60, 60, 90)
		-- Буква читается от площади: низ буквы — к ней.
		label.Rotation = 180
		label.Parent = gui
	end
	-- Флажок у А и звезда у Я: где начало и где конец дорожки.
	local first = origin * CFrame.new(Playground.abcTile(1))
	local pole = part(
		model,
		"AbcStartPole",
		Vector3.new(0.3, 5, 0.3),
		first * CFrame.new(spec.tile / 2 + 1, 2.5, 0),
		Color3.fromRGB(245, 245, 245)
	)
	pole.CanCollide = false
	part(
		model,
		"AbcStartFlag",
		Vector3.new(0.12, 1.4, 2.2),
		first * CFrame.new(spec.tile / 2 + 1, 4.3, -1.1),
		Color3.fromRGB(90, 200, 110)
	).CanCollide =
		false
	local last = origin * CFrame.new(Playground.abcTile(#ordered))
	local lastX = if #spec.rows % 2 == 1 then -1 else 1
	local post = part(
		model,
		"AbcFinishPost",
		Vector3.new(0.4, 4, 0.4),
		last * CFrame.new(lastX * (spec.tile / 2 + 1), 2, 0),
		Color3.fromRGB(245, 245, 245)
	)
	post.CanCollide = false
	local gold = part(
		model,
		"AbcFinishStar",
		Vector3.new(1.8, 1.8, 1.8),
		last * CFrame.new(lastX * (spec.tile / 2 + 1), 4.6, 0),
		Color3.fromRGB(255, 205, 60)
	)
	gold.Shape = Enum.PartType.Ball
	gold.Material = Enum.Material.Neon
	gold.CanCollide = false
	sign(model, origin * CFrame.new(-spec.pitch * 4.5, 0, -spec.rowGap * 3), "🔤")
end

-- Корабль-качели: строит World/Rides, качает и катает RideController.
function BUILDERS.ship(model: Model, origin: CFrame)
	RidesBuilder.buildShip(model, origin)
	sign(model, origin * CFrame.new(10, 0, -13), "🏴‍☠️")
end

-- Домик на дереве с подвесным мостиком и тарзанкой: строит World/Rides, катает RideController.
function BUILDERS.treehouse(model: Model, origin: CFrame)
	RidesBuilder.buildTreehouse(model, origin)
	sign(model, origin * CFrame.new(-4, 0, -22), "🌳")
end

function BUILDERS.slide(model: Model, origin: CFrame)
	RidesBuilder.buildSlide(model, origin)
	sign(model, origin * CFrame.new(8, 0, -14), "🌀")
end

-- Озеро с лодочками-лебедями: воду, мостки и лодочки строит World/Rides, здесь — берег.
function BUILDERS.lake(model: Model, origin: CFrame)
	RidesBuilder.buildSwans(model, origin)
	local lake = RidesBuilder.SWAN_LAKE
	local DecorService = require(script.Parent.DecorService)
	-- Цветущее дерево на островке: его видно с дорожки к домам.
	local tree = DecorService.modelFor("tree_blossom", 1.2)
	if tree then
		tree.Name = "IslandTree"
		tree:PivotTo(origin)
		local box, extent = tree:GetBoundingBox()
		tree:PivotTo(
			tree:GetPivot()
				+ Vector3.new(
					origin.X - box.Position.X,
					origin.Y + 0.8 - (box.Position.Y - extent.Y / 2),
					origin.Z - box.Position.Z
				)
		)
		tree.Parent = model
	end
	-- Кувшинки на воде и камыш у берега, но не на пути лодочек.
	local random = Random.new(12)
	for index = 1, 10 do
		local a = index / 10 * math.pi * 2 + random:NextNumber(0, 0.4)
		local r = if index % 2 == 0 then lake.loop + 4.5 else lake.island + 2.5
		local at = origin * CFrame.new(math.cos(a) * r, 0.42, math.sin(a) * r)
		local pad = cylinder(model, `LilyPad_{index}`, 0.1, 1.8, at, Color3.fromRGB(80, 170, 80))
		pad.CanCollide = false
		if index % 3 == 0 then
			local lily = part(
				model,
				`Lily_{index}`,
				Vector3.new(0.7, 0.7, 0.7),
				at * CFrame.new(0.2, 0.3, 0),
				Color3.fromRGB(255, 180, 210)
			)
			lily.Shape = Enum.PartType.Ball
			lily.CanCollide = false
		end
	end
	for index = 1, 14 do
		local a = index / 14 * math.pi * 2 + random:NextNumber(-0.1, 0.1)
		-- Со стороны мостков камыша нет: проход к воде.
		if math.abs(math.sin(a) + 1) < 0.25 then
			continue
		end
		local r = lake.lake + random:NextNumber(0.5, 1.8)
		for stalk = 1, 3 do
			local at = origin * CFrame.new(math.cos(a) * r + stalk * 0.4 - 0.8, 0, math.sin(a) * r)
			local height = 2.5 + random:NextNumber(0, 1.5)
			local reed = part(
				model,
				`Reed_{index}_{stalk}`,
				Vector3.new(0.18, height, 0.18),
				at
					* CFrame.new(0, height / 2, 0)
					* CFrame.Angles(random:NextNumber(-0.15, 0.15), 0, random:NextNumber(-0.15, 0.15)),
				Color3.fromRGB(90, 150, 70)
			)
			reed.CanCollide = false
			local top = part(
				model,
				`ReedTop_{index}_{stalk}`,
				Vector3.new(0.35, 0.9, 0.35),
				reed.CFrame * CFrame.new(0, height / 2 - 0.3, 0),
				Color3.fromRGB(130, 85, 50)
			)
			top.CanCollide = false
		end
	end
	sign(model, origin * CFrame.new(-5, 0, -(lake.lake + 4)), "🦢")
end

function BUILDERS.balloon(model: Model, origin: CFrame)
	RidesBuilder.buildBalloon(model, origin)
	sign(model, origin * CFrame.new(8, 0, -9), "🎈")
end

--[[
	Тайный сад: круг высоких кустов. С площади видна только зелёная стена;
	вход — с дальней стороны, занавес из листвы, сквозь который проходишь
	(там кусты не твёрдые). К нему ведут камешки-следы вокруг круга. Внутри —
	светлая полянка, светящиеся грибы, светлячки, гирлянда между кустами,
	прудик с кувшинкой и сундук у стены (Config/Chests, chest_secret).
]]
local HEDGE = Color3.fromRGB(60, 135, 70)
local HEDGE_LIGHT = Color3.fromRGB(85, 160, 80)

function BUILDERS.secret(model: Model, origin: CFrame)
	local radius = Playground.SECRET_RADIUS
	local height = Playground.SECRET_HEDGE
	local segments = 22
	-- Вход — за садом, если смотреть с площади: +Z кадра origin.
	local entrance = math.pi / 2
	local function around(a: number, r: number, y: number): CFrame
		return origin * CFrame.new(math.cos(a) * r, y, math.sin(a) * r)
	end
	local function isEntrance(a: number): boolean
		return math.abs(math.atan2(math.sin(a - entrance), math.cos(a - entrance)))
			< math.pi / segments + 0.01
	end

	for index = 0, segments - 1 do
		local a = index / segments * math.pi * 2
		local width = 2 * math.pi * radius / segments + 0.8
		local wall = part(
			model,
			if isEntrance(a) then "LeafCurtain" else "Hedge",
			Vector3.new(3, height, width),
			around(a, radius, height / 2) * CFrame.Angles(0, -a, 0),
			if index % 2 == 0 then HEDGE else HEDGE_LIGHT
		)
		wall.Material = Enum.Material.Grass
		-- Кудрявый верх: шары листвы по кромке.
		local top = part(
			model,
			"HedgeTop",
			Vector3.new(3.6, 3.6, 3.6),
			around(a, radius, height + 0.2),
			if index % 2 == 0 then HEDGE_LIGHT else HEDGE
		)
		top.Shape = Enum.PartType.Ball
		top.Material = Enum.Material.Grass
		top.CanCollide = false
		if isEntrance(a) then
			-- Занавес: та же листва, но сквозь неё проходишь. Чуть светлее — для того, кто ищет.
			wall.CanCollide = false
			wall.Transparency = 0.15
			wall.Color = Color3.fromRGB(110, 175, 90)
		end
	end

	-- Полянка внутри: светлая трава и ковёр цветов.
	local lawn = cylinder(
		model,
		"Lawn",
		0.2,
		radius * 2 - 2,
		origin * CFrame.new(0, 0.1, 0),
		Color3.fromRGB(150, 210, 120)
	)
	lawn.Material = Enum.Material.Grass
	lawn.CanCollide = false
	local random = Random.new(276)
	for index = 1, 40 do
		local a = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(2, radius - 2.5)
		local flower = part(
			model,
			"Flower",
			Vector3.new(0.6, 0.6, 0.6),
			origin * CFrame.new(math.cos(a) * r, 0.35, math.sin(a) * r),
			RAINBOW[(index - 1) % #RAINBOW + 1]
		)
		flower.Shape = Enum.PartType.Ball
		flower.CanCollide = false
	end

	-- Светящиеся грибы по кругу у стены.
	for index = 1, 7 do
		local a = entrance + math.pi + (index - 4) * 0.55
		local at = around(a, radius - 2.3, 0)
		local size = 0.8 + (index % 3) * 0.35
		local stem = cylinder(
			model,
			"GlowStem",
			size * 1.4,
			size * 0.45,
			at * CFrame.new(0, size * 0.7, 0),
			Color3.fromRGB(250, 245, 230)
		)
		stem.CanCollide = false
		-- Шляпка: плоский диск и купол над ним. Цвет густой — неон светлые цвета выбеливает.
		local color = if index % 2 == 0 then Color3.fromRGB(30, 150, 210) else Color3.fromRGB(150, 70, 220)
		local brim =
			cylinder(model, "GlowCap", size * 0.35, size * 1.9, at * CFrame.new(0, size * 1.45, 0), color)
		brim.Material = Enum.Material.Neon
		brim.CanCollide = false
		local dome = part(
			model,
			"GlowDome",
			Vector3.new(size * 1.3, size * 1.3, size * 1.3),
			at * CFrame.new(0, size * 1.6, 0),
			color
		)
		dome.Shape = Enum.PartType.Ball
		dome.Material = Enum.Material.Neon
		dome.CanCollide = false
		local dot = part(
			model,
			"GlowDot",
			Vector3.new(size * 0.35, size * 0.35, size * 0.35),
			at * CFrame.new(size * 0.35, size * 2.1, 0),
			Color3.fromRGB(255, 255, 255)
		)
		dot.Shape = Enum.PartType.Ball
		dot.CanCollide = false
	end

	-- Прудик с кувшинкой — справа от входа.
	local pond = cylinder(
		model,
		"SecretPond",
		0.25,
		5.5,
		around(entrance - 0.9, radius - 5.5, 0.12),
		Color3.fromRGB(90, 170, 220)
	)
	pond.Material = Enum.Material.Glass
	pond.Transparency = 0.2
	pond.CanCollide = false
	local lily = cylinder(
		model,
		"Lily",
		0.1,
		1.6,
		around(entrance - 0.85, radius - 5, 0.28),
		Color3.fromRGB(90, 180, 90)
	)
	lily.CanCollide = false
	local bloom = part(
		model,
		"LilyBloom",
		Vector3.new(0.6, 0.6, 0.6),
		around(entrance - 0.85, radius - 5, 0.55),
		Color3.fromRGB(255, 190, 220)
	)
	bloom.Shape = Enum.PartType.Ball
	bloom.CanCollide = false

	-- Гирлянда: огоньки дугой через сад, от стены к стене.
	local from = around(entrance + 1.2, radius - 0.5, height + 1)
	local to = around(entrance + math.pi - 0.3, radius - 0.5, height + 1)
	local bulbs = 16
	for index = 0, bulbs do
		local t = index / bulbs
		local point = from.Position:Lerp(to.Position, t) - Vector3.new(0, math.sin(t * math.pi) * 2.5, 0)
		local bulb = part(
			model,
			"FairyLight",
			Vector3.new(0.45, 0.45, 0.45),
			CFrame.new(point),
			RAINBOW[index % #RAINBOW + 1]
		)
		bulb.Shape = Enum.PartType.Ball
		bulb.Material = Enum.Material.Neon
		bulb.CanCollide = false
	end

	-- Светлячки: медленные искры над полянкой.
	local air = part(
		model,
		"Fireflies",
		Vector3.new(radius * 1.6, 4, radius * 1.6),
		origin * CFrame.new(0, 3, 0),
		Color3.new(1, 1, 1)
	)
	air.Transparency = 1
	air.CanCollide = false
	air.CanQuery = false
	air.CanTouch = false
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glow.Color = ColorSequence.new(Color3.fromRGB(230, 255, 120), Color3.fromRGB(255, 220, 100))
	glow.LightEmission = 1
	glow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	glow.Lifetime = NumberRange.new(3, 5)
	glow.Rate = 6
	glow.Speed = NumberRange.new(0.3, 0.8)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.Parent = air

	-- Камешки-следы от площади вокруг круга ко входу: кто пойдёт по ним, найдёт.
	for index = 0, 9 do
		local a = entrance + math.pi - 0.5 - index * 0.36
		local stone =
			cylinder(model, "StepStone", 0.2, 1.5, around(a, radius + 3, 0.1), Color3.fromRGB(215, 210, 200))
		stone.CanCollide = false
	end
end

--[[
	Фото-зона: небесный задник с радугой в золотой раме, по бокам объёмные
	А и Я, перед рамкой — метка с фотоаппаратом. Встал на метку — снимок
	(PlaygroundController, AF_PhotoMark). Рама смотрит на площадь: оттуда
	к ней и подходят, и «фотограф» стоит там же.
]]
local GOLD = Color3.fromRGB(255, 205, 80)

local function rainbowBackdrop(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.2
	gui.Parent = board

	-- Радуга: вложенные круги, у контейнера видна только верхняя половина.
	local arc = Instance.new("Frame")
	arc.AnchorPoint = Vector2.new(0.5, 1)
	arc.Position = UDim2.fromScale(0.5, 0.92)
	arc.Size = UDim2.fromScale(0.86, 0.62)
	arc.BackgroundTransparency = 1
	arc.ClipsDescendants = true
	arc.Parent = gui
	for index, color in RAINBOW do
		local share = 1 - (index - 1) * 0.085
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 1)
		ring.Size = UDim2.fromScale(share, share * 2)
		ring.BackgroundColor3 = color
		ring.BorderSizePixel = 0
		ring.ZIndex = index
		ring.Parent = arc
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ring
	end
	local sky = Instance.new("Frame")
	sky.AnchorPoint = Vector2.new(0.5, 0.5)
	sky.Position = UDim2.fromScale(0.5, 1)
	sky.Size = UDim2.fromScale(0.3, 0.6)
	sky.BackgroundColor3 = board.Color
	sky.BorderSizePixel = 0
	sky.ZIndex = #RAINBOW + 1
	sky.Parent = arc
	local skyCorner = Instance.new("UICorner")
	skyCorner.CornerRadius = UDim.new(1, 0)
	skyCorner.Parent = sky

	local function label(text: string, position: UDim2, size: UDim2, color: Color3)
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = position
		l.Size = size
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextScaled = true
		l.Font = Enum.Font.FredokaOne
		l.TextColor3 = color
		l.ZIndex = 20
		l.Parent = gui
		return l
	end
	local title = label(
		"Я учу азбуку!",
		UDim2.fromScale(0.5, 0.13),
		UDim2.fromScale(0.9, 0.18),
		Color3.fromRGB(255, 255, 255)
	)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 110, 200)
	stroke.Thickness = 3
	stroke.Parent = title
	label("☀️", UDim2.fromScale(0.88, 0.32), UDim2.fromScale(0.14, 0.2), Color3.new(1, 1, 1))
	label("☁️", UDim2.fromScale(0.14, 0.34), UDim2.fromScale(0.16, 0.18), Color3.new(1, 1, 1))
	label("☁️", UDim2.fromScale(0.66, 0.27), UDim2.fromScale(0.1, 0.12), Color3.new(1, 1, 1))
end

function BUILDERS.photo(model: Model, origin: CFrame)
	local width, height = 16, 11
	-- Задник чуть дальше от площади, чем метка. Лицевая сторона детали (−Z) смотрит
	-- туда же, куда origin, — на площадь.
	local center = origin * CFrame.new(0, 1.2 + height / 2, 4)
	local board =
		part(model, "PhotoBoard", Vector3.new(width, height, 0.6), center, Color3.fromRGB(165, 215, 250))
	rainbowBackdrop(board)
	-- Рама: четыре золотые планки и шары по углам.
	for _, y in { -1, 1 } do
		part(
			model,
			"FrameBar",
			Vector3.new(width + 1.6, 1, 1),
			center * CFrame.new(0, y * (height / 2 + 0.5), 0),
			GOLD
		)
	end
	for _, x in { -1, 1 } do
		part(
			model,
			"FrameBar",
			Vector3.new(1, height + 2, 1),
			center * CFrame.new(x * (width / 2 + 0.5), 0, 0),
			GOLD
		)
		for _, y in { -1, 1 } do
			local knob = part(
				model,
				"FrameKnob",
				Vector3.new(1.8, 1.8, 1.8),
				center * CFrame.new(x * (width / 2 + 0.5), y * (height / 2 + 0.5), 0),
				Color3.fromRGB(245, 120, 150)
			)
			knob.Shape = Enum.PartType.Ball
		end
		-- Ножка-подпорка сзади: рама стоит, а не висит в воздухе.
		part(
			model,
			"FrameFoot",
			Vector3.new(1, 1.2, 3),
			origin * CFrame.new(x * (width / 2 + 0.5), 0.6, 4.8),
			Color3.fromRGB(150, 110, 70)
		)
	end
	-- По бокам объёмные А и Я: вся азбука от начала до конца. У зрителя «влево» — это +X кадра.
	for index, spec in { { "a", 1, RAINBOW[1] }, { "ya", -1, RAINBOW[6] } } do
		local letter =
			Letter3D.build(spec[1], 5, origin * CFrame.new(spec[2] * (width / 2 + 3.5), 3, 2.5), spec[3])
		letter.Name = `PhotoLetter_{index}`
		letter.Parent = model
	end

	local mark = part(
		model,
		"PhotoMark",
		Vector3.new(0.3, 5, 5),
		origin * CFrame.new(0, 0.15, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
		GOLD
	)
	mark.Shape = Enum.PartType.Cylinder
	mark.CanCollide = false
	local icon = Instance.new("SurfaceGui")
	icon.Face = Enum.NormalId.Right -- ось X цилиндра смотрит вверх
	icon.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	icon.PixelsPerStud = 40
	icon.LightInfluence = 0
	icon.Parent = mark
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "📸"
	text.TextScaled = true
	text.Parent = icon
	-- Где стоит «фотограф»: со стороны площади, чуть выше головы, лицом к раме.
	local eye = (origin * CFrame.new(0, 5.2, -13)).Position
	mark:SetAttribute("Camera", CFrame.lookAt(eye, (origin * CFrame.new(0, 5, 2)).Position))
	CollectionService:AddTag(mark, "AF_PhotoMark")
end

--[[
	Зимняя полянка: снежный круг, каток посередине (метка AF_Ice — на нём
	катаются, Controllers/SkateController), снеговик, нарядная ёлка
	с огоньками и подарками, заснеженные ёлочки по краю и снегопад только
	над полянкой. -Z смотрит на площадь: оттуда приходят, туда и снеговик.
]]
local SNOW = Color3.fromRGB(245, 250, 255)
local SNOW_SHADE = Color3.fromRGB(215, 230, 245)

local function ball(parent: Instance, name: string, diameter: number, at: CFrame, color: Color3): BasePart
	local p = part(parent, name, Vector3.new(diameter, diameter, diameter), at, color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Поставить модель на землю в точке at: низ рамки — на земле, середина — над точкой.
local function plant(object: Model, at: CFrame)
	object:PivotTo(at)
	local box, extent = object:GetBoundingBox()
	local bottom = box.Position.Y - extent.Y / 2
	object:PivotTo(
		object:GetPivot() + Vector3.new(at.X - box.Position.X, at.Y - bottom, at.Z - box.Position.Z)
	)
end

local function snowman(model: Model, at: CFrame)
	local sizes = { 5, 3.8, 2.8 }
	local y = 0
	local centers = {}
	for index, size in sizes do
		y += size / 2 - (if index > 1 then 0.5 else 0.3)
		local body = ball(model, `SnowmanBall_{index}`, size, at * CFrame.new(0, y, 0), SNOW)
		body.Material = Enum.Material.Snow
		centers[index] = y
		y += size / 2
	end
	local head = at * CFrame.new(0, centers[3], 0)
	for _, side in { -1, 1 } do
		ball(
			model,
			"SnowmanEye",
			0.45,
			head * CFrame.new(side * 0.5, 0.35, -1.25),
			Color3.fromRGB(30, 30, 35)
		).CanCollide =
			false
	end
	-- Нос-морковка смотрит на площадь.
	local nose = part(
		model,
		"SnowmanNose",
		Vector3.new(0.4, 0.4, 1.5),
		head * CFrame.new(0, 0, -1.9),
		Color3.fromRGB(255, 140, 40)
	)
	nose.CanCollide = false
	local cone = Instance.new("SpecialMesh")
	cone.MeshType = Enum.MeshType.FileMesh
	cone.MeshId = "rbxassetid://1033714" -- конус из библиотеки Roblox
	cone.Scale = Vector3.new(0.35, 1.4, 0.35)
	cone.Parent = nose
	nose.CFrame = head * CFrame.new(0, 0, -1.9) * CFrame.Angles(math.rad(-90), 0, 0)
	for button = 1, 3 do
		ball(
			model,
			"SnowmanButton",
			0.4,
			at * CFrame.new(0, centers[2] - 1 + button * 0.6, -1.75),
			Color3.fromRGB(30, 30, 35)
		).CanCollide =
			false
	end
	-- Шарф и ведро-шляпа.
	local scarf = cylinder(
		model,
		"SnowmanScarf",
		0.6,
		3.3,
		at * CFrame.new(0, centers[3] - 1.2, 0),
		Color3.fromRGB(230, 60, 70)
	)
	scarf.CanCollide = false
	local tail = part(
		model,
		"SnowmanScarfTail",
		Vector3.new(0.6, 1.6, 0.2),
		at * CFrame.new(0.9, centers[3] - 2, -1.4) * CFrame.Angles(0, 0, math.rad(-15)),
		Color3.fromRGB(230, 60, 70)
	)
	tail.CanCollide = false
	local bucket =
		cylinder(model, "SnowmanHat", 1.5, 2, head * CFrame.new(0, 1.6, 0), Color3.fromRGB(70, 110, 220))
	bucket.CanCollide = false
	-- Руки-веточки.
	for _, side in { -1, 1 } do
		local arm = part(
			model,
			"SnowmanArm",
			Vector3.new(3.2, 0.25, 0.25),
			at * CFrame.new(side * 2.8, centers[2] + 0.6, 0) * CFrame.Angles(0, 0, side * math.rad(25)),
			Color3.fromRGB(120, 80, 50)
		)
		arm.CanCollide = false
	end
end

-- Нарядная ёлка: модель ёлки из декора, гирлянда спиралью, звезда и подарки.
local function festiveTree(model: Model, at: CFrame)
	local DecorService = require(script.Parent.DecorService)
	local tree = DecorService.modelFor("tree_pine", 1.7)
	if not tree then
		return
	end
	tree.Name = "WinterTree"
	plant(tree, at)
	tree.Parent = model
	local box, extent = tree:GetBoundingBox()
	local bottom = box.Position.Y - extent.Y / 2
	local height = extent.Y
	--[[
		Огоньки — по конусу хвои: у ёлки из Store снизу голый ствол (хвоя
		с трети высоты), а коллизия у неё коробкой, так что луч для посадки
		не годится. Конус чуть уже рамки: огонёк лежит на ветке, а не над ней.
	]]
	local foliage = 0.3
	local spread = math.min(extent.X, extent.Z) / 2 * 0.85
	local lights = 30
	for index = 1, lights do
		local share = foliage + (0.95 - foliage) * index / lights
		local angle = index * 2.4
		local r = spread * (1 - (share - foliage) / (1 - foliage)) + 0.3
		local light = ball(
			model,
			`WinterLight_{index}`,
			0.8,
			CFrame.new(
				box.Position.X + math.cos(angle) * r,
				bottom + height * share,
				box.Position.Z + math.sin(angle) * r
			),
			RAINBOW[index % #RAINBOW + 1]
		)
		light.Material = Enum.Material.Neon
		light.CanCollide = false
		CollectionService:AddTag(light, "AF_Twinkle")
	end
	local star = ball(
		model,
		"WinterStar",
		1.8,
		CFrame.new(box.Position.X, bottom + height + 0.6, box.Position.Z),
		Color3.fromRGB(255, 220, 80)
	)
	star.Material = Enum.Material.Neon
	star.CanCollide = false
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 220, 120)
	glow.Range = 14
	glow.Brightness = 1.5
	glow.Parent = star

	-- Подарки под ёлкой: коробка и лента крест-накрест.
	local gifts = {
		{ -3.5, -2.5, 2.2, RAINBOW[1], RAINBOW[3] },
		{ 3, -3, 1.8, RAINBOW[6], RAINBOW[4] },
		{ 0.5, -4.2, 1.4, RAINBOW[8], RAINBOW[5] },
	}
	for index, gift in gifts do
		local place = at * CFrame.new(gift[1], gift[3] / 2, gift[2]) * CFrame.Angles(0, index, 0)
		part(model, `Gift_{index}`, Vector3.new(gift[3], gift[3], gift[3]), place, gift[4])
		for _, turn in { 0, math.pi / 2 } do
			part(
				model,
				`GiftRibbon_{index}`,
				Vector3.new(gift[3] + 0.1, gift[3] + 0.1, 0.3),
				place * CFrame.Angles(0, turn, 0),
				gift[5]
			).CanCollide =
				false
		end
	end
end

function BUILDERS.winter(model: Model, origin: CFrame)
	local radius = Playground.WINTER_RADIUS
	local snow = cylinder(model, "WinterSnow", 0.5, radius * 2, origin * CFrame.new(0, 0.25, 0), SNOW)
	snow.Material = Enum.Material.Snow
	-- Сугробы по краю: полянка читается снежной, а не белой тарелкой.
	for index = 1, 22 do
		local angle = index / 22 * math.pi * 2
		local drift = ball(
			model,
			`WinterDrift_{index}`,
			2.6 + (index % 3) * 0.8,
			origin * CFrame.new(math.cos(angle) * (radius - 0.8), 0.1, math.sin(angle) * (radius - 0.8)),
			if index % 2 == 0 then SNOW else SNOW_SHADE
		)
		drift.Material = Enum.Material.Snow
		drift.CanCollide = false
	end

	-- Каток: голубой лёд с белым бортиком из снежков, со стороны площади вход.
	local iceAt = origin * CFrame.new(0, 0.55, 1)
	local ice = cylinder(model, "Ice", 0.3, Playground.ICE_RADIUS * 2, iceAt, Color3.fromRGB(185, 225, 250))
	ice.Material = Enum.Material.Ice
	ice.Reflectance = 0.25
	CollectionService:AddTag(ice, "AF_Ice")
	for index = 1, 24 do
		local angle = (index - 0.5) / 24 * math.pi * 2
		-- Проходы на катке: со стороны площади и с дальней стороны.
		local toward = math.abs(math.sin(angle) + 1) < 0.08 or math.abs(math.sin(angle) - 1) < 0.08
		if toward then
			continue
		end
		local rim = ball(
			model,
			`IceRim_{index}`,
			1.6,
			iceAt
				* CFrame.new(
					math.cos(angle) * (Playground.ICE_RADIUS + 0.4),
					0.2,
					math.sin(angle) * (Playground.ICE_RADIUS + 0.4)
				),
			SNOW
		)
		rim.Material = Enum.Material.Snow
	end

	snowman(model, origin * CFrame.new(-13, 0.5, -6))
	festiveTree(model, origin * CFrame.new(12, 0.5, 9))

	-- Заснеженные ёлочки по дальнему краю.
	local DecorService = require(script.Parent.DecorService)
	for index, spot in { { -15, 10, 0.8 }, { -6, 16, 0.95 }, { 17, -4, 0.75 }, { 4, 17, 0.85 } } do
		local pine = DecorService.modelFor("tree_pine", spot[3])
		if pine then
			pine.Name = `WinterPine_{index}`
			plant(pine, origin * CFrame.new(spot[1], 0.5, spot[2]) * CFrame.Angles(0, index, 0))
			pine.Parent = model
			local _, size = pine:GetBoundingBox()
			-- Сугроб вокруг ствола: плоский, ёлочка из него растёт.
			local drift = cylinder(
				model,
				`WinterPineSnow_{index}`,
				0.8,
				size.X * 0.55,
				origin * CFrame.new(spot[1], 0.7, spot[2]),
				SNOW
			)
			drift.Material = Enum.Material.Snow
			drift.CanCollide = false
		end
	end

	-- Снегопад: большие мягкие хлопья только над полянкой.
	local cloud =
		part(model, "Snowfall", Vector3.new(radius * 2, 1, radius * 2), origin * CFrame.new(0, 26, 0), SNOW)
	cloud.Transparency = 1
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	local flakes = Instance.new("ParticleEmitter")
	flakes.Name = "Snowflakes"
	flakes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flakes.Shape = Enum.ParticleEmitterShape.Box
	flakes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	flakes.EmissionDirection = Enum.NormalId.Bottom
	flakes.Rate = 45
	flakes.Lifetime = NumberRange.new(7, 9)
	flakes.Speed = NumberRange.new(2.5, 4)
	flakes.SpreadAngle = Vector2.new(15, 15)
	flakes.Acceleration = Vector3.new(0.4, 0, 0.2)
	flakes.Rotation = NumberRange.new(0, 360)
	flakes.RotSpeed = NumberRange.new(-40, 40)
	flakes.Size = NumberSequence.new(0.45)
	flakes.Color = ColorSequence.new(Color3.new(1, 1, 1))
	flakes.LightEmission = 0.4
	flakes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0),
		NumberSequenceKeypoint.new(0.9, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	flakes.Parent = cloud

	sign(model, origin * CFrame.new(-7, 0.5, -Playground.WINTER_RADIUS + 2), "⛄")
end

--[[
	Подсолнуховое поле: грядки, на них подсолнухи разного роста — многие
	выше ребёнка. Голова подсолнуха — отдельная модель с меткой AF_Sunflower
	и опорной точкой Pivot на макушке стебля: её поворачивает клиент
	(PlaygroundController), вслед за ребёнком или к солнцу.
]]
local SUNFLOWER_PETAL = Color3.fromRGB(255, 205, 40)
local SUNFLOWER_HEART = Color3.fromRGB(110, 70, 35)
local STEM = Color3.fromRGB(90, 160, 60)

local function sunflower(model: Model, index: number, at: CFrame, height: number)
	local stem = cylinder(model, `SunStem_{index}`, height, 0.45, at * CFrame.new(0, height / 2, 0), STEM)
	stem.CanCollide = false
	for _, side in { -1, 1 } do
		local leaf = part(
			model,
			`SunLeaf_{index}`,
			Vector3.new(1.6, 0.15, 0.9),
			at
				* CFrame.new(side * 0.8, height * (0.4 + side * 0.08), 0)
				* CFrame.Angles(0, 0, side * math.rad(20)),
			STEM
		)
		leaf.CanCollide = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = leaf
	end
	-- Голова смотрит на площадь (-Z места); клиент поворачивает её целиком.
	local head = Instance.new("Model")
	head.Name = `SunHead_{index}`
	head.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	head.Parent = model
	local pivot = at * CFrame.new(0, height + 0.3, 0)
	local face = pivot * CFrame.new(0, 0, -0.35)
	local heart =
		cylinder(head, "Heart", 0.35, 1.9, face * CFrame.Angles(math.rad(90), 0, 0), SUNFLOWER_HEART)
	heart.Material = Enum.Material.Sand
	heart.CanCollide = false
	local petals = 12
	for petal = 1, petals do
		local a = petal / petals * math.pi * 2
		local leafAt = face * CFrame.Angles(0, 0, a) * CFrame.new(1.35, 0, 0.1)
		local p = part(head, "Petal", Vector3.new(1.3, 0.55, 0.12), leafAt, SUNFLOWER_PETAL)
		p.CanCollide = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	head:SetAttribute("Pivot", pivot)
	CollectionService:AddTag(head, "AF_Sunflower")
end

local function scarecrow(model: Model, at: CFrame)
	local wood = Color3.fromRGB(150, 105, 65)
	part(model, "ScarecrowPole", Vector3.new(0.4, 7, 0.4), at * CFrame.new(0, 3.5, 0), wood)
	part(model, "ScarecrowArms", Vector3.new(5, 0.35, 0.35), at * CFrame.new(0, 5, 0), wood).CanCollide =
		false
	part(
		model,
		"ScarecrowShirt",
		Vector3.new(2, 2.2, 1),
		at * CFrame.new(0, 4.6, 0),
		Color3.fromRGB(220, 80, 70)
	)
	for _, side in { -1, 1 } do
		part(
			model,
			"ScarecrowSleeve",
			Vector3.new(1.4, 0.8, 0.8),
			at * CFrame.new(side * 1.6, 5, 0),
			Color3.fromRGB(80, 130, 210)
		).CanCollide =
			false
		-- Солома из рукавов.
		part(
			model,
			"ScarecrowStraw",
			Vector3.new(0.5, 0.5, 0.5),
			at * CFrame.new(side * 2.5, 5, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color3.fromRGB(240, 210, 110)
		).CanCollide =
			false
	end
	local head = part(
		model,
		"ScarecrowHead",
		Vector3.new(1.5, 1.5, 1.5),
		at * CFrame.new(0, 6.5, 0),
		Color3.fromRGB(240, 220, 170)
	)
	head.Shape = Enum.PartType.Ball
	head.CanCollide = false
	for _, side in { -1, 1 } do
		local eye = part(
			model,
			"ScarecrowEye",
			Vector3.new(0.25, 0.25, 0.25),
			at * CFrame.new(side * 0.3, 6.65, -0.7),
			Color3.fromRGB(40, 35, 40)
		)
		eye.Shape = Enum.PartType.Ball
		eye.CanCollide = false
	end
	local smile = part(
		model,
		"ScarecrowSmile",
		Vector3.new(0.7, 0.12, 0.1),
		at * CFrame.new(0, 6.2, -0.72),
		Color3.fromRGB(200, 70, 60)
	)
	smile.CanCollide = false
	cylinder(model, "ScarecrowBrim", 0.2, 2.8, at * CFrame.new(0, 7.2, 0), Color3.fromRGB(235, 200, 100)).CanCollide =
		false
	cylinder(model, "ScarecrowHat", 1, 1.5, at * CFrame.new(0, 7.7, 0), Color3.fromRGB(235, 200, 100)).CanCollide =
		false
end

function BUILDERS.sunflowers(model: Model, origin: CFrame)
	local rows, perRow = Playground.SUNFLOWER_ROWS, Playground.SUNFLOWER_PER_ROW
	local random = Random.new(33)
	local index = 0
	for row = 1, rows do
		local z = (row - (rows + 1) / 2) * 5
		local bed = part(
			model,
			`SunBed_{row}`,
			Vector3.new(perRow * 4 + 2, 0.4, 2.2),
			origin * CFrame.new(0, 0.2, z),
			Color3.fromRGB(120, 85, 55)
		)
		bed.Material = Enum.Material.Ground
		for column = 1, perRow do
			local x = (column - (perRow + 1) / 2) * 4 + random:NextNumber(-0.4, 0.4)
			-- Посередине поля — пугало, подсолнуха там нет.
			if row == 2 and column == 3 then
				continue
			end
			index += 1
			sunflower(model, index, origin * CFrame.new(x, 0.4, z), random:NextNumber(5, 8.5))
		end
	end
	scarecrow(model, origin * CFrame.new(0, 0.4, -2.5))
	sign(model, origin * CFrame.new(-8, 0, -13), "🌻")
end

-- Мячи, укатившиеся за бортик или упавшие, возвращаются в песочницу.
local function watchBalls(model: Model, origin: CFrame)
	task.spawn(function()
		while model.Parent do
			task.wait(3)
			for _, ball in model:GetChildren() do
				if CollectionService:HasTag(ball, "AF_Ball") and ball:IsA("BasePart") then
					local offset = ball.Position - origin.Position
					if Vector3.new(offset.X, 0, offset.Z).Magnitude > 30 or offset.Y < -20 then
						ball.AssemblyLinearVelocity = Vector3.zero
						ball.CFrame = ball:GetAttribute("Home")
					end
				end
			end
		end
	end)
end

--[[
	Прокат: ларёк с полосатым навесом, перед ним три вещи на подставках —
	самокат, велосипед, лошадка-единорог. Перед каждой круг её цвета: встал —
	поехал (Services/RentalService). Над вещью её эмодзи — ребёнок не читает.
]]
local WHITE = Color3.fromRGB(252, 252, 252)

function BUILDERS.rental(model: Model, origin: CFrame)
	local booth = origin * CFrame.new(0, 0, 8)
	local wood = Color3.fromRGB(250, 225, 170)
	part(model, "Booth", Vector3.new(12, 6, 4), booth * CFrame.new(0, 3, 0), wood).Material =
		Enum.Material.WoodPlanks
	part(
		model,
		"Counter",
		Vector3.new(12.6, 0.5, 1.6),
		booth * CFrame.new(0, 3.2, -2.6),
		Color3.fromRGB(190, 130, 85)
	)
	part(
		model,
		"BoothRoof",
		Vector3.new(13, 0.6, 5),
		booth * CFrame.new(0, 8.6, 0),
		Color3.fromRGB(245, 110, 110)
	)
	-- Стойки навеса и полосатый навес над прилавком: красное с белым.
	for _, x in { -1, 1 } do
		part(model, "AwningPost", Vector3.new(0.4, 8.3, 0.4), booth * CFrame.new(x * 6, 4.15, -3.3), WHITE)
	end
	for stripe = 0, 11 do
		local awning = part(
			model,
			`Awning{stripe}`,
			Vector3.new(1, 0.2, 3.6),
			booth * CFrame.new(-5.5 + stripe, 7.7, -2.2) * CFrame.Angles(math.rad(-18), 0, 0),
			if stripe % 2 == 0 then Color3.fromRGB(240, 80, 90) else WHITE
		)
		awning.CanCollide = false
	end
	sign(model, booth * CFrame.new(0, 3.9, -2.1), "🛴 Прокат")

	for index, vehicle in Rental.list do
		local x = (index - (#Rental.list + 1) / 2) * Rental.PAD_SPACING
		-- Подставка и вещь на ней, лицом к площади.
		local stand = origin * CFrame.new(x, 0, 2.5)
		part(
			model,
			`RentalStand_{vehicle.id}`,
			Vector3.new(4.4, 0.3, 5.6),
			stand * CFrame.new(0, 0.15, 0),
			wood
		)
		local shown = RentalVehicles.build(vehicle.id, stand * CFrame.new(0, 0.3, 0), vehicle.color)
		shown.Name = `RentalShow_{vehicle.id}`
		shown.Parent = model

		-- Круг перед вещью: встал — поехал.
		local ring = cylinder(
			model,
			`RentalRing_{vehicle.id}`,
			0.2,
			Rental.PAD_RADIUS * 2 + 0.6,
			origin * CFrame.new(x, 0.1, -2.5),
			WHITE
		)
		ring.CanCollide = false
		local pad = cylinder(
			model,
			`RentalPad_{vehicle.id}`,
			0.3,
			Rental.PAD_RADIUS * 2,
			origin * CFrame.new(x, 0.15, -2.5),
			vehicle.color
		)
		pad.CanCollide = false
		pad.Material = Enum.Material.Neon
		pad:SetAttribute("Vehicle", vehicle.id)
		CollectionService:AddTag(pad, "RentalPad")

		local anchor =
			part(model, `RentalIcon_{vehicle.id}`, Vector3.one, stand * CFrame.new(0, 6.5, 0), WHITE)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromScale(3.2, 3.2)
		billboard.LightInfluence = 0
		billboard.MaxDistance = 120
		billboard.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = vehicle.icon
		label.TextScaled = true
		label.Parent = billboard
	end
end

--[[
	Бобовый стебель (Config/Playground, beanstalk): толстый зелёный стебель
	с вьющейся лозой до облаков, листья-ступени спиралью, гнездо с яйцами
	на середине (сохранка: упал выше гнезда — вернёт к нему, PlaygroundController),
	стручок-батут к листу, до которого не допрыгнуть, и облачный остров
	с замком великана и золотой гусыней. Сундук на острове ставит ChestService.
]]
local STALK = Color3.fromRGB(95, 185, 75)
local STALK_DARK = Color3.fromRGB(65, 145, 60)
local LEAF = Color3.fromRGB(130, 215, 95)
local LEAF_VEIN = Color3.fromRGB(200, 245, 160)
local CLOUD = Color3.fromRGB(255, 255, 255)
local CLOUD_SHADE = Color3.fromRGB(232, 238, 252)

-- Цилиндр между двумя точками: у Roblox ось цилиндра — X.
local function rodBetween(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3
)
	local p = part(
		parent,
		name,
		Vector3.new((b - a).Magnitude, diameter, diameter),
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		color
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function puff(parent: Instance, name: string, diameter: number, at: CFrame, color: Color3): BasePart
	local p = part(parent, name, Vector3.one * diameter, at, color)
	p.Shape = Enum.PartType.Ball
	p.CanCollide = false
	p.CastShadow = false
	return p
end

-- Лист-ступень: круглая пластина, острый кончик наружу, светлая жилка и черешок к стеблю.
local function beanLeaf(parent: Instance, origin: CFrame, leaf: Playground.BeanLeaf, color: Color3): BasePart
	local dir = Vector3.new(math.cos(leaf.angle), 0, math.sin(leaf.angle))
	local centerLocal = dir * leaf.radius + Vector3.new(0, leaf.y - 0.3, 0)
	local center = origin * CFrame.new(centerLocal)
	local disc = cylinder(parent, `BeanLeaf_{leaf.index}`, 0.6, leaf.size, center, color)
	local outward = origin:VectorToWorldSpace(dir)
	local tipAt = center.Position + outward * (leaf.size / 2)
	local tip = part(
		parent,
		`BeanLeafTip_{leaf.index}`,
		Vector3.new(leaf.size * 0.4, 0.55, leaf.size * 0.4),
		CFrame.lookAt(tipAt, tipAt + outward) * CFrame.Angles(0, math.pi / 4, 0),
		color
	)
	tip.CanCollide = false
	local vein = part(
		parent,
		`BeanVein_{leaf.index}`,
		Vector3.new(0.25, 0.08, leaf.size * 0.95),
		CFrame.lookAt(
			center.Position + Vector3.new(0, 0.32, 0),
			center.Position + Vector3.new(0, 0.32, 0) + outward
		),
		LEAF_VEIN
	)
	vein.CanCollide = false
	local stemFrom = (origin * CFrame.new(dir * 1.6 + Vector3.new(0, leaf.y - 1.2, 0))).Position
	local stemTo = center.Position - outward * (leaf.size / 2 - 0.3)
	rodBetween(parent, `BeanStem_{leaf.index}`, stemFrom, stemTo, 0.5, STALK_DARK).CanCollide = false
	return disc
end

-- Башенка замка: круглая стена, конусная крыша из трёх ярусов и золотой шарик.
local function castleTower(
	parent: Instance,
	at: CFrame,
	height: number,
	wall: Color3,
	roof: Color3,
	flag: Color3?
)
	cylinder(parent, "CastleTower", height, 2.8, at * CFrame.new(0, height / 2, 0), wall)
	for tier, diameter in { 3.6, 2.5, 1.4 } do
		cylinder(
			parent,
			"CastleRoof",
			1.1,
			diameter,
			at * CFrame.new(0, height + 0.55 + (tier - 1) * 1, 0),
			roof
		)
	end
	puff(parent, "CastleKnob", 0.6, at * CFrame.new(0, height + 3.3, 0), GOLD)
	if flag then
		part(parent, "CastleFlagPole", Vector3.new(0.15, 2, 0.15), at * CFrame.new(0, height + 4.4, 0), WHITE).CanCollide =
			false
		part(parent, "CastleFlag", Vector3.new(1.4, 0.8, 0.08), at * CFrame.new(0.7, height + 5, 0), flag).CanCollide =
			false
	end
end

function BUILDERS.beanstalk(model: Model, origin: CFrame)
	local top = Playground.BEAN_TOP
	local island = Playground.BEAN_ISLAND
	local thick = Playground.BEAN_ISLAND_THICK

	-- Корень: холмик земли, три больших листа на траве, лейка и табличка.
	local mound = part(
		model,
		"BeanMound",
		Vector3.new(9, 2.4, 9),
		origin * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(125, 85, 55)
	)
	mound.Material = Enum.Material.Ground
	mound.CanCollide = false -- холмик для вида: запнуться о него у корня незачем
	local moundMesh = Instance.new("SpecialMesh")
	moundMesh.MeshType = Enum.MeshType.Sphere
	moundMesh.Parent = mound
	for index = 1, 3 do
		local angle = index * 2.1
		local at = origin * CFrame.new(math.cos(angle) * 4.5, 0.25, math.sin(angle) * 4.5)
		local ground = cylinder(model, "BeanGroundLeaf", 0.3, 4.5, at, LEAF)
		ground.CanCollide = false
	end
	local can = origin * CFrame.new(-5.5, 0, -6)
	cylinder(model, "WateringCan", 2, 1.8, can * CFrame.new(0, 1, 0), Color3.fromRGB(90, 170, 235)).CanCollide =
		false
	rodBetween(
		model,
		"WateringSpout",
		(can * CFrame.new(0.6, 1.2, 0)).Position,
		(can * CFrame.new(2, 2.4, 0)).Position,
		0.3,
		Color3.fromRGB(90, 170, 235)
	).CanCollide =
		false
	sign(model, origin * CFrame.new(5, 0, -8), "🌱 Бобовый стебель")

	-- Стебель: сегменты с лёгким изгибом, сужается кверху. Сквозь него не пройти.
	local function axis(y: number): Vector3
		return (origin * CFrame.new(math.sin(y / 11) * 0.5, y, math.cos(y / 15) * 0.5 - 0.5)).Position
	end
	local step = 5
	local y = -1
	while y < top - thick do
		local diameter = 4.6 - 1.6 * y / top
		rodBetween(model, "BeanStalk", axis(y), axis(y + step + 0.2), diameter, STALK)
		puff(model, "BeanKnot", diameter + 0.15, CFrame.new(axis(y + step)), STALK).CanCollide = true
		y += step
	end
	-- Лоза вьётся вокруг стебля: тонкая, темнее, для вида.
	local previous = nil
	for turn = 0, (top - thick - 2) / 1.2 do
		local height = turn * 1.2
		local angle = turn * math.rad(20)
		local radius = (4.6 - 1.6 * height / top) / 2 + 0.25
		local point = axis(height)
			+ origin:VectorToWorldSpace(Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius)
		if previous then
			rodBetween(model, "BeanVine", previous, point, 0.45, STALK_DARK).CanCollide = false
		end
		previous = point
	end

	for _, leaf in Playground.beanLeaves() do
		if leaf.kind == "float" then
			-- Качающийся лист — своя модель: клиент двигает её целиком (AF_Float).
			local group = Instance.new("Model")
			group.Name = `BeanFloat_{leaf.index}`
			group.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			group.Parent = model
			local disc = beanLeaf(group, origin, leaf, Color3.fromRGB(165, 225, 90))
			local anchor = part(group, "FloatAnchor", Vector3.one * 0.4, disc.CFrame, WHITE)
			anchor.Transparency = 1
			anchor.CanCollide = false
			anchor:SetAttribute("Amplitude", Playground.BEAN_FLOAT)
			anchor:SetAttribute("Period", 3.2)
			CollectionService:AddTag(anchor, "AF_Float")
		elseif leaf.kind == "nest" then
			-- Гнездо: соломенная площадка, кольцо веточек, три голубых яйца и флажок-сохранка.
			local disc = beanLeaf(model, origin, leaf, LEAF)
			local nest = cylinder(
				model,
				"BeanNest",
				0.5,
				leaf.size - 1.4,
				disc.CFrame * CFrame.new(0, 0.5, 0),
				Color3.fromRGB(215, 175, 105)
			)
			nest.Material = Enum.Material.Fabric
			nest:SetAttribute("Ground", origin.Position.Y)
			nest:SetAttribute("Axis", origin.Position)
			CollectionService:AddTag(nest, "AF_BeanNest")
			local rim = (leaf.size - 1.4) / 2
			for twig = 1, 12 do
				local a = twig / 12 * math.pi * 2
				local b = a + 0.62
				rodBetween(
					model,
					"NestTwig",
					(nest.CFrame * CFrame.new(math.cos(a) * rim, 0.45, math.sin(a) * rim)).Position,
					(nest.CFrame * CFrame.new(math.cos(b) * rim, 0.6, math.sin(b) * rim)).Position,
					0.5,
					Color3.fromRGB(150, 105, 60)
				).CanCollide =
					false
			end
			for egg = 1, 3 do
				local a = egg * 2.1
				puff(
					model,
					"NestEgg",
					0.9,
					nest.CFrame * CFrame.new(math.cos(a) * 0.9, 0.7, math.sin(a) * 0.9),
					Color3.fromRGB(175, 225, 245)
				)
			end
			part(
				model,
				"NestFlagPole",
				Vector3.new(0.18, 3, 0.18),
				nest.CFrame * CFrame.new(0, 1.7, (leaf.size - 1.4) / 2),
				WHITE
			).CanCollide =
				false
			local flag = part(
				model,
				"NestFlag",
				Vector3.new(1.5, 0.9, 0.08),
				nest.CFrame * CFrame.new(0.75, 2.75, (leaf.size - 1.4) / 2),
				Color3.fromRGB(240, 90, 100)
			)
			flag.CanCollide = false
		elseif leaf.kind == "pod" then
			-- Стручок-батут: толстый боб на листе, прыгнул на него — к листу выше прыжка.
			local disc = beanLeaf(model, origin, leaf, LEAF)
			local pod = part(
				model,
				"BeanPod",
				Vector3.new(1.6, 1, 4),
				disc.CFrame * CFrame.new(0, 0.6, 0),
				Color3.fromRGB(110, 200, 70)
			)
			pod.CanCollide = false
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = pod
			local bounce = cylinder(
				model,
				"BeanPodTop",
				0.35,
				3.4,
				disc.CFrame * CFrame.new(0, 0.45, 0),
				Color3.fromRGB(255, 225, 90)
			)
			bounce.Material = Enum.Material.Neon
			bounce:SetAttribute("Power", Playground.BEAN_POD_POWER)
			CollectionService:AddTag(bounce, "AF_BeanPod")
		else
			beanLeaf(model, origin, leaf, LEAF)
		end
	end

	--[[
		Облачный остров: по нему ходят (плоский круг), края и низ — пушистые клубы.
		Коснулся острова — долез: PlaygroundController радуется и снимает сохранку.
	]]
	local ground =
		cylinder(model, "BeanIsland", thick, island * 2, origin * CFrame.new(0, top - thick / 2, 0), CLOUD)
	CollectionService:AddTag(ground, "AF_BeanTop")
	for index = 1, 16 do
		local a = index / 16 * math.pi * 2
		puff(
			model,
			"IslandRim",
			6.5 + (index % 3),
			origin * CFrame.new(math.cos(a) * (island - 1.2), top - 3.4, math.sin(a) * (island - 1.2)),
			if index % 4 == 0 then CLOUD_SHADE else CLOUD
		)
	end
	for index = 1, 7 do
		local a = index / 7 * math.pi * 2 + 0.4
		puff(
			model,
			"IslandBelly",
			9,
			origin * CFrame.new(math.cos(a) * island * 0.55, top - thick - 2.5, math.sin(a) * island * 0.55),
			CLOUD_SHADE
		)
	end
	puff(model, "IslandBelly", 13, origin * CFrame.new(0, top - thick - 4.5, 0), CLOUD_SHADE)

	-- Замок великана за сундуком: розовая крепость, четыре башенки, дверь и окошки.
	local keep = origin * CFrame.new(0, top, 7)
	local pink = Color3.fromRGB(250, 185, 205)
	local blue = Color3.fromRGB(120, 150, 240)
	part(model, "CastleKeep", Vector3.new(8, 6, 5), keep * CFrame.new(0, 3, 0), pink)
	for index = -2, 2 do
		part(model, "CastleCrenel", Vector3.new(1, 1, 1), keep * CFrame.new(index * 1.7, 6.5, -2), pink)
	end
	part(
		model,
		"CastleDoor",
		Vector3.new(2.2, 3, 0.3),
		keep * CFrame.new(0, 1.5, -2.55),
		Color3.fromRGB(150, 95, 60)
	)
	-- Полукруглый верх двери: диск осью наружу, нижняя половина прячется в двери.
	local arch = part(
		model,
		"CastleArch",
		Vector3.new(0.3, 2.2, 2.2),
		keep * CFrame.new(0, 3, -2.55) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(150, 95, 60)
	)
	arch.Shape = Enum.PartType.Cylinder
	arch.CanCollide = false
	for _, x in { -2.6, 2.6 } do
		local window = part(
			model,
			"CastleWindow",
			Vector3.new(1, 1.4, 0.2),
			keep * CFrame.new(x, 3.8, -2.55),
			Color3.fromRGB(255, 235, 150)
		)
		window.Material = Enum.Material.Neon
	end
	castleTower(model, keep * CFrame.new(-4.4, 0, -2), 9, pink, blue, Color3.fromRGB(255, 210, 80))
	castleTower(model, keep * CFrame.new(4.4, 0, -2), 9, pink, blue, Color3.fromRGB(130, 220, 150))
	castleTower(model, keep * CFrame.new(-3.4, 0, 2.4), 11, pink, blue, nil)
	castleTower(model, keep * CFrame.new(3.4, 0, 2.4), 11, pink, blue, nil)

	-- Золотая гусыня на золотых яйцах — из той же сказки.
	local goose = origin * CFrame.new(-6.5, top, 1) * CFrame.Angles(0, math.rad(-35), 0)
	local body = part(
		model,
		"GooseBody",
		Vector3.new(2, 1.6, 2.8),
		goose * CFrame.new(0, 1.3, 0),
		Color3.fromRGB(255, 250, 240)
	)
	local bodyMesh = Instance.new("SpecialMesh")
	bodyMesh.MeshType = Enum.MeshType.Sphere
	bodyMesh.Parent = body
	rodBetween(
		model,
		"GooseNeck",
		(goose * CFrame.new(0, 1.7, -0.9)).Position,
		(goose * CFrame.new(0, 3.1, -1.2)).Position,
		0.6,
		Color3.fromRGB(255, 250, 240)
	)
	puff(model, "GooseHead", 1, goose * CFrame.new(0, 3.3, -1.3), Color3.fromRGB(255, 250, 240))
	part(
		model,
		"GooseBeak",
		Vector3.new(0.35, 0.25, 0.7),
		goose * CFrame.new(0, 3.2, -1.95),
		Color3.fromRGB(255, 160, 60)
	).CanCollide =
		false
	for _, side in { -1, 1 } do
		puff(model, "GooseEye", 0.18, goose * CFrame.new(side * 0.35, 3.45, -1.7), Color3.fromRGB(40, 40, 50))
		local wing = part(
			model,
			"GooseWing",
			Vector3.new(0.3, 1, 1.8),
			goose * CFrame.new(side * 1, 1.5, 0.2),
			Color3.fromRGB(245, 240, 225)
		)
		wing.CanCollide = false
	end
	for egg = 1, 3 do
		local at = goose * CFrame.new(-1.6 + egg * 0.7, 0.45, 1.9 + (egg % 2) * 0.4)
		local shell = part(model, "GoldenEgg", Vector3.new(0.8, 1, 0.8), at, GOLD)
		shell.Material = Enum.Material.Neon
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = shell
	end

	-- Искры над островом: издалека видно, что там что-то есть.
	local air = part(
		model,
		"IslandSparkles",
		Vector3.new(island * 1.6, 3, island * 1.6),
		origin * CFrame.new(0, top + 3, 0),
		WHITE
	)
	air.Transparency = 1
	air.CanCollide = false
	air.CanQuery = false
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(200, 180, 255))
	glow.LightEmission = 1
	glow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	glow.Lifetime = NumberRange.new(2, 3.5)
	glow.Rate = 6
	glow.Speed = NumberRange.new(0.5, 1.5)
	glow.Parent = air
end

--[[
	Рыбалка у пруда: песчаный берег, вода, камыши и кувшинки, деревянные
	мостки от берега к середине, на краю мостков — жёлтый круг рыбака и ведро.
	Рыбок с буквами, удочку и леску делает клиент (Controllers/FishingController):
	у каждого ребёнка свой улов, и сети это ничего не стоит.
]]
local POND_WATER = Color3.fromRGB(70, 165, 215)

--[[
	Модель каталога (Config/Decor) в масштабе scale, стоящая нижней гранью в точке at.
	Нет модели — ничего не ставим: это украшение, а не часть игры.
]]
local function placeDecor(model: Model, id: string, scale: number, at: CFrame, name: string?)
	local DecorService = require(script.Parent.DecorService)
	local decor = DecorService.modelFor(id, scale)
	if not decor then
		return
	end
	decor.Name = name or id
	decor:PivotTo(at)
	local box, extent = decor:GetBoundingBox()
	decor:PivotTo(
		decor:GetPivot()
			+ Vector3.new(
				at.X - box.Position.X,
				at.Y - (box.Position.Y - extent.Y / 2),
				at.Z - box.Position.Z
			)
	)
	decor.Parent = model
end
local POND_SAND = Color3.fromRGB(230, 210, 160)
local PIER_WOOD = Color3.fromRGB(165, 118, 72)

function BUILDERS.pond(model: Model, origin: CFrame)
	local spec = Playground.POND
	local radius = spec.radius
	local shore = cylinder(
		model,
		"PondShore",
		0.3,
		(radius + spec.shore) * 2,
		origin * CFrame.new(0, 0.15, 0),
		POND_SAND
	)
	shore.Material = Enum.Material.Sand
	local deep = cylinder(
		model,
		"PondDeep",
		0.05,
		radius * 1.3,
		origin * CFrame.new(0, 0.33, 0),
		Color3.fromRGB(40, 110, 160)
	)
	deep.CanCollide = false
	-- Вода не держит: в неё можно зайти по щиколотку, как в настоящий пруд.
	local water = cylinder(model, "PondWater", 0.3, radius * 2, origin * CFrame.new(0, 0.42, 0), POND_WATER)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.3
	water.CanCollide = false
	water:SetAttribute("Radius", radius)
	CollectionService:AddTag(water, "AF_Pond")

	-- Камыши по берегу, кроме стороны мостков (−Z, к площади).
	local random = Random.new(33)
	for index = 1, 26 do
		local angle = random:NextNumber(0, math.pi * 2)
		if math.sin(angle) < -0.85 then
			continue -- у мостков свободно
		end
		local distance = radius + random:NextNumber(-0.6, 1.4)
		local height = random:NextNumber(2.2, 3.8)
		local at = origin
			* CFrame.new(math.cos(angle) * distance, 0.3 + height / 2, math.sin(angle) * distance)
		local stem =
			part(model, `Reed_{index}`, Vector3.new(0.18, height, 0.18), at, Color3.fromRGB(95, 150, 70))
		stem.CanCollide = false
		local tip = part(
			model,
			`ReedTip_{index}`,
			Vector3.new(0.9, 0.4, 0.4),
			at * CFrame.new(0, height / 2 - 0.2, 0),
			Color3.fromRGB(120, 80, 45)
		)
		tip.Shape = Enum.PartType.Cylinder
		tip.CFrame = tip.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		tip.CanCollide = false
	end
	-- Кувшинки: зелёные листья с розовым цветком, на двух сидят лягушата (Creator Store).
	for index, spot in { { 5, 4 }, { -6, 3 }, { -3, 7 }, { 6.5, -1 } } do
		if index <= 2 then
			placeDecor(
				model,
				"frog",
				0.45,
				origin * CFrame.new(spot[1], 0.64, spot[2]) * CFrame.Angles(0, math.rad(150 + index * 70), 0),
				`PondFrog_{index}`
			)
		end
		local at = origin * CFrame.new(spot[1], 0.6, spot[2])
		local pad = cylinder(model, `LilyPad_{index}`, 0.06, 2.4, at, Color3.fromRGB(90, 170, 80))
		pad.CanCollide = false
		local bloom = part(
			model,
			`LilyFlower_{index}`,
			Vector3.new(0.7, 0.5, 0.7),
			at * CFrame.new(0.3, 0.25, 0.2),
			Color3.fromRGB(245, 150, 190)
		)
		bloom.Shape = Enum.PartType.Ball
		bloom.CanCollide = false
	end

	-- Рогоз пучками у дальнего берега и резиновая уточка на воде.
	for index, angle in { 20, 65, 115, 160 } do
		local a = math.rad(angle)
		placeDecor(
			model,
			"cattail",
			0.5,
			origin * CFrame.new(math.cos(a) * (radius + 0.8), 0.3, math.sin(a) * (radius + 0.8)),
			`PondCattail_{index}`
		)
	end
	placeDecor(
		model,
		"rubber_duck",
		0.2,
		origin * CFrame.new(-4, 0.45, -2) * CFrame.Angles(0, math.rad(40), 0),
		"PondDuck"
	)

	-- Мостки: от берега у площади к середине пруда, на сваях.
	local from = radius + spec.shore + 1
	local to = radius - spec.pier
	local length = from - to
	local deck = part(
		model,
		"PierDeck",
		Vector3.new(4.2, 0.4, length),
		origin * CFrame.new(0, 0.9, -(from + to) / 2),
		PIER_WOOD
	)
	deck.Material = Enum.Material.WoodPlanks
	for index = 0, 3 do
		for _, side in { -1, 1 } do
			local post = part(
				model,
				`PierPost_{index}_{side}`,
				Vector3.new(0.5, 1.6, 0.5),
				origin * CFrame.new(side * 1.9, 0.5, -(to + index * length / 3)),
				Color3.fromRGB(120, 85, 55)
			)
			post.Material = Enum.Material.Wood
		end
	end
	-- Ступенька с песка на мостки: без неё пятилетка упирается в край доски.
	part(
		model,
		"PierStep",
		Vector3.new(4.2, 0.45, 1.4),
		origin * CFrame.new(0, 0.5, -(from + 0.7)),
		PIER_WOOD
	).Material =
		Enum.Material.WoodPlanks

	-- Круг рыбака на краю мостков: встал — рыбалка началась.
	local mark = cylinder(
		model,
		"FishingMark",
		0.06,
		3.2,
		origin * CFrame.new(0, 1.12, -(to + 1.6)),
		Color3.fromRGB(255, 210, 90)
	)
	mark.CanCollide = false
	mark.Material = Enum.Material.Neon
	mark.Transparency = 0.2
	mark:SetAttribute("Pond", water.Position)
	CollectionService:AddTag(mark, "AF_FishingMark")

	-- Ведро для улова: у края мостков, сбоку от рыбака.
	local bucketAt = origin * CFrame.new(1.4, 1.1, -(to + 3.4))
	local bucket = cylinder(
		model,
		"FishBucket",
		1.3,
		1.5,
		bucketAt * CFrame.new(0, 0.65, 0),
		Color3.fromRGB(80, 140, 210)
	)
	bucket.Material = Enum.Material.Metal
	local rim = cylinder(
		model,
		"FishBucketRim",
		0.15,
		1.65,
		bucketAt * CFrame.new(0, 1.3, 0),
		Color3.fromRGB(200, 200, 210)
	)
	rim.CanCollide = false
	mark:SetAttribute("Bucket", bucketAt.Position + Vector3.new(0, 1.4, 0))

	sign(model, origin * CFrame.new(4.5, 0, -(from + 1)), "🎣 Рыбалка")
end

--[[
	Тир: ярмарочный стенд лицом к площади. Полосатый прилавок, за ним синяя
	стена со звёздами, над ней полосатый навес с флажками. Перед прилавком
	жёлтый круг стрелка, на прилавке корзинка с мячами. Шарики с буквами на
	стене и летящий мяч делает клиент (Controllers/GalleryController).
]]
local GALLERY_RED = Color3.fromRGB(230, 70, 70)
local GALLERY_WHITE = Color3.fromRGB(250, 245, 235)
local GALLERY_BLUE = Color3.fromRGB(60, 90, 180)

function BUILDERS.gallery(model: Model, origin: CFrame)
	local width = 13
	-- Пол стенда: доски.
	part(model, "GalleryFloor", Vector3.new(width + 2, 0.3, 11), origin * CFrame.new(0, 0.15, 1.5), PIER_WOOD).Material =
		Enum.Material.WoodPlanks

	-- Прилавок в красно-белую полоску.
	local stripes = 8
	for index = 1, stripes do
		local x = (index - (stripes + 1) / 2) * (width / stripes)
		local counter = part(
			model,
			`GalleryCounter_{index}`,
			Vector3.new(width / stripes, 3, 1.4),
			origin * CFrame.new(x, 1.8, -3),
			if index % 2 == 0 then GALLERY_RED else GALLERY_WHITE
		)
		counter.Material = Enum.Material.SmoothPlastic
	end
	part(
		model,
		"GalleryCounterTop",
		Vector3.new(width + 0.6, 0.35, 1.9),
		origin * CFrame.new(0, 3.45, -3),
		PIER_WOOD
	).Material =
		Enum.Material.Wood
	-- Корзинка с мячами на прилавке.
	local basketAt = origin * CFrame.new(-4.6, 3.6, -3)
	local basket = cylinder(
		model,
		"GalleryBasket",
		0.9,
		1.8,
		basketAt * CFrame.new(0, 0.45, 0),
		Color3.fromRGB(190, 140, 80)
	)
	basket.Material = Enum.Material.Fabric
	for index, color in
		{ GALLERY_RED, Color3.fromRGB(250, 210, 70), Color3.fromRGB(90, 190, 110), GALLERY_BLUE }
	do
		local toy = part(
			model,
			`GalleryBall_{index}`,
			Vector3.new(0.7, 0.7, 0.7),
			basketAt * CFrame.new((index - 2.5) * 0.35, 1.05, (index % 2 - 0.5) * 0.4),
			color
		)
		toy.Shape = Enum.PartType.Ball
		toy.CanCollide = false
	end

	-- Задняя стена со звёздами: на ней висят шарики.
	local wall =
		part(model, "GalleryWall", Vector3.new(width, 9, 0.6), origin * CFrame.new(0, 4.8, 6), GALLERY_BLUE)
	wall.Material = Enum.Material.SmoothPlastic
	local random = Random.new(75)
	for index = 1, 14 do
		local star = part(
			model,
			`GalleryStar_{index}`,
			Vector3.new(0.5, 0.5, 0.1),
			origin
				* CFrame.new(random:NextNumber(-6, 6), random:NextNumber(1, 9), 5.66)
				* CFrame.Angles(0, 0, math.rad(45)),
			Color3.fromRGB(255, 225, 110)
		)
		star.Material = Enum.Material.Neon
		star.CanCollide = false
	end
	wall:SetAttribute("Columns", Playground.GALLERY.columns)
	wall:SetAttribute("Rows", Playground.GALLERY.rows)
	CollectionService:AddTag(wall, "AF_GalleryWall")

	-- Стойки и полосатый навес с флажками.
	for _, x in { -width / 2, width / 2 } do
		for _, z in { -3.6, 6 } do
			part(
				model,
				"GalleryPost",
				Vector3.new(0.6, 10.5, 0.6),
				origin * CFrame.new(x, 5.25, z),
				GALLERY_WHITE
			).CanCollide = z
				> 0
		end
	end
	for index = 1, stripes do
		local x = (index - (stripes + 1) / 2) * (width / stripes)
		local stripe = part(
			model,
			`GalleryRoof_{index}`,
			Vector3.new(width / stripes, 0.4, 11),
			origin * CFrame.new(x, 10.6, 1.2) * CFrame.Angles(math.rad(-8), 0, 0),
			if index % 2 == 0 then GALLERY_RED else GALLERY_WHITE
		)
		stripe.CanCollide = false
		local flag = part(
			model,
			`GalleryFlag_{index}`,
			Vector3.new(1, 1, 0.1),
			origin * CFrame.new(x, 9.6, -4.3) * CFrame.Angles(0, 0, math.rad(45)),
			RAINBOW[(index - 1) % #RAINBOW + 1]
		)
		flag.CanCollide = false
	end

	-- Круг стрелка перед прилавком.
	local mark = cylinder(
		model,
		"GalleryMark",
		0.06,
		3.4,
		origin * CFrame.new(0, 0.34, -5.6),
		Color3.fromRGB(255, 210, 90)
	)
	mark.CanCollide = false
	mark.Material = Enum.Material.Neon
	mark.Transparency = 0.2
	CollectionService:AddTag(mark, "AF_GalleryMark")

	-- Призы на прилавке: плюшевые мишки и уточка (Creator Store) — то, ради чего стреляют.
	placeDecor(
		model,
		"teddy_bear",
		0.22,
		origin * CFrame.new(3.2, 3.62, -3) * CFrame.Angles(0, math.rad(180), 0),
		"PrizeBear_1"
	)
	placeDecor(
		model,
		"teddy_bear",
		0.18,
		origin * CFrame.new(5.2, 3.62, -3) * CFrame.Angles(0, math.rad(160), 0),
		"PrizeBear_2"
	)
	placeDecor(
		model,
		"rubber_duck",
		0.16,
		origin * CFrame.new(1.4, 3.62, -3) * CFrame.Angles(0, math.rad(200), 0),
		"PrizeDuck"
	)

	sign(model, origin * CFrame.new(width / 2 + 2, 0, -5), "🎯 Тир")
end

function PlaygroundService.build(parent: Instance): number
	local folder = Instance.new("Folder")
	folder.Name = "Playground"
	folder.Parent = parent

	local built = 0
	for _, spot in Playground.spots do
		local builder = BUILDERS[spot.id]
		assert(builder, `PlaygroundService: нет строителя для "{spot.id}"`)
		local model = Instance.new("Model")
		model.Name = `Play_{spot.id}`
		model.Parent = folder
		local origin = frameOf(spot)
		builder(model, origin)
		if spot.id == "sandbox" then
			watchBalls(model, origin)
		end
		built += 1
	end
	return built
end

PlaygroundService.BUILDERS = BUILDERS

return PlaygroundService
