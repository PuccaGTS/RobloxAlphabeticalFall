--!strict
--[[
	Горизонт: что видно за живой изгородью по краю мира.

	Раньше за изгородью кончалась земля, и с любой горки, с колеса обозрения
	или просто сверху было видно край плиты и голубую пустоту — мир выглядел
	полигоном, подвешенным в небе. Теперь за изгородью три пояса:

	  · зелёные холмы с деревьями — сразу за изгородью, как будто парк
	    продолжается дальше, чем можно дойти;
	  · холмы повыше и потемнее — второй план, дымка делает их голубее;
	  · горный хребет вдали — модель из Creator Store (Config/Decor, mountain_rocky).

	Туда нельзя дойти: изгородь с невидимой стеной стоит как стояла (WorldService).
	Поэтому у горизонта нет столкновений и он не бросает тени — это декорация
	театра, а не место. Расстановка детерминирована: один и тот же сид — один
	и тот же пейзаж у всех и всегда.
]]

local Base = require(script.Parent.Base)

local Horizon = {}

Horizon.SEED = 20260921

-- Земля под горизонтом: без неё холмы висели бы над пустотой. Чуть ниже основной.
Horizon.FAR_GROUND_SIZE = 2600
Horizon.FAR_GROUND_TOP = 0.5

export type Belt = {
	name: string,
	count: number,
	radius: { number }, -- от и до, от центра мира
	width: { number }, -- поперёк взгляда из центра
	depth: { number }, -- вдоль взгляда
	height: { number }, -- над землёй (видимая половина холма)
	colors: { Color3 },
	trees: number, -- деревьев на холме
}

local EDGE = Base.GROUND_SIZE / 2

local BELTS: { Belt } = {
	{
		name = "near",
		count = 30,
		radius = { EDGE + 45, EDGE + 110 },
		width = { 110, 190 },
		depth = { 70, 120 },
		height = { 26, 54 },
		colors = {
			Color3.fromRGB(120, 185, 95),
			Color3.fromRGB(105, 170, 85),
			Color3.fromRGB(140, 195, 100),
			Color3.fromRGB(95, 160, 90),
		},
		trees = 2,
	},
	{
		name = "far",
		count = 24,
		radius = { EDGE + 190, EDGE + 290 },
		width = { 200, 320 },
		depth = { 120, 180 },
		height = { 70, 120 },
		colors = {
			Color3.fromRGB(85, 145, 95),
			Color3.fromRGB(95, 150, 110),
			Color3.fromRGB(80, 135, 100),
		},
		trees = 0,
	},
}
Horizon.BELTS = BELTS

-- Какие деревья растут на ближних холмах: только лёгкие, с моделью-файлом. Ёлок вдвое больше.
Horizon.TREES = { "tree_pine", "tree_pine", "tree_round2" } -- лёгкие модели: круглое дерево весит 3240 треугольников
Horizon.TREE_SCALE = { 1.6, 2.4 } -- деревья вдали крупнее: иначе с площади их не видно

Horizon.MOUNTAIN = "mountain_rocky"
Horizon.MOUNTAIN_COUNT = 14
Horizon.MOUNTAIN_RADIUS = { EDGE + 520, EDGE + 640 }
Horizon.MOUNTAIN_SCALE = { 0.9, 1.5 }
-- Горы сливаются с дымкой в голубой: у дальнего плана цвет холоднее.
Horizon.MOUNTAIN_COLOR = Color3.fromRGB(120, 135, 160)

--[[
	Водопад на горизонте — прямо напротив точки появления, за порталами: скала
	с водопадом, пенная чаша и ручей к изгороди. Ближние холмы на его месте
	не растут, чтобы не заслонять. Туда не дойти, как и до всего горизонта,
	но шум воды слышно уже у домов (Config/Ambient.WATERFALL).
]]
Horizon.WATERFALL = {
	angle = 270, -- в градусах; −Z — туда смотрит ребёнок, появившись на площади
	distance = EDGE + 75, -- от центра мира до подножия скалы
	height = 50, -- откуда падает вода: ниже гребня скалы, из расщелины
	width = 12, -- ширина потока
	clearance = 0.2, -- в радианах: ближних холмов в этом секторе нет
	rockScale = 0.36, -- скала — хребет MOUNTAIN в этом масштабе: около 77 студов в высоту
}

-- Кадр подножия водопада: на земле, лицом к центру мира.
function Horizon.waterfallFrame(): CFrame
	local angle = math.rad(Horizon.WATERFALL.angle)
	local foot = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Horizon.WATERFALL.distance
		+ Vector3.new(0, Horizon.FAR_GROUND_TOP, 0)
	return CFrame.lookAt(foot, Vector3.new(0, foot.Y, 0))
end

-- Где шумит вода: чаша под водопадом.
function Horizon.waterfallPool(): Vector3
	return (Horizon.waterfallFrame() * CFrame.new(0, 1, -12)).Position
end

export type Hill = {
	belt: string,
	position: Vector3, -- центр основания на земле
	yaw: number,
	size: Vector3, -- полный эллипсоид: высота холма — половина Y
	color: Color3,
	trees: { Vector3 },
}

