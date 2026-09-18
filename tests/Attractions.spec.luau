--!nocheck
--[[
	Аттракционы забега и станции букв (docs/19-OBSTACLES.md § 3.4).

	Главное, что держат эти тесты: аттракцион трудный, но проходимый. Прыжок
	никогда не длиннее, чем берёт персонаж, от валуна всегда есть ниша, лава
	не забирает обе кочки ряда разом. И второе: аттракцион никому не мешает —
	ни воротам, ни станции, ни мелким элементам.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attractions = require(ReplicatedStorage.Shared.Config.Attractions)
local AttractionPlan = require(ReplicatedStorage.Shared.Logic.AttractionPlan)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)
local Levels = require(ReplicatedStorage.Shared.Config.Levels)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)
local TunnelRun = require(ReplicatedStorage.ServerChallenges.TunnelRun)
local MathGates = require(ReplicatedStorage.ServerChallenges.MathGates)

local function plans(id)
	local list = {}
	for heat = 1, 5 do
		for seed = 1, 40 do
			table.insert(list, AttractionPlan.make(id, heat, Random.new(seed * 7 + heat)))
		end
	end
	return list
end

local function levelSpecs()
	local list = {}
	for _, level in Levels.all do
		for difficulty = 1, 5, 2 do
			table.insert(list, TunnelRun.Build(nil, Letters.ordered(), difficulty, level.index))
		end
	end
	return list
end

