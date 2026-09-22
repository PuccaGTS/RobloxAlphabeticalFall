--!strict
--[[
	Аттракционы забега: большие участки во всю ширину трассы, на которых можно
	по-настоящему упасть или попасться. См. docs/19-OBSTACLES.md § 3.4.

	Мелкие элементы (барьер, яма, мостик) обходятся соседней дорожкой, и на первой
	живой проверке их назвали «вообще не вызывают трудностей». Аттракцион обойти
	нельзя: он занимает всю трассу, и пройти его можно только ловкостью —
	перепрыгать островки, спрятаться от валуна в нише, переждать молот.

	Правило «падение стоит секунд, а не прогресса» остаётся: перед каждым
	аттракционом стоит флажок, и упавший или сбитый возвращается к нему, а не
	к воротам. Звёздочки, буквы и постройки не отнимаются никогда.

	Жар (heat) — сила аттракциона от 1 до 5: шире прыжки, быстрее валуны.
	Его задаёт уровень пути (Config/Levels.heat), а не адаптивная сложность:
	уровень мира должен ощущаться одинаково в каждый заход.
]]

export type Attraction = {
	id: string,
	title: string,
	-- С какого уровня пути аттракцион встречается. До этого его нет вовсе.
	fromLevel: number,
	--[[
		Сколько секунд аттракцион отнимает сверх пробега своей длины: примериться,
		переждать валун, дождаться, пока молот уйдёт. Оценка для раскладки, как
		Tunnel.SECONDS у мелких элементов.
	]]
	seconds: number,
	-- Есть ли под аттракционом обычный пол. Где его нет, падать есть куда.
	floor: boolean,
}

local Attractions = {}

--[[
	Прыжок персонажа: JumpPower 55 при обычной гравитации поднимает на 7,7 студа
	и держит в воздухе больше полсекунды, за которые на скорости 20 он пролетает
	около одиннадцати студов. Самая широкая щель ниже этого с запасом: прыжок
	должен быть трудным для пятилетки, а не невозможным.
]]
Attractions.MAX_GAP = 7.5
Attractions.MAX_RISE = 3 -- на сколько следующая кочка может быть выше предыдущей

Attractions.FLAG_LEAD = 5 -- флажок стоит на полу перед аттракционом, в стольких студах от его начала
Attractions.EXIT = 6 -- ровный пол после аттракциона: отдышаться до следующего

local CATALOG: { Attraction } = {
	{ id = "islands", title = "Островки", fromLevel = 1, seconds = 6, floor = false },
	{ id = "spinner", title = "Вертушка", fromLevel = 1, seconds = 4, floor = true },
	{ id = "boulders", title = "Валуны", fromLevel = 2, seconds = 8, floor = true },
	{ id = "belts", title = "Ленты", fromLevel = 2, seconds = 8, floor = false },
	{ id = "clouds", title = "Облачка", fromLevel = 3, seconds = 9, floor = false },
	{ id = "lava", title = "Лавовые кочки", fromLevel = 4, seconds = 8, floor = false },
	{ id = "swings", title = "Качели", fromLevel = 5, seconds = 10, floor = false },
	{ id = "hammers", title = "Молоты", fromLevel = 6, seconds = 7, floor = false },
}

Attractions.CATALOG = CATALOG

local byId: { [string]: Attraction } = {}
for _, attraction in CATALOG do
	byId[attraction.id] = attraction
end

function Attractions.get(id: string): Attraction?
	return byId[id]
end

function Attractions.expect(id: string): Attraction
	local attraction = byId[id]
	assert(attraction, `Attractions: неизвестный аттракцион "{id}"`)
	return attraction
end

function Attractions.ids(): { string }
	local ids: { string } = {}
	for _, attraction in CATALOG do
		table.insert(ids, attraction.id)
	end
	return ids
end

-- Какие аттракционы открыты на этом уровне пути, по порядку появления.
function Attractions.unlocked(level: number): { string }
	local ids: { string } = {}
	for _, attraction in CATALOG do
		if attraction.fromLevel <= level then
			table.insert(ids, attraction.id)
		end
	end
	return ids
end

