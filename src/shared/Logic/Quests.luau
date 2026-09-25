--!strict
--[[
	Задания дня: три дела на сутки, у каждого значок, счётчик и дорога к месту.

	Зачем. На проверке 24.09.2026: «прошёл все станции, пару раз пробежал полосу —
	всё, больше контента не нашёл, не понимаю, что куда и что делать дальше».
	В игре есть парк с сундуками, стебель до облаков, грот, мир чисел, дом —
	но ребёнок, который не читает, их не ищет. Задание называет одно дело,
	показывает дорогу стрелкой и платит звёздами — «куда идти» и «как заработать»
	решаются одним и тем же.

	Первое задание дня — всегда уровень пути (мир букв и мир чисел через день):
	это главное занятие игры. Второе — уголок парка, каждый день новый: так парк
	находится сам (docs/17-CONTENT-PLAN.md § 7.3). Третье — из остального
	(занятия площади, стройка, покупка, сундук). Всё по сиду дня, так что
	у всех детей на сервере сегодня одни и те же задания и им есть что обсудить.
	Задание, которое нельзя выполнить (все сундуки найдены, дом достроен),
	в выборку не попадает.

	Чистая логика без Roblox API — покрыта тестами. Награды — Config/Economy.
]]

local Quests = {}

export type Quest = {
	id: string,
	icon: string,
	title: string,
	-- Какое событие игры двигает счётчик: "challenge:<id>", "level:letters" и т. д.
	event: string,
	need: number,
	--[[
		Куда ведёт стрелка: имя детали в workspace.Hub (пады, порталы, магазин)
		или особая цель, которую знает только сервер: "home" — свой участок,
		"chest" — ближайший ненайденный сундук, "spot:<id>" — место парка
		(Config/Playground). nil — дороги нет, дело везде.
	]]
	target: string?,
	-- true — главное задание дня: уровень одного из миров.
	main: boolean?,
	-- true — задание про уголок парка: его выполняет само место (событие ParkDone).
	park: boolean?,
}

Quests.PER_DAY = 3

