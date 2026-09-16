--!nonstrict
--[[
	Раскладка забега: где стоят ворота, препятствия и сохранки.

	Это геометрия пути и ничего кроме неё. Что написано НАД проёмами — буква или
	число — модуль не знает и знать не должен: содержимое ворот ему передают
	функцией. Так «Азбучный туннель», «Полоса препятствий» и «Ворота с числами»
	делят одну раскладку, и ошибка в расстояниях чинится один раз, а не трижды.

	Главное правило, которое раскладка обязана соблюдать: препятствия живут МЕЖДУ
	воротами. Пока ребёнок решает задачу, от него не требуется моторики, иначе
	внимание уходит на выживание, а ответ выбирается наугад.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Obstacles = require(Shared.Config.Obstacles)
local Tunnel = require(Shared.Config.Tunnel)

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
	Из чего состоит отрезок по порядку: клетка препятствия или беговая клетка.

	Пробежки идут ПОСЛЕ элементов и распределены поровну, поэтому отрезок никогда
	не начинается с длинного пустого пола, а кончается им всегда: перед воротами
	ребёнок бежит по ровному и успевает выбрать проём (docs/14-TUNNEL-MODE.md § 4.1).
]]
function CourseLayout.cells(obstacleCount: number, runCount: number): { string }
	local cells: { string } = {}
	local placed = 0
	for step = 1, obstacleCount do
		table.insert(cells, "obstacle")
		local want = math.floor(runCount * step / obstacleCount + 0.5)
		while placed < want do
			table.insert(cells, "run")
			placed += 1
		end
	end
	while placed < runCount do
		table.insert(cells, "run")
		placed += 1
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
	Раскладывает путь: отрезок препятствий → ворота → сохранка → отрезок → …

	Длина отрезка считается из числа препятствий на нём, а не берётся константой:
	иначе на полосе, где элементов вшестеро больше, они налезают друг на друга.

	Один элемент не повторяется дважды подряд — иначе отрезок превращается
	в «ещё три таких же барьера», и ребёнок перестаёт смотреть вперёд.

	«Живых» элементов (маятник, платформа, гаснущие плиты) на отрезке не больше
	двух: дальше отрезок начинает требовать реакции, а за ней теряется задача,
	ради которой отрезок и существует (docs/19-OBSTACLES.md § 3.3).

	makeGate(index, random) отдаёт содержимое ворот — проёмы и, если нужно, надпись
	над ними. Вызывается ровно один раз на ворота и строго по порядку: от этого
	зависит повторяемость забега по сиду, на которой держится сохранка.

	Ряды букв на дорожке (docs/14-TUNNEL-MODE.md § 4.2) — по желанию: makeRow(gate,
	random) отдаёт буквы ряда для отрезка перед этими воротами. Ряд получает свою
	клетку на целом полу перед одним из препятствий и никогда не встаёт в зону
	перед воротами: пока ребёнок решает, от него ничего не требуется.

	У рядов свой генератор (rowRandom). Добавь их в общий — и сдвинулась бы вся
	последовательность, а с ней ворота и препятствия уже сохранённых забегов.
]]
function CourseLayout.layout(
	random: Random,
	plan: {
		gateCount: number,
		obstacleCount: number,
		obstacleTier: number,
		makeGate: (index: number, random: Random) -> { [string]: any },
		rowsPerSegment: number?,
		rowRandom: Random?,
		makeRow: ((gate: { [string]: any }, random: Random) -> { { [string]: any } })?,
		-- Секрет уровня: на каком отрезке он спрятан и свой генератор места.
		secretSegment: number?,
		secretRandom: Random?,
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

	local gates = {}
	local obstacles = {}
	local checkpoints = {}
	local rows = {}
	local secret = nil
	local previousId: string? = nil

	local z = Tunnel.START_RUNWAY

	for index = 1, plan.gateCount do
		local rowRandom = plan.rowRandom
		local makeRow = plan.makeRow

		--[[
			Сколько беговых клеток нужно, чтобы отрезок занял свои сорок секунд
			(Tunnel.runCells). Паркур считается первым, пробежки добирают остаток:
			на поздних уровнях, где элементов много, их почти нет.
		]]
		local wanted = if makeRow and rowRandom and #catalog > 0 then plan.rowsPerSegment or 0 else 0
		local runCount = Tunnel.runCells(plan.obstacleCount, plan.obstacleTier, wanted)
		local cells = CourseLayout.cells(plan.obstacleCount, runCount)

		-- Перед какими клетками встанет ряд букв. Решает свой генератор рядов.
		local rowBefore: { [number]: boolean } = {}
		local rowCount = math.min(wanted, #cells)
		if rowCount > 0 and rowRandom then
			local steps: { number } = {}
			for step = 1, #cells do
				table.insert(steps, step)
			end
			for order, step in CourseLayout.shuffled(steps, rowRandom) do
				if order > rowCount then
					break
				end
				rowBefore[step] = true
			end
		end

		--[[
			Секрет получает свою клетку перед одной из клеток отрезка —
			как ряд букв, только в крайней дорожке и на постаменте.
		]]
		local secretBefore: number? = nil
		local secretRandom = plan.secretRandom
		if plan.secretSegment == index and secretRandom and #cells > 0 and #catalog > 0 then
			secretBefore = secretRandom:NextInteger(1, #cells)
		end

		local segment =
			Tunnel.segmentLength(plan.obstacleCount, rowCount + (if secretBefore then 1 else 0), runCount)

		--[[
			Отрезок режется на клетки: клетка ряда букв (если он здесь есть), потом
			клетка препятствия, и так по порядку. Элемент встаёт в свою клетку
			с отступом и кончается до её конца (Tunnel.obstacleLength), так что
			соседи не касаются, плитки с буквами висят над целым полом, а до ворот
			остаётся вся зона решения.
		]]
		local cursor = z + Tunnel.CLEARANCE_AFTER_GATE
		local rowZs: { number } = {}
		local movingUsed = 0

		for step, cell in cells do
			if rowBefore[step] then
				table.insert(rowZs, cursor + Tunnel.ROW_PLACE)
				cursor += Tunnel.ROW_PITCH
			end
			if secretBefore == step and secretRandom then
				secret = {
					segment = index,
					z = cursor + Tunnel.ROW_PITCH / 2,
					lane = if secretRandom:NextInteger(1, 2) == 1 then 1 else Tunnel.LANE_COUNT,
				}
				cursor += Tunnel.ROW_PITCH
			end

			if cell == "run" then
				-- Беговая клетка: целый пол, ничего не строится.
				cursor += Tunnel.RUN_PITCH
				continue
			end

			if #catalog > 0 then
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
			end

			cursor += Tunnel.OBSTACLE_PITCH
		end

		z += segment

		local gate = plan.makeGate(index, random)
		gate.index = index
		gate.z = z
		table.insert(gates, gate)

		if makeRow and rowRandom then
			for _, rowZ in rowZs do
				local lanes = CourseLayout.lanes(rowRandom)
				local items = makeRow(gate, rowRandom)
				for slot, item in items do
					item.lane = lanes[slot]
				end
				table.insert(rows, { index = #rows + 1, segment = index, z = rowZ, items = items })
			end
		end

		--[[
			Сохранка стоит сразу за каждыми воротами. Упал на препятствии —
			вернулся сюда, а не в начало: потеряно максимум одно короткое звено пути,
			и ни одна звёздочка, ни одна буква при этом не отнимается.
		]]
		table.insert(checkpoints, { index = index, z = z + Tunnel.CHECKPOINT_OFFSET })
	end

	return gates, obstacles, checkpoints, z + Tunnel.FINISH_RUNWAY, rows, secret
end

return CourseLayout