--[[
	Параметры по жару 1..5. Всё, что определяет трудность, записано здесь,
	и тест держит, что каждый список длиной ровно в пять.
]]
Attractions.HEAT = {
	islands = {
		size = { 9, 8, 7, 6, 5.5 }, -- диаметр островка
		gapMin = { 3, 3.5, 4, 4.5, 5 },
		gapMax = { 4, 5, 5.5, 6.5, 7 },
		rise = { 0, 0.8, 1.5, 2, 2.5 }, -- на сколько соседние островки расходятся по высоте
		count = { 5, 6, 6, 7, 8 },
	},
	spinner = {
		-- Оборот перекладины. Её надо перепрыгнуть, когда она проходит под ногами.
		period = { 7, 6.2, 5.5, 5, 4.5 },
		bars = { 1, 1, 2, 2, 2 },
	},
	boulders = {
		speed = { 11, 12, 13, 14, 15 }, -- медленнее бега: от валуна можно убежать к нише
		interval = { 6.5, 6, 5.4, 4.8, 4.3 },
	},
	lava = {
		rows = { 5, 6, 6, 7, 8 },
		gap = { 2.5, 3, 3.5, 4, 4.5 }, -- промежуток между кочками вдоль бега
		solid = { 4, 3.6, 3.2, 2.9, 2.6 }, -- сколько кочка стоит над лавой
		sunk = { 1.2, 1.4, 1.6, 1.8, 2 }, -- сколько она прячется
	},
	--[[
		Облачка: над пропастью ряды облаков катаются поперёк трассы. Прыгать
		с облака на облако надо в такт: соседние ряды качаются со сдвигом,
		и два облака сходятся напротив друг друга дважды за взмах.
	]]
	clouds = {
		size = { 9, 8.5, 8, 7.2, 6.5 }, -- поперечник облака
		gap = { 3, 3.5, 4, 4.5, 5 }, -- от края до края соседних рядов вдоль бега
		rows = { 4, 5, 5, 6, 7 },
		period = { 7, 6.5, 6, 5.5, 5 }, -- полный взмах туда и обратно
		travel = { 5, 6, 7, 7.5, 8 }, -- на сколько облако уходит от середины трассы
	},
	--[[
		Ленты: над пропастью лежат ленты транспортёра поперёк трассы, каждая
		тащит вбок — к обрыву слева или справа. Перебегать надо сразу, не стоя:
		кто задержался, того снесёт с края. В конце — длинная лента, которая
		везёт назад, к щели перед ней: против неё надо бежать без остановки.
	]]
	belts = {
		rows = { 3, 4, 4, 5, 6 },
		depth = { 6, 5.5, 5, 4.5, 4 }, -- ширина ленты вдоль бега
		span = { 18, 17, 16, 15, 14 }, -- длина ленты поперёк трассы: с её конца падают
		gap = { 2.5, 3, 3.5, 4, 4.5 }, -- щель между лентами
		speed = { 7, 9, 11, 12.5, 14 }, -- как быстро лента тащит вбок
		back = { 14, 16, 18, 20, 22 }, -- длина последней ленты, везущей назад
		backSpeed = { 5, 6, 7, 8, 9 }, -- её скорость: бег 16, вперёд идёшь, но медленнее
	},
	--[[
		Качели: доски на верёвках качаются вдоль трассы, соседние — навстречу
		друг другу. Когда две доски сходятся, между ними шаг; когда расходятся —
		пропасть. Прыгать в такт, на доске ехать.
	]]
	swings = {
		count = { 4, 4, 5, 5, 6 },
		board = { 7, 6.5, 6, 5.5, 5 }, -- сторона доски
		near = { 1.5, 2, 2.5, 3, 3.5 }, -- щель между досками, когда они сошлись
		period = { 4.6, 4.3, 4, 3.7, 3.4 }, -- полный взмах туда и обратно
		swing = { 0.36, 0.38, 0.4, 0.42, 0.44 }, -- размах в радианах
	},
	hammers = {
		period = { 4.6, 4.2, 3.8, 3.4, 3.1 }, -- полный взмах туда и обратно
		bridge = { 10, 9, 8, 7, 6.5 }, -- ширина мостика под молотами
	},
}

function Attractions.param(id: string, name: string, heat: number): number
	local block = (Attractions.HEAT :: any)[id]
	assert(block and block[name], `Attractions: нет параметра {id}.{name}`)
	local values = block[name]
	return values[math.clamp(math.floor(heat), 1, #values)]
end

-- Геометрия, общая для строителя и для раскладки.
Attractions.SPINNER_DIAMETER = 26
Attractions.SPINNER_BAR_HEIGHT = 1.2 -- по колено: перепрыгивается даже с места
Attractions.SPINNER_LENGTH = Attractions.SPINNER_DIAMETER + 2

Attractions.BOULDER_LENGTH = 64
Attractions.BOULDER_CORRIDOR = 12 -- ширина прохода между стенами: мимо валуна не проскочить
Attractions.BOULDER_DIAMETER = 10
Attractions.BOULDER_WALL_HEIGHT = 12
Attractions.NICHE_DEPTH = 5
Attractions.NICHE_LENGTH = 6
Attractions.NICHE_STEP = 14 -- ниша через каждые столько студов, по очереди слева и справа
Attractions.NICHE_FIRST = 9

Attractions.LAVA_STONE = 4.5 -- сторона кочки
Attractions.LAVA_COLUMN = 6 -- две колонки кочек: слева и справа от оси
Attractions.LAVA_WARN = 0.9 -- сколько кочка краснеет перед тем, как уйти в лаву
Attractions.LAVA_SINK = 4 -- на сколько кочка опускается

Attractions.BELT_BACK_WIDTH = 12 -- ширина последней ленты, везущей назад
Attractions.SWING_ROPE = 14 -- длина верёвки качелей от оси до доски

Attractions.HAMMER_LENGTH = 48
Attractions.HAMMER_COUNT = 3
Attractions.HAMMER_PIVOT = 17 -- высота оси над мостиком
Attractions.HAMMER_ARM = 14
Attractions.HAMMER_SWING = math.rad(65)
Attractions.HAMMER_HEAD = Vector3.new(3.5, 4, 4) -- вдоль бега, поперёк, вверх

return Attractions