Quests.POOL = {
	{
		id = "letters_level",
		icon = "📖",
		title = "Пройди уровень в мире букв",
		event = "level:letters",
		need = 1,
		target = "Portal_letters",
		main = true,
	},
	{
		id = "math_level",
		icon = "🔢",
		title = "Пройди уровень в мире чисел",
		event = "level:math",
		need = 1,
		target = "Portal_math",
		main = true,
	},
	{
		id = "rain",
		icon = "🌧",
		title = "Поймай буквы в Буквопаде",
		event = "challenge:letter_rain",
		need = 1,
		target = "Pad_letter_rain",
	},
	{
		id = "bubbles",
		icon = "🫧",
		title = "Лопни пузыри с буквой",
		event = "challenge:bubbles",
		need = 1,
		target = "Pad_bubbles",
	},
	{
		id = "mirror",
		icon = "🪞",
		title = "Найди букву в зеркалах",
		event = "challenge:mirror",
		need = 1,
		target = "Pad_mirror",
	},
	{
		id = "lava",
		icon = "🌋",
		title = "Сыграй в «Пол — это лава!»",
		event = "challenge:lava_floor",
		need = 1,
		target = "Pad_lava_floor",
	},
	{
		id = "ladder",
		icon = "🪜",
		title = "Поднимись по лестнице букв",
		event = "challenge:alphabet_ladder",
		need = 1,
		target = "Pad_alphabet_ladder",
	},
	{
		id = "scales",
		icon = "⚖️",
		title = "Уравновесь весы",
		event = "challenge:scales",
		need = 1,
		target = "Pad_scales",
	},
	{
		id = "berries",
		icon = "🍓",
		title = "Собери ягоды в корзинку",
		event = "challenge:berries",
		need = 1,
		target = "Pad_berries",
	},
	{
		id = "three",
		icon = "🎯",
		title = "Сыграй в три разных занятия",
		event = "variety",
		need = 3,
	},
	{
		id = "build",
		icon = "🔨",
		title = "Построй что-нибудь у дома",
		event = "build",
		need = 1,
		target = "home",
	},
	{
		id = "buy",
		icon = "🛍",
		title = "Купи обновку в магазине",
		event = "purchase",
		need = 1,
		target = "ShopPad",
	},
	{
		id = "chest",
		icon = "🗝",
		title = "Найди сундук в парке",
		event = "chest",
		need = 1,
		target = "chest",
	},
	--[[
		Уголки парка. Их выполняет само место: сел на шар, дошёл по азбуке до Я,
		позвонил в кристалл, — клиент сообщает серверу (ParkDone), сервер
		проверяет, что ребёнок и правда стоит там (Services/QuestService).
	]]
	{
		id = "park_balloon",
		icon = "🎈",
		title = "Прокатись на воздушном шаре",
		event = "park:balloon",
		need = 1,
		target = "spot:balloon",
		park = true,
	},
	{
		id = "park_ferris",
		icon = "🎡",
		title = "Прокатись на колесе обозрения",
		event = "park:ferris",
		need = 1,
		target = "spot:ferris",
		park = true,
	},
	{
		id = "park_carousel",
		icon = "🎠",
		title = "Покатайся на карусели",
		event = "park:carousel",
		need = 1,
		target = "spot:carousel",
		park = true,
	},
	{
		id = "park_ship",
		icon = "🏴‍☠️",
		title = "Покачайся на корабле",
		event = "park:ship",
		need = 1,
		target = "spot:ship",
		park = true,
	},
	{
		id = "park_lake",
		icon = "🦢",
		title = "Проплыви по озеру на лебеде",
		event = "park:lake",
		need = 1,
		target = "spot:lake",
		park = true,
	},
	{
		id = "park_slide",
		icon = "🌀",
		title = "Скатись с горки-спирали",
		event = "park:slide",
		need = 1,
		target = "spot:slide",
		park = true,
	},
	{
		id = "park_abc",
		icon = "🔤",
		title = "Пройди азбуку-дорожку от А до Я",
		event = "park:abcpath",
		need = 1,
		target = "spot:abcpath",
		park = true,
	},
	{
		id = "park_photo",
		icon = "📸",
		title = "Сфотографируйся в фото-зоне",
		event = "park:photo",
		need = 1,
		target = "spot:photo",
		park = true,
	},
	{
		id = "park_beanstalk",
		icon = "🌱",
		title = "Заберись по стеблю до облаков",
		event = "park:beanstalk",
		need = 1,
		target = "spot:beanstalk",
		park = true,
	},
	{
		id = "park_grotto",
		icon = "💎",
		title = "Позвони в кристаллы грота",
		event = "park:grotto",
		need = 1,
		target = "spot:grotto",
		park = true,
	},
	{
		id = "park_zip",
		icon = "🌳",
		title = "Съедь на тарзанке с домика на дереве",
		event = "park:treehouse",
		need = 1,
		target = "spot:treehouse",
		park = true,
	},
	{
		id = "park_maze",
		icon = "🌿",
		title = "Найди флажок в лабиринте",
		event = "park:maze",
		need = 1,
		target = "spot:maze",
		park = true,
	},
	{
		id = "park_obby",
		icon = "🧗",
		title = "Позвони в колокол на паркур-горе",
		event = "park:obby",
		need = 1,
		target = "spot:obby",
		park = true,
	},
	{
		id = "park_skate",
		icon = "⛸",
		title = "Прокатись по катку",
		event = "park:winter",
		need = 1,
		target = "spot:winter",
		park = true,
	},
	{
		id = "park_pond",
		icon = "🎣",
		title = "Поймай три рыбки на рыбалке",
		event = "park:pond",
		need = 1,
		target = "spot:pond",
		park = true,
	},
	{
		id = "park_rental",
		icon = "🛴",
		title = "Прокатись на самокате или лошадке",
		event = "park:rental",
		need = 1,
		target = "spot:rental",
		park = true,
	},
} :: { Quest }

local byId: { [string]: Quest } = {}
for _, quest in Quests.POOL do
	byId[quest.id] = quest
end

function Quests.get(id: any): Quest?
	return if typeof(id) == "string" then byId[id] else nil
end

--[[
	Задание недели: одно большое дело на семь дней — «пройди 5 уровней»,
	«найди 3 секрета», «побывай в 5 уголках парка». Цель длиннее дня
	(docs/17-CONTENT-PLAN.md § 7.3), и награда за неё — вещь, которой нет
	в витрине: каждую неделю следующая из WEEK_REWARDS. Все собраны — звёзды.
	Живёт в том же поле профиля, что и задания дня: миграция не нужна.
]]
export type Weekly = {
	id: string,
	icon: string,
	title: string,
	-- "level" — уровень любого мира, "park" — разные уголки парка, остальное — как у дня.
	event: string,
	need: number,
}

