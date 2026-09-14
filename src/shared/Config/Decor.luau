--!strict
--[[
	Декор площади: каталог моделей и расстановка. См. docs/21-DECOR.md.

	Здесь только ДАННЫЕ: что за предмет, какая у него модель и где он стоит.
	Ставит их DecorService, а модели приезжают из папки assets/models —
	их кладёт туда художник, а не программист.

	Три правила, ради которых конфиг вообще существует:

	  · декор ничего не делает. Ни одна модель не запускает испытание, не даёт
	    звёздочек и не мешает пройти. Ребёнок вправе залезть на любое дерево
	    и ничего этим не сломать;

	  · модели может не быть. Пока художник не принёс дерево, на его месте стоит
	    примитив-заглушка того же размера. Мир не имеет права выглядеть пустым
	    из-за того, что файл ещё не положили, и не имеет права падать из-за этого;

	  · площадь остаётся проходимой. У порталов, падов, спавна и дорожек есть
	    запретные зоны, и тест проверяет, что ни одна модель в них не влезла.
	    Дерево посреди входа в мир — это ребёнок, который не нашёл, куда идти.
]]

local Base = require(script.Parent.Base)

local Decor = {}

--[[
	Где искать модели в дереве игры. Rojo кладёт содержимое assets/models
	в ReplicatedStorage.Assets — см. default.project.json.
]]
Decor.FOLDER = "Assets"
Decor.SUBFOLDER = "decor"

export type Kind = "tree" | "bush" | "flower" | "rock" | "bench" | "lamp" | "fountain" | "sign"

export type Item = {
	id: string, -- он же имя файла: tree_pine -> assets/models/decor/tree_pine.rbxm
	title: string,
	kind: Kind,
	--[[
		Размер-ориентир в студах: во столько вписывается модель.

		Он нужен по двум причинам. Первая — заглушка: пока модели нет, примитив
		строится ровно этого размера, и расстановка выглядит и проверяется так же,
		как с готовым артом. Вторая — приёмка: модель, которая вдвое больше
		обещанного, ловится тестом, а не глазами на площади.
	]]
	size: Vector3,
	color: Color3, -- цвет заглушки; на готовую модель не влияет
	collide: boolean, -- сквозь кусты и цветы ребёнок проходит насквозь
}

local ITEMS: { Item } = {
	{
		id = "tree_pine",
		title = "Ёлка",
		kind = "tree",
		size = Vector3.new(8, 16, 8),
		color = Color3.fromRGB(90, 150, 100),
		collide = true,
	},
	{
		id = "tree_round",
		title = "Круглое дерево",
		kind = "tree",
		size = Vector3.new(10, 14, 10),
		color = Color3.fromRGB(120, 180, 110),
		collide = true,
	},
	{
		id = "bush_round",
		title = "Куст",
		kind = "bush",
		size = Vector3.new(5, 2.5, 5),
		color = Color3.fromRGB(140, 200, 130),
		collide = false,
	},
	{
		id = "flower_bed",
		title = "Клумба",
		kind = "flower",
		-- Два студа в высоту — это цветы на стеблях, а не голая земля.
		size = Vector3.new(6, 2, 6),
		color = Color3.fromRGB(240, 140, 150),
		collide = false,
	},
	{
		id = "rock_small",
		title = "Камень",
		kind = "rock",
		size = Vector3.new(4, 3, 4),
		color = Color3.fromRGB(170, 170, 180),
		collide = true,
	},
	{
		id = "bench",
		title = "Лавочка",
		kind = "bench",
		size = Vector3.new(6, 3, 2.5),
		color = Color3.fromRGB(200, 160, 110),
		collide = true,
	},
	{
		id = "lamp",
		title = "Фонарь",
		kind = "lamp",
		size = Vector3.new(2, 12, 2),
		color = Color3.fromRGB(240, 220, 150),
		collide = true,
	},
	{
		id = "fountain",
		title = "Фонтан",
		kind = "fountain",
		size = Vector3.new(14, 6, 14),
		color = Color3.fromRGB(150, 200, 235),
		collide = true,
	},
}

