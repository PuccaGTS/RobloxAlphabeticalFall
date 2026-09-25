--!nonstrict
--[[
	Тир (Config/Playground.GALLERY, стенд строит PlaygroundService).

	На задней стене стенда сеткой висят шарики, на каждом буква. Встал на
	жёлтый круг у прилавка — голос называет букву, она крупно вверху экрана.
	Тап по шарику — из руки летит мяч. Нужный шарик лопается облаком конфетти,
	голос повторяет букву; от чужого мяч отскакивает, шарик качается, и голос
	называет нужную ещё раз. Долго не попадается — нужные шарики начинают сиять.

	Три нужных — «ура» и задание дня про тир (ParkReport). Звёзд здесь нет,
	как во всём парке. Шарики и мячи у каждого ребёнка свои: всё на клиенте.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Playground = require(Shared.Config.Playground)
local AudioRegistry = require(Shared.Config.AudioRegistry)

local AudioController = require(script.Parent.AudioController)
local EmoteController = require(script.Parent.EmoteController)
local ParkReport = require(script.Parent.ParkReport)
local HUD = require(script.Parent.Parent.UI.HUD)

local GalleryController = {}

local player = Players.LocalPlayer

local BALLOON_COLORS = {
	Color3.fromRGB(240, 80, 80),
	Color3.fromRGB(250, 170, 60),
	Color3.fromRGB(250, 215, 70),
	Color3.fromRGB(100, 200, 110),
	Color3.fromRGB(80, 170, 240),
	Color3.fromRGB(170, 110, 230),
	Color3.fromRGB(240, 120, 190),
}
local NEAR = 120
local ON_MARK = 2.8
local TAP_REACH = 80
local HINT_AFTER = 9
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

type Balloon = {
	model: Model,
	body: BasePart,
	glow: ParticleEmitter,
	home: CFrame,
	letterId: string,
	phase: number,
	popped: boolean,
	wobble: number, -- до какого момента качается после промаха
}

local wall: BasePart? = nil
local mark: BasePart? = nil
local balloons: { Balloon } = {}
local pool: { string } = {}
local active = false
local target: string? = nil
local hits = 0
local waitingSince = 0
local lastSaid = 0

local function playKey(key: string, at: Vector3, volume: number, speed: number?)
	local id = AudioRegistry.ids[key]
	if not id or id == "" then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Parent = workspace.Terrain
	holder.WorldPosition = at
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 80
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 5)
end

local function confetti(at: Vector3, colors: { Color3 }, count: number)
	local holder = Instance.new("Attachment")
	holder.Parent = workspace.Terrain
	holder.WorldPosition = at
	for _, color in colors do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = SPARKLES
		emitter.Color = ColorSequence.new(color)
		emitter.Size = NumberSequence.new(0.5, 0.1)
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(6, 12)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -20, 0)
		emitter.LightEmission = 0.6
		emitter.Rate = 0
		emitter.Parent = holder
		emitter:Emit(count)
	end
	Debris:AddItem(holder, 2)
end

-- Буквы для шариков: выученные и первая ступень — как у рыбалки.
function GalleryController.update(snapshot: any)
	local list: { string } = table.clone(Letters.byStage(1))
	if typeof(snapshot) == "table" and typeof(snapshot.mastery) == "table" then
		for _, id in Letters.ordered() do
			if (tonumber(snapshot.mastery[id]) or 0) >= 1 and not table.find(list, id) then
				table.insert(list, id)
			end
		end
	end
	if #list < 5 then
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

local function setLetter(balloon: Balloon, letterId: string)
	balloon.letterId = letterId
	local label = balloon.body:FindFirstChild("Letter", true)
	if label and label:IsA("TextLabel") then
		label.Text = Letters.expect(letterId).glyph
	end
end

