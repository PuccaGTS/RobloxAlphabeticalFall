--!nonstrict
--[[
	Клиентская часть «Весов». Правила — Challenges/Scales на сервере.

	Перед ребёнком весы: на одной чаше камни, другая пустая, и весы наклонены
	в сторону тяжёлой. Ближе к ребёнку — кучки камней. Коснулся кучки — сервер
	решает, верно ли, и камни ложатся на пустую чашу: весы выравниваются или
	качаются в сторону тяжёлой. Цифр нигде нет — только камни, их надо сосчитать.

	Весы собраны из закреплённых деталей и двигаются подменой CFrame, без физики:
	детская игра на дешёвом планшете (docs/07-TECH-ARCH.md § 8), и ничего здесь
	не должно падать, катиться или толкать ребёнка.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)

local HUD = require(script.Parent.Parent.UI.HUD)

local ScalesController = {}

local FOLDER_NAME = "AlphabetFall_Scales"
--[[
	Весы на своей поляне крупные: на площади их сцену закрывали порталы,
	и на первой проверке её назвали примитивной. Теперь это главный предмет
	«Двора Весов» — на постаменте, с цепями и золотым шаром, а камни
	в кучках разного цвета, и видно, какая кучка легла на чашу.
]]
local DISTANCE = 16
local PODIUM = 2 -- высота каменного постамента
local BEAM_HEIGHT = 12 -- от земли до оси
local ARM = 8 -- от оси весов до чаши
local HANG = 4 -- на сколько чаша висит ниже коромысла
local PAN_SIZE = 6.5
local PILE_STEP = 8
local PILE_FORWARD = 11 -- кучки ближе к ребёнку, чем весы
local STONE_SIZE = 1.3
local TILT_PER_STONE = math.rad(5)
local MAX_TILT = math.rad(20)

local STONE_COLOR = Color3.fromRGB(150, 145, 140)
local GIVEN_COLOR = Color3.fromRGB(130, 170, 215)
local PILE_COLORS = {
	Color3.fromRGB(240, 150, 150),
	Color3.fromRGB(150, 205, 140),
	Color3.fromRGB(245, 200, 110),
	Color3.fromRGB(190, 150, 225),
}
local WOOD = Color3.fromRGB(170, 120, 75)
local BRASS = Color3.fromRGB(215, 175, 90)
local MARBLE = Color3.fromRGB(235, 230, 225)

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local currentRound = 1
local blockedUntil = 0

-- Детали, которые двигаются вместе с коромыслом.
local beam: BasePart? = nil
local pans: { [string]: BasePart } = {}
local panStones: { [string]: { BasePart } } = { given = {}, chosen = {} }
local piles: { Instance } = {}
local tilt: NumberValue? = nil
local chains: { [string]: BasePart } = {}
local axle: BasePart? = nil

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
		-- Весы стоят лицом к ребёнку: кучки камней должны быть ближе к нему.
		return stage * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.pi, 0)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		end
		local base = root.Position + flat.Unit * DISTANCE + Vector3.new(0, -2.5, 0)
		-- Лицом к ребёнку: локальная -Z смотрит на него.
		return CFrame.lookAt(base, base - flat.Unit)
	end
	return CFrame.new(0, 2, 0)
end

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

--[[
	Раскладка камней рядами по четыре: десять камней — три ряда, их видно
	сразу и пересчитать можно пальцем. Смещения — в плоскости поверхности.
]]
local function stoneOffsets(count: number): { Vector3 }
	local offsets = {}
	local perRow = 4
	local rows = math.ceil(count / perRow)
	for index = 1, count do
		local row = math.floor((index - 1) / perRow)
		local inRow = math.min(perRow, count - row * perRow)
		local column = (index - 1) % perRow
		local x = (column - (inRow - 1) / 2) * STONE_SIZE * 1.15
		local z = (row - (rows - 1) / 2) * STONE_SIZE * 1.15
		table.insert(offsets, Vector3.new(x, STONE_SIZE / 2 + 0.2, z))
	end
	return offsets
end

local function placeStones(surface: CFrame, count: number, list: { BasePart }, color: Color3?)
	for _, offset in stoneOffsets(count) do
		local stone = part(
			"Stone",
			Vector3.one * STONE_SIZE,
			surface * CFrame.new(offset),
			color or STONE_COLOR,
			Enum.PartType.Ball
		)
		stone.Material = Enum.Material.Pebble
		table.insert(list, stone)
	end
end

local function clearStones(list: { BasePart })
	for _, stone in list do
		stone:Destroy()
	end
	table.clear(list)
end

local function pivot(): CFrame
	return origin * CFrame.new(0, BEAM_HEIGHT, 0)
end

