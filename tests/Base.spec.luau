--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Base = require(Shared.Config.Base)

return function()
	describe("Config: участок", function()
		it("четыре категории по четыре уровня", function()
			expect(#Base.CATEGORIES).to.equal(4)
			for _, id in Base.ids() do
				expect(Base.maxLevel(id)).to.equal(4)
				expect(#Base.expect(id).levels).to.equal(4)
			end
		end)

		it("id совпадает с ключом и уровни подписаны", function()
			for _, category in Base.CATEGORIES do
				expect(Base.expect(category.id)).to.equal(category)
				for _, title in category.levels do
					expect(#title > 0).to.equal(true)
				end
			end
		end)

		--[[
			Цена каждого следующего уровня выше предыдущей. Иначе дом можно
			достроить с конца дешевле, чем с начала, и лестница улучшений теряет смысл.
		]]
		it("цены растут от уровня к уровню", function()
			for _, category in Base.CATEGORIES do
				for level = 2, #category.prices do
					expect(category.prices[level] > category.prices[level - 1]).to.equal(true)
				end
			end
		end)

		--[[
			Первое строительство обязано случиться в первый же день, как и первая
			шапка: иначе участок неделю стоит пустым и перестаёт быть целью.
		]]
		it("первый уровень по карману новичку", function()
			for _, category in Base.CATEGORIES do
				expect(category.prices[1] <= 50).to.equal(true)
			end
		end)

		--[[
			Полный участок стоит около 6000 ⭐ (docs/15-HOME-BASE.md § 6) — это
			примерно вся игра целиком. Дешевле — дом достроится за неделю и перестанет
			быть поводом возвращаться; дороже — станет недостижимым.
		]]
		it("весь участок стоит около шести тысяч", function()
			local total = Base.totalPrice()
			expect(total >= 5000).to.equal(true)
			expect(total <= 7000).to.equal(true)
		end)

		it("на последнем уровне покупать больше нечего", function()
			for _, id in Base.ids() do
				expect(Base.priceFor(id, Base.maxLevel(id))).to.equal(nil)
				expect(Base.nextTitle(id, Base.maxLevel(id))).to.equal(nil)
				expect(Base.priceFor(id, 0)).to.be.ok()
			end
		end)
	end)

	describe("Base.sanitize", function()
		it(
			"пустой участок — это нули, а не отсутствие полей",
			function()
				local fresh = Base.newProgress()
				for _, id in Base.ids() do
					expect(fresh[id]).to.equal(0)
				end
			end
		)

		it("из мусора делает пустой участок", function()
			local samples = { 5, "дом", true }
			table.insert(samples, Base.sanitize(nil))

			for _, garbage in samples do
				local clean = Base.sanitize(garbage)
				for _, id in Base.ids() do
					expect(clean[id]).to.equal(0)
				end
			end
		end)

		--[[
			Профиль приходит из DataStore, а не из наших рук: он мог быть сохранён
			билдом, где уровней было больше, или просто испорчен. Вход в игру
			на этом падать не имеет права.
		]]
		it(
			"уровень выше построенного срезается до максимума",
			function()
				local clean = Base.sanitize({ house = 99, roof = -3, yard = 2.7, fence = 0 / 0 })

				expect(clean.house).to.equal(Base.maxLevel("house"))
				expect(clean.roof).to.equal(0)
				expect(clean.yard).to.equal(2)
				expect(clean.fence).to.equal(0)
			end
		)

		it("чужие ключи не проникают в профиль", function()
			local clean = Base.sanitize({ house = 1, ["замок"] = 4, castle = 4 })

			expect(clean.house).to.equal(1)
			expect(clean["замок"]).to.equal(nil)
			expect(clean.castle).to.equal(nil)
		end)
	end)

	describe("Кольцо участков", function()
		--[[
			Двадцать участков на двадцать мест сервера: участок гарантирован
			каждому ребёнку, очередей и «место занято» не бывает.
		]]
		it("участков столько же, сколько мест на сервере", function()
			expect(Base.PLOT_COUNT).to.equal(20)
		end)

		--[[
			Главная проверка кольца: соседние участки не налезают друг на друга.
			Радиус считается из числа участков, и этот тест — та причина,
			по которой его нельзя заменить константой «на глаз».
		]]
		it("соседние участки не пересекаются", function()
			for index = 1, Base.PLOT_COUNT do
				local nextIndex = (index % Base.PLOT_COUNT) + 1
				local gap = (Base.plotPosition(index) - Base.plotPosition(nextIndex)).Magnitude
				expect(gap >= Base.PLOT_SIZE).to.equal(true)
			end
		end)

		it("участки стоят за площадью, а не на ней", function()
			local innerEdge = Base.RING_RADIUS - Base.PLOT_SIZE / 2
			expect(innerEdge > Base.PLAZA_RADIUS).to.equal(true)
		end)

		it("земля накрывает все участки целиком", function()
			local outerEdge = Base.RING_RADIUS + Base.PLOT_SIZE / 2
			expect(Base.GROUND_SIZE / 2 >= outerEdge).to.equal(true)
		end)

		it(
			"все участки на одной высоте и на равном расстоянии от центра",
			function()
				for index = 1, Base.PLOT_COUNT do
					local position = Base.plotPosition(index)
					expect(position.Y).to.equal(0)
					expect(math.abs(position.Magnitude - Base.RING_RADIUS) < 0.001).to.equal(true)
				end
			end
		)
	end)
end
