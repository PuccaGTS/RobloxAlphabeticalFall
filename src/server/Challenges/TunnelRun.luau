--!nonstrict
--[[
	Испытание «Азбучный туннель» — основной режим. См. docs/14-TUNNEL-MODE.md.

	Ребёнок бежит по туннелю, перегороженному воротами. Над каждым проёмом буква,
	голос называет нужную. Пройти мимо выбора невозможно — в этом вся суть:
	буква не бонус на обочине, а единственный способ двигаться дальше.

	Ошибка не убивает и ничего не отнимает — она замедляет на секунду с небольшим,
	и за это время звучит подсказка. Это то же правило, что в «Буквопаде».

	Модуль отвечает только за ПЛАН забега и правила. Геометрию строит TunnelService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Tunnel = require(Shared.Config.Tunnel)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local TunnelRun = {}

TunnelRun.id = "tunnel_run"
TunnelRun.trains = { "recognize", "sound_to_letter" }
TunnelRun.minLetters = 2

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Строит план забега: где ворота, какие буквы в проёмах, где препятствия.

	letters — очередь повторений. Первая буква становится главной целью забега:
	один туннель — одна буква, чтобы ребёнок успел с ней освоиться.
]]
function TunnelRun.Build(_player: Player, letters: { string }, difficulty: number)
	assert(#letters >= TunnelRun.minLetters, "TunnelRun: нужно минимум две буквы")

	local gateCount = DifficultyCurve.pick(Tunnel.PARAMS.gates, difficulty)
	local choiceCount = math.min(DifficultyCurve.pick(Tunnel.PARAMS.choices, difficulty), Tunnel.LANE_COUNT)
	local barrierCount = DifficultyCurve.pick(Tunnel.PARAMS.barriers, difficulty)
	local slowSeconds = DifficultyCurve.pick(Tunnel.PARAMS.missSlowSeconds, difficulty)
	local slowFactor = DifficultyCurve.pick(Tunnel.PARAMS.missSlowFactor, difficulty)

	local targetId = letters[1]

	local distractorPool: { string } = {}
	for index = 2, #letters do
		table.insert(distractorPool, letters[index])
	end
	if #distractorPool == 0 then
		for _, id in Letters.ordered() do
			if id ~= targetId then
				table.insert(distractorPool, id)
			end
		end
	end

	local seed = math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(seed)

	local gates = {}
	for index = 1, gateCount do
		-- Дорожки для проёмов выбираем случайно, но целевая буква обязана
		-- оказаться на одной из них.
		local lanes = {}
		for lane = 1, Tunnel.LANE_COUNT do
			table.insert(lanes, lane)
		end
		lanes = shuffled(lanes, random)

		local openings = {}
		local targetSlot = random:NextInteger(1, choiceCount)

		for slot = 1, choiceCount do
			local letterId = if slot == targetSlot
				then targetId
				else distractorPool[random:NextInteger(1, #distractorPool)]

			table.insert(openings, {
				lane = lanes[slot],
				letterId = letterId,
				glyph = Letters.expect(letterId).glyph,
				isTarget = slot == targetSlot,
			})
		end

		table.insert(gates, {
			index = index,
			z = Tunnel.START_RUNWAY + index * Tunnel.GATE_SPACING,
			openings = openings,
		})
	end

	-- Препятствия живут МЕЖДУ воротами: пока ребёнок решает буквенную задачу,
	-- от него не требуется моторики, иначе буква выбирается наугад.
	local barriers = {}
	for gateIndex = 1, gateCount do
		local from = Tunnel.START_RUNWAY + (gateIndex - 1) * Tunnel.GATE_SPACING
		local to = Tunnel.START_RUNWAY + gateIndex * Tunnel.GATE_SPACING
		for step = 1, barrierCount do
			local z = from + (to - from) * (step / (barrierCount + 1))
			-- Барьер перекрывает одну дорожку: обойти можно всегда, прыгать необязательно.
			table.insert(barriers, { z = z, lane = random:NextInteger(1, Tunnel.LANE_COUNT) })
		end
	end

	return {
		challengeId = TunnelRun.id,
		seed = seed,
		letters = letters,
		difficulty = difficulty,
		targetCount = gateCount,
		params = {
			targetLetter = targetId,
			targetGlyph = Letters.expect(targetId).glyph,
			targetVO = Letters.expect(targetId).vo.sound,
			gates = gates,
			barriers = barriers,
			length = Tunnel.length(gateCount),
			slowSeconds = slowSeconds,
			slowFactor = slowFactor,
		},
	}
end

--[[
	Проверяет прохождение ворот.

	Действие приходит НЕ от клиента, а от серверного триггера в туннеле
	(TunnelService ловит касание проёма). Клиенту здесь верить не нужно вовсе.
]]
function TunnelRun.Validate(state, action)
	if typeof(action) ~= "table" then
		return { handled = false }
	end

	if action.kind == "finish" then
		return { handled = true, correct = false, silent = true, finished = true }
	end

	if action.kind ~= "gate" or typeof(action.gateIndex) ~= "number" then
		return { handled = false }
	end

	local gates = state.spec.params.gates
	local gate = gates[action.gateIndex]
	if not gate then
		return { handled = false }
	end

	-- Одни ворота засчитываются один раз: ребёнок может потоптаться в проёме.
	state.answered = state.answered or {}
	if state.answered[action.gateIndex] then
		return { handled = false }
	end
	state.answered[action.gateIndex] = true

	local opening
	for _, candidate in gate.openings do
		if candidate.lane == action.lane then
			opening = candidate
			break
		end
	end
	if not opening then
		return { handled = false }
	end

	local correct = opening.isTarget
	if correct then
		state.caught += 1
	else
		state.missed += 1
	end

	return {
		handled = true,
		correct = correct,
		gateIndex = action.gateIndex,
		letterId = state.spec.params.targetLetter,
		tappedLetterId = if correct then nil else opening.letterId,
		cooldown = if correct then 0 else state.spec.params.slowSeconds,
		slowFactor = state.spec.params.slowFactor,
		reactionMs = math.max(0, math.floor((os.clock() - (state.gateStartedAt or state.startedAt)) * 1000)),
		finished = false, -- забег заканчивается на финишной черте, а не на последних воротах
	}
end

function TunnelRun.Finish(state)
	local total = state.spec.targetCount
	local passed = state.caught

	local stars = 1
	if passed >= total and state.missed == 0 then
		stars = 3
	elseif passed >= math.ceil(total * 0.6) then
		stars = 2
	end

	return {
		challengeId = TunnelRun.id,
		stars = stars,
		caught = passed,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

-- Времени с запасом: ребёнок бежит сам и может остановиться подумать у каждых ворот.
function TunnelRun.duration(spec): number
	return spec.targetCount * 45 + 60
end

return TunnelRun
