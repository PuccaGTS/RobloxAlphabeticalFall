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
local Letters = require(Shared.Config.Letters)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local RateLimiter = require(script.Parent.RateLimiter)

local LetterRain = require(script.Parent.Parent.Challenges.LetterRain)
local AlphabetLadder = require(script.Parent.Parent.Challenges.AlphabetLadder)
local TunnelRun = require(script.Parent.Parent.Challenges.TunnelRun)
local ObstacleCourse = require(script.Parent.Parent.Challenges.ObstacleCourse)
local MathGates = require(script.Parent.Parent.Challenges.MathGates)
local Bubbles = require(script.Parent.Parent.Challenges.Bubbles)
local Mirror = require(script.Parent.Parent.Challenges.Mirror)

local ChallengeService = {}

local MODULES = {
	[LetterRain.id] = LetterRain,
	[AlphabetLadder.id] = AlphabetLadder,
	[TunnelRun.id] = TunnelRun,
	[ObstacleCourse.id] = ObstacleCourse,
	[MathGates.id] = MathGates,
	[Bubbles.id] = Bubbles,
	[Mirror.id] = Mirror,
}

local active: { [Player]: any } = {}

--[[
	Хуки жизненного цикла испытания.

	Нужны, чтобы миростроительные сервисы (например, TunnelService) могли поднять
	и убрать геометрию, не создавая кольцевой зависимости: ChallengeService не знает
	про туннели, туннели знают про ChallengeService.
]]
local startedHooks: { (player: Player, spec: any) -> () } = {}
local finishedHooks: { (player: Player, spec: any, reason: string) -> () } = {}

function ChallengeService.onStarted(hook: (player: Player, spec: any) -> ())
	table.insert(startedHooks, hook)
end

function ChallengeService.onFinished(hook: (player: Player, spec: any, reason: string) -> ())
	table.insert(finishedHooks, hook)
end

-- Хук на каждый ответ: нужен, например, чтобы притормозить бегущего после неверных ворот.
local answerHooks: { (player: Player, spec: any, result: any) -> () } = {}

function ChallengeService.onAnswer(hook: (player: Player, spec: any, result: any) -> ())
	table.insert(answerHooks, hook)
end

--[[
	Сторожа старта: любой из них может сказать «сейчас нельзя» — например,
	вышло время на сегодня. Сторож сам сообщает ребёнку почему; ChallengeService
	только не запускает испытание и не знает, кто и за что его остановил.
]]
local startGuards: { (player: Player, challengeId: string) -> boolean } = {}

function ChallengeService.addStartGuard(guard: (player: Player, challengeId: string) -> boolean)
	table.insert(startGuards, guard)
end

-- Идёт ли у игрока испытание. Лимит времени ждёт его конца, а не обрывает на бегу.
function ChallengeService.isBusy(player: Player): boolean
	return active[player] ~= nil
end

local function fire(hooks, ...)
	for _, hook in hooks do
		local ok, err = pcall(hook, ...)
		if not ok then
			warn(`[ChallengeService] хук упал: {err}`)
		end
	end
end

local function randomVO(prefix: string, count: number): string
	return string.format("%s_%02d", prefix, math.random(1, math.max(1, count)))
end

local function playVO(player: Player, key: string, interrupt: boolean?)
	RemoteDefs.event("PlayVO"):FireClient(player, key, interrupt == true)
end

--[[
	Фраза из нескольких реплик подряд — так говорит математика: «Сколько будет» +
	«два» + «плюс» + «два». Для ребёнка это одно задание, поэтому и уходит оно
	одним сообщением: клиент запомнит фразу целиком, и кнопка «повторить» повторит
	её всю, а не последний кусок.
]]
local function playPhrase(player: Player, keys: { string }?, interrupt: boolean?)
	if typeof(keys) ~= "table" or #keys == 0 then
		return
	end
	RemoteDefs.event("PlayPhrase"):FireClient(player, keys, interrupt == true)
end

