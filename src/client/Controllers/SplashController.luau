--!strict
--[[
	Брызгалки в парке (Config/Playground splash). Сервер поставил сопла и ведро
	с метками, здесь — вода: струи из пола бьют по хореографии от серверных
	часов (Playground.splashJet), гейзер вздыхает, арки льют занавес, ведро
	раз в полминуты опрокидывается. Красная кнопка — «всё сразу» на три секунды,
	только у нажавшего: соседу его брызгалки не ломаем.

	Кого окатило — с того несколько секунд капает. Ни звёзд, ни прогресса:
	бегать под струями весело само по себе.

	Струя — поток частиц, как у поющего фонтана: высоту задаёт скорость вылета.
	Работает только рядом (ACTIVE): издалека брызгалок всё равно не видно.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Playground = require(Shared.Config.Playground)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local AudioController = require(script.Parent.AudioController)

local SplashController = {}

local GRAVITY = 55
local ACTIVE = 150 -- дальше этого от камеры вода не течёт
local DROP = "rbxasset://textures/particles/smoke_main.dds"
local SPRAY = "rbxasset://textures/particles/sparkles_main.dds"
local WATER = Color3.fromRGB(200, 235, 255)
-- Струя голубее у сопла и светлеет к верху: белые клубы на солнце читались паром.
local STREAM = ColorSequence.new(Color3.fromRGB(90, 175, 255), Color3.fromRGB(190, 230, 255))

local player = Players.LocalPlayer

type Jet = { part: BasePart, index: number, stream: ParticleEmitter, spray: ParticleEmitter }
local jets: { Jet } = {}
local curtains: { ParticleEmitter } = {}
type Bucket = {
	model: Model,
	hinge: CFrame,
	dump: Vector3,
	offsets: { [BasePart]: CFrame },
	spill: ParticleEmitter?,
	lastTip: number,
}
local buckets: { Bucket } = {}
local burstUntil = 0
local wetUntil = 0
local drips: ParticleEmitter? = nil
local spraySound: Sound? = nil

local function soundAt(key: string, parent: Instance, volume: number, looped: boolean): Sound?
	local id = AudioRegistry.ids[key]
	if not id or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 60
	sound.SoundGroup = AudioController.group(if looped then "Ambient" else "SFX")
	sound.Parent = parent
	sound:Play()
	return sound
end

local function emitter(parent: Instance, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(4, 4)
	e.Acceleration = Vector3.new(0, -GRAVITY, 0)
	e.Color = ColorSequence.new(WATER)
	e.Rate = 0
	e.Parent = parent
	return e
end

local function addJet(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local stream = emitter(part, DROP)
	stream.Color = STREAM
	stream.SpreadAngle = Vector2.new(2, 2)
	stream.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	stream.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.85, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	local spray = emitter(part, SPRAY)
	spray.SpreadAngle = Vector2.new(12, 12)
	spray.Size = NumberSequence.new(0.35)
	spray.LightEmission = 0.7
	table.insert(jets, {
		part = part,
		index = part:GetAttribute("Index") or 1,
		stream = stream,
		spray = spray,
	})
	if part:GetAttribute("Index") == 0 and not spraySound then
		spraySound = soundAt("amb_splash_spray", part, 0.45, true)
	end
end

local function addCurtain(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local curtain = emitter(part, DROP)
	curtain.Color = STREAM
	-- Веер из середины арки вниз: вода льётся полотном во всю ширину прохода.
	curtain.EmissionDirection = Enum.NormalId.Bottom
	curtain.SpreadAngle = Vector2.new(38, 4)
	curtain.Speed = NumberRange.new(4, 6)
	curtain.Lifetime = NumberRange.new(0.45, 0.55)
	curtain.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.2),
	})
	curtain.Transparency = NumberSequence.new(0)
	curtain.Rate = 170
	table.insert(curtains, curtain)
	-- Блёстки поверх полотна: на голубом полу светлая вода иначе теряется.
	local glitter = curtain:Clone()
	glitter.Texture = SPRAY
	glitter.Size = NumberSequence.new(0.35)
	glitter.LightEmission = 0.8
	glitter.Rate = 40
	glitter.Parent = part
	table.insert(curtains, glitter)
end

local function addBucket(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local hinge = model:GetAttribute("Hinge")
	local dump = model:GetAttribute("Dump")
	if typeof(hinge) ~= "CFrame" or typeof(dump) ~= "Vector3" then
		return
	end
	local offsets = {}
	local spill: ParticleEmitter? = nil
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			offsets[child] = hinge:ToObjectSpace(child.CFrame)
			if child.Name == "BucketSpill" then
				local water = emitter(child, DROP)
				water.Color = STREAM
				water.EmissionDirection = Enum.NormalId.Top
				water.SpreadAngle = Vector2.new(25, 25)
				water.Speed = NumberRange.new(2, 5)
				water.Lifetime = NumberRange.new(1, 1.4)
				water.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1.4),
					NumberSequenceKeypoint.new(1, 2.4),
				})
				water.Transparency = NumberSequence.new(0.1)
				spill = water
			end
		end
	end
	table.insert(buckets, {
		model = model,
		hinge = hinge,
		dump = dump,
		offsets = offsets,
		spill = spill,
		lastTip = 0,
	})
end

