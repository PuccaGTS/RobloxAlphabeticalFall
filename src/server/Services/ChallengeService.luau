--!nonstrict
--[[
	Запуск, валидация и завершение испытаний.

	Сервер — источник истины: он строит задание, он решает, верен ли ответ,
	и он один начисляет награду. Клиент присылает намерения («тапнул по объекту N»),
	а не результаты. См. docs/07-TECH-ARCH.md § 3 и § 5.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Challenges = require(Shared.Config.Challenges)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local RateLimiter = require(script.Parent.RateLimiter)

local LetterRain = require(script.Parent.Parent.Challenges.LetterRain)
local SyllableBridge = require(script.Parent.Parent.Challenges.SyllableBridge)

local ChallengeService = {}

local MODULES = {
	[LetterRain.id] = LetterRain,
	[SyllableBridge.id] = SyllableBridge,
}

local active: { [Player]: any } = {}

local function randomVO(prefix: string, count: number): string
	return string.format("%s_%02d", prefix, math.random(1, math.max(1, count)))
end

local function playVO(player: Player, key: string, interrupt: boolean?)
	RemoteDefs.event("PlayVO"):FireClient(player, key, interrupt == true)
end

local function finish(player: Player, reason: string)
	local state = active[player]
	if not state then
		return
	end
	active[player] = nil

	local result = state.module.Finish(state)
	local awarded = ProgressService.finishChallenge(player, state.module.id, result.stars)

	RemoteDefs.event("ChallengeEnd"):FireClient(player, {
		challengeId = state.module.id,
		stars = result.stars,
		caught = result.caught,
		targetCount = result.targetCount,
		stars_awarded = awarded,
		reason = reason,
	})

	print(
		string.format(
			"[Challenge] %s завершил %s: %d звезды, +%d ⭐ (%s)",
			player.Name,
			state.module.id,
			result.stars,
			awarded,
			reason
		)
	)
end

--[[
	Собирает буквы для задания: очередь повторений, дополненная доступными буквами,
	если планировщик дал слишком мало (например, в самом начале игры).
]]
local function lettersFor(player: Player, module): { string }?
	local profile = ProfileService.get(player)
	if not profile then
		return nil
	end

	local queue = ProgressService.buildQueue(player)
	local letters: { string } = if queue then table.clone(queue.flat) else {}

	local seen: { [string]: boolean } = {}
	for _, id in letters do
		seen[id] = true
	end

	if #letters < module.minLetters then
		for _, id in ProgressService.availableLetters(profile) do
			if not seen[id] then
				seen[id] = true
				table.insert(letters, id)
			end
			if #letters >= module.minLetters then
				break
			end
		end
	end

	if #letters < module.minLetters then
		return nil
	end
	return letters
end

local function onStart(player: Player, challengeId: any)
	if typeof(challengeId) ~= "string" then
		return
	end

	local module = MODULES[challengeId]
	if not module then
		warn(`[ChallengeService] запрошено неизвестное испытание: {challengeId}`)
		return
	end

	if not RateLimiter.allow(player, "StartChallenge", RemoteDefs.RATE_LIMITS.StartChallenge) then
		return
	end

	if active[player] then
		finish(player, "restart")
	end

	local letters = lettersFor(player, module)
	if not letters then
		warn(`[ChallengeService] {player.Name}: не хватает букв для {challengeId}`)
		return
	end

	local difficulty = ProgressService.difficultyFor(player, challengeId)
	local spec = module.Build(player, letters, difficulty)

	active[player] = {
		module = module,
		spec = spec,
		startedAt = os.clock(),
		sectionStartedAt = os.clock(),
		answered = {},
		section = 0,
		caught = 0,
		missed = 0,
		answers = {},
	}

	RemoteDefs.event("ChallengeSpec"):FireClient(player, spec)
	playVO(player, Challenges.expect(challengeId).voInstruction, true)

	-- Страховка: испытание не может висеть вечно, даже если клиент замолчал.
	local timeout = math.min(module.duration(spec), Challenges.expect(challengeId).maxSeconds)
	task.delay(timeout + 3, function()
		local state = active[player]
		if state and state.spec == spec then
			finish(player, "timeout")
		end
	end)
end

local function onAction(player: Player, action: any)
	local state = active[player]
	if not state then
		return
	end

	if not RateLimiter.allow(player, "ChallengeAction", RemoteDefs.RATE_LIMITS.ChallengeAction) then
		return
	end

	local result = state.module.Validate(state, action)
	if not result.handled then
		return
	end

	local answer = {
		letterId = result.letterId,
		challengeId = state.module.id,
		correct = result.correct,
		reactionMs = result.reactionMs,
		hintsUsed = state.hintsUsed or 0,
	}
	table.insert(state.answers, answer)

	local outcome = ProgressService.applyAnswer(player, answer)

	-- Прочитанный впервые слог — отдельная награда, один раз за слог.
	if result.syllableId then
		ProgressService.markSyllableRead(player, result.syllableId)
	end

	local voKey = if result.correct
		then randomVO("praise", AudioRegistry.PRAISE_COUNT)
		else randomVO("retry", AudioRegistry.RETRY_COUNT)

	RemoteDefs.event("ChallengeFeedback"):FireClient(player, {
		itemIndex = result.itemIndex,
		sectionIndex = result.sectionIndex,
		correct = result.correct,
		-- сколько секунд «сачок опущен» после промаха
		cooldown = result.cooldown or 0,
		caught = state.caught,
		targetCount = state.spec.targetCount,
		vo = voKey,
		-- буква, по которой ребёнок промахнулся: клиент озвучит «Это П. А нам нужна М»
		tappedLetterId = if result.correct then nil else result.tappedLetterId,
		syllableVO = result.syllableVO,
		syllableText = result.syllableText,
		mastery = if outcome then outcome.mastery else nil,
	})

	-- Сначала слитный слог, и только потом похвала: эталон звучания важнее реакции.
	if result.syllableVO then
		playVO(player, result.syllableVO)
	end
	playVO(player, voKey)

	if result.finished then
		finish(player, "completed")
	end
end

--[[
	Запуск испытания со стороны сервера — например, с портала в хабе.
	Проходит ту же валидацию, что и запрос от клиента.
]]
function ChallengeService.startFor(player: Player, challengeId: string)
	onStart(player, challengeId)
end

function ChallengeService.start()
	RateLimiter.start()

	RemoteDefs.event("StartChallenge").OnServerEvent:Connect(onStart)
	RemoteDefs.event("ChallengeAction").OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(function(player: Player)
		active[player] = nil
	end)
end

function ChallengeService.abort(player: Player)
	if active[player] then
		finish(player, "aborted")
	end
end

return ChallengeService
