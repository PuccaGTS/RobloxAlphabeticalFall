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

		it(
			"облачка: прыжок между рядами берётся, облако не вылезает за бортик",
			function()
				for _, plan in plans("clouds") do
					expect(plan.gap <= Attractions.MAX_GAP).to.equal(true)
					expect(plan.travel + plan.size / 2 <= Tunnel.WIDTH / 2).to.equal(true)
					local tail = plan.length - (plan.clouds[#plan.clouds].z + plan.size / 2)
					expect(tail > 1 and tail <= Attractions.MAX_GAP).to.equal(true)
				end
			end
		)

		it("облачка: соседние ряды не идут строем", function()
			for _, plan in plans("clouds") do
				for index = 2, #plan.clouds do
					local shift = math.abs(plan.clouds[index].phase - plan.clouds[index - 1].phase)
					expect(shift > 0.05).to.equal(true)
				end
			end
		end)

		it(
			"ленты: щель между лентами в прыжок, лента короче трассы",
			function()
				for _, plan in plans("belts") do
					expect(plan.gap <= Attractions.MAX_GAP).to.equal(true)
					expect(plan.span < Tunnel.WIDTH - 4).to.equal(true)
					-- Лента тащит, но не быстрее бега: кто бежит, тот перебегает.
					expect(plan.speed < 16 + 1).to.equal(true)
					expect(plan.back.speed < 12).to.equal(true)
					-- Последняя лента начинается после щели и упирается в выход.
					local lastEdge = plan.belts[#plan.belts].z + plan.depth / 2
					local backStart = plan.back.z - plan.back.length / 2
					expect(math.abs(backStart - lastEdge - plan.gap) < 1e-6).to.equal(true)
					expect(math.abs(plan.length - (plan.back.z + plan.back.length / 2)) < 1e-6).to.equal(true)
				end
			end
		)

		it("ленты: три ленты подряд в одну сторону не тянут", function()
			for _, plan in plans("belts") do
				for index = 3, #plan.belts do
					local a, b, c = plan.belts[index - 2], plan.belts[index - 1], plan.belts[index]
					expect(a.direction == b.direction and b.direction == c.direction).to.equal(false)
				end
			end
		end)

		it(
			"качели: сошедшиеся доски — в прыжок, разошедшиеся — нет",
			function()
				for _, plan in plans("swings") do
					expect(plan.near <= Attractions.MAX_GAP).to.equal(true)
					expect(plan.near + 4 * plan.reach > Attractions.MAX_GAP + 4).to.equal(true)
					for index = 2, #plan.swings do
						local a, b = plan.swings[index - 1], plan.swings[index]
						-- В противофазе: одна впереди, другая сзади.
						expect(math.abs(math.abs(b.phase - a.phase) - plan.period / 2) < 1e-6).to.equal(true)
						local closest = (b.z - a.z) - plan.board - 2 * plan.reach
						expect(math.abs(closest - plan.near) < 1e-6).to.equal(true)
					end
					-- Первая доска сходится с полом входа, последняя — с полом выхода.
					expect(math.abs(plan.swings[1].z - plan.reach - plan.board / 2 - plan.near) < 1e-6).to.equal(
						true
					)
					local last = plan.swings[#plan.swings]
					expect(math.abs(plan.length - (last.z + plan.reach + plan.board / 2 + plan.near)) < 1e-6).to.equal(
						true
					)
					expect(plan.board / 2 <= Tunnel.WIDTH / 2).to.equal(true)
				end
			end
		)

		it(
			"буквенные кочки: в каждом ряду ровно одна верная, прыжок между рядами по силам",
			function()
				for _, plan in plans("letterstones") do
					expect(plan.gap + 1 <= Attractions.MAX_GAP).to.equal(true)
					local rights, rows, previous = {}, {}, nil
					for _, stone in plan.stones do
						rows[stone.row] = (rows[stone.row] or 0) + 1
						expect(math.abs(stone.x) + plan.size / 2 <= Tunnel.WIDTH / 2).to.equal(true)
						if stone.right then
							expect(rights[stone.row]).to.equal(nil)
							rights[stone.row] = stone.x
						end
					end
					for row, count in rows do
						expect(count).to.equal(3)
						expect(rights[row]).to.be.ok()
						-- Верная соседнего ряда не дальше соседней дорожки: прыжок наискосок.
						if previous then
							expect(math.abs(rights[row] - previous) <= 9).to.equal(true)
						end
						previous = rights[row]
					end
				end
			end
		)

		it("буквенные кочки: только в мире букв", function()
			expect(table.find(Attractions.unlocked(11), "letterstones")).to.be.ok()
			expect(table.find(Attractions.unlocked(11, true), "letterstones")).to.equal(nil)
		end)

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

		it(
			"батуты: прыжки в досягаемости, толчок выше островка",
			function()
				for _, plan in plans("bounce") do
					expect(plan.gap <= Attractions.MAX_GAP).to.equal(true)
					-- Обычным прыжком (7,7 студа) на островок не попасть — только с батута.
					expect(plan.height - Attractions.BOUNCE_PAD_Y > 7.7).to.equal(true)
					local rise = plan.power * plan.power / (2 * Attractions.GRAVITY)
					expect(rise > plan.height - Attractions.BOUNCE_PAD_Y + 2).to.equal(true)
					-- Потолка у туннеля нет, но подброс не выше двух ростов бортика.
					expect(rise < Tunnel.HEIGHT * 2).to.equal(true)
					for index, pad in plan.pads do
						local island = plan.islands[index]
						expect(island.x).to.equal(pad.x)
						expect(math.abs(pad.x) + plan.travel + plan.pad / 2 <= Tunnel.WIDTH / 2).to.equal(
							true
						)
					end
				end
			end
		)

		it(
			"печеньки: в каждом ряду есть печенька, и до неё допрыгнуть",
			function()
				for _, plan in plans("cookies") do
					local rows = {}
					for _, cookie in plan.cookies do
						rows[cookie.row] = rows[cookie.row] or {}
						table.insert(rows[cookie.row], cookie)
					end
					expect(#rows[1]).to.equal(3)
					for row = 2, #rows do
						expect(#rows[row] >= 1).to.equal(true)
						-- До какой-то печеньки ряда можно допрыгнуть с какой-то печеньки прошлого.
						local best = math.huge
						for _, a in rows[row - 1] do
							for _, b in rows[row] do
								local centers = Vector2.new(a.x - b.x, a.z - b.z).Magnitude
								best = math.min(best, centers - plan.size)
							end
						end
						expect(best <= Attractions.MAX_GAP).to.equal(true)
					end
					expect(plan.gap <= Attractions.MAX_GAP).to.equal(true)
					expect(plan.hold >= 0.5).to.equal(true)
				end
			end
		)

		it(
			"топотуны: в каждом ряду всегда есть кубик наверху",
			function()
				for _, plan in plans("stompers") do
					local byRow = {}
					for _, stomper in plan.stompers do
						byRow[stomper.row] = byRow[stomper.row] or {}
						table.insert(byRow[stomper.row], stomper)
					end
					for _, row in byRow do
						expect(#row).to.equal(3)
						for t = 0, plan.period, 0.02 do
							local up = false
							for _, stomper in row do
								if
									Attractions.stomperDrop(t + stomper.phase, plan.period, plan.down) == 0
								then
									up = true
								end
							end
							expect(up).to.equal(true)
						end
					end
				end
			end
		)

		it(
			"топотуны: дрожь раньше топота, внизу кубик стоит, наверху выше головы",
			function()
				for heat = 1, 5 do
					local period = Attractions.param("stompers", "period", heat)
					local down = Attractions.param("stompers", "down", heat)
					local fallAt = period - down
					expect(Attractions.stomperDrop(fallAt - 0.01, period, down)).to.equal(0)
					expect(Attractions.stomperWarning(fallAt - 0.1, period, down)).to.equal(true)
					expect(Attractions.stomperDrop(fallAt + Attractions.STOMPER_FALL + 0.05, period, down)).to.equal(
						1
					)
					expect(down > Attractions.STOMPER_FALL + Attractions.STOMPER_RISE).to.equal(true)
				end
				-- Поднятый кубик не задевает голову: корень на трёх студах, голова ещё на 2,5.
				expect(Attractions.STOMPER_LIFT > 3 + 2.5 + 1).to.equal(true)
			end
		)

		it(
			"ветродуи: ветер слабее бега, но стоять под ним нельзя",
			function()
				for heat = 1, 5 do
					local speed = Attractions.param("wind", "speed", heat)
					local gust = Attractions.param("wind", "gust", heat)
					local bridge = Attractions.param("wind", "bridge", heat)
					-- Против ветра идти можно: он заметно слабее бега.
					expect(speed < Tunnel.WALK_SPEED * 0.8).to.equal(true)
					-- А кто не упирается и не прячется, того за порыв снесёт с мостика.
					expect(speed * gust > bridge / 2 + 2).to.equal(true)
					expect(bridge >= 5).to.equal(true)
					expect(Attractions.param("wind", "gap", heat) <= Attractions.MAX_GAP).to.equal(true)
				end
				-- За щитом прячешься целиком: корень на трёх студах, голова ещё на 2,5.
				expect(Attractions.WIND_SHELTER_HEIGHT > 3 + 2.5).to.equal(true)
			end
		)

		it(
			"ветродуи: тучки дуют по очереди то слева, то справа",
			function()
				for _, plan in plans("wind") do
					expect(#plan.zones >= 2).to.equal(true)
					for index = 2, #plan.zones do
						expect(plan.zones[index].side).to.equal(-plan.zones[index - 1].side)
					end
				end
			end
		)

		it("ветродуи: щёки надуваются раньше порыва", function()
			for heat = 1, 5 do
				local period = Attractions.param("wind", "period", heat)
				local gust = Attractions.param("wind", "gust", heat)
				local startAt = period - gust
				-- Тихо дольше, чем щёки надуваются: у тучки есть спокойное время.
				expect(startAt > Attractions.WIND_WARN + 0.5).to.equal(true)
				expect(Attractions.windGust(startAt - 0.05, period, gust)).to.equal(0)
				expect(Attractions.windWarning(startAt - 0.5, period, gust)).to.equal(true)
				expect(Attractions.windWarning(startAt + 0.5, period, gust)).to.equal(false)
				expect(Attractions.windGust(startAt + gust / 2, period, gust)).to.equal(1)
				expect(Attractions.windGust(0.1, period, gust)).to.equal(0)
			end
		end)

		it(
			"ветродуи: от щита до щита всегда есть когда пробежать",
			function()
				-- Ребёнок бежит не во всю прыть: семь десятых скорости бега.
				local speed = Tunnel.WALK_SPEED * 0.7
				for _, plan in plans("wind") do
					local function exposed(z, t)
						for _, zone in plan.zones do
							if z >= zone.from and z <= zone.to then
								if math.abs(z - zone.z) < Attractions.WIND_SHELTER / 2 then
									return false
								end
								return Attractions.windGust(t + zone.phase, plan.period, plan.gust) > 0
							end
						end
						return false
					end
					-- Где можно стоять и ждать: у флажка, за каждым щитом, на полу выхода.
					local stops = { -1 }
					for _, zone in plan.zones do
						table.insert(stops, zone.z)
					end
					table.insert(stops, plan.length + 1)
					for index = 2, #stops do
						local from, to = stops[index - 1], stops[index]
						local duration = (to - from) / speed
						local found = false
						for start = 0, plan.period, 0.05 do
							local clear = true
							for tau = 0, duration, 0.02 do
								if exposed(from + speed * tau, start + tau) then
									clear = false
									break
								end
							end
							if clear then
								found = true
								break
							end
						end
						expect(found).to.equal(true)
					end
				end
			end
		)

		it(
			"подъёмники: до каждой следующей платформы есть когда допрыгнуть",
			function()
				for _, plan in plans("lifts") do
					local function height(stop, t)
						if stop.mid then
							return Attractions.liftHeight(stop.mid, plan.travel, plan.period, stop.phase, t)
						end
						return stop.y
					end
					-- Остановки по порядку: пол у флажка, платформы, балкон.
					local stops = { { x = 0, z = -1e9, y = 0 } }
					for _, lift in plan.lifts do
						table.insert(stops, lift)
					end
					table.insert(stops, { x = 0, z = math.huge, y = plan.balcony.y, balcony = true })
					for index = 2, #stops do
						local from, to = stops[index - 1], stops[index]
						local gap
						if from.z == -1e9 then
							gap = to.z - plan.size / 2
						elseif to.balcony then
							gap = plan.balcony.from - (from.z + plan.size / 2)
						else
							gap = Vector2.new(to.x - from.x, to.z - from.z).Magnitude - plan.size
						end
						expect(gap > 1).to.equal(true)
						expect(gap <= Attractions.MAX_GAP + 0.01).to.equal(true)
						-- Окно, когда цель не выше MAX_RISE над тобой, — не меньше 0,6 с подряд.
						local best, run = 0, 0
						for t = 0, plan.period * 2, 0.02 do
							if height(to, t) - height(from, t) <= Attractions.MAX_RISE then
								run += 0.02
								best = math.max(best, run)
							else
								run = 0
							end
						end
						expect(best >= 0.6).to.equal(true)
					end
				end
			end
		)

		it(
			"подъёмники: платформы в трассе, горка не круче, балкон выше всех",
			function()
				for _, plan in plans("lifts") do
					for _, lift in plan.lifts do
						expect(math.abs(lift.x) + plan.size / 2 <= Tunnel.WIDTH / 2).to.equal(true)
					end
					-- Балкон — самое высокое место: подниматься приходится по платформам.
					local first = plan.lifts[1]
					expect(plan.balcony.y > first.mid + plan.travel).to.equal(true)
					expect(plan.balcony.y / plan.slide <= 0.6).to.equal(true)
					expect(plan.length).to.equal(plan.balcony.to + plan.slide)
				end
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

		it(
			"на буквенных кочках верная — буква отрезка, в ряду буквы не повторяются",
			function()
				local seen = 0
				for _, spec in levelSpecs() do
					for _, ride in spec.params.attractions do
						if ride.id == "letterstones" then
							seen += 1
							local target = spec.params.gates[ride.segment].targetLetter
							local rows = {}
							for _, stone in ride.stones do
								expect(Letters.get(stone.letterId)).to.be.ok()
								expect(stone.right == (stone.letterId == target)).to.equal(true)
								rows[stone.row] = rows[stone.row] or {}
								expect(rows[stone.row][stone.letterId]).to.equal(nil)
								rows[stone.row][stone.letterId] = true
							end
						end
					end
				end
				expect(seen > 0).to.equal(true)
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
			«Бежать очень много» — было на обеих живых проверках. Длина отрезка
			теперь уходит на аттракционы, где можно упасть, а не на ровный пол:
			всё, что не аттракцион (станция, мелочь, горка, зона ворот), вместе
			короче двухсот студов, и пустой пробежки на отрезке одна клетка.
		]]
		it(
			"отрезок первого уровня не превращается в долгую пробежку",
			function()
				local spec = TunnelRun.Build(nil, Letters.ordered(), 3, 1)
				local previous = 0
				for index, gate in spec.params.gates do
					local rides = 0
					for _, ride in spec.params.attractions do
						if ride.segment == index then
							rides += ride.z + ride.length - ride.flagZ
						end
					end
					expect(gate.z - previous - rides < 200).to.equal(true)
					previous = gate.z
				end
				expect(#spec.params.track).to.equal(#spec.params.gates * Tunnel.RUN_CELLS)
			end
		)
	end)
end
