--!strict
--[[
	Звуки природы на клиенте (Config/Ambient): птицы над площадью, вода у фонтана.

	Птицы звучат, пока ребёнок на площади; в забеге их место занимает музыка
	забега, и фон тихо уходит. Вода привязана к месту: невидимая точка с 3D-звуком
	стоит там же, где фонтан из Config/Decor, — передвинули фонтан, звук переехал.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AudioRegistry = require(Shared.Config.AudioRegistry)
local Ambient = require(Shared.Config.Ambient)
local Decor = require(Shared.Config.Decor)
local AudioController = require(script.Parent.AudioController)
local MusicController = require(script.Parent.MusicController)

local AmbientController = {}

local folder: Folder? = nil

local function idOf(key: string): string?
	local id = AudioRegistry.ids[key]
	return if id and id ~= "" then id else nil
end

local function makeSound(key: string, volume: number, parent: Instance): Sound?
	local id = idOf(key)
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = volume
	sound.SoundGroup = AudioController.group("Ambient")
	sound.Parent = parent
	return sound
end

-- Звучащая точка в мире: невидимая, ни с чем не сталкивается, звук затухает к радиусу.
local function placeSpot(parent: Folder, position: Vector3, spot: Ambient.Spot)
	local anchor = Instance.new("Part")
	anchor.Name = `Ambient_{spot.key}`
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = parent
	local sound = makeSound(spot.key, spot.volume, anchor)
	if sound then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = spot.radius * 0.15
		sound.RollOffMaxDistance = spot.radius
		-- Одинаковые фонтаны не должны журчать в унисон.
		sound.TimePosition = math.random() * 20
		sound:Play()
	end
end

function AmbientController.init()
	local sounds = Instance.new("Folder")
	sounds.Name = "AmbientSounds"
	sounds.Parent = workspace
	folder = sounds

	for _, placement in Decor.placements do
		local spot = Ambient.SPOTS[placement.id]
		if spot then
			placeSpot(
				sounds,
				Vector3.new(placement.x, Decor.groundY(placement.x, placement.z) + 3, placement.z),
				spot
			)
		end
	end

	local bed = makeSound(Ambient.BED.key, 0, SoundService)
	if not bed then
		return
	end
	bed:Play()
	task.spawn(function()
		local audible: boolean? = nil
		while true do
			local place = MusicController.current()
			local wanted = place == "hub"
			if wanted ~= audible then
				audible = wanted
				local volume = if wanted then Ambient.BED.volume else 0
				TweenService:Create(bed, TweenInfo.new(Ambient.FADE_SECONDS), { Volume = volume }):Play()
			end
			task.wait(1)
		end
	end)
end

-- Звучащая точка, которой нет в каталоге декора: водопад, паровозик. Только после init.
function AmbientController.spot(position: Vector3, spot: Ambient.Spot)
	if folder then
		placeSpot(folder, position, spot)
	end
end

return AmbientController
