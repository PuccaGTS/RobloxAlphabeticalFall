--!nonstrict
-- nonstrict осознанно: метатабличные классы и ответы DataStore имеют тип any,
-- строгая типизация здесь даёт шум вместо пользы. Публичный контракт описан типом Backend.
--[[
	Низкоуровневая работа с DataStore: сессионная блокировка, ретраи, освобождение ключа.

	Зачем блокировка: без неё второй вход того же аккаунта (телепорт, два устройства,
	перезаход в момент сохранения) затирает профиль. Для детской игры это потеря
	всех выученных букв и купленных шапок — самый болезненный баг, который тут возможен.

	Формат записи в DataStore:
		{
			data = <профиль>,
			lock = { jobId = "...", placeId = 123, at = <unix> } | nil,
			savedAt = <unix>,
		}

	ЗАМЕТКА НА БУДУЩЕЕ: перед релизом это стоит заменить на проверенную библиотеку
	(ProfileStore), уже объявленную в wally.toml. Своя реализация покрывает нужды
	разработки, но у библиотеки больше боевого пробега на краевых случаях.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataBackend = {}
DataBackend.__index = DataBackend

-- Блокировка считается протухшей, если её никто не обновлял дольше этого времени.
-- Должно быть заметно больше интервала автосохранения (60 с).
local LOCK_TTL = 300
local MAX_ATTEMPTS = 5
local RETRY_DELAY = 2
-- Сколько ждать освобождения чужой живой блокировки, прежде чем сдаться.
local LOCK_WAIT_ATTEMPTS = 4
local LOCK_WAIT_DELAY = 5

export type Envelope = {
	data: any,
	lock: { jobId: string, placeId: number, at: number }?,
	savedAt: number,
}

export type Backend = {
	loadAsync: (self: Backend, key: string) -> (any, string?),
	saveAsync: (self: Backend, key: string, data: any, release: boolean) -> (boolean, string?),
	releaseAsync: (self: Backend, key: string) -> boolean,
}

local function ourLockId(): string
	-- В Studio JobId пустой, поэтому подставляем стабильную метку сессии.
	return if game.JobId ~= "" then game.JobId else "studio"
end

local function isForeignLiveLock(envelope: Envelope?, now: number): boolean
	if not envelope or not envelope.lock then
		return false
	end
	local lock = envelope.lock
	if lock.jobId == ourLockId() then
		return false
	end
	return (now - lock.at) < LOCK_TTL
end

-- ===== DataStore =================================================================

local Store = {}
Store.__index = Store

function DataBackend.newDataStore(name: string, scope: string?): Backend
	local self = setmetatable({}, Store)
	self._store = DataStoreService:GetDataStore(name, scope)
	return (self :: any) :: Backend
end

function Store:loadAsync(key: string): (any, string?)
	local lastError: string? = nil
	local blockedCount = 0

	for attempt = 1, MAX_ATTEMPTS do
		local blocked = false

		local ok, result = pcall(function()
			return self._store:UpdateAsync(key, function(old: Envelope?)
				local now = os.time()

				if isForeignLiveLock(old, now) then
					blocked = true
					return nil -- отменяем запись, ключ занят другим сервером
				end

				local envelope: Envelope = old or { data = nil, lock = nil, savedAt = now }
				envelope.lock = { jobId = ourLockId(), placeId = game.PlaceId, at = now }
				return envelope
			end)
		end)

		if ok and not blocked then
			local envelope = result :: Envelope?
			if envelope then
				return envelope.data, nil
			end
			return nil, nil
		end

		if blocked then
			blockedCount += 1
			lastError = "ключ занят другой сессией"
			if blockedCount > LOCK_WAIT_ATTEMPTS then
				return nil, "профиль занят другой сессией"
			end
			task.wait(LOCK_WAIT_DELAY)
		else
			lastError = tostring(result)
			warn(
				`[DataBackend] загрузка "{key}" не удалась (попытка {attempt}): {lastError}`
			)
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return nil, lastError
end

function Store:saveAsync(key: string, data: any, release: boolean): (boolean, string?)
	local lastError: string? = nil

	for attempt = 1, MAX_ATTEMPTS do
		local stolen = false

		local ok, err = pcall(function()
			self._store:UpdateAsync(key, function(old: Envelope?)
				local now = os.time()

				if isForeignLiveLock(old, now) then
					-- Чужая живая блокировка: писать нельзя, иначе затрём чужую сессию.
					stolen = true
					return nil
				end

				return {
					data = data,
					lock = if release then nil else { jobId = ourLockId(), placeId = game.PlaceId, at = now },
					savedAt = now,
				}
			end)
		end)

		if ok and not stolen then
			return true, nil
		end

		if stolen then
			return false, "ключ перехвачен другой сессией"
		end

		lastError = tostring(err)
		warn(
			`[DataBackend] сохранение "{key}" не удалось (попытка {attempt}): {lastError}`
		)
		task.wait(RETRY_DELAY * attempt)
	end

	return false, lastError
end

function Store:releaseAsync(key: string): boolean
	local ok = pcall(function()
		self._store:UpdateAsync(key, function(old: Envelope?)
			if not old then
				return nil
			end
			if old.lock and old.lock.jobId ~= ourLockId() then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
	return ok
end

-- ===== Память (Studio без доступа к DataStore) ===================================

local Memory = {}
Memory.__index = Memory

function DataBackend.newMemory(): Backend
	local self = setmetatable({}, Memory)
	self._data = {}
	return (self :: any) :: Backend
end

function Memory:loadAsync(key: string): (any, string?)
	return self._data[key], nil
end

function Memory:saveAsync(key: string, data: any, _release: boolean): (boolean, string?)
	self._data[key] = data
	return true, nil
end

function Memory:releaseAsync(_key: string): boolean
	return true
end

-- ===== Выбор бэкенда =============================================================

--[[
	В Studio без доступа к API DataStore игра должна запускаться и работать,
	иначе разработку не вести. Но подмена на память допустима ТОЛЬКО в Studio:
	на боевом сервере отсутствие DataStore — это авария, а не повод молча терять прогресс.
]]
function DataBackend.auto(name: string, scope: string?): (Backend, boolean)
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(name, scope)
	end)

	if ok and store then
		local probeOk = pcall(function()
			store:GetAsync("__probe__")
		end)
		if probeOk then
			return DataBackend.newDataStore(name, scope), true
		end
	end

	if RunService:IsStudio() then
		warn(
			"[DataBackend] DataStore недоступен — работаем в памяти (только Studio)"
		)
		return DataBackend.newMemory(), false
	end

	error("[DataBackend] DataStore недоступен на боевом сервере")
end

return DataBackend
