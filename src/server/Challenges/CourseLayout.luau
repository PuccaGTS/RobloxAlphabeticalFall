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
]]
function CourseLayout.layout(
	random: Random,
	plan: {
		gateCount: number,
		obstacleCount: number,
		obstacleTier: number,
		makeGate: (index: number, random: Random) -> { [string]: any },
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
	local previousId: string? = nil

	local z = Tunnel.START_RUNWAY

	for index = 1, plan.gateCount do
		local segment = Tunnel.segmentLength(plan.obstacleCount)

		if #catalog > 0 then
			local movingUsed = 0

			for step = 1, plan.obstacleCount do
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
				table.insert(obstacles, {
					id = id,
					kind = obstacle.kind,
					z = z + Tunnel.CLEARANCE_AFTER_GATE + (step - 0.5) * Tunnel.OBSTACLE_PITCH,
					-- Элемент во всю ширину дорожкой не помечается: lane = 0.
					lane = if obstacle.lanes >= Tunnel.LANE_COUNT
						then 0
						else random:NextInteger(1, Tunnel.LANE_COUNT),
				})
			end
		end

		z += segment

		local gate = plan.makeGate(index, random)
		gate.index = index
		gate.z = z
		table.insert(gates, gate)

		--[[
			Сохранка стоит сразу за каждыми воротами. Упал на препятствии —
			вернулся сюда, а не в начало: потеряно максимум одно короткое звено пути,
			и ни одна звёздочка, ни одна буква при этом не отнимается.
		]]
		table.insert(checkpoints, { index = index, z = z + Tunnel.CHECKPOINT_OFFSET })
	end

	return gates, obstacles, checkpoints, z + Tunnel.FINISH_RUNWAY
end

return CourseLayout