Decor.items = ITEMS

local byId: { [string]: Item } = {}
for _, item in ITEMS do
	assert(byId[item.id] == nil, `Decor: дубликат предмета "{item.id}"`)
	byId[item.id] = item
end

function Decor.get(id: string): Item?
	return byId[id]
end

function Decor.expect(id: string): Item
	local item = byId[id]
	assert(item, `Decor: неизвестный предмет "{item and item.id or id}"`)
	return item
end

function Decor.ids(): { string }
	local ids: { string } = {}
	for _, item in ITEMS do
		table.insert(ids, item.id)
	end
	table.sort(ids)
	return ids
end

-- ===== Запретные зоны =============================================================

--[[
	Куда ставить нельзя. Круг с центром и радиусом — этого хватает: всё, что должно
	остаться свободным, круглое или почти круглое.

	Список не «на всякий случай»: каждая зона — это место, куда ребёнок приходит
	ногами. Загороди вход в мир кустом, и он туда не пойдёт, потому что не увидит.
]]
export type Zone = {
	center: Vector2,
	radius: number,
	why: string,
}

local ZONES: { Zone } = {
	{ center = Vector2.new(0, 26), radius = 14, why = "точка появления" },
	{ center = Vector2.new(-16, -6), radius = 16, why = "портал мира букв" },
	{ center = Vector2.new(16, -6), radius = 16, why = "портал мира математики" },
	{
		center = Vector2.new(0, 0),
		radius = 12,
		why = "середина площади: проход к порталам",
	},
	{
		center = Vector2.new(Base.DAILY_LETTER_POSITION.X, Base.DAILY_LETTER_POSITION.Z),
		radius = 6,
		why = "камень буквы дня",
	},
}

--[[
	Пады занятий и магазин стоят полукругом; их зоны считаются той же формулой,
	что и сами пады. Дублировать координаты числами значило бы получить декор,
	стоящий на паде, ровно в тот день, когда полукруг чуть сдвинут.
]]
for slot = 1, Base.PAD_SLOTS do
	local position = Base.padPosition(slot)
	table.insert(ZONES, {
		center = Vector2.new(position.X, position.Z),
		radius = 12,
		why = `пад занятия {slot}`,
	})
end

--[[
	Четыре дорожки от площади к домам. Дерево посреди дорожки — не украшение,
	а вопрос «а туда вообще можно?», и ребёнок сворачивает.
]]
for index = 1, 4 do
	local angle = (index - 1) / 4 * math.pi * 2
	table.insert(ZONES, {
		center = Vector2.new(
			math.cos(angle) * (Base.PLAZA_RADIUS + 8),
			math.sin(angle) * (Base.PLAZA_RADIUS + 8)
		),
		radius = 10,
		why = `дорожка к домам {index}`,
	})
end

Decor.zones = ZONES

--[[
	Дальше этого от центра декор не ставим: там начинаются участки детей,
	и деревья на чужом дворе — это уже не парк, а мусор в чужом доме.
]]
Decor.MAX_RADIUS = Base.RING_RADIUS - Base.PLOT_SIZE

--[[
	Высота земли под точкой. Площадь выложена плиткой и на полстуда выше травы,
	и предмет, поставленный по высоте площади, но стоящий на траве, висит в воздухе.
	Мелочь, которую видно сразу и которую ищут потом полчаса.
]]
function Decor.groundY(x: number, z: number): number
	local inPlaza = math.sqrt(x * x + z * z) <= Base.PLAZA_RADIUS
	return if inPlaza then 1.6 else 1
end

-- Свободно ли место: точка не попадает ни в одну запретную зону.
function Decor.isClear(x: number, z: number, radius: number): (boolean, string?)
	local point = Vector2.new(x, z)
	for _, zone in ZONES do
		if (point - zone.center).Magnitude < zone.radius + radius then
			return false, zone.why
		end
	end
	return true, nil
end

-- ===== Расстановка ================================================================

