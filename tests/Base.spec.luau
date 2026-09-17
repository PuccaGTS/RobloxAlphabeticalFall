--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Base = require(Shared.Config.Base)

return function()
	describe("Config: участок", function()
		it("десять категорий по четыре уровня", function()
			expect(#Base.CATEGORIES).to.equal(10)
			for _, id in Base.ids() do
				expect(Base.maxLevel(id)).to.equal(4)
				expect(#Base.expect(id).levels).to.equal(4)
			end
		end)

		--[[
			Дом, крыша, двор и забор — сам участок; мебель и декор — обстановка
			(docs/15-HOME-BASE.md § 3). Без последних двух двор остаётся голым
			навсегда, сколько бы ребёнок ни учился.
		]]
		it("мебель и декор двора заведены", function()
			for _, id in { "furniture", "decor" } do
				local category = Base.expect(id)
				expect(#category.prices).to.equal(4)
				expect(category.prices[1] <= 30).to.equal(true)
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
			Пады улучшений стоят в один ряд у калитки, и ряд обязан влезть в участок:
			пад, уехавший за забор, ребёнок просто не найдёт. У наборов пады стоят
			у своих мест, в ряду остаются шесть. Раскладку делает BaseService,
			числа живут в конфиге.
		]]
		it("ряд падов улучшений влезает в участок", function()
			expect(#Base.rowIds()).to.equal(6)
			local row = (#Base.rowIds() - 1) * Base.PAD_STEP + Base.PAD_WIDTH
			expect(row <= Base.PLOT_SIZE).to.equal(true)
			expect(Base.PAD_STEP > Base.PAD_WIDTH).to.equal(true)
		end)

		--[[
			Полный участок стоит около 8500 ⭐ (docs/15-HOME-BASE.md § 6) — это
			примерно вся игра целиком. Дешевле — дом достроится за неделю и перестанет
			быть поводом возвращаться; дороже — станет недостижимым.
		]]
		it(
			"весь участок стоит около восьми с половиной тысяч",
			function()
				local total = Base.totalPrice()
				expect(total >= 8000).to.equal(true)
				expect(total <= 9000).to.equal(true)
			end
		)
	end)

	--[[
		Участок тесный: дом, комнаты, Башня, флаги, шпили, мебель и декор уже
		стоят на своих местах, и наборы вписаны между ними. Сдвинули одно число —
		тыква встала в комнату букв, и заметит это ребёнок, а не мы.
		Прямоугольники ниже — то, что строит BaseService помимо наборов,
		в координатах участка (−Z к площади).
	]]
	describe("Config: места наборов на участке", function()
		local HALF = Base.PLOT_SIZE / 2
		local ROW_HALF = (#Base.rowIds() - 1) * Base.PAD_STEP / 2 + Base.PAD_WIDTH / 2
		local PAD_HALF = Base.PAD_WIDTH / 2
		local RESERVED = {
			{ "дом и комнаты", -12, -8, 12, 15 },
			-- Сама Башня круглая — она в RESERVED_CIRCLES, здесь её табличка.
			{ "табличка Башни", -17, 19.4, -7, 20.2 },
			{ "дорожка и фонтан", -4, -HALF, 4, -8 },
			{ "ряд падов", -ROW_HALF, -HALF + 5 - PAD_HALF, ROW_HALF, -HALF + 5 + PAD_HALF },
			{ "мебель", 8, -13, 16, 7 },
			{ "шарики и фонарики", -12, -13, -4, -1 },
			{ "качели", -16, 5, -10, 7 },
			{ "флаги уровней букв", HALF - 4.5, -12.5, HALF, 13.5 },
			{ "флаги уровней математики", -HALF, -12.5, -HALF + 4.5, 13.5 },
			{ "шпили", HALF - 9, HALF - 16.5, HALF - 5, HALF - 5.5 },
			{ "кусты справа от калитки", 19, -HALF, HALF, -HALF + 4.5 },
			{ "кусты слева от калитки", -HALF, -HALF, -19, -HALF + 4.5 },
		}

		-- Круглые постройки: прямоугольник вокруг спирали Башни задел бы огород и площадку.
		local RESERVED_CIRCLES = {
			{ "Башня", -16.5, 14.5, 4.4 },
		}

		local function circleHitsRect(x, z, r, rect)
			local nx = math.clamp(x, rect[2], rect[4])
			local nz = math.clamp(z, rect[3], rect[5])
			return (x - nx) ^ 2 + (z - nz) ^ 2 < r * r
		end

		local function sets()
			local list = {}
			for _, category in Base.CATEGORIES do
				if category.spots then
					table.insert(list, category)
				end
			end
			return list
		end

		it("у всех четырёх наборов есть места и пад", function()
			expect(#sets()).to.equal(4)
			for _, category in sets() do
				expect(#category.spots).to.equal(#category.levels)
				expect(category.pad).to.be.ok()
			end
		end)

		it("места и пады внутри забора", function()
			for _, category in sets() do
				for _, spot in category.spots do
					expect(math.abs(spot.x) + spot.r <= HALF - 1).to.equal(true)
					expect(math.abs(spot.z) + spot.r <= HALF).to.equal(true)
				end
				expect(math.abs(category.pad.X) + PAD_HALF <= HALF - 1).to.equal(true)
				expect(math.abs(category.pad.Y) + PAD_HALF <= HALF - 1).to.equal(true)
			end
		end)

		it("места не задевают дом, Башню, флаги и декор", function()
			for _, category in sets() do
				for level, spot in category.spots do
					for _, rect in RESERVED do
						if circleHitsRect(spot.x, spot.z, spot.r, rect) then
							error(`{category.id}[{level}] задевает «{rect[1]}»`)
						end
					end
					for _, circle in RESERVED_CIRCLES do
						if
							(Vector2.new(spot.x, spot.z) - Vector2.new(circle[2], circle[3])).Magnitude
							< spot.r + circle[4]
						then
							error(`{category.id}[{level}] задевает «{circle[1]}»`)
						end
					end
				end
			end
		end)

		it("места наборов и пады не налезают друг на друга", function()
			local circles = {}
			local pads = {}
			for _, category in sets() do
				for level, spot in category.spots do
					table.insert(circles, { `{category.id}[{level}]`, spot })
				end
				local pad = category.pad
				table.insert(pads, {
					`пад {category.id}`,
					pad.X - PAD_HALF,
					pad.Y - PAD_HALF,
					pad.X + PAD_HALF,
					pad.Y + PAD_HALF,
				})
			end
			for i, a in circles do
				for j = i + 1, #circles do
					local b = circles[j]
					local distance = math.sqrt((a[2].x - b[2].x) ^ 2 + (a[2].z - b[2].z) ^ 2)
					if distance < a[2].r + b[2].r then
						error(`{a[1]} налезает на {b[1]}`)
					end
				end
				for _, pad in pads do
					if circleHitsRect(a[2].x, a[2].z, a[2].r, pad) then
						error(`{a[1]} стоит на «{pad[1]}»`)
					end
				end
			end
			for _, pad in pads do
				for _, rect in RESERVED do
					local overlap = pad[2] < rect[4]
						and pad[4] > rect[2]
						and pad[3] < rect[5]
						and pad[5] > rect[3]
					if overlap then
						error(`{pad[1]} стоит на «{rect[1]}»`)
					end
				end
			end
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
