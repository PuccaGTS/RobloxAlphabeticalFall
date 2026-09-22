--!strict
--[[
	Салют за пройденный уровень (Config/Fireworks). Ребёнок добежал до финиша,
	его вернуло на площадь, на экране итоги — а в небе перед ним рвутся ракеты.
	Уровень — главная веха пути, и она должна ощущаться праздником, а не строчкой.

	Всё на клиенте и только у того, кто прошёл уровень: салют — его, а не общий.
	Ракета — одна деталь с хвостом (Trail), разрыв — один выброс частиц
	(ParticleEmitter:Emit), так что десять ракет стоят меньше одной бабочки
	и в бюджет живого мира (Config/LiveWorld) не входят: через три секунды их нет.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Fireworks = require(Shared.Config.Fireworks)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local AudioController = require(script.Parent.AudioController)

local FireworksController = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local random = Random.new()

local function anchor(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Firework"
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	return part
end

local function play(key: string, parent: Instance, volume: number)
	local id = AudioRegistry.ids[key]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = parent
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

-- Искры одного цвета: шар, разлетающийся от центра.
local function sparks(core: BasePart, color: Color3, size: number, speed: number, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK
	-- Днём белое и полное свечение выбеливают салют: цвет держим густым до конца.
	emitter.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.25))
	emitter.LightEmission = 0.5
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(0.7, size * 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.5) })
	emitter.Lifetime = NumberRange.new(1.3, 1.9)
	emitter.Speed = NumberRange.new(speed * 0.85, speed)
	emitter.Drag = 2
	emitter.Acceleration = Vector3.new(0, -7, 0)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = core
	emitter:Emit(count)
end

-- Разрыв: большой шар искр своего цвета, внутри шар поменьше второго цвета, вспышка.
local function burst(position: Vector3, color: Color3, inner: Color3)
	local core = anchor(position)
	core.Transparency = 1
	sparks(core, color, 3.2, Fireworks.BURST_SPEED, Fireworks.SPARKS)
	sparks(core, inner, 2.2, Fireworks.BURST_SPEED * 0.5, math.floor(Fireworks.SPARKS / 2))

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 40
	light.Brightness = 4
	light.Parent = core
	TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	Debris:AddItem(core, 2.8)
end

-- Ракета: взлетает со свистящим хвостом и рвётся наверху.
local function rocket(from: Vector3, to: Vector3, color: Color3, inner: Color3)
	local head = anchor(from)
	head.Color = color
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.25, 0)
	a0.Parent = head
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.25, 0)
	a1.Parent = head
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), color)
	trail.LightEmission = 1
	trail.Lifetime = 0.5
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = head

	local flight = TweenService:Create(
		head,
		TweenInfo.new(Fireworks.FLIGHT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(to) }
	)
	flight.Completed:Once(function()
		head.Transparency = 1
		burst(to, color, inner)
		Debris:AddItem(head, 0.6)
	end)
	flight:Play()
end

--[[
	Салют перед камерой: ракеты взлетают из-за площади веером, по одной
	с короткими паузами, у каждой свой цвет. Свист и хлопки — один звук
	на весь салют (Pro Sound Effects), он и есть «много ракет».
]]
function FireworksController.show()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local side = Vector3.new(-look.Z, 0, look.X)
	local base = camera.CFrame.Position * Vector3.new(1, 0, 1) + look * Fireworks.DISTANCE

	local listener = anchor(camera.CFrame.Position + look * 20)
	listener.Transparency = 1
	play("sfx_fireworks", listener, 0.8)
	Debris:AddItem(listener, 8)

	for index = 1, Fireworks.ROCKETS do
		local spread = (index - (Fireworks.ROCKETS + 1) / 2) / Fireworks.ROCKETS * Fireworks.WIDTH
		local from = base + side * spread * 0.4 + Vector3.new(0, camera.CFrame.Position.Y - 6, 0)
		local to = base
			+ side * (spread + random:NextNumber(-4, 4))
			+ look * random:NextNumber(-8, 8)
			+ Vector3.new(
				0,
				camera.CFrame.Position.Y + random:NextNumber(Fireworks.HEIGHT[1], Fireworks.HEIGHT[2]),
				0
			)
		local color = Fireworks.COLORS[(index - 1) % #Fireworks.COLORS + 1]
		local inner = Fireworks.COLORS[(index + 2) % #Fireworks.COLORS + 1]
		task.delay(
			(index - 1) * Fireworks.INTERVAL + random:NextNumber(0, 0.15),
			rocket,
			from,
			to,
			color,
			inner
		)
	end
end

return FireworksController