export type Placement = {
	id: string, -- предмет из каталога
	x: number,
	z: number,
	rotation: number, -- поворот вокруг вертикали, в градусах
	scale: number?, -- множитель размера, если этот экземпляр крупнее собратьев
}

local PLACEMENTS: { Placement } = {}

-- Место, которое занимает предмет: половина большей стороны основания.
local function footprint(item: Item, scale: number): number
	return math.max(item.size.X, item.size.Z) / 2 * scale
end

--[[
	Ставит предмет, если место позволяет.

	Точка отбрасывается молча и это НАМЕРЕННО: кольцо деревьев считается формулой,
	и часть его точек неизбежно приходится на пады занятий. Пропустить такую точку —
	правильное поведение: лучше дырка в кольце, чем ёлка на паде. Дырку видно
	только нам, а ёлку — ребёнку, который не нашёл, куда встать.
]]
local function add(id: string, x: number, z: number, rotation: number, scale: number?): boolean
	local item = byId[id]
	assert(item, `Decor: в расстановке нет такого предмета — "{id}"`)

	local radius = footprint(item, scale or 1)

	if not Decor.isClear(x, z, radius) then
		return false
	end

	-- Не ближе, чем на сумму радиусов: иначе лавочка растёт из куста.
	for _, placed in PLACEMENTS do
		local other = byId[placed.id]
		local distance = (Vector2.new(x, z) - Vector2.new(placed.x, placed.z)).Magnitude
		if distance < radius + footprint(other, placed.scale or 1) then
			return false
		end
	end

	-- И не на участках детей: парк кончается там, где начинаются дома.
	if math.sqrt(x * x + z * z) + radius > Decor.MAX_RADIUS then
		return false
	end

	table.insert(PLACEMENTS, { id = id, x = x, z = z, rotation = rotation, scale = scale })
	return true
end

--[[
	Порядок здесь имеет значение: кто встал первым, тот и остался. Сначала
	расставляем то, что задумано в конкретных местах, и только потом кольцо
	деревьев — оно считается формулой и подвинуться может, а фонтан нет.
]]

--[[
	Фонтан с лавочками — за порталами, в дальней половине площади.

	Не в центре: в центре стоят входы в миры, и всё, что перед ними, ребёнок
	обходит вместо того, чтобы в них войти. Зато дальняя половина иначе пустует
	совсем — а именно туда ребёнок выходит, вернувшись из забега.
]]
add("fountain", 0, -34, 0)
add("bench", -14, -40, 20)
add("bench", 14, -40, -20)
add("lamp", -26, -26, 0)
add("lamp", 26, -26, 0)
add("rock_small", 34, -32, 25)
add("rock_small", -34, -32, -40)
add("bush_round", 44, -8, 0)
add("bush_round", -44, -8, 0)

-- Клумбы у выходов на дорожки к домам: они показывают, куда идти, и не мешают идти.
for index = 1, 4 do
	local angle = (index - 1) / 4 * math.pi * 2
	local radius = Base.PLAZA_RADIUS - 8
	add("flower_bed", math.cos(angle) * radius, math.sin(angle) * radius, math.deg(-angle))
end

--[[
	Кольцо деревьев ЗА краем площади, на траве: край плитки должен читаться
	как опушка, а не как обрыв текстуры. Деревья чередуются, чтобы кольцо
	не выглядело забором из одинаковых ёлок.

	Четыре точки кольца всегда выпадают — те, что приходятся на дорожки к домам.
	Так и задумано: дорожка важнее симметрии.
]]
local RING_COUNT = 20
local RING_KINDS = { "tree_pine", "tree_round", "bush_round" }
for index = 1, RING_COUNT do
	local angle = (index - 1) / RING_COUNT * math.pi * 2
	local radius = Base.PLAZA_RADIUS + 9
	add(
		RING_KINDS[(index - 1) % #RING_KINDS + 1],
		math.cos(angle) * radius,
		math.sin(angle) * radius,
		math.deg(-angle)
	)
end

Decor.placements = PLACEMENTS

return Decor
