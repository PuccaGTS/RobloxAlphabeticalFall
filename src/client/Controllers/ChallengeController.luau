--!nonstrict
--[[
	Клиентская часть испытаний: рисует то, что прислал сервер, и отправляет тапы.

	Клиент НИЧЕГО не решает: он не знает, верна ли буква, пока сервер не ответит.
	Буквы падают без физики — анкоренные части двигаются по времени (docs/07-TECH-ARCH.md § 8).

	Серый ящик: формы простые, но тайминги, попадания и обратная связь настоящие.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Stages = require(Shared.Config.Stages)
local MathLevels = require(Shared.Config.MathLevels)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local AudioController = require(script.Parent.AudioController)
local SfxController = require(script.Parent.SfxController)
local LadderController = require(script.Parent.LadderController)
local BubblesController = require(script.Parent.BubblesController)
local MirrorController = require(script.Parent.MirrorController)
local Props = require(script.Parent.Parent.UI.Props)
local LiveWorldController = require(script.Parent.LiveWorldController)
local ScalesController = require(script.Parent.ScalesController)
local BerryController = require(script.Parent.BerryController)
local LavaController = require(script.Parent.LavaController)
local PetController = require(script.Parent.PetController)
local HUD = require(script.Parent.Parent.UI.HUD)
local ResultScreen = require(script.Parent.Parent.UI.ResultScreen)
local Glyph = require(script.Parent.Parent.UI.Glyph)

local ChallengeController = {}

--[[
	Поле Буквопада. Раньше буквы падали в плоскости перед лицом, по ним надо было
	щёлкать, а ребёнок стоял на месте, — на первой проверке это назвали скучным.

	Теперь буквы-шарики падают из облака на поле в пять дорожек и три ряда.
	Под каждой падающей буквой растёт тень: видно, куда она упадёт. Ребёнок бежит
	туда и ловит свою букву телом, у самой травы, а чужие обегает. Щелчок
	по букве по-прежнему работает — на планшете бегать умеют не все.
]]
local LANE_WIDTH = 7
local ROW_DEPTH = 7
local LETTER_SIZE = Vector3.new(4.6, 4.6, 4.6)
local LETTER_REST = 2.4 -- высота центра буквы, лежащей на траве
local CATCH_HEIGHT = 6 -- выше этого буква ещё в воздухе и ногами не ловится
local CATCH_DISTANCE = 4.5
local FOLDER_NAME = "AlphabetFall_Challenge"

local FIELD_STRIPES = {
	Color3.fromRGB(250, 205, 215),
	Color3.fromRGB(255, 230, 170),
	Color3.fromRGB(200, 235, 190),
	Color3.fromRGB(190, 220, 250),
	Color3.fromRGB(225, 205, 245),
}

local player = Players.LocalPlayer

local spec: any = nil
local startedAt = 0
local folder: Folder? = nil
local parts: { [number]: BasePart } = {}
local spawned: { [number]: boolean } = {}
local shadows: { [number]: BasePart } = {}
-- Буквы, по которым ход уже ушёл на сервер: второй раз не отправляем.
local sent: { [number]: boolean } = {}
local origin: CFrame = CFrame.new()
local heartbeat: RBXScriptConnection? = nil
-- Пока «сачок опущен» после промаха, тапы не уходят на сервер и буквы притушены.
local blockedUntil = 0
local wasBlocked = false
local activeChallengeId: string? = nil
-- Буква-цель отдельно от spec: у туннеля геометрию строит сервер, и spec на клиенте
-- не хранится, но HUD всё равно должен показывать, что искать.
local activeTargetGlyph: string? = nil
-- Какое испытание закончилось последним: его и запускает кнопка «Ещё раз».
local lastEndedId: string? = nil

local function cleanup()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	parts = {}
	spawned = {}
	shadows = {}
	sent = {}
	spec = nil
	blockedUntil = 0
	wasBlocked = false
	HUD.showTarget(nil)
	HUD.setBlocked(false)
end

--[[
	Откуда падают буквы. Если на уровне есть площадка ChallengeArea — берём её,
	иначе строим область перед игроком, чтобы серый ящик работал на пустой карте.
]]
--[[
	Где разворачивать сцену. Сервер присылает точку своей поляны в самом задании
	(Config/Venues): одно задание — одна локация, и сцена больше не растёт
	посреди площади, где её закрывали порталы и чужие пады.

	Если поляны нет (старое задание, забег), остаётся прежний путь — «перед
	ребёнком там, где он стоит».
]]
local function stageOf(from: any): CFrame?
	local stage = from and from.params and from.params.stage
	return if typeof(stage) == "CFrame" then stage else nil
end

local function resolveOrigin(from: any): CFrame
	local stage = stageOf(from)
	if stage then
		-- Поле в центре поляны, чуть ближе к ребёнку: до дальнего ряда недалеко бежать.
		return stage * CFrame.new(0, 0, 4)
	end

	local area = workspace:FindFirstChild("ChallengeArea")
	if area and area:IsA("BasePart") then
		return area.CFrame
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		-- Только направление взгляда, без наклона: иначе площадка «падения» кренится
		-- вместе с камерой и буквы улетают вбок.
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		end
		local base = root.Position + flat.Unit * 18 - Vector3.new(0, 2, 0)
		return CFrame.lookAt(base, base + flat.Unit)
	end

	return CFrame.new(0, 0, 0)
end

-- Поле: полосы-дорожки, облако, из которого падают буквы, и большое табло с целью.
local function buildBackdrop(parent: Instance, height: number)
	local lanes = 5

	for lane = 1, lanes do
		local stripe = Instance.new("Part")
		stripe.Name = `FieldStripe_{lane}`
		stripe.Size = Vector3.new(LANE_WIDTH - 0.6, 0.2, ROW_DEPTH * 3 + 4)
		stripe.CFrame = origin * CFrame.new((lane - (lanes + 1) / 2) * LANE_WIDTH, 0.1, 0)
		stripe.Color = FIELD_STRIPES[(lane - 1) % #FIELD_STRIPES + 1]
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.CanQuery = false
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Parent = parent
	end

	-- Облако: из него и сыплются буквы, поэтому оно над всем полем.
	local random = Random.new(7)
	for puff = 1, 14 do
		local cloud = Instance.new("Part")
		cloud.Name = `Cloud_{puff}`
		cloud.Shape = Enum.PartType.Ball
		local size = 7 + random:NextNumber() * 6
		cloud.Size = Vector3.new(size, size, size)
		cloud.CFrame = origin
			* CFrame.new(
				(random:NextNumber() - 0.5) * LANE_WIDTH * 5.5,
				height + 3 + random:NextNumber() * 3,
				(random:NextNumber() - 0.5) * ROW_DEPTH * 3.5
			)
		cloud.Color = Color3.fromRGB(250, 252, 255)
		cloud.Transparency = 0.1
		cloud.Anchored = true
		cloud.CanCollide = false
		cloud.CanQuery = false
		cloud.Material = Enum.Material.SmoothPlastic
		cloud.Parent = parent
	end

	--[[
		Табло за полем: буква-цель крупно. Ребёнок бегает, смотрит под ноги
		и забывает, что ловит, — табло напоминает, куда ни повернись.
	]]
	local board = Props.framedPanel(
		parent,
		"TargetBoard",
		Vector3.new(11, 11, 0.8),
		origin * CFrame.new(0, 9.5, -(ROW_DEPTH * 1.5 + 9)),
		Color3.fromRGB(255, 250, 235),
		Color3.fromRGB(150, 105, 70),
		1,
		3
	)
	-- Табло не темнеет в тени: оно смотрит на ребёнка, а солнце за спиной у табло.
	board.Material = Enum.Material.Neon
	board.Color = Color3.fromRGB(205, 200, 190)
	if spec then
		local target = Letters.expect(spec.params.targetLetter)
		Glyph.attach(board, target.glyph, 0.9, target.color)
	end
end

local function laneOffset(lane: number, lanes: number): number
	return (lane - (lanes + 1) / 2) * LANE_WIDTH
end

-- Ряд, в который падает буква: из номера, чтобы место было одинаковым у всех кадров.
local function rowOffset(index: number): number
	return ((index * 7) % 3 - 1) * ROW_DEPTH
end

local function makeLetterPart(item: any): BasePart
	local letter = Letters.expect(item.letterId)

	local part = Instance.new("Part")
	part.Name = `Letter_{item.index}`
	part.Shape = Enum.PartType.Ball
	part.Size = LETTER_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.Color = letter.color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	-- Буква всегда развёрнута к ребёнку: узнавать её со спины невозможно
	Glyph.attach(part, letter.glyph, 0.95)

	-- ClickDetector сам работает и мышью, и тапом — отдельный код для тача не нужен.
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 200
	click.Parent = part

	click.MouseClick:Connect(function()
		if not spec or sent[item.index] then
			return
		end
		-- Пока идёт пауза после промаха, тапы не отправляем: сервер их всё равно
		-- не примет, а ребёнку важно услышать подсказку, а не «дотыкать» вслепую.
		if os.clock() < blockedUntil then
			return
		end
		sent[item.index] = true
		RemoteDefs.event("ChallengeAction"):FireServer({ itemIndex = item.index })
	end)

	return part
end

-- Тень на траве: растёт и темнеет, пока буква приближается к земле.
local function makeShadow(item: any, lanes: number): BasePart
	local shadow = Instance.new("Part")
	shadow.Name = `Shadow_{item.index}`
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.1, 1, 1)
	shadow.CFrame = origin
		* CFrame.new(laneOffset(item.lane, lanes), 0.25, -rowOffset(item.index))
		* CFrame.Angles(0, 0, math.rad(90))
	shadow.Color = Color3.fromRGB(40, 40, 60)
	shadow.Transparency = 0.7
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.Material = Enum.Material.SmoothPlastic
	return shadow
end

local function popPart(part: BasePart, success: boolean)
	local goalSize = if success then part.Size * 1.6 else part.Size * 0.6
	local tween = TweenService:Create(
		part,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = goalSize, Transparency = 1 }
	)
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	tween:Play()

	if success then
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Rate = 0
		burst.Speed = NumberRange.new(8, 14)
		burst.Lifetime = NumberRange.new(0.5, 0.9)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Color = ColorSequence.new(part.Color)
		burst.Parent = part
		burst:Emit(24)
	end
end

local function dropShadow(index: number)
	local shadow = shadows[index]
	if shadow then
		shadows[index] = nil
		shadow:Destroy()
	end
end

local function onHeartbeat()
	if not spec or not folder then
		return
	end

	local now = os.clock()
	local elapsed = now - startedAt
	local params = spec.params
	local blocked = now < blockedUntil
	local restTime = params.restTime or 0

	for _, item in params.items do
		if not spawned[item.index] and elapsed >= item.spawnAt then
			spawned[item.index] = true
			local part = makeLetterPart(item)
			part.Parent = folder
			parts[item.index] = part
			local shadow = makeShadow(item, params.lanes)
			shadow.Parent = folder
			shadows[item.index] = shadow
		end
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	for index, part in parts do
		local item = params.items[index]
		local age = elapsed - item.spawnAt
		local fallen = age * params.fallSpeed
		local height = params.fallHeight - fallen

		if age > params.flightTime + restTime then
			-- Никто не поймал: буква тает на траве, а не проваливается сквозь неё.
			parts[index] = nil
			dropShadow(index)
			TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			task.delay(0.3, function()
				part:Destroy()
			end)
		else
			local landed = height <= LETTER_REST
			if landed then
				-- На траве буква подпрыгивает: живая, её хочется поймать.
				local since = age - params.flightTime
				height = LETTER_REST + math.abs(math.sin(since * 5)) * 1.2 * math.max(0, 1 - since / 3)
			end

			local x = laneOffset(item.lane, params.lanes)
			local z = -rowOffset(index)
			part.CFrame = origin * CFrame.new(x, height, z) * CFrame.Angles(0, elapsed * 1.5 + index, 0)

			local shadow = shadows[index]
			if shadow then
				local closeness = math.clamp(1 - (height - LETTER_REST) / params.fallHeight, 0.2, 1)
				shadow.Size = Vector3.new(0.1, 4.6 * closeness, 4.6 * closeness)
				shadow.Transparency = 0.85 - 0.35 * closeness
			end

			-- Пауза после промаха видна глазами: буквы притушены и не ловятся.
			part.Transparency = if blocked then 0.65 else 0
			Glyph.setTransparency(part, if blocked then 0.7 else 0)

			--[[
				Ловля телом: буква у земли, ребёнок рядом — ход отправлен.
				Высоко в воздухе буква не ловится, иначе стоящего на месте
				«ловило» бы всё, что падает ему на голову.
			]]
			if
				root
				and root:IsA("BasePart")
				and not blocked
				and not sent[index]
				and height <= CATCH_HEIGHT
				and (root.Position - part.Position).Magnitude <= CATCH_DISTANCE
			then
				sent[index] = true
				RemoteDefs.event("ChallengeAction"):FireServer({ itemIndex = index })
				-- Сервер мог не принять (пауза, опоздание): через секунду можно снова.
				task.delay(1.2, function()
					if parts[index] then
						sent[index] = nil
					end
				end)
			end
		end
	end

	if blocked ~= wasBlocked then
		wasBlocked = blocked
		HUD.setBlocked(blocked)
	end
end

--[[
	Знакомство с новой буквой: крупная буква на экране, пока звучит
	«Это буква М, она говорит м-м-м». Один раз за всю игру на каждую букву.
]]
local function announceIntro(incoming: any)
	local glyph = incoming.params and incoming.params.introGlyph
	if not glyph then
		return
	end
	HUD.showIntro(glyph)
end

local function stopControllers()
	LadderController.stop()
	BubblesController.stop()
	MirrorController.stop()
	ScalesController.stop()
	BerryController.stop()
	LavaController.stop()
end

--[[
	Переход между миром и испытанием. Раньше экран с падающими буквами возникал
	мгновенно поверх площади, и ребёнок не понимал, куда делась игра.

	Шторка гасит картинку за четверть секунды, под ней строится новый экран,
	и через полсекунды она уходит. Это не украшение: резкая смена кадра —
	то, на чём дошкольник теряет нить происходящего.
]]
-- Искры вокруг ребёнка, когда он появился на новом месте.
local function arrivalSparkles()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140), Color3.fromRGB(180, 140, 255))
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(4, 9)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Parent = root
	emitter:Emit(35)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end