export type Mountain = { position: Vector3, yaw: number, scale: number }

local function between(random: Random, range: { number }): number
	return range[1] + random:NextNumber() * (range[2] - range[1])
end

Horizon.EDGE = EDGE
Horizon.CLEARANCE = 4 -- сколько студов от изгороди до ближайшей точки холма

--[[
	Где кончается мир по этому направлению. Изгородь квадратная, а холмы идут
	кольцом: без поправки на угол квадрата холмы на диагоналях оказывались бы
	внутри изгороди — там, где ребёнок может пройти сквозь них.
]]
function Horizon.edgeDistance(angle: number): number
	return EDGE / math.max(math.abs(math.cos(angle)), math.abs(math.sin(angle)))
end

-- Ближайшая к центру точка основания холма в «квадратной» мере: max(|x|, |z|).
function Horizon.innerReach(position: Vector3, size: Vector3, yaw: number): number
	local nearest = math.huge
	local turn = CFrame.Angles(0, yaw, 0)
	for step = 0, 47 do
		local t = step / 48 * math.pi * 2
		local point = position
			+ turn:VectorToWorldSpace(Vector3.new(math.cos(t) * size.X / 2, 0, math.sin(t) * size.Z / 2))
		nearest = math.min(nearest, math.max(math.abs(point.X), math.abs(point.Z)))
	end
	return nearest
end

--[[
	Холмы по кольцу: шаг по углу ровный, а радиус, размер и поворот — случайные
	от сида. Ровный шаг не даёт холмам сбиться в кучу и оставить прореху,
	в которую виден край.
]]
function Horizon.hills(): { Hill }
	local random = Random.new(Horizon.SEED)
	local hills: { Hill } = {}
	for beltIndex, belt in BELTS do
		for index = 1, belt.count do
			local angle = (index - 1 + random:NextNumber() * 0.6) / belt.count * math.pi * 2
				+ beltIndex * 0.37
			--[[
				Сектор водопада ближние холмы оставляют открытым. Случайные числа
				холм всё равно забирает: иначе от водопада сдвинулся бы весь пейзаж.
			]]
			local fromFall =
				math.abs((angle - math.rad(Horizon.WATERFALL.angle) + math.pi) % (math.pi * 2) - math.pi)
			local hidesFall = belt.name == "near" and fromFall < Horizon.WATERFALL.clearance
			local radius = between(random, belt.radius) - EDGE + Horizon.edgeDistance(angle)
			local height = between(random, belt.height)
			local size = Vector3.new(between(random, belt.width), height * 2, between(random, belt.depth))
			-- Длинная сторона — поперёк взгляда из центра: холмы стоят стеной, а не лучами.
			local yaw = -angle + math.pi / 2 + (random:NextNumber() - 0.5) * 0.4
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local position = direction * radius + Vector3.new(0, Horizon.FAR_GROUND_TOP, 0)
			-- Холм, задевший изгородь, отодвигаем наружу, пока не встанет за ней.
			local reach = Horizon.innerReach(position, size, yaw)
			while reach < EDGE + Horizon.CLEARANCE do
				position += direction * (EDGE + Horizon.CLEARANCE - reach + 1)
				reach = Horizon.innerReach(position, size, yaw)
			end
			local trees: { Vector3 } = {}
			for _ = 1, belt.trees do
				-- Точка внутри основания, не у самого края: там склон почти отвесный.
				local spread = random:NextNumber() * 0.6
				local turn = random:NextNumber() * math.pi * 2
				local u = math.cos(turn) * spread / 2
				local v = math.sin(turn) * spread / 2
				local rise = height * math.sqrt(1 - spread ^ 2)
				local offset = CFrame.Angles(0, yaw, 0)
					:VectorToWorldSpace(Vector3.new(u * size.X, 0, v * size.Z))
				table.insert(trees, position + offset + Vector3.new(0, rise - 1, 0))
			end
			if hidesFall then
				continue
			end
			table.insert(hills, {
				belt = belt.name,
				position = position,
				yaw = yaw,
				size = size,
				color = belt.colors[random:NextInteger(1, #belt.colors)],
				trees = trees,
			})
		end
	end
	return hills
end

function Horizon.mountains(): { Mountain }
	local random = Random.new(Horizon.SEED + 1)
	local mountains: { Mountain } = {}
	for index = 1, Horizon.MOUNTAIN_COUNT do
		local angle = (index - 1 + random:NextNumber() * 0.5) / Horizon.MOUNTAIN_COUNT * math.pi * 2
		local radius = between(random, Horizon.MOUNTAIN_RADIUS) - EDGE + Horizon.edgeDistance(angle)
		table.insert(mountains, {
			position = Vector3.new(
				math.cos(angle) * radius,
				Horizon.FAR_GROUND_TOP,
				math.sin(angle) * radius
			),
			-- Хребет — длинная модель: ставим её вдоль кольца, лицом к площади.
			yaw = -angle + math.pi / 2,
			scale = between(random, Horizon.MOUNTAIN_SCALE),
		})
	end
	return mountains
end

return Horizon