-- Чаша на конце коромысла: висит отвесно, как бы ни было наклонено коромысло.
local function panFrame(side: number, angle: number): CFrame
	local tip = (pivot() * CFrame.Angles(0, 0, angle) * CFrame.new(side * ARM, 0, 0)).Position
	return CFrame.new(tip - Vector3.new(0, HANG, 0)) * origin.Rotation
end

local lastPans: { [string]: CFrame } = {}

-- Ставит коромысло на угол angle и тянет за ним чаши вместе с камнями.
local function layout(angle: number)
	if not beam then
		return
	end
	beam.CFrame = pivot() * CFrame.Angles(0, 0, angle)
	for key, side in { given = 1, chosen = -1 } do
		local frame = panFrame(side, angle)
		local pan = pans[key]
		if pan then
			pan.CFrame = frame * CFrame.Angles(0, 0, math.rad(90))
		end
		-- Цепь от конца коромысла до чаши: чаша висит, а не парит.
		local chain = chains[key]
		if chain then
			local tip = (pivot() * CFrame.Angles(0, 0, angle) * CFrame.new(side * ARM, 0, 0)).Position
			local bottom = frame.Position
			chain.Size = Vector3.new(0.2, (tip - bottom).Magnitude, 0.2)
			chain.CFrame = CFrame.new((tip + bottom) / 2) * origin.Rotation
		end
		local previous = lastPans[key]
		if previous then
			local shift = frame * previous:Inverse()
			for _, stone in panStones[key] do
				stone.CFrame = shift * stone.CFrame
			end
		end
		lastPans[key] = frame
	end
end

-- Правая чаша тяжелее — её конец опускается.
local function angleFor(given: number, chosen: number): number
	return math.clamp((chosen - given) * TILT_PER_STONE, -MAX_TILT, MAX_TILT)
end

local swing: Tween? = nil

local function stopSwing()
	if swing then
		swing:Cancel()
		swing = nil
	end
end

-- Качнуть весы к углу: Back-сглаживание даёт тот самый «качнулись и замерли».
local function swingTo(angle: number, seconds: number)
	if not tilt then
		return
	end
	stopSwing()
	swing = TweenService:Create(
		tilt,
		TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = angle }
	)
	swing:Play()
end

