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
local PlayLimit = require(Shared.Logic.PlayLimit)
local Tutorial = require(Shared.Logic.Tutorial)
local ParentReport = require(Shared.Logic.ParentReport)
local SoundSettings = require(Shared.Logic.SoundSettings)
local ProfileRestart = require(Shared.Logic.ProfileRestart)
local PlayLog = require(Shared.Logic.PlayLog)
local Letters = require(Shared.Config.Letters)
local ProfileTemplate = require(Shared.Config.ProfileTemplate)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local TutorialService = require(script.Parent.TutorialService)
local PlayLimitService = require(script.Parent.PlayLimitService)
local ChallengeService = require(script.Parent.ChallengeService)
local BaseService = require(script.Parent.BaseService)
local PetService = require(script.Parent.PetService)
local DailyLetterService = require(script.Parent.DailyLetterService)

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
	  reset  — «забыл PIN»: сбрасывается только PIN. Лимит времени и напоминание
	           остаются: сброс защищён одним взрослым вопросом, и сними он лимит,
	           ребёнок, осиливший 7 × 8, играл бы сколько хочет. Прогресс ребёнка
	           не трогается вовсе (docs/13 § 1);
	  leave  — закрыть родительский экран;
	  skip_tutorial — пропустить обучение первых минут (docs/13 § 3: для второго
	           ребёнка в семье). Только после входа по PIN;
	  set_limit — лимит времени в день: 0 (выключен), 15, 20, 30 или 45 минут;
	  set_rest  — напоминание об отдыхе раз в 20 минут: вкл/выкл;
	  set_volume — громкость музыки, эффектов или голоса ступенью из SoundSettings;
	  set_subtitles — показывать субтитры и при записанной озвучке;
	  set_hide_robux — скрыть из витрины покупки за Robux;
	  reset_letter — забыть прогресс одной буквы: ребёнок «зазубрил» её без понимания.
	           Звёздочки, питомец и открытые ступени остаются: заработанное не отнимаем.
	  restart — «начать заново»: обучение с нуля (Logic/ProfileRestart). Второе
	           подтверждение — PIN ещё раз: сессия живёт 15 минут, и ребёнок, дорвавшийся
	           до открытого экрана, стёр бы всё двумя нажатиями. Ошибка PIN здесь
	           считается попыткой, как при входе.
	Настройки меняются только после входа по PIN.
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

	if action == "set_limit" then
		if not isSignedIn(player) then
			return refuse("not_signed_in")
		end
		local minutes = request.minutes
		local limit = PlayLimit.sanitizeLimit(minutes)
		if minutes ~= 0 and limit == nil then
			return refuse("bad_limit")
		end
		ProfileService.update(player, function(p)
			p.parent = PlayLimit.sanitizeParent(p.parent)
			p.parent.dailyLimitMin = limit
		end)
		logChange(player, `daily_limit {limit or "off"}`)
		PlayLimitService.recheck(player)
		return { ok = true }
	end

	if action == "set_rest" then
		if not isSignedIn(player) then
			return refuse("not_signed_in")
		end
		if typeof(request.on) ~= "boolean" then
			return refuse("bad_request")
		end
		ProfileService.update(player, function(p)
			p.parent = PlayLimit.sanitizeParent(p.parent)
			p.parent.restReminder = request.on
		end)
		logChange(player, `rest_reminder {if request.on then "on" else "off"}`)
		return { ok = true }
	end

	if action == "set_volume" then
		if not isSignedIn(player) then
			return refuse("not_signed_in")
		end
		if typeof(request.key) ~= "string" then
			return refuse("bad_request")
		end
		local applied = ProfileService.update(player, function(p)
			SoundSettings.sanitize(p.settings, ProfileTemplate.defaultSettings())
			return SoundSettings.setVolume(p.settings, request.key, request.value)
		end)
		if not applied then
			return refuse("bad_volume")
		end
		logChange(player, `volume {request.key} {request.value}`)
		return { ok = true }
	end

	if action == "set_subtitles" then
		if not isSignedIn(player) then
			return refuse("not_signed_in")
		end
		if typeof(request.on) ~= "boolean" then
			return refuse("bad_request")
		end
		ProfileService.update(player, function(p)
			p.settings.subtitles = request.on
		end)
		logChange(player, `subtitles {if request.on then "on" else "off"}`)
		return { ok = true }
	end

	--[[
		Покупки за Robux в витрине (docs/13-PARENT-MODE.md § 3). Прячем показ,
		а не владение: купленное раньше остаётся у ребёнка.
	]]
	if action == "set_hide_robux" then
		if not isSignedIn(player) then
			return refuse("not_signed_in")
		end
		if typeof(request.on) ~= "boolean" then
			return refuse("bad_request")
		end
		ProfileService.update(player, function(p)
			p.settings.hideRobux = request.on
		end)
		logChange(player, `hide_robux {if request.on then "on" else "off"}`)
		return { ok = true }
	end

	if action == "reset_letter" then
		if not isSignedIn(player) then
			return refuse("not_signed_in")
		end
		if typeof(request.letterId) ~= "string" or not Letters.get(request.letterId) then
			return refuse("bad_request")
		end
		ProfileService.update(player, function(p)
			p.letters[request.letterId] = nil
		end)
		logChange(player, `letter_reset {request.letterId}`)
		return { ok = true }
	end

	if action == "restart" then
		if not isSignedIn(player) or stored == nil then
			return refuse("not_signed_in")
		end
		local locked = ParentGate.lockedFor(guard, now)
		if locked > 0 then
			return refuse("locked", { lockedFor = locked })
		end
		if not ParentGate.matches(request.pin, saltOf(player), stored) then
			local left = ParentGate.registerFailure(guard, now)
			return refuse("wrong_pin", { attemptsLeft = left, lockedFor = ParentGate.lockedFor(guard, now) })
		end
		ParentGate.registerSuccess(guard)

		-- Идущий забег закрываем до сброса: иначе его финиш записал бы уровень
		-- и ответы в уже чистый профиль. Ребёнок оказывается у своего дома.
		local wasBusy = ChallengeService.isBusy(player)
		ChallengeService.abort(player)
		ProfileService.update(player, function(p)
			ProfileRestart.apply(p, PlayLog.dayOf(os.time()))
		end)
		PetService.refresh(player)
		BaseService.refresh(player)
		DailyLetterService.refresh(player)
		if wasBusy then
			BaseService.sendHome(player)
		end
		logChange(player, "profile_restart")
		return { ok = true }
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
			p.parent = PlayLimit.sanitizeParent(p.parent)
			p.parent.pinHash = nil
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
local function touchedLetters(profile): { string }
	local ids: { string } = {}
	for _, id in Letters.ordered() do
		if profile.letters[id] then
			table.insert(ids, id)
		end
	end
	return ids
end

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
	-- Копия, приведённая к ступеням: старые 0.6/0.7 подсвечиваются ближайшей кнопкой.
	local sound = table.clone(profile.settings)
	SoundSettings.sanitize(sound, ProfileTemplate.defaultSettings())
	return {
		report = ParentReport.build(profile, os.time()),
		tutorialDone = Tutorial.isDone(Tutorial.sanitize(profile.tutorial)),
		settings = {
			limitMin = PlayLimit.sanitizeParent(profile.parent).dailyLimitMin,
			restReminder = PlayLimit.sanitizeParent(profile.parent).restReminder,
			playedTodayMin = math.floor(ProfileService.playedToday(player) / 60),
			music = sound.music,
			sfx = sound.sfx,
			voice = sound.voice,
			subtitles = sound.subtitles,
			hideRobux = sound.hideRobux == true,
			-- Буквы, по которым есть прогресс: только их и есть смысл сбрасывать.
			touched = touchedLetters(profile),
		},
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
