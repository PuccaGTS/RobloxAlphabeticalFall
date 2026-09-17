--!strict
--[[
	Справочник букв. Единственный источник истины по алфавиту: все 33 буквы,
	в алфавитном порядке. Полная таблица с пояснениями — docs/09-DATA-SCHEMA.md.

	ВАЖНО: vo.name — это НАЗВАНИЕ буквы («Буква М»), а не её звук («м»).
	Игра учит алфавит: узнать букву, назвать её, знать, где она стоит.
	Звуки, слоги и чтение сюда не входят — почему, написано в docs/02-LEARNING.md § 1.

	Файл сгенерирован по таблице и правится целиком, а не по одной букве:
	порядок, ступени и ключи озвучки должны оставаться согласованными.
]]

local Types = require(script.Parent.Parent.Types)

-- Цветовая кодировка из docs/08-UX-UI.md (совпадает со схемой российских букварей)
local COLOR_VOWEL = Color3.fromRGB(214, 69, 65) -- красный
local COLOR_HARD = Color3.fromRGB(52, 116, 214) -- синий
local COLOR_SIGN = Color3.fromRGB(150, 150, 155) -- серый

local Letters: { [string]: Types.Letter } = {
	-- ===== Ступень 1 · Первые три (А Б В) =============================================
	a = {
		id = "a",
		glyph = "А",
		glyphLower = "а",
		kind = "vowel",
		order = 1,
		stage = 1,
		color = COLOR_VOWEL,
		vo = { name = "letter_a" },
		example = "АРБУЗ",
		picture = "🍉",
		confusableWith = {},
	},
	b = {
		id = "b",
		glyph = "Б",
		glyphLower = "б",
		kind = "consonant",
		order = 2,
		stage = 1,
		color = COLOR_HARD,
		vo = { name = "letter_b" },
		example = "БАНАН",
		picture = "🍌",
		confusableWith = { "v" },
	},
	v = {
		id = "v",
		glyph = "В",
		glyphLower = "в",
		kind = "consonant",
		order = 3,
		stage = 1,
		color = COLOR_HARD,
		vo = { name = "letter_v" },
		example = "ВОЛК",
		picture = "🐺",
		confusableWith = { "b" },
	},

	-- ===== Ступень 2 · Гости (Г Д Е) ==================================================
	g = {
		id = "g",
		glyph = "Г",
		glyphLower = "г",
		kind = "consonant",
		order = 4,
		stage = 2,
		color = COLOR_HARD,
		vo = { name = "letter_g" },
		example = "ГРИБ",
		picture = "🍄",
		confusableWith = { "t" },
	},
	d = {
		id = "d",
		glyph = "Д",
		glyphLower = "д",
		kind = "consonant",
		order = 5,
		stage = 2,
		color = COLOR_HARD,
		vo = { name = "letter_d" },
		example = "ДОМ",
		picture = "🏠",
		confusableWith = {},
	},
	ye = {
		id = "ye",
		glyph = "Е",
		glyphLower = "е",
		kind = "vowel",
		order = 6,
		stage = 2,
		color = COLOR_VOWEL,
		vo = { name = "letter_ye" },
		example = "ЕЛЬ",
		picture = "🌲",
		confusableWith = { "yo" },
	},

	-- ===== Ступень 3 · Ёжики (Ё Ж З) ==================================================
	yo = {
		id = "yo",
		glyph = "Ё",
		glyphLower = "ё",
		kind = "vowel",
		order = 7,
		stage = 3,
		color = COLOR_VOWEL,
		vo = { name = "letter_yo" },
		example = "ЁЖ",
		picture = "🦔",
		confusableWith = { "ye" },
	},
	zh = {
		id = "zh",
		glyph = "Ж",
		glyphLower = "ж",
		kind = "consonant",
		order = 8,
		stage = 3,
		color = COLOR_HARD,
		vo = { name = "letter_zh" },
		example = "ЖУК",
		picture = "🐞",
		confusableWith = {},
	},
	z = {
		id = "z",
		glyph = "З",
		glyphLower = "з",
		kind = "consonant",
		order = 9,
		stage = 3,
		color = COLOR_HARD,
		vo = { name = "letter_z" },
		example = "ЗОНТ",
		picture = "☂️",
		confusableWith = { "e" },
	},

	-- ===== Ступень 4 · Иголки (И Й К) =================================================
	i = {
		id = "i",
		glyph = "И",
		glyphLower = "и",
		kind = "vowel",
		order = 10,
		stage = 4,
		color = COLOR_VOWEL,
		vo = { name = "letter_i" },
		example = "ИНДЮК",
		picture = "🦃",
		confusableWith = { "j", "n" },
	},
	j = {
		id = "j",
		glyph = "Й",
		glyphLower = "й",
		kind = "consonant",
		order = 11,
		stage = 4,
		color = COLOR_HARD,
		vo = { name = "letter_j" },
		example = "ЧАЙ",
		picture = "🍵",
		confusableWith = { "i" },
	},
	k = {
		id = "k",
		glyph = "К",
		glyphLower = "к",
		kind = "consonant",
		order = 12,
		stage = 4,
		color = COLOR_HARD,
		vo = { name = "letter_k" },
		example = "КОТ",
		picture = "🐱",
		confusableWith = {},
	},

	-- ===== Ступень 5 · Лесная тропа (Л М Н) ===========================================
	l = {
		id = "l",
		glyph = "Л",
		glyphLower = "л",
		kind = "consonant",
		order = 13,
		stage = 5,
		color = COLOR_HARD,
		vo = { name = "letter_l" },
		example = "ЛУНА",
		picture = "🌙",
		confusableWith = {},
	},
	m = {
		id = "m",
		glyph = "М",
		glyphLower = "м",
		kind = "consonant",
		order = 14,
		stage = 5,
		color = COLOR_HARD,
		vo = { name = "letter_m" },
		example = "МЯЧ",
		picture = "⚽",
		confusableWith = {},
	},
	n = {
		id = "n",
		glyph = "Н",
		glyphLower = "н",
		kind = "consonant",
		order = 15,
		stage = 5,
		color = COLOR_HARD,
		vo = { name = "letter_n" },
		example = "НОС",
		picture = "👃",
		confusableWith = { "i", "p" },
	},

	-- ===== Ступень 6 · Облака (О П Р) =================================================
	o = {
		id = "o",
		glyph = "О",
		glyphLower = "о",
		kind = "vowel",
		order = 16,
		stage = 6,
		color = COLOR_VOWEL,
		vo = { name = "letter_o" },
		example = "ОБЛАКО",
		picture = "☁️",
		confusableWith = { "s" },
	},
	p = {
		id = "p",
		glyph = "П",
		glyphLower = "п",
		kind = "consonant",
		order = 17,
		stage = 6,
		color = COLOR_HARD,
		vo = { name = "letter_p" },
		example = "ПАПА",
		picture = "👨",
		confusableWith = { "n" },
	},
	r = {
		id = "r",
		glyph = "Р",
		glyphLower = "р",
		kind = "consonant",
		order = 18,
		stage = 6,
		color = COLOR_HARD,
		vo = { name = "letter_r" },
		example = "РЫБА",
		picture = "🐟",
		confusableWith = {},
	},

	-- ===== Ступень 7 · Солнечный мост (С Т У) =========================================
	s = {
		id = "s",
		glyph = "С",
		glyphLower = "с",
		kind = "consonant",
		order = 19,
		stage = 7,
		color = COLOR_HARD,
		vo = { name = "letter_s" },
		example = "СОК",
		picture = "🧃",
		confusableWith = { "o" },
	},
	t = {
		id = "t",
		glyph = "Т",
		glyphLower = "т",
		kind = "consonant",
		order = 20,
		stage = 7,
		color = COLOR_HARD,
		vo = { name = "letter_t" },
		example = "ТОРТ",
		picture = "🎂",
		confusableWith = { "g" },
	},
	u = {
		id = "u",
		glyph = "У",
		glyphLower = "у",
		kind = "vowel",
		order = 21,
		stage = 7,
		color = COLOR_VOWEL,
		vo = { name = "letter_u" },
		example = "УТКА",
		picture = "🦆",
		confusableWith = {},
	},

	-- ===== Ступень 8 · Фонарики (Ф Х Ц) ===============================================
	f = {
		id = "f",
		glyph = "Ф",
		glyphLower = "ф",
		kind = "consonant",
		order = 22,
		stage = 8,
		color = COLOR_HARD,
		vo = { name = "letter_f" },
		example = "ФОНАРЬ",
		picture = "🔦",
		confusableWith = {},
	},
	h = {
		id = "h",
		glyph = "Х",
		glyphLower = "х",
		kind = "consonant",
		order = 23,
		stage = 8,
		color = COLOR_HARD,
		vo = { name = "letter_h" },
		example = "ХЛЕБ",
		picture = "🍞",
		confusableWith = {},
	},
	c = {
		id = "c",
		glyph = "Ц",
		glyphLower = "ц",
		kind = "hissing",
		order = 24,
		stage = 8,
		color = COLOR_HARD,
		vo = { name = "letter_c" },
		example = "ЦВЕТОК",
		picture = "🌷",
		confusableWith = { "shch" },
	},

	-- ===== Ступень 9 · Чащоба (Ч Ш Щ) =================================================
	ch = {
		id = "ch",
		glyph = "Ч",
		glyphLower = "ч",
		kind = "hissing",
		order = 25,
		stage = 9,
		color = COLOR_HARD,
		vo = { name = "letter_ch" },
		example = "ЧАСЫ",
		picture = "⏰",
		confusableWith = {},
	},
	sh = {
		id = "sh",
		glyph = "Ш",
		glyphLower = "ш",
		kind = "hissing",
		order = 26,
		stage = 9,
		color = COLOR_HARD,
		vo = { name = "letter_sh" },
		example = "ШАР",
		picture = "🎈",
		confusableWith = { "shch" },
	},
	shch = {
		id = "shch",
		glyph = "Щ",
		glyphLower = "щ",
		kind = "hissing",
		order = 27,
		stage = 9,
		color = COLOR_HARD,
		vo = { name = "letter_shch" },
		example = "ЩЕНОК",
		picture = "🐶",
		confusableWith = { "sh", "c" },
	},

	-- ===== Ступень 10 · Три тихони (Ъ Ы Ь) =============================================
	hard = {
		id = "hard",
		glyph = "Ъ",
		glyphLower = "ъ",
		kind = "sign",
		order = 28,
		stage = 10,
		color = COLOR_SIGN,
		vo = { name = "letter_hard" },
		example = "ПОДЪЕЗД",
		picture = "🏢",
		confusableWith = { "soft" },
	},
	y = {
		id = "y",
		glyph = "Ы",
		glyphLower = "ы",
		kind = "vowel",
		order = 29,
		stage = 10,
		color = COLOR_VOWEL,
		vo = { name = "letter_y" },
		example = "СЫР",
		picture = "🧀",
		confusableWith = { "soft" },
	},
	soft = {
		id = "soft",
		glyph = "Ь",
		glyphLower = "ь",
		kind = "sign",
		order = 30,
		stage = 10,
		color = COLOR_SIGN,
		vo = { name = "letter_soft" },
		example = "СОЛЬ",
		picture = "🧂",
		confusableWith = { "hard", "y" },
	},

	-- ===== Ступень 11 · Эхо-финал (Э Ю Я) ==============================================
	e = {
		id = "e",
		glyph = "Э",
		glyphLower = "э",
		kind = "vowel",
		order = 31,
		stage = 11,
		color = COLOR_VOWEL,
		vo = { name = "letter_e" },
		example = "ЭСКИМО",
		picture = "🍦",
		confusableWith = { "z" },
	},
	yu = {
		id = "yu",
		glyph = "Ю",
		glyphLower = "ю",
		kind = "vowel",
		order = 32,
		stage = 11,
		color = COLOR_VOWEL,
		vo = { name = "letter_yu" },
		example = "ЮПИТЕР",
		picture = "🪐",
		confusableWith = {},
	},
	ya = {
		id = "ya",
		glyph = "Я",
		glyphLower = "я",
		kind = "vowel",
		order = 33,
		stage = 11,
		color = COLOR_VOWEL,
		vo = { name = "letter_ya" },
		example = "ЯБЛОКО",
		picture = "🍎",
		confusableWith = {},
	},
}

