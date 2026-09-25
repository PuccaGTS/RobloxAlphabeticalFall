--!strict
--[[
	Участок игрока: геометрия площадки и каталог построек. См. docs/15-HOME-BASE.md.

	Зачем дом вообще: косметика отвечает на вопрос «что я получил», дом — на другой,
	более сильный для пяти лет: «что я построил». Шапку ребёнок надел и забыл,
	а дом он видит каждый вход, помнит, что там было вчера, и хочет достроить.

	Два правила из доки зашиты прямо в данные:
	  · улучшение ЗАМЕНЯЕТ предыдущее, а не ставится рядом — поэтому у категории
	    один уровень, а не список купленного;
	  · строить свободно нельзя — только выбор из готовых уровней в фиксированных
	    слотах. Свободный редактор для четырёхлетки — это сломанный дом и слёзы.

	Цены и уровни живут здесь, а не в коде сервиса: сервер обязан брать цену отсюда,
	из запроса клиента не берётся ничего, кроме названия категории.
]]

local Base = {}

--[[
	Двадцать участков по краю площади: столько детей помещается на сервер.
	Участок гарантирован каждому — ни очереди, ни «место занято».
]]
Base.PLOT_COUNT = 20
--[[
	Сторона участка; фиксирована, чтобы не было гонки «у кого больше».
	Было сорок студов, и в них едва помещались дом, комнаты, Башня, флаги
	и мебель. Огород, площадка, живность и транспорт туда уже не влезали:
	участок вырос до 64, у каждой новой вещи своё место (spots ниже).
]]
Base.PLOT_SIZE = 64
--[[
	Промежуток между участками. Было двенадцать студов, и на первой проверке
	дома «стояли слишком близко»: забор к забору, как в очереди. Теперь между
	домами полоса сада, и каждый участок читается отдельным двором.
]]
Base.PLOT_GAP = 36

--[[
	Радиус кольца участков считается из их числа и размера, а не задан числом.
	Иначе при добавлении двадцать первого участка дома молча налезут друг на друга,
	и заметит это ребёнок, а не мы.
]]
Base.RING_RADIUS = math.ceil(Base.PLOT_COUNT * (Base.PLOT_SIZE + Base.PLOT_GAP) / (2 * math.pi))

-- Площадь в центре: порталы, магазин и пады занятий.
Base.PLAZA_RADIUS = 54

--[[
	Пады занятий и магазин стоят полукругом перед порталами, со стороны точки
	появления. Раскладка живёт здесь, а не в WorldService: по ней же декор
	держит пады свободными (Config/Decor), и два числа об одном полукруге
	однажды уже разошлись бы.

	Мест семь: шесть занятий и магазин последним, чтобы потратить перед выходом
	в мир. Радиус и дуга подобраны так, чтобы между падами оставался проход:
	с «Весами» дуга стала шире, и между падами 12 × 12 остаётся около 6,5 стада прохода.
]]
Base.PAD_DISTANCE = 46
Base.PAD_SLOTS = 8 -- семь занятий и магазин; с «Ягодами» полукруг стал шире и дальше
local PAD_ARC_FROM = 0.05
local PAD_ARC_SPAN = 0.9

function Base.padPosition(slot: number): Vector3
	local angle = math.pi * (PAD_ARC_FROM + PAD_ARC_SPAN * (slot - 1) / math.max(1, Base.PAD_SLOTS - 1))
	return Vector3.new(math.cos(angle) * Base.PAD_DISTANCE, 0, math.sin(angle) * Base.PAD_DISTANCE)
end
--[[
	Камень буквы дня — за порталами, между ними и фонтаном. С точки появления
	его видно в просвете между арками, но на пути к порталам он не лежит:
	наступить на него по дороге и случайно начать задание нельзя.
]]
Base.DAILY_LETTER_POSITION = Vector3.new(0, 0, -18)

--[[
	Доска-карта «Куда пойти?»: слева впереди от точки появления, между порталом
	мира букв и полукругом падов. Её видно сразу, но к порталу она не мешает.
]]
Base.MAP_BOARD_POSITION = Vector3.new(-25, 0, 13)

--[[
	Пад «Охота за секретами» — слева от портала мира букв: ведёт на самый ранний
	открытый уровень, где найдены не все три золотые буквы (Logic/Secrets).
]]
Base.SECRETS_PAD_POSITION = Vector3.new(-45, 0, -24)

