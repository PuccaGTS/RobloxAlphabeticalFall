--!strict
--[[
	Единый реестр Remote-объектов. Ни один RemoteEvent/Function не создаётся вне этого модуля.

	Правило: один Remote — одно намерение. Никаких универсальных DoAction(payload).
	Все хендлеры на сервере обязаны валидировать типы и диапазоны аргументов.
	См. docs/07-TECH-ARCH.md § 6–7.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Net"

local EVENTS: { string } = {
	"ProfileSnapshot", -- S→C  срез профиля
	"StartChallenge", -- C→S  запрос старта испытания
	"ChallengeSpec", -- S→C  задание
	"ChallengeAction", -- C→S  действие игрока
	"ChallengeFeedback", -- S→C  верно/неверно + какую реплику проиграть
	"ChallengeEnd", -- S→C  итог и награда
	"BuyItem", -- C→S
	"EquipItem", -- C→S
	"BuildUpgrade", -- C→S  улучшить постройку на своём участке
	"BaseAssigned", -- S→C  выдан участок: где он стоит (туда переезжает Башня)
	"PlayVO", -- S→C  проиграть реплику по vo_key
	--[[
		S→C  проиграть фразу, собранную из нескольких реплик подряд.

		Нужна математике: «Сколько будет» + «два» + «плюс» + «два» — это четыре
		записи, но для ребёнка одно задание, и кнопка «повторить» обязана повторять
		его целиком, а не последний кусок (docs/16-MATH.md § 5).
	]]
	"PlayPhrase",
	"PlaySfx", -- S→C  короткий звуковой эффект по ключу из Config/Sfx
	"OpenUI", -- S→C  объект мира просит открыть экран ("shop")
	--[[
		S→C  время игры: { state = "over" } — на сегодня всё, { state = "ok" } —
		снова можно (родитель поднял лимит), { state = "rest" } — пора передохнуть.
	]]
	"PlayTime",
	"EquipPet", -- C→S  взять с собой буквёнка: id освоенной буквы (касание на Башне)
	"PetGranted", -- S→C  буква освоена — прилетел новый буквёнок: id буквы
}

local FUNCTIONS: { string } = {
	"ParentAuth", -- C→S  вход в родительский режим по PIN
	"GetParentReport", -- C→S  отчёт о прогрессе
}

-- Лимиты частоты на сервере: событие -> максимум вызовов в секунду от одного игрока.
local RATE_LIMITS: { [string]: number } = {
	StartChallenge = 2,
	ChallengeAction = 20,
	BuyItem = 4,
	EquipItem = 8,
	BuildUpgrade = 4,
	EquipPet = 2,
	-- Родительский режим: вызовы редкие, лимит против перебора PIN скриптом.
	-- Настоящая защита от перебора — пауза после пяти ошибок (Logic/ParentGate).
	ParentAuth = 2,
	GetParentReport = 2,
}

local RemoteDefs = {}

RemoteDefs.EVENTS = EVENTS
RemoteDefs.FUNCTIONS = FUNCTIONS
RemoteDefs.RATE_LIMITS = RATE_LIMITS

local folder: Folder? = nil

local function ensureFolder(): Folder
	if folder then
		return folder
	end

	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			folder = existing
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
		return created
	end

	local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	assert(waited and waited:IsA("Folder"), "RemoteDefs: сервер не создал папку Net")
	folder = waited
	return waited
end

-- Вызывается один раз на сервере при старте.
function RemoteDefs.init()
	assert(
		RunService:IsServer(),
		"RemoteDefs.init можно вызывать только на сервере"
	)
	local parent = ensureFolder()

	for _, name in EVENTS do
		if not parent:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = parent
		end
	end

	for _, name in FUNCTIONS do
		if not parent:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = parent
		end
	end
end

function RemoteDefs.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), `RemoteDefs: неизвестное событие "{name}"`)
	local parent = ensureFolder()
	local remote = if RunService:IsServer()
		then parent:FindFirstChild(name)
		else parent:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), `RemoteDefs: RemoteEvent "{name}" не найден`)
	return remote
end

function RemoteDefs.func(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), `RemoteDefs: неизвестная функция "{name}"`)
	local parent = ensureFolder()
	local remote = if RunService:IsServer()
		then parent:FindFirstChild(name)
		else parent:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteFunction"), `RemoteDefs: RemoteFunction "{name}" не найден`)
	return remote
end

return RemoteDefs
