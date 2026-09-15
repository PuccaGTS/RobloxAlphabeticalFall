--!nonstrict
--[[
	Жизненный цикл профиля игрока: загрузка при входе, автосохранение, выгрузка при выходе.

	Гарантии, которые обязаны соблюдаться (docs/07-TECH-ARCH.md § 4):
	  · профиль загружается ровно один раз на сессию и держит блокировку ключа;
	  · автосохранение каждые 60 с и обязательное сохранение при выходе и BindToClose;
	  · клиенту уходит только срез (ProfileTemplate.toSnapshot), никогда не весь профиль;
	  · если профиль не загрузился — игрок НЕ играет вслепую: мы говорим об этом
	    и не даём копить прогресс, который потом потеряется.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProfileTemplate = require(Shared.Config.ProfileTemplate)
local Migrations = require(Shared.Logic.Migrations)
local PlayLog = require(Shared.Logic.PlayLog)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local DataBackend = require(script.Parent.DataBackend)

local STORE_NAME = "PlayerProfiles"
local STORE_SCOPE = if RunService:IsStudio() then "dev" else "live"
local AUTOSAVE_INTERVAL = 60

local ProfileService = {}

local backend: DataBackend.Backend? = nil
local profiles: { [Player]: any } = {}
local loading: { [Player]: boolean } = {}
local failed: { [Player]: string } = {}
-- Момент, до которого время игрока уже записано в историю занятий.
local playClock: { [Player]: number } = {}
local started = false

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function pushSnapshot(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	RemoteDefs.event("ProfileSnapshot"):FireClient(player, ProfileTemplate.toSnapshot(profile))
end

--[[
	Переносит время с прошлого учёта в историю занятий. Зовётся перед каждым
	сохранением, так что в DataStore время уходит с точностью до минуты,
	а при выходе — до секунды.
]]
local function accountPlay(player: Player)
	local profile = profiles[player]
	local since = playClock[player]
	if not profile or not since then
		return
	end
	local now = os.time()
	PlayLog.addPlay(profile, now, now - since)
	playClock[player] = now
end

local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or not backend then
		return false
	end

	accountPlay(player)

	local ok, err = backend:saveAsync(keyFor(player), profile, release)
	if not ok then
		warn(`[ProfileService] не удалось сохранить {player.Name}: {err}`)
	end
	return ok
end

local function loadProfile(player: Player)
	if not backend then
		return
	end

	loading[player] = true

	local raw, err = backend:loadAsync(keyFor(player))

	-- Игрок мог выйти, пока мы ходили в DataStore.
	if not player:IsDescendantOf(Players) then
		loading[player] = nil
		if raw ~= nil then
			backend:releaseAsync(keyFor(player))
		end
		return
	end

	loading[player] = nil

	if err and raw == nil then
		failed[player] = err
		warn(`[ProfileService] профиль {player.Name} не загружен: {err}`)
		player:Kick(
			"Не получилось загрузить твой прогресс. Зайди, пожалуйста, чуть позже — "
				.. "все твои буквы и вещи на месте."
		)
		return
	end

	local now = os.time()
	local profile = if raw ~= nil then Migrations.normalize(raw, now) else ProfileTemplate.new(now)

	profile.stats.sessionsCount += 1
	profiles[player] = profile
	playClock[player] = now

	-- Первое сохранение сразу: фиксируем блокировку и версию за собой.
	saveProfile(player, false)
	pushSnapshot(player)

	print(
		`[ProfileService] профиль загружен: {player.Name} (звёздочек: {profile.stars})`
	)
end

local function releaseProfile(player: Player)
	if profiles[player] then
		saveProfile(player, true)
		profiles[player] = nil
		playClock[player] = nil
	elseif backend and not loading[player] then
		backend:releaseAsync(keyFor(player))
	end
	failed[player] = nil
end

-- ===== Публичный интерфейс =======================================================

function ProfileService.get(player: Player): any?
	return profiles[player]
end

--[[
	Ждёт загрузки профиля. Все сервисы, которым нужен профиль сразу после входа,
	обязаны идти через это, а не читать get() в надежде, что уже загрузилось.
]]
function ProfileService.waitFor(player: Player, timeout: number?): any?
	local deadline = os.clock() + (timeout or 20)
	while os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile
		end
		if failed[player] or not player:IsDescendantOf(Players) then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

--[[
	Единственный разрешённый способ менять профиль: изменения идут внутри функции,
	снапшот клиенту уходит автоматически. Возвращает результат функции.
]]
function ProfileService.update<T>(player: Player, mutate: (profile: any) -> T): T?
	local profile = profiles[player]
	if not profile then
		return nil
	end

	local result = mutate(profile)
	pushSnapshot(player)
	return result
end

--[[
	Сколько секунд ребёнок играл сегодня: записанное в историю плюс то, что
	набежало с прошлого учёта и ещё не записано. Без хвоста лимит времени
	срабатывал бы с опозданием до минуты.
]]
function ProfileService.playedToday(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local now = os.time()
	local recorded = PlayLog.secondsOn(profile.playLog, PlayLog.dayOf(now))
	local since = playClock[player]
	local pending = if since and PlayLog.dayOf(since) == PlayLog.dayOf(now) then now - since else 0
	return recorded + math.max(0, pending)
end

function ProfileService.pushSnapshot(player: Player)
	pushSnapshot(player)
end

--[[
	Запрос на удаление данных (Roblox Right to Erasure, docs/11-COMPLIANCE.md § 4).
	Запускается руками из консоли сервера или Command Bar Studio по номеру аккаунта
	из запроса — порядок в docs/11-COMPLIANCE.md § 4.1:

	  require(game.ServerScriptService.Server.Services.ProfileService).erase(123456)

	Профиль лежит в двух областях — «dev» (Studio) и «live» (боевые серверы), —
	и удаляется из обеих: удаление должно быть полным, где бы ни играли.
	Кроме профиля, игра об аккаунте ничего не хранит.

	Если игрок сейчас на этом сервере, профиль сначала выбрасывается из памяти
	без сохранения, а игрок выходит из игры: иначе при выходе профиль записался бы
	обратно. На другом сервере его так не достать — тогда удаление этой области
	откладывается с пометкой «повторите через 5 минут», пока force не передан.

	Возвращает true, если удалено отовсюду, и строки отчёта по областям.
]]
function ProfileService.erase(userId: number, force: boolean?): (boolean, { string })
	assert(typeof(userId) == "number" and userId > 0, "erase: нужен номер аккаунта Roblox")
	local key = `player_{userId}`
	local report: { string } = {}
	local allDone = true

	local online = Players:GetPlayerByUserId(userId)
	if online then
		profiles[online] = nil
		playClock[online] = nil
		online:Kick(
			"Данные этого аккаунта удалены по запросу. Спасибо, что играли!"
		)
		table.insert(
			report,
			"игрок был на этом сервере: профиль выброшен без сохранения"
		)
	end

	for _, scope in { "dev", "live" } do
		-- Своя область — через уже выбранный бэкенд: в Studio без API это память,
		-- и удаление видно сразу. Чужая — напрямую в DataStore, если он доступен.
		local backendForScope: DataBackend.Backend? = nil
		if scope == STORE_SCOPE and backend then
			backendForScope = backend
		else
			local ok, store = pcall(DataBackend.newDataStore, STORE_NAME, scope)
			backendForScope = if ok then store else nil
		end

		if not backendForScope then
			allDone = false
			table.insert(report, `{scope}: DataStore недоступен`)
		else
			local removed, err, busy = backendForScope:removeAsync(key, force == true)
			if removed then
				table.insert(report, `{scope}: удалено`)
			else
				allDone = false
				table.insert(
					report,
					if busy
						then `{scope}: {err} — повторите через 5 минут или с force = true`
						else `{scope}: ошибка {err}`
				)
			end
		end
	end

	print(`[ProfileService] erasure {userId}: {table.concat(report, "; ")}`)
	return allDone, report
end

function ProfileService.start()
	if started then
		return
	end
	started = true

	local selected, isReal = DataBackend.auto(STORE_NAME, STORE_SCOPE)
	backend = selected
	if not isReal then
		warn(
			"[ProfileService] прогресс НЕ сохраняется между сессиями (режим памяти)"
		)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(loadProfile, player)
	end)
	Players.PlayerRemoving:Connect(releaseProfile)

	-- Автосохранение: раз в минуту и с разбежкой, чтобы не бить в DataStore залпом.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(saveProfile, player, false)
				task.wait(0.2)
			end
		end
	end)

	game:BindToClose(function()
		for player in profiles do
			task.spawn(releaseProfile, player)
		end
		-- Даём сохранениям долететь: Roblox отводит на BindToClose до 30 секунд.
		task.wait(3)
	end)
end

return ProfileService
