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
	это главное занятие игры. Два других — из остального, по сиду дня, так что
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
		"chest" — ближайший ненайденный сундук. nil — дороги нет, дело везде.
	]]
	target: string?,
	-- true — главное задание дня: уровень одного из миров.
	main: boolean?,
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
} :: { Quest }

local byId: { [string]: Quest } = {}
for _, quest in Quests.POOL do
	byId[quest.id] = quest
end

function Quests.get(id: any): Quest?
	return if typeof(id) == "string" then byId[id] else nil
end

export type State = {
	day: number,
	list: { string }, -- задания сегодняшнего дня по порядку
	progress: { [string]: number },
	played: { string }, -- разные занятия, законченные сегодня (для «трёх разных»)
	bonus: boolean, -- бонус за все три уже выдан
}

function Quests.new(): State
	return { day = 0, list = {}, progress = {}, played = {}, bonus = false }
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
	local others: { string } = {}
	for _, quest in Quests.POOL do
		if table.find(available, quest.id) then
			table.insert(if quest.main then mains else others, quest.id)
		end
	end

	local list: { string } = {}
	if #mains > 0 then
		table.insert(list, mains[day % #mains + 1])
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

-- Новый день — новые задания; тот же день — всё как было.
function Quests.refresh(state: State, day: number, available: { string }): (State, boolean)
	local clean = Quests.sanitize(state)
	if clean.day == day and #clean.list > 0 then
		return clean, false
	end
	local fresh = Quests.new()
	fresh.day = day
	fresh.list = Quests.pick(day, available)
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

return Quests
