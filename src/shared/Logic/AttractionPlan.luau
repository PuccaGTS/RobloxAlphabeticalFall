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

--[[
	Облачка: ряды по одному облаку, каждое катается поперёк трассы. Сдвиг фаз
	между соседними рядами — треть взмаха с небольшим разбросом: облака никогда
	не идут строем, но напротив друг друга оказываются дважды за взмах.
]]
local function clouds(heat: number, random: Random)
	local size = Attractions.param("clouds", "size", heat)
	local gap = Attractions.param("clouds", "gap", heat)
	local rows = Attractions.param("clouds", "rows", heat)
	local period = Attractions.param("clouds", "period", heat)
	local list = {}
	local z = gap + size / 2
	for row = 1, rows do
		table.insert(list, {
			row = row,
			z = z,
			phase = ((row - 1) * period / 3 + random:NextNumber(0, period * 0.15)) % period,
		})
		z += size + gap
	end
	return {
		clouds = list,
		size = size,
		gap = gap,
		period = period,
		travel = Attractions.param("clouds", "travel", heat),
		length = z - size / 2,
	}
end

--[[
	Ленты: ряды лент поперёк трассы, каждая тащит к своему обрыву. Направление
	случайное, но три ленты подряд в одну сторону не тянут: пришлось бы просто
	держаться одного края. Последняя лента длинная и везёт назад, к щели.
]]
local function belts(heat: number, random: Random)
	local rows = Attractions.param("belts", "rows", heat)
	local depth = Attractions.param("belts", "depth", heat)
	local gap = Attractions.param("belts", "gap", heat)
	local list = {}
	local z = gap + depth / 2
	for row = 1, rows do
		local direction = if random:NextInteger(1, 2) == 1 then 1 else -1
		if row >= 3 and list[row - 1].direction == list[row - 2].direction then
			direction = -list[row - 1].direction
		end
		table.insert(list, { row = row, z = z, direction = direction })
		z += depth + gap
	end
	local back = Attractions.param("belts", "back", heat)
	-- z стоит на краю следующей ленты плюс её половина: последняя лента начинается после щели.
	local backZ = z - depth / 2 + back / 2
	return {
		belts = list,
		depth = depth,
		gap = gap,
		span = Attractions.param("belts", "span", heat),
		speed = Attractions.param("belts", "speed", heat),
		back = { z = backZ, length = back, speed = Attractions.param("belts", "backSpeed", heat) },
		-- Последняя лента упирается в пол выхода: сойти с неё можно, только добежав.
		length = backZ + back / 2,
	}
end

