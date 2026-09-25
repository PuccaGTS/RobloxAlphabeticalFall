--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Playground = require(Shared.Config.Playground)
local Decor = require(Shared.Config.Decor)
local Base = require(Shared.Config.Base)
local Chests = require(Shared.Config.Chests)

local function flat(spot)
	local position = Playground.position(spot)
	return Vector2.new(position.X, position.Z)
end

return function()
	describe("Config: игровые места парка", function()
		it("мест не меньше шести и все разные", function()
			local seen = {}
			for _, spot in Playground.spots do
				expect(seen[spot.id]).to.equal(nil)
				seen[spot.id] = true
			end
			expect(#Playground.spots >= 6).to.equal(true)
		end)

		it("стоят в парке: не на площади и не на участках", function()
			for _, spot in Playground.spots do
				local distance = flat(spot).Magnitude
				expect(distance - spot.radius >= Base.PLAZA_RADIUS + 8).to.equal(true)
				expect(distance + spot.radius <= Decor.MAX_RADIUS).to.equal(true)
			end
		end)

		it("не налезают друг на друга", function()
			for i, a in Playground.spots do
				for j, b in Playground.spots do
					if i < j then
						expect((flat(a) - flat(b)).Magnitude >= a.radius + b.radius).to.equal(true)
					end
				end
			end
		end)

		it("не стоят на дорожках, сундуках и падах", function()
			for _, spot in Playground.spots do
				for _, zone in Decor.zones do
					local own = string.find(zone.why, "игровое место", 1, true) ~= nil
					-- Сундук, спрятанный в самом месте (Тайный сад), — его часть, а не помеха.
					for _, chest in Chests.all do
						if chest.insideSpot == spot.id and zone.why == `сундук {chest.id}` then
							own = true
						end
					end
					if not own then
						local distance = (flat(spot) - zone.center).Magnitude
						if distance < spot.radius + zone.radius then
							error(`{spot.id} налезает на зону «{zone.why}»`)
						end
					end
				end
			end
		end)

		it("декор обходит игровые места", function()
			for _, placement in Decor.placements do
				for _, spot in Playground.spots do
					local distance = (Vector2.new(placement.x, placement.z) - flat(spot)).Magnitude
					expect(distance >= spot.radius).to.equal(true)
				end
			end
		end)

		it("в лабиринте до флажка можно дойти от входа", function()
			local rows = Playground.MAZE
			local height, width = #rows, #rows[1]
			local function at(r, c)
				return string.sub(rows[r], c, c)
			end
			local queue, seen = {}, {}
			for c = 1, width do
				if at(1, c) ~= "#" then
					table.insert(queue, { 1, c })
				end
			end
			local found = false
			while #queue > 0 do
				local cell = table.remove(queue, 1)
				local key = cell[1] * 100 + cell[2]
				if not seen[key] then
					seen[key] = true
					if at(cell[1], cell[2]) == "*" then
						found = true
					end
					for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local r, c = cell[1] + d[1], cell[2] + d[2]
						if r >= 1 and r <= height and c >= 1 and c <= width and at(r, c) ~= "#" then
							table.insert(queue, { r, c })
						end
					end
				end
			end
			expect(found).to.equal(true)
		end)
	end)
	describe("Зимняя полянка", function()
		it(
			"каток помещается на снежном круге, а круг — в своём месте",
			function()
				expect(Playground.ICE_RADIUS + 2 < Playground.WINTER_RADIUS).to.equal(true)
				expect(Playground.WINTER_RADIUS <= Playground.expect("winter").radius).to.equal(true)
				expect(Playground.SKATE_GRIP > 0.2).to.equal(true)
			end
		)
	end)

	describe("Бобовый стебель", function()
		local leaves = Playground.beanLeaves()

		it(
			"каждый лист в прыжке от прошлого, кроме того, куда только со стручка",
			function()
				for index = 2, #leaves do
					local leaf = leaves[index]
					local previous = leaves[index - 1]
					-- Настоящий прыжок, но не дальше, чем берёт персонаж с разбега.
					expect(leaf.gap >= 1 and leaf.gap <= 4.5).to.equal(true)
					if leaf.kind == "high" then
						expect(previous.kind).to.equal("pod")
						-- Обычным прыжком не достать, стручок подбрасывает выше с запасом.
						expect(leaf.rise > Playground.BEAN_JUMP).to.equal(true)
						-- Но не выше, чем нужно: над стручком — небо, а не дно острова.
						local podRise = Playground.beanPodRise()
						expect(podRise > leaf.rise + 2).to.equal(true)
						expect(podRise < leaf.rise + 6).to.equal(true)
						expect(previous.radius - previous.size / 2 > Playground.BEAN_ISLAND - 0.5).to.equal(
							true
						)
					else
						local sway = if leaf.kind == "float" or previous.kind == "float"
							then Playground.BEAN_FLOAT
							else 0
						expect(leaf.rise + sway <= Playground.BEAN_JUMP - 1.5).to.equal(true)
					end
				end
			end
		)

		it(
			"под островом голова не стукается, последний лист — снаружи",
			function()
				local underside = Playground.BEAN_TOP - Playground.BEAN_ISLAND_THICK
				for _, leaf in leaves do
					if leaf.radius - leaf.size / 2 < Playground.BEAN_ISLAND + 0.5 then
						expect(leaf.y + 6 < underside).to.equal(true)
					end
				end
				local last = leaves[#leaves]
				expect(last.radius - last.size / 2 > Playground.BEAN_ISLAND).to.equal(true)
				expect(Playground.BEAN_TOP - last.y <= Playground.BEAN_JUMP - 1.5).to.equal(true)
			end
		)

		it("гнездо одно и стоит на середине пути", function()
			local nests = 0
			for _, leaf in leaves do
				if leaf.kind == "nest" then
					nests += 1
					expect(leaf.y > Playground.BEAN_TOP * 0.3 and leaf.y < Playground.BEAN_TOP * 0.6).to.equal(
						true
					)
				end
			end
			expect(nests).to.equal(1)
		end)

		it(
			"сундук на острове, остров не налезает на соседние места",
			function()
				local spot = Playground.expect("beanstalk")
				local chest = Chests.get("chest_sky")
				expect(chest.height).to.equal(Playground.BEAN_TOP)
				local offset = (Chests.position(chest) - Playground.position(spot)).Magnitude
				expect(offset + 2 < Playground.BEAN_ISLAND).to.equal(true)
				for _, other in Playground.spots do
					if other.id ~= spot.id then
						local distance = (flat(other) - flat(spot)).Magnitude
						expect(distance > Playground.BEAN_ISLAND + 4 + other.radius).to.equal(true)
					end
				end
			end
		)
	end)

	describe("Playground: азбука-дорожка", function()
		local Letters = require(Shared.Config.Letters)
		local spec = Playground.ABC
		it(
			"по плитке на каждую букву, змейкой без разрывов и внутри места",
			function()
				local total = 0
				for _, count in spec.rows do
					total += count
				end
				expect(total).to.equal(#Letters.ordered())
				local spot = Playground.expect("abcpath")
				local previous
				for order = 1, total do
					local at = Playground.abcTile(order)
					expect(Vector2.new(at.X, at.Z).Magnitude + spec.tile / 2 < spot.radius).to.equal(true)
					if previous then
						-- Следующая буква — соседняя плитка: вдоль ряда или в соседний ряд.
						local step = (at - previous).Magnitude
						expect(step <= math.max(spec.pitch, spec.rowGap) + 0.01).to.equal(true)
						expect(step >= spec.tile + 0.5).to.equal(true)
					end
					previous = at
				end
			end
		)
	end)

	describe("Playground: грот с кристаллами", function()
		local Chests = require(Shared.Config.Chests)
		local spec = Playground.GROTTO
		local spot = Playground.expect("grotto")

		it("сундук внутри грота, у дальней стены", function()
			local chest
			for _, candidate in Chests.all do
				if candidate.id == "chest_grotto" then
					chest = candidate
				end
			end
			expect(chest).to.be.ok()
			expect(chest.insideSpot).to.equal("grotto")
			local centre = Playground.position(spot)
			local position = Chests.position(chest)
			local offset = Vector2.new(position.X - centre.X, position.Z - centre.Z).Magnitude
			expect(offset < spec.radius - 3).to.equal(true)
			-- Дальше от площади, чем центр грота: у задней стены, а не у входа.
			expect(Vector2.new(position.X, position.Z).Magnitude > spot.distance).to.equal(true)
		end)

		it(
			"кристаллы не загораживают вход и сундук, у каждого своя нота",
			function()
				local notes = {}
				for index, degrees in spec.crystals do
					local a = math.rad(degrees)
					-- Вход на −90°: до него от кристалла больше полуширины проёма с запасом.
					local fromDoor =
						math.abs(math.deg(math.atan2(math.sin(a + math.pi / 2), math.cos(a + math.pi / 2))))
					expect(fromDoor > 30).to.equal(true)
					local at = Vector2.new(math.cos(a), math.sin(a)) * spec.crystalRing
					expect((at - Vector2.new(0, spec.chest)).Magnitude > 3.5).to.equal(true)
					notes[(index - 1) % #Playground.NOTE_SPEEDS + 1] = true
				end
				expect(#spec.crystals <= #Playground.NOTE_SPEEDS).to.equal(true)
				expect(spec.crystalRing < spec.radius).to.equal(true)
				expect(spot.radius >= spec.radius + 5).to.equal(true)
			end
		)
	end)
end
