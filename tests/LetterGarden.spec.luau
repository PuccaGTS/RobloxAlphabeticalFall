--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LetterGarden = require(ReplicatedStorage.Shared.Logic.LetterGarden)
local Migrations = require(ReplicatedStorage.Shared.Logic.Migrations)
local ProfileTemplate = require(ReplicatedStorage.Shared.Config.ProfileTemplate)

return function()
	describe("Logic/LetterGarden", function()
		local T = 1000000

		it("посадил — семечко, потом росток, потом цветок", function()
			local state, letter = LetterGarden.plant(LetterGarden.new(), 2, { "a", "b" }, T)
			expect(letter).to.equal("a")
			local bed = state.beds[2]
			expect(LetterGarden.stage(bed, T)).to.equal("seed")
			expect(LetterGarden.stage(bed, T + LetterGarden.SPROUT)).to.equal("sprout")
			expect(LetterGarden.stage(bed, T + LetterGarden.BLOOM)).to.equal("bloom")
			expect(LetterGarden.left(bed, T + 60)).to.equal(LetterGarden.BLOOM - 60)
		end)

		it(
			"в занятую лунку не сажается, рано не собирается",
			function()
				local state = LetterGarden.plant(LetterGarden.new(), 1, { "a" }, T)
				local _, again = LetterGarden.plant(state, 1, { "a" }, T + 5)
				expect(again).to.equal(nil)
				local _, early = LetterGarden.harvest(state, 1, T + LetterGarden.SPROUT)
				expect(early).to.equal(nil)
			end
		)

		it("урожай освобождает лунку и считается", function()
			local state = LetterGarden.plant(LetterGarden.new(), 3, { "g" }, T)
			local after, letter = LetterGarden.harvest(state, 3, T + LetterGarden.BLOOM + 1)
			expect(letter).to.equal("g")
			expect(after.harvested).to.equal(1)
			expect(LetterGarden.stage(after.beds[3], T + LetterGarden.BLOOM + 1)).to.equal("empty")
		end)

		it(
			"буквы сажаются по кругу из выученных, без выученных — первые",
			function()
				local state = LetterGarden.new()
				local planted = {}
				for index = 1, 3 do
					local letter
					state, letter = LetterGarden.plant(state, index, { "a", "b" }, T)
					table.insert(planted, letter)
				end
				expect(table.concat(planted, ",")).to.equal("a,b,a")
				expect(LetterGarden.hasEmpty(state, T)).to.equal(false)
				local _, first = LetterGarden.plant(LetterGarden.new(), 1, {}, T)
				expect(first).to.equal("a")
			end
		)

		it("мусор из профиля не ломает грядку", function()
			local clean = LetterGarden.sanitize({
				beds = { { letterId = 5 }, { letterId = "a", plantedAt = -1 } },
				next = 0 / 0,
			})
			expect(#clean.beds).to.equal(LetterGarden.BEDS)
			expect(clean.beds[1].letterId).to.equal(nil)
			expect(clean.beds[2].letterId).to.equal(nil)
			expect(clean.next).to.equal(1)
		end)

		it(
			"профиль тринадцатой версии получает пустую грядку",
			function()
				local profile = ProfileTemplate.new(T)
				profile.version = 13
				profile.garden = nil
				local migrated = Migrations.normalize(profile, T)
				expect(migrated.version).to.equal(ProfileTemplate.VERSION)
				expect(#migrated.garden.beds).to.equal(LetterGarden.BEDS)
			end
		)
	end)
end
