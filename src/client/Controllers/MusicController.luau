--!strict
--[[
	Фоновая музыка по местам: площадь, забег мира букв, тропа цифр (Config/Music).

	В сумерки (Config/Evening) место площади — «evening», со своей колыбельной.

	Место определяется по тому, где стоит персонаж: забег ребёнка — модель
	`Tunnel_<UserId>` с меткой `Challenge`, и если персонаж рядом с ней, играет
	плейлист забега. Иначе — площадь. Сервер о музыке ничего не знает и знать
	не должен: это чистый звук на клиенте.

	Треки идут по кругу и сменяются плавно. Громкость подчиняется группе Music:
	её ставит родитель в настройках, а на время реплики её приглушает AudioController.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AudioRegistry = require(Shared.Config.AudioRegistry)
local Music = require(Shared.Config.Music)
local Tunnel = require(Shared.Config.Tunnel)
local AudioController = require(script.Parent.AudioController)
local EveningController = require(script.Parent.EveningController)

local MusicController = {}

-- Забеги стоят далеко от площади, в ряд вдоль X (Config/Tunnel.PLOT_ORIGIN): кто там — тот в забеге.
local RUN_FROM_X = Tunnel.PLOT_ORIGIN.X - Tunnel.PLOT_SPACING / 2

local place: string? = nil
local current: Sound? = nil
local hushes: { [string]: boolean } = {} -- кто просит притихнуть: поющий фонтан и подобные
local HUSHED = 0.2 -- доля громкости, пока рядом играет своя музыка места
local position: { [string]: number } = {} -- какой трек плейлиста играл последним

local function available(list: { string }): { string }
	local ids: { string } = {}
	for _, key in list do
		local id = AudioRegistry.ids[key]
		if id and id ~= "" then
			table.insert(ids, id)
		end
	end
	return ids
end

local function targetVolume(): number
	return if next(hushes) then Music.VOLUME * HUSHED else Music.VOLUME
end

local function fadeOut(sound: Sound)
	local tween = TweenService:Create(sound, TweenInfo.new(Music.FADE_SECONDS), { Volume = 0 })
	tween.Completed:Connect(function()
		sound:Destroy()
	end)
	tween:Play()
end

local playNext: (string) -> ()

function playNext(name: string)
	local list = available((Music.PLAYLISTS :: any)[name] or {})
	if #list == 0 then
		return
	end
	local index = (position[name] or 0) % #list + 1
	position[name] = index

	if current then
		fadeOut(current)
	end
	local sound = Instance.new("Sound")
	sound.Name = `Music_{name}`
	sound.SoundId = list[index]
	sound.Volume = 0
	sound.SoundGroup = AudioController.group("Music")
	sound.Parent = SoundService
	current = sound
	sound.Ended:Connect(function()
		if current == sound and place == name then
			playNext(name)
		end
	end)
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(Music.FADE_SECONDS), { Volume = targetVolume() }):Play()
end

local function runModel(): Model?
	local player = Players.LocalPlayer
	for _, folder in workspace:GetChildren() do
		if folder:IsA("Folder") then
			local model = folder:FindFirstChild(`Tunnel_{player.UserId}`)
			if model and model:IsA("Model") then
				return model
			end
		end
	end
	return nil
end

-- Где сейчас ребёнок: имя плейлиста.
local function whereAmI(): string
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local model = runModel()
	if root and model then
		local challenge = model:GetAttribute("Challenge")
		local runPlace = typeof(challenge) == "string" and (Music.RUN_PLACE :: any)[challenge]
		if runPlace and root.Position.X > RUN_FROM_X then
			return runPlace
		end
	end
	-- В сумерки парк засыпает: вместо дневной музыки — колыбельная.
	if EveningController.isNight() then
		return "evening"
	end
	return "hub"
end

function MusicController.current(): (string?, Sound?)
	return place, current
end

--[[
	Притихнуть на время чужой музыки рядом (поющий фонтан): фон не спорит
	с шоу. Причин может быть несколько — громкость вернётся, когда уйдут все.
]]
function MusicController.hush(reason: string, on: boolean)
	if (hushes[reason] == true) == on then
		return
	end
	hushes[reason] = if on then true else nil
	if current then
		TweenService:Create(current, TweenInfo.new(1.5), { Volume = targetVolume() }):Play()
	end
end

function MusicController.init()
	task.spawn(function()
		while true do
			local now = whereAmI()
			if now ~= place then
				place = now
				playNext(now)
			end
			task.wait(Music.CHECK_SECONDS)
		end
	end)
end

return MusicController