local function buildScales()
	-- Постамент в два яруса: весы стоят на месте, а не на траве.
	local lower = part(
		"PodiumLower",
		Vector3.new(PODIUM / 2, 11, 11),
		origin * CFrame.new(0, PODIUM / 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		MARBLE,
		Enum.PartType.Cylinder
	)
	lower.Material = Enum.Material.Marble
	lower.CanCollide = true
	local upper = part(
		"PodiumUpper",
		Vector3.new(PODIUM / 2, 7, 7),
		origin * CFrame.new(0, PODIUM * 3 / 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		MARBLE,
		Enum.PartType.Cylinder
	)
	upper.Material = Enum.Material.Marble
	upper.CanCollide = true

	local postHeight = BEAM_HEIGHT - PODIUM
	part("Post", Vector3.new(1, postHeight, 1), origin * CFrame.new(0, PODIUM + postHeight / 2, 0), WOOD)
	-- Кольца на столбе: он резной, а не палка.
	for ring = 1, 3 do
		part(
			`PostRing_{ring}`,
			Vector3.new(0.4, 1.6, 1.6),
			origin * CFrame.new(0, PODIUM + ring * postHeight / 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
			BRASS,
			Enum.PartType.Cylinder
		)
	end
	axle = part("Axle", Vector3.one * 1.4, pivot(), BRASS, Enum.PartType.Ball)
	local finial =
		part("Finial", Vector3.one * 1.6, pivot() * CFrame.new(0, 1.6, 0), BRASS, Enum.PartType.Ball)
	finial.Material = Enum.Material.Neon

	beam = part("Beam", Vector3.new(ARM * 2 + 1, 0.6, 0.7), pivot(), BRASS)
	for _, key in { "given", "chosen" } do
		local pan =
			part("Pan", Vector3.new(0.4, PAN_SIZE, PAN_SIZE), CFrame.new(), BRASS, Enum.PartType.Cylinder)
		pan.Material = Enum.Material.Metal
		pans[key] = pan
		chains[key] = part("Chain", Vector3.new(0.2, HANG, 0.2), CFrame.new(), Color3.fromRGB(120, 110, 90))
	end

	local value = Instance.new("NumberValue")
	value.Parent = folder
	value.Changed:Connect(layout)
	tilt = value
	lastPans = {}
	layout(0)
end

local function clearPiles()
	for _, pile in piles do
		pile:Destroy()
	end
	table.clear(piles)
end

local function showRound(index: number)
	clearPiles()
	clearStones(panStones.given)
	clearStones(panStones.chosen)
	if not spec or not folder or not tilt then
		return
	end
	local round = spec.params.rounds[index]
	if not round then
		return
	end

	HUD.showTarget(nil, index - 1, #spec.params.rounds)

	-- Камни задания кладутся на ровную чашу, и весы сразу клонятся к ним.
	stopSwing()
	tilt.Value = 0
	lastPans = {}
	layout(0)
	placeStones(panFrame(1, 0), round.left, panStones.given, GIVEN_COLOR)
	swingTo(angleFor(round.left, 0), 0.8)

	for slot, count in round.choices do
		local surface = origin * CFrame.new((slot - (#round.choices + 1) / 2) * PILE_STEP, 0.4, -PILE_FORWARD)
		local board = part("Pile", Vector3.new(6, 0.5, 6), surface, WOOD)
		board.Material = Enum.Material.WoodPlanks
		table.insert(piles, board)
		-- Бортики ящика: кучка лежит в корзинке, а не рассыпана по доске.
		for _, rim in { { 0, 2.8, 6, 0.4 }, { 0, -2.8, 6, 0.4 }, { 2.8, 0, 0.4, 6 }, { -2.8, 0, 0.4, 6 } } do
			local edge = part(
				"PileRim",
				Vector3.new(rim[3], 0.9, rim[4]),
				surface * CFrame.new(rim[1], 0.45, rim[2]),
				Color3.fromRGB(140, 95, 55)
			)
			edge.Parent = board
		end
		local stones: { BasePart } = {}
		placeStones(surface, count, stones, PILE_COLORS[(slot - 1) % #PILE_COLORS + 1])
		for _, stone in stones do
			stone.Parent = board
		end

		-- Касаются кучки, а не отдельного камня: мишень крупная, по ней не промахнуться.
		local hitbox = part("PileHitbox", Vector3.new(6.5, 4, 6.5), surface * CFrame.new(0, 1.8, 0), WOOD)
		hitbox.Transparency = 1
		hitbox.Parent = board
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 200
		click.Parent = hitbox
		click.MouseClick:Connect(function()
			if not spec or os.clock() < blockedUntil or currentRound ~= index then
				return
			end
			RemoteDefs.event("ChallengeAction"):FireServer({ round = index, slot = slot })
		end)
	end
end

function ScalesController.start(newSpec: any)
	ScalesController.stop()
	spec = newSpec
	currentRound = 1
	blockedUntil = 0
	origin = resolveOrigin(newSpec)

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	buildScales()
	showRound(1)
end

function ScalesController.feedback(fb: any)
	if not spec then
		return
	end
	local round = spec.params.rounds[fb.sectionIndex or currentRound]
	if not round then
		return
	end

	local chosen = tonumber(fb.tappedValue) or 0
	-- Камни на чаше того же цвета, что и кучка: видно, какую из них выбрали.
	local slot = table.find(round.choices, chosen) or 1
	clearStones(panStones.chosen)
	placeStones(
		panFrame(-1, if tilt then tilt.Value else 0),
		chosen,
		panStones.chosen,
		PILE_COLORS[(slot - 1) % #PILE_COLORS + 1]
	)
	swingTo(angleFor(round.left, chosen), if fb.correct then 0.6 else 0.9)

	if fb.correct then
		HUD.toast(`{round.left} = {chosen}`, 2)
		-- Равновесие — праздник: искры от оси весов.
		if axle and axle.Parent then
			local burst = Instance.new("ParticleEmitter")
			burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			burst.Rate = 0
			burst.Speed = NumberRange.new(6, 12)
			burst.Lifetime = NumberRange.new(0.6, 1.2)
			burst.SpreadAngle = Vector2.new(180, 180)
			burst.Color = ColorSequence.new(BRASS)
			burst.Parent = axle
			burst:Emit(40)
		end
		currentRound = round.index + 1
		task.delay(1.6, function()
			if spec then
				showRound(currentRound)
			end
		end)
	else
		-- Весы качнулись и вернулись: камни снимаются, кучки остаются, можно снова.
		local cooldown = fb.cooldown or 0
		blockedUntil = os.clock() + cooldown
		task.delay(math.max(cooldown, 1), function()
			if spec and currentRound == round.index then
				clearStones(panStones.chosen)
				swingTo(angleFor(round.left, 0), 0.6)
			end
		end)
	end
end

function ScalesController.stop()
	stopSwing()
	clearPiles()
	clearStones(panStones.given)
	clearStones(panStones.chosen)
	if folder then
		folder:Destroy()
		folder = nil
	end
	beam = nil
	axle = nil
	pans = {}
	chains = {}
	tilt = nil
	lastPans = {}
	spec = nil
	blockedUntil = 0
	currentRound = 1
end

return ScalesController
