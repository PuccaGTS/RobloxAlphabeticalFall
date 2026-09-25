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
local Chests = require(script.Parent.Chests)
local Playground = require(script.Parent.Playground)

local Decor = {}

--[[
	Где искать модели в дереве игры. Rojo кладёт содержимое assets/models
	в ReplicatedStorage.Assets — см. default.project.json.
]]
Decor.FOLDER = "Assets"
Decor.SUBFOLDER = "decor"

export type Kind =
	"tree"
	| "bush"
	| "flower"
	| "rock"
	| "bench"
	| "lamp"
	| "fountain"
	| "sign"
	| "mushroom"
	| "house"
	| "toy"
	| "play"

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
	--[[
		Номер модели в Creator Store (docs/21-DECOR.md § 7.1). Сервер берёт её сам
		через InsertService, если файла в assets/models нет: достаточно один раз
		нажать Get на странице модели, и сохранять её в файл из Studio не нужно.
	]]
	assetId: number?,
	--[[
		Модель лежит в проекте (assets/models/decor/<id>.model.json, импорт —
		tools/models/import.py), эскиза из деталей у предмета нет. Тест проверяет,
		что файл на месте: без него предмет встал бы серой коробкой.
	]]
	file: boolean?,
	--[[
		Предмет горизонта (Config/Horizon): стоит за изгородью, куда не дойти,
		и в парке не появляется. Ему можно быть с гору — правило «не шире
		двадцати студов» про проход, а здесь проходить некому.
	]]
	horizon: boolean?,
}

