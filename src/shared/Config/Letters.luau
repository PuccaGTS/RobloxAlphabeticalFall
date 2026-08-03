--!strict
--[[
	Справочник букв. Единственный источник истины по алфавиту.
	MVP: 9 букв (острова 1 и 2). Полная таблица всех 33 — docs/09-DATA-SCHEMA.md.

	ВАЖНО: vo.sound — это ЗВУК буквы ("м"), а не её название ("эм").
	См. docs/02-LEARNING.md, правило 1.
]]

local Types = require(script.Parent.Parent.Types)

-- Цветовая кодировка из docs/08-UX-UI.md (совпадает со схемой российских букварей)
local COLOR_VOWEL = Color3.fromRGB(214, 69, 65) -- красный
local COLOR_HARD = Color3.fromRGB(52, 116, 214) -- синий
local COLOR_SIGN = Color3.fromRGB(150, 150, 155) -- серый

local Letters: { [string]: Types.Letter } = {
	-- ===== Остров 1 · Поющий берег (гласные) =====================================
	a = {
		id = "a",
		glyph = "А",
		glyphLower = "а",
		kind = "vowel",
		sustainable = true,
		island = 1,
		order = 1,
		color = COLOR_VOWEL,
		vo = { sound = "snd_a", long = "snd_long_a", name = "name_a" },
		examples = { "mama", "banan" },
		confusableWith = { "o" },
	},
	u = {
		id = "u",
		glyph = "У",
		glyphLower = "у",
		kind = "vowel",
		sustainable = true,
		island = 1,
		order = 2,
		color = COLOR_VOWEL,
		vo = { sound = "snd_u", long = "snd_long_u", name = "name_u" },
		examples = { "puma" },
		confusableWith = { "o" },
	},
	o = {
		id = "o",
		glyph = "О",
		glyphLower = "о",
		kind = "vowel",
		sustainable = true,
		island = 1,
		order = 3,
		color = COLOR_VOWEL,
		vo = { sound = "snd_o", long = "snd_long_o", name = "name_o" },
		examples = { "nota" },
		confusableWith = { "a", "u" },
	},
	i = {
		id = "i",
		glyph = "И",
		glyphLower = "и",
		kind = "vowel",
		sustainable = true,
		island = 1,
		order = 4,
		color = COLOR_VOWEL,
		vo = { sound = "snd_i", long = "snd_long_i", name = "name_i" },
		examples = { "bint" },
		confusableWith = {},
	},

	-- ===== Остров 2 · Мягкие холмы (губные согласные) =============================
	m = {
		id = "m",
		glyph = "М",
		glyphLower = "м",
		kind = "consonant",
		voiced = true,
		sustainable = true,
		island = 2,
		order = 1,
		color = COLOR_HARD,
		vo = { sound = "snd_m", long = "snd_long_m", name = "name_m" },
		examples = { "mama", "puma" },
		confusableWith = { "n" },
	},
	p = {
		id = "p",
		glyph = "П",
		glyphLower = "п",
		kind = "consonant",
		voiced = false,
		sustainable = false,
		island = 2,
		order = 2,
		color = COLOR_HARD,
		vo = { sound = "snd_p", name = "name_p" },
		examples = { "papa", "puma" },
		confusableWith = { "b" },
	},
	b = {
		id = "b",
		glyph = "Б",
		glyphLower = "б",
		kind = "consonant",
		voiced = true,
		sustainable = false,
		island = 2,
		order = 3,
		color = COLOR_HARD,
		vo = { sound = "snd_b", name = "name_b" },
		examples = { "banan", "bant", "bum" },
		confusableWith = { "p" },
	},

	-- ===== Остров 3 · Стучащая долина (частично, для MVP) ========================
	t = {
		id = "t",
		glyph = "Т",
		glyphLower = "т",
		kind = "consonant",
		voiced = false,
		sustainable = false,
		island = 3,
		order = 1,
		color = COLOR_HARD,
		vo = { sound = "snd_t", name = "name_t" },
		examples = { "nota", "bant", "bint" },
		confusableWith = {},
	},
	n = {
		id = "n",
		glyph = "Н",
		glyphLower = "н",
		kind = "consonant",
		voiced = true,
		sustainable = true,
		island = 3,
		order = 3,
		color = COLOR_HARD,
		vo = { sound = "snd_n", long = "snd_long_n", name = "name_n" },
		examples = { "nota", "banan", "bint" },
		confusableWith = { "m" },
	},
}

local Module = {}

Module.all = Letters
Module.COLOR_VOWEL = COLOR_VOWEL
Module.COLOR_HARD = COLOR_HARD
Module.COLOR_SIGN = COLOR_SIGN

function Module.get(id: string): Types.Letter?
	return Letters[id]
end

function Module.expect(id: string): Types.Letter
	local letter = Letters[id]
	assert(letter, `Letters: неизвестная буква "{id}"`)
	return letter
end

-- Все id, отсортированные по методическому порядку (остров, затем order внутри острова).
function Module.ordered(): { string }
	local ids: { string } = {}
	for id in Letters do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string): boolean
		local la, lb = Letters[a], Letters[b]
		if la.island ~= lb.island then
			return la.island < lb.island
		end
		return la.order < lb.order
	end)
	return ids
end

function Module.byIsland(island: number): { string }
	local ids: { string } = {}
	for _, id in Module.ordered() do
		if Letters[id].island == island then
			table.insert(ids, id)
		end
	end
	return ids
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

function Module.consonants(): { string }
	local ids: { string } = {}
	for _, id in Module.ordered() do
		local kind = Letters[id].kind
		if kind == "consonant" or kind == "hissing" then
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
