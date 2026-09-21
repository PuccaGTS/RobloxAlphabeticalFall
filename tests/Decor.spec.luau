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
					if not item.horizon then
						expect(math.max(item.size.X, item.size.Z) <= 20).to.equal(true)
					end
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

	--[[
		Предмет без эскиза держится только на файле модели. Файл потеряли
		или переименовали — в мире встанет серая коробка вместо утки.
	]]
	describe("Config: модели из файлов", function()
		it(
			"у предмета с пометкой file модель лежит в assets/models/decor",
			function()
				local assets = ReplicatedStorage:FindFirstChild("Assets")
				local folder = assets and assets:FindFirstChild("decor")
				for _, item in Decor.items do
					if item.file and not (folder and folder:FindFirstChild(item.id, true)) then
						error(`нет файла модели для «{item.title}» ({item.id})`)
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
			expect(countOf("bench") >= 2).to.equal(true)
			expect(countOf("lamp") >= 2).to.equal(true)

			local trees = countOf("tree_pine") + countOf("tree_round")
			expect(trees >= 8).to.equal(true)
		end)
	end)

	--[[
		Мир назвали пустым: между площадью и домами лежала голая трава. Тест держит,
		что парк есть и что он не сбился в одну кучу: в каждой четверти своё.
	]]
	describe("Config: парк между площадью и домами", function()
		it("в парке много всего и в каждой четверти", function()
			local quarters = { 0, 0, 0, 0 }
			local park = 0
			for _, placement in Decor.placements do
				local distance = math.sqrt(placement.x ^ 2 + placement.z ^ 2)
				if distance > Base.PLAZA_RADIUS + 15 then
					park += 1
					local angle = math.atan2(placement.z, placement.x) % (math.pi * 2)
					local quarter = math.floor(angle / (math.pi / 2)) + 1
					quarters[math.min(quarter, 4)] += 1
				end
			end
			expect(park >= 80).to.equal(true)
			for _, count in quarters do
				expect(count >= 15).to.equal(true)
			end
		end)

		it(
			"кубики с буквами и цифрами стоят на площади и в парке",
			function()
				local plazaLetters, plazaNumbers, park = 0, 0, 0
				for _, placement in Decor.placements do
					local distance = math.sqrt(placement.x ^ 2 + placement.z ^ 2)
					if placement.id == "letter_cubes" or placement.id == "number_cubes" then
						if distance <= Base.PLAZA_RADIUS then
							if placement.id == "letter_cubes" then
								plazaLetters += 1
							else
								plazaNumbers += 1
							end
						else
							park += 1
						end
					end
				end
				expect(plazaLetters >= 1).to.equal(true)
				expect(plazaNumbers >= 1).to.equal(true)
				expect(park >= 4).to.equal(true)
			end
		)

		it("вдоль дорожек к домам стоят фонари", function()
			expect(countOf("lamp") >= 16).to.equal(true)
		end)

		it("дома не стоят вплотную: между участками сад", function()
			local gap = (Base.plotPosition(1) - Base.plotPosition(2)).Magnitude - Base.PLOT_SIZE
			expect(gap >= 30).to.equal(true)
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
