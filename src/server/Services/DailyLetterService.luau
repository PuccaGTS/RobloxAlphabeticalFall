--!nonstrict
--[[
	Буква дня на сервере: выбирает букву на сутки, запускает задания по ней,
	засчитывает их и платит бонус и награду за серию. Правила — Logic/DailyLetter,
	камень на площади строит WorldService, букву на нём рисует клиент
	(DailyLetterController): у каждого ребёнка буква своя.

	Новых реплик не требует: задания говорят своими инструкциями, буква
	называется своим именем, бонус звенит звуком награды.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local DailyLetter = require(Shared.Logic.DailyLetter)
local PlayLog = require(Shared.Logic.PlayLog)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ProgressService = require(script.Parent.ProgressService)
local EconomyService = require(script.Parent.EconomyService)
local ChallengeService = require(script.Parent.ChallengeService)
local Mirror = require(script.Parent.Parent.Challenges.Mirror)

local DailyLetterService = {}

-- Как часто проверять, не наступили ли новые сутки у тех, кто играет через полночь.
local DAY_CHECK_INTERVAL = 60
-- Пауза перед сообщением о засчитанном задании: сначала карточка итогов испытания.
local NOTICE_DELAY = 2.5

local function today(): number
	return PlayLog.dayOf(os.time())
end

local function canMirror(letterId: string?): boolean
	return letterId ~= nil and #Mirror.wrongKinds(letterId) > 0
end

local function notify(player: Player, payload)
	RemoteDefs.event("DailyLetter"):FireClient(player, payload)
end

--[[
	Выбирает букву, если на сегодня её ещё нет. Очередь повторений спрашиваем
	только при смене суток: буква не должна меняться посреди дня от того,
	что ребёнок что-то выучил.
]]
function DailyLetterService.refresh(player: Player)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end
	local day = today()
	local state = DailyLetter.sanitize(profile.daily)
	if state.day == day and state.letterId and Letters.get(state.letterId) then
		return
	end

	local queue = ProgressService.buildQueue(player)
	local letterId =
		DailyLetter.pick(if queue then queue.flat else {}, ProgressService.availableLetters(profile), day)

	ProfileService.update(player, function(p)
		local fresh = DailyLetter.sanitize(p.daily)
		-- Буква из старой версии контента — выбираем заново, как на новый день.
		if fresh.letterId and not Letters.get(fresh.letterId) then
			fresh.letterId = nil
		end
		DailyLetter.refresh(fresh, day, letterId)
		p.daily = fresh
	end)
end

-- Ребёнок коснулся камня: следующее задание по букве дня или «на сегодня всё».
function DailyLetterService.begin(player: Player)
	DailyLetterService.refresh(player)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end

	local state = DailyLetter.sanitize(profile.daily)
	local letter = state.letterId and Letters.get(state.letterId)
	if not letter then
		return
	end

	local day = today()
	local challengeId = DailyLetter.nextTask(state, day, canMirror(state.letterId))
	if not challengeId then
		-- Пройдена: буква называет себя — лишнее повторение не вредит — и ждёт завтра.
		RemoteDefs.event("PlayVO"):FireClient(player, letter.vo.name, true)
		notify(player, { state = "already", letterId = letter.id })
		return
	end

	ChallengeService.startFor(player, challengeId, { focus = letter.id, daily = true })
end

--[[
	Засчитывает задание. Как и обучение, засчитывает и тайм-аут: пять букв
	не поймал, три поймал — задание сделано, проиграть нельзя. Но только если
	ребёнок в нём хоть что-то сделал: зашёл и вышел — не задание.
]]
local function onFinished(player: Player, spec: any, reason: string, answers: number)
	if not (spec.params and spec.params.daily) then
		return
	end
	if reason ~= "completed" and reason ~= "timeout" then
		return
	end
	if answers <= 0 then
		return
	end

	local day = today()
	local letterId
	local outcome = ProfileService.update(player, function(profile)
		local state = DailyLetter.sanitize(profile.daily)
		letterId = state.letterId
		local result = DailyLetter.complete(state, day, spec.challengeId, canMirror(state.letterId))
		profile.daily = state
		return result
	end)
	if not outcome then
		return
	end

	if not outcome.finished then
		print(`[Daily] {player.Name}: буква дня {outcome.done} из {outcome.total}`)
		task.delay(
			NOTICE_DELAY,
			notify,
			player,
			{ state = "step", done = outcome.done, total = outcome.total }
		)
		return
	end

	local bonus = EconomyService.award(player, "letter_of_the_day", outcome.bonus, letterId)
	local streakReward = 0
	if outcome.streakReward > 0 then
		streakReward =
			EconomyService.award(player, "daily_streak", outcome.streakReward, tostring(outcome.streak))
	end
	print(`[Daily] {player.Name}: буква дня пройдена, серия {outcome.streak}`)

	task.delay(NOTICE_DELAY, notify, player, {
		state = "finished",
		letterId = letterId,
		bonus = bonus,
		streak = outcome.streak,
		streakReward = streakReward,
	})
end

function DailyLetterService.start()
	ChallengeService.onFinished(onFinished)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if ProfileService.waitFor(player, 20) then
				DailyLetterService.refresh(player)
			end
		end)
	end)

	-- Играющему через полночь камень показывает новую букву без перезахода.
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(DailyLetterService.refresh, player)
			end
		end
	end)
end

return DailyLetterService
