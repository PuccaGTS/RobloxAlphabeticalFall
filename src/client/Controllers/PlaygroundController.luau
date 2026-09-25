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
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Playground = require(Shared.Config.Playground)

local AudioController = require(script.Parent.AudioController)
local EmoteController = require(script.Parent.EmoteController)
local ParkReport = require(script.Parent.ParkReport)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local Letters = require(Shared.Config.Letters)

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
local addSunflower: (Instance) -> ()
local stepSunflowers: (number) -> ()

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

--[[
	Кристалл в гроте: тронул — звенит своей нотой (волшебный перезвон, Pro Sound
	Effects), вспыхивает белым и медленно гаснет обратно в свой цвет, сыплет искры.
]]
HANDLERS.AF_Crystal = function(crystal: BasePart)
	local color = crystal.Color
	local size = crystal.Size
	crystal.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(crystal, 0.6) then
			return
		end
		local note = crystal:GetAttribute("Note") or 1
		local id = AudioRegistry.ids.sfx_crystal
		if id and id ~= "" then
			playSound(id, (Playground.NOTE_SPEEDS[note] or 1) * 0.9, 0.6, crystal)
		end
		crystal.Color = Color3.new(1, 1, 1)
		crystal.Size = size * 1.12
		TweenService
			:Create(crystal, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Color = color, Size = size })
			:Play()
		burst(crystal, color, 10)
		ParkReport.done("grotto")
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

--[[
	Фото-зона: встал на метку — персонаж поворачивается к «фотографу» и кричит
	«ура», экран вспыхивает, щёлкает затвор, из рамки сыплется конфетти,
	а камера пару секунд держит красивый кадр. Сам снимок делает Roblox
	(снимок экрана) — игра только ставит кадр и радуется вместе с ребёнком.
]]
local function flash()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PhotoFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	local white = Instance.new("Frame")
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 0.05
	white.Parent = gui
	local fade = TweenService:Create(white, TweenInfo.new(0.7), { BackgroundTransparency = 1 })
	fade.Completed:Connect(function()
		gui:Destroy()
	end)
	fade:Play()
end

HANDLERS.AF_PhotoMark = function(mark: BasePart)
	local CONFETTI = {
		Color3.fromRGB(240, 90, 90),
		Color3.fromRGB(250, 210, 80),
		Color3.fromRGB(120, 205, 110),
		Color3.fromRGB(80, 190, 220),
		Color3.fromRGB(230, 120, 190),
	}
	mark.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(mark, Playground.PHOTO_COOLDOWN) then
			return
		end
		local root = rootOf()
		local pose = mark:GetAttribute("Camera")
		local camera = workspace.CurrentCamera
		if not root or typeof(pose) ~= "CFrame" or not camera then
			return
		end
		-- Лицом к фотографу.
		root.CFrame =
			CFrame.lookAt(root.Position, Vector3.new(pose.Position.X, root.Position.Y, pose.Position.Z))
		EmoteController.play("cheer")
		ParkReport.done("photo")

		local previousType = camera.CameraType
		local previousFov = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = pose
		camera.FieldOfView = 55

		task.delay(0.5, function()
			local shutter = AudioRegistry.ids.sfx_camera_shutter
			if shutter and shutter ~= "" then
				playSound(shutter, 1, 0.8, mark)
			end
			flash()
			for _, color in CONFETTI do
				burst(mark, color, 14)
			end
		end)
		task.delay(Playground.PHOTO_POSE_SECONDS, function()
			camera.CameraType = previousType
			camera.FieldOfView = previousFov
		end)
	end)
end

-- Крупное число над клеткой: видно, на что наступил, даже пока голос молчит.
local function showNumber(tile: BasePart, number: number | string)
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

--[[
	Азбука-дорожка. Каждая плитка называет свою букву (не чаще раза в
	speakEvery: бегом по дорожке очередь из названий не копится). Цепочка —
	у ребёнка своя: шагнул на следующую по алфавиту — она загорается и
	остаётся гореть; шагнул на А — цепочка начинается заново. Дошёл до Я,
	не пропустив ни одной, — по дорожке бежит волна света, фанфары, искры.
]]
local abcTiles: { [number]: BasePart } = {}
local abcColors: { [BasePart]: Color3 } = {}
local abcNext = 1
local abcSpoke = 0
local abcParty = false

