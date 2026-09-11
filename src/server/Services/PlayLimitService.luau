--!nonstrict
--[[
	Лимит времени в день и напоминание об отдыхе. См. docs/13-PARENT-MODE.md § 3,
	правила — Logic/PlayLimit.

	Завершение мягкое. Время вышло посреди забега — забег доигрывается до финиша
	(не дольше, чем длится испытание), и только потом голос прощается до завтра.
	Новые занятия после этого не начинаются, но из игры ребёнка никто не выкидывает:
	магазин, дом и Башня остаются, а родитель может поднять лимит в своём разделе,
	и экран «до завтра» уйдёт сам.

	Напоминание об отдыхе тоже ждёт конца забега: голос посреди туннеля
	перебил бы задание, а задание важнее.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayLimit = require(Shared.Logic.PlayLimit)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ChallengeService = require(script.Parent.ChallengeService)

local PlayLimitService = {}

-- Как часто сверяем время. Лимит в минутах, так что точность в четверть минуты с запасом.
local TICK_SECONDS = 15

type Watch = {
	startedAt: number, -- os.clock() начала захода
	lastRestAt: number, -- секунда захода, когда звучало прошлое напоминание
	over: boolean, -- экран «до завтра» уже показан
}

local watches: { [Player]: Watch } = {}

local function send(player: Player, state: string)
	RemoteDefs.event("PlayTime"):FireClient(player, { state = state })
end

local function limitOf(player: Player): number?
	local profile = ProfileService.get(player)
	if not profile then
		return nil
	end
	return PlayLimit.sanitizeParent(profile.parent).dailyLimitMin
end

function PlayLimitService.isOver(player: Player): boolean
	return PlayLimit.isOver(limitOf(player), ProfileService.playedToday(player))
end

local function check(player: Player)
	local watch = watches[player]
	local profile = ProfileService.get(player)
	if not watch or not profile then
		return
	end

	local over = PlayLimitService.isOver(player)

	-- Родитель поднял или снял лимит — экран «до завтра» уходит сам.
	if watch.over and not over then
		watch.over = false
		send(player, "ok")
		return
	end

	-- Идущий забег не трогаем ни лимитом, ни напоминанием: дождёмся финиша.
	if ChallengeService.isBusy(player) then
		return
	end

	if over and not watch.over then
		watch.over = true
		send(player, "over")
		RemoteDefs.event("PlayVO"):FireClient(player, "ui_goodbye", true)
		print(`[PlayLimit] {player.Name}: время на сегодня вышло`)
		return
	end

	local sessionSec = os.clock() - watch.startedAt
	local rest = PlayLimit.sanitizeParent(profile.parent).restReminder
	if not over and PlayLimit.restDue(rest, sessionSec, watch.lastRestAt) then
		watch.lastRestAt = sessionSec
		send(player, "rest")
		RemoteDefs.event("PlayVO"):FireClient(player, "ui_rest_reminder", false)
	end
end

-- Настройки родителя поменялись: проверяем сразу, а не через четверть минуты.
function PlayLimitService.recheck(player: Player)
	task.spawn(check, player)
end

function PlayLimitService.start()
	--[[
		Время вышло — новое занятие не начинается. Ребёнку экран «до завтра»
		показывается ещё раз: он мог его закрыть и снова пойти к паду.
	]]
	ChallengeService.addStartGuard(function(player: Player)
		if PlayLimitService.isOver(player) then
			send(player, "over")
			return false
		end
		return true
	end)

	-- Забег кончился после того, как время вышло: теперь можно прощаться.
	ChallengeService.onFinished(function(player: Player)
		task.delay(3, check, player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		watches[player] = { startedAt = os.clock(), lastRestAt = 0, over = false }
		task.spawn(function()
			if ProfileService.waitFor(player, 20) then
				check(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		watches[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for player in watches do
				task.spawn(check, player)
			end
		end
	end)
end

return PlayLimitService
