--!nonstrict
--[[
	Испытание «Пол — это лава!». См. docs/03-CHALLENGES.md § 9.

	Арена из плит с буквами. Голос называет букву, и через несколько секунд
	весь пол, кроме плит с этой буквой, становится лавой. Успел встать на свою
	букву — звёздочка; не успел или встал не туда — лава подбрасывает вверх,
	и следующий раунд начинается как ни в чём не бывало. Плиты каждый раунд
	перемешиваются, своих становится меньше, времени — тоже.

	Это единственное занятие с площади, где буква узнаётся на бегу и под
	мягким давлением времени. Полоса препятствий, стоявшая на этом паде,
	была тем же забегом, что и портал: на живой проверке 17.09.2026 разницы
	между ними не увидели. Паркур живёт теперь в забеге, а здесь — игра.

	Раунды идут по расписанию серверных часов: клиент (LavaController) рисует
	его сам, сервер (Services/LavaFloorService) в момент лавы смотрит, на какой
	плите стоит ребёнок, и присылает это действием от себя. Клиенту ответ
	не доверяется вовсе.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local LavaFloor = {}

LavaFloor.id = "lava_floor"
LavaFloor.trains = { "recognize" }
LavaFloor.minLetters = 2

-- Арена: GRID × GRID плит со стороной TILE и зазором GAP.
LavaFloor.GRID = 5
LavaFloor.TILE = 6
LavaFloor.GAP = 0.8
LavaFloor.PITCH = LavaFloor.TILE + LavaFloor.GAP

LavaFloor.INTRO = 4 -- пока звучит инструкция, пол спокойный
LavaFloor.LAVA_SECONDS = 2.5 -- сколько пол горит
LavaFloor.REST_SECONDS = 1.5 -- пауза перед следующим раундом: плиты перемешиваются
LavaFloor.WARN_SECONDS = 2 -- последние секунды перед лавой чужие плиты теплеют
LavaFloor.MIN_TARGETS = 2

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Отвлекающие буквы: похожие по начертанию из доступных, потом остальные доступные.
local function distractors(letters: { string }, targetId: string, count: number, random: Random): { string }
	local target = Letters.expect(targetId)
	local available: { [string]: boolean } = {}
	for _, id in letters do
		available[id] = true
	end
	local pool: { string } = {}
	for _, id in target.confusableWith do
		if available[id] and id ~= targetId then
			table.insert(pool, id)
		end
	end
	for _, id in shuffled(letters, random) do
		if id ~= targetId and not table.find(pool, id) then
			table.insert(pool, id)
		end
	end
	if #pool < count then
		for _, id in shuffled(Letters.ordered(), random) do
			if id ~= targetId and not table.find(pool, id) then
				table.insert(pool, id)
			end
		end
	end
	local picked = {}
	for index = 1, math.min(count, #pool) do
		table.insert(picked, pool[index])
	end
	return picked
end

-- Сколько плит со своей буквой в раунде: каждые два раунда на одну меньше.
function LavaFloor.targetsInRound(first: number, round: number): number
	return math.max(LavaFloor.MIN_TARGETS, first - (round - 1) // 2)
end

-- Где начинается раунд и когда в нём загорается лава, от начала испытания.
function LavaFloor.roundStart(params, round: number): number
	local cycle = params.seconds + LavaFloor.LAVA_SECONDS + LavaFloor.REST_SECONDS
	return LavaFloor.INTRO + (round - 1) * cycle
end

function LavaFloor.lavaAt(params, round: number): number
	return LavaFloor.roundStart(params, round) + params.seconds
end

--[[
	Плита под точкой: номер в сетке или nil, если точка вне арены.
	local — точка в осях сцены (Venues.stage): x вбок, z от ребёнка вперёд.
]]
function LavaFloor.tileAt(localPosition: Vector3): number?
	local half = LavaFloor.GRID * LavaFloor.PITCH / 2
	local x, z = localPosition.X + half, localPosition.Z + half
	if x < 0 or z < 0 or x >= half * 2 or z >= half * 2 then
		return nil
	end
	local column = math.floor(x / LavaFloor.PITCH) + 1
	local row = math.floor(z / LavaFloor.PITCH) + 1
	return (row - 1) * LavaFloor.GRID + column
end

-- Центр плиты в осях сцены: обратное к tileAt.
function LavaFloor.tileCenter(index: number): Vector3
	local half = LavaFloor.GRID * LavaFloor.PITCH / 2
	local column = (index - 1) % LavaFloor.GRID + 1
	local row = (index - 1) // LavaFloor.GRID + 1
	return Vector3.new(-half + (column - 0.5) * LavaFloor.PITCH, 0, -half + (row - 0.5) * LavaFloor.PITCH)
end

function LavaFloor.Build(
	_player: Player?,
	letters: { string },
	difficulty: number,
	_track: any,
	seed: number?
)
	assert(#letters >= LavaFloor.minLetters, "LavaFloor: нужно минимум две буквы")

	local meta = Challenges.expect(LavaFloor.id)
	local roundCount = DifficultyCurve.pick(meta.params.rounds, difficulty)
	local seconds = DifficultyCurve.pick(meta.params.seconds, difficulty)
	local firstTargets = DifficultyCurve.pick(meta.params.targets, difficulty)
	local kinds = DifficultyCurve.pick(meta.params.kinds, difficulty)

	local runSeed = seed or math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(runSeed)

	local targetId = letters[1]
	local others = distractors(letters, targetId, kinds, random)
	local cells = LavaFloor.GRID * LavaFloor.GRID

	local rounds = {}
	for round = 1, roundCount do
		local targetTiles = LavaFloor.targetsInRound(firstTargets, round)
		local tiles: { string } = {}
		for index = 1, cells do
			tiles[index] = if index <= targetTiles then targetId else others[(index - 1) % #others + 1]
		end
		table.insert(rounds, { index = round, tiles = shuffled(tiles, random), targets = targetTiles })
	end

	local target = Letters.expect(targetId)
	return {
		challengeId = LavaFloor.id,
		seed = runSeed,
		letters = letters,
		difficulty = difficulty,
		targetCount = roundCount,
		params = {
			targetLetter = targetId,
			targetGlyph = target.glyph,
			targetVO = target.vo.name,
			rounds = rounds,
			seconds = seconds,
			grid = LavaFloor.GRID,
			tile = LavaFloor.TILE,
			pitch = LavaFloor.PITCH,
			intro = LavaFloor.INTRO,
			lavaSeconds = LavaFloor.LAVA_SECONDS,
			restSeconds = LavaFloor.REST_SECONDS,
			warnSeconds = LavaFloor.WARN_SECONDS,
		},
	}
end

--[[
	Действия приходят только от сервера (LavaFloorService): «раунд N, ребёнок
	на плите T» и «раунды кончились». Отличает их от клиентских токен, который
	клиенту не отправляется никогда.

	Ребёнок вне арены — не ответ: он мог отойти посмотреть, и засчитывать
	это ошибкой узнавания буквы было бы нечестно. Звёздочки за раунд тогда нет.
]]
function LavaFloor.Validate(state, action)
	if typeof(action) ~= "table" or action.token == nil or action.token ~= state.lavaToken then
		return { handled = false }
	end

	if action.kind == "end" then
		return { handled = true, correct = false, silent = true, finished = true }
	end

	if action.kind ~= "round" or typeof(action.round) ~= "number" then
		return { handled = false }
	end
	local round = state.spec.params.rounds[action.round]
	if not round or state.answered[action.round] then
		return { handled = false }
	end
	state.answered[action.round] = true

	local tile = if typeof(action.tile) == "number" then action.tile else nil
	if tile == nil then
		return { handled = false }
	end

	local letterId = round.tiles[tile]
	local correct = letterId == state.spec.params.targetLetter
	if correct then
		state.caught += 1
	else
		state.missed += 1
	end

	return {
		handled = true,
		correct = correct,
		itemIndex = action.round,
		letterId = state.spec.params.targetLetter,
		tappedLetterId = letterId,
		reactionMs = math.floor(state.spec.params.seconds * 1000),
		finished = false,
	}
end

function LavaFloor.Finish(state)
	local total = state.spec.targetCount
	local caught = state.caught

	local stars = 1
	if caught >= total then
		stars = 3
	elseif caught >= math.ceil(total * 0.6) then
		stars = 2
	end

	return {
		challengeId = LavaFloor.id,
		stars = stars,
		caught = caught,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

-- Все раунды и запас: испытание кончается само, когда кончились раунды.
function LavaFloor.duration(spec): number
	local params = spec.params
	return LavaFloor.lavaAt(params, #params.rounds) + LavaFloor.LAVA_SECONDS + 5
end

return LavaFloor
