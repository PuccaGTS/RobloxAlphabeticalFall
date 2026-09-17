--!nonstrict
--[[
	Клиентская часть «Зеркала». Правила — Challenges/Mirror на сервере.

	Перед ребёнком ряд табличек с одной и той же буквой: одна написана правильно,
	остальные перевёрнуты, лежат на боку или отражены. Голос называет букву,
	ребёнок выбирает правильную табличку. Букву-цель на экран не выводим:
	показать правильное начертание — значит отменить задание.

	Интерфейс Roblox поворачивает текст, но не отражает его, поэтому буквы на
	табличках нарисованы штрихами (Logic/StrokeGlyphs): отражение и поворот —
	это формула над точками. Все таблички раунда рисуются одинаково, иначе
	«неправильную» можно было бы найти по другому шрифту, а не по начертанию.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)
local StrokeGlyphs = require(Shared.Logic.StrokeGlyphs)

local Glyph = require(script.Parent.Parent.UI.Glyph)
local HUD = require(script.Parent.Parent.UI.HUD)

local MirrorController = {}

local FOLDER_NAME = "AlphabetFall_Mirror"
local CARD_SIZE = Vector3.new(5, 5, 0.8)
local CARD_STEP = 6.2
local DISTANCE = 13

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local currentRound = 1
local blockedUntil = 0
local cards: { BasePart } = {}

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
		-- Таблички смотрят на ребёнка, поэтому сцена развёрнута к входу.
		return stage * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, math.pi, 0)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		end
		local base = root.Position + flat.Unit * DISTANCE + Vector3.new(0, 1.5, 0)
		-- Лицом к ребёнку: таблички смотрят на него, а не от него.
		return CFrame.lookAt(base, base - flat.Unit)
	end
	return CFrame.new(0, 4, 0)
end

local function clearCards()
	for _, card in cards do
		card:Destroy()
	end
	cards = {}
end

local function showRound(index: number)
	clearCards()
	if not spec or not folder then
		return
	end
	local round = spec.params.rounds[index]
	if not round then
		return
	end

	HUD.showTarget(nil, index - 1, #spec.params.rounds)

	for slot, variant in round.variants do
		local card = Instance.new("Part")
		card.Name = `MirrorCard_{slot}`
		card.Size = CARD_SIZE
		card.CFrame = origin * CFrame.new((slot - (#round.variants + 1) / 2) * CARD_STEP, 0, 0)
		card.Color = Color3.fromRGB(250, 248, 240)
		card.Material = Enum.Material.SmoothPlastic
		card.Anchored = true
		card.CanCollide = false
		card.Parent = folder

		if StrokeGlyphs.has(round.letterId) then
			local strokes = StrokeGlyphs.strokes(round.letterId, variant.mirrored, variant.rotation)
			Glyph.attachStrokes(card, strokes, 0.85, round.color)
		else
			-- Запасной путь для буквы без штрихов: повернуть можно, отразить нет.
			local billboard = Glyph.attach(card, variant.glyph, 0.85, round.color)
			local label = billboard:FindFirstChild("Glyph")
			if label and label:IsA("TextLabel") then
				label.Rotation = variant.rotation
			end
		end

		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 200
		click.Parent = card
		click.MouseClick:Connect(function()
			if not spec or os.clock() < blockedUntil then
				return
			end
			RemoteDefs.event("ChallengeAction"):FireServer({ round = index, slot = slot })
		end)

		table.insert(cards, card)
	end
end

function MirrorController.start(newSpec: any)
	MirrorController.stop()
	spec = newSpec
	currentRound = 1
	blockedUntil = 0
	origin = resolveOrigin(newSpec)

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	showRound(1)
end

function MirrorController.feedback(fb: any)
	if not spec then
		return
	end

	if fb.correct then
		-- Правильная табличка вспыхивает, остальные гаснут, потом следующий раунд.
		for _, card in cards do
			TweenService:Create(card, TweenInfo.new(0.25), { Transparency = 0.8 }):Play()
			Glyph.setTransparency(card, 0.8)
		end
		currentRound = (fb.sectionIndex or currentRound) + 1
		task.delay(0.9, function()
			if spec then
				showRound(currentRound)
			end
		end)
	else
		-- Промах не убирает выбор: таблички остаются, после паузы можно снова.
		blockedUntil = os.clock() + (fb.cooldown or 0)
		for _, card in cards do
			card.Transparency = 0.6
		end
		task.delay(fb.cooldown or 0, function()
			for _, card in cards do
				if card.Parent then
					card.Transparency = 0
				end
			end
		end)
	end
end

function MirrorController.stop()
	clearCards()
	if folder then
		folder:Destroy()
		folder = nil
	end
	spec = nil
	blockedUntil = 0
	currentRound = 1
end

return MirrorController