local Module = {}

Module.all = Letters
Module.COLOR_VOWEL = COLOR_VOWEL
Module.COLOR_HARD = COLOR_HARD
Module.COLOR_SIGN = COLOR_SIGN

Module.COUNT = 33

function Module.get(id: string): Types.Letter?
	return Letters[id]
end

function Module.expect(id: string): Types.Letter
	local letter = Letters[id]
	assert(letter, `Letters: неизвестная буква "{id}"`)
	return letter
end

-- Все id в алфавитном порядке: А, Б, В … Я. Он же порядок изучения.
function Module.ordered(): { string }
	local ids: { string } = {}
	for id in Letters do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string): boolean
		return Letters[a].order < Letters[b].order
	end)
	return ids
end

function Module.byStage(stage: number): { string }
	local ids: { string } = {}
	for _, id in Module.ordered() do
		if Letters[id].stage == stage then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Буква по месту в алфавите: 1 → А, 33 → Я. Нужна «Алфавитной лестнице».
function Module.at(order: number): Types.Letter?
	for _, letter in Letters do
		if letter.order == order then
			return letter
		end
	end
	return nil
end

-- Следующая буква алфавита. Для Я возвращает nil — дальше ничего нет.
function Module.after(id: string): Types.Letter?
	return Module.at(Module.expect(id).order + 1)
end

function Module.before(id: string): Types.Letter?
	return Module.at(Module.expect(id).order - 1)
end

function Module.vowels(): { string }
	local ids: { string } = {}
	for _, id in Module.ordered() do
		if Letters[id].kind == "vowel" then
			table.insert(ids, id)
		end
	end
	return ids
end

function Module.count(): number
	local n = 0
	for _ in Letters do
		n += 1
	end
	return n
end

return Module
