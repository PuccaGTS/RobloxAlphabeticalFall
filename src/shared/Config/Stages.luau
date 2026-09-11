--!strict
--[[
	Ступени алфавита: 11 групп по 3 буквы, строго в алфавитном порядке А → Я.
	Раньше на этом месте были 8 «островов», собранных по звукам (гласные, шипящие,
	взрывные). Звуки мы больше не учим, и группировать по ним стало нечем:
	ступень — это просто следующие три буквы азбуки. См. docs/02-LEARNING.md § 2.

	Три буквы — не круглое число ради красоты: столько ребёнок 4–7 лет удерживает
	в одном заходе, и ровно столько нужно, чтобы ворота могли предложить выбор
	из трёх вариантов, не подмешивая букв с других ступеней.
]]

local Types = require(script.Parent.Parent.Types)
local Letters = require(script.Parent.Letters)

-- Музыкальных тем три, ступеней одиннадцать: темы идут по кругу.
-- Меняется тема — меняется ощущение места, и переход на новую ступень слышно.
local THEMES = { "mus_theme_1", "mus_theme_2", "mus_theme_3" }

local Stages: { Types.Stage } = {
	{
		index = 1,
		id = "first_three",
		title = "Первые три",
		glyphs = "А Б В",
		letters = Letters.byStage(1),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0, -- первая ступень открыта всегда
		music = THEMES[1],
	},
	{
		index = 2,
		id = "guests",
		title = "Гости",
		glyphs = "Г Д Е",
		letters = Letters.byStage(2),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[2],
	},
	{
		index = 3,
		id = "hedgehogs",
		title = "Ёжики",
		glyphs = "Ё Ж З",
		letters = Letters.byStage(3),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[3],
	},
	{
		index = 4,
		id = "needles",
		title = "Иголки",
		glyphs = "И Й К",
		letters = Letters.byStage(4),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[1],
	},
	{
		index = 5,
		id = "forest_path",
		title = "Лесная тропа",
		glyphs = "Л М Н",
		letters = Letters.byStage(5),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[2],
	},
	{
		index = 6,
		id = "clouds",
		title = "Облака",
		glyphs = "О П Р",
		letters = Letters.byStage(6),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[3],
	},
	{
		index = 7,
		id = "sunny_bridge",
		title = "Солнечный мост",
		glyphs = "С Т У",
		letters = Letters.byStage(7),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[1],
	},
	{
		index = 8,
		id = "lanterns",
		title = "Фонарики",
		glyphs = "Ф Х Ц",
		letters = Letters.byStage(8),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[2],
	},
	{
		index = 9,
		id = "thicket",
		title = "Чащоба",
		glyphs = "Ч Ш Щ",
		letters = Letters.byStage(9),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[3],
	},
	{
		index = 10,
		id = "three_quiet",
		title = "Три тихони",
		glyphs = "Ъ Ы Ь",
		letters = Letters.byStage(10),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[1],
	},
	{
		index = 11,
		id = "echo_finale",
		title = "Эхо-финал",
		glyphs = "Э Ю Я",
		letters = Letters.byStage(11),
		challenges = { "letter_rain", "alphabet_ladder", "tunnel_run", "obstacle_course" },
		unlockPrevMasteryRatio = 0.8,
		music = THEMES[2],
	},
}

local Module = {}

Module.all = Stages
Module.THEMES = THEMES

function Module.get(index: number): Types.Stage?
	for _, stage in Stages do
		if stage.index == index then
			return stage
		end
	end
	return nil
end

function Module.expect(index: number): Types.Stage
	local stage = Module.get(index)
	assert(stage, `Stages: нет ступени с индексом {index}`)
	return stage
end

function Module.count(): number
	return #Stages
end

--[[
	Открыта ли ступень: нужно, чтобы >= unlockPrevMasteryRatio букв предыдущей
	имели статус «изученная» (2) или выше. Первая открыта всегда.

	Одну букву можно «недоучить» и всё равно пройти дальше — она вернётся
	в повторениях. Тупика быть не должно ни при каких условиях.
]]
function Module.isUnlocked(index: number, masteryOf: (letterId: string) -> number): boolean
	local stage = Module.get(index)
	if not stage then
		return false
	end
	if index <= 1 or stage.unlockPrevMasteryRatio <= 0 then
		return true
	end

	local prev = Module.get(index - 1)
	if not prev or #prev.letters == 0 then
		return false
	end

	local learned = 0
	for _, letterId in prev.letters do
		if masteryOf(letterId) >= 2 then
			learned += 1
		end
	end

	return (learned / #prev.letters) >= stage.unlockPrevMasteryRatio
end

-- Ступень, на которой стоит буква. Нужна, чтобы понять, доступна ли она игроку.
function Module.ofLetter(letterId: string): number
	return Letters.expect(letterId).stage
end

return Module