Quests.WEEKLY = {
	{ id = "week_levels", icon = "🏁", title = "Пройди 5 уровней", event = "level", need = 5 },
	{
		id = "week_park",
		icon = "🎡",
		title = "Побывай в 5 уголках парка",
		event = "park",
		need = 5,
	},
	{
		id = "week_secrets",
		icon = "✨",
		title = "Найди 3 секрета в забеге",
		event = "secret",
		need = 3,
	},
	{
		id = "week_daily",
		icon = "📋",
		title = "Выполни 8 заданий дня",
		event = "daily_quest",
		need = 8,
	},
	{
		id = "week_play",
		icon = "🎯",
		title = "Сыграй 12 занятий",
		event = "finished",
		need = 12,
	},
} :: { Weekly }

-- Вещи за недели по порядку (Config/Shop, grantedBy = "weekly:<номер>").
Quests.WEEK_REWARDS = { "hat_dino", "back_bear", "hat_dragon", "hat_whaleshark", "hat_goldshark" }

export type Week = {
	week: number,
	id: string,
	have: number,
	seen: { string }, -- уголки парка, уже засчитанные на этой неделе
	done: boolean,
}

export type State = {
	day: number,
	list: { string }, -- задания сегодняшнего дня по порядку
	progress: { [string]: number },
	played: { string }, -- разные занятия, законченные сегодня (для «трёх разных»)
	bonus: boolean, -- бонус за все три уже выдан
	week: Week?,
}

function Quests.new(): State
	return { day = 0, list = {}, progress = {}, played = {}, bonus = false }
end

function Quests.weekOf(day: number): number
	return math.floor(day / 7)
end

function Quests.weekly(id: any): Weekly?
	for _, weekly in Quests.WEEKLY do
		if weekly.id == id then
			return weekly
		end
	end
	return nil
end

