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
local RemoteDefs = require(Shared.Net.RemoteDefs)

local AudioController = require(script.Parent.AudioController)
local HUD = require(script.Parent.Parent.UI.HUD)

local ChallengeController = {}

local LANE_WIDTH = 5
local LETTER_SIZE = Vector3.new(4, 4, 0.6)
local FOLDER_NAME = "AlphabetFall_Challenge"

local player = Players.LocalPlayer

local spec: any = nil
local startedAt = 0
local folder: Folder? = nil
local parts: { [number]: BasePart } = {}
local spawned: { [number]: boolean } = {}
local origin: CFrame = CFrame.new()
local heartbeat: RBXScriptConnection? = nil

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
	HUD.showTarget(nil)
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
		return root.CFrame * CFrame.new(0, 0, -14)
	end

	return CFrame.new(0, 0, 0)
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

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(200, 200)
	surface.AlwaysOnTop = false
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = letter.glyph
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = surface

	-- ClickDetector сам работает и мышью, и тапом — отдельный код для тача не нужен.
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 200
	click.Parent = part

	click.MouseClick:Connect(function()
		if not spec then
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

	local elapsed = os.clock() - startedAt
	local params = spec.params

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
		end
	end
end

local function onSpec(newSpec: any)
	cleanup()

	spec = newSpec
	startedAt = os.clock()
	origin = resolveOrigin()

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	HUD.showTarget(spec.params.targetGlyph, 0, spec.targetCount)

	-- Звук буквы-цели: сначала ребёнок слышит, что ловить, и только потом видит текст.
	task.delay(0.6, function()
		if spec then
			AudioController.speak(spec.params.targetVO)
		end
	end)

	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
end

local function onFeedback(feedback: any)
	local part = parts[feedback.itemIndex]
	if part then
		parts[feedback.itemIndex] = nil
		popPart(part, feedback.correct)
	end

	HUD.showTarget(spec and spec.params.targetGlyph or nil, feedback.caught, feedback.targetCount)

	-- Промах: называем букву, по которой ребёнок попал, потом снова цель.
	-- «Это П. А нам нужна М» — так ошибка становится подсказкой, а не наказанием.
	if not feedback.correct and feedback.tappedLetterId then
		local tapped = Letters.get(feedback.tappedLetterId)
		if tapped then
			task.delay(0.5, function()
				AudioController.speak(tapped.vo.sound)
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
	RemoteDefs.event("ChallengeSpec").OnClientEvent:Connect(onSpec)
	RemoteDefs.event("ChallengeFeedback").OnClientEvent:Connect(onFeedback)
	RemoteDefs.event("ChallengeEnd").OnClientEvent:Connect(onEnd)

	Players.LocalPlayer.CharacterRemoving:Connect(cleanup)
end

return ChallengeController