--[[
	Качели: доски на верёвках качаются вдоль бега, соседние — в противофазе.
	Ось каждой следующей стоит так, чтобы сошедшиеся доски разделяла щель near,
	а разошедшиеся — пропасть в near плюс два размаха. Первая сходится с полом
	входа, последняя — с полом выхода.
]]
local function swings(heat: number, _random: Random)
	local count = Attractions.param("swings", "count", heat)
	local board = Attractions.param("swings", "board", heat)
	local near = Attractions.param("swings", "near", heat)
	local period = Attractions.param("swings", "period", heat)
	local amplitude = Attractions.param("swings", "swing", heat)
	local reach = Attractions.SWING_ROPE * math.sin(amplitude) -- на сколько доска уходит от оси вдоль бега
	local step = board + 2 * reach + near
	local list = {}
	local z = near + board / 2 + reach
	for index = 1, count do
		table.insert(list, {
			index = index,
			z = z,
			-- Нечётные в фазе, чётные навстречу: соседи сходятся и расходятся.
			phase = if index % 2 == 1 then 0 else period / 2,
		})
		z += step
	end
	return {
		swings = list,
		board = board,
		near = near,
		period = period,
		amplitude = amplitude,
		reach = reach,
		length = list[#list].z + reach + board / 2 + near,
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

--[[
	Батуты: «батут — островок» несколько раз подряд. Батут стоит в пропасти
	ниже пола, островок высоко: обычным прыжком на него не попасть, только
	с батута. Островок на той же дорожке, что и его батут, — подброс ведёт
	вперёд, а не вбок; следующий батут на соседней дорожке или на той же.
]]
local function bounce(heat: number, random: Random)
	local count = Attractions.param("bounce", "pairs", heat)
	local pad = Attractions.param("bounce", "pad", heat)
	local island = Attractions.param("bounce", "island", heat)
	local gap = Attractions.param("bounce", "gap", heat)
	local height = Attractions.param("bounce", "height", heat)
	local travel = Attractions.param("bounce", "travel", heat)
	local period = Attractions.param("bounce", "period", heat)
	-- Ноги поднимаются от верха батута до островка и ещё на запас сверху.
	local power = Attractions.bouncePower(height - Attractions.BOUNCE_PAD_Y + Attractions.BOUNCE_CLEAR)

	local pads = {}
	local tops = {}
	local z = gap + pad / 2
	local lane = nil
	for index = 1, count do
		lane = laneNear(random, lane)
		-- Едущий батут не выезжает за бортик: крайние дорожки везут к середине.
		local x = if travel > 0 then math.clamp(lane, -9 + travel, 9 - travel) else lane
		table.insert(pads, {
			index = index,
			x = x,
			z = z,
			phase = random:NextNumber(0, period),
		})
		z += pad / 2 + gap + island / 2
		table.insert(tops, { index = index, x = x, z = z, y = height })
		z += island / 2 + gap + pad / 2
	end
	return {
		pads = pads,
		islands = tops,
		pad = pad,
		island = island,
		gap = gap,
		height = height,
		travel = travel,
		period = period,
		power = power,
		-- После последнего островка спрыгиваешь на пол выхода.
		length = z - pad / 2,
	}
end

--[[
	Печеньки: ряды по три печеньки на дорожках, в части рядов одной-двух нет.
	Где печенька в ряду одна, она стоит не дальше соседней дорожки от одной
	из печенек прошлого ряда: прыжок наискосок есть всегда.
]]
local function cookies(heat: number, random: Random)
	local rows = Attractions.param("cookies", "rows", heat)
	local size = Attractions.param("cookies", "size", heat)
	local gap = Attractions.param("cookies", "gap", heat)
	local missing = Attractions.param("cookies", "missing", heat)

	local list = {}
	local z = gap + size / 2
	local previous: { number } = { 0 }
	for row = 1, rows do
		local keep: { number } = { table.unpack(LANES) }
		-- Первый ряд целый: на аттракцион входят, а не угадывают.
		local drop = if row == 1 then 0 else random:NextInteger(0, missing)
		if drop >= 2 then
			keep = { laneNear(random, previous[random:NextInteger(1, #previous)]) }
		elseif drop == 1 then
			table.remove(keep, random:NextInteger(1, #keep))
		end
		for _, x in keep do
			table.insert(list, { row = row, x = x, z = z })
		end
		previous = keep
		z += size + gap
	end
	return {
		cookies = list,
		size = size,
		gap = gap,
		hold = Attractions.param("cookies", "hold", heat),
		length = z - size / 2,
	}
end

--[[
	Буквенные кочки: ряды по три кочки, по одной на дорожку. В каждом ряду
	одна «верная» — на ней буква отрезка, её номер в ряду — right. Какие буквы
	на остальных, решает забег (Challenges/RunCourse): здесь только места.
	Верные соседних рядов не дальше соседней дорожки: прыжок наискосок, а не
	через всю трассу.
]]
local function letterstones(heat: number, random: Random)
	local rows = Attractions.param("letterstones", "rows", heat)
	local size = Attractions.param("letterstones", "size", heat)
	local gap = Attractions.param("letterstones", "gap", heat)

	local stones = {}
	local z = gap + size / 2
	local previous: number? = nil
	for row = 1, rows do
		local right = laneNear(random, previous)
		for lane, x in LANES do
			table.insert(stones, { row = row, lane = lane, x = x, z = z, right = x == right })
		end
		previous = right
		z += size + gap
	end
	return {
		stones = stones,
		size = size,
		gap = gap,
		length = z - size / 2,
	}
end

--[[
	Кубики-топотуны: ряды по три кубика над дорожками. В ряду кубики топают
	по очереди, со сдвигом в треть цикла, соседние ряды — со своим сдвигом:
	волна топота бежит по аттракциону, и переждать её надо с умом.
]]
local function stompers(heat: number, random: Random)
	local rows = Attractions.param("stompers", "rows", heat)
	local period = Attractions.param("stompers", "period", heat)
	local size = Attractions.STOMPER_SIZE
	local gap = Attractions.STOMPER_GAP
	local list = {}
	local z = gap + size / 2
	for row = 1, rows do
		local shift = random:NextNumber(0, period)
		for column, x in LANES do
			table.insert(list, {
				row = row,
				column = column,
				x = x,
				z = z,
				phase = (shift + (column - 1) * period / 3) % period,
			})
		end
		z += size + gap
	end
	return {
		stompers = list,
		period = period,
		down = Attractions.param("stompers", "down", heat),
		length = z - size / 2,
	}
end

--[[
	Ветродуи: участки мостика подряд, у каждого своя тучка. Тучки висят
	по очереди слева и справа, щит — посреди участка у наветренного края.
	Фазы соседних тучек близки, но не равны: порывы бегут волной вдоль
	мостика, и от щита до щита всегда есть когда пробежать (это держит тест).
]]
local function wind(heat: number, random: Random)
	local zones = Attractions.param("wind", "zones", heat)
	local gap = Attractions.param("wind", "gap", heat)
	local period = Attractions.param("wind", "period", heat)
	local length = Attractions.WIND_ZONE
	local shift = random:NextNumber(0, period)
	local side = if random:NextInteger(1, 2) == 1 then 1 else -1
	local list = {}
	local z = gap
	for zone = 1, zones do
		table.insert(list, {
			zone = zone,
			from = z,
			to = z + length,
			z = z + length / 2,
			side = side, -- где висит тучка: дует от неё к другому краю мостика
			phase = (shift + (zone - 1) * period * 0.12) % period,
		})
		side = -side
		z += length + gap
	end
	return {
		zones = list,
		bridge = Attractions.param("wind", "bridge", heat),
		gap = gap,
		speed = Attractions.param("wind", "speed", heat),
		gust = Attractions.param("wind", "gust", heat),
		period = period,
		-- После последнего участка — щель до пола выхода (если щели вообще есть).
		length = z,
	}
end

--[[
	Подъёмники: платформы на шариках петляют по дорожкам и ездят вверх-вниз,
	середина хода каждой следующей на rise выше прошлой. Соседняя отстаёт на
	LIFT_SHIFT хода: пока ты едешь вверх, она ещё внизу, — и дважды за ход
	есть окно, когда до неё допрыгнешь (это держит тест). После последней —
	балкон ещё на rise выше, с балкона горка вниз, к полу выхода.
]]
local function lifts(heat: number, random: Random)
	local count = Attractions.param("lifts", "count", heat)
	local size = Attractions.param("lifts", "size", heat)
	local gap = Attractions.param("lifts", "gap", heat)
	local rise = Attractions.param("lifts", "rise", heat)
	local period = Attractions.param("lifts", "period", heat)
	local shift = random:NextNumber(0, period)
	local list = {}
	local z = gap + size / 2
	local x = laneNear(random, nil)
	for index = 1, count do
		if index > 1 then
			local previous = list[index - 1]
			x = laneNear(random, previous.x)
			-- Край до края — ровно gap, и по диагонали, когда тропа сворачивает.
			local reach = size + gap
			local dx = x - previous.x
			z = previous.z + math.sqrt(reach * reach - dx * dx)
		end
		table.insert(list, {
			index = index,
			x = x,
			z = z,
			mid = index * rise,
			phase = (shift - (index - 1) * period * Attractions.LIFT_SHIFT) % period,
		})
	end
	local last = list[#list]
	local balconyFrom = last.z + size / 2 + gap
	local balconyY = (count + 1) * rise
	local slide = balconyY / Attractions.LIFT_SLOPE
	return {
		lifts = list,
		size = size,
		gap = gap,
		rise = rise,
		travel = Attractions.param("lifts", "travel", heat),
		period = period,
		balcony = { from = balconyFrom, to = balconyFrom + Attractions.LIFT_BALCONY, y = balconyY },
		slide = slide,
		length = balconyFrom + Attractions.LIFT_BALCONY + slide,
	}
end

local MAKERS = {
	lifts = lifts,
	wind = wind,
	bounce = bounce,
	cookies = cookies,
	letterstones = letterstones,
	stompers = stompers,
	islands = islands,
	lava = lava,
	spinner = spinner,
	boulders = boulders,
	clouds = clouds,
	belts = belts,
	swings = swings,
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
