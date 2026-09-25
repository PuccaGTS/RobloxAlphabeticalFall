--!nonstrict
--[[
	Рыбалка у пруда (Config/Playground.POND, строит PlaygroundService).

	По пруду плавают рыбки, у каждой над спинкой буква. Встал на жёлтый круг
	на краю мостков — в руке удочка, голос называет букву, она же крупно
	вверху экрана. Тап по рыбке с этой буквой — клюёт: катушка трещит, рыбка
	вылетает из воды по дуге прямо в ведро, голос повторяет букву. Тап по чужой —
	она плещет хвостом и уплывает быстрее, а голос ещё раз называет нужную.
	Не угадывается долго — нужная рыбка начинает искриться.

	Три рыбки — праздник и задание дня про пруд (ParkReport). Звёзд здесь нет,
	как во всём парке (Config/Playground): это спокойное занятие руками.

	Всё на клиенте: рыбки, удочка и улов у каждого ребёнка свои.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Playground = require(Shared.Config.Playground)
local AudioRegistry = require(Shared.Config.AudioRegistry)

local AudioController = require(script.Parent.AudioController)
local EmoteController = require(script.Parent.EmoteController)
local ParkReport = require(script.Parent.ParkReport)
local HUD = require(script.Parent.Parent.UI.HUD)

local FishingController = {}

local player = Players.LocalPlayer

local FISH_COLORS = {
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(90, 170, 245),
	Color3.fromRGB(250, 205, 70),
	Color3.fromRGB(240, 110, 160),
	Color3.fromRGB(120, 210, 120),
	Color3.fromRGB(170, 130, 240),
}
local NEAR = 160 -- дальше этого рыбки не плавают: их всё равно не видно
local ON_MARK = 2.6 -- столько от середины круга — ещё на круге
local TAP_REACH = 90 -- пикселей от пальца до рыбки на экране: промахнуться трудно
local HINT_AFTER = 9 -- через столько секунд без улова нужная рыбка начинает искриться
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

type Fish = {
	model: Model,
	body: BasePart,
	label: TextLabel,
	sparkle: ParticleEmitter,
	letterId: string,
	ring: number, -- радиус круга, по которому плывёт
	speed: number, -- рад/с, со знаком: в какую сторону
	angle: number,
	flee: number, -- до какого момента удирает от чужого тапа
	busy: boolean, -- летит в ведро
}

local pond: BasePart? = nil
local mark: BasePart? = nil
local fishes: { Fish } = {}
local pool: { string } = {}
local active = false
local target: string? = nil
local caught = 0
local waitingSince = 0
local lastSaid = 0
local rod: BasePart? = nil
local bobber: BasePart? = nil
local line: Beam? = nil

local function playKey(key: string, at: Instance, volume: number, speed: number?)
	local id = AudioRegistry.ids[key]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 80
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = if at:IsA("BasePart") then at else SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
end

local function burst(at: Vector3, color: Color3, count: number)
	local holder = Instance.new("Attachment")
	holder.Parent = workspace.Terrain
	holder.WorldPosition = at
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLES
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	Debris:AddItem(holder, 1.5)
end

-- Буквы для рыбок: выученные ребёнком и все буквы первой ступени — чтобы было из чего выбрать.
function FishingController.update(snapshot: any)
	local list: { string } = table.clone(Letters.byStage(1))
	if typeof(snapshot) == "table" and typeof(snapshot.mastery) == "table" then
		for _, id in Letters.ordered() do
			if (tonumber(snapshot.mastery[id]) or 0) >= 1 and not table.find(list, id) then
				table.insert(list, id)
			end
		end
	end
	if #list < 4 then
		for _, id in Letters.byStage(2) do
			table.insert(list, id)
		end
	end
	pool = list
end

local function randomLetter(except: string?): string
	local choices = {}
	for _, id in pool do
		if id ~= except then
			table.insert(choices, id)
		end
	end
	return choices[math.random(1, #choices)]
end

local function setLetter(fish: Fish, letterId: string)
	fish.letterId = letterId
	local letter = Letters.expect(letterId)
	fish.label.Text = letter.glyph
	fish.label.TextColor3 = letter.color
end

-- Рыбка: овальное тельце, хвост-веер, плавники, глазки и буква над спинкой.
local function buildFish(index: number): Fish
	local color = FISH_COLORS[(index - 1) % #FISH_COLORS + 1]
	local model = Instance.new("Model")
	model.Name = `Fish_{index}`

	local function piece(name: string, size: Vector3, offset: CFrame, tint: Color3, sphere: boolean): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = offset
		p.Color = tint
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		if sphere then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Parent = model
		return p
	end

	-- Нос смотрит в −Z: так рыбку удобно ставить CFrame.lookAt по ходу.
	local body = piece("Body", Vector3.new(1.2, 1, 2.6), CFrame.identity, color, true)
	piece(
		"Belly",
		Vector3.new(1, 0.6, 2),
		CFrame.new(0, -0.22, 0),
		color:Lerp(Color3.new(1, 1, 1), 0.5),
		true
	)
	piece(
		"Tail",
		Vector3.new(0.2, 1.3, 1),
		CFrame.new(0, 0, 1.55),
		color:Lerp(Color3.new(0, 0, 0), 0.15),
		true
	)
	piece(
		"Fin",
		Vector3.new(0.15, 0.7, 0.9),
		CFrame.new(0, 0.55, 0.1),
		color:Lerp(Color3.new(0, 0, 0), 0.15),
		true
	)
	for _, side in { -1, 1 } do
		piece(
			`Eye_{side}`,
			Vector3.new(0.32, 0.32, 0.32),
			CFrame.new(side * 0.5, 0.2, -0.8),
			Color3.new(1, 1, 1),
			true
		)
		piece(
			`Pupil_{side}`,
			Vector3.new(0.18, 0.18, 0.18),
			CFrame.new(side * 0.6, 0.22, -0.88),
			Color3.new(0, 0, 0),
			true
		)
	end
	model.PrimaryPart = body

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(2.2, 2.2)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Parent = body
	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 252, 240)
	bubble.BackgroundTransparency = 0.1
	bubble.Parent = billboard
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = bubble
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.8, 0.8)
	label.Position = UDim2.fromScale(0.1, 0.1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = bubble

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = SPARKLES
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparkle.Size = NumberSequence.new(0.6, 0)
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Rate = 14
	sparkle.Enabled = false
	sparkle.Parent = body

	local spec = Playground.POND
	local fish: Fish = {
		model = model,
		body = body,
		label = label,
		sparkle = sparkle,
		letterId = "a",
		ring = spec.radius * (0.35 + 0.1 * (index % 5)),
		speed = (0.25 + 0.07 * index) * (if index % 2 == 0 then -1 else 1),
		angle = index * 1.3,
		flee = 0,
		busy = false,
	}
	setLetter(fish, randomLetter(nil))
	model.Parent = workspace
	return fish
end

local function fishFrame(fish: Fish, now: number): CFrame
	local center = (pond :: BasePart).Position
	local radius = math.min(fish.ring, Playground.POND.radius - 1.6)
	local position = center
		+ Vector3.new(
			math.cos(fish.angle) * radius,
			0.35 + math.sin(now * 2 + fish.angle) * 0.12,
			math.sin(fish.angle) * radius
		)
	local direction = if fish.speed > 0 then 1 else -1
	local tangent = Vector3.new(-math.sin(fish.angle), 0, math.cos(fish.angle)) * direction
	-- Хвостом виляет: небольшой поворот туда-сюда.
	local wiggle = math.sin(now * 8 + fish.angle * 3) * 0.18
	return CFrame.lookAt(position, position + tangent) * CFrame.Angles(0, wiggle, 0)
end

-- Удочка в правой руке и поплавок на воде перед мостками.
local function takeRod()
	local character = player.Character
	local hand = character
		and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand or not hand:IsA("BasePart") or rod or not pond or not mark then
		return
	end
	local pole = Instance.new("Part")
	pole.Name = "FishingRod"
	pole.Size = Vector3.new(0.2, 0.2, 6)
	pole.Color = Color3.fromRGB(120, 80, 45)
	pole.Material = Enum.Material.Wood
	pole.CanCollide = false
	pole.CanQuery = false
	pole.CanTouch = false
	pole.Massless = true
	-- Наклон считаем от туловища, а не от кисти: кисть у разных аватаров повёрнута по-разному.
	local root = character:FindFirstChild("HumanoidRootPart")
	local facing = if root and root:IsA("BasePart") then root.CFrame.Rotation else CFrame.identity
	pole.CFrame = CFrame.new(hand.Position)
		* facing
		* CFrame.Angles(math.rad(35), 0, 0)
		* CFrame.new(0, 0, -2.8)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = pole
	weld.Parent = pole
	pole.Parent = character
	local end_ = Instance.new("Attachment")
	end_.Position = Vector3.new(0, 0, -3)
	end_.Parent = pole
	rod = pole

	local float = Instance.new("Part")
	float.Name = "FishingBobber"
	float.Shape = Enum.PartType.Ball
	float.Size = Vector3.new(0.6, 0.6, 0.6)
	float.Color = Color3.fromRGB(235, 70, 60)
	float.Anchored = true
	float.CanCollide = false
	float.CanQuery = false
	float.CanTouch = false
	local ahead = (pond.Position - mark.Position) * Vector3.new(1, 0, 1)
	float.Position = Vector3.new(mark.Position.X, pond.Position.Y + 0.35, mark.Position.Z) + ahead.Unit * 3
	float.Parent = workspace
	bobber = float
	local hook = Instance.new("Attachment")
	hook.Parent = float
	local beam = Instance.new("Beam")
	beam.Attachment0 = end_
	beam.Attachment1 = hook
	beam.Width0 = 0.06
	beam.Width1 = 0.06
	beam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
	beam.CurveSize0 = -1
	beam.FaceCamera = true
	beam.Parent = pole
	line = beam
end

local function dropRod()
	if rod then
		rod:Destroy()
	end
	if bobber then
		bobber:Destroy()
	end
	rod, bobber, line = nil, nil, nil
end

local function sayTarget()
	if not target then
		return
	end
	lastSaid = os.clock()
	AudioController.speak(Letters.expect(target).vo.name)
end

-- Новая буква: у хотя бы одной свободной рыбки должна быть именно она.
local function newTarget()
	target = randomLetter(target)
	waitingSince = os.clock()
	local has = false
	for _, fish in fishes do
		fish.sparkle.Enabled = false
		if fish.letterId == target and not fish.busy then
			has = true
		end
	end
	if not has then
		local free = {}
		for _, fish in fishes do
			if not fish.busy then
				table.insert(free, fish)
			end
		end
		if #free > 0 then
			setLetter(free[math.random(1, #free)], target :: string)
		end
	end
	HUD.showTarget(Letters.expect(target :: string).glyph, caught, Playground.POND.goal)
	sayTarget()
end

local function start()
	active = true
	caught = 0
	takeRod()
	newTarget()
end

local function stop()
	active = false
	target = nil
	dropRod()
	for _, fish in fishes do
		fish.sparkle.Enabled = false
	end
	HUD.showTarget(nil)
end

-- Поймал: рыбка по дуге летит из воды в ведро, леска тянется за ней.
local function reel(fish: Fish)
	fish.busy = true
	fish.sparkle.Enabled = false
	local from = fish.body.Position
	local bucketAt = mark and mark:GetAttribute("Bucket")
	local to = if typeof(bucketAt) == "Vector3" then bucketAt else from + Vector3.new(0, 4, 0)
	playKey("sfx_fish_reel", fish.body, 0.7)
	playKey("sfx_fish_drip", fish.body, 0.8)
	burst(from, Color3.fromRGB(170, 220, 255), 18)
	if line then
		local hook = Instance.new("Attachment")
		hook.Parent = fish.body
		line.Attachment1 = hook
	end
	local seconds = Playground.POND.bite
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - started) / seconds, 0, 1)
		local arc = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 6, 0)
		fish.model:PivotTo(CFrame.new(arc) * CFrame.Angles(math.sin(t * 20) * 0.5, t * 6, 0))
		if t >= 1 then
			connection:Disconnect()
			burst(to, Letters.expect(fish.letterId).color, 20)
			playKey("sfx_crystal", fish.body, 0.6, 1.2)
			fish.model.Parent = nil
			if line and bobber then
				line.Attachment1 = bobber:FindFirstChildOfClass("Attachment")
			end
			-- Новая рыбка выплывает с дальнего края через пару секунд.
			task.delay(2, function()
				fish.busy = false
				fish.angle += math.pi
				setLetter(fish, randomLetter(target))
				fish.model.Parent = workspace
			end)
		end
	end)
end

local function onTap(screen: Vector2)
	local camera = workspace.CurrentCamera
	if not active or not target or not camera then
		return
	end
	local best, bestDistance = nil, TAP_REACH
	for _, fish in fishes do
		if not fish.busy and fish.model.Parent then
			local point, visible = camera:WorldToViewportPoint(fish.body.Position + Vector3.new(0, 0.9, 0))
			if visible then
				local distance = (Vector2.new(point.X, point.Y) - screen).Magnitude
				if distance < bestDistance then
					best, bestDistance = fish, distance
				end
			end
		end
	end
	if not best then
		return
	end
	if best.letterId == target then
		local letter = Letters.expect(target)
		caught += 1
		reel(best)
		AudioController.speak(letter.vo.name)
		HUD.showTarget(letter.glyph, caught, Playground.POND.goal)
		if caught >= Playground.POND.goal then
			caught = 0
			EmoteController.play("cheer")
			ParkReport.done("pond")
			task.delay(1.2, HUD.toast, "🎣 Три рыбки в ведре! Молодец!", 4)
		end
		task.delay(Playground.POND.bite + 0.8, function()
			if active then
				newTarget()
			end
		end)
	else
		-- Не та: плеснула хвостом и удирает, а голос ещё раз называет нужную.
		best.flee = os.clock() + 1.6
		playKey("sfx_fish_splash", best.body, 0.6, 1.2)
		burst(best.body.Position, Color3.fromRGB(170, 220, 255), 12)
		if os.clock() - lastSaid > 1.5 then
			sayTarget()
		end
	end
end

local function step(dt: number)
	if not pond or not mark or not pond.Parent then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local near = (root.Position - pond.Position).Magnitude < NEAR
	if #fishes == 0 and near then
		for index = 1, Playground.POND.fish do
			table.insert(fishes, buildFish(index))
		end
	end
	if not near then
		if active then
			stop()
		end
		return
	end

	local now = os.clock()
	for _, fish in fishes do
		if not fish.busy then
			local fast = if fish.flee > now then 4 else 1
			fish.angle += fish.speed * dt * fast
			fish.model:PivotTo(fishFrame(fish, now))
		end
	end

	local flat = (root.Position - mark.Position) * Vector3.new(1, 0, 1)
	local onMark = flat.Magnitude < ON_MARK and math.abs(root.Position.Y - mark.Position.Y) < 5
	if onMark and not active then
		start()
	elseif not onMark and active then
		stop()
	end
	if active and target and now - waitingSince > HINT_AFTER then
		for _, fish in fishes do
			fish.sparkle.Enabled = fish.letterId == target and not fish.busy
		end
	end
	-- Поплавок покачивается.
	if bobber then
		bobber.Position = Vector3.new(
			bobber.Position.X,
			pond.Position.Y + 0.35 + math.sin(now * 3) * 0.08,
			bobber.Position.Z
		)
	end
end

function FishingController.init()
	FishingController.update(nil)
	local function watchTag(tag: string, set: (BasePart) -> ())
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			if instance:IsA("BasePart") then
				set(instance)
			end
		end)
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("BasePart") then
				set(instance)
			end
		end
	end
	watchTag("AF_Pond", function(part)
		pond = part
	end)
	watchTag("AF_FishingMark", function(part)
		mark = part
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			onTap(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	RunService.Heartbeat:Connect(step)
end

-- Для стенда проверки: где рыбка с буквой и сколько поймано.
function FishingController.debug()
	local list = {}
	for _, fish in fishes do
		table.insert(list, { letterId = fish.letterId, position = fish.body.Position, busy = fish.busy })
	end
	return { active = active, target = target, caught = caught, fishes = list }
end

FishingController.tap = onTap

return FishingController
