--!strict
--[[
	Первые минуты новичка: куда вести ребёнка, пока он ещё ничего здесь не знает.
	См. docs/01-GDD.md § 6 и docs/08-UX-UI.md § 7.

	Никаких обучающих текстов: голос и стрелка, по одному действию за раз.
	Шагов три, и каждый — полный круг «поучился → получил»:

	  1. catch — Буквопад: первая буква, знакомство с ней, первые звёздочки;
	  2. shop  — магазин: звёздочки превращаются в шапку на голове;
	  3. run   — портал мира букв: первый уровень, ворота с А, Б и В.

	После первого уровня — прогулка по парку (docs/17-CONTENT-PLAN.md § 7.3):
	стрелка ведёт мимо трёх мест — паркур-горы, карусели и рыбалки. Шаг
	засчитывается, когда ребёнок дошёл до места. На проверке 24.09.2026
	взрослый, пройдя площадь, парка просто не нашёл; новичок теперь увидит
	его в первые же минуты.

	Состояние — набор сделанных шагов, а не номер текущего. Ребёнок не обязан
	идти по порядку: побежал сначала в портал — шаг «run» засчитан, и стрелка
	покажет на то, что осталось. С номером шага он застрял бы на первом,
	сделав уже всё остальное.

	Чистая логика без Roblox API — покрыта тестами.
]]

local Tutorial = {}

export type Step = {
	id: string,
	-- Куда показывает стрелка: имя детали в workspace.Hub (её строит WorldService).
	target: string,
	-- Что говорит голос, когда шаг становится текущим. Только уже записанные реплики.
	vo: string?,
}

Tutorial.STEPS = {
	{ id = "catch", target = "Pad_letter_rain", vo = "story_intro" },
	{ id = "shop", target = "ShopPad", vo = "ui_shop" },
	{ id = "run", target = "Portal_letters", vo = nil },
	-- Прогулка: цель "spot:<id>" — место парка (Config/Playground), стрелку ставит клиент.
	{ id = "walk_obby", target = "spot:obby", vo = nil },
	{ id = "walk_carousel", target = "spot:carousel", vo = nil },
	{ id = "walk_pond", target = "spot:pond", vo = nil },
} :: { Step }

-- Шаги прогулки: миграция отмечает их сделанными у тех, кто прошёл обучение до неё.
Tutorial.WALK = { "walk_obby", "walk_carousel", "walk_pond" }

local byId: { [string]: Step } = {}
for _, step in Tutorial.STEPS do
	byId[step.id] = step
end

-- Какое событие игры закрывает какой шаг.
Tutorial.EVENTS = {
	letter_rain = "catch",
	purchase = "shop",
	tunnel_run = "run",
	-- Дошёл до места парка (TutorialService смотрит, где стоит ребёнок).
	["arrive:obby"] = "walk_obby",
	["arrive:carousel"] = "walk_carousel",
	["arrive:pond"] = "walk_pond",
} :: { [string]: string }

export type State = { [string]: boolean }

-- Из DataStore может прийти что угодно: оставляем только известные шаги со значением true.
function Tutorial.sanitize(raw: any): State
	local clean: State = {}
	if typeof(raw) ~= "table" then
		return clean
	end
	for _, step in Tutorial.STEPS do
		if raw[step.id] == true then
			clean[step.id] = true
		end
	end
	return clean
end

-- Первый несделанный шаг по порядку. nil — обучение пройдено.
function Tutorial.current(state: State): Step?
	for _, step in Tutorial.STEPS do
		if not state[step.id] then
			return step
		end
	end
	return nil
end

function Tutorial.isDone(state: State): boolean
	return Tutorial.current(state) == nil
end

function Tutorial.isFresh(state: State): boolean
	return next(state) == nil
end

--[[
	Отмечает событие игры. Возвращает шаг, который оно закрыло, или nil,
	если событие к обучению отношения не имеет или шаг уже был сделан.
]]
function Tutorial.complete(state: State, event: string): string?
	local stepId = Tutorial.EVENTS[event]
	if stepId == nil or state[stepId] then
		return nil
	end
	state[stepId] = true
	return stepId
end

-- Всё отмечено сделанным: для тех, кто уже играл, и для «пропустить» из родительского режима.
function Tutorial.finished(): State
	local state: State = {}
	for _, step in Tutorial.STEPS do
		state[step.id] = true
	end
	return state
end

function Tutorial.get(id: string): Step?
	return byId[id]
end

--[[
	Играл ли этот профиль до появления обучения. Такого ребёнка не водим
	за руку к паду, на котором он уже был: признак — любые звёздочки, буквы
	или вещи. Нужен миграции, которая заводит обучение старым профилям.
]]
function Tutorial.hasPlayed(profile: any): boolean
	if typeof(profile) ~= "table" then
		return false
	end
	if typeof(profile.stars) == "number" and profile.stars > 0 then
		return true
	end
	if typeof(profile.letters) == "table" and next(profile.letters) ~= nil then
		return true
	end
	if typeof(profile.inventory) == "table" and #profile.inventory > 0 then
		return true
	end
	return false
end

return Tutorial
