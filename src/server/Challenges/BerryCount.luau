--!nonstrict
--[[
	Испытание «Ягодная поляна». См. docs/16-MATH.md § 3.2.

	Голос говорит, сколько ягод собрать. По краю поляны растут кусты с ягодами,
	в центре стоит корзинка. Ребёнок бегает, собирает ягоды и несёт их в корзинку.
	Столько, сколько надо, — засчитано. Больше или меньше — ничего страшного:
	ягоды возвращаются на кусты, и можно собрать заново.

	Это единственное место, где счёт тренируется действием, а не выбором:
	ребёнок считает, пока бежит, и в корзинку несёт ровно столько, сколько насчитал.
	Цифр на экране нет — только ягоды, которые он уже держит.

	Задание зависит от ступени счёта:
	  · счёт и цифры — «Собери ягод: три»;
	  · сложение и вычитание — «Сколько будет два плюс один? Собери столько ягод»;
	  · состав числа — в корзинке уже лежат ягоды, «доложи, чтобы стало пять».

	Ответ засчитывается текущей ступени ребёнка. Это второе испытание по счёту
	после ворот с числами, и с ним ступени до состава числа осваиваются по тому же
	правилу двух разных занятий, что и буквы (ProgressService).

	Контракт модуля испытания: Build → Validate (много раз) → Finish.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MathConfig = require(Shared.Config.Math)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local BerryCount = {}

BerryCount.id = "berries"
BerryCount.trains = { "count" }
BerryCount.minLetters = 0
BerryCount.usesMathStage = true

-- Ягод на поляне не больше, чем ребёнок обежит за раунд, и кустов под них хватает.
BerryCount.MAX_BERRIES = 12
BerryCount.SPOTS = 16
BerryCount.SPOT_RADIUS = { 15, 22 } -- ближний и дальний круг кустов вокруг корзинки

--[[
	Места для ягод: два круга вокруг корзинки, восемь мест в каждом, дальний
	повёрнут на полшага — так кусты не встают один за другим на одной линии.
]]
function BerryCount.spot(index: number): Vector2
	local ring = if index <= BerryCount.SPOTS / 2 then 1 else 2
	local inRing = BerryCount.SPOTS / 2
	local order = (index - 1) % inRing
	local angle = (order + (ring - 1) * 0.5) / inRing * math.pi * 2
	local radius = BerryCount.SPOT_RADIUS[ring]
	return Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
end

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Задача раунда для ступени. Сложение и вычитание берутся из общего генератора
	(Config/Math), чтобы пример звучал так же, как в воротах. Счёт и цифры —
	просто «собери N». Больше/меньше и групп здесь нет: сравнивать не с чем,
	и группы — не про сбор по одной ягоде; им отдаётся счёт в пределах ступени.
]]
function BerryCount.roundFor(stage: number, random: Random, extra: number)
	local spec = MathConfig.get(stage) or MathConfig.expect(1)
	local cap = math.min(MathConfig.MAX_NUMBER, BerryCount.MAX_BERRIES - extra)
	local given = 0
	local target: number
	local vo: { string }
	local prompt = ""

	if spec.kind == "add" or spec.kind == "sub" then
		local task = MathConfig.generate(stage, random, 2)
		target = math.clamp(task.answer, 1, cap)
		vo = table.clone(task.vo)
		table.insert(vo, "mtask_collect_that")
		prompt = task.prompt
	elseif spec.kind == "compose" then
		local total = random:NextInteger(math.max(3, spec.min), math.min(spec.max, cap))
		given = random:NextInteger(1, total - 1)
		target = total - given
		vo = { "mtask_fill", `num_{total}` }
	else
		local low = math.max(1, spec.min)
		local high = math.clamp(spec.max, low, cap)
		target = random:NextInteger(low, high)
		vo = { "mtask_collect", `num_{target}` }
	end

	return { target = target, given = given, vo = vo, prompt = prompt }
end

