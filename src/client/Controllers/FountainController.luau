--!strict
--[[
	Поющий фонтан на клиенте (Config/Fountain). Сопла — невидимые точки
	над чашей фонтана из Config/Decor, у каждого излучатель капель. Раз в
	полторы минуты по серверным часам начинается шоу: струи бьют по
	хореографии Fountain.height, красятся радугой, играет «Water Ballet»,
	а фоновая музыка рядом с фонтаном на это время притихает.

	Струя — поток частиц, а не детали: высоту задаёт скорость вылета,
	и капли падают сами. Бюджет живого мира (Config/LiveWorld) это не трогает.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Fountain = require(Shared.Config.Fountain)
local Decor = require(Shared.Config.Decor)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local AudioController = require(script.Parent.AudioController)
local MusicController = require(script.Parent.MusicController)

local FountainController = {}

-- Мягкие клубы сливаются в сплошной столб воды; искры поверх — брызги.
local DROP = "rbxasset://textures/particles/smoke_main.dds"
local SPRAY = "rbxasset://textures/particles/sparkles_main.dds"
local WATER = Color3.fromRGB(215, 240, 255)

type Jet = { index: number, emitter: ParticleEmitter, spray: ParticleEmitter }
local jets: { Jet } = {}
local music: Sound? = nil
local wasShowing = false

local function nozzle(folder: Folder, index: number, position: Vector3): Jet
	local part = Instance.new("Part")
	part.Name = `Jet_{index}`
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = CFrame.new(position)
	part.Parent = folder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = DROP
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(3, 3)
	emitter.Acceleration = Vector3.new(0, -Fountain.GRAVITY, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 1.3),
		NumberSequenceKeypoint.new(1, 2),
	})
	-- На ярком дневном небе полупрозрачная вода пропадает: столб держим плотным.
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.85, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(WATER)
	emitter.Parent = part

	local spray = emitter:Clone()
	spray.Texture = SPRAY
	spray.SpreadAngle = Vector2.new(8, 8)
	spray.Size = NumberSequence.new(0.5)
	spray.LightEmission = 0.8
	spray.Parent = part
	return { index = index, emitter = emitter, spray = spray }
end

-- Струя высотой share от предельной: скорость вылета, время полёта и густота.
local function setJet(jet: Jet, share: number, color: Color3)
	local top = if jet.index == 0 then Fountain.CENTER_HEIGHT else Fountain.MAX_HEIGHT
	local height = top * share
	if height < 0.5 then
		jet.emitter.Rate = 0
		jet.spray.Rate = 0
		return
	end
	local speed = math.sqrt(2 * Fountain.GRAVITY * height)
	-- Капля живёт, пока взлетает и падает обратно в чашу.
	local lifetime = NumberRange.new(2 * speed / Fountain.GRAVITY)
	local tint = ColorSequence.new(color, color:Lerp(WATER, 0.3))
	for _, emitter in { jet.emitter, jet.spray } do
		emitter.Speed = NumberRange.new(speed * 0.95, speed)
		emitter.Lifetime = lifetime
		emitter.Color = tint
	end
	jet.emitter.Rate = 35 + 30 * share
	jet.spray.Rate = 10 + 10 * share
end

local function startMusic(folder: Folder, t: number)
	local id = AudioRegistry.ids.mus_fountain_show
	if not id or id == "" then
		return
	end
	local anchor = folder:FindFirstChild("Jet_0") :: BasePart?
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.7
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = Fountain.HEAR
	sound.SoundGroup = AudioController.group("Music")
	sound.TimePosition = t
	sound.Parent = anchor or folder
	sound:Play()
	music = sound
end

local function stopMusic()
	local sound = music
	music = nil
	if not sound then
		return
	end
	local fade = TweenService:Create(sound, TweenInfo.new(2), { Volume = 0 })
	fade.Completed:Connect(function()
		sound:Destroy()
	end)
	fade:Play()
end

local function step()
	local t = Fountain.showTime(workspace:GetServerTimeNow())
	local camera = workspace.CurrentCamera
	local near = camera ~= nil and (camera.CFrame.Position - Fountain.CENTER).Magnitude < Fountain.HEAR
	local showing = t ~= nil
	if showing ~= wasShowing then
		wasShowing = showing
		if showing then
			local folder = workspace:FindFirstChild("AlphabetFallFountain")
			if folder and folder:IsA("Folder") then
				startMusic(folder, t or 0)
			end
		else
			stopMusic()
		end
	end
	-- Фоновая музыка рядом с шоу притихает, чтобы два вальса не спорили.
	MusicController.hush("fountain", showing and near)

	for _, jet in jets do
		if t then
			setJet(jet, Fountain.height(jet.index, t), Fountain.color(jet.index, t))
		else
			-- Вне шоу фонтан журчит сам (модель из Store): струи молчат.
			jet.emitter.Rate = 0
			jet.spray.Rate = 0
		end
	end
end

function FountainController.init()
	local folder = Instance.new("Folder")
	folder.Name = "AlphabetFallFountain"
	folder.Parent = workspace
	local center = Fountain.CENTER
	local ground = Decor.groundY(center.X, center.Z)
	table.insert(jets, nozzle(folder, 0, Vector3.new(center.X, ground + Fountain.NOZZLE_Y + 2.5, center.Z)))
	for index = 1, Fountain.JETS do
		local a = (index - 1) / Fountain.JETS * math.pi * 2
		local position = center
			+ Vector3.new(
				math.cos(a) * Fountain.RING,
				ground + Fountain.NOZZLE_Y,
				math.sin(a) * Fountain.RING
			)
		table.insert(jets, nozzle(folder, index, position))
	end
	RunService.Heartbeat:Connect(step)
end

return FountainController