local function buildBalloon(index: number, home: CFrame): Balloon
	local model = Instance.new("Model")
	model.Name = `GalleryBalloon_{index}`
	local color = BALLOON_COLORS[(index - 1) % #BALLOON_COLORS + 1]
	local function piece(name: string, size: Vector3, offset: CFrame, tint: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = home * offset
		p.Color = tint
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	local body = piece("Body", Vector3.new(2.1, 2.1, 2.1), CFrame.identity, color, Enum.PartType.Ball)
	body.Material = Enum.Material.Glass
	body.Reflectance = 0.1
	piece(
		"Shine",
		Vector3.new(0.45, 0.45, 0.45),
		CFrame.new(-0.45, 0.5, -0.8),
		Color3.new(1, 1, 1),
		Enum.PartType.Ball
	)
	piece("Knot", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, -1.1, 0), color, Enum.PartType.Ball)
	piece("String", Vector3.new(0.05, 1.3, 0.05), CFrame.new(0, -1.9, 0), Color3.fromRGB(240, 240, 240))
	model.PrimaryPart = body

	-- Буква «напечатана» на шарике: на передней грани, к прилавку. Билборд в середине шара прятался бы внутри.
	local billboard = Instance.new("SurfaceGui")
	billboard.Face = Enum.NormalId.Front
	billboard.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	billboard.PixelsPerStud = 45
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Parent = body
	local label = Instance.new("TextLabel")
	label.Name = "Letter"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(40, 40, 60)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	local glow = Instance.new("ParticleEmitter")
	glow.Texture = SPARKLES
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 235, 140))
	glow.Size = NumberSequence.new(0.6, 0)
	glow.Lifetime = NumberRange.new(0.6, 1)
	glow.Speed = NumberRange.new(1, 2)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.LightEmission = 1
	glow.Rate = 14
	glow.Enabled = false
	glow.Parent = body

	local balloon: Balloon = {
		model = model,
		body = body,
		glow = glow,
		home = home,
		letterId = "a",
		phase = index * 0.9,
		popped = false,
		wobble = 0,
	}
	setLetter(balloon, randomLetter(nil))
	model.Parent = workspace
	return balloon
end

local function buildWall()
	local stand = wall :: BasePart
	local spec = Playground.GALLERY
	-- Лицо стены смотрит к прилавку (−Z стенда), шарики висят в полутора студах перед ним.
	local face = stand.CFrame * CFrame.new(0, 0, -stand.Size.Z / 2 - 1.3)
	local index = 0
	for row = 1, spec.rows do
		for column = 1, spec.columns do
			index += 1
			local x = (column - (spec.columns + 1) / 2) * 2.9
			local y = -0.4 + (row - 1) * 2.5
			table.insert(balloons, buildBalloon(index, face * CFrame.new(x, y, 0)))
		end
	end
end

local function sayTarget()
	if target then
		lastSaid = os.clock()
		AudioController.speak(Letters.expect(target).vo.name)
	end
end

local function newTarget()
	target = randomLetter(target)
	waitingSince = os.clock()
	local has = false
	for _, balloon in balloons do
		balloon.glow.Enabled = false
		if balloon.letterId == target and not balloon.popped then
			has = true
		end
	end
	if not has then
		local free = {}
		for _, balloon in balloons do
			if not balloon.popped then
				table.insert(free, balloon)
			end
		end
		if #free > 0 then
			setLetter(free[math.random(1, #free)], target :: string)
		end
	end
	HUD.showTarget(Letters.expect(target :: string).glyph, hits, Playground.GALLERY.goal)
	sayTarget()
end

local function start()
	active = true
	hits = 0
	newTarget()
end

local function stop()
	active = false
	target = nil
	for _, balloon in balloons do
		balloon.glow.Enabled = false
	end
	HUD.showTarget(nil)
end

-- Мяч из руки по дуге; когда долетел — onArrive.
local function throwBall(to: Vector3, onArrive: () -> ())
	local character = player.Character
	local hand = character
		and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if hand then hand.Position elseif root then root.Position else to - Vector3.new(0, 0, 6)
	local ball = Instance.new("Part")
	ball.Name = "GalleryThrow"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.8, 0.8, 0.8)
	ball.Color = BALLOON_COLORS[math.random(1, #BALLOON_COLORS)]
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Position = from
	ball.Parent = workspace
	playKey("sfx_run_whoosh", from, 0.4, 1.4)
	EmoteController.play("point")
	local seconds = Playground.GALLERY.throw
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - started) / seconds, 0, 1)
		ball.Position = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 2.5, 0)
		if t >= 1 then
			connection:Disconnect()
			onArrive()
			-- Отскок вниз и прочь.
			local fall = os.clock()
			local drop
			drop = RunService.Heartbeat:Connect(function()
				local u = os.clock() - fall
				ball.Position = to + Vector3.new(0, 2 * u - 12 * u * u, -3 * u)
				if u > 0.8 then
					drop:Disconnect()
					ball:Destroy()
				end
			end)
		end
	end)