local function abcLight(tile: BasePart, lit: boolean)
	tile.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

local function abcReset()
	for _, tile in abcTiles do
		abcLight(tile, false)
		tile.Color = abcColors[tile] or tile.Color
	end
	abcNext = 1
end

local function abcCelebrate()
	abcParty = true
	ParkReport.done("abcpath")
	playSound(CHEER_SOUND, 1, 0.6, abcTiles[#abcTiles] or abcTiles[1])
	-- Волна от А до Я: каждая плитка вспыхивает белым и сыплет искры.
	for order = 1, #abcTiles do
		local tile = abcTiles[order]
		task.delay(order * 0.06, function()
			if tile.Parent then
				tile.Color = Color3.new(1, 1, 1)
				TweenService:Create(tile, TweenInfo.new(0.6), { Color = abcColors[tile] }):Play()
				burst(tile, abcColors[tile] or tile.Color, 6)
			end
		end)
	end
	task.delay(Playground.ABC.celebrate, function()
		abcParty = false
		abcReset()
	end)
end

HANDLERS.AF_AbcTile = function(tile: BasePart)
	local order = tile:GetAttribute("Order") or 1
	abcTiles[order] = tile
	abcColors[tile] = tile.Color
	tile.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(tile, 0.8) or abcParty then
			return
		end
		local id = tile:GetAttribute("Letter")
		local letter = id and Letters.get(id)
		if not letter then
			return
		end
		local now = os.clock()
		if now - abcSpoke >= Playground.ABC.speakEvery then
			abcSpoke = now
			AudioController.speak(letter.vo.name)
		end
		playSound(NOTE_SOUND, 0.7 + order * 0.025, 0.3, tile)
		showNumber(tile, letter.glyph)
		if order == 1 then
			abcReset()
		end
		if order == abcNext then
			abcLight(tile, true)
			abcNext += 1
			if abcNext > #abcTiles and #abcTiles >= 33 then
				abcCelebrate()
			end
		end
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
				-- Та же метка у флажка лабиринта и у колокола паркур-горы.
				ParkReport.done(ParkReport.spotOf(flag))
			end
		end
	end)
end

--[[
	Крылья мельниц в парке (DecorShapes.windmill). Крутятся здесь, а не на сервере:
	сервер двигал бы девять деталей каждый кадр по сети каждому ребёнку.
	Дальше трёхсот студов не крутим — там их всё равно не видно.
	Тем же крутятся колесо обозрения и пропеллер самолётика во дворе: у них
	своя скорость в атрибуте Speed.
]]
HANDLERS.AF_Windmill = function(hub: BasePart)
	local blades = hub.Parent
	if not blades or not blades:IsA("Model") then
		return
	end
	local speed = hub:GetAttribute("Speed") or 0.7
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
		angle += dt * speed
		local now = home * CFrame.Angles(0, 0, angle)
		for part, offset in parts do
			part.CFrame = now * offset
		end
	end)
end

--[[
	Двигает всю группу деталей, в которой лежит метка, каждый кадр по формуле.
	Смещения деталей запоминаются от их места на сервере, поэтому группа
	не «уплывает» и после перестройки участка начинает с чистого листа.
]]
local ANIMATE_DISTANCE = 250

local function animateGroup(anchor: BasePart, frameAt: (number) -> CFrame)
	local group = anchor.Parent
	if not group or not group:IsA("Model") then
		return
	end
	local home = CFrame.new(anchor.Position)
	local parts: { [BasePart]: CFrame } = {}
	for _, descendant in group:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts[descendant] = home:ToObjectSpace(descendant.CFrame)
		end
	end
	local clock = math.random() * 10
	local connection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if not anchor.Parent then
			connection:Disconnect()
			return
		end
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - home.Position).Magnitude > ANIMATE_DISTANCE then
			return
		end
		clock += dt
		local now = home * frameAt(clock)
		for part, offset in parts do
			part.CFrame = now * offset
		end
	end)
end

-- Карусель во дворе, утки в пруду: крутятся вокруг вертикали метки.
HANDLERS.AF_Spin = function(anchor: BasePart)
	local speed = anchor:GetAttribute("Speed") or 0.5
	animateGroup(anchor, function(t: number)
		return CFrame.Angles(0, t * speed, 0)
	end)
end

