--!nonstrict
--[[
	Буквята в мире: строит и водит питомцев всех игроков вокруг.
	Кто за кем летает, решает сервер и пишет атрибутами игрока PetLetter и PetLetter2
	(Services/PetService); здесь только картинка, касание и титул Хранителя.

	Никакой физики (docs/07-TECH-ARCH.md § 8): буквёнок — анкерные детали,
	которые каждый кадр подтягиваются к месту за плечом хозяина. Не толкается,
	не падает в яму и не застревает в стене — у пятилетнего нет терпения
	ждать, пока питомец выберется из-за угла.

	Нажал на буквёнка — он называет свою букву. Любого, не только своего:
	подошёл к соседу, нажал на его буквёнка — услышал «Буква Ж». Это то самое
	постоянное фоновое повторение, ради которого буквята и придуманы.

	Пока арта нет, буквёнок собран из примитивов: шарик цвета буквы, глаза,
	буква над головой. Модель художника встанет сюда же (docs/10-CONTENT-PIPELINE.md).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)

local AudioController = require(script.Parent.AudioController)
local Glyph = require(script.Parent.Parent.UI.Glyph)

local PetController = {}

-- Слоты: первый буквёнок за правым плечом, второй (за 10 освоенных букв) — за левым.
local ATTRIBUTES = { "PetLetter", "PetLetter2" }
local KEEPER_ATTRIBUTE = "AlphabetKeeper"
local FOLDER_NAME = "AlphabetFallPets"
local BODY_SIZE = 2.2
-- Сбоку, чуть сзади и выше: голова не мешает камере.
local OFFSETS = { CFrame.new(2.6, 1.2, 2.4), CFrame.new(-2.6, 1.2, 2.4) }
local FOLLOW_SPEED = 6 -- чем больше, тем плотнее держится за хозяином
-- Хозяин телепортировался (портал, падение в туннеле) — буквёнок прыгает следом, а не летит через весь мир.
local SNAP_DISTANCE = 60

type Pet = {
	model: Model,
	body: BasePart,
	letterId: string,
}

local pets: { [Player]: { [number]: Pet } } = {}
local folder: Folder? = nil

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace
	folder = created
	return created
end

local function piece(model: Model, name: string, shape: Enum.PartType, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function build(letterId: string): Pet
	local letter = Letters.expect(letterId)

	local model = Instance.new("Model")
	model.Name = `Pet_{letterId}`

	local body = piece(model, "Body", Enum.PartType.Ball, Vector3.one * BODY_SIZE, letter.color)
	body.CanQuery = true -- только тело ловит касание
	model.PrimaryPart = body

	-- Глаза смотрят туда же, куда хозяин: -Z у Roblox — «вперёд».
	for _, side in { -1, 1 } do
		local eye = piece(model, `Eye_{side}`, Enum.PartType.Ball, Vector3.one * 0.55, Color3.new(1, 1, 1))
		eye:SetAttribute("Offset", CFrame.new(side * 0.42, 0.25, -0.85))
		local pupil =
			piece(model, `Pupil_{side}`, Enum.PartType.Ball, Vector3.one * 0.28, Color3.fromRGB(30, 30, 40))
		pupil:SetAttribute("Offset", CFrame.new(side * 0.42, 0.25, -1.08))
	end

	local tag = piece(model, "Tag", Enum.PartType.Block, Vector3.one * 0.1, letter.color)
	tag.Transparency = 1
	tag:SetAttribute("Offset", CFrame.new(0, BODY_SIZE * 0.95, 0))
	local label = Glyph.attach(tag, letter.glyph, 16)
	-- У букв испытаний надпись поверх всего, у буквёнка — нет: иначе буквы соседских
	-- питомцев висели бы сквозь стены по всей площади.
	label.AlwaysOnTop = false
	label.MaxDistance = 60

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = body
	click.MouseClick:Connect(function()
		AudioController.speak(letter.vo.name)
		-- Отклик на касание: буквёнок подпрыгивает, чтобы было видно — он услышал.
		local original = body.Size
		TweenService:Create(body, TweenInfo.new(0.12), { Size = original * 1.25 }):Play()
		task.delay(0.14, function()
			if body.Parent then
				TweenService:Create(body, TweenInfo.new(0.2), { Size = original }):Play()
			end
		end)
	end)

	model.Parent = container()
	return { model = model, body = body, letterId = letterId }
end

local function place(pet: Pet, at: CFrame)
	pet.body.CFrame = at
	for _, part in pet.model:GetChildren() do
		if part:IsA("BasePart") and part ~= pet.body then
			local offset = part:GetAttribute("Offset")
			if typeof(offset) == "CFrame" then
				part.CFrame = at * offset
			end
		end
	end
end

local function sync(player: Player, slot: number)
	local letterId = player:GetAttribute(ATTRIBUTES[slot])
	local slots = pets[player] or {}
	pets[player] = slots
	local current = slots[slot]

	if current and current.letterId == letterId then
		return
	end
	if current then
		current.model:Destroy()
		slots[slot] = nil
	end
	if typeof(letterId) == "string" and Letters.get(letterId) then
		slots[slot] = build(letterId)
	end
end

--[[
	Титул «Хранитель Азбуки» над головой — за все 33 освоенные буквы. Текст наш,
	а не введённый игроком, поэтому показывать его другим можно без фильтра
	(docs/11-COMPLIANCE.md § 2). Висит на голове персонажа и переживает перерождение.
]]
local TITLE_NAME = "AlphabetKeeperTitle"

local function syncTitle(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local existing = head:FindFirstChild(TITLE_NAME)
	local isKeeper = player:GetAttribute(KEEPER_ATTRIBUTE) == true
	if not isKeeper then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = TITLE_NAME
	billboard.Size = UDim2.fromOffset(220, 40)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "👑 Хранитель Азбуки"
	label.TextColor3 = Color3.fromRGB(255, 214, 102)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
	billboard.Parent = head
end

local function watch(player: Player)
	for slot, attribute in ATTRIBUTES do
		sync(player, slot)
		player:GetAttributeChangedSignal(attribute):Connect(function()
			sync(player, slot)
		end)
	end

	syncTitle(player)
	player:GetAttributeChangedSignal(KEEPER_ATTRIBUTE):Connect(function()
		syncTitle(player)
	end)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 10)
		syncTitle(player)
	end)
end

local function step(dt: number)
	local now = os.clock()
	local alpha = math.min(1, dt * FOLLOW_SPEED)

	for player, slots in pets do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		for slot, pet in slots do
			if root and root:IsA("BasePart") then
				-- Покачивание в воздухе: у каждого буквёнка своя фаза, чтобы соседи не качались хором.
				local bob = math.sin(now * 2.2 + player.UserId % 7 + slot * 1.7) * 0.3
				local goal = root.CFrame * OFFSETS[slot] * CFrame.new(0, bob, 0)
				local from = pet.body.CFrame
				local at = if (from.Position - goal.Position).Magnitude > SNAP_DISTANCE
					then goal
					else from:Lerp(goal, alpha)
				place(pet, at)
				if pet.model.Parent == nil then
					pet.model.Parent = container()
				end
			elseif pet.model.Parent ~= nil then
				-- Хозяин без персонажа (перерождается) — буквёнок прячется, а не висит в пустоте.
				pet.model.Parent = nil
			end
		end
	end
end

function PetController.init()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, pet in pets[player] or {} do
			pet.model:Destroy()
		end
		pets[player] = nil
	end)

	RunService.Heartbeat:Connect(step)
end

return PetController
