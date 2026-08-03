--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Shop = require(Shared.Config.Shop)
local Economy = require(Shared.Config.Economy)

return function()
	describe("Config: магазин", function()
		it("id совпадает с ключом таблицы", function()
			for id, item in Shop.all do
				expect(item.id).to.equal(id)
			end
		end)

		it("у предмета ровно один способ получения", function()
			for _, id in Shop.ids() do
				local item = Shop.expect(id)
				local ways = 0
				if item.price then
					ways += 1
				end
				if item.robuxProduct then
					ways += 1
				end
				if item.grantedBy then
					ways += 1
				end
				expect(ways).to.equal(1)
			end
		end)

		it("категория предмета известна", function()
			for _, id in Shop.ids() do
				expect(table.find(Shop.CATEGORIES, Shop.expect(id).category)).to.be.ok()
			end
		end)

		it("цена попадает в свой ценовой тир", function()
			for _, id in Shop.ids() do
				local item = Shop.expect(id)
				if item.price then
					local tier = Economy.PRICE_TIERS[item.tier]
					expect(tier).to.be.ok()
					expect(item.price >= tier.min).to.equal(true)
					expect(item.price <= tier.max).to.equal(true)
				end
			end
		end)

		it("витрина отсортирована от дешёвого к дорогому", function()
			local ids = Shop.ids()
			for index = 2, #ids do
				local prev = Shop.expect(ids[index - 1]).price or math.huge
				local current = Shop.expect(ids[index]).price or math.huge
				expect(prev <= current).to.equal(true)
			end
		end)

		it("самый дешёвый предмет по карману после первого испытания", function()
			-- принцип из docs/04-ECONOMY.md: первая покупка в первые пять минут
			local cheapest = Shop.expect(Shop.ids()[1]).price
			expect(cheapest <= Economy.rewardForChallenge(2)).to.equal(true)
		end)

		it("у каждого предмета есть чем его показать", function()
			for _, id in Shop.ids() do
				local item = Shop.expect(id)
				expect(#item.icon > 0).to.equal(true)
				expect(item.visual ~= nil or item.trail ~= nil).to.equal(true)
			end
		end)

		it("носимый предмет собран больше чем из одной детали", function()
			-- из одного куба не получается ни кепка, ни корона — получается куб на голове
			for _, id in Shop.ids() do
				local item = Shop.expect(id)
				if item.visual then
					expect(#item.visual >= 2).to.equal(true)
					for _, piece in item.visual do
						expect(typeof(piece.size)).to.equal("Vector3")
						expect(typeof(piece.offset)).to.equal("CFrame")
					end
				end
			end
		end)

		it("в срезе MVP есть предметы всех категорий", function()
			for _, category in Shop.CATEGORIES do
				local found = false
				for _, id in Shop.ids() do
					if Shop.expect(id).category == category then
						found = true
						break
					end
				end
				expect(found).to.equal(true)
			end
		end)
	end)
end