-- Задание недели week: по кругу, у всех детей одно и то же.
function Quests.weeklyFor(week: number): Weekly
	return Quests.WEEKLY[week % #Quests.WEEKLY + 1]
end

local function sanitizeWeek(raw: any): Week?
	if typeof(raw) ~= "table" or typeof(raw.week) ~= "number" or raw.week ~= raw.week then
		return nil
	end
	local weekly = Quests.weekly(raw.id)
	if not weekly then
		return nil
	end
	local have = if typeof(raw.have) == "number" and raw.have == raw.have then raw.have else 0
	local seen: { string } = {}
	if typeof(raw.seen) == "table" then
		for _, id in raw.seen do
			if typeof(id) == "string" and #id <= 32 and not table.find(seen, id) and #seen < 32 then
				table.insert(seen, id)
			end
		end
	end
	return {
		week = math.floor(raw.week),
		id = weekly.id,
		have = math.clamp(math.floor(have), 0, weekly.need),
		seen = seen,
		done = raw.done == true,
	}
end

local function isCount(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < 1000
end

function Quests.sanitize(raw: any): State
	if typeof(raw) ~= "table" then
		return Quests.new()
	end
	local state = Quests.new()
	state.day = if typeof(raw.day) == "number"
			and raw.day == raw.day
			and math.abs(raw.day) < math.huge
		then math.floor(raw.day)
		else 0
	if typeof(raw.list) == "table" then
		for _, id in raw.list do
			if Quests.get(id) and not table.find(state.list, id) and #state.list < Quests.PER_DAY then
				table.insert(state.list, id)
			end
		end
	end
	if typeof(raw.progress) == "table" then
		for id, count in raw.progress do
			local quest = Quests.get(id)
			if quest and isCount(count) then
				state.progress[id] = math.min(math.floor(count), quest.need)
			end
		end
	end
	if typeof(raw.played) == "table" then
		for _, id in raw.played do
			if typeof(id) == "string" and not table.find(state.played, id) and #state.played < 32 then
				table.insert(state.played, id)
			end
		end
	end
	state.bonus = raw.bonus == true
	state.week = sanitizeWeek(raw.week)
	return state
end

--[[
	Задания на день. available — какие из пула сейчас выполнимы (решает сервер).
	Первое — уровень пути: чётный день — мир букв, нечётный — мир чисел,
	а если один из миров недоступен, берётся другой.
]]
function Quests.pick(day: number, available: { string }): { string }
	local random = Random.new(day * 7919 + 17)
	local mains: { string } = {}
	local parks: { string } = {}
	local others: { string } = {}
	for _, quest in Quests.POOL do
		if table.find(available, quest.id) then
			local bucket = if quest.main then mains elseif quest.park then parks else others
			table.insert(bucket, quest.id)
		end
	end

	local list: { string } = {}
	if #mains > 0 then
		table.insert(list, mains[day % #mains + 1])
	end
	-- Уголки парка идут по кругу с шагом 7: соседние дни ведут в разные концы парка.
	if #parks > 0 then
		table.insert(list, parks[(day * 7) % #parks + 1])
	end
	for i = #others, 2, -1 do
		local j = random:NextInteger(1, i)
		others[i], others[j] = others[j], others[i]
	end
	for _, id in others do
		if #list >= Quests.PER_DAY then
			break
		end
		table.insert(list, id)
	end
	return list
end

-- Новый день — новые задания; тот же день — всё как было. Новая неделя — новое задание недели.
function Quests.refresh(state: State, day: number, available: { string }): (State, boolean)
	local clean = Quests.sanitize(state)
	local week = Quests.weekOf(day)
	local weekChanged = clean.week == nil or (clean.week :: Week).week ~= week
	if weekChanged then
		clean.week = { week = week, id = Quests.weeklyFor(week).id, have = 0, seen = {}, done = false }
	end
	if clean.day == day and #clean.list > 0 then
		return clean, weekChanged
	end
	local fresh = Quests.new()
	fresh.day = day
	fresh.list = Quests.pick(day, available)
	fresh.week = clean.week
	return fresh, true
end

function Quests.isDone(state: State, id: string): boolean
	local quest = Quests.get(id)
	return quest ~= nil and (state.progress[id] or 0) >= quest.need
end

function Quests.allDone(state: State): boolean
	if #state.list == 0 then
		return false
	end
	for _, id in state.list do
		if not Quests.isDone(state, id) then
			return false
		end
	end
	return true
end

--[[
	Событие игры. Возвращает новое состояние и задания, которые им только что
	выполнены (за них платят). detail — id законченного занятия у события
	"finished": оно двигает и «занятие такое-то», и «три разных».
]]
function Quests.record(state: State, event: string, detail: string?): (State, { string })
	local clean = Quests.sanitize(state)
	local events = { event }
	if event == "finished" and detail then
		events = { `challenge:{detail}` }
		if not table.find(clean.played, detail) then
			table.insert(clean.played, detail)
		end
	end

	local completed: { string } = {}
	for _, id in clean.list do
		local quest = byId[id]
		if Quests.isDone(clean, id) then
			continue
		end
		local have = clean.progress[id] or 0
		if quest.event == "variety" then
			have = math.min(#clean.played, quest.need)
		elseif table.find(events, quest.event) then
			have += 1
		else
			continue
		end
		clean.progress[id] = math.min(have, quest.need)
		if clean.progress[id] >= quest.need then
			table.insert(completed, id)
		end
	end
	return clean, completed
end

--[[
	То же событие — для задания недели. Отдельно от дня: сервер зовёт обе,
	а выполненные задания дня приходят сюда событием "daily_quest" по одному.
	Возвращает новое состояние и true, если неделя выполнена только что.
]]
function Quests.recordWeek(state: State, event: string): (State, boolean)
	local clean = Quests.sanitize(state)
	local week = clean.week
	if not week or week.done then
		return clean, false
	end
	local weekly = Quests.weekly(week.id) :: Weekly
	local counts = false
	if weekly.event == "level" then
		counts = string.sub(event, 1, 6) == "level:"
	elseif weekly.event == "park" then
		local spot = string.match(event, "^park:(.+)$")
		if spot and not table.find(week.seen, spot) then
			table.insert(week.seen, spot)
			counts = true
		end
	else
		counts = event == weekly.event
	end
	if not counts then
		return clean, false
	end
	week.have = math.min(week.have + 1, weekly.need)
	if week.have >= weekly.need then
		week.done = true
		return clean, true
	end
	return clean, false
end

-- Вещь за выполненную неделю: первая из WEEK_REWARDS, которой у ребёнка ещё нет.
function Quests.weekReward(inventory: { string }): string?
	for _, id in Quests.WEEK_REWARDS do
		if not table.find(inventory, id) then
			return id
		end
	end
	return nil
end

return Quests
