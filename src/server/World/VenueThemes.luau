--!nonstrict
--[[
	Оформление полян занятий. Раньше поляна была коробкой: зелёный пол и три
	полупрозрачные цветные стены. Место не читалось ни как «поляна», ни как
	«двор» — ребёнок стоял в цветном ящике.

	Теперь у каждой поляны:
	  · задник — холмы, горы или облака за краем пола, а не стена;
	  · свой набор вещей по теме: у Буквопада тучки и лужи, у Горы — вершины
	    со снегом и флажки, у Пузырей — пруды и ракушки, у Зеркала — колонны
	    и рамы, у Весов — торговые лавки, у Ягод — забор, тюки сена и пугало;
	  · невидимая ограда по краю: упасть с поляны нельзя, а смотреть она не мешает.

	Всё тематическое стоит у края (дальше THEME_RADIUS от центра): середина
	поляны принадлежит заданию, и заслонять его нельзя. Детали только
	закреплённые и почти все без касаний — это задник, а не игра.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Venues = require(Shared.Config.Venues)

local VenueThemes = {}

-- Ближе этого к центру тематические вещи не ставятся: там сцена задания.
VenueThemes.THEME_RADIUS = 34

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Деталь для вида: сквозь неё проходят, и касаний она не ловит.
local function prop(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local p = part(parent, name, size, cframe, color, material)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	return p
end

local function ball(parent, name, size, cframe, color, material)
	local p = prop(parent, name, size, cframe, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Цилиндр «стоя»: высота по Y. У Roblox цилиндр лежит по X, поэтому поворот.
local function column(parent, name, height, diameter, cframe, color, material)
	local p = prop(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		cframe * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

--[[
	Точка у края поляны: угол от «вперёд» (−Z, куда смотрит ребёнок) по часовой,
	расстояние от центра. Вход — сзади ребёнка (+Z, угол 180°).
]]
local function around(center: Vector3, degrees: number, distance: number, y: number?): CFrame
	local angle = math.rad(degrees)
	local at = center + Vector3.new(math.sin(angle) * distance, y or 0, -math.cos(angle) * distance)
	return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
end

-- Невидимая ограда по всем четырём сторонам и низкий бордюр по краю пола.
local function fence(model: Model, center: Vector3, venue)
	local half = Venues.SIZE / 2
	for _, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local alongX = side[1] == 0
		local wall = part(
			model,
			`Bound_{side[1]}_{side[2]}`,
			Vector3.new(if alongX then Venues.SIZE + 4 else 2, 40, if alongX then 2 else Venues.SIZE + 4),
			CFrame.new(center + Vector3.new(side[1] * (half + 1), 20, side[2] * (half + 1))),
			Color3.new(1, 1, 1)
		)
		wall.Transparency = 1
		wall.CanQuery = false

		local curb = part(
			model,
			`Curb_{side[1]}_{side[2]}`,
			Vector3.new(if alongX then Venues.SIZE else 1.6, 0.8, if alongX then 1.6 else Venues.SIZE),
			CFrame.new(center + Vector3.new(side[1] * (half - 0.8), 0.4, side[2] * (half - 0.8))),
			venue.accent,
			Enum.Material.Cobblestone
		)
		curb.CanCollide = false
	end
end

-- Холмы за краем: поляна стоит в долине, а не висит в пустоте.
local function hills(model: Model, center: Vector3, venue, random: Random, skipFront: boolean)
	local half = Venues.SIZE / 2
	local color = darker(venue.ground, 0.12)
	for index = 1, 16 do
		local degrees = (index - 1) / 16 * 360 + random:NextNumber() * 12
		-- Позади ребёнка (у входа) холмов меньше: оглянулся — видно небо.
		if not (skipFront and degrees > 150 and degrees < 210) then
			local size = 30 + random:NextNumber() * 26
			ball(
				model,
				`Hill_{index}`,
				Vector3.new(size * 1.4, size, size * 1.2),
				around(center, degrees, half + size * 0.35, -size * 0.25),
				if index % 2 == 0 then color else darker(color, 0.08),
				Enum.Material.Grass
			)
		end
	end
end

-- Пятна травы потемнее по краю пола: пол перестаёт быть заливкой.
local function patches(model: Model, center: Vector3, venue, random: Random)
	for index = 1, 10 do
		local degrees = random:NextNumber() * 360
		local distance = VenueThemes.THEME_RADIUS + random:NextNumber() * 18
		local size = 6 + random:NextNumber() * 8
		column(
			model,
			`Patch_{index}`,
			0.12,
			size,
			around(center, degrees, distance, 0.06),
			darker(venue.ground, 0.08 + random:NextNumber() * 0.06),
			Enum.Material.Grass
		)
	end
end

local function particles(parent: BasePart, color: Color3, rate: number, rise: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLES
	emitter.Color = ColorSequence.new(color)
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 20)
	emitter.Acceleration = Vector3.new(0, rise, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.LightEmission = 0.6
	emitter.Parent = parent
end

-- Большая плоская невидимая деталь над поляной: из неё сыплются частицы атмосферы.
local function ambience(
	model: Model,
	center: Vector3,
	color: Color3,
	rate: number,
	rise: number,
	size: number
)
	local emitterPart = prop(
		model,
		"Ambience",
		Vector3.new(Venues.SIZE * 0.8, 1, Venues.SIZE * 0.8),
		CFrame.new(center + Vector3.new(0, if rise > 0 then 1 else 30, 0)),
		color
	)
	emitterPart.Transparency = 1
	particles(emitterPart, color, rate, rise, size)
end

local THEMES = {}

-- Буквопад: тучки над краем, лужи и зонтики.
function THEMES.letter_rain(model: Model, center: Vector3, venue, random: Random)
	hills(model, center, venue, random, true)
	for cloud = 1, 6 do
		local base =
			around(center, (cloud - 1) * 60 + 20, 48 + random:NextNumber() * 8, 34 + random:NextNumber() * 8)
		for puff = 1, 5 do
			local size = 8 + random:NextNumber() * 6
			ball(
				model,
				`Cloud_{cloud}_{puff}`,
				Vector3.new(size * 1.3, size, size),
				base * CFrame.new((puff - 3) * 5, random:NextNumber() * 2, random:NextNumber() * 3),
				Color3.fromRGB(245, 248, 255)
			)
		end
	end
	for puddle = 1, 7 do
		local size = 5 + random:NextNumber() * 6
		local at =
			around(center, puddle * 51 + 10, VenueThemes.THEME_RADIUS + 4 + random:NextNumber() * 16, 0.08)
		local water = column(
			model,
			`Puddle_{puddle}`,
			0.1,
			size,
			at,
			Color3.fromRGB(150, 200, 240),
			Enum.Material.Glass
		)
		water.Transparency = 0.25
	end
	local UMBRELLA =
		{ Color3.fromRGB(240, 90, 90), Color3.fromRGB(250, 200, 70), Color3.fromRGB(110, 170, 240) }
	for index = 1, 3 do
		local at = around(center, 60 + index * 70, 44)
		column(model, `UmbrellaPole_{index}`, 7, 0.35, at * CFrame.new(0, 3.5, 0), Color3.fromRGB(90, 80, 80))
		local canopy = ball(
			model,
			`Umbrella_{index}`,
			Vector3.new(9, 3, 9),
			at * CFrame.new(0, 7.2, 0),
			UMBRELLA[index],
			Enum.Material.Fabric
		)
		canopy.CastShadow = true
		ball(
			model,
			`UmbrellaTip_{index}`,
			Vector3.one * 0.7,
			at * CFrame.new(0, 8.8, 0),
			Color3.fromRGB(250, 250, 250)
		)
	end
end

-- Гора Алфавита: вершины со снегом позади лестницы и флажки по бокам.
function THEMES.alphabet_ladder(model: Model, center: Vector3, venue, random: Random)
	hills(model, center, venue, random, true)
	local ROCK = Color3.fromRGB(150, 140, 165)
	for peak = 1, 5 do
		local degrees = -50 + (peak - 1) * 25
		local height = 55 + random:NextNumber() * 30 - math.abs(peak - 3) * 10
		local at = around(center, degrees, Venues.SIZE / 2 + 30 + random:NextNumber() * 10, 0)
		local wedgeWidth = 34 + random:NextNumber() * 10
		for _, side in { -1, 1 } do
			local slope = Instance.new("WedgePart")
			slope.Name = `Peak_{peak}_{side}`
			slope.Size = Vector3.new(wedgeWidth, height, height * 0.8)
			slope.CFrame = at
				* CFrame.new(0, height / 2, side * height * 0.4)
				-- Клин высокий сзади (+Z): ближний к поляне склон так и стоит, дальний развёрнут.
				* CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
			slope.Color = if side < 0 then ROCK else darker(ROCK, 0.1)
			slope.Material = Enum.Material.Slate
			slope.Anchored = true
			slope.CanCollide = false
			slope.CanQuery = false
			slope.CanTouch = false
			slope.CastShadow = false
			slope.Parent = model
		end
		ball(
			model,
			`Snow_{peak}`,
			Vector3.new(wedgeWidth * 0.9, height * 0.25, height * 0.35),
			at * CFrame.new(0, height * 0.9, 0),
			Color3.fromRGB(250, 252, 255),
			Enum.Material.Snow
		)
	end
	local FLAGS =
		{ Color3.fromRGB(240, 100, 100), Color3.fromRGB(250, 200, 70), Color3.fromRGB(110, 190, 120) }
	for index = 1, 6 do
		local side = if index % 2 == 0 then 1 else -1
		local at = CFrame.new(center + Vector3.new(side * 20, 0, 22 - index * 11))
		column(model, `FlagPole_{index}`, 9, 0.3, at * CFrame.new(0, 4.5, 0), Color3.fromRGB(245, 245, 245))
		prop(
			model,
			`Flag_{index}`,
			Vector3.new(0.15, 1.8, 3),
			at * CFrame.new(0, 8, -1.5),
			FLAGS[(index - 1) % #FLAGS + 1],
			Enum.Material.Fabric
		)
	end
	for rock = 1, 8 do
		local size = 3 + random:NextNumber() * 5
		ball(
			model,
			`Boulder_{rock}`,
			Vector3.new(size * 1.3, size, size),
			around(center, rock * 45 + random:NextNumber() * 20, 40 + random:NextNumber() * 14, size * 0.3),
			darker(ROCK, random:NextNumber() * 0.15),
			Enum.Material.Slate
		)
	end
end

-- Берег Пузырей: пруды по бокам, ракушки, спасательные круги, пузырьки в воздухе.
function THEMES.bubbles(model: Model, center: Vector3, venue, random: Random)
	hills(model, center, venue, random, true)
	for pond = 1, 2 do
		local side = if pond == 1 then -1 else 1
		local at = CFrame.new(center + Vector3.new(side * 42, 0.1, -8))
		column(model, `PondSand_{pond}`, 0.1, 26, at, Color3.fromRGB(235, 220, 170), Enum.Material.Sand)
		local water = column(
			model,
			`Pond_{pond}`,
			0.2,
			21,
			at * CFrame.new(0, 0.1, 0),
			Color3.fromRGB(90, 180, 220),
			Enum.Material.Glass
		)
		water.Transparency = 0.2
		-- Спасательный круг: восемь кусочков по кругу, красные и белые.
		for piece = 1, 8 do
			local angle = piece / 8 * math.pi * 2
			prop(
				model,
				`Ring_{pond}_{piece}`,
				Vector3.new(1.1, 0.6, 1.6),
				at
					* CFrame.new(math.cos(angle) * 2.2, 0.5, math.sin(angle) * 2.2)
					* CFrame.Angles(0, -angle, 0),
				if piece % 2 == 0 then Color3.fromRGB(240, 80, 80) else Color3.fromRGB(250, 250, 250)
			)
		end
	end
	local SHELL =
		{ Color3.fromRGB(255, 190, 200), Color3.fromRGB(255, 230, 190), Color3.fromRGB(240, 200, 240) }
	for shell = 1, 10 do
		local size = 1 + random:NextNumber()
		ball(
			model,
			`Shell_{shell}`,
			Vector3.new(size * 1.3, size * 0.6, size),
			around(center, random:NextNumber() * 360, 36 + random:NextNumber() * 18, 0.3),
			SHELL[(shell - 1) % #SHELL + 1]
		)
	end
	ambience(model, center, Color3.fromRGB(200, 240, 255), 6, 1.2, 1.2)
end

-- Зеркальный двор: колонны с золотыми шарами, рамы на заднике, блёстки в воздухе.
function THEMES.mirror(model: Model, center: Vector3, venue, random: Random)
	hills(model, center, venue, random, true)
	local GOLD = Color3.fromRGB(255, 205, 90)
	for index = 1, 8 do
		local at = around(center, (index - 1) * 45 + 22.5, 44)
		column(
			model,
			`ColumnBase_{index}`,
			1,
			3.4,
			at * CFrame.new(0, 0.5, 0),
			lighter(venue.accent, 0.3),
			Enum.Material.Marble
		)
		column(
			model,
			`Column_{index}`,
			12,
			2.2,
			at * CFrame.new(0, 7, 0),
			Color3.fromRGB(245, 240, 230),
			Enum.Material.Marble
		)
		ball(
			model,
			`ColumnTop_{index}`,
			Vector3.one * 2.6,
			at * CFrame.new(0, 14.3, 0),
			GOLD,
			Enum.Material.Foil
		)
	end
	for frame = 1, 3 do
		local at = CFrame.new(center + Vector3.new((frame - 2) * 22, 0, -(Venues.SIZE / 2 - 3)))
		prop(
			model,
			`FrameBorder_{frame}`,
			Vector3.new(10, 14, 0.6),
			at * CFrame.new(0, 10, 0),
			GOLD,
			Enum.Material.Foil
		)
		local glass = prop(
			model,
			`FrameGlass_{frame}`,
			Vector3.new(8.4, 12.4, 0.2),
			at * CFrame.new(0, 10, 0.4),
			Color3.fromRGB(200, 225, 245),
			Enum.Material.Glass
		)
		glass.Reflectance = 0.4
	end
	ambience(model, center, Color3.fromRGB(255, 240, 200), 5, -0.2, 0.8)
end

-- Двор Весов: торговые лавки с полосатыми навесами, ящики и мешки.
function THEMES.scales(model: Model, center: Vector3, venue, random: Random)
	hills(model, center, venue, random, true)
	local AWNING = {
		{ Color3.fromRGB(240, 90, 90), Color3.fromRGB(250, 245, 235) },
		{ Color3.fromRGB(90, 150, 230), Color3.fromRGB(250, 245, 235) },
		{ Color3.fromRGB(110, 190, 110), Color3.fromRGB(250, 245, 235) },
	}
	local WOOD = Color3.fromRGB(170, 125, 80)
	for stall = 1, 3 do
		local at = around(center, -70 + (stall - 1) * 70, 45)
		for _, corner in { { -5, -3 }, { 5, -3 }, { -5, 3 }, { 5, 3 } } do
			column(
				model,
				`StallPost_{stall}_{corner[1]}_{corner[2]}`,
				8,
				0.5,
				at * CFrame.new(corner[1], 4, corner[2]),
				WOOD
			)
		end
		local counter = part(
			model,
			`StallCounter_{stall}`,
			Vector3.new(10, 3, 3),
			at * CFrame.new(0, 1.5, -2),
			WOOD,
			Enum.Material.WoodPlanks
		)
		counter.CastShadow = true
		for stripe = 1, 6 do
			prop(
				model,
				`Awning_{stall}_{stripe}`,
				Vector3.new(11.4 / 6, 0.3, 7.4),
				at * CFrame.new((stripe - 3.5) * 11.4 / 6, 8.3, 0) * CFrame.Angles(math.rad(-12), 0, 0),
				AWNING[stall][(stripe % 2) + 1],
				Enum.Material.Fabric
			)
		end
		-- На прилавке — то, что взвешивают: яблоки, груши, тыквы.
		for fruit = 1, 4 do
			ball(
				model,
				`Fruit_{stall}_{fruit}`,
				Vector3.one * (1 + stall * 0.3),
				at * CFrame.new(-3.5 + fruit * 1.6, 3.5, -2),
				if stall == 1
					then Color3.fromRGB(230, 60, 60)
					elseif stall == 2 then Color3.fromRGB(200, 220, 90)
					else Color3.fromRGB(240, 150, 50)
			)
		end
	end
	for crate = 1, 6 do
		local size = 2.5 + random:NextNumber() * 1.5
		local at = around(
			center,
			120 + crate * 20 + random:NextNumber() * 8,
			40 + random:NextNumber() * 10,
			size / 2
		)
		prop(
			model,
			`Crate_{crate}`,
			Vector3.one * size,
			at * CFrame.Angles(0, random:NextNumber() * 3, 0),
			WOOD,
			Enum.Material.WoodPlanks
		)
	end
	for sack = 1, 5 do
		local at = around(center, -120 - sack * 18, 42 + random:NextNumber() * 8, 1.2)
		ball(
			model,
			`Sack_{sack}`,
			Vector3.new(3, 3.2, 2.6),
			at,
			Color3.fromRGB(200, 170, 120),
			Enum.Material.Fabric
		)
	end
end

-- Ягодная поляна: деревянный забор, тюки сена, пугало с шляпой.
function THEMES.berries(model: Model, center: Vector3, venue, random: Random)
	hills(model, center, venue, random, false)
	local WOOD = Color3.fromRGB(160, 115, 75)
	local half = Venues.SIZE / 2 - 4
	for _, side in { { 0, -1 }, { -1, 0 }, { 1, 0 } } do
		local alongX = side[1] == 0
		for rail = 1, 2 do
			prop(
				model,
				`FenceRail_{side[1]}_{side[2]}_{rail}`,
				Vector3.new(if alongX then half * 2 else 0.4, 0.5, if alongX then 0.4 else half * 2),
				CFrame.new(center + Vector3.new(side[1] * half, rail * 1.3, side[2] * half)),
				WOOD,
				Enum.Material.WoodPlanks
			)
		end
		for post = -5, 5 do
			local offset = post * half / 5
			prop(
				model,
				`FencePost_{side[1]}_{side[2]}_{post}`,
				Vector3.new(0.6, 3.4, 0.6),
				CFrame.new(
					center
						+ Vector3.new(
							if alongX then offset else side[1] * half,
							1.7,
							if alongX then side[2] * half else offset
						)
				),
				darker(WOOD, 0.1),
				Enum.Material.Wood
			)
		end
	end
	for bale = 1, 5 do
		local at =
			around(center, 40 + bale * 55 + random:NextNumber() * 10, 44 + random:NextNumber() * 6, 1.6)
		prop(
			model,
			`Bale_{bale}`,
			Vector3.new(5, 3.2, 3.2),
			at * CFrame.Angles(0, random:NextNumber() * 3, 0),
			Color3.fromRGB(235, 200, 110),
			Enum.Material.Fabric
		)
	end
	-- Пугало: машет всем, кто пришёл за ягодами.
	local scarecrow = around(center, -35, 46)
	column(model, "ScarecrowPole", 9, 0.5, scarecrow * CFrame.new(0, 4.5, 0), WOOD)
	prop(model, "ScarecrowArms", Vector3.new(7, 0.5, 0.5), scarecrow * CFrame.new(0, 6.5, 0), WOOD)
	prop(
		model,
		"ScarecrowShirt",
		Vector3.new(3.2, 3.4, 1.4),
		scarecrow * CFrame.new(0, 6, 0),
		Color3.fromRGB(90, 140, 210),
		Enum.Material.Fabric
	)
	ball(
		model,
		"ScarecrowHead",
		Vector3.one * 2.4,
		scarecrow * CFrame.new(0, 9, 0),
		Color3.fromRGB(240, 210, 150),
		Enum.Material.Fabric
	)
	column(
		model,
		"ScarecrowHatBrim",
		0.3,
		4,
		scarecrow * CFrame.new(0, 10.1, 0),
		Color3.fromRGB(200, 160, 80),
		Enum.Material.Fabric
	)
	column(
		model,
		"ScarecrowHat",
		1.4,
		2.2,
		scarecrow * CFrame.new(0, 10.9, 0),
		Color3.fromRGB(200, 160, 80),
		Enum.Material.Fabric
	)
	ambience(model, center, Color3.fromRGB(255, 230, 160), 3, 0.3, 0.7)
end

VenueThemes.THEMES = THEMES

-- Построить оформление поляны. Seed из порядка поляны: у всех одинаково и каждый запуск.
function VenueThemes.build(model: Model, center: Vector3, venue, seed: number)
	local random = Random.new(seed)
	fence(model, center, venue)
	patches(model, center, venue, random)
	local theme = THEMES[venue.id]
	if theme then
		theme(model, center, venue, random)
	else
		hills(model, center, venue, random, true)
	end
end

return VenueThemes