--[[
	Огоньки гирлянды на ёлке зимней полянки: мигают вразнобой. Один общий
	цикл на все огоньки, а не по циклу на каждый, и только когда ёлку видно.
]]
local twinkles: { BasePart } = {}
local twinkleClock = 0
HANDLERS.AF_Twinkle = function(light: BasePart)
	table.insert(twinkles, light)
	if #twinkles > 1 then
		return
	end
	RunService.Heartbeat:Connect(function(dt: number)
		twinkleClock += dt
		local camera = workspace.CurrentCamera
		for index = #twinkles, 1, -1 do
			local bulb = twinkles[index]
			if not bulb.Parent then
				table.remove(twinkles, index)
			elseif camera and (camera.CFrame.Position - bulb.Position).Magnitude < ANIMATE_DISTANCE then
				bulb.Transparency = 0.5 - 0.5 * math.max(0, math.sin(twinkleClock * 2.6 + index * 1.7))
			end
		end
	end)
end

--[[
	Подсолнухи на поле у озера смотрят на ребёнка, пока он рядом, а без
	него — на солнце. Голову поворачивают не рывком, а с угловой скоростью
	SUNFLOWER_TURN: видно, как всё поле медленно оборачивается следом.
]]
type Sunflower = { model: Model, pivot: CFrame, parts: { BasePart }, offsets: { CFrame }, facing: Vector3 }
local sunflowers: { Sunflower } = {}
local sunFrames: { CFrame } = {}

