--!nonstrict
--[[
	Раскладка забега: где стоят станции, препятствия, аттракционы, ворота и сохранки.

	Это геометрия пути и ничего кроме неё. Что написано НАД проёмами — буква или
	число — модуль не знает и знать не должен: содержимое ворот ему передают
	функцией. Так «Азбучный туннель» и «Ворота с числами» делят одну раскладку,
	и ошибка в расстояниях чинится один раз, а не дважды.

	Главное правило, которое раскладка обязана соблюдать: препятствия живут МЕЖДУ
	воротами. Пока ребёнок решает задачу, от него не требуется моторики, иначе
	внимание уходит на выживание, а ответ выбирается наугад.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Obstacles = require(Shared.Config.Obstacles)
local Tunnel = require(Shared.Config.Tunnel)
local Attractions = require(Shared.Config.Attractions)
local AttractionPlan = require(Shared.Logic.AttractionPlan)

local CourseLayout = {}

function CourseLayout.shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Из чего состоит отрезок по порядку.

	Станция буквы — первой: буква отрезка звучит до паркура. Мелкие элементы
	делятся поровну вокруг аттракционов, так что аттракцион никогда не стоит
	вплотную к станции или к воротам. Беговая клетка — последней: трасса
	делает горку или вираж, и за ним видно ворота (docs/14-TUNNEL-MODE.md § 4.1).
]]
function CourseLayout.cells(
	obstacleCount: number,
	runCount: number,
	attractionCount: number?,
	station: boolean?
): { string }
	local cells: { string } = {}
	if station then
		table.insert(cells, "station")
	end
	local attractions = attractionCount or 0
	local placed = 0
	for step = 1, obstacleCount do
		table.insert(cells, "obstacle")
		local want = math.floor(attractions * step / (obstacleCount + 1) + 0.5)
		while placed < want do
			table.insert(cells, "attraction")
			placed += 1
		end
	end
	while placed < attractions do
		table.insert(cells, "attraction")
		placed += 1
	end
	for _ = 1, runCount do
		table.insert(cells, "run")
	end
	return cells
end

-- Дорожки в случайном порядке: на какой из них окажется верный ответ, заранее не угадать.
function CourseLayout.lanes(random: Random): { number }
	local lanes = {}
	for lane = 1, Tunnel.LANE_COUNT do
		table.insert(lanes, lane)
	end
	return CourseLayout.shuffled(lanes, random)
end

