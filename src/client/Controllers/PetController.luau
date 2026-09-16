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

	Пока арта нет, буквёнок собран из примитивов — но это зверёк, а не шарик:
	у каждой буквы свой (котик, зайчик, мишка, птенчик, лягушонок), с животиком,
	щёчками, лапками и хвостиком. Моргает, машет крыльями, прыгает от касания
	и радуется верным ответам хозяина. Модель художника встанет сюда же
	(docs/10-CONTENT-PIPELINE.md).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Shop = require(Shared.Config.Shop)

local AudioController = require(script.Parent.AudioController)
local Glyph = require(script.Parent.Parent.UI.Glyph)

local PetController = {}

-- Слоты: первый буквёнок за правым плечом, второй (за 10 освоенных букв) — за левым.
local ATTRIBUTES = { "PetLetter", "PetLetter2" }
local KEEPER_ATTRIBUTE = "AlphabetKeeper"
-- Скин всех буквят игрока (Config/Shop, категория "petskin"); ставит сервер.
local SKIN_ATTRIBUTE = "PetSkin"
local RAINBOW_SPEED = 0.15 -- оборотов радуги в секунду: плавно, без мигания (docs/11 § 7)
local FOLDER_NAME = "AlphabetFallPets"
local BODY_SIZE = 2.2
-- Сбоку, чуть сзади и выше: голова не мешает камере.
local OFFSETS = { CFrame.new(2.6, 1.2, 2.4), CFrame.new(-2.6, 1.2, 2.4) }
local FOLLOW_SPEED = 6 -- чем больше, тем плотнее держится за хозяином
-- Хозяин телепортировался (портал, падение в туннеле) — буквёнок прыгает следом, а не летит через весь мир.
local SNAP_DISTANCE = 60
local HOP_SECONDS = 0.5
-- Радость за верный ответ: прыжок с оборотом и искры. Чуть дольше прыжка от касания.
local CHEER_SECONDS = 0.9
local BLINK_SECONDS = 0.13

