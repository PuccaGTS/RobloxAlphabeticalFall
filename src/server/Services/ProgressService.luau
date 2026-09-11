--!nonstrict
--[[
	Прогресс обучения: применяет ответы к профилю, двигает статусы букв и ступеней
	счёта, планирует повторения, открывает ступени алфавита и заказывает награды
	у EconomyService.

	Ветки обучения две — буквы и математика, — и они не блокируют друг друга
	(docs/16-MATH.md § 6). Правила освоения у них общие, поэтому применение ответа
	написано дважды по форме, но опирается на один и тот же MasteryRules.

	Это единственное место, где ответ ребёнка превращается в изменение прогресса.
	Испытания сюда только сообщают факты — решение принимается здесь.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Stages = require(Shared.Config.Stages)
local Levels = require(Shared.Config.Levels)
local MathConfig = require(Shared.Config.Math)
local Economy = require(Shared.Config.Economy)
local MasteryRules = require(Shared.Logic.MasteryRules)
local ReviewScheduler = require(Shared.Logic.ReviewScheduler)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local ProfileService = require(script.Parent.ProfileService)
local EconomyService = require(script.Parent.EconomyService)

local ProgressService = {}

-- Серии верных/неверных ответов для адаптивной сложности: только на время сессии.
local streaksByPlayer: { [Player]: { [string]: DifficultyCurve.Streaks } } = {}

local function streaksFor(player: Player, challengeId: string): DifficultyCurve.Streaks
	local byChallenge = streaksByPlayer[player]
	if not byChallenge then
		byChallenge = {}
		streaksByPlayer[player] = byChallenge
	end

	local streaks = byChallenge[challengeId]
	if not streaks then
		streaks = DifficultyCurve.newStreaks()
		byChallenge[challengeId] = streaks
	end
	return streaks
end

--[[
	Хуки на смену статуса буквы. Нужны питомцам: освоенная буква приносит
	буквёнка. ProgressService при этом не знает про питомцев — питомцы знают
	про прогресс, как туннели про испытания.
]]
local transitionHooks: { (player: Player, transition: MasteryRules.Transition) -> () } = {}

function ProgressService.onTransition(hook: (player: Player, transition: MasteryRules.Transition) -> ())
	table.insert(transitionHooks, hook)
end

local function progressFor(profile, letterId: string, now: number)
	local existing = profile.letters[letterId]
	if existing then
		return existing
	end
	local fresh = MasteryRules.newProgress(now)
	profile.letters[letterId] = fresh
	return fresh
end

--[[
	Пересчитывает открытые ступени. Вызывается после каждого изменения статуса буквы.
	Возвращает список индексов ступеней, открывшихся именно сейчас.
]]
function ProgressService.refreshStages(profile): { number }
	local opened: { number } = {}

	local function masteryOf(letterId: string): number
		local p = profile.letters[letterId]
		return if p then p.mastery else 0
	end

	for _, stage in Stages.all do
		local state = profile.stages[stage.index]
		if not state then
			state = { unlocked = false, chests = {} }
			profile.stages[stage.index] = state
		end

		if not state.unlocked and Stages.isUnlocked(stage.index, masteryOf) then
			state.unlocked = true
			table.insert(opened, stage.index)
		end
	end

	return opened
end

function ProgressService.unlockedStageIndex(profile): number
	local highest = 1
	for index, state in profile.stages do
		if state.unlocked and index > highest then
			highest = index
		end
	end
	return highest
end

--[[
	Буквы открытых ступеней в алфавитном порядке — вход для планировщика повторений.

	Список всегда является началом алфавита без пропусков: ступени идут подряд,
	и это то, на что опирается «Алфавитная лестница», спрашивая «какая следующая».
]]
function ProgressService.availableLetters(profile): { string }
	local maxStage = ProgressService.unlockedStageIndex(profile)
	local ids: { string } = {}
	for _, id in Letters.ordered() do
		if Letters.expect(id).stage <= maxStage then
			table.insert(ids, id)
		end
	end
	return ids
end

function ProgressService.buildQueue(player: Player): ReviewScheduler.Queue?
	local profile = ProfileService.get(player)
	if not profile then
		return nil
	end
	return ReviewScheduler.buildQueue(profile.letters, ProgressService.availableLetters(profile), os.time())
end

export type AnswerOutcome = {
	mastery: number,
	transition: MasteryRules.Transition?,
	openedStages: { number },
	starsAwarded: number,
	difficulty: number,
}

--[[
	Главная функция сервиса: применить один ответ ребёнка.

	answer приходит из серверной части испытания (не от клиента напрямую!) —
	клиент сообщает только «тапнул по объекту X в момент T», а верно это или нет,
	решает валидация испытания. См. docs/07-TECH-ARCH.md § 5.
]]
function ProgressService.applyAnswer(player: Player, answer): AnswerOutcome?
	local profile = ProfileService.get(player)
	if not profile then
		return nil
	end

	if not Letters.get(answer.letterId) then
		warn(`[ProgressService] ответ по неизвестной букве: {answer.letterId}`)
		return nil
	end

	local now = os.time()
	local outcome: AnswerOutcome = {
		mastery = 0,
		transition = nil,
		openedStages = {},
		starsAwarded = 0,
		difficulty = DifficultyCurve.DEFAULT_LEVEL,
	}

	ProfileService.update(player, function(p)
		local before = progressFor(p, answer.letterId, now)
		local updated, transition = MasteryRules.applyAnswer(before, answer, now)
		updated = ReviewScheduler.schedule(updated, answer.correct, now)
		p.letters[answer.letterId] = updated

		outcome.mastery = updated.mastery
		outcome.transition = transition

		if transition then
			outcome.openedStages = ProgressService.refreshStages(p)
		end

		-- Адаптивная сложность живёт на пару (игрок × испытание).
		-- Серии ведём в памяти сессии: они про «здесь и сейчас», а не про историю обучения,
		-- поэтому в профиль (и в DataStore) им попадать незачем.
		local level = p.difficulty[answer.challengeId] or DifficultyCurve.DEFAULT_LEVEL
		local adjusted = DifficultyCurve.apply(level, streaksFor(player, answer.challengeId), answer.correct)
		streaksByPlayer[player][answer.challengeId] = adjusted.streaks
		p.difficulty[answer.challengeId] = adjusted.level
		outcome.difficulty = adjusted.level
	end)

	-- Награды выдаём после изменения профиля, чтобы начисление легло на актуальный прогресс.
	if answer.correct then
		outcome.starsAwarded += EconomyService.award(
			player,
			"correct_answer",
			Economy.REWARDS.correctAnswer,
			answer.letterId
		)
	end

	local transition = outcome.transition
	if transition then
		local reward = Economy.rewardForMasteryTransition(transition.from, transition.to)
		if reward > 0 then
			local source = if transition.to >= MasteryRules.MASTERED
				then "letter_mastered"
				else "letter_learned"
			outcome.starsAwarded += EconomyService.award(player, source, reward, transition.letterId)
		end

		for _, hook in transitionHooks do
			task.spawn(hook, player, transition)
		end
	end

	--[[
		Открылась новая ступень — значит, предыдущая пройдена. Награда идёт за неё:
		это самая крупная разовая выплата в игре, и получить её можно только учась.
	]]
	for _, index in outcome.openedStages do
		outcome.starsAwarded += EconomyService.award(
			player,
			"stage_cleared",
			Economy.REWARDS.stageCleared,
			tostring(index - 1)
		)
	end

	return outcome
end

-- ===== Математика ================================================================

--[[
	Прогресс по счёту устроен так же, как по буквам, и обслуживается тем же кодом:
	MasteryRules и ReviewScheduler не знают, что именно осваивается (docs/16-MATH.md § 4).
	Разница ровно одна, и она вынужденная — испытание у математики пока одно,
	поэтому для перехода в «изученную» хватает успехов в одном типе. Появятся
	«Весы» и сбор предметов — вернём двойку, как у букв.
]]
local MATH_MIN_TYPES = 1

local function mathProgressFor(profile, stageId: string, now: number)
	profile.math = if typeof(profile.math) == "table" then profile.math else {}
	local existing = profile.math[stageId]
	if existing then
		return existing
	end
	local fresh = MasteryRules.newProgress(now)
	profile.math[stageId] = fresh
	return fresh
end

local function mathMasteryOf(profile): (stageId: string) -> number
	return function(stageId: string): number
		local progress = if typeof(profile.math) == "table" then profile.math[stageId] else nil
		return if progress then progress.mastery else 0
	end
end

--[[
	Самая высокая открытая ступень счёта. Именно её и играет ребёнок: выбирать
	ступень руками он не может (и не должен — читать он ещё не умеет), а нижние
	ступени возвращаются к нему повторениями внутри своей же ступени.
]]
function ProgressService.mathStage(player: Player): number
	local profile = ProfileService.get(player)
	if not profile then
		return 1
	end

	return MathConfig.current(mathMasteryOf(profile))
end

--[[
	Применяет один ответ на воротах с числами.

	Зеркало ProgressService.applyAnswer, и отличия перечислимы: осваивается ступень,
	а не буква; типов испытаний пока один; ступени математики открываются сами
	из статусов и отдельного поля в профиле не имеют.

	Награда — та же, что за букву. Счёт ребёнку даётся не легче алфавита,
	и платить за него меньше не за что.
]]
function ProgressService.applyMathAnswer(player: Player, answer): AnswerOutcome?
	local profile = ProfileService.get(player)
	if not profile then
		return nil
	end

	local stage = MathConfig.byId(answer.letterId)
	if not stage then
		warn(
			`[ProgressService] ответ по неизвестной ступени счёта: {answer.letterId}`
		)
		return nil
	end

	local now = os.time()
	local outcome: AnswerOutcome = {
		mastery = 0,
		transition = nil,
		openedStages = {},
		starsAwarded = 0,
		difficulty = DifficultyCurve.DEFAULT_LEVEL,
	}

	ProfileService.update(player, function(p)
		local before = mathProgressFor(p, stage.id, now)
		local updated, transition = MasteryRules.applyAnswer(before, answer, now, MATH_MIN_TYPES)
		updated = ReviewScheduler.schedule(updated, answer.correct, now)
		p.math[stage.id] = updated

		outcome.mastery = updated.mastery
		outcome.transition = transition

		local level = p.difficulty[answer.challengeId] or DifficultyCurve.DEFAULT_LEVEL
		local adjusted = DifficultyCurve.apply(level, streaksFor(player, answer.challengeId), answer.correct)
		streaksByPlayer[player][answer.challengeId] = adjusted.streaks
		p.difficulty[answer.challengeId] = adjusted.level
		outcome.difficulty = adjusted.level
	end)

	if answer.correct then
		outcome.starsAwarded += EconomyService.award(
			player,
			"correct_answer",
			Economy.REWARDS.correctAnswer,
			stage.id
		)
	end

	local transition = outcome.transition
	if transition then
		local reward = Economy.rewardForMasteryTransition(transition.from, transition.to)
		if reward > 0 then
			local source = if transition.to >= MasteryRules.MASTERED then "math_mastered" else "math_learned"
			outcome.starsAwarded += EconomyService.award(player, source, reward, stage.id)
		end
	end

	return outcome
end

--[[
	Буква своего отрезка, подобранная на дорожке забега. Звёздочка — да,
	ответ — нет: статусы букв двигают только решения в воротах.
]]
function ProgressService.awardCollect(player: Player, letterId: string): number
	return EconomyService.award(player, "letter_collected", Economy.REWARDS.letterCollected, letterId)
end

-- Итог испытания: 1..3 звезды, но не меньше гарантированного минимума.
function ProgressService.finishChallenge(player: Player, challengeId: string, stars: number): number
	local reward = Economy.rewardForChallenge(stars)
	return EconomyService.award(player, "challenge_result", reward, challengeId)
end

-- ===== Сохранки забегов ==========================================================

--[[
	Забег не заканчивается выходом из игры.

	Сохранка живёт в профиле, а не в памяти забега: ребёнок закрыл планшет
	посреди уровня — назавтра он продолжает с той же арки, а не с начала.
	Это прямое требование docs/14-TUNNEL-MODE.md § 3.3, и оно важнее экономии
	места в DataStore: начинать сначала то, что уже пройдено, — главный способ
	отбить у ребёнка желание проходить.

	Храним не геометрию, а рецепт: сид, буквы и сложность. Из них план забега
	собирается заново тем же кодом и получается тем же самым.
]]
local function isSavedRun(value: any, challengeId: string): boolean
	if typeof(value) ~= "table" then
		return false
	end
	if value.challengeId ~= challengeId then
		return false
	end
	if typeof(value.seed) ~= "number" or typeof(value.difficulty) ~= "number" then
		return false
	end
	if typeof(value.checkpoint) ~= "number" or value.checkpoint < 1 then
		return false
	end
	--[[
		Букв может не быть вовсе: в математическом забеге их нет по существу,
		и там рецепт держится на ступени счёта.
	]]
	if typeof(value.letters) ~= "table" then
		return false
	end
	for _, letterId in value.letters do
		if not Letters.get(letterId) then
			return false
		end
	end
	if #value.letters == 0 then
		return MathConfig.get(value.stage) ~= nil
	end
	if #value.letters < 2 then
		return false
	end
	-- Уровня может не быть (свободный забег), но если он есть, он обязан существовать.
	if value.level ~= nil and not Levels.get(value.level) then
		return false
	end
	return true
end

--[[
	Незаконченный забег этого испытания, если он есть.

	Мусор и записи от старых версий контента молча отбрасываются: ребёнок
	в худшем случае начнёт забег сначала, и это лучше, чем ошибка на входе.
]]
function ProgressService.savedRun(player: Player, challengeId: string)
	local profile = ProfileService.get(player)
	if not profile or typeof(profile.runs) ~= "table" then
		return nil
	end

	local saved = profile.runs[challengeId]
	if not isSavedRun(saved, challengeId) then
		return nil
	end
	return saved
end

--[[
	Записывает пройденную сохранку. Назад точка не двигается: пробежать арку
	второй раз, вернувшись к ней после падения, — не повод потерять путь.
]]
function ProgressService.saveRunCheckpoint(player: Player, spec, checkpointIndex: number)
	if typeof(checkpointIndex) ~= "number" or checkpointIndex < 1 then
		return
	end

	ProfileService.update(player, function(profile)
		profile.runs = if typeof(profile.runs) == "table" then profile.runs else {}

		local existing = profile.runs[spec.challengeId]
		if
			typeof(existing) == "table"
			and existing.seed == spec.seed
			and typeof(existing.checkpoint) == "number"
			and existing.checkpoint >= checkpointIndex
		then
			return
		end

		profile.runs[spec.challengeId] = {
			challengeId = spec.challengeId,
			seed = spec.seed,
			letters = table.clone(spec.letters),
			difficulty = spec.difficulty,
			-- Ступень счёта — часть рецепта наравне с сидом: без неё вернувшийся
			-- ребёнок получил бы тот же туннель с другими задачами.
			stage = spec.stage,
			-- Уровень мира букв — по той же причине: он решает, какие буквы на отрезках.
			level = spec.level,
			checkpoint = checkpointIndex,
			savedAt = os.time(),
		}
	end)
end

-- Забег пройден до финиша: продолжать нечего, следующий раз строится новый.
function ProgressService.clearRun(player: Player, challengeId: string)
	ProfileService.update(player, function(profile)
		if typeof(profile.runs) == "table" then
			profile.runs[challengeId] = nil
		end
	end)
end

-- ===== Уровни мира букв ==========================================================

--[[
	Уровень, который играет портал мира букв: следующий за пройденными.
	Ребёнок его не выбирает — портал просто продолжает путь (docs/14-TUNNEL-MODE.md § 3.2).
]]
function ProgressService.lettersLevel(player: Player): number
	local profile = ProfileService.get(player)
	local cleared = if profile then Levels.sanitize(profile.levels)[Levels.WORLD] else 0
	return Levels.current(cleared)
end

--[[
	Уровень пройден до финиша. Пройденный путь назад не двигается: повторное
	прохождение раннего уровня не отнимает поздних.
]]
function ProgressService.clearLevel(player: Player, index: number)
	if not Levels.get(index) then
		return
	end
	ProfileService.update(player, function(profile)
		local levels = Levels.sanitize(profile.levels)
		levels[Levels.WORLD] = math.max(levels[Levels.WORLD], index)
		profile.levels = levels
	end)
end

function ProgressService.start()
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		streaksByPlayer[player] = nil
	end)
end

--[[
	Первая ли это встреча с буквой.

	«Впервые» — значит по ней вообще не было ни одного ответа, ни верного, ни нет.
	Именно в этот момент, и только в этот, звучит знакомство: «Это буква М.
	Она говорит: м-м-м». Второй раз здороваться с буквой странно.
]]
function ProgressService.isFirstMeeting(player: Player, letterId: string): boolean
	local profile = ProfileService.get(player)
	if not profile then
		return false
	end

	local progress = profile.letters[letterId]
	if not progress then
		return true
	end
	return progress.correct == 0 and progress.wrong == 0
end

function ProgressService.difficultyFor(player: Player, challengeId: string): number
	local profile = ProfileService.get(player)
	if not profile then
		return DifficultyCurve.DEFAULT_LEVEL
	end
	return profile.difficulty[challengeId] or DifficultyCurve.DEFAULT_LEVEL
end

return ProgressService
