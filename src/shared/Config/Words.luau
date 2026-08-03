--!strict
--[[
	Банк слов. Критерии отбора — docs/02-LEARNING.md § 4:
	3–5 букв, максимум 2 слога, пишется как слышится, есть однозначная детская картинка.

	Инвариант (проверяется тестом ConfigIntegrity):
	все буквы слова должны принадлежать острову <= word.minIsland,
	иначе слово попадёт ребёнку раньше, чем он выучит его буквы.

	MVP: 8 слов на буквах А У О И М П Б Т Н.
]]

local Types = require(script.Parent.Parent.Types)

local Words: { [string]: Types.Word } = {
	mama = {
		id = "mama",
		text = "МАМА",
		letters = { "m", "a", "m", "a" },
		syllables = { "МА", "МА" },
		vo = "word_mama",
		voSyllabic = "word_syl_mama",
		image = "img_word_mama",
		minIsland = 2,
		tags = { "family" },
	},
	papa = {
		id = "papa",
		text = "ПАПА",
		letters = { "p", "a", "p", "a" },
		syllables = { "ПА", "ПА" },
		vo = "word_papa",
		voSyllabic = "word_syl_papa",
		image = "img_word_papa",
		minIsland = 2,
		tags = { "family" },
	},
	puma = {
		id = "puma",
		text = "ПУМА",
		letters = { "p", "u", "m", "a" },
		syllables = { "ПУ", "МА" },
		vo = "word_puma",
		voSyllabic = "word_syl_puma",
		image = "img_word_puma",
		minIsland = 2,
		tags = { "animal" },
	},
	bum = {
		id = "bum",
		text = "БУМ",
		letters = { "b", "u", "m" },
		syllables = { "БУМ" },
		vo = "word_bum",
		voSyllabic = "word_syl_bum",
		image = "img_word_bum",
		minIsland = 2,
		tags = { "sound" },
	},
	nota = {
		id = "nota",
		text = "НОТА",
		letters = { "n", "o", "t", "a" },
		syllables = { "НО", "ТА" },
		vo = "word_nota",
		voSyllabic = "word_syl_nota",
		image = "img_word_nota",
		minIsland = 3,
		tags = { "music" },
	},
	bant = {
		id = "bant",
		text = "БАНТ",
		letters = { "b", "a", "n", "t" },
		syllables = { "БАНТ" },
		vo = "word_bant",
		voSyllabic = "word_syl_bant",
		image = "img_word_bant",
		minIsland = 3,
		tags = { "thing" },
	},
	bint = {
		id = "bint",
		text = "БИНТ",
		letters = { "b", "i", "n", "t" },
		syllables = { "БИНТ" },
		vo = "word_bint",
		voSyllabic = "word_syl_bint",
		image = "img_word_bint",
		minIsland = 3,
		tags = { "thing" },
	},
	banan = {
		id = "banan",
		text = "БАНАН",
		letters = { "b", "a", "n", "a", "n" },
		syllables = { "БА", "НАН" },
		vo = "word_banan",
		voSyllabic = "word_syl_banan",
		image = "img_word_banan",
		minIsland = 3,
		tags = { "food" },
	},
}

local Module = {}

Module.all = Words

function Module.get(id: string): Types.Word?
	return Words[id]
end

function Module.expect(id: string): Types.Word
	local word = Words[id]
	assert(word, `Words: неизвестное слово "{id}"`)
	return word
end

function Module.ids(): { string }
	local ids: { string } = {}
	for id in Words do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Слова, у которых ВСЕ буквы уже освоены игроком. Раньше этого слово не показываем.
function Module.available(knownLetters: { [string]: boolean }): { string }
	local result: { string } = {}
	for _, id in Module.ids() do
		local ok = true
		for _, letterId in Words[id].letters do
			if knownLetters[letterId] ~= true then
				ok = false
				break
			end
		end
		if ok then
			table.insert(result, id)
		end
	end
	return result
end

return Module
