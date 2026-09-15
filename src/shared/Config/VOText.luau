--!strict
--[[
	Текст каждой реплики — для субтитров. Тот же текст, что в docs/VO-SCRIPT.md:
	что диктор скажет, то и будет написано.

	Субтитры нужны прямо сейчас, а не «для читающих когда-нибудь»: озвучка ещё
	не записана, и без текста игра молчит. Задание «Беги на цифру три» без голоса
	не понять ни ребёнку, ни взрослому, который её проверяет. Поэтому любая
	реплика без загруженного аудио показывается текстом (AudioController).
	Когда озвучка появится, текст останется только для тех, кто включит
	субтитры в родительском режиме (docs/08-UX-UI.md § 8).

	Названия букв и куски математики не пишутся руками: они собираются
	из справочника букв и Config/Math, чтобы список нельзя было забыть обновить.
]]

local Letters = require(script.Parent.Letters)
local MathConfig = require(script.Parent.Math)

local VOText = {}

local FIXED: { [string]: string } = {
	instr_letter_rain = "Лови вот эту букву!",
	instr_alphabet_ladder = "Поднимайся по лестнице. Какая буква идёт после этой?",
	instr_tunnel_run = "Беги в ворота вот с этой буквой!",
	instr_obstacle_course = "Полоса препятствий! Прыгай, беги и не пропусти вот эту букву:",
	instr_bubbles = "Лопни все пузыри вот с этой буквой:",
	instr_mirror = "Найди букву, которая написана правильно.",
	instr_math_gates = "Слушай задание и беги в нужные ворота!",
	instr_scales = "Выбери столько же камней, чтобы весы стали ровными.",

	story_intro = "Привет! Я Азбука. Буквы разлетелись по всему свету. Поможешь мне их найти?",
	story_meet_letter = "Познакомься! Это…",
	story_stage_open = "Смотри, открылись новые буквы!",
	story_stage_done = "Ты выучил всю ступень. Молодец!",

	praise_01 = "Молодец!",
	praise_02 = "Точно!",
	praise_03 = "Вот эта!",
	praise_04 = "Получилось!",
	praise_05 = "Здорово!",
	praise_06 = "Ты нашёл!",
	praise_07 = "Так и есть!",
	praise_08 = "Вот это да!",

	retry_01 = "Почти!",
	retry_02 = "Слушай ещё разок.",
	retry_03 = "Это другая буква.",
	retry_04 = "Давай найдём вместе.",
	retry_05 = "Ничего страшного, пробуем ещё.",

	hint_01 = "Смотри сюда.",
	hint_02 = "Вот эта светится.",
	hint_03 = "Попробуй вот эту.",

	ui_shop = "Магазин.",
	ui_stars = "Твои звёздочки.",
	ui_goodbye = "До завтра! Буквы будут тебя ждать.",
	ui_rest_reminder = "Давай отдохнём? Глазкам нужен перерыв.",
}

-- У Й, Ъ и Ь свои имена, а не «буква такая-то» (docs/VO-SCRIPT.md, «Как читать названия»).
local LETTER_NAMES: { [string]: string } = {
	j = "Буква Й. И краткое",
	hard = "Твёрдый знак",
	soft = "Мягкий знак",
}

local NUMBERS = {
	"один",
	"два",
	"три",
	"четыре",
	"пять",
	"шесть",
	"семь",
	"восемь",
	"девять",
	"десять",
}

local texts: { [string]: string } = table.clone(FIXED)

for _, letterId in Letters.ordered() do
	local letter = Letters.expect(letterId)
	texts[letter.vo.name] = LETTER_NAMES[letterId] or `Буква {letter.glyph}`
end

for value, word in NUMBERS do
	texts[`num_{value}`] = word
end

for key, text in MathConfig.PHRASES do
	texts[key] = text
end

VOText.texts = texts

function VOText.get(key: string): string?
	return texts[key]
end

--[[
	Текст фразы из нескольких реплик: «Сколько будет» + «два» + «плюс» + «два» →
	«Сколько будет два плюс два». Неизвестные куски пропускаются: лучше короче,
	чем с техническим ключом посреди фразы.
]]
function VOText.phrase(keys: { string }): string
	local words: { string } = {}
	for _, key in keys do
		local text = texts[key]
		if text then
			table.insert(words, text)
		end
	end
	return table.concat(words, " ")
end

return VOText