return function()
	describe("Config: аттракционы", function()
		it("у каждого параметра ровно пять значений жара", function()
			for id, block in Attractions.HEAT do
				expect(Attractions.get(id)).to.be.ok()
				for _, values in block do
					expect(#values).to.equal(5)
				end
			end
		end)

		it(
			"каждый аттракцион умеет и план, и уровень появления",
			function()
				for _, id in Attractions.ids() do
					local meta = Attractions.expect(id)
					expect(meta.fromLevel >= 1 and meta.fromLevel <= Levels.count()).to.equal(true)
					local plan = AttractionPlan.make(id, 3, Random.new(1))
					expect(plan.length > 0).to.equal(true)
				end
			end
		)

		it("на первом уровне уже есть что проходить", function()
			expect(#Attractions.unlocked(1) >= 2).to.equal(true)
		end)

		it(
			"у каждого уровня жар от одного до пяти и хотя бы один аттракцион",
			function()
				for _, level in Levels.all do
					local heat, count = Levels.attractions(level.index)
					expect(heat >= 1 and heat <= 5).to.equal(true)
					expect(count >= 1).to.equal(true)
				end
			end
		)
	end)

	describe("AttractionPlan: проходимость", function()
		--[[
			Прыжок персонажа берёт около одиннадцати студов с разбега. Щель шире
			MAX_GAP ребёнку не по силам — такой в игре не бывает никогда.
		]]
		it(
			"островки: каждый прыжок по силам и не вверх выше MAX_RISE",
			function()
				for _, plan in plans("islands") do
					local previous = nil
					for _, island in plan.islands do
						local radius = island.size / 2
						local gap
						if previous then
							local centers =
								Vector2.new(island.x - previous.x, island.z - previous.z).Magnitude
							gap = centers - radius - previous.size / 2
							expect(island.y - previous.y <= Attractions.MAX_RISE).to.equal(true)
						else
							gap = island.z - radius
						end
						expect(gap > 1).to.equal(true)
						expect(gap <= Attractions.MAX_GAP + 0.01).to.equal(true)
						expect(math.abs(island.x) + radius <= Tunnel.WIDTH / 2).to.equal(true)
						previous = island
					end
					local tail = plan.length - (previous.z + previous.size / 2)
					expect(tail > 1 and tail <= Attractions.MAX_GAP).to.equal(true)
				end
			end
		)

		it("островки: чем жарче, тем шире прыжки", function()
			expect(Attractions.param("islands", "gapMax", 5) > Attractions.param("islands", "gapMax", 1)).to.equal(
				true
			)
			expect(Attractions.param("islands", "size", 5) < Attractions.param("islands", "size", 1)).to.equal(
				true
			)
		end)

		it("лава: соседние кочки в прыжке, и выход тоже", function()
			for _, plan in plans("lava") do
				local rows = {}
				for _, stone in plan.stones do
					rows[stone.row] = stone.z
				end
				local previous = 0
				for row = 1, #rows do
					local gap = rows[row] - Attractions.LAVA_STONE / 2 - previous
					expect(gap <= Attractions.MAX_GAP).to.equal(true)
					previous = rows[row] + Attractions.LAVA_STONE / 2
				end
				expect(plan.length - previous <= Attractions.MAX_GAP).to.equal(true)
			end
		end)

		--[[
			В любой момент в каждом ряду хотя бы одна кочка над лавой: стоять
			на месте нельзя, но шагнуть есть куда всегда.
		]]
		it("лава: ряд никогда не уходит в лаву целиком", function()
			for _, plan in plans("lava") do
				local byRow = {}
				for _, stone in plan.stones do
					byRow[stone.row] = byRow[stone.row] or {}
					table.insert(byRow[stone.row], stone)
				end
				for _, stones in byRow do
					for t = 0, plan.period, 0.05 do
						local up = false
						for _, stone in stones do
							if stone.steady or (t + stone.phase) % plan.period < plan.solid then
								up = true
							end
						end
						expect(up).to.equal(true)
					end
				end
			end
		end)

		it(
			"валуны: от ниши до ниши успеваешь добежать между валунами",
			function()
				for _, plan in plans("boulders") do
					expect(#plan.niches >= 3).to.equal(true)
					local previous = 0
					for _, niche in plan.niches do
						local run = (niche.z - previous) / Tunnel.WALK_SPEED
						expect(run < plan.interval * 0.5).to.equal(true)
						previous = niche.z
					end
					-- От последней ниши до выхода тоже.
					expect((plan.length - previous) / Tunnel.WALK_SPEED < plan.interval * 0.5).to.equal(true)
					-- Валун медленнее ребёнка: от него можно убежать к нише.
					expect(plan.speed < Tunnel.WALK_SPEED).to.equal(true)
				end
			end
		)

		it("валуны: в нише валун не достаёт", function()
			local radius = Attractions.BOULDER_DIAMETER / 2
			local nicheCenter = Attractions.BOULDER_CORRIDOR / 2 + Attractions.NICHE_DEPTH / 2
			-- Корень ребёнка в середине ниши, валун катится по оси.
			expect(nicheCenter > radius + 1.3).to.equal(true)
			-- А в проходе не проскочить мимо: валун почти во всю ширину.
			expect(Attractions.BOULDER_CORRIDOR / 2 < radius + 1.3).to.equal(true)
		end)

		it("вертушка: перекладину можно перепрыгнуть", function()
			-- Прыжок поднимает на 7,7 студа, перекладина по колено.
			expect(Attractions.SPINNER_BAR_HEIGHT < 2).to.equal(true)
			for heat = 1, 5 do
				expect(Attractions.param("spinner", "period", heat) >= 4).to.equal(true)
			end
		end)

		it(
			"молоты: мостик не уже шести студов, молот достаёт до края",
			function()
				for heat = 1, 5 do
					expect(Attractions.param("hammers", "bridge", heat) >= 6).to.equal(true)
				end
				local reach = Attractions.HAMMER_ARM * math.sin(Attractions.HAMMER_SWING)
				expect(reach > Attractions.param("hammers", "bridge", 1) / 2).to.equal(true)
			end
		)

		it("по тому же генератору — тот же план", function()
			for _, id in Attractions.ids() do
				local a = AttractionPlan.make(id, 4, Random.new(99))
				local b = AttractionPlan.make(id, 4, Random.new(99))
				expect(a.length).to.equal(b.length)
			end
		end)
	end)

	describe("AttractionPlan.sequence", function()
		it("самый новый открытый идёт первым", function()
			local sequence = AttractionPlan.sequence({ "islands", "spinner", "boulders" }, 6, Random.new(3))
			expect(sequence[1]).to.equal("boulders")
			expect(#sequence).to.equal(6)
		end)

		it("один и тот же дважды подряд не встаёт", function()
			for seed = 1, 50 do
				local sequence = AttractionPlan.sequence(Attractions.unlocked(11), 12, Random.new(seed))
				for index = 2, #sequence do
					expect(sequence[index]).never.to.equal(sequence[index - 1])
				end
			end
		end)
	end)

	describe("Забег: станции и аттракционы на пути", function()
		it(
			"у каждого отрезка мира букв своя станция с буквой ворот",
			function()
				for _, spec in levelSpecs() do
					expect(#spec.params.stations).to.equal(#spec.params.gates)
					for _, station in spec.params.stations do
						local gate = spec.params.gates[station.segment]
						expect(station.letterId).to.equal(gate.targetLetter)
						expect(station.z + Tunnel.STATION_PITCH <= gate.z - Tunnel.CLEARANCE_BEFORE_GATE).to.equal(
							true
						)
						local previous = spec.params.gates[station.segment - 1]
						expect(
							station.z
								>= (if previous then previous.z else 0)
									+ Tunnel.CLEARANCE_AFTER_GATE
									- 0.001
						).to.equal(true)
					end
				end
			end
		)

		it(
			"у мира математики станций нет, а аттракционы есть",
			function()
				local spec = MathGates.Build(nil, { "a" }, 3, 3)
				expect(#(spec.params.stations or {})).to.equal(0)
				expect(#spec.params.attractions).to.equal(#spec.params.gates)
			end
		)

		it(
			"аттракционов на отрезке столько, сколько у уровня",
			function()
				for _, spec in levelSpecs() do
					local _, perSegment = Levels.attractions(spec.level)
					expect(#spec.params.attractions).to.equal(perSegment * #spec.params.gates)
				end
			end
		)

		it(
			"аттракцион не налезает ни на элементы, ни на станцию, ни на ворота",
			function()
				for _, spec in levelSpecs() do
					for _, ride in spec.params.attractions do
						local from, to = ride.flagZ - 1, ride.z + ride.length
						for _, obstacle in spec.params.obstacles do
							local oFrom = obstacle.z - Tunnel.obstacleLead(obstacle.kind)
							local oTo = obstacle.z + Tunnel.obstacleLength(obstacle.kind)
							expect(to < oFrom or from > oTo).to.equal(true)
						end
						for _, station in spec.params.stations do
							expect(to < station.z or from > station.z + Tunnel.STATION_PITCH).to.equal(true)
						end
						local gate = spec.params.gates[ride.segment]
						expect(to <= gate.z - Tunnel.CLEARANCE_BEFORE_GATE).to.equal(true)
					end
				end
			end
		)

		it("флажок стоит перед своим аттракционом", function()
			for _, spec in levelSpecs() do
				for _, ride in spec.params.attractions do
					expect(ride.flagZ < ride.z).to.equal(true)
					expect(ride.z - ride.flagZ <= Attractions.FLAG_LEAD).to.equal(true)
				end
			end
		end)

		it(
			"на первом уровне встречается самый новый аттракцион",
			function()
				local spec = TunnelRun.Build(nil, Letters.ordered(), 3, 1)
				local unlocked = Attractions.unlocked(1)
				expect(spec.params.attractions[1].id).to.equal(unlocked[#unlocked])
			end
		)

		it(
			"по тому же рецепту — те же аттракционы и станции",
			function()
				local spec = TunnelRun.Build(nil, { "a", "b", "v" }, 3, 7)
				local again = TunnelRun.Rebuild({
					challengeId = spec.challengeId,
					seed = spec.seed,
					letters = spec.letters,
					difficulty = spec.difficulty,
					level = spec.level,
					checkpoint = 1,
					savedAt = 0,
				})
				expect(#again.params.attractions).to.equal(#spec.params.attractions)
				for index, ride in spec.params.attractions do
					expect(again.params.attractions[index].id).to.equal(ride.id)
					expect(again.params.attractions[index].z).to.equal(ride.z)
				end
				for index, station in spec.params.stations do
					expect(again.params.stations[index].z).to.equal(station.z)
				end
			end
		)

		--[[
			«Бежать очень много» — было на первой живой проверке. Отрезок первого
			уровня теперь короче трёхсот студов, и пустой пробежки на нём одна клетка.
		]]
		it(
			"отрезок первого уровня не превращается в долгую пробежку",
			function()
				local spec = TunnelRun.Build(nil, Letters.ordered(), 3, 1)
				local previous = 0
				for _, gate in spec.params.gates do
					expect(gate.z - previous < 300).to.equal(true)
					previous = gate.z
				end
				expect(#spec.params.track).to.equal(#spec.params.gates * Tunnel.RUN_CELLS)
			end
		)
	end)
end