local ITEMS: { Item } = {
	{
		id = "tree_pine",
		assetId = 5616880673,
		title = "Ёлка",
		kind = "tree",
		size = Vector3.new(8, 16, 8),
		color = Color3.fromRGB(90, 150, 100),
		collide = true,
	},
	{
		id = "tree_round",
		assetId = 13870570014,
		title = "Круглое дерево",
		kind = "tree",
		size = Vector3.new(10, 14, 10),
		color = Color3.fromRGB(120, 180, 110),
		collide = true,
	},
	{
		id = "bush_round",
		assetId = 14720410685,
		title = "Куст",
		kind = "bush",
		size = Vector3.new(5, 2.5, 5),
		color = Color3.fromRGB(140, 200, 130),
		collide = false,
	},
	{
		id = "flower_bed",
		assetId = 1353190583,
		title = "Клумба",
		kind = "flower",
		-- Два студа в высоту — это цветы на стеблях, а не голая земля.
		size = Vector3.new(6, 2, 6),
		color = Color3.fromRGB(240, 140, 150),
		collide = false,
	},
	{
		id = "rock_small",
		assetId = 2557020130,
		title = "Камень",
		kind = "rock",
		size = Vector3.new(4, 3, 4),
		color = Color3.fromRGB(170, 170, 180),
		collide = true,
	},
	--[[
		Горный хребет на горизонте (Config/Horizon): стоит за изгородью, куда
		не дойти, поэтому в парке его нет. Low-Poly Rocky Mountain Border,
		DaveCam456, 557 треугольников.
	]]
	{
		id = "mountain_rocky",
		assetId = 11751636142,
		file = true,
		horizon = true,
		title = "Горный хребет",
		kind = "rock",
		size = Vector3.new(377, 215, 136),
		color = Color3.fromRGB(120, 135, 160),
		collide = false,
	},
	{
		id = "bench",
		assetId = 7499829922,
		title = "Лавочка",
		kind = "bench",
		size = Vector3.new(6, 3, 2.5),
		color = Color3.fromRGB(200, 160, 110),
		collide = true,
	},
	{
		id = "lamp",
		assetId = 565846542,
		title = "Фонарь",
		kind = "lamp",
		size = Vector3.new(2, 12, 2),
		color = Color3.fromRGB(240, 220, 150),
		collide = true,
	},
	--[[
		Кубики с буквами и с цифрами: стопка из трёх. Моделей у них нет и не нужно —
		знаки на гранях рисует эскиз, и у каждой стопки свои буквы.
	]]
	{
		id = "letter_cubes",
		title = "Кубики с буквами",
		kind = "sign",
		size = Vector3.new(5.6, 4.8, 3.6),
		color = Color3.fromRGB(252, 248, 238),
		collide = true,
	},
	{
		id = "number_cubes",
		title = "Кубики с цифрами",
		kind = "sign",
		size = Vector3.new(5.6, 4.8, 3.6),
		color = Color3.fromRGB(252, 248, 238),
		collide = true,
	},
	--[[
		Лесное и деревенское: мухоморы, пеньки, брёвна, стол для пикника,
		домик-гриб, стожки сена и мельница. На первой прогулке по большому парку
		деревья, кусты и камни повторялись до зевоты — ребёнку нужно, чтобы
		за следующим деревом было что-то новое, на что можно залезть.
		Модели отобраны так же, как первые восемь (docs/21-DECOR.md § 7.1).
	]]
	{
		id = "mushroom",
		assetId = 4644085527,
		title = "Мухоморы",
		kind = "mushroom",
		size = Vector3.new(5, 6.6, 5),
		color = Color3.fromRGB(225, 70, 70),
		collide = true,
	},
	{
		id = "stump",
		assetId = 6764157470,
		title = "Пенёк",
		kind = "rock",
		size = Vector3.new(3, 2.6, 3),
		color = Color3.fromRGB(135, 95, 65),
		collide = true,
	},
	{
		id = "log",
		assetId = 11312714034,
		title = "Бревно",
		kind = "rock",
		size = Vector3.new(8, 2.6, 2.6),
		color = Color3.fromRGB(150, 105, 70),
		collide = true,
	},
	{
		id = "picnic_table",
		assetId = 23153940,
		title = "Стол для пикника",
		kind = "bench",
		size = Vector3.new(7, 4, 6),
		color = Color3.fromRGB(190, 145, 95),
		collide = true,
	},
	{
		id = "mushroom_house",
		assetId = 11483003911,
		title = "Домик-гриб",
		kind = "house",
		size = Vector3.new(12, 13.2, 12),
		color = Color3.fromRGB(225, 70, 70),
		collide = true,
	},
	{
		id = "hay_bales",
		assetId = 5464985431,
		title = "Стожки сена",
		kind = "rock",
		size = Vector3.new(6, 3.4, 4),
		color = Color3.fromRGB(230, 200, 110),
		collide = true,
	},
	-- Мельница, счёты и карандаши — только эскизы: подходящих моделей в Store нет.
	{
		id = "windmill",
		title = "Мельница",
		kind = "house",
		size = Vector3.new(10, 17, 7),
		color = Color3.fromRGB(245, 240, 225),
		collide = true,
	},
	{
		id = "abacus",
		title = "Счёты",
		kind = "toy",
		size = Vector3.new(8, 7.4, 2.4),
		color = Color3.fromRGB(200, 150, 100),
		collide = true,
	},
	{
		id = "crayons",
		title = "Карандаши в стакане",
		kind = "toy",
		size = Vector3.new(5, 8.4, 5),
		color = Color3.fromRGB(120, 170, 235),
		collide = true,
	},
	--[[
		Игрушки-великаны и детская площадка из Creator Store (импорт 17.09.2026,
		tools/models/picks.json). На первой прогулке мир назвали скучным: деревья,
		клумбы и кубики. Теперь по дороге есть резиновая утка ростом с дом,
		плюшевый мишка, машинка, динозаврик, надувной замок, воздушный шар.
		На всё крупное можно залезть.
	]]
	{
		id = "tree_round2",
		assetId = 3287226226,
		file = true,
		title = "Пышное дерево",
		kind = "tree",
		size = Vector3.new(10, 14, 10),
		color = Color3.fromRGB(110, 175, 95),
		collide = true,
	},
	{
		id = "tree_blossom",
		assetId = 5950446599,
		file = true,
		title = "Цветущее дерево",
		kind = "tree",
		size = Vector3.new(12, 14, 9),
		color = Color3.fromRGB(245, 170, 205),
		collide = true,
	},
	{
		id = "bush_round2",
		assetId = 10432612977,
		file = true,
		title = "Светлый куст",
		kind = "bush",
		size = Vector3.new(4, 3.6, 4),
		color = Color3.fromRGB(170, 215, 90),
		collide = false,
	},
	{
		id = "rubber_duck",
		assetId = 5134201685,
		file = true,
		title = "Резиновая утка",
		kind = "toy",
		size = Vector3.new(7, 7.5, 10),
		color = Color3.fromRGB(255, 220, 60),
		collide = true,
	},
	{
		id = "teddy_bear",
		assetId = 12549476788,
		file = true,
		title = "Плюшевый мишка",
		kind = "toy",
		size = Vector3.new(8, 9, 5.5),
		color = Color3.fromRGB(190, 130, 80),
		collide = true,
	},
	{
		id = "rocking_horse",
		assetId = 4722865973,
		file = true,
		title = "Лошадка-качалка",
		kind = "toy",
		size = Vector3.new(5, 3.1, 6.6),
		color = Color3.fromRGB(215, 140, 80),
		collide = true,
	},
	{
		id = "toy_car",
		assetId = 14133969865,
		file = true,
		title = "Игрушечная машинка",
		kind = "toy",
		size = Vector3.new(10, 5, 6.7),
		color = Color3.fromRGB(90, 160, 80),
		collide = true,
	},
	{
		id = "toy_dino",
		assetId = 5151489661,
		file = true,
		title = "Динозаврик",
		kind = "toy",
		size = Vector3.new(11, 6, 3.4),
		color = Color3.fromRGB(110, 200, 110),
		collide = true,
	},
	{
		id = "hot_air_balloon",
		assetId = 166871533,
		file = true,
		title = "Воздушный шар",
		kind = "toy",
		size = Vector3.new(4, 34, 4.6),
		color = Color3.fromRGB(240, 120, 110),
		collide = true,
	},
	{
		id = "tent",
		assetId = 11853786155,
		file = true,
		title = "Палатка",
		kind = "house",
		size = Vector3.new(11, 5.4, 10.5),
		color = Color3.fromRGB(230, 210, 150),
		collide = true,
	},
	{
		id = "bouncy_castle",
		assetId = 28701,
		file = true,
		title = "Надувной замок",
		kind = "play",
		size = Vector3.new(13, 24, 17),
		color = Color3.fromRGB(250, 215, 60),
		collide = true,
	},
	{
		id = "sand_castle",
		assetId = 4882256146,
		file = true,
		title = "Замок из песка",
		kind = "toy",
		size = Vector3.new(7, 3.7, 7),
		color = Color3.fromRGB(230, 205, 150),
		collide = true,
	},
	{
		id = "koi_bridge",
		assetId = 574502744,
		file = true,
		title = "Горбатый мостик",
		kind = "play",
		size = Vector3.new(19, 7.4, 4.4),
		color = Color3.fromRGB(150, 100, 70),
		collide = true,
	},
	{
		id = "swing",
		assetId = 3245765758,
		file = true,
		title = "Качели",
		kind = "play",
		size = Vector3.new(7, 9.6, 6.8),
		color = Color3.fromRGB(120, 90, 70),
		collide = true,
	},
	{
		id = "merry_wheel",
		assetId = 15709165,
		file = true,
		title = "Крутилка",
		kind = "play",
		size = Vector3.new(13, 2.6, 13),
		color = Color3.fromRGB(230, 60, 60),
		collide = true,
	},
	{
		id = "fountain",
		assetId = 5477511653,
		title = "Фонтан",
		kind = "fountain",
		size = Vector3.new(14, 6, 14),
		color = Color3.fromRGB(150, 200, 235),
		collide = true,
	},
}