Base.GROUND_SIZE = (Base.RING_RADIUS + Base.PLOT_SIZE) * 2

--[[
	Пады улучшений стоят в один ряд у калитки. Ширина и шаг подобраны так, чтобы
	весь ряд влезал в переднюю сторону участка: категорий стало шесть, и ряд
	по семь студов на пад вылез бы за забор. Держится тестом.
]]
Base.PAD_WIDTH = 5.4
Base.PAD_STEP = 6.2

--[[
	Где стоит участок с номером index. Чистая функция: расстановка кольца
	проверяется тестом, а не глазами в Studio.
]]
function Base.plotPosition(index: number): Vector3
	local angle = (index - 1) / Base.PLOT_COUNT * math.pi * 2
	return Vector3.new(math.cos(angle) * Base.RING_RADIUS, 0, math.sin(angle) * Base.RING_RADIUS)
end

-- Место одной постройки на участке: центр в координатах участка и радиус.
-- Ось −Z смотрит на площадь, калитка на z = −PLOT_SIZE / 2.
export type Spot = { x: number, z: number, r: number }

export type Category = {
	id: string,
	title: string,
	emoji: string,
	-- Цена перехода на уровень N лежит в prices[N]. Уровень 0 — пустой участок.
	prices: { number },
	levels: { string }, -- как называется каждый уровень, для подписи на паде
	--[[
		Для построек-наборов: где стоит вещь каждого уровня и где её пад.
		Пад стоит рядом с местом стройки, а не в ряду у калитки: ряд из десяти
		падов в участок не влезает, а купить грядку, стоя у грядки, понятнее.
	]]
	spots: { Spot }?,
	pad: Vector2?,
	--[[
		Формы на выбор (docs/15-HOME-BASE.md § 3.1): у забора — какие верхушки
		у столбиков, у крыши — какой она формы. Первая — та, что была всегда.
		Форма выбирается один раз на категорию и держится на всех её уровнях.
	]]
	shapes: { Shape }?,
	-- Перекрашивается ли категория. Двор — это трава и дорожки, красить там нечего.
	paintable: boolean?,
}

--[[
	icon — эмодзи на карточке выбора. picture — рисунок из рамок вместо эмодзи,
	когда подходящего эмодзи нет: столбик забора с верхушкой, окно (BuildPickerUI).

	У наборов форма — это другая вещь на том же месте: самокат вместо велосипеда,
	колесо обозрения вместо карусели. Тогда у формы свои названия и значки
	на каждый уровень (titles, icons): на карточке — та вещь, которую покупают
	сейчас, а на паде — её название, а не название вещи из другой формы.
]]
export type Shape = {
	title: string,
	icon: string,
	picture: string?,
	titles: { string }?,
	icons: { string }?,
}

-- Стиль категории: номер формы и номер краски (Base.PAINTS). Оба с единицы.
export type Style = { shape: number, paint: number }

