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
Base.GROUND_SIZE = (Base.RING_RADIUS + Base.PLOT_SIZE) * 2

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
	Четыре категории по четыре уровня. Цены из docs/15-HOME-BASE.md § 3.

	Первый уровень стоит 25–50 ⭐ — столько ребёнок зарабатывает в первый же день:
	первое строительство обязано случиться сразу, как и первая шапка.
	Полный дом стоит около 6000 ⭐ — это долгая цель, а не покупка на вечер.
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
