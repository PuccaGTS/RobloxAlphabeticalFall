--!nonstrict
--[[
	Клиентская часть «Ягодной поляны». Правила — Challenges/BerryCount на сервере.

	В центре поляны корзинка, вокруг кусты. На части кустов висят ягоды. Ребёнок
	подбегает к кусту — ягода срывается и летит за ним над головой: сколько ягод
	несёт, столько и видно. Подбежал к корзинке — ягоды отправились на проверку.
	Столько, сколько надо, — ягоды падают в корзинку, искры, следующее задание.
	Не столько — ягоды возвращаются на кусты, задание звучит снова.

	Цифр на экране нет: вместо счётчика — сами ягоды над головой и в строке
	наверху. Пример («2 + 1») показывается только на ступенях сложения
	и вычитания, где его и так пишут на воротах.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)

local HUD = require(script.Parent.Parent.UI.HUD)

local BerryController = {}

local FOLDER_NAME = "AlphabetFall_Berries"
local PICK_DISTANCE = 4.5
local BASKET_DISTANCE = 6
local BERRY_SIZE = 1.5
local SPOTS = 16
local SPOT_RADIUS = { 15, 22 } -- как в Challenges/BerryCount.spot

local BERRY = Color3.fromRGB(220, 50, 70)
local LEAF = Color3.fromRGB(90, 160, 80)
local BUSH = Color3.fromRGB(110, 175, 100)
local WICKER = Color3.fromRGB(190, 140, 80)

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local currentRound = 1
local blockedUntil = 0
local waitingBasket = false
local heartbeat: RBXScriptConnection? = nil

-- Ягоды раунда: деталь, её место на кусте и сорвана ли.
local berries: { [number]: { part: BasePart, home: CFrame, carried: boolean } } = {}
local carried: { number } = {}
local basketTop: CFrame = CFrame.new()
local inBasket: { BasePart } = {}

local function stageOf(from: any): CFrame?
	local stage = from and from.params and from.params.stage
	return if typeof(stage) == "CFrame" then stage else nil
end

local function resolveOrigin(from: any): CFrame
	local stage = stageOf(from)
	if stage then
		return stage
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		end
		local base = root.Position + flat.Unit * 26 - Vector3.new(0, 3, 0)
		return CFrame.lookAt(base, base + flat.Unit)
	end
	return CFrame.new(0, 0, 0)
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
	p.CanQuery = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function spot(index: number): Vector3
	local ring = if index <= SPOTS / 2 then 1 else 2
	local inRing = SPOTS / 2
	local order = (index - 1) % inRing
	local angle = (order + (ring - 1) * 0.5) / inRing * math.pi * 2
	local radius = SPOT_RADIUS[ring]
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Ягоды одной строкой: цифр нет, есть сами ягоды.
local function berryLine(count: number): string
	return string.rep("🍓", count)
end

local function refreshHud()
	if not spec then
		return
	end
	local round = spec.params.rounds[currentRound]
	local prompt = round and round.prompt or ""
	local line = berryLine(#carried)
	local text = if prompt ~= "" then `{prompt}   {line}` else line
	HUD.showTarget(if text ~= "" then text else nil, currentRound - 1, #spec.params.rounds)
end

local function berryPart(name: string, cframe: CFrame): BasePart
	local berry = part(name, Vector3.one * BERRY_SIZE, cframe, BERRY, Enum.PartType.Ball)
	berry.Material = Enum.Material.Glass
	local leaf =
		part(`{name}_Leaf`, Vector3.new(0.9, 0.2, 0.5), cframe * CFrame.new(0, BERRY_SIZE / 2, 0), LEAF)
	leaf.Parent = berry
	return berry
end

local function buildField()
	-- Корзинка в центре: к ней несут ягоды.
	local basket = part(
		"Basket",
		Vector3.new(3, 6, 6),
		origin * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		WICKER,
		Enum.PartType.Cylinder
	)
	basket.Material = Enum.Material.WoodPlanks
	basket.CanCollide = true
	local rim = part(
		"BasketRim",
		Vector3.new(0.5, 6.8, 6.8),
		origin * CFrame.new(0, 3.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(150, 105, 60),
		Enum.PartType.Cylinder
	)
	rim.Material = Enum.Material.WoodPlanks
	for _, side in { -1, 1 } do
		part(
			`BasketHandle_{side}`,
			Vector3.new(0.5, 4, 0.5),
			origin * CFrame.new(side * 2.8, 5, 0),
			Color3.fromRGB(150, 105, 60)
		)
	end
	part(
		"BasketHandleTop",
		Vector3.new(6.1, 0.5, 0.5),
		origin * CFrame.new(0, 7, 0),
		Color3.fromRGB(150, 105, 60)
	)
	basketTop = origin * CFrame.new(0, 3.4, 0)

	-- Кусты на всех местах: на части из них ягоды, остальные ждут своего раунда.
	for index = 1, SPOTS do
		local at = spot(index)
		local bush = part(
			`Bush_{index}`,
			Vector3.new(4.5, 3.6, 4.5),
			origin * CFrame.new(at.X, 1.8, -at.Z),
			BUSH,
			Enum.PartType.Ball
		)
		bush.Material = Enum.Material.Grass
	end
end

local function clearBasket()
	for _, berry in inBasket do
		berry:Destroy()
	end
	table.clear(inBasket)
end

-- Ягоды, которые уже лежат в корзинке: для «доложи до пяти».
local function fillBasket(count: number)
	clearBasket()
	for index = 1, count do
		local angle = index / math.max(count, 1) * math.pi * 2
		local berry = berryPart(
			`Given_{index}`,
			basketTop * CFrame.new(math.cos(angle) * 1.4, 0, math.sin(angle) * 1.4)
		)
		table.insert(inBasket, berry)
	end
end

local function clearBerries()
	for _, berry in berries do
		berry.part:Destroy()
	end
	table.clear(berries)
	table.clear(carried)
end

local function showRound(index: number)
	clearBerries()
	waitingBasket = false
	if not spec or not folder then
		return
	end
	local round = spec.params.rounds[index]
	if not round then
		return
	end

	fillBasket(round.given or 0)
	for _, item in round.berries do
		local home = origin * CFrame.new(item.x, 4, -item.z)
		berries[item.index] = { part = berryPart(`Berry_{item.index}`, home), home = home, carried = false }
	end

	HUD.toast(
		if (round.given or 0) > 0
			then "Доложи ягод в корзинку!"
			elseif round.prompt ~= "" then "Посчитай и собери столько ягод!"
			else "Собери ягоды и неси в корзинку!",
		4
	)
	refreshHud()
end

local function onHeartbeat()
	if not spec then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local now = os.clock()
	local blocked = now < blockedUntil
	local bob = math.sin(now * 3) * 0.2

	-- Несомые ягоды летят столбиком над головой: сколько несёшь — видно сразу.
	for order, index in carried do
		local berry = berries[index]
		if berry then
			local target =
				CFrame.new(root.Position + Vector3.new(0, 3.5 + order * (BERRY_SIZE + 0.1) + bob, 0))
			berry.part.CFrame = berry.part.CFrame:Lerp(target, 0.35)
		end
	end

	if blocked or waitingBasket then
		return
	end

	for index, berry in berries do
		if not berry.carried and (berry.home.Position - root.Position).Magnitude <= PICK_DISTANCE then
			berry.carried = true
			table.insert(carried, index)
			RemoteDefs.event("ChallengeAction")
				:FireServer({ kind = "pick", round = currentRound, berry = index })
			refreshHud()
		end
	end

	if #carried > 0 and (basketTop.Position - root.Position).Magnitude <= BASKET_DISTANCE then
		waitingBasket = true
		RemoteDefs.event("ChallengeAction"):FireServer({ kind = "basket", round = currentRound })
		-- Если сервер ответ не принял (опоздание), через пару секунд можно снова.
		task.delay(2.5, function()
			waitingBasket = false
		end)
	end
end

function BerryController.start(newSpec: any)
	BerryController.stop()
	spec = newSpec
	currentRound = 1
	blockedUntil = 0
	origin = resolveOrigin(newSpec)

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	buildField()
	showRound(1)
	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
end

function BerryController.feedback(fb: any)
	if not spec then
		return
	end
	local round = spec.params.rounds[fb.sectionIndex or currentRound]
	if not round then
		return
	end

	if fb.correct then
		-- Ягоды падают в корзинку, из неё летят искры.
		for order, index in carried do
			local berry = berries[index]
			if berry then
				local angle = order / math.max(#carried, 1) * math.pi * 2
				TweenService:Create(
					berry.part,
					TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = basketTop * CFrame.new(math.cos(angle) * 0.8, 0.8, math.sin(angle) * 0.8) }
				):Play()
			end
		end
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Rate = 0
		sparkles.Speed = NumberRange.new(6, 12)
		sparkles.Lifetime = NumberRange.new(0.6, 1.2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Color = ColorSequence.new(BERRY)
		local anchor = part("BasketSparkles", Vector3.one * 0.5, basketTop, BERRY)
		anchor.Transparency = 1
		sparkles.Parent = anchor
		sparkles:Emit(40)

		table.clear(carried)
		currentRound = round.index + 1
		task.delay(1.8, function()
			if spec then
				clearBasket()
				showRound(currentRound)
			end
		end)
		return
	end

	-- Не столько: ягоды возвращаются на кусты, можно собрать заново.
	blockedUntil = os.clock() + (fb.cooldown or 0)
	HUD.toast("Посчитаем ещё раз!", 2)
	for _, index in carried do
		local berry = berries[index]
		if berry then
			berry.carried = false
			TweenService
				:Create(berry.part, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = berry.home })
				:Play()
		end
	end
	table.clear(carried)
	waitingBasket = false
	refreshHud()
end

function BerryController.stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	clearBerries()
	clearBasket()
	if folder then
		folder:Destroy()
		folder = nil
	end
	spec = nil
	blockedUntil = 0
	currentRound = 1
	waitingBasket = false
end

return BerryController