function BerryCount.Build(
	_player: Player?,
	_letters: { string },
	difficulty: number,
	stage: number?,
	seed: number?
)
	local meta = Challenges.expect(BerryCount.id)
	local roundCount = DifficultyCurve.pick(meta.params.rounds, difficulty)
	local extra = DifficultyCurve.pick(meta.params.extra, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)
	local stageIndex = stage or 1
	local topic = (MathConfig.get(stageIndex) or MathConfig.expect(1)).id

	local runSeed = seed or math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(runSeed)

	local spotIds: { number } = {}
	for index = 1, BerryCount.SPOTS do
		table.insert(spotIds, index)
	end

	local rounds = {}
	local previous = 0
	for index = 1, roundCount do
		local round = BerryCount.roundFor(stageIndex, random, extra)
		-- Одно и то же число два раза подряд — повтор, а не задание.
		if round.target == previous and round.given == 0 then
			round = BerryCount.roundFor(stageIndex, random, extra)
		end
		previous = round.target

		local berryCount = math.min(round.target + extra, BerryCount.MAX_BERRIES)
		local berries = {}
		for slot, spot in shuffled(spotIds, random) do
			if slot > berryCount then
				break
			end
			local at = BerryCount.spot(spot)
			table.insert(berries, { index = slot, x = at.X, z = at.Y })
		end

		round.index = index
		round.berries = berries
		table.insert(rounds, round)
	end

	return {
		challengeId = BerryCount.id,
		seed = runSeed,
		letters = {},
		difficulty = difficulty,
		stage = stageIndex,
		targetCount = roundCount,
		params = {
			rounds = rounds,
			mathStageId = topic,
			missCooldown = missCooldown,
			taskVO = rounds[1] and rounds[1].vo,
			taskPrompt = rounds[1] and rounds[1].prompt or "",
		},
	}
end

--[[
	Действия клиента:
	  pick   — сорвал ягоду berry в раунде round. Тихое действие: ни звезды,
	           ни голоса, только счёт в корзине у сервера;
	  basket — принёс ягоды в корзинку. Вот это ответ: сколько сорвал, столько
	           и проверяем.
]]
function BerryCount.Validate(state, action)
	if typeof(action) ~= "table" or typeof(action.round) ~= "number" then
		return { handled = false }
	end

	state.round = state.round or 1
	local round = state.spec.params.rounds[state.round]
	if not round or action.round ~= state.round then
		return { handled = false }
	end

	local now = os.clock()
	if state.blockedUntil and now < state.blockedUntil then
		return { handled = false, blocked = true }
	end

	state.picked = state.picked or {}

	if action.kind == "pick" then
		if
			typeof(action.berry) ~= "number"
			or not round.berries[action.berry]
			or state.picked[action.berry]
		then
			return { handled = false }
		end
		state.picked[action.berry] = true
		return { handled = true, silent = true }
	end

	if action.kind ~= "basket" then
		return { handled = false }
	end

	local picked = 0
	for _ in state.picked do
		picked += 1
	end
	if picked == 0 then
		return { handled = false }
	end

	local correct = picked == round.target
	local since = state.roundStartedAt or state.startedAt
	local cooldown = 0
	state.picked = {}

	local following = nil
	if correct then
		state.caught += 1
		state.round += 1
		state.roundStartedAt = now
		following = state.spec.params.rounds[state.round]
	else
		state.missed += 1
		cooldown = state.spec.params.missCooldown
		state.blockedUntil = now + cooldown
	end

	return {
		handled = true,
		correct = correct,
		cooldown = cooldown,
		sectionIndex = round.index,
		topic = "math",
		topicId = state.spec.params.mathStageId,
		-- Сколько ягод принёс: верно — голос называет, сколько стало в корзинке,
		-- неверно — сколько принёс, а потом задание звучит снова.
		tappedValue = picked + round.given,
		stepVO = `num_{picked + round.given}`,
		voAfter = if correct then (following and following.vo) else round.vo,
		nextPrompt = if correct then (following and following.prompt or "") else round.prompt,
		reactionMs = math.max(0, math.floor((now - since) * 1000)),
		finished = state.round > #state.spec.params.rounds,
	}
end

function BerryCount.Finish(state)
	local total = state.spec.targetCount
	local stars = 1
	if state.caught >= total and state.missed == 0 then
		stars = 3
	elseif state.caught >= total then
		stars = 2
	end
	return {
		challengeId = BerryCount.id,
		stars = stars,
		caught = state.caught,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

function BerryCount.duration(_spec): number
	return Challenges.expect(BerryCount.id).maxSeconds
end

return BerryCount