end

local function pop(balloon: Balloon)
	balloon.popped = true
	balloon.glow.Enabled = false
	local at = balloon.body.Position
	playKey("sfx_balloon_pop", at, 0.8)
	confetti(at, { balloon.body.Color, Color3.fromRGB(255, 230, 110), Color3.new(1, 1, 1) }, 14)
	balloon.model.Parent = nil
	task.delay(Playground.GALLERY.regrow, function()
		balloon.popped = false
		setLetter(balloon, randomLetter(target))
		balloon.model.Parent = workspace
	end)
end

local function onTap(screen: Vector2)
	local camera = workspace.CurrentCamera
	if not active or not target or not camera then
		return
	end
	local best, bestDistance = nil, TAP_REACH
	for _, balloon in balloons do
		if not balloon.popped then
			local point, visible = camera:WorldToViewportPoint(balloon.body.Position)
			if visible then
				local distance = (Vector2.new(point.X, point.Y) - screen).Magnitude
				if distance < bestDistance then
					best, bestDistance = balloon, distance
				end
			end
		end
	end
	if not best then
		return
	end
	local chosen = best :: Balloon
	local right = chosen.letterId == target
	if right then
		-- Засчитываем сразу: второй тап по тому же шарику, пока летит мяч, не нужен.
		chosen.popped = true
		hits += 1
	end
	throwBall(chosen.body.Position, function()
		if right then
			chosen.popped = false
			pop(chosen)
			AudioController.speak(Letters.expect(chosen.letterId).vo.name)
			HUD.showTarget(Letters.expect(chosen.letterId).glyph, hits, Playground.GALLERY.goal)
			if hits >= Playground.GALLERY.goal then
				hits = 0
				EmoteController.play("cheer")
				ParkReport.done("gallery")
				task.delay(1, HUD.toast, "🎯 Три шарика! Меткий стрелок!", 4)
			end
			task.delay(1, function()
				if active then
					newTarget()
				end
			end)
		else
			chosen.wobble = os.clock() + 1
			playKey("sfx_ball_bounce", chosen.body.Position, 0.7)
			if os.clock() - lastSaid > 1.5 then
				sayTarget()
			end
		end
	end)
end

local function step()
	if not wall or not mark or not wall.Parent then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local near = (root.Position - wall.Position).Magnitude < NEAR
	if #balloons == 0 and near then
		buildWall()
	end
	if not near then
		if active then
			stop()
		end
		return
	end

	local now = os.clock()
	for _, balloon in balloons do
		if not balloon.popped then
			local sway = math.sin(now * 1.3 + balloon.phase) * 0.25
			local bob = math.sin(now * 1.7 + balloon.phase * 2) * 0.2
			local shake = if balloon.wobble > now then math.sin(now * 30) * 0.3 else 0
			balloon.model:PivotTo(
				balloon.home * CFrame.new(sway + shake, bob, 0) * CFrame.Angles(0, 0, sway * 0.3)
			)
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
		for _, balloon in balloons do
			balloon.glow.Enabled = balloon.letterId == target and not balloon.popped
		end
	end
end

function GalleryController.init()
	GalleryController.update(nil)
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
	watchTag("AF_GalleryWall", function(part)
		wall = part
	end)
	watchTag("AF_GalleryMark", function(part)
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

-- Для стенда проверки.
function GalleryController.debug()
	local list = {}
	for _, balloon in balloons do
		table.insert(
			list,
			{ letterId = balloon.letterId, position = balloon.body.Position, popped = balloon.popped }
		)
	end
	return { active = active, target = target, hits = hits, balloons = list }
end

GalleryController.tap = onTap

return GalleryController