--[[
	Десять категорий по четыре уровня. Цены из docs/15-HOME-BASE.md § 3.

	Первый уровень стоит 20–50 ⭐ — столько ребёнок зарабатывает в первый же день:
	первое строительство обязано случиться сразу, как и первая шапка.
	Полный дом стоит около 8500 ⭐ — это долгая цель, а не покупка на вечер.

	Четыре первые категории — сам дом: там уровень ЗАМЕНЯЕТ предыдущий, черепица
	встаёт вместо соломы. Две последние — мебель и декор двора, и они набираются:
	коврик не выбрасывает кровать. Набор не превращает двор в свалку — вещей
	всего восемь, у каждой своё место, и ставятся они по порядку, а не куда попало.
]]
local CATEGORIES: { Category } = {
	{
		id = "house",
		title = "Дом",
		emoji = "🏠",
		prices = { 50, 200, 500, 1000 },
		levels = { "Шалаш", "Домик", "Двухэтажный", "Башенка" },
		-- Форма дома — его окна: на всех четырёх уровнях, от сруба до башенки.
		shapes = {
			{ title = "Квадратные", icon = "", picture = "window_square" },
			{ title = "Круглые", icon = "", picture = "window_round" },
			{ title = "Арочные", icon = "", picture = "window_arch" },
		},
	},
	{
		id = "roof",
		title = "Крыша",
		emoji = "🔺",
		prices = { 40, 150, 400, 800 },
		levels = { "Солома", "Черепица", "Цветная", "Светящаяся" },
		shapes = {
			{ title = "Домиком", icon = "🏠" },
			{ title = "Шатром", icon = "⛺" },
			{ title = "Куполом", icon = "🍄" },
		},
	},
	{
		id = "yard",
		title = "Двор",
		emoji = "🌳",
		prices = { 30, 120, 300, 700 },
		levels = { "Трава", "Дорожка", "Сад", "Фонтан" },
	},
	{
		id = "fence",
		title = "Забор",
		emoji = "🚧",
		prices = { 25, 100, 250, 600 },
		levels = { "Колышки", "Штакетник", "Каменный", "Буквенный" },
		shapes = {
			{ title = "Ровный", icon = "", picture = "flat" },
			{ title = "Острый", icon = "", picture = "pointed" },
			{ title = "Круглый", icon = "", picture = "round" },
		},
	},
	--[[
		Мебель. Стоит на террасе перед домом, а не внутри: внутрь дома ребёнок
		не заходит — там нет ни одной причины быть, — а увидеть купленное он должен
		каждый раз, когда подбегает к своему участку.

		Без дома мебель не ставится: стол посреди пустого участка — это не уют,
		а недоразумение. Купленный уровень при этом не пропадает, он ждёт дом,
		ровно как крыша.
	]]
	{
		id = "furniture",
		title = "Мебель",
		emoji = "🪑",
		prices = { 30, 60, 90, 150 },
		levels = { "Стол", "Лавочка", "Коврик", "Полка" },
	},
	--[[
		Декор двора. Самое дешёвое начало во всём каталоге: флажки за 20 ⭐ —
		первая покупка, которую ребёнок может сделать в первые же минуты,
		и первое доказательство, что двор его.
	]]
	{
		id = "decor",
		title = "Декор",
		emoji = "🎈",
		prices = { 20, 50, 120, 200 },
		levels = { "Флажки", "Шарики", "Фонари", "Качели" },
	},
	--[[
		Четыре набора вокруг дома: огород, площадка, живность, транспорт.
		Как мебель и декор, они набираются, а не заменяются, и у каждой вещи
		своё место на участке. Места подобраны так, чтобы не задеть дом, комнаты,
		Башню, флаги, шпили и дорожку, — это держит тест, а не глаз.

		Первая вещь каждого набора стоит как первая шапка: ребёнок, у которого
		уже есть домик, выбирает, что дальше, — грядку, песочницу или будку.
	]]
	{
		id = "garden",
		title = "Огород",
		emoji = "🥕",
		prices = { 25, 60, 110, 220 },
		levels = { "Грядка", "Подсолнухи", "Тыквы", "Яблоня" },
		-- Вторая форма — вещи из Creator Store (BaseService.STORE_SHAPES), как и третьи у наборов ниже.
		shapes = {
			{ title = "Огород", icon = "🥕" },
			{
				title = "Цветник",
				icon = "🌷",
				titles = {
					"Клумба",
					"Грибочки",
					"Пугало",
					"Цветущее дерево",
				},
				icons = { "🌷", "🍄", "🎃", "🌸" },
			},
		},
		-- Вдоль левого забора, от калитки к Башне.
		spots = {
			{ x = -23, z = -11, r = 3.5 },
			{ x = -23, z = -4, r = 3 },
			{ x = -23, z = 2, r = 2.5 },
			{ x = -23, z = 8.5, r = 3.5 },
		},
		pad = Vector2.new(-15, -5),
	},
	{
		id = "playground",
		title = "Площадка",
		emoji = "🛝",
		prices = { 35, 80, 160, 300 },
		levels = { "Песочница", "Горка", "Батут", "Карусель" },
		shapes = {
			{
				title = "Песочница",
				icon = "🏖️",
				titles = { "Песочница", "Горка", "Батут", "Карусель" },
				icons = { "🏖️", "🛝", "🤸", "🎠" },
			},
			{
				title = "Шалаш",
				icon = "⛺",
				titles = { "Шалаш", "Лазалка", "Бассейн", "Колесо" },
				icons = { "⛺", "🧗", "🏊", "🎡" },
			},
			{
				title = "Качели",
				icon = "🏰",
				titles = {
					"Качели",
					"Надувной замок",
					"Замок из песка",
					"Крутилка",
				},
				icons = { "🌳", "🏰", "🏖️", "🎠" },
			},
		},
		-- За домом слева; карусели там тесно, она встаёт у калитки.
		spots = {
			{ x = -9, z = 25, r = 3.5 },
			{ x = -22, z = 25, r = 6.5 },
			{ x = -1, z = 25, r = 3 },
			{ x = -23, z = -20, r = 3.5 },
		},
		pad = Vector2.new(-24, 15),
	},
	{
		id = "pets",
		title = "Живность",
		emoji = "🐶",
		prices = { 40, 90, 180, 350 },
		levels = { "Будка", "Курятник", "Пруд с утками", "Пони" },
		shapes = {
			{ title = "Живые", icon = "🐶" },
			{
				title = "Игрушки",
				icon = "🧸",
				titles = {
					"Домик-будка",
					"Плюшевый мишка",
					"Уточка",
					"Динозаврик",
				},
				icons = { "🏠", "🧸", "🦆", "🦖" },
			},
		},
		-- За домом справа: будка, курятник, пруд и пони у заднего забора.
		spots = {
			{ x = 6, z = 26, r = 2.5 },
			{ x = 12.5, z = 26, r = 3.5 },
			{ x = 20, z = 22.5, r = 3 },
			{ x = 19.5, z = 28.5, r = 2 },
		},
		pad = Vector2.new(17, 15),
	},
	{
		id = "transport",
		title = "Транспорт",
		emoji = "🚲",
		prices = { 50, 120, 250, 500 },
		levels = { "Велосипед", "Машинка", "Воздушный шар", "Ракета" },
		shapes = {
			{
				title = "Велосипед",
				icon = "🚲",
				titles = {
					"Велосипед",
					"Машинка",
					"Воздушный шар",
					"Ракета",
				},
				icons = { "🚲", "🚗", "🎈", "🚀" },
			},
			{
				title = "Самокат",
				icon = "🛴",
				titles = { "Самокат", "Грузовичок", "Самолётик", "Тарелка" },
				icons = { "🛴", "🚚", "🛩️", "🛸" },
			},
			{
				title = "Игрушечный",
				icon = "🚂",
				titles = { "Машинка", "Паровозик", "Самолёт", "Ракета" },
				icons = { "🚗", "🚂", "✈️", "🚀" },
			},
		},
		-- Вдоль правого забора: от велосипеда у калитки до ракеты у дома.
		spots = {
			{ x = 23, z = -21, r = 2.5 },
			{ x = 23, z = -13, r = 4 },
			{ x = 23, z = -3, r = 3 },
			{ x = 23, z = 6, r = 3 },
		},
		pad = Vector2.new(15, -17),
	},
}

