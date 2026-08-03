--!strict
--[[
	Слоги. Генерируются из Config/Letters по правилам docs/02-LEARNING.md § 3,
	а не вводятся руками — иначе неизбежны опечатки и пропуски озвучки.

	ВАЖНО: каждый слог озвучивается ОДНИМ слитным файлом (vo = "blend_ma").
	Склейка "м" + "а" в рантайме запрещена — она учит побуквенному чтению.
]]

local Types = require(script.Parent.Parent.Types)
local Letters = require(script.Parent.Letters)

-- Сочетания, которые не даём никогда: ЖЫ/ШЫ/ЧЫ/ЩЫ/ЦЫ и Э после шипящих.
-- Ключ — "<consonantId>_<vowelId>".
local FORBIDDEN: { [string]: boolean } = {
	zh_y = true,
	sh_y = true,
	ch_y = true,
	shch_y = true,
	c_y = true,
	zh_e = true,
	sh_e = true,
	ch_e = true,
	shch_e = true,
	c_e = true,
}

-- Согласные, которыми закрываем слог (остальные звучат неестественно в конце).
local CLOSING: { [string]: boolean } = {
	m = true,
	n = true,
	t = true,
	p = true,
	k = true,
	s = true,
	h = true,
	l = true,
	r = true,
	f = true,
	sh = true,
}

-- Слоги из двух гласных — первое, что читает ребёнок на острове 1.
local VOWEL_PAIRS: { { string } } = {
	{ "a", "u" },
	{ "u", "a" },
	{ "i", "a" },
	{ "a", "i" },
}

local CLOSED_MIN_ISLAND = 3 -- закрытые слоги даём не раньше третьего острова

local Syllables: { [string]: Types.Syllable } = {}
local orderedIds: { string } = {}

local function add(syllable: Types.Syllable)
	assert(Syllables[syllable.id] == nil, `Syllables: дубликат id "{syllable.id}"`)
	Syllables[syllable.id] = syllable
	table.insert(orderedIds, syllable.id)
end

-- 1. Гласная + гласная (АУ, УА, ИА, АИ)
for _, pair in VOWEL_PAIRS do
	local first, second = pair[1], pair[2]
	local a, b = Letters.expect(first), Letters.expect(second)
	add({
		id = first .. second,
		text = a.glyph .. b.glyph,
		consonant = nil,
		vowel = second,
		kind = "vv",
		vo = "blend_" .. first .. second,
		minIsland = math.max(a.island, b.island),
	})
end

-- 2. Открытые слоги: согласная + гласная (МА, МУ, ПО...) — основной тип
for _, cId in Letters.consonants() do
	local c = Letters.expect(cId)
	for _, vId in Letters.vowels() do
		local v = Letters.expect(vId)
		if not FORBIDDEN[cId .. "_" .. vId] then
			add({
				id = cId .. vId,
				text = c.glyph .. v.glyph,
				consonant = cId,
				vowel = vId,
				kind = "open",
				vo = "blend_" .. cId .. vId,
				minIsland = math.max(c.island, v.island),
			})
		end
	end
end

-- 3. Закрытые слоги: гласная + согласная (АМ, ОП, УТ)
for _, vId in Letters.vowels() do
	local v = Letters.expect(vId)
	for _, cId in Letters.consonants() do
		if CLOSING[cId] then
			local c = Letters.expect(cId)
			add({
				id = vId .. cId,
				text = v.glyph .. c.glyph,
				consonant = cId,
				vowel = vId,
				kind = "closed",
				vo = "blend_" .. vId .. cId,
				minIsland = math.max(c.island, v.island, CLOSED_MIN_ISLAND),
			})
		end
	end
end

local Module = {}

Module.all = Syllables

function Module.get(id: string): Types.Syllable?
	return Syllables[id]
end

function Module.expect(id: string): Types.Syllable
	local syllable = Syllables[id]
	assert(syllable, `Syllables: неизвестный слог "{id}"`)
	return syllable
end

function Module.ids(): { string }
	return table.clone(orderedIds)
end

function Module.count(): number
	return #orderedIds
end

--[[
	Слоги, которые можно предложить игроку прямо сейчас:
	обе буквы уже как минимум «изученные», и остров открыт.
]]
function Module.available(knownLetters: { [string]: boolean }, maxIsland: number): { string }
	local result: { string } = {}
	for _, id in orderedIds do
		local s = Syllables[id]
		local ok = s.minIsland <= maxIsland and knownLetters[s.vowel] == true
		if ok and s.consonant ~= nil then
			ok = knownLetters[s.consonant] == true
		end
		if ok and s.kind == "vv" then
			-- у слога из двух гласных первая буква зашита в id
			local firstId = string.sub(id, 1, #id - #s.vowel)
			ok = knownLetters[firstId] == true
		end
		if ok then
			table.insert(result, id)
		end
	end
	return result
end

return Module
