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
Base.PLOT_SIZE = 40 -- сторона участка; фиксирована, чтобы не было гонки «у кого больше»
Base.PLOT_GAP = 12 -- парк между участками: дорожки, деревья, лавки

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
Base.PAD_DISTANCE = 42
Base.PAD_SLOTS = 7
local PAD_ARC_FROM = 0.08
local PAD_ARC_SPAN = 0.84

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

export type Category = {
	id: string,
	title: string,
	emoji: string,
	-- Цена перехода на уровень N лежит в prices[N]. Уровень 0 — пустой участок.
	prices: { number },
	levels: { string }, -- как называется каждый уровень, для подписи на паде
}

--[[
	Шесть категорий по четыре уровня. Цены из docs/15-HOME-BASE.md § 3.

	Первый уровень стоит 20–50 ⭐ — столько ребёнок зарабатывает в первый же день:
	первое строительство обязано случиться сразу, как и первая шапка.
	Полный дом стоит около 6000 ⭐ — это долгая цель, а не покупка на вечер.

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
	},
	{
		id = "roof",
		title = "Крыша",
		emoji = "🔺",
		prices = { 40, 150, 400, 800 },
		levels = { "Солома", "Черепица", "Цветная", "Светящаяся" },
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
		levels = { "Стол", "Кровать", "Коврик", "Полка" },
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
		levels = { "Флажки", "Шарики", "Фонарики", "Качели" },
	},
}

Base.CATEGORIES = CATEGORIES

local byId: { [string]: Category } = {}
for _, category in CATEGORIES do
	assert(byId[category.id] == nil, `Base: дубликат категории {category.id}`)
	assert(
		#category.prices == #category.levels,
		`Base: у категории {category.id} цены и уровни не совпадают`
	)
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

-- Название следующего уровня — для подписи на паде: ребёнок видит, что он покупает.
function Base.nextTitle(id: string, currentLevel: number): string?
	local category = Base.expect(id)
	local next_ = currentLevel + 1
	if next_ < 1 or next_ > #category.levels then
		return nil
	end
	return category.levels[next_]
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
