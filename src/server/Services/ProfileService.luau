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

local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or not backend then
		return false
	end

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

function ProfileService.pushSnapshot(player: Player)
	pushSnapshot(player)
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
