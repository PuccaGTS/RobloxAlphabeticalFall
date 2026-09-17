--!nonstrict
--[[
	Игра на игровых местах парка (Config/Playground). Сервер поставил детали
	и метки, здесь — что происходит, когда ребёнок до них дотронулся:

	  · батут подбрасывает и чуть проседает;
	  · клавиша музыкальной дорожки звучит своей нотой и вспыхивает;
	  · клетка классиков называет своё число и показывает его крупно;
	  · шарик лопается искрами и через несколько секунд вырастает снова;
	  · флажок в середине лабиринта радуется найденному.

	Всё локальное: у каждого ребёнка свои лопнутые шарики, и никакой награды —
	её здесь нет и быть не должно (Config/Playground). Метки приходят через
	CollectionService, поэтому места, которые подгрузились позже (стриминг),
	подключаются сами.

	Звуки — только встроенные в клиент (как в Config/Sfx): грузить нечего.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Playground = require(Shared.Config.Playground)

local AudioController = require(script.Parent.AudioController)

local PlaygroundController = {}

local NOTE_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local BOUNCE_SOUND = "rbxasset://sounds/action_jump.mp3"
local POP_SOUND = "rbxasset://sounds/paintball.wav"
local CHEER_SOUND = "rbxasset://sounds/victory.wav"
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local player = Players.LocalPlayer
local cooldown: { [Instance]: number } = {}

local function isMine(hit: BasePart): boolean
	local character = player.Character
	return character ~= nil and hit:IsDescendantOf(character)
end

-- Не чаще, чем раз в seconds на одну деталь: стоящий на клавише не звенит без конца.
local function ready(part: Instance, seconds: number): boolean
	local now = os.clock()
	if (cooldown[part] or 0) > now then
		return false
	end
	cooldown[part] = now + seconds
	return true
end

local function playSound(id: string, speed: number, volume: number, at: BasePart)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	sound.RollOffMaxDistance = 80
	-- Через группу эффектов: громкость из родительских настроек действует и здесь.
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = at
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(3, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function burst(part: BasePart, color: Color3, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLES
	emitter.Color = ColorSequence.new(color)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(6, 12)
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Parent = part
	emitter:Emit(count)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end

local function rootOf(): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local HANDLERS: { [string]: (BasePart) -> () } = {}

HANDLERS.AF_Trampoline = function(top: BasePart)
	local home = top.CFrame
	top.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(top, 0.35) then
			return
		end
		local root = rootOf()
		if not root then
			return
		end
		local velocity = root.AssemblyLinearVelocity
		local power = top:GetAttribute("Power") or 70
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, power, velocity.Z)
		playSound(BOUNCE_SOUND, 0.8 + power / 200, 0.5, top)

		-- Сетка проседает и пружинит обратно.
		top.CFrame = home * CFrame.new(0, -0.35, 0)
		TweenService:Create(top, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { CFrame = home }):Play()
	end)
end

HANDLERS.AF_Note = function(key: BasePart)
	local home = key.CFrame
	key.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(key, 0.4) then
			return
		end
		local note = key:GetAttribute("Note") or 1
		playSound(NOTE_SOUND, Playground.NOTE_SPEEDS[note] or 1, 0.5, key)
		key.CFrame = home * CFrame.new(0, -0.2, 0)
		TweenService:Create(key, TweenInfo.new(0.3, Enum.EasingStyle.Back), { CFrame = home }):Play()
		burst(key, key.Color, 6)
	end)
end

-- Крупное число над клеткой: видно, на что наступил, даже пока голос молчит.
local function showNumber(tile: BasePart, number: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 120)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = tile
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(number)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(1.2), { StudsOffset = Vector3.new(0, 7, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()
	task.delay(1.3, function()
		billboard:Destroy()
	end)
end

HANDLERS.AF_Number = function(tile: BasePart)
	tile.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(tile, 1.2) then
			return
		end
		local number = tile:GetAttribute("Number") or 1
		AudioController.speak(`num_{number}`)
		playSound(NOTE_SOUND, 0.8 + number * 0.08, 0.25, tile)
		showNumber(tile, number)
	end)
end

HANDLERS.AF_Balloon = function(balloon: BasePart)
	local popped = false
	local rope = balloon:FindFirstChildWhichIsA("BasePart")
	balloon.Touched:Connect(function(hit)
		if popped or not isMine(hit) then
			return
		end
		popped = true
		playSound(POP_SOUND, 1.3, 0.45, balloon)
		burst(balloon, balloon.Color, 25)
		balloon.Transparency = 1
		if rope then
			rope.Transparency = 1
		end

		task.delay(Playground.BALLOON_REGROW, function()
			if not balloon.Parent then
				return
			end
			if rope then
				rope.Transparency = 0
			end
			local size = balloon.Size
			balloon.Size = size * 0.2
			balloon.Transparency = 0.1
			TweenService:Create(balloon, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Size = size }):Play()
			popped = false
		end)
	end)
end

-- Касание флажка в середине лабиринта: нашёл! Звук победы и искры.
HANDLERS.AF_MazeFlag = function(flag: BasePart)
	flag.CanTouch = true
	-- Флажок висит высоко: засчитываем, когда ребёнок просто дошёл до середины.
	task.spawn(function()
		while flag.Parent do
			task.wait(0.5)
			local root = rootOf()
			if root and (root.Position - flag.Position).Magnitude < 7 and ready(flag, 8) then
				playSound(CHEER_SOUND, 1, 0.5, flag)
				burst(flag, flag.Color, 40)
			end
		end
	end)
end

--[[
	Крылья мельниц в парке (DecorShapes.windmill). Крутятся здесь, а не на сервере:
	сервер двигал бы девять деталей каждый кадр по сети каждому ребёнку.
	Дальше трёхсот студов не крутим — там их всё равно не видно.
]]
HANDLERS.AF_Windmill = function(hub: BasePart)
	local blades = hub.Parent
	if not blades or not blades:IsA("Model") then
		return
	end
	local home = hub.CFrame
	local parts: { [BasePart]: CFrame } = {}
	for _, descendant in blades:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts[descendant] = home:ToObjectSpace(descendant.CFrame)
		end
	end
	local angle = math.random() * math.pi * 2
	local connection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if not hub.Parent then
			connection:Disconnect()
			return
		end
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - home.Position).Magnitude > 300 then
			return
		end
		angle += dt * 0.7
		local now = home * CFrame.Angles(0, 0, angle)
		for part, offset in parts do
			part.CFrame = now * offset
		end
	end)
end

function PlaygroundController.init()
	for tag, handler in HANDLERS do
		local function attach(instance: Instance)
			if instance:IsA("BasePart") then
				handler(instance)
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(attach)
		for _, instance in CollectionService:GetTagged(tag) do
			attach(instance)
		end
	end

	-- Детали, ушедшие из стриминга, не должны держать запись в таблице задержек.
	for tag in HANDLERS do
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
			cooldown[instance] = nil
		end)
	end
end

return PlaygroundController
