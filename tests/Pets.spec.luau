--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Pets = require(Shared.Logic.Pets)
local MasteryRules = require(Shared.Logic.MasteryRules)
local Letters = require(Shared.Config.Letters)
local Shop = require(Shared.Config.Shop)

local function lettersWith(statuses)
	local letters = {}
	for letterId, mastery in statuses do
		local progress = MasteryRules.newProgress(0)
		progress.mastery = mastery
		letters[letterId] = progress
	end
	return letters
end

return function()
	describe("Pets — кто есть", function()
		it("буквёнок есть только у освоенной буквы", function()
			local letters = lettersWith({ a = 3, b = 2, v = 1 })
			expect(Pets.isOwned(letters, "a")).to.equal(true)
			expect(Pets.isOwned(letters, "b")).to.equal(false)
			expect(Pets.isOwned(letters, "v")).to.equal(false)
			expect(Pets.isOwned(letters, "g")).to.equal(false)
		end)

		it("список — по алфавиту, а не по порядку освоения", function()
			local letters = lettersWith({ m = 3, a = 3, ya = 3, b = 1 })
			local owned = Pets.owned(letters)
			expect(table.concat(owned, ",")).to.equal("a,m,ya")
		end)

		it("мусор вместо букв не даёт питомцев", function()
			expect(#Pets.owned(nil)).to.equal(0)
			expect(#Pets.owned({ a = "освоена" })).to.equal(0)
			expect(Pets.isOwned(lettersWith({ a = 3 }), "нет такой")).to.equal(false)
			expect(Pets.isOwned(lettersWith({ a = 3 }), 42)).to.equal(false)
		end)

		-- docs/17-CONTENT-PLAN.md § 4: питомцы не продаются, иначе связка «учился → получил» ломается.
		it("буквят нет в магазине", function()
			for _, item in Shop.all do
				expect(item.category).never.to.equal("pet")
			end
		end)
	end)

	describe("Pets — кто летает", function()
		it("чистка выкидывает чужих, повторы и лишних", function()
			local letters = lettersWith({ a = 3, b = 3 })
			expect(#Pets.sanitizeEquipped({ "v" }, letters)).to.equal(0)
			local clean = Pets.sanitizeEquipped({ "a", "a", "b" }, letters)
			expect(#clean).to.equal(Pets.SLOTS)
			expect(clean[1]).to.equal("a")
			expect(#Pets.sanitizeEquipped("мусор", letters)).to.equal(0)
		end)

		it("первый буквёнок сразу вылетает к ребёнку", function()
			local letters = lettersWith({ a = 3 })
			local equipped = Pets.afterMastered({}, letters, "a")
			expect(equipped[1]).to.equal("a")
		end)

		-- Любимца на новичка молча не меняем: слот занят — новый ждёт на Башне.
		it("занятый слот не отдаём новичку", function()
			local letters = lettersWith({ a = 3, b = 3 })
			local equipped = Pets.afterMastered({ "a" }, letters, "b")
			expect(#equipped).to.equal(1)
			expect(equipped[1]).to.equal("a")
		end)

		it("выбрать можно только своего", function()
			local letters = lettersWith({ a = 3, b = 2 })
			expect(Pets.choose(letters, "a")[1]).to.equal("a")
			expect(Pets.choose(letters, "b")).to.equal(nil)
			expect(Pets.choose(letters, nil)).to.equal(nil)
		end)

		it("буквёнок есть у каждой из 33 букв", function()
			local all = {}
			for _, id in Letters.ordered() do
				all[id] = MasteryRules.MASTERED
			end
			expect(#Pets.owned(lettersWith(all))).to.equal(Letters.count())
		end)
	end)
end
