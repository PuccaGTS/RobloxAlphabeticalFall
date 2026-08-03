--!nonstrict
--[[
	Прогресс обучения: применяет ответы к профилю, двигает статусы букв,
	планирует повторения, открывает острова и заказывает награды у EconomyService.

	Это единственное место, где ответ ребёнка превращается в изменение прогресса.
	Испытания сюда только сообщают факты — решение принимается здесь.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Islands = require(Shared.Config.Islands)
local Syllables = require(Shared.Config.Syllables)
local Words = require(Shared.Config.Words)
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
	Пересчитывает открытые острова. Вызывается после каждого изменения статуса буквы.
	Возвращает список индексов островов, открывшихся именно сейчас.
]]
function ProgressService.refreshIslands(profile): { number }
	local opened: { number } = {}

	local function masteryOf(letterId: string): number
		local p = profile.letters[letterId]
		return if p then p.mastery else 0
	end

	for _, island in Islands.all do
		local state = profile.islands[island.index]
		if not state then
			state = { unlocked = false, bossDone = false, chests = {} }
			profile.islands[island.index] = state
		end

		if not state.unlocked and Islands.isUnlocked(island.index, masteryOf) then
			state.unlocked = true
			table.insert(opened, island.index)
		end
	end

	return opened
end

function ProgressService.unlockedIslandIndex(profile): number
	local highest = 1
	for index, state in profile.islands do
		if state.unlocked and index > highest then
			highest = index
		end
	end
	return highest
end

-- Буквы открытых островов в методическом порядке — вход для планировщика повторений.
function ProgressService.availableLetters(profile): { string }
	local maxIsland = ProgressService.unlockedIslandIndex(profile)
	local ids: { string } = {}
	for _, id in Letters.ordered() do
		if Letters.expect(id).island <= maxIsland then
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
	openedIslands: { number },
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
		openedIslands = {},
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
			outcome.openedIslands = ProgressService.refreshIslands(p)
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
	end

	return outcome
end

-- Первое прочтение слога: награда один раз за слог.
function ProgressService.markSyllableRead(player: Player, syllableId: string): boolean
	local profile = ProfileService.get(player)
	if not profile or not Syllables.get(syllableId) then
		return false
	end
	if profile.syllables[syllableId] then
		return false
	end

	ProfileService.update(player, function(p)
		p.syllables[syllableId] = true
	end)
	EconomyService.award(player, "syllable_first_read", Economy.REWARDS.syllableFirstRead, syllableId)
	return true
end

-- Первое собранное слово: награда один раз за слово.
function ProgressService.markWordBuilt(player: Player, wordId: string): boolean
	local profile = ProfileService.get(player)
	if not profile or not Words.get(wordId) then
		return false
	end
	if profile.words[wordId] then
		return false
	end

	ProfileService.update(player, function(p)
		p.words[wordId] = true
	end)
	EconomyService.award(player, "word_first_built", Economy.REWARDS.wordFirstBuilt, wordId)
	return true
end

-- Итог испытания: 1..3 звезды, но не меньше гарантированного минимума.
function ProgressService.finishChallenge(player: Player, challengeId: string, stars: number): number
	local reward = Economy.rewardForChallenge(stars)
	return EconomyService.award(player, "challenge_result", reward, challengeId)
end

function ProgressService.start()
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		streaksByPlayer[player] = nil
	end)
end

function ProgressService.difficultyFor(player: Player, challengeId: string): number
	local profile = ProfileService.get(player)
	if not profile then
		return DifficultyCurve.DEFAULT_LEVEL
	end
	return profile.difficulty[challengeId] or DifficultyCurve.DEFAULT_LEVEL
end

return ProgressService
