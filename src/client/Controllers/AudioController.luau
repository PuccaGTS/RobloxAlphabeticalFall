--!strict
--[[
	Аудио-контроллер: очередь озвучки и приглушение музыки.
	Реализует требования docs/05-AUDIO-VO.md § 5.

	Ключевые правила:
	  · реплики НЕ накладываются — только очередь;
	  · название буквы (letter_) нельзя прервать ничем — это эталон;
	  · на время любой реплики музыка и эмбиент опускаются до 30%;
	  · кнопка «динамик» повторяет последнюю значимую реплику.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AudioRegistry = require(Shared.Config.AudioRegistry)

local AudioController = {}

local DUCK_FACTOR = 0.3
local DUCK_IN = 0.15
local DUCK_OUT = 0.3
local REPEAT_COOLDOWN = 0.5
-- Страховка от зависшей очереди: ни одна реплика в игре не длиннее нескольких секунд
-- (docs/05-AUDIO-VO.md § 3), так что ждать дольше бессмысленно.
local MAX_CLIP_SECONDS = 12

-- Приоритеты: чем больше, тем важнее. 3 = название буквы, прерывать запрещено.
local PRIORITY_BY_PREFIX: { { prefix: string, priority: number } } = {
	{ prefix = "letter_", priority = 3 },
	-- Число — такой же эталон, как название буквы: прерывать его нечем.
	{ prefix = "num_", priority = 3 },
	{ prefix = "mtask_", priority = 2 },
	{ prefix = "mop_", priority = 2 },
	{ prefix = "instr_", priority = 2 },
	{ prefix = "story_", priority = 2 },
	{ prefix = "praise_", priority = 1 },
	{ prefix = "retry_", priority = 1 },
	{ prefix = "hint_", priority = 1 },
	{ prefix = "ui_", priority = 0 },
}

-- Реплики, которые запоминает кнопка «повторить»
local REPEATABLE_PRIORITY = 2

type QueueItem = {
	key: string,
	assetId: string,
	priority: number,
}

local groups: { [string]: SoundGroup } = {}
local baseVolume: { [string]: number } = {
	Master = 1,
	VO = 1,
	SFX = 0.7,
	Music = 0.6,
	Ambient = 0.5,
}

local queue: { QueueItem } = {}
local current: Sound? = nil
local currentPriority = -1
local lastRepeatable: string? = nil
-- Задание из нескольких реплик («Сколько будет два плюс два»): кнопка «повторить»
-- обязана повторить его целиком, а не последний кусок.
local lastPhrase: { string }? = nil
local lastRepeatAt = 0
local ducked = false
local pumping = false

local function priorityOf(key: string): number
	for _, entry in PRIORITY_BY_PREFIX do
		if string.sub(key, 1, #entry.prefix) == entry.prefix then
			return entry.priority
		end
	end
	return 0
end

local function getOrCreateGroup(name: string, parent: Instance, volume: number): SoundGroup
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end

	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = volume
	group.Parent = parent
	return group
end

local function ensureGroups()
	if groups.Master then
		return
	end

	local master = getOrCreateGroup("Master", SoundService, baseVolume.Master)
	groups.Master = master

	for _, name in { "VO", "SFX", "Music", "Ambient" } do
		groups[name] = getOrCreateGroup(name, master, baseVolume[name])
	end
end

local function tweenGroup(name: string, volume: number, time: number)
	local group = groups[name]
	if not group then
		return
	end
	TweenService:Create(group, TweenInfo.new(time), { Volume = volume }):Play()
end

local function setDucked(state: boolean)
	if ducked == state then
		return
	end
	ducked = state
	local time = if state then DUCK_IN else DUCK_OUT
	local factor = if state then DUCK_FACTOR else 1
	tweenGroup("Music", baseVolume.Music * factor, time)
	tweenGroup("Ambient", baseVolume.Ambient * factor, time)
end

local function playItem(item: QueueItem)
	local sound = Instance.new("Sound")
	sound.Name = "VO_" .. item.key
	sound.SoundId = item.assetId
	sound.SoundGroup = groups.VO
	sound.Volume = 1
	sound.Parent = SoundService

	current = sound
	currentPriority = item.priority

	if item.priority >= REPEATABLE_PRIORITY then
		lastRepeatable = item.key
	end

	sound:Play()

	-- Ждём окончания, но со страховкой: если ассет не загрузился, Ended может не прийти
	-- никогда, а очередь озвучки вставать не имеет права.
	local finished = false
	local connections = {
		sound.Ended:Connect(function()
			finished = true
		end),
		sound.Stopped:Connect(function()
			finished = true
		end),
	}
	local deadline = os.clock() + MAX_CLIP_SECONDS
	while not finished and os.clock() < deadline do
		task.wait(0.05)
	end
	for _, connection in connections do
		connection:Disconnect()
	end

	sound:Destroy()
	current = nil
	currentPriority = -1
end

local function pump()
	if pumping then
		return
	end
	pumping = true

	task.spawn(function()
		while #queue > 0 do
			setDucked(true)
			local item = table.remove(queue, 1) :: QueueItem
			local ok, err = pcall(playItem, item)
			if not ok then
				warn(`[AudioController] не удалось проиграть {item.key}: {err}`)
				current = nil
				currentPriority = -1
			end
		end
		setDucked(false)
		pumping = false
	end)
end

--[[
	Ставит реплику в очередь. Возвращает false, если озвучки ещё нет —
	вызывающий код обязан это пережить (показать анимацию и идти дальше).
]]
function AudioController.speak(key: string): boolean
	ensureGroups()

	local assetId = AudioRegistry.resolve(key)
	if not assetId then
		-- реплика не записана: запоминаем как «последнюю» всё равно,
		-- чтобы кнопка «повторить» вела себя предсказуемо, когда аудио появится
		local priority = priorityOf(key)
		if priority >= REPEATABLE_PRIORITY then
			lastRepeatable = key
			lastPhrase = nil
		end
		return false
	end

	table.insert(queue, { key = key, assetId = assetId, priority = priorityOf(key) })
	if priorityOf(key) >= REPEATABLE_PRIORITY then
		lastPhrase = nil
	end
	pump()
	return true
end

--[[
	Фраза: несколько реплик подряд как одно задание. Так говорит математика —
	«Сколько будет» + «два» + «плюс» + «два» (docs/16-MATH.md § 5).

	Возвращает false, если не прозвучало НИЧЕГО: часть кусков может быть ещё
	не записана, и это не повод молчать целиком — ребёнок услышит то, что есть,
	а недостающее увидит на воротах.
]]
function AudioController.speakPhrase(keys: { string }): boolean
	ensureGroups()

	local spoken = false
	for _, key in keys do
		if AudioController.speak(key) then
			spoken = true
		end
	end

	-- Фразу запоминаем целиком и всегда, даже если озвучки ещё нет: кнопка
	-- «повторить» должна вести себя одинаково до и после записи реплик.
	lastPhrase = table.clone(keys)
	lastRepeatable = nil
	return spoken
end

--[[
	Срочная реплика: очищает очередь из менее важных, но НИКОГДА не обрывает
	уже звучащий эталон звука (priority 3).
]]
function AudioController.interrupt(key: string): boolean
	ensureGroups()

	local priority = priorityOf(key)
	local filtered: { QueueItem } = {}
	for _, item in queue do
		if item.priority > priority then
			table.insert(filtered, item)
		end
	end
	queue = filtered

	local sound = current
	if sound and currentPriority < priority and currentPriority < 3 then
		sound:Stop()
	end

	return AudioController.speak(key)
end

-- Кнопка «динамик» на HUD. Самая нажимаемая кнопка в игре — держим её отзывчивой.
function AudioController.repeatLast(): boolean
	local phrase = lastPhrase
	local key = lastRepeatable
	if not phrase and not key then
		return false
	end

	local now = os.clock()
	if now - lastRepeatAt < REPEAT_COOLDOWN then
		return false
	end
	lastRepeatAt = now

	if phrase then
		local spoken = false
		for _, item in phrase do
			if AudioController.speak(item) then
				spoken = true
			end
		end
		-- speak() сбросил бы запомненную фразу, повторяя её же: возвращаем на место.
		lastPhrase = phrase
		lastRepeatable = nil
		return spoken
	end

	return AudioController.speak(key :: string)
end

function AudioController.stopAll()
	queue = {}
	local sound = current
	if sound then
		sound:Stop()
	end
	setDucked(false)
end

function AudioController.setVolume(groupName: string, volume: number)
	ensureGroups()
	baseVolume[groupName] = math.clamp(volume, 0, 1)
	local factor = if ducked and (groupName == "Music" or groupName == "Ambient") then DUCK_FACTOR else 1
	tweenGroup(groupName, baseVolume[groupName] * factor, 0.1)
end

-- Предзагрузка пачки реплик (обычно — всё аудио текущей ступени) на экране загрузки.
function AudioController.preload(keys: { string })
	ensureGroups()

	local sounds: { Instance } = {}
	for _, key in keys do
		local assetId = AudioRegistry.resolve(key)
		if assetId then
			local sound = Instance.new("Sound")
			sound.SoundId = assetId
			table.insert(sounds, sound)
		end
	end

	if #sounds == 0 then
		return
	end

	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(sounds)
	end)
	if not ok then
		warn(`[AudioController] предзагрузка не удалась: {err}`)
	end

	for _, sound in sounds do
		sound:Destroy()
	end
end

--[[
	Группа звука по имени. Нужна эффектам: они играют мимо очереди реплик,
	но обязаны подчиняться той же громкости и тому же приглушению на время речи.
]]
function AudioController.group(name: string): SoundGroup?
	ensureGroups()
	return groups[name]
end

function AudioController.init()
	ensureGroups()
end

return AudioController