local function fadeThrough()
	local parent = player:FindFirstChildOfClass("PlayerGui")
	if not parent then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ChallengeFade"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.ResetOnSpawn = false
	gui.Parent = parent

	local veil = Instance.new("Frame")
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.fromRGB(28, 24, 44)
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.Parent = gui

	-- Звёздочки на затемнении: переход читается как «волшебно перенёсся», а не как мигание.
	for index = 1, 12 do
		local star = Instance.new("TextLabel")
		star.BackgroundTransparency = 1
		star.Text = if index % 3 == 0 then "✨" else "⭐"
		star.TextScaled = true
		star.TextTransparency = 1
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Size = UDim2.fromScale(0.05, 0.08)
		local angle = index / 12 * math.pi * 2
		star.Position = UDim2.fromScale(0.5, 0.5)
		star.Parent = veil
		TweenService:Create(star, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
			Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.32, 0.5 + math.sin(angle) * 0.36),
			TextTransparency = 0,
			Rotation = 90,
		}):Play()
	end
	SfxController.play("whoosh")

	TweenService:Create(veil, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
	task.delay(0.45, function()
		TweenService:Create(veil, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		for _, star in veil:GetChildren() do
			if star:IsA("TextLabel") then
				TweenService:Create(star, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			end
		end
		arrivalSparkles()
		task.delay(0.4, function()
			gui:Destroy()
		end)
	end)
end

local function onSpec(newSpec: any)
	fadeThrough()
	cleanup()
	stopControllers()
	announceIntro(newSpec)

	-- Каждое испытание рисуется своим модулем: общего у них только сеть и HUD.
	if newSpec.challengeId == "alphabet_ladder" then
		activeChallengeId = newSpec.challengeId
		LadderController.start(newSpec)
		return
	end
	if newSpec.challengeId == "bubbles" then
		activeChallengeId = newSpec.challengeId
		BubblesController.start(newSpec)
		return
	end
	if newSpec.challengeId == "mirror" then
		activeChallengeId = newSpec.challengeId
		MirrorController.start(newSpec)
		return
	end
	if newSpec.challengeId == "scales" then
		activeChallengeId = newSpec.challengeId
		ScalesController.start(newSpec)
		return
	end
	if newSpec.challengeId == "berries" then
		activeChallengeId = newSpec.challengeId
		BerryController.start(newSpec)
		return
	end
	if newSpec.challengeId == "lava_floor" then
		activeChallengeId = newSpec.challengeId
		LavaController.start(newSpec)
		return
	end

	--[[
		Забеги рисует сервер: ворота, стены и препятствия — настоящая геометрия мира,
		а не клиентские декорации. Клиенту остаётся только показать, что искать.
	]]
	if newSpec.challengeId == "tunnel_run" then
		activeChallengeId = newSpec.challengeId
		activeTargetGlyph = newSpec.params.targetGlyph
		HUD.showTarget(newSpec.params.targetGlyph, 0, newSpec.targetCount)
		-- Где есть станции, букву отрезка называет станция: беги к ней.
		if #(newSpec.params.stations or {}) > 0 then
			HUD.toast(`Беги к большой букве {newSpec.params.targetGlyph}!`, 4)
			return
		end
		HUD.toast(`Беги в ворота с буквой {newSpec.params.targetGlyph}`, 4)
		task.delay(0.6, function()
			AudioController.speak(newSpec.params.targetVO)
		end)
		return
	end

	--[[
		Ворота с числами. На HUD только пример («2 + 2»), и то не всегда: у задания
		«беги на цифру три» показывать нечего вовсе. Ответ ребёнок обязан услышать
		и посчитать — напиши мы его сверху, и задание свелось бы к поиску такой же
		картинки, а считать стало бы незачем.

		Задачу произносит сервер: она меняется у каждых ворот, и клиент о смене
		узнаёт только из обратной связи.
	]]
	if newSpec.challengeId == "math_gates" then
		activeChallengeId = newSpec.challengeId
		activeTargetGlyph = nil
		local prompt = newSpec.params.taskPrompt
		HUD.showTarget(if prompt ~= "" then prompt else nil, 0, newSpec.targetCount)
		HUD.toast("Слушай задание и беги в нужные ворота", 4)
		return
	end

	activeChallengeId = newSpec.challengeId
	spec = newSpec
	startedAt = os.clock()
	origin = resolveOrigin(newSpec)

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	buildBackdrop(container, spec.params.fallHeight)
	HUD.showTarget(spec.params.targetGlyph, 0, spec.targetCount)
	-- Пока нет озвучки, задание должно быть сказано хотя бы текстом,
	-- иначе непонятно, что вообще происходит и что от тебя хотят.
	HUD.toast(`Беги и лови букву {spec.params.targetGlyph}! Смотри на тени`, 4)

	-- Звук буквы-цели: сначала ребёнок слышит, что ловить, и только потом видит текст.
	task.delay(0.6, function()
		if spec then
			AudioController.speak(spec.params.targetVO)
		end
	end)

	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
end

--[[
	Звук ответа. Играет раньше любой реплики и не ждёт её: ребёнок должен понять,
	что ход засчитан, в тот же миг, когда коснулся ворот, — иначе он тычет ещё раз.

	Промах звучит нейтрально и тихо: ошибка стоит времени, а не самооценки.
]]
local function feedbackSound(correct: boolean)
	SfxController.play(if correct then "correct" else "miss")
end

local function onFeedback(feedback: any)
	feedbackSound(feedback.correct == true)
	-- Буквята радуются верному ответу хозяина: прыжок с оборотом и искры.
	if feedback.correct then
		PetController.cheer()
	end

	if activeChallengeId == "alphabet_ladder" then
		-- букву-цель для следующей ступени выставит сама лестница
		LadderController.feedback(feedback)
		return
	end
	if activeChallengeId == "bubbles" then
		BubblesController.feedback(feedback)
		return
	end
	if activeChallengeId == "mirror" then
		MirrorController.feedback(feedback)
		return
	end
	if activeChallengeId == "scales" then
		ScalesController.feedback(feedback)
		return
	end
	if activeChallengeId == "berries" then
		BerryController.feedback(feedback)
		return
	end
	if activeChallengeId == "lava_floor" then
		LavaController.feedback(feedback)
		return
	end

	if activeChallengeId == "math_gates" then
		local prompt = feedback.nextPrompt
		HUD.showTarget(if prompt and prompt ~= "" then prompt else nil, feedback.caught, feedback.targetCount)
		--[[
			Промах: называем число, в ворота с которым ребёнок вбежал. Дальше сервер
			повторит задачу целиком — «это четыре, а нам нужно пять» складывается
			из двух реплик и не требует ни одной новой записи.
		]]
		if not feedback.correct and feedback.tappedValue then
			AudioController.speak(`num_{feedback.tappedValue}`)
		end
		return
	end

	if activeChallengeId == "tunnel_run" then
		if not feedback.correct and feedback.tappedLetterId then
			local tapped = Letters.get(feedback.tappedLetterId)
			if tapped then
				AudioController.speak(tapped.vo.name)
			end
		end

		--[[
			Уровень перешёл на новую букву: следующий отрезок ищет её. Название
			произносит сервер сразу за похвалой, здесь только экран — и знакомство,
			если с этой буквой ребёнок встречается впервые.
		]]
		if feedback.nextGlyph then
			activeTargetGlyph = feedback.nextGlyph
			if feedback.introGlyph then
				HUD.showIntro(feedback.introGlyph)
			end
			HUD.toast(`Теперь беги в ворота с буквой {feedback.nextGlyph}`, 4)
		end
		HUD.showTarget(activeTargetGlyph, feedback.caught, feedback.targetCount)
		return
	end

	local part = parts[feedback.itemIndex]
	if part then
		parts[feedback.itemIndex] = nil
		dropShadow(feedback.itemIndex)
		popPart(part, feedback.correct)
	end

	HUD.showTarget(spec and spec.params.targetGlyph or nil, feedback.caught, feedback.targetCount)

	if not feedback.correct and (feedback.cooldown or 0) > 0 then
		blockedUntil = os.clock() + feedback.cooldown
	end

	-- Промах: называем букву, по которой ребёнок попал, потом снова цель.
	-- «Это буква П. А нам нужна М» — так ошибка становится подсказкой, а не наказанием.
	if not feedback.correct and feedback.tappedLetterId then
		local tapped = Letters.get(feedback.tappedLetterId)
		if tapped then
			task.delay(0.5, function()
				AudioController.speak(tapped.vo.name)
				task.wait(0.7)
				if spec then
					AudioController.speak(spec.params.targetVO)
				end
			end)
		end
	end
end

local function onEnd(result: any)
	-- Обратно на площадь тоже переносит сервер: тот же переход, что и туда.
	fadeThrough()
	cleanup()
	stopControllers()
	activeChallengeId = nil
	activeTargetGlyph = nil
	lastEndedId = result.challengeId

	--[[
		Финиш звучит всегда, награда — только если она была. Молчаливый конец
		испытания читается как «ничего не произошло», а именно в этот момент
		ребёнок ждёт, что его похвалят.
	]]
	SfxController.play("finish")
	if (result.stars_awarded or 0) > 0 then
		task.delay(0.5, function()
			SfxController.play("reward")
		end)
	end

	--[[
		Пройденный уровень называется по имени ступени: «Первые три пройдены».
		Ребёнок прочитать это не сможет, а вот родитель рядом — сможет, и именно
		ему важно видеть, что путь продвинулся.
	]]
	local stage = if result.levelCleared then Stages.get(result.levelCleared) else nil
	local mathLevel = if result.mathLevelCleared then MathLevels.get(result.mathLevelCleared) else nil
	local cleared = if stage
		then `Уровень «{stage.title}» пройден!`
		elseif mathLevel then `Уровень «{mathLevel.title}» пройден!`
		else nil

	-- Нажал 🏠 посреди испытания — он уже ушёл, и итог ему показывать незачем.
	if result.reason ~= "aborted" then
		ResultScreen.show(result.stars or 1, result.stars_awarded or 0, cleared)
		-- Три звезды — над парком радуга: вернёшься на площадь и увидишь.
		if result.stars == 3 then
			LiveWorldController.rainbow()
		end
	end
	print(
		string.format(
			"[Challenge] итог: %d звезды, поймано %d из %d, +%d ⭐",
			result.stars,
			result.caught or 0,
			result.targetCount or 0,
			result.stars_awarded or 0
		)
	)
end

function ChallengeController.start(challengeId: string)
	RemoteDefs.event("StartChallenge"):FireServer(challengeId)
end

function ChallengeController.init()
	ResultScreen.init({
		onAgain = function()
			if lastEndedId then
				ChallengeController.start(lastEndedId)
			end
		end,
		onHome = function()
			RemoteDefs.event("GoHome"):FireServer()
		end,
		onStar = function()
			SfxController.play("correct")
		end,
	})

	RemoteDefs.event("ChallengeSpec").OnClientEvent:Connect(onSpec)
	RemoteDefs.event("ChallengeFeedback").OnClientEvent:Connect(onFeedback)
	RemoteDefs.event("ChallengeEnd").OnClientEvent:Connect(onEnd)

	Players.LocalPlayer.CharacterRemoving:Connect(cleanup)
end

return ChallengeController