-- Окатило: с персонажа капает, у каждого своё.
local function soak(root: BasePart, seconds: number)
	wetUntil = math.max(wetUntil, os.clock() + seconds)
	if drips and drips.Parent == root then
		return
	end
	local drop = Instance.new("ParticleEmitter")
	drop.Name = "Drips"
	drop.Texture = SPRAY
	drop.Color = ColorSequence.new(Color3.fromRGB(90, 170, 255))
	drop.EmissionDirection = Enum.NormalId.Bottom
	drop.Speed = NumberRange.new(1, 3)
	drop.Acceleration = Vector3.new(0, -40, 0)
	drop.Lifetime = NumberRange.new(0.4, 0.7)
	drop.Size = NumberSequence.new(0.5)
	drop.LightEmission = 0.3
	drop.Shape = Enum.ParticleEmitterShape.Box
	drop.Rate = 45
	drop.Parent = root
	drips = drop
end

local function flat(a: Vector3, b: Vector3): number
	return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
end

local function setJet(jet: Jet, share: number)
	local top = if jet.index == 0 then Playground.SPLASH_GEYSER_HEIGHT else Playground.SPLASH_JET_HEIGHT
	local height = top * share
	if height < 0.4 then
		jet.stream.Rate = 0
		jet.spray.Rate = 0
		return
	end
	local speed = math.sqrt(2 * GRAVITY * height)
	local lifetime = NumberRange.new(2 * speed / GRAVITY)
	for _, e in { jet.stream, jet.spray } do
		e.Speed = NumberRange.new(speed * 0.92, speed)
		e.Lifetime = lifetime
	end
	jet.stream.Rate = 70 + 50 * share
	jet.spray.Rate = 8 + 8 * share
end

local function step()
	if drips then
		drips.Enabled = os.clock() < wetUntil
	end
	local camera = workspace.CurrentCamera
	local near = false
	for _, jet in jets do
		if camera and (camera.CFrame.Position - jet.part.Position).Magnitude < ACTIVE then
			near = true
			break
		end
	end
	if spraySound then
		spraySound.Volume = if near then 0.45 else 0
	end
	for _, curtain in curtains do
		curtain.Enabled = near
	end
	if not near then
		for _, jet in jets do
			jet.stream.Rate = 0
			jet.spray.Rate = 0
		end
		return
	end

	local now = workspace:GetServerTimeNow()
	local burst = os.clock() < burstUntil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local wet = false

	for _, jet in jets do
		local share = if burst then 1 else Playground.splashJet(jet.index, now)
		setJet(jet, share)
		if root and share > 0.3 then
			local reach = if jet.index == 0 then 2 else 1.4
			local top = (
				if jet.index == 0 then Playground.SPLASH_GEYSER_HEIGHT else Playground.SPLASH_JET_HEIGHT
			) * share
			if
				flat(root.Position, jet.part.Position) < reach
				and root.Position.Y < jet.part.Position.Y + top + 2
			then
				wet = true
			end
		end
	end
	if root then
		for _, curtain in curtains do
			local spout = curtain.Parent :: BasePart
			local inside = spout.CFrame:PointToObjectSpace(root.Position)
			if math.abs(inside.X) < spout.Size.X / 2 and math.abs(inside.Z) < 1.5 and inside.Y < 0 then
				wet = true
			end
		end
	end

	for _, bucket in buckets do
		local tip = Playground.splashBucket(now)
		local turned = bucket.hinge * CFrame.Angles(0, 0, -math.rad(115) * tip)
		for part, offset in bucket.offsets do
			part.CFrame = turned * offset
		end
		if bucket.spill then
			bucket.spill.Rate = if tip > 0.7 then 160 else 0
		end
		-- Опрокинулось только что: всплеск и звук.
		if tip >= 1 and bucket.lastTip < 1 then
			local spillPart = bucket.spill and bucket.spill.Parent
			local sound = soundAt("sfx_splash_bucket", spillPart or bucket.model, 0.8, false)
			if sound then
				Debris:AddItem(sound, 5)
			end
		end
		bucket.lastTip = tip
		if root and tip > 0.7 and flat(root.Position, bucket.dump) < 3.8 then
			wet = true
		end
	end

	if root and wet then
		soak(root, Playground.SPLASH_WET)
	end
end

-- Красная кнопка: всё разом на SPLASH_BURST секунд, только у нажавшего.
local function addButton(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local home = part.CFrame
	part.Touched:Connect(function(hit: BasePart)
		local character = player.Character
		if not character or not hit:IsDescendantOf(character) or os.clock() < burstUntil then
			return
		end
		burstUntil = os.clock() + Playground.SPLASH_BURST
		local sound = soundAt("sfx_splash_burst", part, 0.7, false)
		if sound then
			Debris:AddItem(sound, 4)
		end
		part.CFrame = home * CFrame.new(0, -0.5, 0)
		task.delay(0.3, function()
			part.CFrame = home
		end)
	end)
end

local function watch(tag: string, add: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
end

-- Стриминг унёс брызгалки: забываем их, вернутся — добавятся заново.
local function forget(instance: Instance)
	for index = #jets, 1, -1 do
		if jets[index].part == instance then
			table.remove(jets, index)
		end
	end
	for index = #curtains, 1, -1 do
		if curtains[index].Parent == instance or curtains[index].Parent == nil then
			table.remove(curtains, index)
		end
	end
	for index = #buckets, 1, -1 do
		if buckets[index].model == instance then
			table.remove(buckets, index)
		end
	end
	if spraySound and (spraySound.Parent == instance or spraySound.Parent == nil) then
		spraySound:Destroy()
		spraySound = nil
	end
end

function SplashController.init()
	watch("AF_SplashJet", addJet)
	watch("AF_SplashCurtain", addCurtain)
	watch("AF_SplashBucket", addBucket)
	watch("AF_SplashButton", addButton)
	for _, tag in { "AF_SplashJet", "AF_SplashCurtain", "AF_SplashBucket" } do
		CollectionService:GetInstanceRemovedSignal(tag):Connect(forget)
	end
	RunService.Heartbeat:Connect(step)
end

return SplashController