type Pet = {
	model: Model,
	body: BasePart,
	letterId: string,
	skinId: string?,
	rainbow: boolean,
	hopUntil: number,
	blinkAt: number,
	cheerUntil: number?,
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

--[[
	Какой зверёк у буквы. Раньше буквёнок был шариком с глазами, и на площади
	все питомцы выглядели одинаково. Теперь у каждой буквы свой зверёк —
	по порядку в алфавите, чтобы у соседних букв зверьки были разные:
	котик, зайчик, мишка, птенчик, лягушонок. Буква над головой остаётся главной.
]]
local SPECIES = { "cat", "bunny", "bear", "bird", "frog" }

local function speciesOf(letterId: string): string
	local letter = Letters.expect(letterId)
	return SPECIES[(letter.order - 1) % #SPECIES + 1]
end

local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Деталь, которая следует за телом со смещением; tint — красится вместе с телом (радужный скин).
local function attached(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	offset: CFrame,
	tint: string?
): BasePart
	local part = piece(model, name, shape, size, color)
	part:SetAttribute("Offset", offset)
	if tint then
		part:SetAttribute("Tint", tint)
	end
	return part
end

local function build(letterId: string, skinId: string?): Pet
	local letter = Letters.expect(letterId)
	local item = if skinId then Shop.get(skinId) else nil
	local skin = if item and item.category == "petskin" then item.skin else nil
	local species = speciesOf(letterId)
	local r = BODY_SIZE / 2

	local model = Instance.new("Model")
	model.Name = `Pet_{letterId}`

	-- Без скина тело цвета буквы; со скином — наряд скина, а цвет буквы остаётся у надписи.
	local body = piece(model, "Body", Enum.PartType.Ball, Vector3.one * BODY_SIZE, letter.color)
	if skin then
		body.Color = skin.color
		body.Material = skin.material
		body.Transparency = skin.transparency or 0
	end
	body.CanQuery = true -- только тело ловит касание
	model.PrimaryPart = body
	local coat = body.Color

	-- Животик светлее тела, щёчки розовые: из шарика получается мордочка.
	attached(
		model,
		"Belly",
		Enum.PartType.Ball,
		Vector3.new(1.3, 1.2, 0.5),
		lighter(coat, 0.55),
		CFrame.new(0, -0.35, -r + 0.12),
		"light"
	)
	for _, side in { -1, 1 } do
		attached(
			model,
			`Cheek_{side}`,
			Enum.PartType.Ball,
			Vector3.new(0.35, 0.25, 0.1),
			Color3.fromRGB(255, 160, 175),
			CFrame.new(side * 0.68, -0.05, -r + 0.22)
		)
	end

	-- Глаза смотрят туда же, куда хозяин: -Z у Roblox — «вперёд». Блик делает взгляд живым.
	local eyeY = if species == "frog" then 0.75 else 0.25
	local eyeSize = if species == "frog" then 0.7 else 0.55
	for _, side in { -1, 1 } do
		local eye = attached(
			model,
			`Eye_{side}`,
			Enum.PartType.Ball,
			Vector3.one * eyeSize,
			Color3.new(1, 1, 1),
			CFrame.new(side * 0.42, eyeY, -r + 0.25)
		)
		eye:SetAttribute("Blink", true)
		local pupil = attached(
			model,
			`Pupil_{side}`,
			Enum.PartType.Ball,
			Vector3.one * (eyeSize * 0.5),
			Color3.fromRGB(30, 30, 40),
			CFrame.new(side * 0.42, eyeY, -r - 0.02)
		)
		pupil:SetAttribute("Blink", true)
		local shine = attached(
			model,
			`Shine_{side}`,
			Enum.PartType.Ball,
			Vector3.one * 0.1,
			Color3.new(1, 1, 1),
			CFrame.new(side * 0.36, eyeY + 0.08, -r - 0.12)
		)
		shine.Material = Enum.Material.Neon
		shine:SetAttribute("Blink", true)
	end

	-- Лапки снизу и хвостик сзади — у всех, кроме птенчика: у того крылья.
	if species ~= "bird" then
		for _, side in { -1, 1 } do
			attached(
				model,
				`Foot_{side}`,
				Enum.PartType.Ball,
				Vector3.new(0.55, 0.35, 0.7),
				darker(coat, 0.15),
				CFrame.new(side * 0.45, -r + 0.05, -0.2),
				"dark"
			)
		end
		attached(
			model,
			"Tail",
			Enum.PartType.Ball,
			Vector3.one * 0.55,
			lighter(coat, 0.3),
			CFrame.new(0, -0.3, r),
			"light"
		)
	end

	if species == "cat" then
		for _, side in { -1, 1 } do
			local ear = Instance.new("WedgePart")
			ear.Name = `Ear_{side}`
			ear.Size = Vector3.new(0.25, 0.7, 0.6)
			ear.Color = coat
			ear.Anchored = true
			ear.CanCollide = false
			ear.CanTouch = false
			ear.CanQuery = false
			ear.CastShadow = false
			ear.Parent = model
			ear:SetAttribute(
				"Offset",
				CFrame.new(side * 0.55, r - 0.05, 0) * CFrame.Angles(0, 0, side * -0.3)
			)
			ear:SetAttribute("Tint", "body")
		end
		for _, side in { -1, 1 } do
			for whisker = -1, 1, 2 do
				attached(
					model,
					`Whisker_{side}_{whisker}`,
					Enum.PartType.Block,
					Vector3.new(0.5, 0.04, 0.04),
					Color3.fromRGB(60, 50, 50),
					CFrame.new(side * 0.95, -0.12 + whisker * 0.08, -r + 0.3)
						* CFrame.Angles(0, 0, whisker * side * 0.25)
				)
			end
		end
	elseif species == "bunny" then
		for _, side in { -1, 1 } do
			local ear = attached(
				model,
				`Ear_{side}`,
				Enum.PartType.Ball,
				Vector3.new(0.4, 1.3, 0.3),
				coat,
				CFrame.new(side * 0.35, r + 0.45, 0.1) * CFrame.Angles(0, 0, side * -0.15),
				"body"
			)
			ear:SetAttribute("Wiggle", side)
			attached(
				model,
				`EarInner_{side}`,
				Enum.PartType.Ball,
				Vector3.new(0.2, 0.9, 0.1),
				Color3.fromRGB(255, 190, 200),
				CFrame.new(side * 0.35, r + 0.45, -0.02) * CFrame.Angles(0, 0, side * -0.15)
			)
		end
	elseif species == "bear" then
		for _, side in { -1, 1 } do
			attached(
				model,
				`Ear_{side}`,
				Enum.PartType.Ball,
				Vector3.new(0.6, 0.6, 0.35),
				coat,
				CFrame.new(side * 0.72, r - 0.12, 0),
				"body"
			)
			attached(
				model,
				`EarInner_{side}`,
				Enum.PartType.Ball,
				Vector3.new(0.3, 0.3, 0.1),
				lighter(coat, 0.5),
				CFrame.new(side * 0.72, r - 0.12, -0.15),
				"light"
			)
		end
		attached(
			model,
			"Snout",
			Enum.PartType.Ball,
			Vector3.new(0.6, 0.4, 0.3),
			lighter(coat, 0.6),
			CFrame.new(0, -0.05, -r - 0.02),
			"light"
		)
		attached(
			model,
			"Nose",
			Enum.PartType.Ball,
			Vector3.one * 0.18,
			Color3.fromRGB(40, 30, 30),
			CFrame.new(0, 0.05, -r - 0.15)
		)
	elseif species == "bird" then
		attached(
			model,
			"Beak",
			Enum.PartType.Ball,
			Vector3.new(0.35, 0.25, 0.45),
			Color3.fromRGB(255, 170, 60),
			CFrame.new(0, -0.05, -r - 0.1)
		)
		for _, side in { -1, 1 } do
			local wing = attached(
				model,
				`Wing_{side}`,
				Enum.PartType.Ball,
				Vector3.new(0.3, 0.9, 1.1),
				darker(coat, 0.1),
				CFrame.new(side * (r + 0.05), 0, 0.1),
				"dark"
			)
			wing:SetAttribute("Flap", side)
		end
		attached(
			model,
			"Crest",
			Enum.PartType.Ball,
			Vector3.new(0.2, 0.5, 0.2),
			darker(coat, 0.1),
			CFrame.new(0, r + 0.15, 0) * CFrame.Angles(-0.4, 0, 0),
			"dark"
		)
	elseif species == "frog" then
		attached(
			model,
			"Smile",
			Enum.PartType.Block,
			Vector3.new(0.7, 0.06, 0.06),
			Color3.fromRGB(60, 40, 40),
			CFrame.new(0, -0.1, -r + 0.02)
		)
	end

	local tag = piece(model, "Tag", Enum.PartType.Block, Vector3.one * 0.1, letter.color)
	tag.Transparency = 1
	tag:SetAttribute("Offset", CFrame.new(0, BODY_SIZE * 1.15, 0))
	local label = Glyph.attach(tag, letter.glyph, 16)
	-- У букв испытаний надпись поверх всего, у буквёнка — нет: иначе буквы соседских
	-- питомцев висели бы сквозь стены по всей площади.
	label.AlwaysOnTop = false
	label.MaxDistance = 60

	local pet: Pet = {
		model = model,
		body = body,
		letterId = letterId,
		skinId = if skin then skinId else nil,
		rainbow = skin ~= nil and skin.rainbow == true,
		hopUntil = 0,
		blinkAt = os.clock() + 2 + math.random() * 3,
	}

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = body
	click.MouseClick:Connect(function()
		AudioController.speak(letter.vo.name)
		-- Отклик на касание: буквёнок подпрыгивает, чтобы было видно — он услышал.
		pet.hopUntil = os.clock() + HOP_SECONDS
	end)

	model.Parent = container()
	return pet
end

local function place(pet: Pet, at: CFrame)
	local now = os.clock()
	pet.body.CFrame = at

	-- Моргание: глаза на миг пропадают, и через несколько секунд снова.
	local blinking = now >= pet.blinkAt and now < pet.blinkAt + BLINK_SECONDS
	if now >= pet.blinkAt + BLINK_SECONDS then
		pet.blinkAt = now + 2.5 + math.random() * 3
	end

	for _, part in pet.model:GetChildren() do
		if part:IsA("BasePart") and part ~= pet.body then
			local offset = part:GetAttribute("Offset")
			if typeof(offset) == "CFrame" then
				local flap = part:GetAttribute("Flap")
				local wiggle = part:GetAttribute("Wiggle")
				if typeof(flap) == "number" then
					offset = offset * CFrame.Angles(0, 0, flap * math.sin(now * 12) * 0.6)
				elseif typeof(wiggle) == "number" then
					offset = offset * CFrame.Angles(0, 0, wiggle * math.sin(now * 3) * 0.15)
				end
				part.CFrame = at * offset
			end
			if part:GetAttribute("Blink") then
				part.LocalTransparencyModifier = if blinking then 1 else 0
			end
		end
	end
end

-- Радужный скин перекрашивает не только тело, но и уши, лапки, хвост и животик.
local function tint(pet: Pet, color: Color3)
	pet.body.Color = color
	for _, part in pet.model:GetChildren() do
		local kind = part:GetAttribute("Tint")
		if part:IsA("BasePart") and kind then
			part.Color = if kind == "light"
				then lighter(color, if part.Name == "Belly" then 0.55 else 0.3)
				elseif kind == "dark" then darker(color, 0.15)
				else color
		end
	end
end

--[[
	Буквята хозяина радуются верному ответу: прыгают с оборотом, из них летят
	искры. Вызывается у своего игрока — радость видит тот, кто ответил.
]]
function PetController.cheer()
	local slots = pets[Players.LocalPlayer]
	if not slots then
		return
	end
	for _, pet in slots do
		pet.cheerUntil = os.clock() + CHEER_SECONDS
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Rate = 0
		sparkles.Speed = NumberRange.new(4, 8)
		sparkles.Lifetime = NumberRange.new(0.5, 0.9)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Color = ColorSequence.new(pet.body.Color)
		sparkles.Parent = pet.body
		sparkles:Emit(18)
		task.delay(1.2, function()
			sparkles:Destroy()
		end)
	end
end

local function sync(player: Player, slot: number)
	local letterId = player:GetAttribute(ATTRIBUTES[slot])
	local rawSkin = player:GetAttribute(SKIN_ATTRIBUTE)
	local skinId = if typeof(rawSkin) == "string" then rawSkin else nil
	local slots = pets[player] or {}
	pets[player] = slots
	local current = slots[slot]

	if current and current.letterId == letterId and current.skinId == skinId then
		return
	end
	local at = if current then current.body.CFrame else nil
	if current then
		current.model:Destroy()
		slots[slot] = nil
	end
	if typeof(letterId) == "string" and Letters.get(letterId) then
		local pet = build(letterId, skinId)
		-- Сменили наряд — буквёнок остаётся на месте, а не прилетает издалека.
		if at then
			place(pet, at)
		end
		slots[slot] = pet
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
	player:GetAttributeChangedSignal(SKIN_ATTRIBUTE):Connect(function()
		for slot in ATTRIBUTES do
			sync(player, slot)
		end
	end)

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
				-- Прыжок от касания и радость за ответ: вверх-вниз, у радости ещё и оборот.
				if now < pet.hopUntil then
					local progress = 1 - (pet.hopUntil - now) / HOP_SECONDS
					goal *= CFrame.new(0, math.sin(progress * math.pi) * 1.2, 0)
				end
				if pet.cheerUntil and now < pet.cheerUntil then
					local progress = 1 - (pet.cheerUntil - now) / CHEER_SECONDS
					goal *= CFrame.new(0, math.sin(progress * math.pi) * 2.2, 0) * CFrame.Angles(
						0,
						progress * math.pi * 2,
						0
					)
				end
				local from = pet.body.CFrame
				local at = if (from.Position - goal.Position).Magnitude > SNAP_DISTANCE
					then goal
					else from:Lerp(goal, alpha)
				place(pet, at)
				if pet.rainbow then
					tint(pet, Color3.fromHSV((now * RAINBOW_SPEED + slot * 0.25) % 1, 0.6, 1))
				end
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