function addSunflower(instance: Instance)
	local pivot = instance:GetAttribute("Pivot")
	if not instance:IsA("Model") or typeof(pivot) ~= "CFrame" then
		return
	end
	local parts, offsets = {}, {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			table.insert(offsets, pivot:ToObjectSpace(descendant.CFrame))
		end
	end
	table.insert(
		sunflowers,
		{ model = instance, pivot = pivot, parts = parts, offsets = offsets, facing = pivot.LookVector }
	)
end

function stepSunflowers(dt: number)
	if #sunflowers == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local root = rootOf()
	local sun = Lighting:GetSunDirection()
	for index = #sunflowers, 1, -1 do
		local flower = sunflowers[index]
		if not flower.model.Parent then
			table.remove(sunflowers, index)
			continue
		end
		local at = flower.pivot.Position
		if not camera or (camera.CFrame.Position - at).Magnitude > ANIMATE_DISTANCE then
			continue
		end
		local target = sun
		if root and (root.Position - at).Magnitude < Playground.SUNFLOWER_WATCH then
			target = root.Position + Vector3.new(0, 1.5, 0) - at
		end
		-- Голову не задирают к зениту и не роняют к земле.
		local flat = target * Vector3.new(1, 0, 1)
		if flat.Magnitude < 0.05 then
			flat = flower.facing * Vector3.new(1, 0, 1)
		end
		local lift = math.clamp(target.Unit.Y, -0.45, 0.55)
		target = flat.Unit * math.sqrt(1 - lift * lift) + Vector3.new(0, lift, 0)
		local angle = math.acos(math.clamp(flower.facing:Dot(target), -1, 1))
		if angle > 0.002 then
			local share = math.min(1, Playground.SUNFLOWER_TURN * dt / angle)
			flower.facing = flower.facing:Lerp(target, share).Unit
		end
		local frame = CFrame.lookAt(at, at + flower.facing)
		table.clear(sunFrames)
		for i, offset in flower.offsets do
			sunFrames[i] = frame * offset
		end
		workspace:BulkMoveTo(flower.parts, sunFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

--[[
	Бобовый стебель (Config/Playground, beanstalk). Гнездо на середине — сохранка:
	коснулся — флажок позеленел; сорвался, забравшись выше гнезда, — вернулся
	в гнездо, как к флажку в забеге. Спрыгнул с самого гнезда — значит, слезаешь:
	сохранка снимается. Долез до острова — ура и искры, сохранка больше не нужна,
	вниз — просто прыжком. У каждого ребёнка своя сохранка, сеть не нужна.
]]
local NEST_RED = Color3.fromRGB(240, 90, 100)
local NEST_GREEN = Color3.fromRGB(110, 215, 125)
local beanNest: BasePart? = nil
local beanPeak = 0

local function nestFlag(nest: BasePart, color: Color3)
	local flag = nest.Parent and nest.Parent:FindFirstChild("NestFlag")
	if flag and flag:IsA("BasePart") then
		flag.Color = color
	end
end

local function dropNest()
	if beanNest then
		nestFlag(beanNest, NEST_RED)
	end
	beanNest = nil
end

HANDLERS.AF_BeanNest = function(nest: BasePart)
	nest.Touched:Connect(function(hit)
		if not isMine(hit) then
			return
		end
		if beanNest ~= nest then
			beanNest = nest
			nestFlag(nest, NEST_GREEN)
			burst(nest, NEST_GREEN, 20)
			playSound(NOTE_SOUND, 1.5, 0.5, nest)
		end
		local root = rootOf()
		beanPeak = if root then root.Position.Y else nest.Position.Y
	end)
end

local function watchBeanFall()
	local nest = beanNest
	if not nest then
		return
	end
	local root = rootOf()
	local axis = nest:GetAttribute("Axis")
	local ground = nest:GetAttribute("Ground")
	if not root or not nest.Parent or typeof(axis) ~= "Vector3" or typeof(ground) ~= "number" then
		dropNest()
		return
	end
	local position = root.Position
	beanPeak = math.max(beanPeak, position.Y)
	local flat = ((position - axis) * Vector3.new(1, 0, 1)).Magnitude
	if flat > 60 then
		dropNest()
		return
	end
	if position.Y < ground + 5 and flat < 30 then
		if beanPeak > nest.Position.Y + 3.5 then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(nest.Position + Vector3.new(0, 3.5, 0)) * root.CFrame.Rotation
			beanPeak = nest.Position.Y
			burst(nest, NEST_GREEN, 16)
		else
			dropNest()
		end
	end
end

--[[
	Стручок-батут: подбрасывает к листу, до которого не допрыгнуть. Толчок как
	у батутов забега (RunHazardController): простую скорость персонаж гасит за
	кадр, поэтому — свободный полёт и десятая доля секунды LinearVelocity вверх.
]]
HANDLERS.AF_BeanPod = function(pod: BasePart)
	local home = pod.CFrame
	pod.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(pod, 0.5) then
			return
		end
		local root = rootOf()
		local humanoid = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			return
		end
		local power = pod:GetAttribute("Power") or Playground.BEAN_POD_POWER
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local push = Instance.new("LinearVelocity")
		push.Attachment0 = attachment
		push.RelativeTo = Enum.ActuatorRelativeTo.World
		push.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		push.LineDirection = Vector3.yAxis
		push.LineVelocity = power
		push.MaxForce = 1e6
		push.Parent = root
		task.delay(Playground.BEAN_POD_HOLD, function()
			push:Destroy()
			attachment:Destroy()
		end)
		playSound(BOUNCE_SOUND, 0.7, 0.6, pod)
		burst(pod, Color3.fromRGB(255, 230, 110), 12)
		pod.CFrame = home * CFrame.new(0, -0.3, 0)
		TweenService:Create(pod, TweenInfo.new(0.4, Enum.EasingStyle.Elastic), { CFrame = home }):Play()
	end)
end

HANDLERS.AF_BeanTop = function(island: BasePart)
	island.Touched:Connect(function(hit)
		if not isMine(hit) or not ready(island, 20) then
			return
		end
		dropNest()
		ParkReport.done("beanstalk")
		burst(island, Color3.fromRGB(255, 220, 110), 40)
		local magic = AudioRegistry.ids.sfx_magic
		if magic and magic ~= "" then
			playSound(magic, 1, 0.7, island)
		end
		EmoteController.play("cheer")
	end)
end

-- Воздушный шар на привязи: плавно вверх и вниз.
HANDLERS.AF_Float = function(anchor: BasePart)
	local amplitude = anchor:GetAttribute("Amplitude") or 0.5
	local period = anchor:GetAttribute("Period") or 3
	animateGroup(anchor, function(t: number)
		return CFrame.new(0, math.sin(t / period * math.pi * 2) * amplitude, 0)
	end)
end

function PlaygroundController.init()
	-- Подсолнухи — модели, а не детали: у них свой цикл.
	CollectionService:GetInstanceAddedSignal("AF_Sunflower"):Connect(addSunflower)
	for _, instance in CollectionService:GetTagged("AF_Sunflower") do
		addSunflower(instance)
	end
	RunService.Heartbeat:Connect(stepSunflowers)
	RunService.Heartbeat:Connect(watchBeanFall)

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
