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
	--[[
		С седьмого уровня новых аттракционов не было: самый новый встаёт первым,
		и дальние уровни встречали ребёнка уже знакомым. Теперь каждый из трёх
		последних открывает своё — батуты, печеньки, топотунов.
	]]
	{ id = "bounce", title = "Батуты", fromLevel = 7, seconds = 8, floor = false },
	{ id = "cookies", title = "Печеньки", fromLevel = 8, seconds = 7, floor = false },
	{ id = "stompers", title = "Кубики-топотуны", fromLevel = 9, seconds = 9, floor = true },
	--[[
		На десятом и одиннадцатом уровнях нового не было — ребёнок, дошедший
		так далеко, встречал только знакомое. Теперь десятый открывает ветер.
	]]
	{ id = "wind", title = "Ветродуи", fromLevel = 10, seconds = 9, floor = false },
	-- Последний, одиннадцатый уровень тоже встречает новым: подъёмники на шариках.
	{ id = "lifts", title = "Подъёмники", fromLevel = 11, seconds = 10, floor = false },
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
	--[[
		Батуты: над пропастью чередуются батут внизу и высокий островок.
		Батут подбрасывает выше обычного прыжка — только с него и попадёшь
		на островок, а с островка спрыгиваешь на следующий батут. Промахнулся
		мимо батута — вниз, к флажку. С жара 3 батуты ездят поперёк трассы.
	]]
	bounce = {
		pairs = { 3, 3, 4, 4, 5 }, -- сколько раз «батут — островок»
		pad = { 8, 7, 6.5, 6, 5.5 }, -- поперечник батута
		island = { 8, 7, 6.5, 6, 5.5 }, -- поперечник островка
		gap = { 2.5, 3, 3.5, 4, 4.5 }, -- по горизонтали от края до края
		height = { 7, 8, 9, 10, 10.5 }, -- на сколько островок выше пола трассы
		travel = { 0, 0, 3, 4, 5 }, -- на сколько батут уезжает вбок от своей дорожки
		period = { 6, 6, 5.5, 5, 4.5 }, -- полный ход батута туда и обратно
	},
	--[[
		Печеньки: дорожка из круглых печенек над пропастью. Наступил — печенька
		трещит и через миг крошится вниз, а потом вырастает снова. Стоять
		нельзя: только бежать и прыгать дальше. Чем жарче, тем быстрее крошатся
		и тем больше дырок между ними.
	]]
	cookies = {
		rows = { 5, 6, 7, 7, 8 },
		size = { 7, 6.5, 6, 5.5, 5 }, -- поперечник печеньки
		gap = { 1.5, 2, 2.5, 3, 3.5 }, -- щель между рядами
		hold = { 1.2, 1, 0.85, 0.7, 0.6 }, -- сколько печенька держит, когда на неё встали
		missing = { 0, 1, 1, 2, 2 }, -- печенек из трёх, которых в ряду нет вовсе
	},
	--[[
		Кубики-топотуны: над полом висят огромные игрушечные кубики с буквами,
		по кубику над каждой дорожкой, и по очереди топают вниз. Перед топотом
		кубик краснеет и дрожит, тень под ним темнеет. Попался — к флажку.
		В каждом ряду всегда хотя бы один кубик наверху: стоять под ним можно.
	]]
	stompers = {
		rows = { 3, 4, 4, 5, 5 },
		period = { 4.2, 3.9, 3.6, 3.3, 3 }, -- полный цикл кубика
		down = { 1.2, 1.3, 1.4, 1.5, 1.6 }, -- из них внизу (с падением и подъёмом)
	},
	--[[
		Ветродуи: узкий мостик над пропастью, сбоку висят тучки с лицами.
		Тучка надувает щёки — и дует поперёк мостика, сдувая в пропасть.
		Переждать порыв можно за щитом, который стоит посреди каждого участка,
		или упираться: ветер слабее бега, и против него устоишь, если не зевать.
		Соседние тучки висят по разные стороны — дует то вправо, то влево.
	]]
	wind = {
		zones = { 2, 3, 3, 4, 4 }, -- сколько тучек, у каждой свой участок мостика
		bridge = { 9, 8, 7, 6, 5.5 }, -- ширина мостика
		gap = { 0, 0, 2.5, 3, 3.5 }, -- щель между участками: прыгать приходится под ветром
		speed = { 9, 10.5, 12, 13.5, 15 }, -- как быстро сдувает вбок, студов в секунду
		gust = { 1.4, 1.6, 1.8, 2, 2.2 }, -- сколько дует порыв
		period = { 5.2, 5, 4.8, 4.6, 4.4 }, -- полный цикл тучки: тихо, щёки, порыв
	},
	--[[
		Подъёмники: над пропастью платформы на воздушных шариках ездят вверх-вниз,
		и каждая следующая висит выше прошлой. Прыгать, когда соседняя опустилась
		к тебе: подождёшь — уедет вверх, не допрыгнешь. С последней — на балкон
		высоко над трассой, а с балкона вниз по радужной горке.
	]]
	lifts = {
		count = { 3, 3, 4, 4, 5 },
		size = { 8, 7.5, 7, 6.5, 6 }, -- поперечник платформы
		gap = { 2.5, 3, 3.5, 4, 4.5 }, -- от края до края соседних платформ
		rise = { 2, 2.5, 3, 3, 3.5 }, -- на сколько середина хода следующей выше прошлой
		travel = { 3, 3.5, 4, 4.5, 5 }, -- на сколько платформа уходит вверх и вниз от середины
		period = { 6, 5.6, 5.2, 4.8, 4.4 }, -- полный ход вверх и обратно
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

Attractions.GRAVITY = 196.2 -- workspace.Gravity по умолчанию: проект её не меняет
Attractions.BOUNCE_PAD_Y = -1.5 -- верх батута ниже пола трассы: он стоит в пропасти
Attractions.BOUNCE_CLEAR = 3.5 -- на сколько ноги взлетают выше островка

-- Толчок батута, после которого ноги поднимаются на rise студов.
function Attractions.bouncePower(rise: number): number
	return math.sqrt(2 * Attractions.GRAVITY * rise)
end

Attractions.COOKIE_FALL = 0.45 -- за сколько секунд раскрошенная печенька уходит вниз
Attractions.COOKIE_BACK = 2.5 -- через сколько после этого вырастает снова

Attractions.STOMPER_SIZE = 8 -- сторона кубика: почти во всю дорожку
Attractions.STOMPER_GAP = 4.5 -- полоса пола между рядами: там можно переждать
Attractions.STOMPER_LIFT = 10 -- на сколько низ поднятого кубика выше пола
Attractions.STOMPER_WARN = 0.55 -- сколько кубик дрожит и краснеет перед топотом
Attractions.STOMPER_FALL = 0.15 -- падение
Attractions.STOMPER_RISE = 0.6 -- подъём обратно

--[[
	Где кубик в момент s своего цикла: 0 — наверху, 1 — стоит на полу.
	Цикл: наверху, в конце — дрожь; топот; стоит; медленно поднимается.
	Одна функция на клиента, который двигает кубик, и на тест, который
	проверяет, что в каждом ряду есть где переждать.
]]
function Attractions.stomperDrop(s: number, period: number, down: number): number
	s = s % period
	local fallAt = period - down
	if s < fallAt then
		return 0
	end
	local t = s - fallAt
	if t < Attractions.STOMPER_FALL then
		return t / Attractions.STOMPER_FALL
	end
	local riseAt = down - Attractions.STOMPER_RISE
	if t < riseAt then
		return 1
	end
	return 1 - (t - riseAt) / Attractions.STOMPER_RISE
end

-- Дрожит ли кубик перед топотом: по этому ребёнок узнаёт, что пора уходить.
function Attractions.stomperWarning(s: number, period: number, down: number): boolean
	s = s % period
	local fallAt = period - down
	return s >= fallAt - Attractions.STOMPER_WARN and s < fallAt
end

Attractions.WIND_ZONE = 16 -- длина участка одной тучки вдоль бега
Attractions.WIND_WARN = 1 -- столько тучка надувает щёки перед порывом
Attractions.WIND_RAMP = 0.2 -- порыв набирает силу и стихает за столько секунд
Attractions.WIND_SHELTER = 4.5 -- длина щита вдоль бега: за ним ветра нет
Attractions.WIND_SHELTER_HEIGHT = 6 -- выше головы: за щитом прячешься целиком
Attractions.WIND_CLOUD_Y = 8 -- на какой высоте над мостиком висит тучка

--[[
	Сила ветра тучки в момент s её цикла, от 0 до 1. Цикл: тихо, в конце —
	щёки надуваются (WIND_WARN), потом порыв длиной gust. Одна функция на
	клиента, который сдувает и рисует, и на тест, который ищет, когда
	пробежать от щита до щита.
]]
function Attractions.windGust(s: number, period: number, gust: number): number
	s = s % period
	local startAt = period - gust
	if s < startAt then
		return 0
	end
	local t = s - startAt
	local ramp = Attractions.WIND_RAMP
	return math.clamp(math.min(t / ramp, (gust - t) / ramp), 0, 1)
end

-- Надувает ли тучка щёки: через секунду подует.
function Attractions.windWarning(s: number, period: number, gust: number): boolean
	s = s % period
	local startAt = period - gust
	return s >= startAt - Attractions.WIND_WARN and s < startAt
end

Attractions.LIFT_SHIFT = 0.3 -- на какую долю хода соседняя платформа отстаёт от прошлой
Attractions.LIFT_BALCONY = 8 -- глубина балкона вдоль бега
Attractions.LIFT_SLOPE = 0.55 -- крутизна горки с балкона: подъём на студ длины
Attractions.LIFT_BALLOON = 11 -- на какой высоте над платформой висят шарики

-- Высота верха платформы над полом трассы в момент now.
function Attractions.liftHeight(
	mid: number,
	travel: number,
	period: number,
	phase: number,
	now: number
): number
	return mid + travel * math.sin(2 * math.pi * (now + phase) / period)
end

return Attractions
