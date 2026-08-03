--!nocheck
--[[
	Инварианты контента. Эти тесты — единственная защита от ошибок в конфигах,
	которые иначе всплывут уже на ребёнке: слово из невыученных букв, слог без озвучки,
	буква-«путаница», которой нет в алфавите.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Letters = require(Shared.Config.Letters)
local Syllables = require(Shared.Config.Syllables)
local Words = require(Shared.Config.Words)
local Islands = require(Shared.Config.Islands)
local Challenges = require(Shared.Config.Challenges)
local AudioRegistry = require(Shared.Config.AudioRegistry)

return function()
	describe("Config: буквы", function()
		it("id совпадает с ключом таблицы", function()
			for id, letter in Letters.all do
				expect(letter.id).to.equal(id)
			end
		end)

		it(
			"у каждой буквы есть звук, а тянущиеся имеют растянутую версию",
			function()
				for _, id in Letters.ordered() do
					local letter = Letters.expect(id)
					expect(letter.vo.sound).to.be.a("string")
					expect(#letter.vo.sound > 0).to.equal(true)
					if letter.sustainable and letter.kind ~= "sign" then
						expect(letter.vo.long).to.be.ok()
					end
				end
			end
		)

		it("буквы-путаницы существуют в алфавите", function()
			for _, id in Letters.ordered() do
				for _, other in Letters.expect(id).confusableWith do
					expect(Letters.get(other)).to.be.ok()
					expect(other).never.to.equal(id)
				end
			end
		end)

		it("внутри острова порядок букв не дублируется", function()
			local seen = {}
			for _, id in Letters.ordered() do
				local letter = Letters.expect(id)
				local key = letter.island .. ":" .. letter.order
				expect(seen[key]).to.equal(nil)
				seen[key] = id
			end
		end)
	end)

	describe("Config: слоги", function()
		it("генерируются и не пустые", function()
			expect(Syllables.count() > 0).to.equal(true)
		end)

		it("состоят из существующих букв", function()
			for _, id in Syllables.ids() do
				local syllable = Syllables.expect(id)
				expect(Letters.get(syllable.vowel)).to.be.ok()
				if syllable.consonant then
					expect(Letters.get(syllable.consonant)).to.be.ok()
				end
			end
		end)

		it(
			"не содержат запрещённых сочетаний ЖЫ/ШЫ/ЧЫ/ЩЫ/ЦЫ",
			function()
				for _, id in Syllables.ids() do
					local syllable = Syllables.expect(id)
					if syllable.consonant and syllable.kind == "open" then
						local pair = syllable.consonant .. "_" .. syllable.vowel
						local forbidden = pair == "zh_y"
							or pair == "sh_y"
							or pair == "ch_y"
							or pair == "shch_y"
							or pair == "c_y"
						expect(forbidden).to.equal(false)
					end
				end
			end
		)

		it("открываются не раньше островов своих букв", function()
			for _, id in Syllables.ids() do
				local syllable = Syllables.expect(id)
				local vowelIsland = Letters.expect(syllable.vowel).island
				expect(syllable.minIsland >= vowelIsland).to.equal(true)
				if syllable.consonant then
					expect(syllable.minIsland >= Letters.expect(syllable.consonant).island).to.equal(true)
				end
			end
		end)

		it(
			"закрытые слоги не даются раньше третьего острова",
			function()
				for _, id in Syllables.ids() do
					local syllable = Syllables.expect(id)
					if syllable.kind == "closed" then
						expect(syllable.minIsland >= 3).to.equal(true)
					end
				end
			end
		)
	end)

	describe("Config: слова", function()
		it("написание совпадает с набором букв", function()
			for _, id in Words.ids() do
				local word = Words.expect(id)
				local built = ""
				for _, letterId in word.letters do
					built ..= Letters.expect(letterId).glyph
				end
				expect(built).to.equal(word.text)
			end
		end)

		it(
			"не содержат букв с более позднего острова, чем сами доступны",
			function()
				for _, id in Words.ids() do
					local word = Words.expect(id)
					for _, letterId in word.letters do
						local letter = Letters.expect(letterId)
						expect(letter.island <= word.minIsland).to.equal(true)
					end
				end
			end
		)

		it("разбиты на слоги без потери букв", function()
			for _, id in Words.ids() do
				local word = Words.expect(id)
				expect(table.concat(word.syllables, "")).to.equal(word.text)
			end
		end)

		it("доступны только при выученных буквах", function()
			local known = { m = true, a = true }
			local available = Words.available(known)

			expect(table.find(available, "mama")).to.be.ok()
			expect(table.find(available, "papa")).never.to.be.ok()
		end)
	end)

	describe("Config: острова", function()
		it(
			"состав островов совпадает со справочником букв",
			function()
				for _, island in Islands.all do
					expect(#island.letters).to.equal(#Letters.byIsland(island.index))
				end
			end
		)

		it("первый остров открыт всегда", function()
			expect(Islands.isUnlocked(1, function()
				return 0
			end)).to.equal(true)
		end)

		it(
			"следующий остров требует 80% изученных букв предыдущего",
			function()
				local first = Letters.byIsland(1)
				local learned = {}

				local function masteryOf(id)
					return if learned[id] then 2 else 0
				end

				expect(Islands.isUnlocked(2, masteryOf)).to.equal(false)

				for _, id in first do
					learned[id] = true
				end
				expect(Islands.isUnlocked(2, masteryOf)).to.equal(true)
			end
		)

		it("ссылается только на существующие испытания", function()
			for _, island in Islands.all do
				for _, challengeId in island.challenges do
					expect(Challenges.get(challengeId)).to.be.ok()
				end
			end
		end)
	end)

	describe("Config: испытания", function()
		it(
			"у каждого параметра ровно пять значений сложности",
			function()
				for _, id in Challenges.ids() do
					local meta = Challenges.expect(id)
					for name, values in meta.params do
						expect(#values).to.equal(5)
						if #values ~= 5 then
							warn(`{id}.{name}: ожидалось 5 значений`)
						end
					end
				end
			end
		)
	end)

	describe("Config: озвучка", function()
		it(
			"все реплики, которые просит игра, объявлены в реестре",
			function()
				local missing = AudioRegistry.unregistered()
				if #missing > 0 then
					warn("нет в реестре: " .. table.concat(missing, ", "))
				end
				expect(#missing).to.equal(0)
			end
		)

		it("реестр содержит звуки всех букв и все слоги", function()
			local required = AudioRegistry.requiredKeys()
			expect(#required >= Letters.count() + Syllables.count()).to.equal(true)
		end)
	end)
end