--[[
	Раскладывает путь: станция → паркур → аттракцион → паркур → ворота → сохранка → …

	Длина отрезка — сумма его клеток, а не константа.

	Один элемент не повторяется дважды подряд — иначе отрезок превращается
	в «ещё три таких же барьера», и ребёнок перестаёт смотреть вперёд.

	«Живых» мелких элементов (маятник, платформа, гаснущие плиты) на отрезке
	не больше двух (docs/19-OBSTACLES.md § 3.3). Аттракционы в этот счёт
	не входят: они живут отдельно и занимают всю трассу.

	makeGate(index, random) отдаёт содержимое ворот — проёмы и, если нужно, надпись
	над ними. Вызывается ровно один раз на ворота и строго по порядку: от этого
	зависит повторяемость забега по сиду, на которой держится сохранка.

	Аттракционы (Config/Attractions) раскладываются своим генератором: ворота
	и мелкие элементы от их появления не зависят. Перед каждым стоит флажок —
	маленькая сохранка: упавший на аттракционе возвращается к нему, а не к воротам.
	В профиль флажок не пишется, только арки за воротами.
]]
function CourseLayout.layout(
	random: Random,
	plan: {
		gateCount: number,
		obstacleCount: number,
		obstacleTier: number,
		makeGate: (index: number, random: Random) -> { [string]: any },
		-- Секреты уровня: на каких отрезках спрятаны (по одному на отрезок) и свой генератор места.
		secretSegments: { number }?,
		secretRandom: Random?,
		-- Особый участок уровня: на каком отрезке, перед воротами (Tunnel.SPECIAL_PITCH).
		specialSegment: number?,
		-- Станция буквы в начале каждого отрезка: только у мира букв.
		stations: boolean?,
		-- Аттракционы: какие открыты, какой силы, сколько на отрезок и свой генератор.
		attractions: {
			unlocked: { string },
			heat: number,
			perSegment: number,
			random: Random,
			-- Финал уровня (Attractions.isBossLevel): самые новые аттракционы после последних ворот.
			boss: boolean?,
		}?,
	}
)
	local catalog = Obstacles.upToTier(plan.obstacleTier)

	-- Спокойные элементы: ими добираем отрезок, когда живых на нём уже достаточно.
	local calm: { string } = {}
	for _, id in catalog do
		if not Obstacles.isMoving(id) then
			table.insert(calm, id)
		end
	end

	local rides = plan.attractions
	local perSegment = if rides and #rides.unlocked > 0 then rides.perSegment else 0
	local rideIds = if rides and perSegment > 0
		then AttractionPlan.sequence(rides.unlocked, perSegment * plan.gateCount, rides.random)
		else {}

	local gates = {}
	local obstacles = {}
	local checkpoints = {}
	local stations = {}
	local attractions = {}
	-- Где лежат беговые клетки: на них трасса получает форму (Logic/TrackShape).
	local runs = {}
	local secrets = {}
	local special = nil
	local previousId: string? = nil

	local z = Tunnel.START_RUNWAY

	for index = 1, plan.gateCount do
		local cells = CourseLayout.cells(plan.obstacleCount, Tunnel.RUN_CELLS, perSegment, plan.stations)
		--[[
			Особый участок — последняя клетка отрезка: после паркура и пробежки,
			прямо перед зоной ворот. Лестница стоит на ровном, как и всё, кроме
			пробежек, и после неё ребёнок успевает увидеть ворота.
		]]
		if plan.specialSegment == index then
			table.insert(cells, "special")
		end

		--[[
			Секрет получает свою клетку перед одной из клеток отрезка, в крайней
			дорожке и на постаменте. Не перед станцией: между аркой и станцией
			ребёнок ещё не знает, что ищет.
		]]
		local secretBefore: number? = nil
		local secretRandom = plan.secretRandom
		local hidesSecret = plan.secretSegments ~= nil and table.find(plan.secretSegments, index) ~= nil
		if hidesSecret and secretRandom and #cells > 0 and #catalog > 0 then
			local first = if plan.stations then 2 else 1
			secretBefore = secretRandom:NextInteger(math.min(first, #cells), #cells)
		end

		local cursor = z + Tunnel.CLEARANCE_AFTER_GATE
		local movingUsed = 0

		for step, cell in cells do
			if secretBefore == step and secretRandom then
				table.insert(secrets, {
					index = #secrets + 1,
					segment = index,
					z = cursor + Tunnel.SECRET_PITCH / 2,
					lane = if secretRandom:NextInteger(1, 2) == 1 then 1 else Tunnel.LANE_COUNT,
				})
				cursor += Tunnel.SECRET_PITCH
			end

			if cell == "station" then
				table.insert(stations, { index = #stations + 1, segment = index, z = cursor })
				cursor += Tunnel.STATION_PITCH
				continue
			end

			if cell == "attraction" and rides then
				local ride = AttractionPlan.make(rideIds[#attractions + 1], rides.heat, rides.random)
				ride.index = #attractions + 1
				ride.segment = index
				ride.flagZ = cursor + 1
				ride.z = cursor + Attractions.FLAG_LEAD
				table.insert(attractions, ride)
				cursor = ride.z + ride.length + Attractions.EXIT
				continue
			end

			if cell == "special" then
				special = { segment = index, z = cursor }
				cursor += Tunnel.SPECIAL_PITCH
				continue
			end

			if cell == "run" then
				-- Беговая клетка: ничего не строится, зато здесь горка, вираж или змейка.
				table.insert(runs, { from = cursor, to = cursor + Tunnel.RUN_PITCH })
				cursor += Tunnel.RUN_PITCH
				continue
			end

			if cell == "obstacle" and #catalog > 0 then
				local pool = if movingUsed >= Tunnel.MAX_MOVING_PER_SEGMENT and #calm > 0
					then calm
					else catalog

				local id = pool[random:NextInteger(1, #pool)]
				if id == previousId and #pool > 1 then
					id = pool[(table.find(pool, id) % #pool) + 1]
				end
				previousId = id

				if Obstacles.isMoving(id) then
					movingUsed += 1
				end

				local obstacle = Obstacles.expect(id)
				local lane = 0 -- элемент во всю ширину дорожкой не помечается
				if obstacle.lanes < Tunnel.LANE_COUNT then
					lane = if obstacle.edge
						then (if random:NextInteger(1, 2) == 1 then 1 else Tunnel.LANE_COUNT)
						else random:NextInteger(1, Tunnel.LANE_COUNT)
				end

				table.insert(obstacles, {
					id = id,
					kind = obstacle.kind,
					z = cursor + Tunnel.OBSTACLE_LEAD,
					lane = lane,
				})
				cursor += Tunnel.OBSTACLE_PITCH
			end
		end

		z = math.max(cursor + Tunnel.CLEARANCE_BEFORE_GATE, z + Tunnel.MIN_GATE_SPACING)

		local gate = plan.makeGate(index, random)
		gate.index = index
		gate.z = z
		table.insert(gates, gate)

		--[[
			Сохранка стоит сразу за каждыми воротами. Упал на препятствии —
			вернулся к флажку аттракциона или сюда, а не в начало, и ни одна
			звёздочка, ни одна буква при этом не отнимается.
		]]
		table.insert(checkpoints, { index = index, z = z + Tunnel.CHECKPOINT_OFFSET })
	end

	--[[
		Финал: после последних ворот (сохранка уже стоит за ними) два самых
		новых аттракциона уровня на ступень жарче. Буквы на буквенных — буква
		последнего отрезка. Упал — к флажку перед аттракционом, как везде.
	]]
	local boss = nil
	if rides and rides.boss and #rides.unlocked > 0 and plan.gateCount > 0 then
		local cursor = z + Tunnel.CLEARANCE_AFTER_GATE
		boss = { from = cursor, to = cursor }
		local count = math.min(Attractions.BOSS_RIDES, #rides.unlocked)
		for offset = count - 1, 0, -1 do
			local id = rides.unlocked[#rides.unlocked - offset]
			local ride = AttractionPlan.make(id, math.min(rides.heat + 1, 5), rides.random)
			ride.index = #attractions + 1
			ride.segment = plan.gateCount
			ride.boss = true
			ride.flagZ = cursor + 1
			ride.z = cursor + Attractions.FLAG_LEAD
			table.insert(attractions, ride)
			cursor = ride.z + ride.length + Attractions.EXIT
		end
		boss.to = cursor
		z = cursor
	end

	return {
		gates = gates,
		obstacles = obstacles,
		checkpoints = checkpoints,
		boss = boss,
		length = z + Tunnel.FINISH_RUNWAY,
		secrets = secrets,
		runs = runs,
		special = special,
		stations = stations,
		attractions = attractions,
	}
end

return CourseLayout
