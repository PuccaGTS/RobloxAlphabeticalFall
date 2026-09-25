--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Badges = require(Shared.Config.Badges)
local Chests = require(Shared.Config.Chests)
local Levels = require(Shared.Config.Levels)
local Letters = require(Shared.Config.Letters)
local Pets = require(Shared.Logic.Pets)

local function learned(count)
	local letters = {}
	for index, id in Letters.ordered() do
		if index <= count then
			letters[id] = { mastery = Pets.OWNED_AT }
		end
	end
	return letters
end

return function()
	describe("Config/Badges — значки Roblox", function()
		it(
			"новичку не положено ничего, мусор не ломает счёт",
			function()
				expect(next(Badges.earned(nil))).to.equal(nil)
				expect(next(Badges.earned({ levels = "x", letters = 5, inventory = false }))).to.equal(nil)
			end
		)

		it("первый и все уровни мира букв", function()
			local one = Badges.earned({ levels = { [Levels.WORLD] = 1 } })
			expect(one.first_level).to.equal(true)
			expect(one.all_levels).to.equal(nil)
			local all = Badges.earned({ levels = { [Levels.WORLD] = Levels.count() } })
			expect(all.all_levels).to.equal(true)
		end)

		it("первый буквёнок и все 33", function()
			expect(Badges.earned({ letters = learned(1) }).first_pet).to.equal(true)
			expect(Badges.earned({ letters = learned(32) }).all_pets).to.equal(nil)
			expect(Badges.earned({ letters = learned(Letters.count()) }).all_pets).to.equal(true)
		end)

		it("все сундуки — только когда открыт каждый", function()
			local inventory = {}
			for _, chest in Chests.all do
				table.insert(inventory, chest.itemId)
			end
			expect(Badges.earned({ inventory = inventory }).all_chests).to.equal(true)
			table.remove(inventory)
			expect(Badges.earned({ inventory = inventory }).all_chests).to.equal(nil)
		end)

		it("ключи значков уникальны", function()
			local seen = {}
			for _, badge in Badges.LIST do
				expect(seen[badge.key]).to.equal(nil)
				seen[badge.key] = true
			end
		end)
	end)
end
