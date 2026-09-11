--!nonstrict
--[[
	Родительский режим на сервере: вход по PIN и выдача отчёта.
	См. docs/13-PARENT-MODE.md § 1, § 2 и § 8.

	Отчёт клиенту уходит только после входа: пока PIN не введён, статистика
	ребёнка не лежит в памяти клиента вовсе. Хеш PIN и счётчик попыток
	не покидают сервер никогда — клиент узнаёт только «подошёл / не подошёл /
	подождите столько-то секунд».

	Вход живёт на сервере, а не флагом на клиенте: флаг клиента подделывается
	одной строкой, а сессия на сервере — нет.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ParentGate = require(Shared.Logic.ParentGate)
local Tutorial = require(Shared.Logic.Tutorial)
local ParentReport = require(Shared.Logic.ParentReport)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local TutorialService = require(script.Parent.TutorialService)

local ParentService = {}

-- До какого момента (os.clock) вход действует.
local sessions: { [Player]: number } = {}
local guards: { [Player]: ParentGate.Guard } = {}

local function saltOf(player: Player): string
	return tostring(player.UserId)
end

local function guardOf(player: Player): ParentGate.Guard
	local guard = guards[player]
	if not guard then
		guard = ParentGate.newGuard()
		guards[player] = guard
	end
	return guard
end

local function pinHashOf(profile): string?
	local parent = profile.parent
	if typeof(parent) ~= "table" or typeof(parent.pinHash) ~= "string" then
		return nil
	end
	return parent.pinHash
end

local function isSignedIn(player: Player): boolean
	local until_ = sessions[player]
	return until_ ~= nil and os.clock() < until_
end

local function signIn(player: Player)
	sessions[player] = os.clock() + ParentGate.SESSION_SECONDS
end

--[[
	Каждое изменение настроек родителя пишется в лог одной строкой с событием
	parent_setting_change (docs/13-PARENT-MODE.md § 8). Самого PIN в строке нет.
]]
local function logChange(player: Player, what: string)
	print(`[Parent] parent_setting_change {player.UserId} {what}`)
end

local function refuse(reason: string, extra: { [string]: any }?)
	local answer = { ok = false, reason = reason }
	for key, value in extra or {} do
		answer[key] = value
	end
	return answer
end

--[[
	Все шаги входа — одна функция с полем action. Шаги перечислимы, у каждого
	свои проверки, и лишнего от клиента не принимается:

	  status — есть ли PIN и не идёт ли пауза;
	  set    — задать PIN, если его ещё нет;
	  enter  — войти по PIN;
	  reset  — «забыл PIN»: сброс настроек родительского режима, прогресс ребёнка
	           не трогается (docs/13 § 1). Перед ним клиент спрашивает взрослый
	           вопрос — это барьер от ребёнка, а не от взломщика;
	  leave  — закрыть родительский экран;
	  skip_tutorial — пропустить обучение первых минут (docs/13 § 3: для второго
	           ребёнка в семье). Только после входа по PIN.
]]
local function onAuth(player: Player, request: any)
	if not RateLimiter.allow(player, "ParentAuth", RemoteDefs.RATE_LIMITS.ParentAuth) then
		return refuse("busy")
	end
	if typeof(request) ~= "table" or typeof(request.action) ~= "string" then
		return refuse("bad_request")
	end

	local profile = ProfileService.get(player)
	if not profile then
		return refuse("no_profile")
	end

	local guard = guardOf(player)
	local now = os.clock()
	local stored = pinHashOf(profile)
	local action = request.action

	if action == "status" then
		return { ok = true, hasPin = stored ~= nil, lockedFor = ParentGate.lockedFor(guard, now) }
	end

	if action == "leave" then
		sessions[player] = nil
		return { ok = true }
	end

	if action == "set" then
		if stored ~= nil then
			return refuse("pin_exists")
		end
		if not ParentGate.isValidPin(request.pin) then
			return refuse("bad_pin")
		end
		local hash = ParentGate.hash(request.pin, saltOf(player))
		ProfileService.update(player, function(p)
			p.parent = if typeof(p.parent) == "table" then p.parent else {}
			p.parent.pinHash = hash
		end)
		logChange(player, "pin_set")
		signIn(player)
		return { ok = true }
	end

	if action == "enter" then
		if stored == nil then
			return refuse("no_pin")
		end
		local locked = ParentGate.lockedFor(guard, now)
		if locked > 0 then
			return refuse("locked", { lockedFor = locked })
		end
		if ParentGate.matches(request.pin, saltOf(player), stored) then
			ParentGate.registerSuccess(guard)
			signIn(player)
			return { ok = true }
		end
		-- Мусор вместо PIN тоже попытка: иначе перебор шёл бы в обход паузы.
		local left = ParentGate.registerFailure(guard, now)
		return refuse("wrong_pin", { attemptsLeft = left, lockedFor = ParentGate.lockedFor(guard, now) })
	end

	if action == "skip_tutorial" then
		if not isSignedIn(player) then
			return refuse("not_signed_in")
		end
		TutorialService.skip(player)
		logChange(player, "tutorial_skipped")
		return { ok = true }
	end

	if action == "reset" then
		ProfileService.update(player, function(p)
			p.parent = { pinHash = nil, dailyLimitMin = nil }
		end)
		ParentGate.registerSuccess(guard)
		sessions[player] = nil
		logChange(player, "parent_reset")
		return { ok = true }
	end

	return refuse("bad_request")
end

--[[
	Отчёт — только вошедшему. Каждый запрос продлевает вход: родитель, который
	листает вкладки, не должен вылетать на экран PIN посреди чтения.
]]
local function onReport(player: Player)
	if not RateLimiter.allow(player, "GetParentReport", RemoteDefs.RATE_LIMITS.GetParentReport) then
		return nil
	end
	if not isSignedIn(player) then
		return nil
	end

	local profile = ProfileService.get(player)
	if not profile then
		return nil
	end

	signIn(player)
	return {
		report = ParentReport.build(profile, os.time()),
		tutorialDone = Tutorial.isDone(Tutorial.sanitize(profile.tutorial)),
		-- Время сервера: по нему клиент считает «повтор через 3 дня»,
		-- часы планшета могут врать на сутки.
		now = os.time(),
	}
end

function ParentService.start()
	RemoteDefs.func("ParentAuth").OnServerInvoke = onAuth
	RemoteDefs.func("GetParentReport").OnServerInvoke = onReport

	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
		guards[player] = nil
	end)
end

return ParentService
