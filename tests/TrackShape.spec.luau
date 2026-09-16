--!nocheck
--[[
	Форма трассы забега. Главное, что держат эти тесты: горки и виражи живут
	только на беговых клетках, а ворота, препятствия и ряды букв стоят на ровном.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrackShape = require(ReplicatedStorage.Shared.Logic.TrackShape)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)
local Levels = require(ReplicatedStorage.Shared.Config.Levels)
local TunnelRun = require(ReplicatedStorage.ServerChallenges.TunnelRun)
local ObstacleCourse = require(ReplicatedStorage.ServerChallenges.ObstacleCourse)
local MathGates = require(ReplicatedStorage.ServerChallenges.MathGates)

local function runsEvery(count, pitch, gap)
	local runs = {}
	local z = 40
	for _ = 1, count do
		table.insert(runs, { from = z, to = z + pitch })
		z += pitch + gap
	end
	return runs, z + 40
end

local function specs()
	local list = {}
	for _, level in Levels.all do
		table.insert(list, TunnelRun.Build(nil, { "a", "b", "v" }, 3, level.index))
	end
	for difficulty = 1, 5 do
		table.insert(list, ObstacleCourse.Build(nil, { "m", "a", "u" }, difficulty))
	end
	table.insert(list, MathGates.Build(nil, { "a" }, 3, 3))
	return list
end

return function()
	describe("TrackShape.plan", function()
		it("по тому же сиду — та же форма", function()
			local runs = runsEvery(12, 50, 100)
			local first = TrackShape.plan(runs, 42)
			local second = TrackShape.plan(runs, 42)
			for index, zone in first do
				expect(second[index].kind).to.equal(zone.kind)
			end
		end)

		it("зона формы ровно на беговой клетке и на каждой", function()
			local runs = runsEvery(10, 50, 80)
			local zones = TrackShape.plan(runs, 7)
			expect(#zones).to.equal(#runs)
			for index, zone in zones do
				expect(zone.from).to.equal(runs[index].from)
				expect(zone.to).to.equal(runs[index].to)
			end
		end)

		it("одна и та же форма дважды подряд не встаёт", function()
			for seed = 1, 30 do
				local zones = TrackShape.plan(runsEvery(15, 50, 60), seed)
				for index = 2, #zones do
					local a = zones[index - 1].kind:gsub("_left", ""):gsub("_right", "")
					local b = zones[index].kind:gsub("_left", ""):gsub("_right", "")
					expect(a ~= b).to.equal(true)
				end
			end
		end)

		it("разные сиды дают разные трассы", function()
			local runs = runsEvery(12, 50, 100)
			local kinds = {}
			for seed = 1, 20 do
				local line = {}
				for _, zone in TrackShape.plan(runs, seed) do
					table.insert(line, zone.kind)
				end
				kinds[table.concat(line, ",")] = true
			end
			local distinct = 0
			for _ in kinds do
				distinct += 1
			end
			expect(distinct > 10).to.equal(true)
		end)
	end)

	describe("TrackShape.sampler", function()
		it("вне зон трасса ровная: без наклона", function()
			for seed = 1, 10 do
				local runs, length = runsEvery(10, 50, 70)
				local sampler = TrackShape.sampler(TrackShape.plan(runs, seed), length)
				for z = 0, length - 2, 3 do
					if not sampler.zoneAt(z) and not sampler.zoneAt(z + 1) then
						local look = sampler.frame(z).LookVector
						expect(math.abs(look.Y) < 0.01).to.equal(true)
					end
				end
			end
		end)

		it("высота не выходит из коридора", function()
			for seed = 1, 30 do
				local runs, length = runsEvery(20, 50, 40)
				local sampler = TrackShape.sampler(TrackShape.plan(runs, seed), length)
				for z = 0, length, 5 do
					local y = sampler.frame(z).Position.Y
					expect(y >= TrackShape.MIN_HEIGHT - TrackShape.DIP_DEPTH - 0.01).to.equal(true)
					expect(y <= TrackShape.MAX_HEIGHT + TrackShape.HILL_HEIGHT + 0.01).to.equal(true)
				end
			end
		end)

		it("пол непрерывен: соседние точки рядом", function()
			local runs, length = runsEvery(12, 50, 60)
			local sampler = TrackShape.sampler(TrackShape.plan(runs, 99), length)
			for z = 0, length - 1 do
				local gap = (sampler.frame(z + 1).Position - sampler.frame(z).Position).Magnitude
				expect(gap < 1.5).to.equal(true)
			end
		end)

		it(
			"змейка возвращает трассу на прежнее направление",
			function()
				local sampler = TrackShape.sampler({ { from = 10, to = 60, kind = "zigzag" } }, 100)
				local before = sampler.flat(5).LookVector
				local after = sampler.flat(80).LookVector
				expect(before:Dot(after) > 0.999).to.equal(true)
			end
		)

		--[[
			Туннели игроков стоят рядом. Трасса, ушедшая вбок дальше половины
			промежутка, влезла бы в соседний туннель.
		]]
		it("трасса не уходит к соседнему туннелю", function()
			local limit = Tunnel.PLOT_SPACING / 2 - Tunnel.WIDTH
			for seed = 1, 60 do
				local runs, length = runsEvery(30, 50, 110)
				local sampler = TrackShape.sampler(TrackShape.plan(runs, seed), length)
				for z = 0, length, 10 do
					expect(math.abs(sampler.flat(z).Position.X) < limit).to.equal(true)
				end
			end
		end)
	end)

	describe("TrackShape и забеги", function()
		it("у каждого забега есть форма трассы", function()
			for _, spec in specs() do
				expect(typeof(spec.params.track)).to.equal("table")
				expect(#spec.params.track >= Tunnel.MIN_RUN_CELLS).to.equal(true)
			end
		end)

		--[[
			Ворота видно заранее и на ровном; под препятствием горки нет;
			плитка с буквой не висит на склоне.
		]]
		it(
			"ворота, препятствия и ряды букв стоят вне зон формы",
			function()
				for _, spec in specs() do
					local sampler = TrackShape.sampler(spec.params.track, spec.params.length)
					for _, gate in spec.params.gates do
						expect(sampler.zoneAt(gate.z)).to.equal(nil)
						expect(sampler.zoneAt(gate.z - Tunnel.CLEARANCE_BEFORE_GATE + 1)).to.equal(nil)
					end
					for _, obstacle in spec.params.obstacles do
						local from = obstacle.z - Tunnel.obstacleLead(obstacle.kind)
						local to = obstacle.z + (Tunnel.obstacleLength(obstacle.kind) or 0)
						for z = from, to, 1 do
							expect(sampler.zoneAt(z)).to.equal(nil)
						end
					end
					for _, row in spec.params.rows or {} do
						expect(sampler.zoneAt(row.z)).to.equal(nil)
					end
					for _, checkpoint in spec.params.checkpoints do
						expect(sampler.zoneAt(checkpoint.z)).to.equal(nil)
					end
				end
			end
		)

		it("забег по рецепту собирается с той же формой", function()
			local spec = TunnelRun.Build(nil, { "a", "b", "v" }, 3, 4)
			local again = TunnelRun.Rebuild({
				challengeId = spec.challengeId,
				seed = spec.seed,
				letters = spec.letters,
				difficulty = spec.difficulty,
				level = spec.level,
				checkpoint = 0,
			})
			for index, zone in spec.params.track do
				expect(again.params.track[index].kind).to.equal(zone.kind)
			end
		end)
	end)
end