local function finish(player: Player, reason: string)
	local state = active[player]
	if not state then
		return
	end
	active[player] = nil

	fire(finishedHooks, player, state.spec, reason)

	--[[
		Дошёл до финиша — сохранка больше не нужна: следующий раз это будет
		новый забег с новым сидом. Любой другой исход (вышел домой, тайм-аут,
		закрыл игру) сохранку оставляет: именно ради него она и заводилась.
	]]
	if reason == "completed" and state.module.Rebuild then
		ProgressService.clearRun(player, state.module.id)
	end

	--[[
		Финиш уровня открывает следующий — сколько бы ворот ни было взято.
		Ошибка стоит времени, а не прогресса: буквы, на которых ребёнок ошибся,
		вернутся к нему повторением на следующих уровнях.
	]]
	local levelCleared = if reason == "completed" then state.spec.level else nil
	if levelCleared then
		ProgressService.clearLevel(player, levelCleared)
	end

	local result = state.module.Finish(state)

	--[[
		Награда за испытание — только если ребёнок в нём хоть что-то сделал.
		Иначе перезапуск (например, повторное касание пада) сам по себе приносил
		звёздочки, и «фарм» сводился к тому, чтобы топтаться на портале.
	]]
	local awarded = 0
	if #state.answers > 0 then
		awarded = ProgressService.finishChallenge(player, state.module.id, result.stars)
	end

	RemoteDefs.event("ChallengeEnd"):FireClient(player, {
		challengeId = state.module.id,
		stars = result.stars,
		caught = result.caught,
		targetCount = result.targetCount,
		stars_awarded = awarded,
		reason = reason,
		levelCleared = levelCleared,
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
	Собирает буквы для задания: сначала очередь повторений, следом все остальные
	доступные буквы.

	Порядок здесь и есть договор с испытаниями: первая буква — то, что планировщик
	просит показать сегодня, остальные — материал для отвлекающих вариантов.
	Хвост из всех доступных букв нужен «Алфавитной лестнице»: она поднимается
	по соседним буквам, и ей нужен весь отрезок азбуки, а не выборка из него.
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

	for _, id in ProgressService.availableLetters(profile) do
		if not seen[id] then
			seen[id] = true
			table.insert(letters, id)
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

	--[[
		Идущее испытание не перезапускаем.

		Раньше повторный запрос обрывал текущее и строил новое: ребёнок стоял на паде,
		касания шли одно за другим, арена пересобиралась в его текущей позиции —
		и выглядело это так, будто стенд с буквами ходит за ним следом,
		а буква-цель меняется сама по себе.
	]]
	if active[player] then
		return
	end

	for _, guard in startGuards do
		if not guard(player, challengeId) then
			return
		end
	end

	local letters = lettersFor(player, module)
	if not letters then
		warn(`[ChallengeService] {player.Name}: не хватает букв для {challengeId}`)
		return
	end

	local difficulty = ProgressService.difficultyFor(player, challengeId)

	--[[
		Место на пути своего мира: ступень счёта для математики, уровень для букв.
		Выбирает его не ребёнок, а прогресс: читать он не умеет, а меню ступеней
		и уровней ему не нужно. Испытаниям с площади этот аргумент не нужен,
		и они его не берут.
	]]
	local track = if module.usesMathStage
		then ProgressService.mathStage(player)
		elseif module.usesLevel then ProgressService.lettersLevel(player)
		else nil

	--[[
		Незаконченный забег продолжается, а не начинается заново.

		Испытание умеет это, если объявило Rebuild: тогда план собирается из рецепта,
		лежащего в профиле, и ребёнок оказывается в том же туннеле на той же арке.
		Испытания без сохранок (Буквопад, Лестница) идут обычным путём.

		Битую запись из DataStore тихо выбрасываем и строим новый забег: испорченный
		профиль не повод не пустить ребёнка в игру.
	]]
	local saved = if module.Rebuild then ProgressService.savedRun(player, challengeId) else nil
	local spec
	if saved then
		local ok, rebuilt = pcall(module.Rebuild, saved)
		if ok then
			spec = rebuilt
		else
			warn(
				`[ChallengeService] сохранка {challengeId} не восстановилась: {rebuilt}`
			)
			ProgressService.clearRun(player, challengeId)
			saved = nil
		end
	end
	spec = spec or module.Build(player, letters, difficulty, track)

	--[[
		Найденный секрет уровня больше не появляется: план забега об этом не знает
		(он собирается из рецепта и должен быть одинаковым), поэтому отметка ставится
		здесь, поверх готового плана.
	]]
	local secret = spec.params.secret
	if secret and spec.level and ProgressService.secretFound(player, spec.level) then
		secret.found = true
	end

	local state = {
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
	active[player] = state

	if saved and module.Resume then
		module.Resume(state)
	end

	--[[
		Знакомство с новой буквой — до инструкции.

		Порядок реплик важен: сначала «Познакомься! Это буква М», и только потом
		«лови вот эту». Сперва ребёнку показывают, кто это, и лишь затем просят
		с ней что-то сделать.

		Реплик две, а не одна: общее «познакомься» плюс название буквы. Так на все
		33 буквы уходит 34 записи вместо 33 отдельных знакомств — см. docs/05-AUDIO-VO.md § 2.
	]]
	local targetLetter = spec.params.targetLetter
	if targetLetter and ProgressService.isFirstMeeting(player, targetLetter) then
		local letter = Letters.get(targetLetter)
		if letter then
			spec.params.introGlyph = letter.glyph
			playVO(player, "story_meet_letter", true)
			playVO(player, letter.vo.name)
		end
	end

	fire(startedHooks, player, spec)

	RemoteDefs.event("ChallengeSpec"):FireClient(player, spec)
	playVO(player, Challenges.expect(challengeId).voInstruction)

	--[[
		Задача первых ворот звучит сразу за инструкцией: у ворот с числами задание
		своё на каждые ворота, и без этого ребёнок побежал бы к первым, не услышав,
		что от него хотят.
	]]
	playPhrase(player, spec.params.taskVO)

	-- Страховка: испытание не может висеть вечно, даже если клиент замолчал.
	-- Когда падать больше нечему, испытание обязано закончиться само и сразу:
	-- «поймал 4 из 5, и ничего не происходит» — это ощущение поломки.
	local timeout = math.min(module.duration(spec), Challenges.expect(challengeId).maxSeconds)
	task.delay(timeout + 1, function()
		local current = active[player]
		if current and current.spec == spec then
			finish(player, "timeout")
		end
	end)
end

local function handleAction(player: Player, action: any, trusted: boolean)
	local state = active[player]
	if not state then
		return
	end

	-- Действия из мира (касание ворот) приходят от сервера и лимиту не подлежат:
	-- ограничивать надо клиента, а не собственные триггеры.
	if
		not trusted
		and not RateLimiter.allow(player, "ChallengeAction", RemoteDefs.RATE_LIMITS.ChallengeAction)
	then
		return
	end

	local result = state.module.Validate(state, action)
	if not result.handled then
		return
	end

	--[[
		Буква, подобранная на дорожке: звёздочка и звон, но не ответ. Ни похвалы
		голосом, ни следующего задания — иначе голос тараторил бы на каждом
		шаге забега и перебивал задание ворот.
	]]
	--[[
		Секрет уровня: голос называет золотую букву — это повторение, ради которого
		секрет и сделан буквой, а не сундуком, — и за первую находку 15 ⭐.
	]]
	if result.secret then
		local awarded = ProgressService.claimSecret(player, state.spec.level, result.letterId)
		fire(answerHooks, player, state.spec, result)
		RemoteDefs.event("PlaySfx"):FireClient(player, "reward")
		local letter = Letters.get(result.letterId)
		if letter then
			playVO(player, letter.vo.name)
		end
		print(
			`[Challenge] {player.Name} нашёл секрет уровня {state.spec.level}: +{awarded} ⭐`
		)
		return
	end

	if result.collect then
		ProgressService.awardCollect(player, result.letterId)
		fire(answerHooks, player, state.spec, result)
		RemoteDefs.event("PlaySfx"):FireClient(player, "correct")
		return
	end

	-- «Тихое» действие (пересечение финиша) прогресс не двигает и наград не приносит.
	if result.silent then
		if result.finished then
			finish(player, "completed")
		end
		return
	end

	--[[
		Что именно осваивается, решает испытание: буква или ступень счёта. Формат
		ответа при этом один и тот же — правила освоения у обеих веток общие
		(docs/16-MATH.md § 4).
	]]
	local isMath = result.topic == "math"
	local answer = {
		letterId = if isMath then result.topicId else result.letterId,
		challengeId = state.module.id,
		correct = result.correct,
		reactionMs = result.reactionMs,
		hintsUsed = state.hintsUsed or 0,
	}
	table.insert(state.answers, answer)

	local outcome = if isMath
		then ProgressService.applyMathAnswer(player, answer)
		else ProgressService.applyAnswer(player, answer)
	fire(answerHooks, player, state.spec, result)

	local voKey = if result.correct
		then randomVO("praise", AudioRegistry.PRAISE_COUNT)
		else randomVO("retry", AudioRegistry.RETRY_COUNT)

	--[[
		Уровень сменил букву посреди забега. Если с новой буквой ребёнок ещё
		не встречался, сперва знакомство, потом название — тот же порядок,
		что и на старте забега: сначала показываем, кто это, потом просим найти.
	]]
	local voAfter = result.voAfter
	local introGlyph = nil
	if result.nextLetter and ProgressService.isFirstMeeting(player, result.nextLetter) then
		local letter = Letters.get(result.nextLetter)
		if letter then
			introGlyph = letter.glyph
			voAfter = { "story_meet_letter", letter.vo.name }
		end
	end

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
		-- «Алфавитная лестница» отдаёт взятую букву: клиент напишет её на ступени
		stepVO = result.stepVO,
		stepGlyph = result.stepGlyph,
		-- Ворота с числами: во что ребёнок вбежал и какой пример его ждёт дальше
		tappedValue = result.tappedValue,
		nextPrompt = result.nextPrompt,
		-- Уровень мира букв: буква следующего отрезка и знакомство с ней, если оно первое
		nextGlyph = result.nextGlyph,
		introGlyph = introGlyph,
		mastery = if outcome then outcome.mastery else nil,
	})

	-- Сначала название взятой буквы, и только потом похвала: эталон важнее реакции.
	if result.stepVO then
		playVO(player, result.stepVO)
	end
	playVO(player, voKey)

	--[[
		После реакции — задача следующих ворот (или та же самая, если ребёнок
		ошибся). Порядок именно такой: сперва короткое «молодец», потом новое
		задание, иначе задание перебивается похвалой и его не слышно.
	]]
	playPhrase(player, voAfter)

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

--[[
	Действие, порождённое самим сервером: касание ворот или финишной черты в туннеле.
	Клиенту здесь верить не нужно вовсе — он о таком действии даже не знает.
]]
function ChallengeService.submitAction(player: Player, action: any)
	handleAction(player, action, true)
end

function ChallengeService.start()
	RateLimiter.start()

	RemoteDefs.event("StartChallenge").OnServerEvent:Connect(onStart)
	RemoteDefs.event("ChallengeAction").OnServerEvent:Connect(function(player: Player, action: any)
		handleAction(player, action, false)
	end)

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
