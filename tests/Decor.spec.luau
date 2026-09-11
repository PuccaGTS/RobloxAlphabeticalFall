--!nocheck
--[[
	Декор площади. Проверяем то, что иначе увидит ребёнок, а не мы:
	дерево перед порталом, лавочка внутри куста, клумба за краем плитки.

	Расстановка считается формулами, и любая правка радиусов способна тихо
	сдвинуть половину предметов — тесты здесь именно для этого.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Decor = require(Shared.Config.Decor)
local Base = require(Shared.Config.Base)

local function footprint(item, scale)
	return math.max(item.size.X, item.size.Z) / 2 * (scale or 1)
end

local function countOf(id)
	local count = 0
	for _, placement in Decor.placements do
		if placement.id == id then
			count += 1
		end
	end
	return count
end

return function()
	describe("Config: каталог декора", function()
		it("id уникальны и у каждого предмета есть размер", function()
			local seen = {}
			for _, item in Decor.items do
				expect(seen[item.id]).to.equal(nil)
				seen[item.id] = true
				expect(item.size.X > 0).to.equal(true)
				expect(item.size.Y > 0).to.equal(true)
				expect(item.size.Z > 0).to.equal(true)
				expect(#item.title > 0).to.equal(true)
			end
		end)

		--[[
			Размер-ориентир не бывает «примерно с площадь»: по нему строится заглушка,
			и предмет крупнее двадцати студов в основании перекрывает проход целиком.
		]]
		it(
			"ни один предмет не крупнее двадцати студов в основании",
			function()
				for _, item in Decor.items do
					expect(math.max(item.size.X, item.size.Z) <= 20).to.equal(true)
				end
			end
		)

		it(
			"сквозь низкое ребёнок проходит, высокое обходит",
			function()
				for _, item in Decor.items do
					-- Куст и клумба ниже пояса: заставлять их обходить незачем
					if item.size.Y <= 2.5 then
						expect(item.collide).to.equal(false)
					end
				end
			end
		)
	end)

	describe("Config: расстановка декора", function()
		it("каждая точка ссылается на предмет каталога", function()
			for _, placement in Decor.placements do
				if Decor.get(placement.id) == nil then
					error(
						`в расстановке предмет «{placement.id}», которого нет в каталоге`
					)
				end
			end
		end)

		--[[
			Главный тест этого файла. Порталы, пады и точка появления — места, куда
			ребёнок приходит ногами. Дерево, вставшее перед входом в мир, — это
			ребёнок, который туда не пошёл, потому что не увидел, куда идти.
		]]
		it(
			"ничто не стоит перед порталами, падами и спавном",
			function()
				for _, placement in Decor.placements do
					local item = Decor.expect(placement.id)
					local clear, why =
						Decor.isClear(placement.x, placement.z, footprint(item, placement.scale))
					if not clear then
						error(
							`«{item.title}» в точке {math.floor(placement.x)}, {math.floor(
								placement.z
							)} загораживает: {why}`
						)
					end
				end
			end
		)

		it("предметы не растут друг из друга", function()
			for i = 1, #Decor.placements do
				for j = i + 1, #Decor.placements do
					local a, b = Decor.placements[i], Decor.placements[j]
					local itemA, itemB = Decor.expect(a.id), Decor.expect(b.id)
					local distance = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
					local needed = footprint(itemA, a.scale) + footprint(itemB, b.scale)
					if distance < needed then
						error(
							`«{itemA.title}» и «{itemB.title}» стоят в {math.floor(distance)} студах, а нужно {math.floor(
								needed
							)}`
						)
					end
				end
			end
		end)

		it("парк кончается там, где начинаются дома детей", function()
			for _, placement in Decor.placements do
				local item = Decor.expect(placement.id)
				local distance = math.sqrt(placement.x ^ 2 + placement.z ^ 2)
				expect(distance + footprint(item, placement.scale) <= Decor.MAX_RADIUS).to.equal(true)
				expect(Decor.MAX_RADIUS < Base.RING_RADIUS).to.equal(true)
			end
		end)

		--[[
			Плитка площади на полстуда выше травы. Предмет, поставленный по высоте
			площади, но стоящий на траве, висит в воздухе — и наоборот, тонет.
		]]
		it("высота земли под предметом берётся по месту", function()
			expect(Decor.groundY(0, 0)).to.equal(1.6)
			expect(Decor.groundY(Base.PLAZA_RADIUS + 20, 0)).to.equal(1)
		end)

		--[[
			Точки, попавшие на пад, отбрасываются молча — и на этом можно потерять
			половину декора, не заметив. Поэтому проверяем, что ключевое всё-таки
			встало: пустая площадь выглядит как недоделанная игра.
		]]
		it("площадь не осталась пустой", function()
			expect(#Decor.placements >= 20).to.equal(true)
			expect(countOf("fountain")).to.equal(1)
			expect(countOf("bench")).to.equal(2)
			expect(countOf("lamp")).to.equal(2)

			local trees = countOf("tree_pine") + countOf("tree_round")
			expect(trees >= 8).to.equal(true)
		end)
	end)

	describe("Decor.isClear", function()
		it(
			"середина портала занята, дальний угол площади свободен",
			function()
				expect(Decor.isClear(-16, -6, 1)).to.equal(false)
				expect(Decor.isClear(0, 26, 1)).to.equal(false)
				expect(Decor.isClear(46, -40, 1)).to.equal(true)
			end
		)

		it(
			"крупный предмет не влезает там, где влезает мелкий",
			function()
				-- В шаге от запретной зоны спавна, сбоку от падов: цветок помещается, фонтан уже нет
				expect(Decor.isClear(-15.5, 20, 1)).to.equal(true)
				expect(Decor.isClear(-15.5, 20, 8)).to.equal(false)
			end
		)

		it("дорожки к домам тоже нельзя загораживать", function()
			local clear, why = Decor.isClear(Base.PLAZA_RADIUS + 8, 0, 1)
			expect(clear).to.equal(false)
			expect(string.find(why, "дорожка")).to.be.ok()
		end)
	end)
end
