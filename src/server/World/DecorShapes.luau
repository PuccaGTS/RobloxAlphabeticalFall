--!nonstrict
--[[
	Эскизы декора: деревья, лавочки и фонтан, собранные из примитивов.

	Зачем это здесь, а не в виде готовых моделей от художника. Модели из чужих
	библиотек в проект просто так не попадают: одни требуют входа в аккаунт Roblox
	и Toolbox, другие — загрузки меша на аккаунт с модерацией. И то и другое делает
	человек, а не репозиторий. А площадь из серых коробок выглядит недоделанной
	игрой и мешает проверять её на ребёнке уже сейчас.

	Поэтому эскизы: шар, цилиндр и брусок складываются в узнаваемое дерево или
	лавочку прямо кодом. Это не финальный арт и не притворяется им — это то,
	что можно прочитать в диффе, поправить одной строкой и не платить лицензией.

	Как только в assets/models/decor лёг настоящий `.rbxm`, DecorService берёт его,
	а эскиз не строится вовсе (docs/21-DECOR.md).

	Правила, общие для всех эскизов:
	  · модель стоит НА НУЛЕ: низ на y = 0, а на землю её поставит DecorService;
	  · габарит не больше заявленного в Config/Decor — это держится тестом,
	    иначе дерево полезет в проход, которого в конфиге не видно;
	  · деталей мало. Цель — 30 FPS на дешёвом планшете, и дерево из сорока
	    шариков эту цель убивает быстрее, чем украшает мир.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Letters = require(ReplicatedStorage:WaitForChild("Shared").Config.Letters)

local DecorShapes = {}

local BARK = Color3.fromRGB(120, 85, 60)
local LEAF_DARK = Color3.fromRGB(70, 130, 85)
local LEAF_LIGHT = Color3.fromRGB(120, 185, 110)
local STONE = Color3.fromRGB(165, 165, 172)
local WOOD = Color3.fromRGB(190, 145, 95)
local METAL = Color3.fromRGB(90, 95, 110)
local WATER = Color3.fromRGB(120, 195, 235)
local EARTH = Color3.fromRGB(120, 90, 70)

--[[
	Одна деталь эскиза.

	Все детали якорятся и не сталкиваются между собой: сталкиваемость целиком
	решает DecorService по каталогу, здесь про неё думать не надо.
]]
local function piece(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

--[[
	Ствол дерева. Цилиндр в Roblox лежит вдоль X, поэтому его ставят на попа
	поворотом на 90° — это первое, на чём спотыкаются, собирая дерево из деталей.
]]
local function trunk(model: Model, height: number, thickness: number): BasePart
	return piece(
		model,
		"Trunk",
		Enum.PartType.Cylinder,
		Vector3.new(height, thickness, thickness),
		at(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		BARK,
		Enum.Material.Wood
	)
end

local BUILDERS: { [string]: (Model) -> () } = {}

--[[
	Ёлка: ствол и три сплюснутых шара, от большого к малому.

	Шары, а не конусы: конуса среди примитивов нет, а собирать его из клиньев —
	это восемь деталей на дерево вместо четырёх. Сплюснутый шар читается как
	пушистая крона, и с трёх метров ребёнку этого достаточно.
]]
BUILDERS.tree_pine = function(model: Model)
	trunk(model, 6, 1.6)

	local tiers = {
		{ width = 7.5, height = 4.5, y = 6.5 },
		{ width = 5.8, height = 4, y = 9.8 },
		{ width = 3.6, height = 3.4, y = 12.8 },
	}
	for index, tier in tiers do
		piece(
			model,
			`Crown_{index}`,
			Enum.PartType.Ball,
			Vector3.new(tier.width, tier.height, tier.width),
			at(0, tier.y, 0),
			if index == 2 then LEAF_LIGHT else LEAF_DARK,
			Enum.Material.Grass
		)
	end
end

-- Круглое дерево: одна большая крона и два шара поменьше по бокам — так крона
-- перестаёт быть идеальным шаром и выглядит живее.
BUILDERS.tree_round = function(model: Model)
	trunk(model, 5.5, 1.8)

	piece(
		model,
		"Crown",
		Enum.PartType.Ball,
		Vector3.new(8.5, 7.5, 8.5),
		at(0, 9, 0),
		LEAF_LIGHT,
		Enum.Material.Grass
	)
	piece(
		model,
		"CrownLeft",
		Enum.PartType.Ball,
		Vector3.new(5, 4.5, 5),
		at(-2.6, 7, 1.2),
		LEAF_DARK,
		Enum.Material.Grass
	)
	piece(
		model,
		"CrownRight",
		Enum.PartType.Ball,
		Vector3.new(4.4, 4, 4.4),
		at(2.8, 7.6, -1),
		LEAF_DARK,
		Enum.Material.Grass
	)
end

-- Куст: три шара внахлёст. Ниже пояса, и сквозь него ребёнок проходит насквозь.
BUILDERS.bush_round = function(model: Model)
	piece(
		model,
		"Body",
		Enum.PartType.Ball,
		Vector3.new(3.6, 2.4, 3.6),
		at(0, 1.2, 0),
		LEAF_DARK,
		Enum.Material.Grass
	)
	piece(
		model,
		"Left",
		Enum.PartType.Ball,
		Vector3.new(2.6, 1.9, 2.6),
		at(-1.2, 0.95, 0.6),
		LEAF_LIGHT,
		Enum.Material.Grass
	)
	piece(
		model,
		"Right",
		Enum.PartType.Ball,
		Vector3.new(2.2, 1.7, 2.2),
		at(1.3, 0.85, -0.5),
		LEAF_LIGHT,
		Enum.Material.Grass
	)
end

--[[
	Клумба: круг земли и пять цветов на стеблях.

	Цвета взяты разные и яркие: клумбы стоят у выходов на дорожки к домам
	и работают указателем «сюда можно идти».
]]
BUILDERS.flower_bed = function(model: Model)
	piece(
		model,
		"Soil",
		Enum.PartType.Cylinder,
		Vector3.new(0.6, 5.6, 5.6),
		at(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		EARTH,
		Enum.Material.Ground
	)

	local colors = {
		Color3.fromRGB(240, 120, 130),
		Color3.fromRGB(250, 210, 110),
		Color3.fromRGB(200, 150, 235),
		Color3.fromRGB(245, 150, 100),
		Color3.fromRGB(140, 200, 240),
	}
	for index, color in colors do
		local angle = (index - 1) / #colors * math.pi * 2
		local x, z = math.cos(angle) * 1.5, math.sin(angle) * 1.5

		piece(
			model,
			`Stem_{index}`,
			Enum.PartType.Cylinder,
			Vector3.new(0.9, 0.2, 0.2),
			at(x, 1, z) * CFrame.Angles(0, 0, math.rad(90)),
			LEAF_DARK,
			Enum.Material.Grass
		)
		piece(model, `Bloom_{index}`, Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), at(x, 1.5, z), color)
	end
end

-- Камень: два сплюснутых шара внахлёст, слегка завалены. Правильный шар
-- читается как мяч, а не как камень, — весь фокус в этом наклоне.
BUILDERS.rock_small = function(model: Model)
	piece(
		model,
		"Body",
		Enum.PartType.Ball,
		Vector3.new(2.9, 2.1, 2.7),
		at(0, 1.3, 0) * CFrame.Angles(0.12, 0.4, 0.15),
		STONE,
		Enum.Material.Slate
	)
	piece(
		model,
		"Chip",
		Enum.PartType.Ball,
		Vector3.new(1.5, 1.2, 1.4),
		at(0.85, 0.8, 0.5) * CFrame.Angles(0.25, 0, -0.15),
		Color3.fromRGB(145, 145, 155),
		Enum.Material.Slate
	)
end

-- Лавочка: сиденье, наклонная спинка и четыре ножки.
BUILDERS.bench = function(model: Model)
	piece(
		model,
		"Seat",
		Enum.PartType.Block,
		Vector3.new(5.6, 0.4, 1.8),
		at(0, 1.6, 0),
		WOOD,
		Enum.Material.Wood
	)
	piece(
		model,
		"Back",
		Enum.PartType.Block,
		Vector3.new(5.6, 1.3, 0.35),
		at(0, 2.3, -0.75) * CFrame.Angles(math.rad(-12), 0, 0),
		WOOD,
		Enum.Material.Wood
	)

	for index, x in { -2.3, 2.3 } do
		for jndex, z in { -0.6, 0.6 } do
			piece(
				model,
				`Leg_{index}_{jndex}`,
				Enum.PartType.Cylinder,
				Vector3.new(1.6, 0.3, 0.3),
				at(x, 0.8, z) * CFrame.Angles(0, 0, math.rad(90)),
				METAL,
				Enum.Material.Metal
			)
		end
	end
end

--[[
	Фонарь: столб, перекладина и светящийся плафон.

	Свет настоящий (PointLight), но слабый и тёплый: вечера в игре нет, фонарь
	нужен как ориентир на площади, а не как источник освещения.
]]
BUILDERS.lamp = function(model: Model)
	piece(
		model,
		"Base",
		Enum.PartType.Cylinder,
		Vector3.new(0.6, 1.6, 1.6),
		at(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		METAL,
		Enum.Material.Metal
	)
	piece(
		model,
		"Post",
		Enum.PartType.Cylinder,
		Vector3.new(9.5, 0.5, 0.5),
		at(0, 5.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		METAL,
		Enum.Material.Metal
	)

	local bulb = piece(
		model,
		"Bulb",
		Enum.PartType.Ball,
		Vector3.new(1.6, 1.6, 1.6),
		at(0, 10.6, 0),
		Color3.fromRGB(255, 240, 190),
		Enum.Material.Neon
	)

	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = 14
	light.Color = Color3.fromRGB(255, 235, 190)
	light.Shadows = false -- тени от фонарей на планшете стоят дороже, чем дают
	light.Parent = bulb
end

--[[
	Фонтан: чаша, вода, колонна и верхняя чашечка со струёй.

	Вода — полупрозрачная деталь материала Water, а не терраформ: настоящая вода
	Roblox работает только в терраформе, а терраформ посреди площади мы не льём.
]]
BUILDERS.fountain = function(model: Model)
	piece(
		model,
		"Basin",
		Enum.PartType.Cylinder,
		Vector3.new(1.6, 13, 13),
		at(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
		STONE,
		Enum.Material.Concrete
	)
	piece(
		model,
		"Rim",
		Enum.PartType.Cylinder,
		Vector3.new(0.7, 14, 14),
		at(0, 1.9, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(200, 198, 195),
		Enum.Material.Concrete
	)

	local water = piece(
		model,
		"Water",
		Enum.PartType.Cylinder,
		Vector3.new(0.4, 12.4, 12.4),
		at(0, 1.85, 0) * CFrame.Angles(0, 0, math.rad(90)),
		WATER,
		Enum.Material.Water
	)
	water.Transparency = 0.35

	piece(
		model,
		"Column",
		Enum.PartType.Cylinder,
		Vector3.new(2.6, 1.6, 1.6),
		at(0, 3.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		STONE,
		Enum.Material.Concrete
	)
	piece(
		model,
		"Cup",
		Enum.PartType.Cylinder,
		Vector3.new(0.5, 5, 5),
		at(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(200, 198, 195),
		Enum.Material.Concrete
	)

	local jet = piece(
		model,
		"Jet",
		Enum.PartType.Cylinder,
		Vector3.new(1.3, 0.8, 0.8),
		at(0, 5.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		WATER,
		Enum.Material.Neon
	)
	jet.Transparency = 0.45
end

--[[
	Собирает эскиз предмета. Возвращает nil, если эскиза нет — тогда DecorService
	поставит простую коробку по габариту каталога.
]]
--[[
	Кубики с буквами и цифрами — детские, из кубиков складывают первые слова.
	Два кубика внизу, третий сверху, на каждой грани крупный знак цвета буквы.
	Это единственный декор, который прямо про игру: азбука стоит на площади
	и на полянах, а не только в заданиях.

	Знаки идут по кругу: каждая следующая стопка берёт следующие три буквы
	алфавита, так что по всему миру встречаются все тридцать три.
]]
local CUBE = 2.3
local nextLetter = 0
local nextNumber = 0

local function cubeFaces(part: BasePart, glyph: string, color: Color3)
	for _, face in Enum.NormalId:GetEnumItems() do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(100, 100)
		gui.LightInfluence = 0.3
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = glyph
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.fromRGB(40, 35, 60)
		label.TextStrokeTransparency = 0.3
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Parent = gui
	end
end

local function cubeStack(model: Model, glyphs: { { glyph: string, color: Color3 } })
	local spots = {
		at(-CUBE / 2 - 0.1, CUBE / 2, 0) * CFrame.Angles(0, math.rad(-8), 0),
		at(CUBE / 2 + 0.1, CUBE / 2, 0.2) * CFrame.Angles(0, math.rad(12), 0),
		at(0, CUBE * 1.5, 0.1) * CFrame.Angles(0, math.rad(20), 0),
	}
	for index, spot in spots do
		local mark = glyphs[index]
		local cube = piece(
			model,
			`Cube_{index}`,
			Enum.PartType.Block,
			Vector3.one * CUBE,
			spot,
			Color3.fromRGB(252, 248, 238),
			Enum.Material.WoodPlanks
		)
		cubeFaces(cube, mark.glyph, mark.color)
	end
end

BUILDERS.letter_cubes = function(model: Model)
	local ordered = Letters.ordered()
	local glyphs = {}
	for _ = 1, 3 do
		nextLetter = nextLetter % #ordered + 1
		local letter = Letters.expect(ordered[nextLetter])
		table.insert(glyphs, { glyph = letter.glyph, color = letter.color })
	end
	cubeStack(model, glyphs)
end

local NUMBER_COLORS = {
	Color3.fromRGB(230, 90, 90),
	Color3.fromRGB(90, 150, 230),
	Color3.fromRGB(90, 180, 110),
	Color3.fromRGB(240, 170, 60),
	Color3.fromRGB(170, 110, 220),
}

BUILDERS.number_cubes = function(model: Model)
	local glyphs = {}
	for _ = 1, 3 do
		nextNumber = nextNumber % 10 + 1
		table.insert(
			glyphs,
			{ glyph = tostring(nextNumber), color = NUMBER_COLORS[(nextNumber - 1) % #NUMBER_COLORS + 1] }
		)
	end
	cubeStack(model, glyphs)
end

--[[
	Лес и деревня: мухоморы, пенёк, бревно, стол для пикника, домик-гриб,
	стожки сена и мельница. Всё, на что ребёнок захочет залезть.
]]
local CAP_RED = Color3.fromRGB(225, 70, 70)
local CREAM = Color3.fromRGB(250, 240, 220)
local STRAW = Color3.fromRGB(230, 200, 110)

-- Стоячий цилиндр: как ствол, но любой высоты, толщины и на любой высоте.
local function column(
	model: Model,
	name: string,
	height: number,
	diameter: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	return piece(
		model,
		name,
		Enum.PartType.Cylinder,
		Vector3.new(height, diameter, diameter),
		cframe * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material
	)
end

-- Шляпка гриба: плоский диск снизу и купол сверху, в белых точках.
local function mushroomCap(model: Model, name: string, cframe: CFrame, width: number, dots: number)
	column(model, `{name}Brim`, width * 0.24, width, cframe, CAP_RED)
	local dome = width * 0.78
	piece(
		model,
		`{name}Dome`,
		Enum.PartType.Ball,
		Vector3.one * dome,
		cframe * CFrame.new(0, width * 0.1, 0),
		CAP_RED
	)
	for index = 1, dots do
		local angle = index / dots * math.pi * 2 + 0.4
		piece(
			model,
			`{name}Dot_{index}`,
			Enum.PartType.Ball,
			Vector3.one * width * 0.16,
			cframe * CFrame.new(math.cos(angle) * width * 0.3, width * 0.36, math.sin(angle) * width * 0.3),
			Color3.fromRGB(255, 255, 250)
		)
	end
end

BUILDERS.mushroom = function(model: Model)
	column(model, "Stem", 3.8, 1.5, at(-0.5, 1.9, 0.3), CREAM)
	mushroomCap(model, "Cap", at(-0.5, 4.3, 0.3), 4, 3)
	column(model, "SmallStem", 1.6, 0.7, at(1.5, 0.8, -1.2), CREAM)
	mushroomCap(model, "SmallCap", at(1.5, 1.8, -1.2), 1.8, 1)
end

BUILDERS.stump = function(model: Model)
	column(model, "Stump", 2.2, 2.6, at(0, 1.1, 0), BARK, Enum.Material.Wood)
	column(model, "Rings", 0.2, 2.2, at(0, 2.25, 0), Color3.fromRGB(215, 180, 130), Enum.Material.Wood)
	piece(
		model,
		"Moss",
		Enum.PartType.Ball,
		Vector3.one * 0.9,
		at(0.9, 0.5, 0.8),
		LEAF_LIGHT,
		Enum.Material.Grass
	)
end

BUILDERS.log = function(model: Model)
	piece(
		model,
		"Log",
		Enum.PartType.Cylinder,
		Vector3.new(7.4, 2.4, 2.4),
		at(0, 1.2, 0),
		BARK,
		Enum.Material.Wood
	)
	for _, side in { -1, 1 } do
		piece(
			model,
			`LogEnd_{side}`,
			Enum.PartType.Cylinder,
			Vector3.new(0.2, 2, 2),
			at(side * 3.72, 1.2, 0),
			Color3.fromRGB(215, 180, 130),
			Enum.Material.Wood
		)
	end
end

BUILDERS.picnic_table = function(model: Model)
	piece(
		model,
		"Top",
		Enum.PartType.Block,
		Vector3.new(6.4, 0.4, 2.8),
		at(0, 2.9, 0),
		WOOD,
		Enum.Material.WoodPlanks
	)
	-- Скатерть в полоску: полосы поверх красного, а не шахматка из деталей.
	piece(
		model,
		"Cloth",
		Enum.PartType.Block,
		Vector3.new(4.2, 0.1, 2.9),
		at(0, 3.14, 0),
		Color3.fromRGB(235, 90, 90),
		Enum.Material.Fabric
	)
	for index = -1, 1, 2 do
		piece(
			model,
			`ClothStripe_{index}`,
			Enum.PartType.Block,
			Vector3.new(0.6, 0.12, 2.92),
			at(index * 1, 3.15, 0),
			Color3.fromRGB(255, 250, 245),
			Enum.Material.Fabric
		)
	end
	for _, side in { -1, 1 } do
		piece(
			model,
			`Bench_{side}`,
			Enum.PartType.Block,
			Vector3.new(6.4, 0.35, 1),
			at(0, 1.7, side * 2.4),
			WOOD,
			Enum.Material.WoodPlanks
		)
		piece(
			model,
			`Legs_{side}`,
			Enum.PartType.Block,
			Vector3.new(0.4, 2.8, 5.6),
			at(side * 2.4, 1.4, 0),
			Color3.fromRGB(160, 120, 80),
			Enum.Material.Wood
		)
	end
	piece(
		model,
		"Basket",
		Enum.PartType.Block,
		Vector3.new(1.2, 0.8, 0.9),
		at(-1.8, 3.6, 0.2),
		Color3.fromRGB(180, 130, 80),
		Enum.Material.WoodPlanks
	)
	piece(
		model,
		"Apple",
		Enum.PartType.Ball,
		Vector3.one * 0.6,
		at(1.4, 3.5, -0.3),
		Color3.fromRGB(230, 60, 60)
	)
end

BUILDERS.mushroom_house = function(model: Model)
	column(model, "Walls", 6.4, 6.6, at(0, 3.2, 0), CREAM)
	mushroomCap(model, "Roof", at(0, 7.4, 0), 11.6, 4)
	-- Дверь и окошки смотрят на −Z: туда, откуда подходят.
	piece(
		model,
		"Door",
		Enum.PartType.Block,
		Vector3.new(1.8, 3, 0.4),
		at(0, 1.5, -3.2),
		Color3.fromRGB(150, 100, 65),
		Enum.Material.WoodPlanks
	)
	piece(
		model,
		"DoorTop",
		Enum.PartType.Cylinder,
		Vector3.new(0.4, 1.8, 1.8),
		at(0, 3, -3.2) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(150, 100, 65),
		Enum.Material.WoodPlanks
	)
	for _, side in { -1, 1 } do
		local window = CFrame.Angles(0, side * math.rad(40), 0) * at(0, 4, -3.25)
		piece(
			model,
			`Window_{side}`,
			Enum.PartType.Cylinder,
			Vector3.new(0.3, 1.5, 1.5),
			window * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(150, 205, 240),
			Enum.Material.Glass
		)
	end
	piece(
		model,
		"Flower",
		Enum.PartType.Ball,
		Vector3.one * 0.8,
		at(-1.9, 0.4, -3.6),
		Color3.fromRGB(240, 130, 200)
	)
end

BUILDERS.hay_bales = function(model: Model)
	local spots = { at(-1.45, 0.8, 0), at(1.45, 0.8, 0.2), at(0, 2.4, 0.1) }
	for index, spot in spots do
		piece(
			model,
			`Bale_{index}`,
			Enum.PartType.Block,
			Vector3.new(2.8, 1.6, 1.8),
			spot * CFrame.Angles(0, math.rad(index * 7 - 10), 0),
			STRAW,
			Enum.Material.Grass
		)
		piece(
			model,
			`BaleBand_{index}`,
			Enum.PartType.Block,
			Vector3.new(0.25, 1.62, 1.82),
			spot * CFrame.Angles(0, math.rad(index * 7 - 10), 0),
			Color3.fromRGB(190, 150, 80),
			Enum.Material.Fabric
		)
	end
end

--[[
	Мельница: беленый домик-башня, красная крыша-купол, дверь и крылья спереди.
	Крылья — отдельная модель с меткой AF_Windmill: крутит их клиент
	(PlaygroundController), сервер ничего не гоняет по сети.
]]
BUILDERS.windmill = function(model: Model)
	column(model, "Tower", 9, 5.2, at(0, 4.5, 0.6), Color3.fromRGB(245, 240, 225), Enum.Material.Plaster)
	column(model, "TowerTop", 2, 4.2, at(0, 10, 0.6), Color3.fromRGB(245, 240, 225), Enum.Material.Plaster)
	piece(model, "Roof", Enum.PartType.Ball, Vector3.one * 4.6, at(0, 11.4, 0.6), CAP_RED)
	piece(
		model,
		"Door",
		Enum.PartType.Block,
		Vector3.new(1.6, 2.8, 0.4),
		at(0, 1.4, -1.95),
		Color3.fromRGB(150, 100, 65),
		Enum.Material.WoodPlanks
	)

	local blades = Instance.new("Model")
	blades.Name = "Blades"
	-- Крылья приезжают к клиенту целиком: иначе стриминг привёз бы часть лопастей позже, и они встали бы криво.
	blades.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	blades.Parent = model
	local hubAt = at(0, 11, -2.6)
	local hub = piece(
		blades,
		"Hub",
		Enum.PartType.Ball,
		Vector3.one * 1.1,
		hubAt,
		Color3.fromRGB(150, 100, 65),
		Enum.Material.Wood
	)
	-- Две длинные перекладины крестом и четыре паруса на них.
	for index = 1, 2 do
		piece(
			blades,
			`Arm_{index}`,
			Enum.PartType.Block,
			Vector3.new(0.35, 11.4, 0.3),
			hubAt * CFrame.Angles(0, 0, math.rad(45 + index * 90)),
			Color3.fromRGB(150, 100, 65),
			Enum.Material.Wood
		)
	end
	for index = 1, 4 do
		local spin = hubAt * CFrame.Angles(0, 0, math.rad(45 + index * 90))
		piece(
			blades,
			`Sail_{index}`,
			Enum.PartType.Block,
			Vector3.new(1.4, 4.2, 0.15),
			spin * CFrame.new(0.85, 3.4, 0.05),
			Color3.fromRGB(255, 252, 245),
			Enum.Material.Fabric
		)
	end
	blades.PrimaryPart = hub
	CollectionService:AddTag(hub, "AF_Windmill")
end

--[[
	Игрушки учёбы: большие счёты и стакан с карандашами. Не задание и не подсказка —
	просто вещи из детской, которые напоминают, куда ведут порталы.
]]
local RAINBOW = {
	Color3.fromRGB(235, 90, 90),
	Color3.fromRGB(245, 160, 70),
	Color3.fromRGB(245, 210, 80),
	Color3.fromRGB(110, 190, 110),
	Color3.fromRGB(100, 160, 235),
}

-- Счёты: три прутка, на верхнем одна косточка, на среднем две, на нижнем три — сосчитай.
BUILDERS.abacus = function(model: Model)
	for _, side in { -1, 1 } do
		piece(
			model,
			`Post_{side}`,
			Enum.PartType.Block,
			Vector3.new(0.8, 7.4, 2.4),
			at(side * 3.6, 3.7, 0),
			WOOD,
			Enum.Material.WoodPlanks
		)
	end
	piece(
		model,
		"Bar",
		Enum.PartType.Block,
		Vector3.new(6.4, 0.6, 1.2),
		at(0, 6.8, 0),
		Color3.fromRGB(170, 120, 80),
		Enum.Material.WoodPlanks
	)
	for row = 1, 3 do
		local y = 6.8 - row * 1.6
		piece(
			model,
			`Rod_{row}`,
			Enum.PartType.Cylinder,
			Vector3.new(6.6, 0.2, 0.2),
			at(0, y, 0),
			METAL,
			Enum.Material.Metal
		)
		for bead = 1, row do
			piece(
				model,
				`Bead_{row}_{bead}`,
				Enum.PartType.Ball,
				Vector3.one * 1.1,
				at(-3.2 + bead * 1.15, y, 0),
				RAINBOW[row * 2 - 1]
			)
		end
	end
end

BUILDERS.crayons = function(model: Model)
	column(model, "Cup", 3, 3.6, at(0, 1.5, 0), Color3.fromRGB(120, 170, 235))
	column(model, "CupRim", 0.4, 3.9, at(0, 3, 0), Color3.fromRGB(250, 250, 245))
	local tilts =
		{ { -0.7, -0.5, -8, 7.4 }, { 0.8, -0.3, 9, 6.6 }, { 0, 0.8, 4, 7.8 }, { -0.6, 0.7, -12, 6.2 } }
	for index, spec in tilts do
		local height = spec[4] - 1.2
		local base = at(spec[1], 1, spec[2]) * CFrame.Angles(math.rad(spec[3] * 0.4), 0, math.rad(spec[3]))
		local color = RAINBOW[index]
		column(model, `Crayon_{index}`, height, 0.9, base * CFrame.new(0, height / 2, 0), color)
		column(model, `CrayonTip_{index}`, 0.8, 0.5, base * CFrame.new(0, height + 0.4, 0), color)
	end
end

function DecorShapes.build(item): Model?
	local builder = BUILDERS[item.id]
	if not builder then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = `{item.id}_sketch`

	builder(model)

	if not model:FindFirstChildWhichIsA("BasePart") then
		model:Destroy()
		return nil
	end

	--[[
		Точка привязки — центр основания, и главной детали у эскиза нет намеренно.

		Габарит модели Roblox считает В СИСТЕМЕ ЕЁ ПРИВЯЗКИ. Назначь мы главной
		деталью ствол — а он лежит на боку, потому что цилиндры в Roblox лежат
		вдоль X, — и «ёлка 8 на 16» превратилась бы в «14 на 8» с низом на пяти
		студах над землёй. Ровно это и случилось при первой сборке, поймал тест.
	]]
	model.WorldPivot = CFrame.new()

	return model
end

function DecorShapes.has(id: string): boolean
	return BUILDERS[id] ~= nil
end

function DecorShapes.ids(): { string }
	local ids: { string } = {}
	for id in BUILDERS do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return DecorShapes
