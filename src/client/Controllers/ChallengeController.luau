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
local ScalesController = require(script.Parent.ScalesController)
local HUD = require(script.Parent.Parent.UI.HUD)
local ResultScreen = require(script.Parent.Parent.UI.ResultScreen)
local Glyph = require(script.Parent.Parent.UI.Glyph)

local ChallengeController = {}

local LANE_WIDTH = 6
local LETTER_SIZE = Vector3.new(5.5, 5.5, 1)
local FOLDER_NAME = "AlphabetFall_Challenge"

local player = Players.LocalPlayer

local spec: any = nil
local startedAt = 0
local folder: Folder? = nil
local parts: { [number]: BasePart } = {}
local spawned: { [number]: boolean } = {}
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
local function resolveOrigin(): CFrame
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

-- Задник: без него буквы висят в пустоте и не читаются на фоне неба.
local function buildBackdrop(parent: Instance, height: number)
	local backdrop = Instance.new("Part")
	backdrop.Name = "Backdrop"
	backdrop.Size = Vector3.new(LANE_WIDTH * 6, height + 8, 1)
	backdrop.CFrame = origin * CFrame.new(0, height / 2, 3)
	backdrop.Color = Color3.fromRGB(74, 86, 130)
	backdrop.Transparency = 0.25
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanQuery = false
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Parent = parent

	local corner = Instance.new("SpecialMesh")
	corner.MeshType = Enum.MeshType.Brick
	corner.Parent = backdrop
end

local function laneOffset(lane: number, lanes: number): number
	return (lane - (lanes + 1) / 2) * LANE_WIDTH
end

local function makeLetterPart(item: any): BasePart
	local letter = Letters.expect(item.letterId)

	local part = Instance.new("Part")
	part.Name = `Letter_{item.index}`
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
		if not spec then
			return
		end
		-- Пока идёт пауза после промаха, тапы не отправляем: сервер их всё равно
		-- не примет, а ребёнку важно услышать подсказку, а не «дотыкать» вслепую.
		if os.clock() < blockedUntil then
			return
		end
		RemoteDefs.event("ChallengeAction"):FireServer({ itemIndex = item.index })
	end)

	return part
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
end

local function onHeartbeat()
	if not spec or not folder then
		return
	end

	local now = os.clock()
	local elapsed = now - startedAt
	local params = spec.params
	local blocked = now < blockedUntil

	for _, item in params.items do
		if not spawned[item.index] and elapsed >= item.spawnAt then
			spawned[item.index] = true
			local part = makeLetterPart(item)
			part.Parent = folder
			parts[item.index] = part
		end
	end

	for index, part in parts do
		local item = params.items[index]
		local fallen = (elapsed - item.spawnAt) * params.fallSpeed
		local height = params.fallHeight - fallen

		if height <= 0 then
			part:Destroy()
			parts[index] = nil
		else
			part.CFrame = origin
				* CFrame.new(laneOffset(item.lane, params.lanes), height, 0)
				* CFrame.Angles(0, 0, math.sin(elapsed * 2 + index) * 0.15)

			-- Пауза после промаха видна глазами: буквы притушены и не ловятся.
			part.Transparency = if blocked then 0.65 else 0
			Glyph.setTransparency(part, if blocked then 0.7 else 0)
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
end

local function onSpec(newSpec: any)
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

	--[[
		Забеги рисует сервер: ворота, стены и препятствия — настоящая геометрия мира,
		а не клиентские декорации. Клиенту остаётся только показать, что искать.
	]]
	if newSpec.challengeId == "tunnel_run" or newSpec.challengeId == "obstacle_course" then
		activeChallengeId = newSpec.challengeId
		activeTargetGlyph = newSpec.params.targetGlyph
		HUD.showTarget(newSpec.params.targetGlyph, 0, newSpec.targetCount)
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
	origin = resolveOrigin()

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	buildBackdrop(container, spec.params.fallHeight)
	HUD.showTarget(spec.params.targetGlyph, 0, spec.targetCount)
	-- Пока нет озвучки, задание должно быть сказано хотя бы текстом,
	-- иначе непонятно, что вообще происходит и что от тебя хотят.
	HUD.toast(`Лови букву {spec.params.targetGlyph}`, 3)

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

	if activeChallengeId == "tunnel_run" or activeChallengeId == "obstacle_course" then
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