Decor.items = ITEMS

--[[
	Пруд под горбатым мостиком. Мостик из Creator Store стоял прямо на траве:
	горб есть, а перебираться не через что. Под каждый мостик ставится пруд
	(DecorService), в нём плавают карпы (LiveWorldController).

	Форма — три круга воды вдоль мостика, в координатах мостика: x — вдоль
	пролёта, z — поперёк. Пролёт 19 студов, поэтому вода кончается у его опор.
	Карпы плавают по эллипсу KOI_PATH внутри воды и ныряют под мостик.
]]
Decor.POND_UNDER = "koi_bridge"
Decor.POND_BLOBS = {
	{ x = 0, z = 0, radius = 6 },
	{ x = -4.4, z = 0.6, radius = 4.6 },
	{ x = 4.4, z = -0.6, radius = 4.6 },
}
Decor.KOI_PATH = { radiusX = 6.3, radiusZ = 3 }

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
	{
		center = Vector2.new(Base.MAP_BOARD_POSITION.X, Base.MAP_BOARD_POSITION.Z),
		radius = 10,
		why = "доска-карта «Куда пойти?»",
	},
	{
		center = Vector2.new(Base.SECRETS_PAD_POSITION.X, Base.SECRETS_PAD_POSITION.Z),
		radius = 8,
		why = "пад «Охота за секретами»",
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

--[[
	Дорожки к домам по всей длине, а не только у площади: парк стал гуще,
	и дерево на середине дорожки — тот же вопрос «а туда можно?».
]]
local PATH_HALF_WIDTH = 5
for index = 1, 4 do
	local angle = (index - 1) / 4 * math.pi * 2
	local distance = Base.PLAZA_RADIUS
	while distance < Base.RING_RADIUS do
		table.insert(ZONES, {
			center = Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance),
			radius = PATH_HALF_WIDTH,
			why = `дорожка к домам {index}`,
		})
		distance += 8
	end
