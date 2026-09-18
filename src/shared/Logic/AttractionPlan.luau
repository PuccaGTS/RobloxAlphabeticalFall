--!strict
--[[
	План одного аттракциона: где стоят островки, кочки, ниши и молоты.
	Чистая функция от жара и генератора — повторяемость забега по сиду держится
	и здесь (docs/14-TUNNEL-MODE.md § 3.3).

	Координаты локальные: z — от начала аттракциона вперёд по бегу, x — вбок
	(дорожки на −9, 0, 9), y — вверх от уровня пола трассы. Строит по плану
	TunnelService, анимирует движущееся клиент (RunHazardController).
]]

local Attractions = require(script.Parent.Parent.Config.Attractions)

local AttractionPlan = {}

local LANES = { -9, 0, 9 }

local function laneNear(random: Random, previous: number?): number
	if previous == nil then
		return LANES[random:NextInteger(1, #LANES)]
	end
	-- Соседняя дорожка чаще, чем та же: тропа петляет, и прыжок каждый раз другой.
	local options: { number } = {}
	for _, x in LANES do
		if math.abs(x - previous) <= 9 and (x ~= previous or random:NextNumber() < 0.3) then
			table.insert(options, x)
		end
	end
	if #options == 0 then
		return previous
	end
	return options[random:NextInteger(1, #options)]
end

--[[
	Островки: тропа из круглых кочек над пропастью. Расстояние между краями
	соседних кочек берётся из жара, а центр следующей ставится так, чтобы
	это расстояние выдержалось и по диагонали, когда тропа сворачивает.
]]
local function islands(heat: number, random: Random)
	local size = Attractions.param("islands", "size", heat)
	local gapMin = Attractions.param("islands", "gapMin", heat)
	local gapMax = Attractions.param("islands", "gapMax", heat)
	local rise = Attractions.param("islands", "rise", heat)
	local count = Attractions.param("islands", "count", heat)
	local radius = size / 2

	local list = {}
	local previous = nil
	for index = 1, count do
		local gap = random:NextNumber(gapMin, gapMax)
		local x = laneNear(random, previous and previous.x)
		local z
		if previous == nil then
			z = gap + radius -- от края пола трассы
		else
			local dx = x - previous.x
			local reach = gap + radius * 2
			z = previous.z + math.sqrt(math.max(reach * reach - dx * dx, 1))
		end
		local y = 0
		if previous and rise > 0 then
			y = math.clamp(previous.y + random:NextNumber(-rise, rise), -rise, rise)
		end
		local island = { index = index, x = x, y = y, z = z, size = size }
		table.insert(list, island)
		previous = island
	end

	local last = list[#list]
	local tail = random:NextNumber(gapMin, gapMax)
	return {
		islands = list,
		length = last.z + radius + tail,
	}
end

--[[
	Лавовые кочки: две колонки квадратных кочек над лавой. Кочки уходят в лаву
	и возвращаются, со сдвигом фаз вдоль колонки — стоять на месте нельзя,
	а шагнуть вперёд или в соседнюю колонку можно всегда: каждая третья строка
	не тонет вовсе, это передышка.
]]
local function lava(heat: number, random: Random)
	local rows = Attractions.param("lava", "rows", heat)
	local gap = Attractions.param("lava", "gap", heat)
	local solid = Attractions.param("lava", "solid", heat)
	local sunk = Attractions.param("lava", "sunk", heat)
	local period = solid + sunk
	local stone = Attractions.LAVA_STONE

	local stones = {}
	local z = gap + stone / 2
	for row = 1, rows do
		local steady = row % 3 == 0
		for column, side in { -1, 1 } do
			table.insert(stones, {
				row = row,
				column = column,
				x = side * Attractions.LAVA_COLUMN,
				z = z,
				steady = steady,
				-- Фаза: соседние по колонке тонут не разом, соседние по строке — в противофазе.
				phase = if steady
					then 0
					else (row * 0.37 * period + (column - 1) * period / 2 + random:NextNumber(0, 0.3))
						% period,
			})
		end
		z += stone + gap
	end

	return {
		stones = stones,
		period = period,
		solid = solid,
		length = z - stone / 2,
	}
end

local function spinner(heat: number, random: Random)
	return {
		length = Attractions.SPINNER_LENGTH,
		period = Attractions.param("spinner", "period", heat),
		bars = Attractions.param("spinner", "bars", heat),
		-- Направление вращения: по часовой или против, чтобы вертушки не были близнецами.
		direction = if random:NextInteger(1, 2) == 1 then 1 else -1,
	}
end

local function boulders(heat: number, _random: Random)
	local niches = {}
	local z = Attractions.NICHE_FIRST
	local side = -1
	while z + Attractions.NICHE_LENGTH / 2 < Attractions.BOULDER_LENGTH - 4 do
		table.insert(niches, { z = z, side = side })
		side = -side
		z += Attractions.NICHE_STEP
	end
	return {
		length = Attractions.BOULDER_LENGTH,
		speed = Attractions.param("boulders", "speed", heat),
		interval = Attractions.param("boulders", "interval", heat),
		niches = niches,
	}
end

local function hammers(heat: number, _random: Random)
	local period = Attractions.param("hammers", "period", heat)
	local list = {}
	local step = Attractions.HAMMER_LENGTH / (Attractions.HAMMER_COUNT + 1)
	for index = 1, Attractions.HAMMER_COUNT do
		table.insert(list, {
			index = index,
			z = step * index,
			-- Соседние молоты качаются не в такт: окно проскочить есть у каждого.
			phase = (index - 1) * period / Attractions.HAMMER_COUNT,
		})
	end
	return {
		length = Attractions.HAMMER_LENGTH,
		period = period,
		bridge = Attractions.param("hammers", "bridge", heat),
		hammers = list,
	}
end

local MAKERS = {
	islands = islands,
	lava = lava,
	spinner = spinner,
	boulders = boulders,
	hammers = hammers,
}

function AttractionPlan.make(id: string, heat: number, random: Random): { [string]: any }
	local maker = MAKERS[id]
	assert(maker, `AttractionPlan: не умею строить "{id}"`)
	local plan = maker(heat, random)
	plan.id = id
	plan.heat = heat
	return plan
end

--[[
	Какие аттракционы встанут на отрезки забега, по порядку.

	Самый новый из открытых встаёт первым: ребёнок, дошедший до нового уровня,
	сразу видит, что появилось. Дальше — по кругу в перемешанном порядке,
	и один и тот же аттракцион дважды подряд не встаёт.
]]
function AttractionPlan.sequence(unlocked: { string }, count: number, random: Random): { string }
	local result: { string } = {}
	if #unlocked == 0 or count <= 0 then
		return result
	end
	table.insert(result, unlocked[#unlocked])
	while #result < count do
		local pool = table.clone(unlocked)
		for i = #pool, 2, -1 do
			local j = random:NextInteger(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		for _, id in pool do
			if #result >= count then
				break
			end
			if id ~= result[#result] or #unlocked == 1 then
				table.insert(result, id)
			end
		end
	end
	return result
end

return AttractionPlan