for _, category in CATEGORIES do
	if category.paintable == nil then
		category.paintable = category.id ~= "yard"
	end
end

Base.CATEGORIES = CATEGORIES

--[[
	Краски построек (docs/15-HOME-BASE.md § 3.1). Первая — «как задумано»:
	постройка своих цветов. Остальные перекрашивают главный цвет постройки —
	стены дома, доски забора, кузов машинки. Бесплатно и сколько угодно раз:
	это не покупка, а «мой дом такого цвета».
]]
export type Paint = { title: string, color: Color3? }

Base.PAINTS = {
	{ title = "Как задумано", color = nil },
	{ title = "Красный", color = Color3.fromRGB(235, 95, 90) },
	{ title = "Оранжевый", color = Color3.fromRGB(245, 160, 70) },
	{ title = "Жёлтый", color = Color3.fromRGB(250, 215, 85) },
	{ title = "Зелёный", color = Color3.fromRGB(115, 200, 120) },
	{ title = "Голубой", color = Color3.fromRGB(105, 175, 235) },
	{ title = "Фиолетовый", color = Color3.fromRGB(170, 125, 225) },
	{ title = "Розовый", color = Color3.fromRGB(245, 155, 200) },
} :: { Paint }

local byId: { [string]: Category } = {}
for _, category in CATEGORIES do
	assert(byId[category.id] == nil, `Base: дубликат категории {category.id}`)
	assert(
		#category.prices == #category.levels,
		`Base: у категории {category.id} цены и уровни не совпадают`
	)
	assert(
		category.spots == nil or #category.spots == #category.levels,
		`Base: у категории {category.id} мест не столько, сколько уровней`
	)
	for index, shape in category.shapes or {} do
		assert(
			(shape.titles == nil or #shape.titles == #category.levels)
				and (shape.icons == nil or #shape.icons == #category.levels),
			`Base: у формы {index} категории {category.id} подписей не столько, сколько уровней`
		)
	end
	byId[category.id] = category
end

function Base.get(id: string): Category?
	return byId[id]
end

function Base.expect(id: string): Category
	local category = byId[id]
	assert(category, `Base: неизвестная категория "{id}"`)
	return category
end

function Base.ids(): { string }
	local ids: { string } = {}
	for _, category in CATEGORIES do
		table.insert(ids, category.id)
	end
	return ids
end

-- Категории, чьи пады стоят в ряду у калитки: у наборов пад стоит у своего места.
function Base.rowIds(): { string }
	local ids: { string } = {}
	for _, category in CATEGORIES do
		if not category.pad then
			table.insert(ids, category.id)
		end
	end
	return ids
end

function Base.maxLevel(id: string): number
	return #Base.expect(id).prices
end

--[[
	Сколько стоит подняться с текущего уровня на следующий.
	nil означает «выше некуда»: категория достроена.
]]
function Base.priceFor(id: string, currentLevel: number): number?
	local category = Base.expect(id)
	local next_ = currentLevel + 1
	if next_ < 1 or next_ > #category.prices then
		return nil
	end
	return category.prices[next_]
end

--[[
	Название следующего уровня — для подписи на паде: ребёнок видит, что он покупает.
	shape — выбранная форма: у наборов она меняет саму вещь, а с ней и название.
]]
function Base.nextTitle(id: string, currentLevel: number, shape: number?): string?
	local category = Base.expect(id)
	local next_ = currentLevel + 1
	if next_ < 1 or next_ > #category.levels then
		return nil
	end
	local chosen = category.shapes and category.shapes[shape or 1]
	return if chosen and chosen.titles then chosen.titles[next_] else category.levels[next_]
end

-- Значок формы на карточке выбора: у наборов — вещь того уровня, что покупают сейчас.
function Base.shapeIcon(shape: Shape, level: number): string
	return if shape.icons then shape.icons[math.clamp(level, 1, #shape.icons)] else shape.icon
end

--[[
	Пустой участок: все категории на нуле.

	Ноль — это не «сломанный профиль», а честное начало: у ребёнка, который
	только зашёл, дома ещё нет, есть место под него.
]]
function Base.newProgress(): { [string]: number }
	local progress: { [string]: number } = {}
	for _, category in CATEGORIES do
		progress[category.id] = 0
	end
	return progress
end

--[[
	Приводит блок построек к допустимым значениям: чужие ключи, дробные уровни
	и уровни выше построенного нами выбрасываются.

	Профиль приходит из DataStore, а не из наших рук: он мог быть сохранён старым
	билдом, в котором уровней было больше. Уронить на этом вход в игру нельзя.
]]
function Base.sanitize(progress: any): { [string]: number }
	local clean = Base.newProgress()
	if typeof(progress) ~= "table" then
		return clean
	end

	for _, category in CATEGORIES do
		local level = progress[category.id]
		if typeof(level) == "number" and level == level then
			clean[category.id] = math.clamp(math.floor(level), 0, #category.prices)
		end
	end

	return clean
end

function Base.shapeCount(id: string): number
	local shapes = Base.expect(id).shapes
	return if shapes then #shapes else 1
end

function Base.paintColor(index: number): Color3?
	local paint = Base.PAINTS[index]
	return if paint then paint.color else nil
end

--[[
	Стили всех категорий: у каждой форма и краска, по умолчанию первые.
	Как и уровни, стиль приходит из DataStore: чужие ключи, дроби и номера
	за пределами списка приводятся к допустимым, вход в игру на них не падает.
]]
function Base.sanitizeStyle(raw: any): { [string]: Style }
	local clean: { [string]: Style } = {}
	for _, category in CATEGORIES do
		local entry = if typeof(raw) == "table" then raw[category.id] else nil
		local shape, paint = 1, 1
		if typeof(entry) == "table" then
			if typeof(entry.shape) == "number" and entry.shape == entry.shape then
				shape = math.clamp(math.floor(entry.shape), 1, Base.shapeCount(category.id))
			end
			if typeof(entry.paint) == "number" and entry.paint == entry.paint and category.paintable then
				paint = math.clamp(math.floor(entry.paint), 1, #Base.PAINTS)
			end
		end
		clean[category.id] = { shape = shape, paint = paint }
	end
	return clean
end

-- Сколько стоит весь участок целиком: цифра из доки, которую держит тест.
function Base.totalPrice(): number
	local total = 0
	for _, category in CATEGORIES do
		for _, price in category.prices do
			total += price
		end
	end
	return total
end

return Base
