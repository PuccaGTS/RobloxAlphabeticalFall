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