end

-- Сундуки: к ним подходят вплотную, и открыть сундук за кустом нельзя.
for _, chest in Chests.all do
	local position = Chests.position(chest)
	table.insert(ZONES, {
		center = Vector2.new(position.X, position.Z),
		radius = 7,
		why = `сундук {chest.id}`,
	})
end

-- Игровые места парка: батут в ёлках не найти, а классики под кустом не попрыгать.
for _, spot in Playground.spots do
	local position = Playground.position(spot)
	table.insert(ZONES, {
		center = Vector2.new(position.X, position.Z),
		radius = spot.radius,
		why = `игровое место {spot.id}`,
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
-- Кубики у своих порталов: с буквами у мира букв, с цифрами у мира математики.
add("letter_cubes", -37, -10, 25)
add("number_cubes", 37, -10, -25)
add("letter_cubes", -30, -30, -15)
add("number_cubes", 30, -30, 15)

--[[
	Игрушки-великаны сразу за краем площади — то, что ребёнок видит, появившись:
	за порталами надувной замок, утка ростом с дом и воздушный шар над деревьями,
	слева динозаврик и палатка, справа машинка и лошадка-качалка, за спиной качели,
	крутилка и горбатый мостик. Ставятся раньше колец и россыпи: место за ними.
]]
local TOYS = {
	{ "bouncy_castle", 30, -98, 180 },
	{ "rubber_duck", -30, -84, 150 },
	{ "hot_air_balloon", -48, -132, 0 },
	{ "hot_air_balloon", 70, -150, 40 },
	{ "teddy_bear", 58, -70, 210 },
	{ "sand_castle", -58, -66, 20 },
	{ "toy_dino", -92, -24, 70 },
	{ "tent", -104, 34, 110 },
	{ "tree_blossom", -84, 62, 0 },
	{ "toy_car", 92, -30, 250 },
	{ "rocking_horse", 84, 46, 290 },
	{ "tree_blossom", 104, 20, 90 },
	{ "swing", -24, 92, 0 },
	{ "merry_wheel", 26, 96, 0 },
	{ "koi_bridge", -64, 110, 40 },
	{ "tree_blossom", 62, 116, 30 },
	{ "rubber_duck", 150, 70, 300 },
	{ "teddy_bear", -150, -70, 80 },
	{ "toy_dino", 120, -120, 220 },
	{ "tent", 140, 130, 200 },
}
for _, toy in TOYS do
	add(toy[1], toy[2], toy[3], toy[4])
end

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
local RING_KINDS = {
	"tree_pine",
	"tree_round",
	"bush_round",
	"tree_blossom",
	"tree_round2",
	"bush_round2",
	"rock_small",
}
local ringRandom = Random.new(54)
for index = 1, RING_COUNT do
	-- Опушка живая: деревья чуть вразброс по кругу и разного роста.
	local angle = (index - 1 + ringRandom:NextNumber() * 0.5) / RING_COUNT * math.pi * 2
	local radius = Base.PLAZA_RADIUS + 7 + ringRandom:NextNumber() * 5
	local id = RING_KINDS[ringRandom:NextInteger(1, #RING_KINDS)]
	add(
		id,
		math.cos(angle) * radius,
		math.sin(angle) * radius,
		ringRandom:NextNumber() * 360,
		if id == "rock_small" then nil else 0.85 + ringRandom:NextNumber() * 0.4
	)
end

--[[
	Парк между площадью и домами.

	На первой проверке мир назвали пустым: от края площади до участков лежало
	полторы сотни студов голой травы, и дома стояли вплотную друг к другу.
	Дома разнесены (Config/Base.PLOT_GAP), а трава между ними теперь парк:
	фонари вдоль дорожек, рощи и полянки между дорожками, опушка перед домами.

	Всё ставится той же функцией add и подчиняется тем же запретам: ничего
	на дорожках, на сундуках и на чужих участках.
]]

--[[
	Фонари вдоль каждой дорожки к домам. Не через равный шаг и не строго
	по очереди слева-справа: на первой прогулке ровный ритм «дерево, фонарь,
	кубики» читался как забор. Шаг гуляет, сторона иногда повторяется,
	а между фонарями встают то лавочка, то клумба, то камень — у каждой
	дорожки свой набор.
]]
local pathRandom = Random.new(77)
local PATH_EXTRAS = {
	{ "bench", "flower_bed", "rock_small" },
	{ "flower_bed", "bush_round", "bench" },
	{ "rock_small", "bench", "flower_bed" },
	{ "bush_round", "flower_bed", "rock_small" },
}
for index = 1, 4 do
	local angle = (index - 1) / 4 * math.pi * 2
	local along = Vector2.new(math.cos(angle), math.sin(angle))
	local across = Vector2.new(-along.Y, along.X)
	local distance = Base.PLAZA_RADIUS + 18 + pathRandom:NextNumber() * 8
	local side = if index % 2 == 0 then 1 else -1
	local extra = 1
	while distance < Decor.MAX_RADIUS - 6 do
		local spot = along * distance + across * (PATH_HALF_WIDTH + 3) * side
		add("lamp", spot.X, spot.Y, math.deg(-angle) + pathRandom:NextNumber() * 20)

		-- Между фонарями — что-то своё, на другой стороне и чуть дальше от дорожки.
		local between = distance + 11 + pathRandom:NextNumber() * 4
		local kinds = PATH_EXTRAS[index]
		local id = kinds[(extra - 1) % #kinds + 1]
		local offset = PATH_HALF_WIDTH + 5 + pathRandom:NextNumber() * 4
		local other = along * between - across * offset * side
		add(id, other.X, other.Y, pathRandom:NextNumber() * 360)
		extra += 1

		distance += 22 + pathRandom:NextNumber() * 12
		if pathRandom:NextNumber() < 0.7 then
			side = -side
		end
	end
end

--[[
	Рощи и полянки — по одной на каждую четверть между дорожками. Роща ближе
	к площади, полянка с клумбами и лавочкой — ближе к домам: по дороге домой
	есть где присесть.
]]
-- У каждой рощи свой характер: ельник, лиственная, кустарник с камнями, смешанная.
local GROVES = {
	{ "tree_pine", "tree_pine", "tree_pine", "tree_round", "bush_round", "rock_small" },
	{ "tree_blossom", "tree_round", "bush_round2", "tree_blossom", "flower_bed", "bush_round" },
	{ "bush_round", "rock_small", "tree_pine", "rock_small", "bush_round", "tree_round" },
	{ "tree_round2", "tree_pine", "tree_round", "tree_blossom", "bush_round2", "bush_round" },
}
local GROVE_HEART = { "tree_pine", "tree_round", "tree_pine", "tree_round" }
local groveRandom = Random.new(105)
for quarter = 1, 4 do
	local angle = ((quarter - 1) / 4 + 1 / 8 + (groveRandom:NextNumber() - 0.5) * 0.05) * math.pi * 2
	local center = Vector2.new(math.cos(angle), math.sin(angle)) * (95 + groveRandom:NextNumber() * 20)
	for index, id in GROVES[quarter] do
		local around = index / #GROVES[quarter] * math.pi * 2 + quarter + groveRandom:NextNumber() * 0.6
		local radius = (if index <= 4 then 11 else 19) + groveRandom:NextNumber() * 4
		local spot = center + Vector2.new(math.cos(around), math.sin(around)) * radius
		local tall = id == "tree_pine" or id == "tree_round"
		add(
			id,
			spot.X,
			spot.Y,
			groveRandom:NextNumber() * 360,
			if tall then 0.9 + groveRandom:NextNumber() * 0.5 else nil
		)
	end
	add(GROVE_HEART[quarter], center.X, center.Y, quarter * 30, 1.4 + groveRandom:NextNumber() * 0.3)

	local meadow = Vector2.new(math.cos(angle + 0.25), math.sin(angle + 0.25)) * 160
	add("flower_bed", meadow.X, meadow.Y, quarter * 20)
	add("flower_bed", meadow.X + 9, meadow.Y - 6, quarter * 50)
	add("bench", meadow.X - 8, meadow.Y + 6, quarter * 90)
	add("rock_small", meadow.X + 4, meadow.Y + 12, quarter * 15)

	local meadow2 = Vector2.new(math.cos(angle - 0.3), math.sin(angle - 0.3)) * 140
	add("flower_bed", meadow2.X, meadow2.Y, quarter * 35)
	add("bush_round", meadow2.X - 10, meadow2.Y, 0)
end

--[[
	Грибная деревня, мельницы и игрушки — во внешнем поясе парка.

	Кольцо участков стало шире, и пояс между рощами и опушкой перед домами
	остался почти пустым: россыпь распределена на весь парк и там редка.
	Теперь по дороге домой в каждой четверти своё место: в двух — домик-гриб
	с мухоморами и пеньками, в двух других — мельница со стожками и столом
	для пикника. Счёты стоят ближе к миру математики, карандаши — к миру букв.
]]
local villageRandom = Random.new(314)
for quarter = 1, 4 do
	local angle = ((quarter - 1) / 4 + 1 / 8 + (villageRandom:NextNumber() - 0.5) * 0.06) * math.pi * 2
	local center = Vector2.new(math.cos(angle), math.sin(angle)) * (Decor.MAX_RADIUS - 52)
	local facing = math.deg(-angle) + 90
	if quarter % 2 == 1 then
		add("mushroom_house", center.X, center.Y, facing)
		for index = 1, 5 do
			local around = index / 5 * math.pi * 2 + villageRandom:NextNumber() * 0.5
			local spot = center
				+ Vector2.new(math.cos(around), math.sin(around)) * (12 + villageRandom:NextNumber() * 4)
			local id = if index % 2 == 0 then "stump" else "mushroom"
			add(id, spot.X, spot.Y, villageRandom:NextNumber() * 360, 0.8 + villageRandom:NextNumber() * 0.5)
		end
	else
		add("windmill", center.X, center.Y, facing)
		local side = Vector2.new(-math.sin(angle), math.cos(angle))
		local inward = -Vector2.new(math.cos(angle), math.sin(angle))
		local hay = center + side * 10
		add("hay_bales", hay.X, hay.Y, villageRandom:NextNumber() * 360)
		local hay2 = center + side * 9 + inward * 7
		add("hay_bales", hay2.X, hay2.Y, villageRandom:NextNumber() * 360)
		local table_ = center - side * 11 + inward * 6
		add("picnic_table", table_.X, table_.Y, facing)
		local log = center - side * 6 + inward * 14
		add("log", log.X, log.Y, facing + 30)
	end
end

--[[
	Опушка перед домами: кольцо деревьев у края парка. Дома за ней читаются
	как отдельный посёлок, а не как продолжение площади.
]]
local EDGE_COUNT = 44
local EDGE_KINDS = { "tree_pine", "tree_round", "tree_round2", "bush_round", "tree_blossom", "tree_pine" }
local edgeRandom = Random.new(202)
for index = 1, EDGE_COUNT do
	local angle = (index - 0.5 + (edgeRandom:NextNumber() - 0.5) * 0.6) / EDGE_COUNT * math.pi * 2
	local radius = Decor.MAX_RADIUS - 8 - edgeRandom:NextNumber() * 6
	add(
		EDGE_KINDS[edgeRandom:NextInteger(1, #EDGE_KINDS)],
		math.cos(angle) * radius,
		math.sin(angle) * radius,
		edgeRandom:NextNumber() * 360,
		0.9 + edgeRandom:NextNumber() * 0.4
	)
end

--[[
	Россыпь: деревья, кусты и камни по свободным местам. Случайность
	с постоянным сидом — расстановка одинаковая у всех и каждый запуск,
	а тест проверяет её так же, как ручную.
]]
-- Кубиков в россыпи мало: встреченные на каждом шагу, они и делали парк однообразным.
local SCATTER = {
	"tree_round",
	"tree_pine",
	"bush_round",
	"rock_small",
	"flower_bed",
	"bush_round",
	"tree_round",
	"rock_small",
	"tree_pine",
	"flower_bed",
	"letter_cubes",
	"number_cubes",
}
local scatter = Random.new(2026)
for _ = 1, 140 do
	local angle = scatter:NextNumber() * math.pi * 2
	local radius = Base.PLAZA_RADIUS + 25 + scatter:NextNumber() * (Decor.MAX_RADIUS - Base.PLAZA_RADIUS - 40)
	local id = SCATTER[scatter:NextInteger(1, #SCATTER)]
	add(id, math.cos(angle) * radius, math.sin(angle) * radius, scatter:NextNumber() * 360)
end

-- Счёты по стороне мира математики (+X), карандаши — мира букв (−X).
local toyRandom = Random.new(515)
for index = 1, 8 do
	local isMath = index % 2 == 0
	local angle = (index / 8 - 0.5) * math.pi * 0.9
		+ (if isMath then 0 else math.pi)
		+ (toyRandom:NextNumber() - 0.5) * 0.2
	local radius = Base.PLAZA_RADIUS
		+ 40
		+ toyRandom:NextNumber() * (Decor.MAX_RADIUS - Base.PLAZA_RADIUS - 70)
	add(
		if isMath then "abacus" else "crayons",
		math.cos(angle) * radius,
		math.sin(angle) * radius,
		math.deg(-angle) + 90 + (toyRandom:NextNumber() - 0.5) * 40
	)
end

-- Лесная мелочь в рощах и по всему парку: мухоморы, пеньки, брёвна.
local WOODLAND = { "mushroom", "stump", "log", "mushroom", "stump", "picnic_table" }
local woodland = Random.new(4096)
for _ = 1, 90 do
	local angle = woodland:NextNumber() * math.pi * 2
	local radius = Base.PLAZA_RADIUS
		+ 30
		+ woodland:NextNumber() * (Decor.MAX_RADIUS - Base.PLAZA_RADIUS - 44)
	local id = WOODLAND[woodland:NextInteger(1, #WOODLAND)]
	add(id, math.cos(angle) * radius, math.sin(angle) * radius, woodland:NextNumber() * 360)
end

-- Внешний пояс гуще деревьями: россыпь выше заполнила в основном ближнюю часть.
local outer = Random.new(8128)
local OUTER =
	{ "tree_round", "tree_pine", "bush_round2", "flower_bed", "tree_blossom", "tree_round2", "rock_small" }
for _ = 1, 70 do
	local angle = outer:NextNumber() * math.pi * 2
	local radius = 175 + outer:NextNumber() * (Decor.MAX_RADIUS - 190)
	local id = OUTER[outer:NextInteger(1, #OUTER)]
	local tall = id == "tree_pine" or id == "tree_round"
	add(
		id,
		math.cos(angle) * radius,
		math.sin(angle) * radius,
		outer:NextNumber() * 360,
		if tall then 0.9 + outer:NextNumber() * 0.4 else nil
	)
end

Decor.placements = PLACEMENTS

return Decor
